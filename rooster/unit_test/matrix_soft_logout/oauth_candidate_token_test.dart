// Reproducer for review finding c1-1:
// MatrixTokenRefresher.reauthenticateWithOAuth validates the candidate OAuth
// access token via MatrixApi(..., httpClient: client.httpClient).getTokenOwner().
// Because client.httpClient is TokenRefreshingHttpClient:
// 1. If whoami rejects the candidate token with 401 M_UNKNOWN_TOKEN (soft_logout: true)
//    while the old token at-1 is still valid (e.g. proactive renewal failed with
//    invalid_grant before at-1 expired), TokenRefreshingHttpClient calls
//    refresher.refresh(staleToken: 'at-oauth'), which sees current ('at-1') != staleToken
//    BEFORE checking needsReauthentication and returns 'at-1'.
//    TokenRefreshingHttpClient then retries whoami with Bearer at-1, which answers
//    200 for @alice/DEVICE1, bypassing the whoami verification and overwriting the
//    session with the rejected token.
// 2. If the user signs into a locked/suspended alt account on the OAuth page and
//    whoami returns 401 M_USER_LOCKED or 403 M_USER_SUSPENDED for that foreign token,
//    TokenRefreshingHttpClient reports the restriction on THIS account's refresher,
//    falsely locking/suspending this account.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_account_restriction.dart';

import 'oauth_reauthenticate_test.dart' show browser, flowFor, refusedOAuth;
import 'soft_logout_fakes.dart';

class _WhoamiOverrideServer extends SoftLogoutServer {
  _WhoamiOverrideServer(this.whoamiForNewToken);
  final http.Response Function() whoamiForNewToken;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/_matrix/client/v3/account/whoami') {
      final auth = request.headers['authorization'];
      http.Response? answer;
      if (auth == 'Bearer at-oauth') {
        answer = whoamiForNewToken();
      } else if (auth == 'Bearer at-1') {
        answer = SoftLogoutServer.json({
          'user_id': userId,
          'device_id': deviceId,
        });
      }
      if (answer != null) {
        final body = await request.finalize().toBytes();
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..bodyBytes = body;
        requests.add(copy);
        return http.StreamedResponse(
          Stream.value(answer.bodyBytes),
          answer.statusCode,
          headers: answer.headers,
          request: request,
        );
      }
    }
    return super.send(request);
  }
}

void main() {
  test(
      'c1-1a: whoami 401 soft_logout on candidate OAuth token must NOT retry '
      'with old at-1 and accept the rejected token', () async {
    final server = _WhoamiOverrideServer(() => SoftLogoutServer.json({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Candidate token soft logged out',
          'soft_logout': true,
        }, status: 401));
    // Proactive renewal was refused (invalid_grant), while at-1 is NOT expired.
    final client = await refusedOAuth(server);
    final before = await storedAccount(client);

    final result =
        await (await flowFor(client, browser(server))).reauthenticate(client);

    expect(result, isA<LoginResultError>(),
        reason: 'a candidate token rejected by whoami must never succeed');
    expect(server.tokensFor('/_matrix/client/v3/account/whoami'),
        ['Bearer at-oauth'],
        reason: 'whoami for candidate token must not be retried with old at-1');
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
    expect(client.getMatrixClient().accessToken, 'at-1');
    expect((await storedAccount(client))['token'], before['token']);
  }, skip: skipWithoutVodozemac);

  test(
      'c1-1b: whoami 401 M_USER_LOCKED on another account token must NOT mark '
      'this account as locked', () async {
    final server = _WhoamiOverrideServer(() => SoftLogoutServer.json({
          'errcode': 'M_USER_LOCKED',
          'error': 'Other account locked',
          'soft_logout': true,
        }, status: 401));
    final client = await refusedOAuth(server);
    final restriction =
        client.getComponent<MatrixAccountRestrictionComponent>()!;
    expect(restriction.watcher.restriction.value, isNull);

    final result =
        await (await flowFor(client, browser(server))).reauthenticate(client);
    await Future<void>.delayed(Duration.zero);

    expect(result, isA<LoginResultError>());
    expect(restriction.watcher.restriction.value, isNull,
        reason: 'a locked error from an unverified candidate token belongs to '
            'whichever account signed in on the OAuth page, not this account');
    expect(client.getMatrixClient().accessToken, 'at-1');
  }, skip: skipWithoutVodozemac);
}
