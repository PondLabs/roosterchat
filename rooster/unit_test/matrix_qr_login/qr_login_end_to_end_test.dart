import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';

import 'fake_rendezvous.dart';

const _secrets = QrLoginSecrets(
  masterKey: 'bWFzdGVyLXByaXZhdGUta2V5LTMyLWJ5dGVzLWxvbmcu',
  selfSigningKey: 'c2VsZi1zaWduaW5nLXByaXZhdGUta2V5LTMyLWJ5dGVz',
  userSigningKey: 'dXNlci1zaWduaW5nLXByaXZhdGUta2V5LTMyLWJ5dGVz',
  backupKey: 'YmFja3VwLXByaXZhdGUta2V5LTMyLWJ5dGVzLWxvbmcu',
  backupVersion: '7',
  backupAlgorithm: 'm.megolm_backup.v1.curve25519-aes-sha2',
);

/// The new device: the grant completes once the other device approved.
class _NewDevice implements QrLoginNewDeviceHost {
  final approved = Completer<bool>();
  QrLoginSecrets? imported;
  Uri? grantHomeserver;
  bool cancelled = false;

  @override
  Future<QrLoginGrant> startGrant(Uri homeserver) async {
    grantHomeserver = homeserver;
    return QrLoginGrant(
      deviceId: 'NEWDEVICE',
      verificationUri: Uri.parse('https://auth.example/device'),
      verificationUriComplete:
          Uri.parse('https://auth.example/device?code=ABCD'),
      signedIn: approved.future,
      cancel: () => cancelled = true,
    );
  }

  @override
  Future<void> importSecrets(QrLoginSecrets secrets) async =>
      imported = secrets;
}

class _ExistingDevice implements QrLoginExistingDeviceHost {
  _ExistingDevice(this.newDevice);

  final _NewDevice newDevice;
  final devices = <String>{'THISDEVICE'};
  Uri? approvedAt;
  int exports = 0;

  @override
  Uri get homeserver => Uri.parse('https://matrix.example');

  @override
  Future<void> approve(Uri verificationUri) async {
    approvedAt = verificationUri;
    // The person approves in the browser: the server makes the device.
    devices.add('NEWDEVICE');
    newDevice.approved.complete(true);
  }

  @override
  Future<bool> deviceExists(String deviceId) async =>
      devices.contains(deviceId);

  @override
  Future<QrLoginSecrets> exportSecrets() async {
    exports++;
    return _secrets;
  }
}

