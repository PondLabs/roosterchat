// A server failing while renewing (a proxy's 502, a 500, the OAuth token
// endpoint's 503) is not the token being refused: the session stays active
// and the next renewal tries again. Review finding c1-1.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';

import 'soft_logout_fakes.dart';

void main() {
  // c1-1: a server error while renewing is not a refusal.
  for (final (name, oidc, answer) in [
    (
      '/v3/refresh 502 from a proxy (HTML)',
      false,
      () => http.Response('<html>Bad Gateway</html>', 502,
          headers: {'content-type': 'text/html'})
    ),
    (
      '/v3/refresh 500 M_UNKNOWN',
      false,
      () => SoftLogoutServer.json(
          {'errcode': 'M_UNKNOWN', 'error': 'Internal server error'},
          status: 500)
    ),
    (
      'OAuth token endpoint 503',
      true,
      () => SoftLogoutServer.json({'error': 'temporarily_unavailable'},
          status: 503)
    ),
  ]) {
    test('c1-1 $name keeps the session active and tries again', () async {
      final server = SoftLogoutServer()..refreshAnswer = answer;
      final client = await signedIn(server, oidc: oidc);
      server.expired.add('at-1');

      expect(await client.tokenRefresher.refresh(), isNull);
      expect(client.tokenRefresher.state.value, TokenRefreshState.active,
          reason: 'a 5xx is the server failing, not refusing the token');
      server.refreshAnswer = null;
      expect(await client.tokenRefresher.refresh(), 'at-2');
    }, skip: skipWithoutVodozemac);
  }
}
