/// Photos sent as GIFs are (`reserved_media.dart`): the event leaves at
/// Send, with mxcs reserved for the photo and its thumbnail and the
/// photo's size and blurhash, and the two go up after it, the thumbnail
/// first. Until they are up the sent message shows the upload's stage,
/// count and clock, and "Cancel send" stops the uploads and takes the
/// message back (redacts it). An upload that fails for good does the same,
/// and leaves a failed message of this device only, with the photo held in
/// memory, whose "Retry" sends a new event under a new transaction id, to
/// new reservations.
///
/// The uploads are the SDK's upload loop of any file message
/// (`file_upload_loop.dart`: its new attempts, its four uploads at once,
/// its cancel), each part run in a zone that sends it to its reserved mxc
/// (`runUploadToReserved`). In an encrypted room the photo and its
/// thumbnail are encrypted before the event leaves (`file_cipher.dart`, a
/// new key and iv for every attempt), and only that is uploaded.
///
/// A homeserver that gives no reservation (no such endpoint, too many
/// pending, any error) gets the photo the usual way, upload first
/// ([sendMatrixFile]), with nothing shown to the user. So does every other
/// file.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/file_cipher.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/client/matrix/media/reserved_media.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/network/upload_progress.dart';

/// The most mxcs one account holds reserved for photos and not uploaded
/// yet. Synapse refuses a sixth (`max_pending_media_uploads`, 5 by
/// default): a photo that would go over this is sent upload first instead
/// of asking.
const maxOpenPhotoReservations = 4;

/// What one account knows of its homeserver's reservations for photos,
/// and how many are open.
class _PhotoReservations extends MediaReservations {
  int open = 0;
}

final _reservations = Expando<_PhotoReservations>('photo reservations');

/// The ones [client] holds, made on first use.
_PhotoReservations _reservationsOf(matrix.Client client) =>
    _reservations[client] ??= _PhotoReservations();

/// [count] mxcs for a photo (the file's, then its thumbnail's), or null to
/// upload first: one refused, or [maxOpenPhotoReservations] would be
/// passed. Each is asked for once the one before it was granted, so a
/// refusal leaves none of the photo's waiting on the homeserver, and a
/// homeserver without reservations is asked once per photo at most. Those
/// granted count as open until [_release].
Future<List<Uri>?> _reserve(matrix.Client client, int count) async {
  final reservations = _reservationsOf(client);
  if (reservations.unsupported ||
      reservations.open + count > maxOpenPhotoReservations) {
    return null;
  }
  // Taken before asking: photos sent together count each other.
  reservations.open += count;
  final granted = <Uri>[];
  for (var i = 0; i < count; i++) {
    final mxc = await reservations.reserve(client, what: "a photo");
    if (mxc == null) {
      // One granted before this refusal expires unused on the homeserver.
      reservations.open -= count;
      return null;
    }
    granted.add(mxc);
  }
  return granted;
}

void _release(matrix.Client client, int count) {
  final reservations = _reservationsOf(client);
  reservations.open = math.max(0, reservations.open - count);
}

/// The photos of each account sent by asynchronous upload, by the ids
/// their messages show under: the transaction id of the attempt whose
/// uploads run (also on its sent event, as `transaction_id`), and the id of
/// the failed message left after one failed.
final _sends = Expando<Map<String, AsyncPhotoSend>>('async photo sends');

Map<String, AsyncPhotoSend> _sendsOf(matrix.Client client) =>
    _sends[client] ??= {};

/// The photo of [room] being sent by asynchronous upload whose message is
/// [id] (a transaction id or a failed message's id), or null.
AsyncPhotoSend? asyncPhotoSendOf(matrix.Room room, String id) {
  final send = _sends[room.client]?[id];
  return send?.room == room ? send : null;
}

/// [event]'s photo send, looked up by its transaction id first: a sent
/// event's id is the server's, its transaction id ours.
AsyncPhotoSend? asyncPhotoSendOfEvent(matrix.Event event) {
  final txid = event.transactionId;
  return (txid == null ? null : asyncPhotoSendOf(event.room, txid)) ??
      asyncPhotoSendOf(event.room, event.eventId);
}

/// The photo messages of each account whose upload failed and that could
/// not be taken back: in the room, pointing at media that never came. By
/// transaction id and event id.
final _leftInRoom = Expando<Set<String>>('photo messages left in the room');

/// [ids] (a photo message's transaction id and event id) are of a photo
/// message whose upload failed and that is still in the room.
void markPhotoLeftInRoom(matrix.Client client, Iterable<String> ids) =>
    (_leftInRoom[client] ??= {}).addAll(ids);

