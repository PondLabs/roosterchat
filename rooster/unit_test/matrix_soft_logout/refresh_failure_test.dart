// A refused renewal (OAuth `400 invalid_grant`, /v3/refresh `401
// M_UNKNOWN_TOKEN` without soft_logout, no refresh token at all) moves the
// account to "sign in again": no more renewals, sync stopped, and the
// database and the Olm account stay. Signing in again keeps the device.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'soft_logout_fakes.dart';

void main() {
  final refusals = <String, (bool, String?, http.Response Function()?)>{
    'OAuth 400 invalid_grant': (
      true,
      'rt-1',
      () => SoftLogoutServer.json({'error': 'invalid_grant'}, status: 400),
    ),
    '/v3/refresh 401 M_UNKNOWN_TOKEN without soft_logout': (
      false,
      'rt-1',
      () => SoftLogoutServer.json({
            'errcode': 'M_UNKNOWN_TOKEN',
            'error': 'Refresh token revoked',
            'soft_logout': false,
          }, status: 401),
    ),
    'no refresh token': (false, null, null),
  };

  Future<void> expectNothingLost(
      MatrixClient client, Map<String, Object?> before) async {
    final mx = client.getMatrixClient();
    final after = await storedAccount(client);
    expect(after['device_id'], deviceId);
    expect(after['user_id'], userId);
    expect(after['olm_account'], before['olm_account']);
    expect(mx.isLogged(), isTrue);
    expect(mx.encryption, isNotNull);
    expect(mx.deviceID, deviceId);
  }

  refusals.forEach((name, refusal) {
    final (oidc, refreshToken, answer) = refusal;

    test('$name: sign in again, no loop, keys kept', () async {
      final server = SoftLogoutServer()..refreshAnswer = answer;
      final client =
          await signedIn(server, oidc: oidc, refreshToken: refreshToken);
      final mx = client.getMatrixClient();
      final before = await storedAccount(client);
      expect(before['olm_account'], isNotNull);
      final states = <matrix.LoginState>[];
      final listener = mx.onLoginStateChanged.stream.listen(states.add);
      server.expired.add('at-1');

      await expectLater(
          mx.getTokenOwner(),
          throwsA(isA<matrix.MatrixException>().having(
              (e) => e.error, 'error', matrix.MatrixError.M_UNKNOWN_TOKEN)));
      expect(client.tokenRefresher.state.value,
          TokenRefreshState.needsReauthentication);
      final renewals = server.refreshRequests.length;
      expect(renewals, refreshToken == null ? 0 : 1);

      // More requests, a sync (which calls onSoftLogout) and the expiry
      // check: none renews again, none logs out.
      for (var i = 0; i < 3; i++) {
        await expectLater(
            mx.getTokenOwner(), throwsA(isA<matrix.MatrixException>()));
      }
      await mx.oneShotSync();
      await mx.ensureNotSoftLoggedOut(const Duration(minutes: 10));
      expect(server.refreshRequests, hasLength(renewals));
      expect(await client.tokenRefresher.refresh(), isNull);
      expect(server.refreshRequests, hasLength(renewals));

      await listener.cancel();
      expect(states, isNot(contains(matrix.LoginState.loggedOut)));
      await expectNothingLost(client, before);
    }, skip: skipWithoutVodozemac);
  });

  test('a network failure is not a refusal: the next soft logout tries again',
      () async {
    final server = SoftLogoutServer()
      ..refreshAnswer = () => throw http.ClientException('offline');
    final client = await signedIn(server);
    server.expired.add('at-1');

    expect(await client.tokenRefresher.refresh(), isNull);
    expect(client.tokenRefresher.state.value, TokenRefreshState.active);
    server.refreshAnswer = null;
    expect(await client.tokenRefresher.refresh(), 'at-2');
    expect(server.refreshRequests, hasLength(2));
  }, skip: skipWithoutVodozemac);

  group('signing in again', () {
    Future<(MatrixClient, SoftLogoutServer, Map<String, Object?>)>
        refused() async {
      final server = SoftLogoutServer()
        ..refreshAnswer = () =>
            SoftLogoutServer.json({'error': 'invalid_grant'}, status: 400);
      final client = await signedIn(server, refreshToken: 'rt-1');
      final before = await storedAccount(client);
      expect(await client.tokenRefresher.refresh(), isNull);
      expect(client.tokenRefresher.state.value,
          TokenRefreshState.needsReauthentication);
      return (client, server, before);
    }

    test('with the password keeps the device, the database and the keys',
        () async {
      final (client, server, before) = await refused();
      final mx = client.getMatrixClient();

      await client.tokenRefresher.reauthenticate(password: 'secret');

      final body = jsonDecode(server.loginRequests.single.body);
      expect(body['device_id'], deviceId);
      expect(body['refresh_token'], isTrue);
      expect(body['identifier'], {'type': 'm.id.user', 'user': userId});
      expect(server.loginRequests.single.headers['authorization'], isNull);
      expect(client.tokenRefresher.state.value, TokenRefreshState.active);
      expect(mx.accessToken, 'at-login');
      expect(mx.onLoginStateChanged.value, matrix.LoginState.loggedIn);
      final after = await storedAccount(client);
      expect(after['token'], 'at-login');
      expect(after['refresh_token'], 'rt-login');
      await expectNothingLost(client, before);

      // Renewals work again, with the new refresh token.
      server.refreshAnswer = null;
      expect(await client.tokenRefresher.refresh(), 'at-2');
      expect(server.refreshRequests.last.body,
          contains('"refresh_token":"rt-login"'));
    }, skip: skipWithoutVodozemac);

    test('a wrong password changes nothing', () async {
      final (client, _, before) = await refused();

      await expectLater(client.tokenRefresher.reauthenticate(password: 'wrong'),
          throwsA(isA<matrix.MatrixException>()));
      expect(client.tokenRefresher.state.value,
          TokenRefreshState.needsReauthentication);
      expect(client.getMatrixClient().accessToken, 'at-1');
      await expectNothingLost(client, before);
    }, skip: skipWithoutVodozemac);

    test('an answer for another device is not used', () async {
      final (client, server, before) = await refused();
      server.loginDeviceId = 'OTHERDEVICE';

      await expectLater(
          client.tokenRefresher.reauthenticate(loginToken: 'sso-token'),
          throwsA(isA<ReauthenticationMismatch>()));
      expect(client.getMatrixClient().accessToken, 'at-1');
      expect((await storedAccount(client))['token'], 'at-1');
      await expectNothingLost(client, before);
    }, skip: skipWithoutVodozemac);
  });
}
