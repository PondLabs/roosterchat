import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_export_format.dart';

/// Element's test vector (`MegolmExportEncryption-test`): "plain" under
/// the passphrase "password", salt "saltsaltsaltsalt", an IV of 0x88 and
/// 10 rounds. Reading it proves the layout, the key derivation, the HMAC
/// and AES-CTR are the spec's.
const _elementVector = '-----BEGIN MEGOLM SESSION DATA-----\n'
    'AXNhbHRzYWx0c2FsdHNhbHSIiIiIiIiIiIiIiIiIiIiIAAAACmIRUW2OjZ3L2l6j9h0lHlV3M2dx\n'
    'cissyYBxjsfsAndErh065A8=\n'
    '-----END MEGOLM SESSION DATA-----';

const _passphrase = 'correct horse battery';

final _sessions = <Map<String, Object?>>[
  {
    'algorithm': 'm.megolm.v1.aes-sha2',
    'forwarding_curve25519_key_chain': <String>[],
    'room_id': '!room:example.test',
    'sender_key': 'senderkey',
    'sender_claimed_keys': {'ed25519': 'claimed'},
    'session_id': 'sessionid',
    'session_key': 'sessionkey',
  },
];

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// The base64 inside a file, decoded.
Uint8List _body(String file) => base64.decode(const LineSplitter()
    .convert(file)
    .where((line) => !line.startsWith('-----'))
    .join());

/// [body] back between the file's header and trailer.
String _armor(List<int> body) => '${MegolmExportFormat.header}\n'
    '${base64.encode(body)}\n${MegolmExportFormat.trailer}\n';

Matcher _fails(MegolmExportError error) => throwsA(
    isA<MegolmExportException>().having((e) => e.error, 'error', error));