void main() {
  late FakeRendezvousServer server;
  late _NewDevice newDevice;
  late _ExistingDevice existing;

  setUp(() {
    server = FakeRendezvousServer();
    newDevice = _NewDevice();
    existing = _ExistingDevice(newDevice);
  });

  /// The new device makes the rendezvous and QR code; the signed-in one
  /// reads it (through the pasted text) and connects.
  Future<(QrSecureChannel, QrSecureChannel)> connect() async {
    final invite =
        await QrLoginInvite.create(server, server.endpoint, sleep: noSleep);
    final scanned = QrCodeData.fromText(invite.qrCode.toText());
    expect(scanned.mode, QrLoginMode.login);
    final accepted = invite.accept();
    final opened =
        await QrSecureChannel.connect(server, scanned, sleep: noSleep);
    return (await accepted, opened);
  }

  /// Its value or its error, so an early error is not an unhandled one.
  Future<Object?> settle(Future<Object?> future) =>
      future.then((value) => value, onError: (Object error) => error);

  Future<QrLoginSecrets> runExisting(QrSecureChannel channel) =>
      runQrLoginExistingDevice(channel, existing,
          sleep: noSleep, deviceChecks: 3);

  test('sign-in end to end: same check code, approval, secrets arrive',
      () async {
    final (g, s) = await connect();
    expect(g.checkCode, s.checkCode, reason: 'both derive the same code');
    expect(g.checkCode.digits, inInclusiveRange(0, 99));

    final steps = <QrLoginStep>[];
    final sent = settle(runExisting(s));
    await runQrLoginNewDevice(g, newDevice,
        typedCheckCode: s.checkCode.digits, onStep: steps.add);

    expect(await sent, same(_secrets));
    expect(existing.exports, 1);
    expect(existing.approvedAt,
        Uri.parse('https://auth.example/device?code=ABCD'));
    expect(newDevice.grantHomeserver, Uri.parse('https://matrix.example'));
    expect(newDevice.imported?.toMessage(), _secrets.toMessage());
    expect(steps, [
      QrLoginStep.waitingForApproval,
      QrLoginStep.signingIn,
      QrLoginStep.sharingKeys,
      QrLoginStep.done,
    ]);
    // The rendezvous is deleted at the end, and nothing in it was clear.
    expect(server.sessions, isEmpty);
    for (final body in server.written) {
      expect(body, isNot(contains('m.login')));
      expect(body, isNot(contains(_secrets.masterKey!)));
    }
  });

  test('the secrets never show in toString', () {
    final text =
        '$_secrets ${QrLoginSecrets.fromMessage(_secrets.toMessage())}';
    for (final value in [
      _secrets.masterKey!,
      _secrets.selfSigningKey!,
      _secrets.userSigningKey!,
      _secrets.backupKey!,
    ]) {
      expect(text, isNot(contains(value)));
    }
  });

  test('a refused check code sends m.login.failure and deletes the channel',
      () async {
    final (g, s) = await connect();
    final sent = settle(runExisting(s));
    final wrong = (s.checkCode.digits + 1) % 100;

    await expectLater(
        runQrLoginNewDevice(g, newDevice, typedCheckCode: wrong),
        throwsA(isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.checkCodeMismatch)));
    expect(newDevice.grantHomeserver, isNull, reason: 'no sign-in started');
    expect(server.log.last, startsWith('DELETE'));
    expect(server.sessions, isEmpty);

    // The signed-in device read the failure (or found the channel gone),
    // and sent nothing.
    expect(await sent, isA<QrLoginException>());
    expect(existing.exports, 0);
  });

  test('the failure reaches the signed-in device even over its message',
      () async {
    server.ignoreDeletes = true;
    final (g, s) = await connect();
    // The signed-in device has written m.login.protocols, unread: the
    // failure replaces it (412, then the current ETag).
    await s.send({'type': 'm.login.protocols'});
    await g.fail('user_cancelled');
    await expectLater(
        s.receive({'m.login.protocol'}),
        throwsA(isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.cancelled)));
  });

  test('a changed message fails to decrypt: nothing applied, channel deleted',
      () async {
    final (g, s) = await connect();
    // Flip one ciphertext bit of everything written from now on.
    server.onPut = (body) {
      final bytes = eciesBase64Decode(body);
      bytes[3] ^= 0x01;
      return eciesBase64Encode(bytes);
    };
    final sent = settle(runExisting(s));
    await expectLater(
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits),
        throwsA(isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.insecure)));
    expect(newDevice.grantHomeserver, isNull);
    expect(newDevice.imported, isNull);
    expect(server.sessions, isEmpty);
    expect(await sent, isA<QrLoginException>());
    expect(existing.exports, 0);
  });

  test('a replayed (out of order) message fails: nothing applied', () async {
    final (g, s) = await connect();
    await s.send({
      'type': 'm.login.protocols',
      'protocols': [qrLoginDeviceGrant],
      'homeserver': 'https://matrix.example',
    });
    // The earlier INITIATE put back in place of m.login.protocols, as
    // someone replaying the channel would.
    server.inject(server.written[0].split('|').first);
    await expectLater(
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits),
        throwsA(isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.insecure)));
    expect(newDevice.grantHomeserver, isNull);
    expect(newDevice.imported, isNull);
    expect(server.sessions, isEmpty);
  });

  test('a secrets message from before the sign-in is not accepted', () async {
    final (g, s) = await connect();
    // A signed-in device that skips the protocol and sends the keys first.
    await s.send(_secrets.toMessage());
    await expectLater(
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits),
        throwsA(isA<QrLoginException>()));
    expect(newDevice.imported, isNull);
    expect(server.sessions, isEmpty);
  });

  test('a device ID the account already has is refused before approval',
      () async {
    existing.devices.add('NEWDEVICE');
    final (g, s) = await connect();
    final sent = settle(runExisting(s));
    await expectLater(
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits),
        throwsA(isA<QrLoginException>().having(
            (e) => e.error, 'error', QrLoginError.deviceAlreadyExists)));
    expect(newDevice.cancelled, isTrue, reason: 'the grant stops polling');
    expect(
        await sent,
        isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.deviceAlreadyExists));
    expect(existing.approvedAt, isNull);
    expect(existing.exports, 0);
  });

  group('an expired channel ends with a localized message', () {
    for (final status in [404, 410]) {
      test('HTTP $status while waiting for the other device', () async {
        final invite =
            await QrLoginInvite.create(server, server.endpoint, sleep: noSleep);
        server.forceStatus = status;
        await expectLater(
            invite.accept(),
            throwsA(isA<QrLoginException>()
                .having((e) => e.error, 'error', QrLoginError.expired)
                .having((e) => e.error.message, 'message',
                    QrLoginError.errorQrLoginExpired)));
        expect(server.log.last, startsWith('DELETE'));
      });

      test('HTTP $status in the middle of the sign-in', () async {
        final (g, s) = await connect();
        server.forceStatus = status;
        await expectLater(
            runQrLoginNewDevice(g, newDevice,
                typedCheckCode: s.checkCode.digits),
            throwsA(isA<QrLoginException>()
                .having((e) => e.error, 'error', QrLoginError.expired)));
        await expectLater(
            runExisting(s),
            throwsA(isA<QrLoginException>()
                .having((e) => e.error, 'error', QrLoginError.expired)));
        expect(existing.exports, 0);
      });
    }

    test('the message is English text, not a key', () {
      expect(QrLoginError.expired.message,
          'The QR code expired or was closed. Start again to get a new one.');
    });
  });

  test('a declined sign-in on the signed-in device stops the new device',
      () async {
    final (g, s) = await connect();
    final done =
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits);
    await s.send({
      'type': 'm.login.protocols',
      'protocols': [qrLoginDeviceGrant],
      'homeserver': 'https://matrix.example',
    });
    await s.receive({'m.login.protocol'});
    await s.send({'type': 'm.login.declined'});
    await expectLater(
        done,
        throwsA(isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.declined)));
    expect(newDevice.cancelled, isTrue, reason: 'the grant stops polling');
    expect(newDevice.imported, isNull);
  });
}
