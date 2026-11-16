/// Sends one file's event through the Matrix SDK and keeps its
/// [AttachmentSend] up to date: the transaction id is ours, so the app
/// knows which pending event is which, and the stages the SDK does not
/// publish are read from its own pending event. A failure is caught here
/// and shown on the message, never left as an unhandled error.
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
  StreamSubscription<matrix.Event>? pending;
  if (send != null) {
    final file = attachment.file;
    send.trace?.handedOver(
      bytes: file.bytes.length,
      thumbnailBytes: attachment.thumbnailFile?.bytes.length,
      width: file.info['w'] as int?,
      height: file.info['h'] as int?,
    );
    send.handedOver(txid);
    // The SDK shows its pending event as soon as it has the file, and shows
    // it again with the upload's address once uploaded, before the event
    // is sent.
    pending = room.client.onTimelineEvent.stream.listen((event) {
      if (event.roomId != room.id || event.eventId != txid) return;
      send.echo();
      if (event.content['url'] is String || event.content['file'] is Map) {
        send.uploaded();
      }
    });
  }

  Future<String?> sendFile() => room.sendFileEvent(attachment.file,
      txid: txid,
      threadLastEventId: threadLastEventId,
      threadRootEventId: threadRootEventId,
      extraContent: extraContent,
      thumbnail: attachment.thumbnailFile);

  try {
    final trace = send?.trace;
    final id = await (trace == null ? sendFile() : trace.run(sendFile));
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
