/// Sends one file's event through the Matrix SDK and keeps its
/// [AttachmentSend] up to date: the transaction id is ours, so the app
/// knows which pending event is which, and the stages the SDK does not
/// publish are read from its own pending event. Its uploads report to it
/// through a zone value around the SDK's send ([runForUpload]), so it
/// shows the real count and the wait for the server. A failure is caught
/// here and shown on the message, never left as an unhandled error.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/mime.dart';
import 'package:rooster/utils/network/upload_progress.dart';

/// A file to send that the composer follows (its [send]).
class TrackedMatrixAttachment extends MatrixProcessedAttachment {
  TrackedMatrixAttachment(super.file, this.send, {super.thumbnailFile});

  final AttachmentSend send;
}

/// Sends [attachment] in [room] under a new transaction id. Never throws:
/// the result is the event's id, or null when the file did not reach the
/// room (its pending event then says so).
Future<String?> sendMatrixFile(
  matrix.Room room,
  MatrixProcessedAttachment attachment, {
  String? threadRootEventId,
  String? threadLastEventId,
  Map<String, dynamic>? extraContent,
}) async {
  final send = attachment is TrackedMatrixAttachment ? attachment.send : null;
  final txid = room.client.generateUniqueTransactionId();
  if (send != null) {
    final file = attachment.file;
    final thumbnailBytes = attachment.thumbnailFile?.bytes.length;
    send.trace?.handedOver(
      bytes: file.bytes.length,
      thumbnailBytes: thumbnailBytes,
      width: file.info['w'] as int?,
      height: file.info['h'] as int?,
    );
    // Encryption keeps the size (AES-CTR): these are the bytes uploaded.
    send.handedOver(txid,
        bytes: file.bytes.length,
        uploadBytes: file.bytes.length + (thumbnailBytes ?? 0));
  }
  return _follow(
      room,
      send,
      txid,
      () => room.sendFileEvent(attachment.file,
          txid: txid,
          threadLastEventId: threadLastEventId,
          threadRootEventId: threadRootEventId,
          extraContent: extraContent,
          thumbnail: attachment.thumbnailFile));
}

/// "Retry" on [event], a file that failed, which [send] follows when it is
/// known: its stage goes back to uploading, and the SDK sends it again
/// (`Event.sendAgain`) under the same transaction id. Its parts that went
/// up are not uploaded again, and when all did (the event has their
/// address) only the event is sent. Never throws, like [sendMatrixFile].
Future<String?> retryMatrixFile(matrix.Event event, AttachmentSend? send) {
  if (send != null) {
    send.retrying();
    final kept = event.room.sendingFileUploads[event.eventId]?.values;
    send.upload.partsKept(kept?.fold<int>(0, (sum, p) => sum + p.bytes) ?? 0);
  }
  return _follow(event.room, send, event.eventId, event.sendAgain);
}

/// Whether [event], a file message, already has its upload's address: the
/// `url`, or the encrypted file's `file` in an encrypted room.
bool isUploadedFileEvent(matrix.Event event) =>
    event.content['url'] is String || event.content['file'] is Map;

/// Runs [sendFile], the SDK's send of the file under [txid], keeping
/// [send]'s stage: the SDK shows its pending event as soon as it has the
/// file, and shows it again with the upload's address once uploaded,
/// before the event is sent.
Future<String?> _follow(matrix.Room room, AttachmentSend? send, String txid,
    Future<String?> Function() sendFile) async {
  StreamSubscription<matrix.Event>? pending;
  if (send != null) {
    pending = room.client.onTimelineEvent.stream.listen((event) {
      if (event.roomId != room.id || event.eventId != txid) return;
      send.echo();
      if (event.fileSendingStatus == matrix.FileSendingStatus.encrypting) {
        send.encryptingFile();
      }
      if (event.content['url'] is String || event.content['file'] is Map) {
        send.uploaded();
      }
    });
  }

  try {
    final trace = send?.trace;
    Future<String?> traced() => trace == null || trace.span.isFinished
        ? sendFile()
        : trace.run(sendFile);
    final id =
        await (send == null ? traced() : runForUpload(send.upload, traced));
    if (id == null) {
      send?.failed();
    } else {
      send?.sent();
    }
    return id;
  } catch (error, stack) {
    // The upload or the event failed for good: the SDK marked its pending
    // event as failed, and the message shows it.
    Log.onError(error, stack, content: "Could not send a file");
    send?.failed();
    return null;
  } finally {
    await pending?.cancel();
  }
}

/// The file of [event] while it is still being sent from this device, as
/// the SDK keeps it ([matrix.Room.sendingFilePlaceholders]): what a pending
/// event shows instead of downloading anything. Null for any other event.
Attachment? localPendingAttachment(matrix.Event event) {
  if (!event.status.isSending && !event.status.isError) return null;
  final room = event.room;
  final file = room.sendingFilePlaceholders[event.eventId];
  if (file == null) return null;
  final mimeType = file.mimeType;
  final name = file.name;
  final width = (file.info['w'] as num?)?.toDouble();
  final height = (file.info['h'] as num?)?.toDouble();
  final provider = MemoryFileProvider(file.bytes, name);

  if (Mime.imageTypes.contains(mimeType)) {
    return ImageAttachment(localPicture(file.bytes), provider,
        name: name,
        mimeType: mimeType,
        fileSize: file.size,
        width: width,
        height: height);
  }
  if (Mime.videoTypes.contains(mimeType)) {
    final poster = room.sendingFileThumbnails[event.eventId];
    return PendingVideoAttachment(provider,
        poster: poster == null ? null : localPicture(poster.bytes),
        name: name,
        mimeType: mimeType,
        fileSize: file.size,
        width: width,
        height: height);
  }
  return FileAttachment(provider,
      name: name, mimeType: mimeType, fileSize: file.size);
}

/// A file held in memory: a pending message's own file.
class MemoryFileProvider implements FileProvider {
  MemoryFileProvider(this.bytes, this.name);

  final Uint8List bytes;
  final String name;

  @override
  String get fileIdentifier => "memory:${identityHashCode(bytes)}";

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) => File(filepath).writeAsBytes(bytes);

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => bytes;
}
