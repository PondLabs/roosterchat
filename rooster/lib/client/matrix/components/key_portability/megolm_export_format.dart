/// The Matrix spec's key export format ("Key exports" in the
/// client-server API), the file Element and other clients save and read:
/// a JSON list of room key sessions, encrypted with a passphrase.
///
/// The bytes are a version byte (1), a 16-byte salt, a 16-byte IV, the
/// PBKDF2 round count (4 bytes, big-endian), the AES-256-CTR ciphertext and
/// an HMAC-SHA-256 of everything before it. PBKDF2-HMAC-SHA-512 turns the
/// passphrase into 512 bits: the AES key, then the HMAC key. The file is
/// that in base64 between `-----BEGIN MEGOLM SESSION DATA-----` and
/// `-----END MEGOLM SESSION DATA-----`.
///
/// The `cryptography` package does the work: Web Crypto in a browser, pure
/// Dart elsewhere, where PBKDF2 runs on an isolate of its own so the
/// screen does not freeze for its half a million rounds.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Why a key export could not be read.
enum MegolmExportError {
  /// No `BEGIN`/`END MEGOLM SESSION DATA` lines: some other file.
  notAKeyExport,

  /// Broken base64, too short, or a version this app does not know: a
  /// truncated or damaged file.
  damaged,

  /// The HMAC does not match: the passphrase is wrong (or the encrypted
  /// part was changed).
  wrongPassphrase,

  /// It decrypted, but is not a list of room key sessions.
  invalidContent,
}

class MegolmExportException implements Exception {
  const MegolmExportException(this.error);

  final MegolmExportError error;

  @override
  String toString() => 'MegolmExportException(${error.name})';
}

class MegolmExportFormat {
  static const header = '-----BEGIN MEGOLM SESSION DATA-----';
  static const trailer = '-----END MEGOLM SESSION DATA-----';

  /// Element's round count: it takes a guesser that long per passphrase.
  static const defaultRounds = 500000;

  static const _version = 1;
  static const _saltLength = 16;
  static const _ivLength = 16;
  static const _macLength = 32;
  static const _headerLength = 1 + _saltLength + _ivLength + 4;

  /// Bytes per base64 line, as Element writes them: a multiple of 3, so
  /// no line but the last has padding.
  static const _lineBytes = 96;

  /// [sessions] encrypted with [passphrase], as the file's text.
  static Future<String> encrypt(
    List<Map<String, Object?>> sessions,
    String passphrase, {
    int rounds = defaultRounds,
    Random? random,
  }) =>
      encryptBytes(utf8.encode(jsonEncode(sessions)), passphrase,
          rounds: rounds, random: random);

