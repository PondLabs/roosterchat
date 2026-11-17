/// The encryption of a file's attachment piece by piece: AES-256 in
/// counter mode (pointycastle's `CTRStreamCipher`, which encrypts as
/// vodozemac's `aes_ctr` does when the counter starts at zero, as the
/// Matrix spec has it), and the SHA-256 of every encrypted byte. Pure Dart,
/// so it runs in any isolate (see `disk_file_source.dart`, which runs it in
/// one of its own).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart'
    show AESEngine, CTRStreamCipher, KeyParameter, ParametersWithIV;

/// A file being encrypted piece by piece, with a new key and iv, and the
/// hash of what it gave so far.
class FileCipher {
  FileCipher(Uint8List key, Uint8List iv) : this._(key, iv, _DigestSink());

  FileCipher._(this.key, this.iv, this._digest)
      : _ctr = CTRStreamCipher(AESEngine())
          ..init(true, ParametersWithIV(KeyParameter(key), iv)),
        _hash = sha256.startChunkedConversion(_digest) {
    if (key.length != 32 || iv.length != 16) {
      throw ArgumentError('AES-256-CTR takes a 32-byte key and a 16-byte iv');
    }
  }

  /// A cipher with a random 32-byte key and an iv as the Matrix spec asks
  /// for attachments: 8 random bytes, then the 64-bit counter at zero, so
  /// it never wraps within a file and every client counts it the same.
  factory FileCipher.random() {
    final random = Random.secure();
    Uint8List bytes(int n) =>
        Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));
    return FileCipher(
        bytes(32), Uint8List.fromList([...bytes(8), ...List.filled(8, 0)]));
  }

  final Uint8List key;
  final Uint8List iv;
  final CTRStreamCipher _ctr;
  final _DigestSink _digest;
  final ByteConversionSink _hash;

  /// The bytes this cipher has encrypted.
  int encryptedBytes = 0;

  /// Encrypts the next piece, in place, and adds it to the hash: the pieces
  /// go on one after the other, so any sizes encrypt as the whole would.
  void encrypt(Uint8List piece) {
    _ctr.processBytes(piece, 0, piece.length, piece, 0);
    encryptedBytes += piece.length;
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
