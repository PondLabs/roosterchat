// ROOSTER: this whole file is Rooster's. A file of a file message that is
// read from where it lives (a file on disk) at each upload attempt, never
// held whole in memory: a `MatrixFile` with a [FileSendSource] is sent by
// `Room.sendFileEvent` through `file_upload_loop.dart`, its request body a
// stream ([FileSendRequest]). The SDK knows no file system: the app gives
// the source.

import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:matrix/matrix.dart';

/// Where a file to send is read from, anew at each upload attempt.
abstract class FileSendSource {
  /// The file's size in bytes when it was attached: what goes up, and what
  /// its event says.
  int get length;

  /// One upload attempt of the file as it is, in the clear. Nothing is read
  /// before its [FileSendRead.bytes] are listened to.
  FileSendRead read();

  /// One upload attempt of the file encrypted with a new key and iv
  /// (AES-256-CTR, as `encryptFile`), off the thread that draws the UI.
  /// Nothing is read before its [FileSendRead.bytes] are listened to.
  FileSendRead readEncrypted();
}

/// One upload attempt's read of a [FileSendSource].
abstract class FileSendRead {
  /// The bytes that go up, [FileSendSource.length] of them, read only as
  /// the request takes them. Ends with [FileSourceChangedException] when
  /// the file is gone, shorter or longer, or changed since it was attached.
  Stream<List<int>> get bytes;

  /// [bytes] ended with every byte read, and the file had not changed.
  bool get complete;

  /// An encrypted read, once [complete]: the key, the iv and the hash of
  /// every encrypted byte that went up (its `data` is empty). Null for a
  /// read in the clear.
  EncryptedFile? get encryption;

  /// Why [bytes] failed, when they did.
  Object? get failure;

  /// Stops reading and closes the file: completes once it is closed. Can
  /// be called again; [bytes] end with an error when still listened to.
  Future<void> close();
}

/// The file of a message changed on this device since it was attached: it
/// is gone, shorter, longer, or written since. Its send ends here, without
/// a new attempt: what its event would describe is not on the disk any
/// more.
class FileSourceChangedException implements Exception {
  const FileSourceChangedException(this.reason);

  /// What changed, without the file's name or path.
  final String reason;

  @override
  String toString() => 'FileSourceChangedException: $reason';
}

/// A request whose body is [body], [length] bytes, handed to the transport
/// as it takes them.
class FileSendRequest extends http.BaseRequest {
  FileSendRequest(super.method, super.url, this.body, int length) {
    contentLength = length;
  }

  final Stream<List<int>> body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}
