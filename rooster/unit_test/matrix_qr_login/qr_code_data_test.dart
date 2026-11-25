import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';

final _key = List<int>.generate(32, (i) => i + 1);
final _url = Uri.parse(
    'https://matrix.example/_matrix/client/unstable/org.matrix.msc4108/rendezvous/abc');

Matcher _refused(String why) => throwsA(isA<QrCodeDataException>()
    .having((e) => e.message, 'message', contains(why)));

void main() {
  test('a login code is MATRIX, 0x02, 0x03, the key, then the URL', () {
    final bytes = QrCodeData(
            mode: QrLoginMode.login, publicKey: _key, rendezvousUrl: _url)
        .toBytes();
    final url = utf8.encode(_url.toString());
    expect(bytes, [
      ...ascii.encode('MATRIX'),
      0x02,
      0x03,
      ..._key,
      url.length >> 8,
      url.length & 0xff,
      ...url,
    ]);
    final back = QrCodeData.fromBytes(bytes);
    expect(back.mode, QrLoginMode.login);
    expect(back.publicKey, _key);
    expect(back.rendezvousUrl, _url);
    expect(back.serverName, isNull);
  });

  test('a reciprocate code (0x04) carries the server name after the URL', () {
    final data = QrCodeData(
        mode: QrLoginMode.reciprocate,
        publicKey: _key,
        rendezvousUrl: _url,
        serverName: 'example.org');
    final bytes = data.toBytes();
    expect(bytes[7], 0x04);
    expect(bytes.sublist(bytes.length - 13),
        [0, 11, ...ascii.encode('example.org')]);
    final back = QrCodeData.fromBytes(bytes);
    expect(back.serverName, 'example.org');
    expect(back.mode, QrLoginMode.reciprocate);
  });

  test('the pasted text is the same bytes in base64', () {
    final data = QrCodeData(
        mode: QrLoginMode.login, publicKey: _key, rendezvousUrl: _url);
    final text = data.toText();
    expect(base64.decode(text), data.toBytes());
    // Whitespace from copying across lines is ignored.
    final back = QrCodeData.fromText(
        ' ${text.substring(0, 20)}\n${text.substring(20)} ');
    expect(back.rendezvousUrl, _url);
    expect(() => QrCodeData.fromText('not a code!'), _refused('base64'));
  });

  group('refuses', () {
    final good = QrCodeData(
            mode: QrLoginMode.reciprocate,
            publicKey: _key,
            rendezvousUrl: _url,
            serverName: 'example.org')
        .toBytes();

    test('every truncation', () {
      for (var length = 0; length < good.length; length++) {
        expect(() => QrCodeData.fromBytes(good.sublist(0, length)),
            throwsA(isA<QrCodeDataException>()),
            reason: 'cut at $length bytes');
      }
    });

    test('another magic', () {
      expect(
          () => QrCodeData.fromBytes(
              [...ascii.encode('MATRIZ'), ...good.sublist(6)]),
          _refused('Not a login QR code'));
      expect(() => QrCodeData.fromBytes(ascii.encode('https://example.org')),
          _refused('Not a login QR code'));
    });

    test('an unknown version', () {
      for (final version in [0x00, 0x01, 0x03, 0xff]) {
        expect(() => QrCodeData.fromBytes([...good]..[6] = version),
            _refused('Unknown version $version'));
      }
    });

    test('an unknown mode (the verification modes 0x00-0x02 included)', () {
      for (final mode in [0x00, 0x01, 0x02, 0x05]) {
        expect(() => QrCodeData.fromBytes([...good]..[7] = mode),
            _refused('Unknown mode $mode'));
      }
    });

    test('bytes after the payload', () {
      expect(() => QrCodeData.fromBytes([...good, 0]),
          _refused('Bytes after the payload'));
    });

    test('a rendezvous URL that is not http(s), or not UTF-8', () {
      QrCodeData withUrl(String url) => QrCodeData(
          mode: QrLoginMode.login,
          publicKey: _key,
          rendezvousUrl: Uri.parse(url));
      expect(
          () => QrCodeData.fromBytes(withUrl('javascript:alert(1)').toBytes()),
          _refused('rendezvous URL'));
      final bytes = withUrl('https://a').toBytes();
      expect(() => QrCodeData.fromBytes([...bytes]..[bytes.length - 1] = 0xff),
          _refused('UTF-8'));
    });

    test('a key that is not 32 bytes', () {
      expect(
          () => QrCodeData(
              mode: QrLoginMode.login, publicKey: [1, 2], rendezvousUrl: _url),
          _refused('32 bytes'));
    });
  });
}
