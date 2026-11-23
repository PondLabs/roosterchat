// The password and single sign-on logins ask the homeserver for a refresh
// token (`refresh_token: true` in the body of POST /v3/login), so that the
// session can be renewed instead of ending.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'soft_logout_fakes.dart';
import '../matrix_auth_oidc/oidc_fakes.dart' show newAccount;

/// Single sign-on without the browser: the page handed back this token.
class _SsoWithoutBrowser extends MatrixSSOLoginFlow {
  _SsoWithoutBrowser() : super(name: 'Example');

  @override
  Future<String?> obtainLoginToken(matrix.Client mx) async => 'sso-token';
}

void main() {
  setUpAll(initVodozemac);

  Future<(MatrixClient, SoftLogoutServer)> discovered() async {
    final server = SoftLogoutServer();
    final client = await newAccount(server);
    final (ok, _) = await client.setHomeserver(Uri.https(homeserverHost));
    expect(ok, isTrue);
    // The SDK also asks for one whenever onSoftLogout is set: the flows
    // must ask on their own.
    client.getMatrixClient().onSoftLogout = null;
    return (client, server);
  }

  Map<String, Object?> loginBody(SoftLogoutServer server) =>
      jsonDecode(server.loginRequests.single.body) as Map<String, Object?>;

  test('the password login asks for a refresh token', () async {
    final (client, server) = await discovered();
    final flow = MatrixPasswordLoginFlow()
      ..username = 'alice'
      ..password = 'secret';

    final result = await flow.submit(client);

    expect(result, isA<LoginResultSuccess>());
    final body = loginBody(server);
    expect(body['type'], 'm.login.password');
    expect(body['refresh_token'], isTrue);
    final stored = await storedAccount(client);
    expect(stored['refresh_token'], 'rt-login',
        reason: 'the refresh token is kept for later');
  }, skip: skipWithoutVodozemac);

  test('the single sign-on login asks for a refresh token', () async {
    final (client, server) = await discovered();

    final result = await _SsoWithoutBrowser().submit(client);

    expect(result, isA<LoginResultSuccess>());
    final body = loginBody(server);
    expect(body['type'], 'm.login.token');
    expect(body['token'], 'sso-token');
    expect(body['refresh_token'], isTrue);
  }, skip: skipWithoutVodozemac);
}
