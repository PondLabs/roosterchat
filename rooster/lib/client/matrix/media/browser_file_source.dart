/// A file picked, pasted or dropped in the browser, sent as the browser's
/// `File` (a `Blob`) and never read whole into memory: web only.
///
/// In a room that does not encrypt, `XMLHttpRequest` sends the `File` as it
/// is (`BlobBody` in `xhr_upload_web.dart`): the browser reads it from the
/// disk while it sends. In an encrypted room each attempt reads it in
/// pieces of [BrowserFileSource.piece] bytes, encrypts each with a new key
/// (AES-256-CTR and SHA-256, `file_cipher.dart`, on the page's thread: the
/// web has no isolates) and adds it to a `Blob` the browser keeps, which is
/// what goes up. Memory grows by a piece, not by the file.
///
/// A file changed, moved or deleted since it was picked is not readable
/// any more (the browser's `NotReadableError`): its read ends with
/// [matrix.FileSourceChangedException], and its send fails without a new
/// attempt, as a file on disk does (`disk_file_source_io.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/media/file_cipher.dart';
import 'package:rooster/utils/network/xhr_upload_web.dart';
import 'package:web/web.dart' as web;

/// The browser's [file], read anew at each upload attempt.
class BrowserFileSource implements matrix.FileSendSource {
  BrowserFileSource(this.file) : length = file.size;

  /// The largest piece read at once.
  static const piece = 256 * 1024;

  final web.Blob file;

  @override
  final int length;

  /// Bytes read into memory from the file, every attempt together: none
  /// for an upload in the clear through `XMLHttpRequest`, only the byte
  /// that checks the file is still readable.
  int bytesRead = 0;

  /// The most bytes read at once.
  int largestRead = 0;

  @override
  matrix.FileSendRead read() => BrowserFileRead(this, encrypted: false);

  @override
  matrix.FileSendRead readEncrypted() => BrowserFileRead(this, encrypted: true);
}

/// One upload attempt's read of a [BrowserFileSource]: listened to, its
/// pieces one at a time; given to `XMLHttpRequest`, the `Blob` it sends.
class BrowserFileRead extends Stream<List<int>>
    implements matrix.FileSendRead, BlobBody {
  BrowserFileRead(this._source, {required this.encrypted});

  final BrowserFileSource _source;
  final bool encrypted;
  bool _started = false;
  bool _closed = false;

  /// The browser was given the file itself, to read while it sends.
  bool _givenToBrowser = false;
  Future<void>? _closing;

  @override
  bool complete = false;

  @override
  matrix.EncryptedFile? encryption;

  @override
  Object? failure;

  @override
  Stream<List<int>> get bytes => this;

  void _start() {
    if (_started) throw StateError('A read of a file is used once');
    _started = true;
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    _start();
    return _streamed().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Stream<List<int>> _streamed() async* {
    yield* _pieces();
    if (!_closed) complete = true;
  }

  /// The file in pieces, each read when the last was taken, encrypted in
  /// an encrypted read, whose [encryption] is set after the last.
  Stream<Uint8List> _pieces() async* {
    final cipher = encrypted ? FileCipher.random() : null;
    final length = _source.length;
    for (var start = 0; start < length;) {
      final end = math.min(start + BrowserFileSource.piece, length);
      final piece = await _read(start, end);
      if (_closed) return;
      cipher?.encrypt(piece);
      start = end;
      yield piece;
    }
    if (_closed || cipher == null) return;
    encryption = matrix.EncryptedFile(
      data: Uint8List(0),
      k: cipher.keyText,
      iv: cipher.ivText,
      sha256: FileCipher.unpadded(base64.encode(cipher.finish())),
    );
  }

  /// Bytes [start] to [end] of the file, read into memory.
  Future<Uint8List> _read(int start, int end) async {
    final Uint8List piece;
    try {
      final buffer = await _source.file.slice(start, end).arrayBuffer().toDart;
      piece = buffer.toDart.asUint8List();
    } catch (_) {
      // NotReadableError: changed, moved or deleted since it was picked.
      throw failure ??=
          const matrix.FileSourceChangedException('the file cannot be read');
    }
    _source
      ..bytesRead += piece.length
      ..largestRead = math.max(_source.largestRead, piece.length);
    if (piece.length != end - start) {
      throw failure ??=
          const matrix.FileSourceChangedException('the file is shorter');
    }
    return piece;
  }

  @override
  Future<web.Blob> blob() async {
    _start();
    if (!encrypted) {
      // One byte, to know the browser can still read it.
      if (_source.length > 0) await _read(0, 1);
      _givenToBrowser = true;
      return _source.file;
    }
    var out = web.Blob();
    await for (final piece in _pieces()) {
      // The browser keeps what was encrypted; one piece is held here.
      out = web.Blob(<JSAny>[out, piece.toJS].toJS);
    }
    if (_closed) throw StateError('The read of the file was closed');
    return out;
  }

  @override
  void sent() {
    if (_closed) return;
    complete = !encrypted || encryption != null;
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_givenToBrowser && !complete && failure == null) {
      // The browser's send failed: Chrome fails one whose file changed
      // since it was picked (ERR_UPLOAD_FILE_CHANGED), and a byte read
      // tells that from a network failure.
      try {
        await _read(0, 1);
      } catch (_) {}
    }
    _closed = true;
  }
}
