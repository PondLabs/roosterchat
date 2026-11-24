// Signing an OAuth 2.0 session's device in again after its refresh token
// was refused: the server's page is asked for this same device
// (`urn:matrix:client:device:<device_id>`), and the new token is only used
// when `whoami` says it is this account on this device. The device, its Olm
// account and the database stay; another device is refused and the old
// session kept; closing the page leaves the account signed out as before.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'soft_logout_fakes.dart';

const _devicePrefix = 'urn:matrix:client:device:';

/// An OAuth account on [server] whose refresh token was just refused.
Future<MatrixClient> refusedOAuth(SoftLogoutServer server) async {
  server.refreshAnswer =
      () => SoftLogoutServer.json({'error': 'invalid_grant'}, status: 400);
  final client = await signedIn(server, oidc: true);
  await client.tokenRefresher.refresh();
  expect(client.tokenRefresher.state.value,
      TokenRefreshState.needsReauthentication);
  return client;
}

/// A browser that signs in on the server's page: the server grants the
/// device the authorization request asks for, unless the test set another.
FakeRedirectReceiver browser(SoftLogoutServer server, {bool cancel = false}) {
  late final FakeRedirectReceiver receiver;
  receiver = FakeRedirectReceiver((authorization) {
    if (cancel) return null;
    final scopes = authorization.queryParameters['scope']!.split(' ');
    final device = scopes.firstWhere((s) => s.startsWith(_devicePrefix));
    server.oauthDeviceId ??= device.substring(_devicePrefix.length);
    return redirectWith(receiver.redirectUri, {
      'code': 'code-1',
      'state': authorization.queryParameters['state']!,
    });
  });
  return receiver;
}

Future<MatrixOidcLoginFlow> flowFor(
    MatrixClient client, FakeRedirectReceiver receiver) async {
  final flow = await MatrixOidcLoginFlow.forReauthentication(client,
      receiverFactory: ({required landingPage}) async => receiver);
  expect(flow, isNotNull);
  return flow!;
}

void main() {
  test('a session signed in with a password gets no OAuth flow', () async {
    final client = await signedIn(SoftLogoutServer());
    expect(await MatrixOidcLoginFlow.forReauthentication(client), isNull);
  }, skip: skipWithoutVodozemac);

  test('asks for this device, then keeps the device, keys and database',
      () async {
    final server = SoftLogoutServer();
    final client = await refusedOAuth(server);
    final mx = client.getMatrixClient();
    final before = await storedAccount(client);
    final database = mx.database;
    final encryption = mx.encryption;
    final identityKey = mx.identityKey;
    final rooms = mx.rooms.length;
    final states = <matrix.LoginState>[];
    final listener = mx.onLoginStateChanged.stream.listen(states.add);

    final receiver = browser(server);
    final result = await (await flowFor(client, receiver)).reauthenticate(
      client,
    );

    expect(result, isA<LoginResultSuccess>());
    final scopes = receiver.opened.single.queryParameters['scope']!.split(' ');
    expect(scopes, contains('urn:matrix:client:device:$deviceId'));
    final grant = server.codeGrantRequests.single.bodyFields;
    expect(grant['code'], 'code-1');
    expect(grant['code_verifier'], isNotEmpty);
    expect(server.tokensFor('/_matrix/client/v3/account/whoami'),
        contains('Bearer at-oauth'));
    expect(receiver.closed, isTrue);

    expect(client.tokenRefresher.state.value, TokenRefreshState.active);
    expect(mx.isLogged(), isTrue);
    expect(mx.accessToken, 'at-oauth');
    expect(mx.deviceID, deviceId);
    expect(mx.userID, userId);
    expect(identical(mx.database, database), isTrue);
    expect(identical(mx.encryption, encryption), isTrue);
    expect(mx.identityKey, identityKey);
    expect(mx.rooms, hasLength(rooms));
    final after = await storedAccount(client);
    expect(after['device_id'], deviceId);
    expect(after['olm_account'], before['olm_account']);
    expect(after['token'], 'at-oauth');
    expect(after['refresh_token'], 'rt-oauth');
    expect(after['oidc_client_id'], 'dcr-client-01');
    await listener.cancel();
    expect(states, isNot(contains(matrix.LoginState.loggedOut)));

    // The next renewal uses the new refresh token and client.
    server.refreshAnswer = null;
    expect(await client.tokenRefresher.refresh(), 'at-2');
    final renewal = server.refreshRequests.last.bodyFields;
    expect(renewal['refresh_token'], 'rt-oauth');
    expect(renewal['client_id'], 'dcr-client-01');
  }, skip: skipWithoutVodozemac);

  final mismatches = <String, (String?, String?, bool)>{
    'a new device': (null, 'NEWDEVICE', true),
    'another account': ('@mallory:$homeserverHost', deviceId, false),
  };
  mismatches.forEach((name, mismatch) {
    final (user, device, newDevice) = mismatch;

    test('$name is refused and the old session stays', () async {
      final server = SoftLogoutServer()
        ..oauthUserId = user
        ..oauthDeviceId = device;
      final client = await refusedOAuth(server);
      final mx = client.getMatrixClient();
      final before = await storedAccount(client);
      final states = <matrix.LoginState>[];
      final listener = mx.onLoginStateChanged.stream.listen(states.add);

      final flow = await flowFor(client, browser(server));
      await expectLater(
          flow.reauthenticate(client),
          throwsA(isA<ReauthenticationMismatch>()
              .having((e) => e.newDevice, 'newDevice', newDevice)));

      expect(server.codeGrantRequests, hasLength(1));
      expect(client.tokenRefresher.state.value,
          TokenRefreshState.needsReauthentication);
      expect(mx.accessToken, 'at-1');
      expect(mx.deviceID, deviceId);
      expect(mx.isLogged(), isTrue);
      expect(mx.encryption, isNotNull);
      final after = await storedAccount(client);
      for (final key in [
        'token',
        'refresh_token',
        'device_id',
        'user_id',
        'olm_account',
        'oidc_client_id',
      ]) {
        expect(after[key], before[key], reason: key);
      }
      await listener.cancel();
      expect(states, isEmpty);
    }, skip: skipWithoutVodozemac);
  });

  test('closing the page leaves the account signed out on this device',
      () async {
    final server = SoftLogoutServer();
    final client = await refusedOAuth(server);
    final mx = client.getMatrixClient();
    final before = await storedAccount(client);

    final receiver = browser(server, cancel: true);
    final result =
        await (await flowFor(client, receiver)).reauthenticate(client);

    expect(result, isA<LoginResultCancelled>());
    expect(receiver.closed, isTrue);
    expect(server.codeGrantRequests, isEmpty);
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
    expect(mx.accessToken, 'at-1');
    expect(mx.isLogged(), isTrue);
    expect(await storedAccount(client), before);
    // Still no renewal on its own.
    expect(await client.tokenRefresher.refresh(), isNull);
  }, skip: skipWithoutVodozemac);
}