/// Whether [event] is one of this device's photo messages whose upload
/// failed and that is still in the room (its redaction failed): its sender
/// is told so under it.
bool isPhotoLeftInRoom(matrix.Event event) {
  final left = _leftInRoom[event.room.client];
  if (left == null) return false;
  final txid = event.transactionId;
  return left.contains(event.eventId) || (txid != null && left.contains(txid));
}

/// Whether [attachment] goes by asynchronous upload when the homeserver
/// reserves: a photo held in memory (`m.image`; a file read from disk is
/// encrypted anew at each attempt, so its key is not known before) sent
/// from the composer, whose send ([TrackedMatrixAttachment.send]) shows
/// the upload under the sent message with "Cancel send". Any other photo
/// (a photo album's) goes upload first: nothing would show it uploading.
bool sendsByAsyncUpload(MatrixProcessedAttachment attachment) {
  final file = attachment.file;
  return attachment is TrackedMatrixAttachment &&
      file.msgType == matrix.MessageTypes.Image &&
      file.source == null &&
      file.bytes.isNotEmpty;
}

/// Sends [attachment] in [room]: a photo by asynchronous upload
/// ([AsyncPhotoSend]), any other file upload first ([sendMatrixFile]).
/// Never throws: the result is the event's id, or null when the file did
/// not reach the room (its message then says so).
Future<String?> sendMatrixAttachment(
  matrix.Room room,
  MatrixProcessedAttachment attachment, {
  String? threadRootEventId,
  String? threadLastEventId,
  Map<String, dynamic>? extraContent,
}) {
  if (!sendsByAsyncUpload(attachment)) {
    return sendMatrixFile(room, attachment,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId,
        extraContent: extraContent);
  }
  return AsyncPhotoSend(room, attachment,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
          extraContent: extraContent)
      .start();
}

/// What a photo's message says while it is sent by asynchronous upload.
enum AsyncPhotoState {
  /// Its mxcs are being reserved, or its event sent: an unsent message.
  sending,

  /// Its event was sent and the photo goes up: "Cancel send" stops it.
  uploading,

  /// Uploaded: the message is whole.
  done,

  /// It failed for good, or was cancelled: the message was taken back, and
  /// a failed message of this device holds the photo for "Retry".
  failed,

  /// Taken back after "Cancel send": nothing is left.
  cancelled,
}

/// One photo sent by asynchronous upload, across its attempts ("Retry"
/// after a failure starts a new one, under a new transaction id).
class AsyncPhotoSend extends ChangeNotifier {
  AsyncPhotoSend(this.room, this.attachment,
      {this.threadRootEventId, this.threadLastEventId, this.extraContent});

  final matrix.Room room;
  final MatrixProcessedAttachment attachment;
  final String? threadRootEventId;
  final String? threadLastEventId;
  final Map<String, dynamic>? extraContent;

  /// The composer's send that follows this photo, when it came from there:
  /// the same object for every attempt, so its count and clock carry over
  /// from the transaction id to the event's id.
  AttachmentSend? get send {
    final attachment = this.attachment;
    return attachment is TrackedMatrixAttachment ? attachment.send : null;
  }

  matrix.MatrixFile get _file => attachment.file;
  matrix.MatrixImageFile? get _thumbnail => attachment.thumbnailFile;

  AsyncPhotoState _state = AsyncPhotoState.sending;
  AsyncPhotoState get state => _state;

  /// The current attempt's transaction id.
  String? transactionId;

  /// The current attempt's event, once the server took it.
  String? eventId;

  /// The failed message this device shows after the last attempt failed.
  String? failedMessageId;

  /// Its event was sent and its uploads run: "Cancel send" stops them.
  bool get uploading => _state == AsyncPhotoState.uploading;

  /// The attempt in flight, and its end.
  Completer<String?>? _attempt;

