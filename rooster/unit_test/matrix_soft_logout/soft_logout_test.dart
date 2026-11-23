// A soft logout renews the token, by /v3/refresh for a password or single
// sign-on session and by the OAuth token endpoint (grant_type=refresh_token)
// for an OAuth one, on the same device: the database, the Olm account and
// the encryption stay.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';

import 'soft_logout_fakes.dart';

void main() {
  for (final oidc in [false, true]) {
    final mode = oidc ? 'OAuth' : 'legacy';

    test('$mode: a soft logout on sync renews the token on the same device',
        () async {
      final server = SoftLogoutServer();
      final client = await signedIn(server, oidc: oidc);
      final mx = client.getMatrixClient();
      final before = await storedAccount(client);
      expect(before['olm_account'], isNotNull);
      final encryption = mx.encryption;
      final states = <matrix.LoginState>[];
      final listener = mx.onLoginStateChanged.stream.listen(states.add);

      server.expired.add('at-1');
      await mx.oneShotSync();

      final refresh = server.refreshRequests.single;
      if (oidc) {
        expect(refresh.bodyFields, {
          'grant_type': 'refresh_token',
          'refresh_token': 'rt-1',
          'client_id': oidcClientId,
        });
      } else {
        expect(refresh.body, contains('"refresh_token":"rt-1"'));
      }
      expect(server.tokensFor('/_matrix/client/v3/sync').last, 'Bearer at-2');
      expect(mx.accessToken, 'at-2');
      expect(mx.deviceID, deviceId);
      expect(mx.isLogged(), isTrue);
      expect(identical(mx.encryption, encryption), isTrue);
      expect(client.tokenRefresher.state.value, TokenRefreshState.active);

      final after = await storedAccount(client);
      expect(after['token'], 'at-2');
      expect(after['refresh_token'], 'rt-2');
      expect(after['device_id'], deviceId);
      expect(after['olm_account'], before['olm_account']);
      expect(after['oidc_client_id'], oidc ? oidcClientId : null);
      await listener.cancel();
      expect(states, isNot(contains(matrix.LoginState.loggedOut)));
    }, skip: skipWithoutVodozemac);

    test('$mode: a token about to expire is renewed by the SDK first',
        () async {
      final server = SoftLogoutServer();
      final client = await signedIn(server, oidc: oidc);
      final mx = client.getMatrixClient();
      final before = await storedAccount(client);

      // The token expires in five minutes: within ten, the SDK calls
      // onSoftLogout before any request.
      await mx.ensureNotSoftLoggedOut(const Duration(minutes: 10));

      expect(server.refreshRequests, hasLength(1));
      expect(mx.accessToken, 'at-2');
      expect(mx.deviceID, deviceId);
      expect(mx.accessTokenExpiresAt, isNotNull);
      final after = await storedAccount(client);
      expect(after['olm_account'], before['olm_account']);
    }, skip: skipWithoutVodozemac);
  }
}
