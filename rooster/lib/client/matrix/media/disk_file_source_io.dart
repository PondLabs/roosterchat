import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/media/file_cipher.dart';

/// The file at [path] as the SDK reads it at each upload (see
/// [DiskFileSource]), or null when it cannot be read.
Future<DiskFileSource?> diskFileSource(String path) => DiskFileSource.at(path);

/// A file on disk that the Matrix SDK reads anew at each upload attempt,
/// in pieces of [piece] bytes, each read only when the request takes the
/// last: memory grows by a few pieces, not by the file. In an encrypted
/// room each piece is encrypted in an isolate of its own (AES-256-CTR and
/// SHA-256, `file_cipher.dart`), with a new key at each attempt, so the
/// key and hash its event carries are those of the bytes that went up.
///
/// The file is the one at [path] when it was attached: [length] bytes,
/// written at [modified]. One that is gone, shorter, longer or written
/// since ends the read with [matrix.FileSourceChangedException].
class DiskFileSource implements matrix.FileSendSource {
  DiskFileSource(this.path, {required this.length, required this.modified});

  /// The file at [path] as it is now, or null when it cannot be read.
  static Future<DiskFileSource?> at(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return DiskFileSource(path, length: stat.size, modified: stat.modified);
    } on FileSystemException {
      return null;
    }
  }

  /// The largest piece read at once.
  static const piece = 256 * 1024;

  final String path;

  @override
  final int length;

  final DateTime modified;

  /// Times the file was opened: one per upload attempt.
  int opens = 0;

  /// Bytes read from the file, every attempt together.
  int bytesRead = 0;

  /// Reads whose file is open now.
  int openFiles = 0;

  /// Bytes encrypted for this file, and the isolate that encrypted them,
  /// as the cipher reports them at the end of each encrypted read.
  int encryptedBytes = 0;
  String? encryptedIn;

  @override
  matrix.FileSendRead read() => _DiskRead(this, encrypted: false);

  @override
  matrix.FileSendRead readEncrypted() => _DiskRead(this, encrypted: true);
}

/// One upload attempt's read of a [DiskFileSource].
class _DiskRead implements matrix.FileSendRead {
  _DiskRead(this._source, {required bool encrypted}) : _encrypted = encrypted {
    _out = StreamController<List<int>>(
      onListen: _pump,
      onResume: _pump,
      onCancel: close,
    );
  }

  final DiskFileSource _source;
  final bool _encrypted;
  late final StreamController<List<int>> _out;

  RandomAccessFile? _file;
  _CipherWorker? _worker;

  /// The opening of the file (and the cipher), which a close waits for.
  Future<void>? _opening;

  /// The file operation running, which a close waits for.
  Future<Object?>? _pending;
  int _read = 0;
  bool _pumping = false;
  bool _closed = false;
  Future<void>? _closing;

  @override
  bool complete = false;

  @override
  matrix.EncryptedFile? encryption;

  @override
  Object? failure;

  @override
  Stream<List<int>> get bytes => _out.stream;

  Future<T> _io<T>(Future<T> operation) {
    _pending = operation;
    return operation;
  }

  /// Reads (and encrypts) pieces while the request takes them: stops when
  /// it pauses, and goes on when it resumes.
  Future<void> _pump() async {
    if (_pumping || _closed || complete) return;
    _pumping = true;
    try {
      await (_opening ??= _open());
      if (_closed) return;
      final length = _source.length;
      while (!_closed && !_out.isPaused && _read < length) {
        final want = math.min(DiskFileSource.piece, length - _read);
        var piece = await _io(_file!.read(want));
        if (_closed) return;
        _source.bytesRead += piece.length;
        if (piece.length < want) {
          throw const matrix.FileSourceChangedException('the file is shorter');
        }
        _read += piece.length;
        final worker = _worker;
        if (worker != null) {
          piece = await worker.encrypt(piece);
          if (_closed) return;
        }
        _out.add(piece);
      }
      if (_closed || _read < length) return;
      await _end();
    } catch (error, stack) {
      if (_closed) return;
      failure = error is FileSystemException
          ? const matrix.FileSourceChangedException('the file cannot be read')
          : error;
      // The request fails with it; the file is closed, and so is the body.
      _out.addError(failure!, stack);
      await close();
    } finally {
      _pumping = false;
    }
  }

  /// Opens the file, as it was attached, and the cipher of an encrypted
  /// read. A close waits for the whole of it, then closes what it opened.
  Future<void> _open() async {
    await _checkUnchanged();
    if (_encrypted) _worker = await _CipherWorker.start();
    _file = await File(_source.path).open();
    _source.opens++;
    _source.openFiles++;
  }

