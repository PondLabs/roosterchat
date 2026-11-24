/// The ECIES channel of QR code login (MSC4108), byte for byte the one of
/// `vodozemac::ecies` 0.9, so Rooster talks to Element X and every other
/// client built on vodozemac without its native or WASM binary.
///
/// X25519 makes the shared secret. HKDF-SHA-512 (no salt) turns it into two
/// ChaCha20-Poly1305 keys, one per direction, and a two-byte check code.
/// Each HKDF info is `MATRIX_QR_CODE_LOGIN_<PURPOSE>|<G public key>|<S
/// public key>` in unpadded base64, where S is the device that opens the
/// channel (the one that read the QR code) and G the one whose key it read.
/// Each direction counts its own nonces from 0, little-endian, so a message
/// replayed, dropped or reordered no longer decrypts.
///
/// Pure Dart (the `cryptography` package), the same on every platform.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The application info of QR code login, vodozemac's
/// `MATRIX_QR_LOGIN_INFO_PREFIX`.
const qrLoginEciesInfo = 'MATRIX_QR_CODE_LOGIN';

/// A message that does not decrypt (wrong key, changed, replayed or out of
/// order), a key without contributory behaviour, or one that is not a key.
class EciesException implements Exception {
  const EciesException(this.reason);

  final String reason;

  @override
  String toString() => 'EciesException($reason)';
}

/// The two-byte code both sides derive, read out on one device and typed
/// on the other to rule out a man in the middle.
class EciesCheckCode {
  EciesCheckCode(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != 2) throw ArgumentError('A check code is two bytes');
  }

  final Uint8List bytes;

  /// vodozemac's `CheckCode::to_digit`: 0 to 99, shown with two digits.
  int get digits => (bytes[0] % 10) * 10 + bytes[1] % 10;

  String get display => digits.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is EciesCheckCode &&
      other.bytes[0] == bytes[0] &&
      other.bytes[1] == bytes[1];

  @override
  int get hashCode => Object.hash(bytes[0], bytes[1]);
}

/// Standard base64 without padding, as vodozemac writes it.
String eciesBase64Encode(List<int> bytes) =>
    base64.encode(bytes).replaceAll('=', '');

/// Standard base64 with or without padding, as vodozemac reads it.
Uint8List eciesBase64Decode(String text) {
  if (text.length % 4 == 1 ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(text)) {
    throw const FormatException('Not base64');
  }
  final unpadded = text.replaceAll('=', '');
  return base64.decode(unpadded.padRight((unpadded.length + 3) ~/ 4 * 4, '='));
}

Uint8List _publicKeyBytes(List<int> bytes) {
  if (bytes.length != 32) {
    throw const EciesException('A Curve25519 public key is 32 bytes');
  }
  return Uint8List.fromList(bytes);
}

/// vodozemac's `InitialMessage`: the opener's public key and the first
/// ciphertext, encoded `<ciphertext>|<public key>`.
class EciesInitialMessage {
  EciesInitialMessage(List<int> publicKey, List<int> ciphertext)
      : publicKey = _publicKeyBytes(publicKey),
        ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List publicKey;
  final Uint8List ciphertext;

  String encode() =>
      '${eciesBase64Encode(ciphertext)}|${eciesBase64Encode(publicKey)}';

  static EciesInitialMessage decode(String text) {
    final separator = text.indexOf('|');
    if (separator < 0) throw const FormatException('No | separator');
    return EciesInitialMessage(eciesBase64Decode(text.substring(separator + 1)),
        eciesBase64Decode(text.substring(0, separator)));
  }
}

/// vodozemac's `Message`: a ciphertext in unpadded base64.
class EciesMessage {
  EciesMessage(List<int> ciphertext)
      : ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List ciphertext;

  String encode() => eciesBase64Encode(ciphertext);

  static EciesMessage decode(String text) =>
      EciesMessage(eciesBase64Decode(text));
}

enum _Role { initiator, recipient }

final _x25519 = X25519();
final _aead = Chacha20.poly1305Aead();

/// A channel not established yet: our ephemeral X25519 key pair.
class Ecies {
  Ecies._(this._keyPair, this.publicKey, this.info);

  final SimpleKeyPair _keyPair;
  final Uint8List publicKey;
  final String info;

  static Future<Ecies> create({String info = qrLoginEciesInfo}) async =>
      _from(await _x25519.newKeyPair(), info);