  void _set(AsyncPhotoState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  /// Sends the photo: the result is the event's id once the photo is up,
  /// or null when it did not reach the room. Never throws.
  Future<String?> start() async {
    final attempt = _attempt = Completer<String?>();
    try {
      attempt.complete(await _send());
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not send a photo");
      attempt.complete(null);
    }
    return attempt.future;
  }

  /// "Cancel send" while its uploads run: they stop (the request in flight
  /// is aborted) and the message is taken back. Ends when it is.
  Future<void> cancel() async {
    final txid = transactionId;
    if (!uploading || txid == null) return;
    room.cancelSending(txid);
    await _attempt?.future;
  }

  /// "Retry" on its failed message: that message goes, and the photo is
  /// sent again, by a new event under a new transaction id.
  Future<String?> retry() async {
    if (_state != AsyncPhotoState.failed) return null;
    _forgetFailedMessage();
    final failed = failedMessageId;
    failedMessageId = null;
    if (failed != null) await room.dropUnsentEvent(failed);
    send?.retrying();
    _set(AsyncPhotoState.sending);
    return start();
  }

  /// Its failed message was dismissed ("Cancel" on it): nothing is kept.
  Future<void> dismiss() async {
    _forgetFailedMessage();
    final send = this.send;
    if (send != null) AttachmentSends.instance.remove(send);
  }

  void _forgetFailedMessage() {
    final failed = failedMessageId;
    if (failed != null) _sendsOf(room.client).remove(failed);
  }

  /// Runs [body] in the composer's span, so its requests are timed there.
  Future<T> _traced<T>(Future<T> Function() body) {
    final trace = send?.trace;
    return trace == null || trace.span.isFinished ? body() : trace.run(body);
  }

  Future<String?> _send() async {
    final client = room.client;
    final file = _file;
    final thumbnail = _thumbnail;
    final send = this.send;
    final txid = transactionId = client.generateUniqueTransactionId();
    eventId = null;
    final sends = _sendsOf(client)..[txid] = this;

    final thumbnailBytes = thumbnail?.bytes.length;
    if (send != null) {
      send.trace?.handedOver(
        bytes: file.size,
        thumbnailBytes: thumbnailBytes,
        width: file.info['w'] as int?,
        height: file.info['h'] as int?,
      );
      // Encryption keeps the size (AES-CTR): these are the bytes uploaded.
      send.handedOver(txid,
          bytes: file.size, uploadBytes: file.size + (thumbnailBytes ?? 0));
    }

    // Shown at once, as the SDK shows a file it sends; cancellable as one
    // until its event's request leaves.
    await room.showFileMessage(txid, file,
        thumbnail: thumbnail,
        extraContent: extraContent,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId);
    send?.echo();

    // In an encrypted room, encrypted while its mxcs are reserved, and
    // before the event: it carries the key and the hash of the bytes that
    // go up. Decided once, as the SDK does.
    final encrypt = room.encrypted && client.fileEncryptionEnabled;
    if (encrypt) send?.encryptingFile();
    final encryption = encrypt
        ? Future.wait([
            encryptPhotoPart(file.bytes),
            if (thumbnail != null) encryptPhotoPart(thumbnail.bytes),
          ])
        : null;

    final parts = thumbnail == null ? 1 : 2;
    final mxcs = await _traced(() => _reserve(client, parts));
    if (room.isSendCancelled(txid) || mxcs == null) encryption?.ignore();
    if (room.isSendCancelled(txid)) {
      if (mxcs != null) _release(client, parts);
      return _cancelledBeforeEvent(txid);
    }
    if (mxcs == null) {
      sends.remove(txid);
      send?.trace?.uploadPath(async: false);
      return sendMatrixFile(room, attachment,
          txid: txid,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
          extraContent: extraContent);
    }
    send?.trace?.uploadPath(async: true);

    var released = false;
    void release() {
      if (released) return;
      released = true;
      _release(client, parts);
    }

    try {
      return await _sendReserved(txid, mxcs, release,
          encrypt: encrypt, encryption: await encryption);
    } finally {
      release();
    }
  }

  /// Cancelled before its event left: the message is taken away (as any
  /// unsent message, `Event.cancelSend`, which did it already).
  Future<String?> _cancelledBeforeEvent(String txid) async {
    room.sendingQueueEventsByTxId.remove(txid);
    await room.dropUnsentEvent(txid);
    _sendsOf(room.client).remove(txid);
    send?.trace?.finish(ok: false, cancelled: true);
    send?.failed();
    _set(AsyncPhotoState.cancelled);
    return null;
  }

  Future<String?> _sendReserved(
      String txid, List<Uri> mxcs, void Function() release,
      {required bool encrypt,
      required List<matrix.EncryptedFile>? encryption}) async {
    final client = room.client;
    final file = _file;
    final thumbnail = _thumbnail;
    final send = this.send;
    final fileMxc = mxcs.first;
    final thumbnailMxc = thumbnail == null ? null : mxcs.last;
    final encryptedFile = encryption?.first;
    final encryptedThumbnail = thumbnail == null ? null : encryption?.last;
    if (room.isSendCancelled(txid)) return _cancelledBeforeEvent(txid);

    final content = photoEventContent(
      file,
      fileMxc,
      thumbnail: thumbnail,
      thumbnailMxc: thumbnailMxc,
      encryptedFile: encryptedFile,
      encryptedThumbnail: encryptedThumbnail,
      extraContent: extraContent,
    );

    // While it goes up the timeline shows the photo from memory; it goes
    // into the account's own media only once it is up, so a send the app's
    // closing cuts short leaves no picture the others never get.
    final files = {
      fileMxc.toString(): file.bytes,
      if (thumbnail != null && thumbnailMxc != null)
        thumbnailMxc.toString(): thumbnail.bytes,
    };
    holdUploadingMedia(client, files);
    try {
      final String? id;
      try {
        id = await _traced(() => room.sendEvent(content,
            txid: txid,
            threadRootEventId: threadRootEventId,
            threadLastEventId: threadLastEventId,
            // Refused if the room encrypts files by the time it goes.
            uploadedInTheClear: !encrypt));
      } catch (error, stack) {
        Log.onError(error, stack, content: "Could not send a photo's event");
        return _failed(txid, null);
      }
      if (id == null) {
        // Cancelled before its request left: the SDK took it away.
        if (room.isSendCancelled(txid)) return _cancelledBeforeEvent(txid);
        return _failed(txid, null);
      }

      eventId = id;
      room.uploadsAfterEvent(txid);
      send?.trace?.eventSent();
      _set(AsyncPhotoState.uploading);
      // In the database before any byte goes up: an opening after the app
      // closed during the upload takes the message back.
      await photoUploadStarted(room, txid, id);

      try {
        Future<void> upload(Uri mxc, matrix.FileSendPart part,
                matrix.MatrixFile clear, matrix.EncryptedFile? encrypted) =>
            matrix.runUploadToReserved(
                mxc,
                () => matrix.uploadFileParts(
                      room,
                      txid,
                      {
                        part: matrix.FilePartSend(null,
                            encrypted?.toMatrixFile() ?? clear, encrypted),
                      },
                      encrypted: encrypt,
                    ));
        Future<void> uploads() => Future.wait([
              // The thumbnail first: the others see a picture sooner.
              if (thumbnail != null && thumbnailMxc != null)
                upload(thumbnailMxc, matrix.FileSendPart.thumbnail, thumbnail,
                    encryptedThumbnail),
              upload(fileMxc, matrix.FileSendPart.file, file, encryptedFile),
            ], eagerError: false);
        await _traced(() =>
            send == null ? uploads() : runForUpload(send.upload, uploads));
      } catch (error, stack) {
        room.uploadsAfterEventEnded(txid);
        release();
        if (error is matrix.SendCancelledException ||
            room.isSendCancelled(txid)) {
          return _cancelledAfterEvent(txid, id);
        }
        final retryAfterMs =
            error is matrix.MatrixException ? error.retryAfterMs : null;
        if (retryAfterMs != null) {
          send?.upload.serverAskedToWait(
              client.sendClock.now().add(Duration(milliseconds: retryAfterMs)));
        }
        Log.onError(error, stack, content: "Could not upload a photo");
        return _failed(txid, id);
      }

      room.uploadsAfterEventEnded(txid);
      release();
      await keepUploadedMedia(client, files);
      await photoUploadEnded(client, txid);
      _sendsOf(client).remove(txid);
      room.forgetFileSend(txid);
      _set(AsyncPhotoState.done);
      send?.sent();
      return id;
    } finally {
      releaseUploadingMedia(client, files.keys);
    }
  }

  /// Takes the sent message [id] back: true when the server took the
  /// redaction.
  Future<bool> _takeBack(String id) async {
    try {
      await room.redactEvent(id);
      return true;
    } catch (error, stack) {
      Log.onError(error, stack,
          content: "Could not take back a photo whose upload ended");
      return false;
    }
  }

  /// "Cancel send" during the uploads: the message is taken back. When it
  /// cannot be, its sender is told, as after a failure.
  Future<String?> _cancelledAfterEvent(String txid, String id) async {
    final client = room.client;
    send?.trace?.finish(ok: false, cancelled: true);
    if (await _takeBack(id)) {
      await photoUploadEnded(client, txid);
      _sendsOf(client).remove(txid);
      room.forgetFileSend(txid);
      _set(AsyncPhotoState.cancelled);
      final send = this.send;
      if (send != null) AttachmentSends.instance.remove(send);
      return null;
    }
    return _failed(txid, id, takenBack: false);
  }

  /// The attempt [txid] failed for good: its sent message [id] is taken
  /// back (when it was sent), and a failed message of this device holds
  /// the photo for "Retry". The send was not cancelled.
  Future<String?> _failed(String txid, String? id, {bool? takenBack}) async {
    final client = room.client;
    final sends = _sendsOf(client)..remove(txid);
    final left = id != null && !(takenBack ?? await _takeBack(id));
    if (left) {
      // Still in the room: its sender is told under it.
      markPhotoLeftInRoom(client, [txid, id]);
      notifyListeners();
    }
    // An unsent event that failed: gone, the failed message stands for it.
    if (id == null) await room.dropUnsentEvent(txid);
    room.forgetFileSend(txid);

    final failed = failedMessageId = client.generateUniqueTransactionId();
    sends[failed] = this;
    send?.failed();
    _set(AsyncPhotoState.failed);
    await room.showFileMessage(failed, _file,
        thumbnail: _thumbnail,
        failed: true,
        extraContent: extraContent,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId);
    // Off the list of uploads the next opening settles, unless its message
    // is still in the room: that opening tries to take it back again.
    if (id != null) {
      await photoUploadEnded(client, txid,
          failedMessageId: left ? failed : null);
    }
    return null;
  }
}

/// [clear] encrypted for an upload, as the Matrix spec has attachments
/// encrypted: a new key and iv ([FileCipher.random]), and the SHA-256 of
/// what goes up. A copy: [clear] stays as it is. In pieces, with a pause
/// between them, so a large photo never holds the UI thread long (the web
/// has no isolate for it).
Future<matrix.EncryptedFile> encryptPhotoPart(Uint8List clear) async {
  const piece = 256 * 1024;
  final cipher = FileCipher.random();
  final data = Uint8List.fromList(clear);
  for (var at = 0; at < data.length; at += piece) {
    if (at > 0) await Future<void>.delayed(Duration.zero);
    cipher.encrypt(
        Uint8List.sublistView(data, at, math.min(at + piece, data.length)));
  }
  return matrix.EncryptedFile(
    data: data,
    k: cipher.keyText,
    iv: cipher.ivText,
    sha256: FileCipher.unpadded(base64.encode(cipher.finish())),
  );
}

/// The event of [file] sent before its upload: as the SDK writes a file
/// message (`Room.sendFileEvent`), with the reserved [fileMxc] and
/// [thumbnailMxc] in place of the uploads' addresses, and in an encrypted
/// room their keys and hashes ([encryptedFile], [encryptedThumbnail]).
Map<String, dynamic> photoEventContent(
  matrix.MatrixFile file,
  Uri fileMxc, {
  matrix.MatrixImageFile? thumbnail,
  Uri? thumbnailMxc,
  matrix.EncryptedFile? encryptedFile,
  matrix.EncryptedFile? encryptedThumbnail,
  Map<String, dynamic>? extraContent,
}) {
  Map<String, dynamic> encrypted(
          Uri mxc, String mimeType, matrix.EncryptedFile encryption) =>
      {
        'url': mxc.toString(),
        'mimetype': mimeType,
        'v': 'v2',
        'key': {
          'alg': 'A256CTR',
          'ext': true,
          'k': encryption.k,
          'key_ops': ['encrypt', 'decrypt'],
          'kty': 'oct',
        },
        'iv': encryption.iv,
        'hashes': {'sha256': encryption.sha256},
      };
  final hasThumbnail = thumbnail != null && thumbnailMxc != null;
  return {
    'msgtype': file.msgType,
    'body': file.name,
    'filename': file.name,
    if (encryptedFile == null) 'url': fileMxc.toString(),
    if (encryptedFile != null)
      'file': encrypted(fileMxc, file.mimeType, encryptedFile),
    'info': {
      ...file.info,
      if (hasThumbnail && encryptedThumbnail == null)
        'thumbnail_url': thumbnailMxc.toString(),
      if (hasThumbnail && encryptedThumbnail != null)
        'thumbnail_file':
            encrypted(thumbnailMxc, thumbnail.mimeType, encryptedThumbnail),
      if (hasThumbnail) 'thumbnail_info': thumbnail.info,
      if (hasThumbnail &&
          thumbnail.blurhash != null &&
          file is matrix.MatrixImageFile &&
          file.blurhash == null)
        'xyz.amorgan.blurhash': thumbnail.blurhash,
    },
    if (extraContent != null) ...extraContent,
  };
}
