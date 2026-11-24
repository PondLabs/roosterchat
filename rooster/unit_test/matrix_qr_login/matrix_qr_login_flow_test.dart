// QR code login on a real Rooster account: the new device signs in with
// the device grant and token exchange of "Sign in from another device"
// (T2.1b's fakes), under the device ID it announced to the signed-in
// device, and keeps only the secrets that match the account's keys.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/qr_login/matrix_qr_login.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'qr_homeserver.dart';

class _SignedInDevice implements QrLoginExistingDeviceHost {
  _SignedInDevice(this.homeserver, {this.secrets = const QrLoginSecrets()});

  @override
  final Uri homeserver;
  final QrLoginSecrets secrets;
  final looks = <String>[];
  bool approved = false;

  @override
  Future<void> approve(Uri verificationUri) async => approved = true;

  /// Not there before the approval, there after it.
  @override
  Future<bool> deviceExists(String deviceId) async {
    looks.add(deviceId);
    return approved;
  }

  @override
  Future<QrLoginSecrets> exportSecrets() async => secrets;
}

void main() {
  group('MatrixQrLoginFlow', skip: skipWithoutVodozemac, () {
    setUpAll(initVodozemac);

    Future<(QrHomeserver, MatrixClient, QrSecureChannel, QrSecureChannel)>
        connect() async {
      final server = QrHomeserver(
          DeviceGrantServer(answers: [DeviceGrantServer.tokens()]));
      final client = await newAccount(server);
      final (ok, _) = await client.setHomeserver(Uri.https(homeserverHost));
      expect(ok, isTrue);
      final invite = await QrLoginInvite.create(
          server, server.rendezvous.endpoint,
          sleep: noSleep);
      final accepted = invite.accept();
      final s = await QrSecureChannel.connect(
          server, QrCodeData.fromText(invite.qrCode.toText()),
          sleep: noSleep);
      return (server, client, await accepted, s);
    }

    test('signs in with the device ID the signed-in device was told', () async {
      final (server, client, g, s) = await connect();
      final mx = client.getMatrixClient();
      final existing = _SignedInDevice(mx.homeserver!,
          secrets: QrLoginSecrets(
              // Keys of no account: checked, then dropped.
              masterKey: base64.encode(List.filled(32, 1)).replaceAll('=', ''),
              selfSigningKey:
                  base64.encode(List.filled(32, 2)).replaceAll('=', '')));
      final clock = FakeDeviceGrantClock();
      final flow = MatrixQrLoginFlow(
          channel: g,
          typedCheckCode: s.checkCode.digits,
          authMetadata: client.authMetadata!,
          clock: clock);

      final sent = runQrLoginExistingDevice(s, existing, sleep: noSleep);
      final result = flow.submit(client);
      await clock.fireNext();

      expect(await result, isA<LoginResultSuccess>());
      expect(mx.isLogged(), isTrue);
      expect(mx.accessToken, 'device-access-token');
      expect((await sent).masterKey, isNotNull);

      // One device authorization, under the scope of the announced ID.
      final scope = Uri.splitQueryString(
          server.grant.deviceRequests.single.body)['scope']!;
      final announced = existing.looks.first;
      expect(scope, contains('device:$announced'));
      expect(server.grant.tokenPolls, hasLength(1));
      // Secrets that match no published key are not kept.
      expect(
          await mx.database
              .getSSSSCache(matrix.EventTypes.CrossSigningMasterKey),
          isNull);
      expect(server.rendezvous.sessions, isEmpty);
    });

    test('another homeserver than the chosen one: no grant, a clear error',
        () async {
      final (server, client, g, s) = await connect();
      final existing =
          _SignedInDevice(Uri.parse('https://other-server.example'));
      final flow = MatrixQrLoginFlow(
          channel: g,
          typedCheckCode: s.checkCode.digits,
          authMetadata: client.authMetadata!);

      final sent = runQrLoginExistingDevice(s, existing, sleep: noSleep)
          .then<Object?>((v) => v, onError: (Object e) => e);
      final result = await flow.submit(client);

      expect(result, isA<LoginResultError>());
      expect((result as LoginResultError).errorMessage,
          QrLoginError.errorQrLoginHomeserverMismatch);
      expect(server.grant.deviceRequests, isEmpty);
      expect(await sent, isA<QrLoginException>());
      expect(existing.approved, isFalse);
    });

    test('a wrong check code: no grant, nothing signed in', () async {
      final (server, client, g, s) = await connect();
      final flow = MatrixQrLoginFlow(
          channel: g,
          typedCheckCode: (s.checkCode.digits + 50) % 100,
          authMetadata: client.authMetadata!);
      final result = await flow.submit(client);
      expect((result as LoginResultError).errorMessage,
          QrLoginError.errorQrLoginCheckCodeMismatch);
      expect(server.grant.deviceRequests, isEmpty);
      expect(client.getMatrixClient().isLogged(), isFalse);
      expect(server.rendezvous.log.last, startsWith('DELETE'));
    });
  });
}
