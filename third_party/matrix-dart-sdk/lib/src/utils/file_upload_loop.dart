// ROOSTER: this whole file is Rooster's. The upload loop of
// `Room.sendFileEvent`: each part of a file message (the file, its
// thumbnail) goes up by itself, the parts together; a part is kept once it
// went up, and is tried again by itself a bounded number of times.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// The time the file send loop reads and waits by. Tests give the client
/// their own, to decide the loop's rules without waiting for real.
class SendClock {
  const SendClock();

  DateTime now() => DateTime.now();

  Future<void> delay(Duration duration) => Future.delayed(duration);
}

/// A part of a file message.
enum FileSendPart { file, thumbnail }

/// Thrown inside a send that was cancelled (`Room.cancelSending`): the send
/// stops there, and nothing more of it reaches the server.
class SendCancelledException implements Exception {
  const SendCancelledException();

  @override
  String toString() => 'SendCancelledException: the send was cancelled';
}

/// Thrown before the event of a file message whose parts went up in the
/// clear when its room now encrypts files: an encrypted event never points
/// to an upload in the clear. A retry uploads the file again, encrypted.
class ClearUploadInEncryptedRoomException implements Exception {
  const ClearUploadInEncryptedRoomException();

  @override
  String toString() => 'ClearUploadInEncryptedRoomException: the room '
      'encrypts files now and the file went up in the clear';
}

const _uploadCancelKey = #matrixUploadCancel;

/// The cancel of the upload running in this zone, null outside the upload
/// of a part of a file message: it completes when that message's send is
/// cancelled, and the HTTP client aborts the request then.
Future<void>? currentUploadCancel() =>
    Zone.current[_uploadCancelKey] as Future<void>?;

/// Runs [upload] so that the HTTP client aborts its request when [cancel]
/// completes (see [currentUploadCancel]).
R runCancellableUpload<R>(Future<void> cancel, R Function() upload) =>
    runZoned(upload, zoneValues: {_uploadCancelKey: cancel});

/// Runs [run] until the send of the message [txid] in [room] is cancelled:
/// then [SendCancelledException] is thrown at once, and the future [run]
/// was given completes, so what it started can stop. Throws at once when
/// the send was cancelled before.
Future<T> untilSendCancelled<T>(
  Room room,
  String txid,
  Future<T> Function(Future<void> cancelled) run,
) async {
  if (room.isSendCancelled(txid)) throw const SendCancelledException();
  final cancelled = Completer<void>();
  final listening = room.onSendCancelled.listen((cancelledTxid) {
    if (cancelledTxid == txid && !cancelled.isCompleted) cancelled.complete();
  });
  try {
    return await Future.any([
      run(cancelled.future),
      cancelled.future.then<T>((_) => throw const SendCancelledException()),
    ]);
  } finally {
    await listening.cancel();
  }
}

/// The most upload requests of file messages a client has open at once,
/// across messages: a file and its thumbnail are two.
const maxUploadsAtOnce = 4;

/// A client's upload requests: how many are open, and the parts waiting
/// for one to end, in the order they came.
class _UploadSlots {
  int open = 0;
  final waiting = Queue<Completer<void>>();

  /// An upload ended: the first part waiting takes its slot.
  void give() {
    if (waiting.isNotEmpty) {
      waiting.removeFirst().complete();
    } else {
      open--;
    }
  }
}

final _uploadSlots = Expando<_UploadSlots>();

/// Takes one of the upload slots of [room]'s client for the message
/// [txid], waiting for its turn; a cancel while it waits leaves the line.
Future<_UploadSlots> _takeUploadSlot(Room room, String txid) async {
  final slots = _uploadSlots[room.client] ??= _UploadSlots();
  if (room.isSendCancelled(txid)) throw const SendCancelledException();
  if (slots.open < maxUploadsAtOnce) {
    slots.open++;
    return slots;
  }
  final turn = Completer<void>();
  slots.waiting.add(turn);
  try {
    await untilSendCancelled(room, txid, (_) => turn.future);
  } catch (_) {
    // Handed the slot just as the cancel came: it goes to the next.
    if (!slots.waiting.remove(turn)) slots.give();
    rethrow;
  }
  return slots;
}

/// A part of a file message that went up: its address, its size and, in
/// an encrypted room, the key and hash its event carries. A retry of the
/// message reuses it, with the same key, instead of uploading it again.
class UploadedFilePart {
  const UploadedFilePart(this.uri, {required this.bytes, this.encryptedFile});

  final Uri uri;

  /// The bytes that went up.
  final int bytes;

  /// The file's encryption (its key, iv and hash; not its bytes), null
  /// for a part sent in the clear.
  final EncryptedFile? encryptedFile;
}

/// The waits before the new attempts of a part that failed: at most two.
const fileUploadRetryDelays = [Duration(seconds: 2), Duration(seconds: 8)];

/// A `retry_after_ms` longer than this is not waited for: the message
/// fails, and its error says when the server takes it again.
const fileUploadLongestRetryAfter = Duration(seconds: 8);

/// A part that failed after running longer than this is not tried again
/// by itself: it would cost as long again, the user decides.
const fileUploadLongestRetriedRun = Duration(seconds: 60);

