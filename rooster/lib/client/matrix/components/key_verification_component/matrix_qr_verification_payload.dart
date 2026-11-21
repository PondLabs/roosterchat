import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

/// Specific reason why a QR verification payload could not be parsed or
/// matched to the active verification transaction.
enum QrPayloadParseError {
  empty,
  invalidEncoding,
  invalidHeader,
  unsupportedVersion,
  invalidMode,
  invalidTransactionId,
  truncated,
  transactionMismatch,
}

/// Thrown when a pasted or loaded QR verification payload is malformed or does
/// not belong to the active verification transaction.
class QrPayloadFormatException implements Exception {
  const QrPayloadFormatException(this.error, [this.detail]);

  final QrPayloadParseError error;
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'QrPayloadFormatException($error)' : '$error: $detail';
}

/// Result of checking a parsed Matrix QR verification payload against the
/// active [KeyVerification] session and known public keys.
enum QrKeyValidationResult {
  valid,
  transactionMismatch,
  keyMismatch,
  unverifiedOwnMasterKey,
}

/// Parsed Matrix QR key verification payload (`MATRIX` v2 binary format).
///
/// Layout per Matrix Client-Server API specification:
/// - Bytes 0..5: ASCII `"MATRIX"`
/// - Byte 6: version (`0x02`)
/// - Byte 7: mode (`0x00` other user, `0x01` self trusted, `0x02` self untrusted)
/// - Bytes 8..9: big-endian uint16 length `L` of the UTF-8 transaction/event ID
/// - Bytes 10..(10+L-1): UTF-8 transaction/event ID
/// - Next 32 bytes: first Ed25519 public key
/// - Next 32 bytes: second Ed25519 public key
/// - Remaining bytes (>= 8 bytes): shared secret
class MatrixQrVerificationPayload {
  MatrixQrVerificationPayload({
    required this.version,
    required this.mode,
    required this.transactionId,
    required this.firstKey,
    required this.secondKey,
    required this.sharedSecret,
    required Uint8List rawBytes,
  }) : rawBytes = Uint8List.fromList(rawBytes);

  static const String magicPrefix = 'MATRIX';
  static const List<int> _prefixBytes = [0x4D, 0x41, 0x54, 0x52, 0x49, 0x58];
  static const int supportedVersion = 0x02;
  static const int _headerSize = 10;
  static const int _ed25519KeyLength = 32;
  static const int _minSecretLength = 8;

  final int version;
  final QRMode mode;
  final String transactionId;
  final String firstKey;
  final String secondKey;
  final String sharedSecret;
  final Uint8List rawBytes;

  /// Encodes raw Matrix QR payload bytes as Base64 text for copying and pasting
  /// when no camera is available (desktop / web fallback).
  static String encodeText(Uint8List rawBytes) => base64Encode(rawBytes);