  /// Every byte was read: nothing more is there, and it was not written
  /// since it was attached. Then the hash of what went up is known, and the
  /// file is closed before the server answers.
  Future<void> _end() async {
    if ((await _io(_file!.read(1))).isNotEmpty) {
      throw const matrix.FileSourceChangedException('the file is longer');
    }
    await _checkUnchanged();
    final worker = _worker;
    if (worker != null) {
      final (hash, bytes, isolate) = await worker.finish();
      _source
        ..encryptedBytes += bytes
        ..encryptedIn = isolate;
      encryption = matrix.EncryptedFile(
        data: Uint8List(0),
        k: worker.keyText,
        iv: worker.ivText,
        sha256: FileCipher.unpadded(base64.encode(hash)),
      );
    }
    if (_closed) return;
    complete = true;
    // The file is closed, and so is the body: the request's last byte.
    await close();
  }

  Future<void> _checkUnchanged() async {
    final stat = await _io(File(_source.path).stat());
    if (stat.type == FileSystemEntityType.notFound) {
      throw const matrix.FileSourceChangedException('the file is gone');
    }
    if (stat.size != _source.length || stat.modified != _source.modified) {
      throw const matrix.FileSourceChangedException(
          'the file was written since it was attached');
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // A file is closed once open, with no operation of its own running.
    try {
      await _opening;
    } catch (_) {}
    try {
      await _pending;
    } catch (_) {}
    final file = _file;
    _file = null;
    if (file != null) {
      try {
        await file.close();
      } finally {
        _source.openFiles--;
      }
    }
    _worker?.stop();
    _worker = null;
    // Still listened to: the request's body ends here, short of its
    // length, and the request fails if it was not aborted already.
    if (!_out.isClosed) unawaited(_out.close());
  }
}

/// The isolate a file is encrypted in, piece by piece, with a new key.
class _CipherWorker {
  _CipherWorker._(
      this._isolate, this._replies, this._requests, this.keyText, this.ivText);

  static Future<_CipherWorker> start() async {
    final replies = ReceivePort();
    final cipher = FileCipher.random();
    final isolate = await Isolate.spawn(
        _cipherMain, (replies.sendPort, cipher.key, cipher.iv),
        debugName: 'file cipher',
        onExit: replies.sendPort,
        errorsAreFatal: true);
    final worker = _CipherWorker._(
        isolate, replies, Completer<SendPort>(), cipher.keyText, cipher.ivText);
    replies.listen(worker._reply);
    worker._toWorker = await worker._requests.future;
    return worker;
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  final Completer<SendPort> _requests;
  final String keyText;
  final String ivText;
  late final SendPort _toWorker;
  Completer<Object?>? _waiting;
  bool _stopped = false;

  void _reply(Object? message) {
    if (!_requests.isCompleted && message is SendPort) {
      _requests.complete(message);
      return;
    }
    final waiting = _waiting;
    _waiting = null;
    if (message == null) {
      // The isolate ended (its exit message).
      _stopped = true;
      _replies.close();
      if (!_requests.isCompleted) {
        _requests.completeError(StateError('The file cipher did not start'));
      }
      waiting?.completeError(StateError('The file cipher stopped'));
      return;
    }
    waiting?.complete(message);
  }

  Future<Object?> _ask(Object message) {
    if (_stopped) throw StateError('The file cipher stopped');
    final waiting = _waiting = Completer<Object?>();
    _toWorker.send(message);
    return waiting.future;
  }

  /// [piece], encrypted.
  Future<Uint8List> encrypt(Uint8List piece) async {
    final reply = await _ask(TransferableTypedData.fromList([piece]));
    return (reply as TransferableTypedData).materialize().asUint8List();
  }

  /// The SHA-256 of every piece encrypted, how many bytes the cipher
  /// encrypted, and the name of the isolate it ran in; the isolate ends.
  Future<(Uint8List, int, String?)> finish() async {
    final reply = await _ask(const _Finish());
    final (hash, bytes, isolate) =
        reply as (TransferableTypedData, int, String?);
    return (hash.materialize().asUint8List(), bytes, isolate);
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _waiting?.completeError(StateError('The file cipher stopped'));
    _waiting = null;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

/// Asks the cipher isolate for the hash.
class _Finish {
  const _Finish();
}

void _cipherMain((SendPort, Uint8List, Uint8List) start) {
  final (replies, key, iv) = start;
  final cipher = FileCipher(key, iv);
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    if (message is TransferableTypedData) {
      final piece = message.materialize().asUint8List();
      cipher.encrypt(piece);
      replies.send(TransferableTypedData.fromList([piece]));
    } else if (message is _Finish) {
      replies.send((
        TransferableTypedData.fromList([cipher.finish()]),
        cipher.encryptedBytes,
        Isolate.current.debugName,
      ));
      requests.close();
    }
  });
}