  /// A key pair from a known seed. Only test vectors need one.
  static Future<Ecies> fromSeed(List<int> seed,
          {String info = qrLoginEciesInfo}) async =>
      _from(await _x25519.newKeyPairFromSeed(seed), info);

  static Future<Ecies> _from(SimpleKeyPair keyPair, String info) async {
    final public = await keyPair.extractPublicKey();
    return Ecies._(keyPair, Uint8List.fromList(public.bytes), info);
  }

  /// As device S: opens the channel to [theirPublicKey] (read from the QR
  /// code) with [plaintext] as the first message.
  Future<(EstablishedEcies, EciesInitialMessage)> establishOutbound(
      List<int> theirPublicKey, List<int> plaintext) async {
    final channel = await EstablishedEcies._create(
        this, _publicKeyBytes(theirPublicKey), _Role.initiator);
    final first = await channel.encrypt(plaintext);
    return (channel, EciesInitialMessage(publicKey, first.ciphertext));
  }

  /// As device G: takes the channel [message] opens, and its plaintext.
  Future<(EstablishedEcies, Uint8List)> establishInbound(
      EciesInitialMessage message) async {
    final channel = await EstablishedEcies._create(
        this, message.publicKey, _Role.recipient);
    final plaintext = await channel.decrypt(EciesMessage(message.ciphertext));
    return (channel, plaintext);
  }
}

/// An established channel: encrypts what we send and decrypts what the
/// other side sends, each in order.
class EstablishedEcies {
  EstablishedEcies._(this._encryptionKey, this._decryptionKey, this.checkCode,
      this.theirPublicKey);

  final SecretKey _encryptionKey;
  final SecretKey _decryptionKey;
  final EciesCheckCode checkCode;
  final Uint8List theirPublicKey;
  int _encryptionNonce = 0;
  int _decryptionNonce = 0;

  static Future<EstablishedEcies> _create(
      Ecies ours, Uint8List theirs, _Role role) async {
    final shared = await (await _x25519.sharedSecretKey(
      keyPair: ours._keyPair,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    ))
        .extractBytes();
    // x25519-dalek's `was_contributory`: a low-order key gives all zeros.
    if (shared.every((b) => b == 0)) {
      throw const EciesException('Non-contributory key');
    }
    final (g, s) = role == _Role.recipient
        ? (ours.publicKey, theirs)
        : (theirs, ours.publicKey);
    final keys = '|${eciesBase64Encode(g)}|${eciesBase64Encode(s)}';
    final info = ours.info;
    Future<List<int>> expand(String purpose, int length) async =>
        (await Hkdf(hmac: Hmac.sha512(), outputLength: length).deriveKey(
          secretKey: SecretKey(shared),
          nonce: const [],
          info: utf8.encode('${info}_$purpose$keys'),
        ))
            .extractBytes();
    final keyS = await expand('ENCKEY_S', 32);
    final keyG = await expand('ENCKEY_G', 32);
    final code = EciesCheckCode(await expand('CHECKCODE', 2));
    final (encrypt, decrypt) =
        role == _Role.initiator ? (keyS, keyG) : (keyG, keyS);
    return EstablishedEcies._(
        SecretKey(encrypt), SecretKey(decrypt), code, theirs);
  }

  /// vodozemac's `EciesNonce`: the counter's 12 low bytes, little-endian.
  static List<int> _nonce(int counter) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(0, counter, Endian.little);
    return nonce;
  }

  Future<EciesMessage> encrypt(List<int> plaintext) async {
    final box = await _aead.encrypt(plaintext,
        secretKey: _encryptionKey, nonce: _nonce(_encryptionNonce++));
    return EciesMessage([...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [EciesException] when [message] is not the next one the other
  /// side sent: changed, replayed, reordered or from someone else.
  Future<Uint8List> decrypt(EciesMessage message) async {
    final nonce = _nonce(_decryptionNonce++);
    final bytes = message.ciphertext;
    if (bytes.length < 16) throw const EciesException('Decryption failed');
    try {
      final clear = await _aead.decrypt(
        SecretBox(bytes.sublist(0, bytes.length - 16),
            nonce: nonce, mac: Mac(bytes.sublist(bytes.length - 16))),
        secretKey: _decryptionKey,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const EciesException('Decryption failed');
    }
  }
}
