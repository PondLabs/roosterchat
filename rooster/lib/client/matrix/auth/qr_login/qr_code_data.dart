/// What a QR code login QR code holds (MSC4108, version 2), as Element X and
/// the matrix-rust-sdk write it:
///
/// | bytes | what |
/// |---|---|
/// | 6 | `MATRIX` |
/// | 1 | version, `0x02` |
/// | 1 | mode: `0x03` a new device asks to sign in, `0x04` a signed-in device offers it |
/// | 32 | the Curve25519 public key of the ECIES channel |
/// | 2 + n | the rendezvous URL, UTF-8, its length big-endian |
/// | 2 + n | `0x04` only: the homeserver's server name, the same way |
///
/// The same bytes in base64 are the code a person pastes when the other
/// device has no camera.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';

enum QrLoginMode {
  /// Shown by the device that wants to sign in.
  login(0x03),

  /// Shown by a signed-in device, with its homeserver.
  reciprocate(0x04);

  const QrLoginMode(this.byte);
  final int byte;
}

class QrCodeDataException implements FormatException {
  const QrCodeDataException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'QrCodeDataException($message)';
}

class QrCodeData {
  QrCodeData({
    required this.mode,
    required List<int> publicKey,
    required this.rendezvousUrl,
    this.serverName,
  }) : publicKey = Uint8List.fromList(publicKey) {
    if (publicKey.length != 32) {
      throw const QrCodeDataException('The public key is not 32 bytes');
    }
    if ((mode == QrLoginMode.reciprocate) != (serverName != null)) {
      throw const QrCodeDataException('A server name goes with 0x04 only');
    }
  }

  static const prefix = 'MATRIX';
  static const version = 0x02;

  final QrLoginMode mode;
  final Uint8List publicKey;
  final Uri rendezvousUrl;
  final String? serverName;

  Uint8List toBytes() {
    final out = BytesBuilder()
      ..add(ascii.encode(prefix))
      ..addByte(version)
      ..addByte(mode.byte)
      ..add(publicKey);
    void addString(String value) {
      final bytes = utf8.encode(value);
      if (bytes.length > 0xffff) {
        throw const QrCodeDataException('Too long for a QR code');
      }
      out
        ..addByte(bytes.length >> 8)
        ..addByte(bytes.length & 0xff)
        ..add(bytes);
    }

    addString(rendezvousUrl.toString());
    if (serverName != null) addString(serverName!);
    return out.toBytes();
  }

  /// The text a person can paste instead of scanning.
  String toText() => base64.encode(toBytes());

  static QrCodeData fromText(String text) {
    try {
      return fromBytes(eciesBase64Decode(text.replaceAll(RegExp(r'\s'), '')));
    } on QrCodeDataException {
      rethrow;
    } on FormatException {
      throw const QrCodeDataException('Not base64');
    }
  }

  /// Throws [QrCodeDataException] for another prefix, an unknown version
  /// or mode, a cut payload, bytes left over, or a URL that is not http(s).
  /// Plain http is allowed like the homeserver field allows it (a server
  /// on a LAN): what goes through the rendezvous is encrypted end to end.
  static QrCodeData fromBytes(List<int> bytes) {
    var at = 0;
    List<int> take(int n) {
      if (at + n > bytes.length) {
        throw const QrCodeDataException('Truncated');
      }
      return bytes.sublist(at, at += n);
    }

    String takeString() {
      final length = take(2);
      try {
        return utf8.decode(take(length[0] << 8 | length[1]));
      } on FormatException {
        throw const QrCodeDataException('Not UTF-8');
      }
    }

    if (bytes.length < prefix.length ||
        ascii.decode(take(prefix.length), allowInvalid: true) != prefix) {
      throw const QrCodeDataException('Not a login QR code');
    }
    final version = take(1).single;
    if (version != QrCodeData.version) {
      throw QrCodeDataException('Unknown version $version');
    }
    final modeByte = take(1).single;
    final mode = QrLoginMode.values.where((m) => m.byte == modeByte);
    if (mode.isEmpty) throw QrCodeDataException('Unknown mode $modeByte');
    final publicKey = take(32);
    final url = Uri.tryParse(takeString());
    final serverName =
        mode.single == QrLoginMode.reciprocate ? takeString() : null;
    if (at != bytes.length) {
      throw const QrCodeDataException('Bytes after the payload');
    }
    if (url == null || !isAllowedRendezvousUrl(url)) {
      throw const QrCodeDataException('Not an http(s) rendezvous URL');
    }
    return QrCodeData(
      mode: mode.single,
      publicKey: publicKey,
      rendezvousUrl: url,
      serverName: serverName,
    );
  }

  static bool isAllowedRendezvousUrl(Uri url) =>
      url.host.isNotEmpty && (url.scheme == 'https' || url.scheme == 'http');
}