void main() {
  test("reads Element's test vector", () async {
    final plain = await MegolmExportFormat.decryptBytes(
        _bytes(_elementVector), 'password');
    expect(utf8.decode(plain), 'plain');
  });

  test('a file it writes reads back with the passphrase', () async {
    final file = await MegolmExportFormat.encrypt(_sessions, _passphrase,
        rounds: 1000, random: Random(1));
    expect(
        await MegolmExportFormat.decrypt(_bytes(file), _passphrase), _sessions);
  });

  test('writes the spec layout between the BEGIN and END lines', () async {
    final file = await MegolmExportFormat.encrypt(
        List.filled(40, _sessions.first), _passphrase,
        rounds: 1234, random: Random(2));
    final lines = const LineSplitter().convert(file);
    expect(lines.first, '-----BEGIN MEGOLM SESSION DATA-----');
    expect(lines.last, '-----END MEGOLM SESSION DATA-----');
    expect(file, endsWith('\n'));
    // 96 bytes a line, as Element writes them: no padding but at the end.
    final body = lines.sublist(1, lines.length - 1);
    expect(body.length, greaterThan(2));
    for (final line in body.take(body.length - 1)) {
      expect(line.length, 128);
      expect(line, isNot(contains('=')));
    }

    final data = _body(file);
    expect(data[0], 1, reason: 'version');
    expect(ByteData.sublistView(data, 33, 37).getUint32(0), 1234,
        reason: 'the rounds, big-endian after the salt and the IV');
    expect(data[17 + 8] & 0x80, 0, reason: "the IV's bit 63 is clear");
  });

  test('writes 500 000 rounds unless told otherwise', () {
    expect(MegolmExportFormat.defaultRounds, 500000);
  });

  test('a wrong passphrase fails', () async {
    final file =
        await MegolmExportFormat.encrypt(_sessions, _passphrase, rounds: 1000);
    expect(MegolmExportFormat.decrypt(_bytes(file), 'wrong passphrase'),
        _fails(MegolmExportError.wrongPassphrase));
  });

  test('a file cut short fails', () async {
    final file = await MegolmExportFormat.encrypt(
        List.filled(10, _sessions.first), _passphrase,
        rounds: 1000);
    // Its second half lost, trailer and all.
    final half = file.substring(0, file.length ~/ 2);
    expect(MegolmExportFormat.decrypt(_bytes(half), _passphrase),
        _fails(MegolmExportError.damaged));

    // Its last bytes lost, the trailer still there: the HMAC is not the
    // one of what is left.
    final data = _body(file);
    final cut = _armor(data.sublist(0, data.length - 7));
    expect(MegolmExportFormat.decrypt(_bytes(cut), _passphrase),
        _fails(MegolmExportError.wrongPassphrase));

    // Shorter than a header and a MAC.
    final stub = _armor(data.sublist(0, 60));
    expect(MegolmExportFormat.decrypt(_bytes(stub), _passphrase),
        _fails(MegolmExportError.damaged));
  });

  test('a changed byte fails', () async {
    final file =
        await MegolmExportFormat.encrypt(_sessions, _passphrase, rounds: 1000);
    final data = _body(file);
    data[40] ^= 1;
    expect(MegolmExportFormat.decrypt(_bytes(_armor(data)), _passphrase),
        _fails(MegolmExportError.wrongPassphrase));
  });

  test('another version fails', () async {
    final file =
        await MegolmExportFormat.encrypt(_sessions, _passphrase, rounds: 1000);
    final data = _body(file)..[0] = 2;
    expect(MegolmExportFormat.decrypt(_bytes(_armor(data)), _passphrase),
        _fails(MegolmExportError.damaged));
  });

  group('a round count above the ceiling', () {
    /// A good 1000-round file whose header now asks for [rounds].
    Future<Uint8List> asking(int rounds) async {
      final file = await MegolmExportFormat.encrypt(_sessions, _passphrase,
          rounds: 1000, random: Random(3));
      final data = _body(file);
      ByteData.sublistView(data, 33, 37).setUint32(0, rounds);
      return _bytes(_armor(data));
    }

    // Deriving the key for that many rounds takes from minutes to hours:
    // the timeout fails the test if anything starts it.
    for (final rounds in [0xFFFFFFFF, MegolmExportFormat.maxRounds + 1]) {
      test('$rounds is a damaged file, refused before any key derivation',
          timeout: const Timeout(Duration(seconds: 10)), () async {
        final file = await asking(rounds);
        final clock = Stopwatch()..start();
        await expectLater(MegolmExportFormat.decrypt(file, _passphrase),
            _fails(MegolmExportError.damaged));
        expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      });
    }

    test('the ceiling is well above what clients write', () {
      expect(MegolmExportFormat.maxRounds, 10000000);
      expect(MegolmExportFormat.maxRounds,
          greaterThan(MegolmExportFormat.defaultRounds));
    });

    test('is never written', timeout: const Timeout(Duration(seconds: 10)),
        () async {
      for (final rounds in [0, MegolmExportFormat.maxRounds + 1]) {
        await expectLater(
            MegolmExportFormat.encrypt(_sessions, _passphrase, rounds: rounds),
            throwsArgumentError);
      }
    });
  });

  test('broken base64 fails', () async {
    final broken =
        '${MegolmExportFormat.header}\nnot*base64!\n${MegolmExportFormat.trailer}';
    expect(MegolmExportFormat.decrypt(_bytes(broken), _passphrase),
        _fails(MegolmExportError.damaged));
  });

  test('a file that is not a key export fails', () async {
    expect(MegolmExportFormat.decrypt(_bytes('hello'), _passphrase),
        _fails(MegolmExportError.notAKeyExport));
    expect(
        MegolmExportFormat.decrypt(
            Uint8List.fromList([0xff, 0xfe, 0x00, 0xc3]), _passphrase),
        _fails(MegolmExportError.notAKeyExport));
  });

  test('a file that decrypts to no list of sessions fails', () async {
    final notAList = await MegolmExportFormat.encryptBytes(
        utf8.encode('{"rooms": []}'), _passphrase,
        rounds: 1000);
    expect(MegolmExportFormat.decrypt(_bytes(notAList), _passphrase),
        _fails(MegolmExportError.invalidContent));
    expect(MegolmExportFormat.decrypt(_bytes(_elementVector), 'password'),
        _fails(MegolmExportError.invalidContent));
  });

  test('reads a file with Windows line ends and blank lines around it',
      () async {
    final file =
        await MegolmExportFormat.encrypt(_sessions, _passphrase, rounds: 1000);
    final windows = '\r\n\r\n${file.replaceAll('\n', '\r\n')}\r\n';
    expect(await MegolmExportFormat.decrypt(_bytes(windows), _passphrase),
        _sessions);
  });
}
