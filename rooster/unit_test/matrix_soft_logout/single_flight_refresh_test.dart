// Requests that meet a soft logout at the same time share one renewal:
// five concurrent calls answered `401 M_UNKNOWN_TOKEN` (`soft_logout: true`)
// make exactly one request to /v3/refresh (or the OAuth token endpoint),
// and every call is sent again with the renewed token.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'soft_logout_fakes.dart';

void main() {
  for (final oidc in [false, true]) {
    final endpoint = oidc ? 'the OAuth token endpoint' : '/v3/refresh';

    test('five concurrent soft logouts make one request to $endpoint',
        () async {
      final server = SoftLogoutServer();
      final client = await signedIn(server, oidc: oidc);
      final mx = client.getMatrixClient();
      server.expired.add('at-1');
      server.gate = Completer<void>();

      final calls = [for (var i = 0; i < 5; i++) mx.getTokenOwner()];
      // Every call met the soft logout before the renewal answers.
      while (server.tokensFor('/_matrix/client/v3/account/whoami').length < 5) {
        await Future<void>.delayed(Duration.zero);
      }
      server.gate!.complete();
      final owners = await Future.wait(calls);

      expect(server.refreshRequests, hasLength(1));
      expect(owners, hasLength(5));
      expect(server.tokensFor('/_matrix/client/v3/account/whoami'),
          [...List.filled(5, 'Bearer at-1'), ...List.filled(5, 'Bearer at-2')]);
      expect(mx.accessToken, 'at-2');
    }, skip: skipWithoutVodozemac);

    test('callers of the refresher share its answer ($endpoint)', () async {
      final server = SoftLogoutServer();
      final client = await signedIn(server, oidc: oidc);
      server.gate = Completer<void>();

      final tokens = [
        for (var i = 0; i < 5; i++) client.tokenRefresher.refresh(),
      ];
      server.gate!.complete();

      expect(await Future.wait(tokens), List.filled(5, 'at-2'));
      expect(server.refreshRequests, hasLength(1));
    }, skip: skipWithoutVodozemac);
  }

  test('a request sent with a token already renewed is not renewed again',
      () async {
    final server = SoftLogoutServer();
    final client = await signedIn(server);

    expect(await client.tokenRefresher.refresh(), 'at-2');
    expect(await client.tokenRefresher.refresh(staleToken: 'at-1'), 'at-2');
    expect(server.refreshRequests, hasLength(1));
  }, skip: skipWithoutVodozemac);
}
