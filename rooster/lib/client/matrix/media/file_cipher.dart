/// The encryption of a file's attachment piece by piece, as the Matrix SDK
/// encrypts one whole (`encryptFile`): AES-256 in counter mode with
/// vodozemac's counter (`Ctr64BE`), and the SHA-256 of every encrypted
/// byte. Pure Dart, so it runs in any isolate (see `disk_file_source.dart`,
/// which runs it in one of its own).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;

/// AES-256-CTR as vodozemac's `aes_ctr` applies it: the iv's first 8
/// bytes stay as they are, its last 8 are a big-endian count of 16-byte
/// blocks that wraps at 2^64. [apply] goes on where the last call stopped,
/// so pieces of any size encrypt as the whole would.
class AesCtr64 {
  AesCtr64(Uint8List key, Uint8List iv) : _counter = Uint8List.fromList(iv) {
    if (key.length != 32 || iv.length != 16) {
      throw ArgumentError('AES-256-CTR takes a 32-byte key and a 16-byte iv');
    }
    _aes.init(true, KeyParameter(key));
  }

  /// The blocks encrypted in this isolate, every cipher together: a test
  /// reads it to know where the work was done.
  static int blocksHere = 0;

  final _aes = AESEngine();
  final Uint8List _counter;
  final _keystream = Uint8List(16);
  int _used = 16;

  /// Encrypts (or decrypts) [bytes] in place.
  void apply(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (_used == 16) {
        _aes.processBlock(_counter, 0, _keystream, 0);
        blocksHere++;
        _next();
        _used = 0;
      }
      bytes[i] ^= _keystream[_used++];
    }
  }

  /// The next block's counter: the low 64 bits, wrapping.
  void _next() {
    for (var i = 15; i >= 8; i--) {
      _counter[i] = (_counter[i] + 1) & 0xff;
      if (_counter[i] != 0) return;
    }
  }
}

/// A file being encrypted piece by piece, with a new key and iv, and the
/// hash of what it gave so far.
class FileCipher {
  FileCipher(Uint8List key, Uint8List iv) : this._(key, iv, _DigestSink());

  FileCipher._(this.key, this.iv, this._digest)
      : _ctr = AesCtr64(key, iv),
        _hash = sha256.startChunkedConversion(_digest);

  /// A cipher with a random 32-byte key and 16-byte iv, as `encryptFile`
  /// makes them.
  factory FileCipher.random() {
    final random = Random.secure();
    Uint8List bytes(int n) =>
        Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));
    return FileCipher(bytes(32), bytes(16));
  }

  final Uint8List key;
  final Uint8List iv;
  final AesCtr64 _ctr;
  final _DigestSink _digest;
  final ByteConversionSink _hash;

  /// Encrypts the next piece, in place, and adds it to the hash.
  void encrypt(Uint8List piece) {
    _ctr.apply(piece);
    _hash.add(piece);
  }

  /// The SHA-256 of everything encrypted, once the file is done.
  Uint8List finish() {
    _hash.close();
    return Uint8List.fromList(_digest.value!.bytes);
  }

  /// [key] as an event's `k`: unpadded base64url, as `encryptFile`.
  String get keyText => unpadded(base64Url.encode(key));

  /// [iv] as an event's `iv`: unpadded base64, as `encryptFile`.
  String get ivText => unpadded(base64.encode(iv));

  static String unpadded(String text) => text.replaceAll('=', '');
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