  /// [plaintext] encrypted with [passphrase], as the file's text.
  static Future<String> encryptBytes(
    List<int> plaintext,
    String passphrase, {
    int rounds = defaultRounds,
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    List<int> randomBytes(int n) => List.generate(n, (_) => rng.nextInt(256));
    final salt = randomBytes(_saltLength);
    final iv = randomBytes(_ivLength);
    // The counter's top bit clear, as the spec asks, so it cannot wrap
    // around in a 64-bit counter.
    iv[8] &= 0x7f;
    final keys = await _deriveKeys(passphrase, salt, rounds);
    final ciphertext = await _aesCtr(plaintext, keys.aesKey, iv, encrypt: true);

    final body = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(salt)
      ..add(iv)
      ..add(_uint32(rounds))
      ..add(ciphertext);
    final signed = body.takeBytes();
    final mac = await _hmac(keys.hmacKey, signed);
    return _armor(Uint8List.fromList([...signed, ...mac]));
  }

  /// The sessions in [file], decrypted with [passphrase]. Throws a
  /// [MegolmExportException] for anything but a good file and passphrase,
  /// before anything is decrypted when the HMAC does not match.
  static Future<List<Map<String, Object?>>> decrypt(
      Uint8List file, String passphrase) async {
    final plaintext = await decryptBytes(file, passphrase);
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! List) throw const FormatException('not a list');
      return [
        for (final session in decoded)
          if (session is Map<String, Object?>)
            session
          else
            throw const FormatException('not an object'),
      ];
    } on FormatException {
      throw const MegolmExportException(MegolmExportError.invalidContent);
    }
  }

  /// The plaintext in [file], as [decrypt] reads it before the JSON.
  static Future<List<int>> decryptBytes(
      Uint8List file, String passphrase) async {
    final data = _unarmor(file);
    if (data.length < _headerLength + _macLength) {
      throw const MegolmExportException(MegolmExportError.damaged);
    }
    if (data[0] != _version) {
      throw const MegolmExportException(MegolmExportError.damaged);
    }
    final salt = data.sublist(1, 1 + _saltLength);
    final iv = data.sublist(1 + _saltLength, 1 + _saltLength + _ivLength);
    final rounds = ByteData.sublistView(data, _headerLength - 4, _headerLength)
        .getUint32(0);
    if (rounds == 0) {
      throw const MegolmExportException(MegolmExportError.damaged);
    }
    final signed = Uint8List.sublistView(data, 0, data.length - _macLength);
    final mac = Uint8List.sublistView(data, data.length - _macLength);

    final keys = await _deriveKeys(passphrase, salt, rounds);
    final expected = await _hmac(keys.hmacKey, signed);
    if (!_sameBytes(expected, mac)) {
      throw const MegolmExportException(MegolmExportError.wrongPassphrase);
    }
    return _aesCtr(
        Uint8List.sublistView(signed, _headerLength), keys.aesKey, iv,
        encrypt: false);
  }

  static String _armor(Uint8List data) {
    final lines = <String>[header];
    for (var i = 0; i < data.length; i += _lineBytes) {
      lines.add(base64.encode(
          Uint8List.sublistView(data, i, min(i + _lineBytes, data.length))));
    }
    lines.add(trailer);
    return '${lines.join('\n')}\n';
  }

  static Uint8List _unarmor(Uint8List file) {
    final String text;
    try {
      text = utf8.decode(file);
    } on FormatException {
      throw const MegolmExportException(MegolmExportError.notAKeyExport);
    }
    final lines = const LineSplitter().convert(text).map((l) => l.trim());
    final body = lines.skipWhile((line) => line != header).toList();
    if (body.isEmpty) {
      throw const MegolmExportException(MegolmExportError.notAKeyExport);
    }
    final end = body.indexOf(trailer);
    // A header without its trailer: the end of the file is missing.
    if (end < 0) throw const MegolmExportException(MegolmExportError.damaged);
    try {
      return base64.decode(body.sublist(1, end).join());
    } on FormatException {
      throw const MegolmExportException(MegolmExportError.damaged);
    }
  }

  static Future<({List<int> aesKey, List<int> hmacKey})> _deriveKeys(
      String passphrase, List<int> salt, int rounds) async {
    final args = (utf8.encode(passphrase), salt, rounds);
    // Pure Dart PBKDF2 is slow: off the screen's isolate, except in a
    // browser, where Web Crypto does it without blocking anyway.
    final key = kIsWeb ? await _pbkdf2(args) : await compute(_pbkdf2, args);
    return (aesKey: key.sublist(0, 32), hmacKey: key.sublist(32, 64));
  }

  static Future<List<int>> _aesCtr(List<int> input, List<int> key, List<int> iv,
      {required bool encrypt}) async {
    final cipher = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key);
    if (encrypt) {
      final box = await cipher.encrypt(input, secretKey: secretKey, nonce: iv);
      return box.cipherText;
    }
    return cipher.decrypt(SecretBox(input, nonce: iv, mac: Mac.empty),
        secretKey: secretKey);
  }

  static Future<List<int>> _hmac(List<int> key, List<int> input) async =>
      (await Hmac.sha256().calculateMac(input, secretKey: SecretKey(key)))
          .bytes;

  static List<int> _uint32(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  /// Compares in constant time, as a MAC check should.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// PBKDF2-HMAC-SHA-512 to 512 bits. Top level, for [compute].
Future<List<int>> _pbkdf2((List<int>, List<int>, int) args) async {
  final (passphrase, salt, rounds) = args;
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha512(),
    iterations: rounds,
    bits: 512,
  ).deriveKey(secretKey: SecretKey(passphrase), nonce: salt);
  return key.extractBytes();
}