/// The Matrix errors that end a send: size, permission, authentication.
const _endingErrcodes = {
  'M_TOO_LARGE',
  'M_FORBIDDEN',
  'M_UNKNOWN_TOKEN',
  'M_MISSING_TOKEN',
  'M_UNAUTHORIZED',
  'M_USER_DEACTIVATED',
};

/// How long to wait before trying a part again after [error], when
/// [retries] new attempts were made already and the failed one ran for
/// [ranFor]; null when the part is not tried again by itself.
Duration? fileUploadRetryWait(
  Object error, {
  required int retries,
  required Duration ranFor,
}) {
  if (retries >= fileUploadRetryDelays.length) return null;
  // Its errcode is not a string: it says nothing to [_endingErrcodes].
  if (error is FileTooBigMatrixException) return null;
  if (error is MatrixException && _endingErrcodes.contains(error.errcode)) {
    return null;
  }
  if (ranFor > fileUploadLongestRetriedRun) return null;
  final retryAfterMs = error is MatrixException ? error.retryAfterMs : null;
  if (retryAfterMs != null) {
    final retryAfter = Duration(milliseconds: retryAfterMs);
    return retryAfter > fileUploadLongestRetryAfter ? null : retryAfter;
  }
  return fileUploadRetryDelays[retries];
}

/// The parts of the file message [txid] in [room] that went up before and
/// can be reused: a part that does not match the room's file encryption
/// ([encrypted]) is let go and uploaded again, and so is a thumbnail the
/// message no longer has.
Map<FileSendPart, UploadedFilePart> keptFileParts(
  Room room,
  String txid, {
  required bool encrypted,
  required bool hasThumbnail,
}) {
  final kept = room.sendingFileUploads[txid];
  if (kept == null) return const {};
  kept.removeWhere((_, part) => (part.encryptedFile != null) != encrypted);
  if (!hasThumbnail) kept.remove(FileSendPart.thumbnail);
  return Map.of(kept);
}

/// What [uploadFileParts] does with one part of a file message, decided
/// once, before any upload: reuse [kept], or upload [upload], which in an
/// encrypted room is the part encrypted as [encryptedFile].
class FilePartSend {
  const FilePartSend(this.kept, this.upload, this.encryptedFile);

  final UploadedFilePart? kept;
  final MatrixFile? upload;
  final EncryptedFile? encryptedFile;
}

/// Uploads the [parts] of the file message [txid] in [room] together, and
/// gives their addresses in the same order. A part kept from before is
/// reused as [parts] says, never looked up again; one that goes up is kept
/// at once. When a part fails for good, the others still finish and are
/// kept, and then its error is thrown. With [encrypted], a part without its
/// encryption is never uploaded: the clear bytes cannot reach the server.
Future<List<Uri>> uploadFileParts(
  Room room,
  String txid,
  Map<FileSendPart, FilePartSend> parts, {
  required bool encrypted,
}) =>
    Future.wait(
      [
        for (final MapEntry(key: part, value: send) in parts.entries)
          _uploadFilePart(room, txid, part, send, encrypted: encrypted),
      ],
      eagerError: false,
    );

Future<Uri> _uploadFilePart(
  Room room,
  String txid,
  FileSendPart part,
  FilePartSend send, {
  required bool encrypted,
}) async {
  final kept = send.kept;
  if (kept != null) return kept.uri;
  final upload = send.upload;
  final encryptedFile = send.encryptedFile;
  if (upload == null || (encrypted && encryptedFile == null)) {
    throw StateError('A part of a file message has nothing safe to upload');
  }
  final client = room.client;
  final clock = client.sendClock;
  for (var retries = 0;; retries++) {
    // At most [maxUploadsAtOnce] at once; the time of an attempt counts
    // from its start, not from its wait for a slot.
    final slots = await _takeUploadSlot(room, txid);
    final started = clock.now();
    final Uri uri;
    try {
      // A cancel aborts the request in flight (see [currentUploadCancel]).
      uri = await untilSendCancelled(
        room,
        txid,
        (cancelled) => runCancellableUpload(
          cancelled,
          () => client.uploadContent(
            upload.bytes,
            filename: upload.name,
            contentType: upload.mimeType,
          ),
        ),
      );
    } catch (error) {
      slots.give();
      if (error is SendCancelledException) rethrow;
      final wait = fileUploadRetryWait(
        error,
        retries: retries,
        ranFor: clock.now().difference(started),
      );
      if (wait == null) rethrow;
      Logs().v('Upload of a file part failed. Trying again in $wait');
      await untilSendCancelled(room, txid, (_) => clock.delay(wait));
      continue;
    }
    slots.give();
    // Not kept for a message no longer being sent (cancelled).
    if (room.sendingFilePlaceholders.containsKey(txid) &&
        !room.isSendCancelled(txid)) {
      room.sendingFileUploads.putIfAbsent(txid, () => {})[part] =
          UploadedFilePart(
        uri,
        bytes: upload.bytes.length,
        // What a reuse needs: the key, the iv and the hash, not the
        // encrypted bytes, which went up already.
        encryptedFile: encryptedFile == null
            ? null
            : EncryptedFile(
                data: Uint8List(0),
                k: encryptedFile.k,
                iv: encryptedFile.iv,
                sha256: encryptedFile.sha256,
              ),
      );
    }
    return uri;
  }
}
