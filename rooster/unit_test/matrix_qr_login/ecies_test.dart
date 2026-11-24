import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';

List<int> _unhex(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ];

const _initiate = 'MATRIX_QR_CODE_LOGIN_INITIATE';
const _ok = 'MATRIX_QR_CODE_LOGIN_OK';
const _protocols = '{"type":"m.login.protocols","protocols":'
    '["device_authorization_grant"],"homeserver":"https://matrix.example/"}';

void main() {
  // vodozemac-0.9.0/src/ecies/messages.rs, `mod test`.
  group('vodozemac 0.9 message encoding (src/ecies/messages.rs)', () {
    const initialMessage =
        '3On7QFJyLQMAErua9K/yIOcJALvuMYax1AW0iWgf64AwtSMZXwAA012Q|'
        '9yA/CX8pJKF02Prd75ZyBQHg3fGTVVGDNl86q1z17Us';
    const message = 'ZmtSLdzMcyjC5eV6L8xBI6amsq7gDNbCjz1W5OjX4Z8W';
    const publicKey = '9yA/CX8pJKF02Prd75ZyBQHg3fGTVVGDNl86q1z17Us';

    test('initial message decodes to its key and encodes back', () {
      final decoded = EciesInitialMessage.decode(initialMessage);
      expect(eciesBase64Encode(decoded.publicKey), publicKey);
      expect(decoded.encode(), initialMessage);
    });

    test('message encodes back the same', () {
      expect(EciesMessage.decode(message).encode(), message);
    });

    test('no separator, a short key or broken base64 is refused', () {
      expect(() => EciesInitialMessage.decode(message), throwsFormatException);
      expect(() => EciesInitialMessage.decode('AAAA|AAAA'),
          throwsA(isA<EciesException>()));
      expect(() => EciesMessage.decode('not*base64'), throwsFormatException);
    });
  });

  // vodozemac-0.9.0/src/ecies/mod.rs, `fn check_code()`.
  test('check code digits (src/ecies/mod.rs check_code)', () {
    expect(EciesCheckCode([0x00, 0x00]).digits, 0);
    expect(EciesCheckCode([0x09, 0x09]).digits, 99);
    expect(EciesCheckCode([0xff, 0xff]).digits, 55);
    expect(EciesCheckCode([0x00, 0x07]).display, '07');
  });

  // Made by vodozemac 0.9.0 itself (its `Ecies::new`, random keys on its
  // side) against Rooster's side with a fixed seed: the generator and its
  // output are kept with the task's evidence (`ecies-vectors/src/main.rs`,
  // `vectors.txt`). vodozemac checked every message Rooster wrote.
  group('interop with vodozemac 0.9', () {
    test('vodozemac opens the channel, Rooster is device G', () async {
      final g = await Ecies.fromSeed(_unhex(
          '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20'));
      expect(eciesBase64Encode(g.publicKey),
          'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw');
      final (channel, first) = await g.establishInbound(
          EciesInitialMessage.decode(
              '55fGurEza9TswabN79seoS6JaUKb3x5FCTVlhF09mL5FucpU23GyrJKQqHMI|'
              'T6JBl6hLU/xl7vyN7fWrQdtscHGEHMIYDctd2DMQNlE'));
      expect(utf8.decode(first), _initiate);
      expect(
          utf8.decode(await channel.decrypt(EciesMessage.decode(
              '8EkjDCJaCCqyLKkdKeG02aYpHxgwzwGTT3osnIkNOQi2WSMUo7LXCmeyoAQCqS'
              'Qwz7u7LNq3KHhNYRvvVRSdM5yQnt3fa7D/ZsmWNTg22spxX+z8w1zrYkcX08he'
              '061QQDtHVzDAgTyV6eD3UNK3idt+LlHEbVS+eOVbywMi'))),
          _protocols);
      expect(channel.checkCode.bytes, _unhex('65be'));
      expect(channel.checkCode.display, '10');
      // The reply vodozemac decrypted: G's first nonce and key.
      expect((await channel.encrypt(utf8.encode(_ok))).encode(),
          '/XnE7/OhwJ2k1osmGl3Ss2B6JiKjgLjE7Y6UUFmgD09kKerUNTE2');
    });

    test('Rooster opens the channel (device S), vodozemac is G', () async {
      final s = await Ecies.fromSeed(_unhex(
          '2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40'));
      final (channel, initial) = await s.establishOutbound(
          eciesBase64Decode('1+5KMAJ69rgJpGT8MhBcx3rsBO86pz5Tsn5Zua4xnXI'),
          utf8.encode(_initiate));
      // Byte for byte what vodozemac accepted.
      expect(
          initial.encode(),
          '5AjgFYF1E6Wc5MGVqL5HfTIDhYr3yIRLAtlBPJ28cB6mEXiBPyKOoK1wxNPn|'
          'WGmv9FBUlzLLqu1eXfmzCm2jHLDldCutWtShp2jxpns');
      expect(
          (await channel.encrypt(utf8.encode(_protocols))).encode(),
          'Q2tXg2OCh0tesxzklDsFACxumSqkUibg7qZJaD83eNdytoRA2xwJvyKyHGElmfsAHz'
          'lpqp34KMMdEkfwsGABhrLqrRezFvKEWjdr5Gpa4PBh+oXMTWO+3x9pzzF9GMXtG73'
          'A5hUbP32s20o69VxXWTjTajuRhuOLYk0vaGKJ');
      expect(channel.checkCode.bytes, _unhex('842b'));
      expect(channel.checkCode.display, '23');
      expect(
          utf8.decode(await channel.decrypt(EciesMessage.decode(
              'VQoA53BTC1reDnWfsLSdj/1HXI7BhVn7AVuL3unTJPQJMnJYfMIj'))),
          _ok);
    });
  });

  group('a channel between two Rooster devices', () {
    Future<(EstablishedEcies, EstablishedEcies)> pair() async {
      final g = await Ecies.create();
      final (s, initial) =
          await (await Ecies.create()).establishOutbound(g.publicKey, [1]);
      final (gChannel, _) = await g.establishInbound(initial);
      return (s, gChannel);
    }

    test('both sides derive the same check code and talk both ways', () async {
      final (s, g) = await pair();
      expect(s.checkCode, g.checkCode);
      final message = await g.encrypt(utf8.encode('hello'));
      expect(utf8.decode(await s.decrypt(message)), 'hello');
    });

    test('a changed byte does not decrypt', () async {
      final (s, g) = await pair();
      final message = await s.encrypt(utf8.encode('secret'));
      final changed = [...message.ciphertext]..[0] ^= 1;
      expect(g.decrypt(EciesMessage(changed)), throwsA(isA<EciesException>()));
    });

    test('a replayed or reordered message does not decrypt', () async {
      final (s, g) = await pair();
      await s.encrypt([1]);
      final second = await s.encrypt([2]);
      await expectLater(g.decrypt(second), throwsA(isA<EciesException>()));

      final (s2, g2) = await pair();
      final once = await s2.encrypt([1]);
      expect(await g2.decrypt(once), [1]);
      await expectLater(g2.decrypt(once), throwsA(isA<EciesException>()));
    });

    test('another opener key than the one that encrypted is refused', () async {
      // vodozemac's `invalid_check_code`: Malory swaps the public key.
      final g = await Ecies.create();
      final malory = await Ecies.create();
      final (_, initial) =
          await (await Ecies.create()).establishOutbound(g.publicKey, [1]);
      final swapped = EciesInitialMessage(malory.publicKey, initial.ciphertext);
      expect(g.establishInbound(swapped), throwsA(isA<EciesException>()));
    });

    test('a low-order key (no contributory behaviour) is refused', () async {
      final g = await Ecies.create();
      expect(g.establishInbound(EciesInitialMessage(List.filled(32, 0), [0])),
          throwsA(isA<EciesException>()));
    });
  });
}