  /// Decodes user-provided QR payload text into raw bytes.
  ///
  /// Accepts Base64 / Base64URL (padded or unpadded, ignoring whitespace),
  /// hexadecimal strings representing a `MATRIX` header, or raw Latin-1
  /// binary strings starting with `"MATRIX"`.
  static Uint8List decodeInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const QrPayloadFormatException(QrPayloadParseError.empty);
    }

    // Raw binary/Latin-1 string directly starting with "MATRIX".
    if (trimmed.startsWith(magicPrefix) &&
        trimmed.codeUnits.every((unit) => unit <= 0xFF)) {
      return Uint8List.fromList(trimmed.codeUnits);
    }

    // Hexadecimal string (e.g. from external QR debuggers), optional 0x prefix.
    final hexCandidate = _stripHexFormatting(trimmed);
    if (hexCandidate != null) {
      return _decodeHex(hexCandidate);
    }

    // Standard Base64 or Base64URL, ignoring internal whitespace/line breaks.
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder == 1) {
      throw const QrPayloadFormatException(QrPayloadParseError.invalidEncoding);
    }
    final padded =
        remainder == 0 ? normalized : normalized + '=' * (4 - remainder);
    try {
      return Uint8List.fromList(base64Decode(padded));
    } on FormatException {
      throw const QrPayloadFormatException(QrPayloadParseError.invalidEncoding);
    }
  }

  /// Parses raw binary bytes of a Matrix QR code payload.
  static MatrixQrVerificationPayload parseBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const QrPayloadFormatException(QrPayloadParseError.empty);
    }
    if (bytes.length < _headerSize || !_hasMagicPrefix(bytes)) {
      throw const QrPayloadFormatException(QrPayloadParseError.invalidHeader);
    }

    final version = bytes[6];
    if (version != supportedVersion) {
      throw QrPayloadFormatException(
        QrPayloadParseError.unsupportedVersion,
        'version=$version',
      );
    }

    final modeCode = bytes[7];
    QRMode? mode;
    for (final candidate in QRMode.values) {
      if (candidate.code == modeCode) {
        mode = candidate;
        break;
      }
    }
    if (mode == null) {
      throw QrPayloadFormatException(
        QrPayloadParseError.invalidMode,
        'mode=$modeCode',
      );
    }

    final txnLen = ByteData.sublistView(bytes, 8, 10).getUint16(0, Endian.big);
    if (txnLen == 0) {
      throw const QrPayloadFormatException(
        QrPayloadParseError.invalidTransactionId,
      );
    }

    final keysOffset = _headerSize + txnLen;
    final secondKeyOffset = keysOffset + _ed25519KeyLength;
    final secretOffset = secondKeyOffset + _ed25519KeyLength;
    if (bytes.length < secretOffset + _minSecretLength) {
      throw const QrPayloadFormatException(QrPayloadParseError.truncated);
    }

    final String transactionId;
    try {
      transactionId = utf8.decode(
        bytes.sublist(_headerSize, keysOffset),
        allowMalformed: false,
      );
    } on FormatException {
      throw const QrPayloadFormatException(
        QrPayloadParseError.invalidTransactionId,
      );
    }
    if (transactionId.isEmpty) {
      throw const QrPayloadFormatException(
        QrPayloadParseError.invalidTransactionId,
      );
    }

    final firstKey = encodeBase64Unpadded(
      bytes.sublist(keysOffset, secondKeyOffset),
    );
    final secondKey = encodeBase64Unpadded(
      bytes.sublist(secondKeyOffset, secretOffset),
    );
    final sharedSecret = encodeBase64Unpadded(bytes.sublist(secretOffset));

    return MatrixQrVerificationPayload(
      version: version,
      mode: mode,
      transactionId: transactionId,
      firstKey: firstKey,
      secondKey: secondKey,
      sharedSecret: sharedSecret,
      rawBytes: bytes,
    );
  }

  /// Parses a text-encoded QR payload (Base64, Base64URL, hex or raw string).
  static MatrixQrVerificationPayload parseText(String input) =>
      parseBytes(decodeInput(input));

  /// Parses bytes loaded from a file: supports raw binary Matrix QR files as
  /// well as UTF-8 text files containing Base64 or hex payloads.
  static MatrixQrVerificationPayload parseFileBytes(Uint8List fileBytes) {
    if (fileBytes.isEmpty) {
      throw const QrPayloadFormatException(QrPayloadParseError.empty);
    }
    if (_hasMagicPrefix(fileBytes)) {
      return parseBytes(fileBytes);
    }
    try {
      final text = utf8.decode(fileBytes, allowMalformed: false);
      return parseText(text);
    } on FormatException {
      return parseBytes(fileBytes);
    }
  }

  /// Validates this payload's transaction ID, mode, and BOTH public keys
  /// (`firstKey` and `secondKey`) against the active [request].
  QrKeyValidationResult validateForRequest(KeyVerification request) {
    if (request.transactionId == null ||
        transactionId != request.transactionId) {
      return QrKeyValidationResult.transactionMismatch;
    }

    final client = request.client;
    final ownUserId = client.userID;
    final ownDeviceId = client.deviceID;
    final ownKeys = client.userDeviceKeys[ownUserId];
    final otherKeys = client.userDeviceKeys[request.userId];
    final ownMasterKey = ownKeys?.masterKey;
    final ownDeviceKey =
        ownDeviceId == null ? null : ownKeys?.getKey(ownDeviceId);
    final ownOtherDeviceKey =
        request.deviceId == null ? null : ownKeys?.getKey(request.deviceId!);
    final otherMasterKey = otherKeys?.masterKey;

    switch (mode) {
      case QRMode.verifyOtherUser:
        if (request.userId == ownUserId) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (!(ownMasterKey?.verified ?? false)) {
          return QrKeyValidationResult.unverifiedOwnMasterKey;
        }
        if (otherMasterKey?.ed25519Key == null ||
            ownMasterKey?.ed25519Key == null) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (firstKey != otherMasterKey!.ed25519Key ||
            secondKey != ownMasterKey!.ed25519Key) {
          return QrKeyValidationResult.keyMismatch;
        }
        return QrKeyValidationResult.valid;

      case QRMode.verifySelfTrusted:
        if (request.userId != ownUserId) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (ownMasterKey?.ed25519Key == null ||
            ownDeviceKey?.ed25519Key == null) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (firstKey != ownMasterKey!.ed25519Key ||
            secondKey != ownDeviceKey!.ed25519Key) {
          return QrKeyValidationResult.keyMismatch;
        }
        return QrKeyValidationResult.valid;

      case QRMode.verifySelfUntrusted:
        if (request.userId != ownUserId) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (!(ownMasterKey?.verified ?? false)) {
          return QrKeyValidationResult.unverifiedOwnMasterKey;
        }
        if (ownOtherDeviceKey?.ed25519Key == null ||
            ownMasterKey?.ed25519Key == null) {
          return QrKeyValidationResult.keyMismatch;
        }
        if (firstKey != ownOtherDeviceKey!.ed25519Key ||
            secondKey != ownMasterKey!.ed25519Key) {
          return QrKeyValidationResult.keyMismatch;
        }
        return QrKeyValidationResult.valid;
    }
  }

  static bool _hasMagicPrefix(Uint8List bytes) {
    if (bytes.length < _prefixBytes.length) return false;
    for (var i = 0; i < _prefixBytes.length; i++) {
      if (bytes[i] != _prefixBytes[i]) return false;
    }
    return true;
  }

  static String? _stripHexFormatting(String input) {
    var s = input;
    if (s.startsWith('0x') || s.startsWith('0X')) {
      s = s.substring(2);
    }
    s = s.replaceAll(RegExp(r'[\s:\-]+'), '');
    if (s.length >= 12 &&
        s.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(s) &&
        s.substring(0, 12).toLowerCase() == '4d4154524958') {
      return s;
    }
    return null;
  }

  static Uint8List _decodeHex(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
