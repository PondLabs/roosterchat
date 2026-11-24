// The QR code login guards that only a test proves are there: no secrets
// before the new device shows up on the account, a refused check code
// reaching the signed-in device as m.login.failure, no nonce used twice,
// and no cross-signing key kept unless it is the account's published one.
// From the review of T5.3.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';
import 'package:rooster/client/matrix/auth/qr_login/matrix_qr_login.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../matrix_auth_oidc/oidc_fakes.dart'
    show initVodozemac, skipWithoutVodozemac;
import 'fake_rendezvous.dart';

const _secrets = QrLoginSecrets(
  masterKey: 'bWFzdGVyLXByaXZhdGUta2V5LTMyLWJ5dGVzLWxvbmcu',
  selfSigningKey: 'c2VsZi1zaWduaW5nLXByaXZhdGUta2V5LTMyLWJ5dGVz',
);

class _NewDevice implements QrLoginNewDeviceHost {
  final approved = Completer<bool>();
  QrLoginSecrets? imported;

  @override
  Future<QrLoginGrant> startGrant(Uri homeserver) async => QrLoginGrant(
        deviceId: 'NEWDEVICE',
        verificationUri: Uri.parse('https://auth.example/device'),
        signedIn: approved.future,
        cancel: () {},
      );

  @override
  Future<void> importSecrets(QrLoginSecrets secrets) async =>
      imported = secrets;
}

/// A signed-in device whose server never lists the new device (it lied
/// about m.login.success, or signed in under another ID).
class _Existing implements QrLoginExistingDeviceHost {
  _Existing(this.newDevice);
  final _NewDevice newDevice;
  int exports = 0;

  @override
  Uri get homeserver => Uri.parse('https://matrix.example');

  @override
  Future<void> approve(Uri verificationUri) async =>
      newDevice.approved.complete(true);

  @override
  Future<bool> deviceExists(String deviceId) async => false;

  @override
  Future<bool> trusts(Uri verificationUri) async => true;

  @override
  Future<QrLoginSecrets> exportSecrets() async {
    exports++;
    return _secrets;
  }
}

void main() {
  test('no secrets leave when the new device never shows up on the account',
      () async {
    final server = FakeRendezvousServer();
    final newDevice = _NewDevice();
    final existing = _Existing(newDevice);
    final invite =
        await QrLoginInvite.create(server, server.endpoint, sleep: noSleep);
    final accepted = invite.accept();
    final s = await QrSecureChannel.connect(
        server, QrCodeData.fromText(invite.qrCode.toText()),
        sleep: noSleep);
    final g = await accepted;
    final sent =
        runQrLoginExistingDevice(s, existing, sleep: noSleep, deviceChecks: 2)
            .then<Object?>((v) => v, onError: (Object e) => e);
    final got =
        runQrLoginNewDevice(g, newDevice, typedCheckCode: s.checkCode.digits)
            .then<Object?>((v) => v, onError: (Object e) => e);
    expect(
        await sent,
        isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.deviceNotFound));
    expect(existing.exports, 0);
    expect(await got, isA<QrLoginException>());
    expect(newDevice.imported, isNull);
    for (final body in server.written) {
      expect(body, isNot(contains(_secrets.masterKey!)));
    }
  });

  test('a refused check code: the signed-in device reads m.login.failure',
      () async {
    final server = FakeRendezvousServer();
    final invite =
        await QrLoginInvite.create(server, server.endpoint, sleep: noSleep);
    final accepted = invite.accept();
    final s = await QrSecureChannel.connect(
        server, QrCodeData.fromText(invite.qrCode.toText()),
        sleep: noSleep);
    final g = await accepted;
    final reader = (s.receive({'m.login.protocol'}))
        .then<Object?>((v) => v, onError: (Object e) => e);
    await expectLater(
        runQrLoginNewDevice(g, _NewDevice(),
            typedCheckCode: (s.checkCode.digits + 1) % 100),
        throwsA(isA<QrLoginException>()));
    // m.login.failure, not just the channel gone (expired).
    expect(
        await reader,
        isA<QrLoginException>()
            .having((e) => e.error, 'error', QrLoginError.cancelled));
    expect(server.deletes, greaterThan(0));
  });

  test('ecies: no nonce is used twice in one direction', () async {
    final g = await Ecies.create();
    final (s, _) =
        await (await Ecies.create()).establishOutbound(g.publicKey, [1]);
    final a = await s.encrypt([0, 0, 0, 0]);
    final b = await s.encrypt([0, 0, 0, 0]);
    expect(a.encode(), isNot(b.encode()));
  });

  test('a cross-signing key that is not the one of the account is never kept',
      skip: skipWithoutVodozemac, () async {
    sqfliteFfiInit();
    await initVodozemac();
    final database = await matrix.MatrixSdkDatabase.init('qr_login_guards',
        database: await databaseFactoryFfi.openDatabase(':memory:',
            options: OpenDatabaseOptions(singleInstance: false)),
        sqfliteFactory: databaseFactoryFfi);
    final mx = matrix.Client('qr_login_guards',
        httpClient: FakeMatrixApi(), database: database);
    FakeMatrixApi.client = mx;
    await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await mx.init(
      newToken: 'abcd',
      newUserID: '@test:fakeServer.notExisting',
      newHomeserver: mx.homeserver,
      newDeviceName: 'test',
      newDeviceID: 'GHTYAJCE',
    );
    await mx.abortSync();
    expect(mx.encryption, isNotNull);
    // The account publishes a master key (FakeMatrixApi /keys/query) and
    // has it in secret storage: the only thing between a wrong key and
    // the cache is the public key comparison.
    expect(mx.accountData[matrix.EventTypes.CrossSigningMasterKey], isNotNull);
    await importQrLoginSecrets(
        mx,
        QrLoginSecrets(
            masterKey: eciesBase64Encode(List.filled(32, 7)),
            selfSigningKey: eciesBase64Encode(List.filled(32, 8))));
    expect(
        await mx.database.getSSSSCache(matrix.EventTypes.CrossSigningMasterKey),
        isNull);
    expect(
        await mx.database
            .getSSSSCache(matrix.EventTypes.CrossSigningSelfSigning),
        isNull);
  });
}
