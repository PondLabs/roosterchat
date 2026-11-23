// "Try again" after a refused renewal keeps asking the person to sign in
// again until a renewal works. Review finding c1-2.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';

import 'soft_logout_fakes.dart';

void main() {
  // c1-2: "Try again" while the server cannot be reached.
  test('c1-2 retry that fails on the network keeps asking to sign in again',
      () async {
    final server = SoftLogoutServer()
      ..refreshAnswer =
          () => SoftLogoutServer.json({'error': 'invalid_grant'}, status: 400);
    final client = await signedIn(server, oidc: true);
    server.expired.add('at-1');
    expect(await client.tokenRefresher.refresh(), isNull);
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);

    server.refreshAnswer = () => throw http.ClientException('offline');
    expect(await client.tokenRefresher.retry(), isNull);
    // Sync is still stopped and the token still dead: the person must still
    // be told (alert and dialog), not shown a working session.
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);

    // Once the renewal works, the session is active again.
    server.refreshAnswer = null;
    expect(await client.tokenRefresher.retry(), 'at-2');
    expect(client.tokenRefresher.state.value, TokenRefreshState.active);
  }, skip: skipWithoutVodozemac);
}
