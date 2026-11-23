// An account created from the login screen signs in like any other login:
// it goes through MatrixClient.executeLoginFlow, so it is kept for the next
// start of the app (the registered accounts in the preferences) and what
// follows a login runs (the own profile, the components' post-login init).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/global_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/login/login_page.dart';
import 'package:rooster/ui/pages/login/register_view.dart';

import '../matrix_auth_oidc/oidc_fakes.dart' show initVodozemac, newAccount;
import 'lifecycle_fakes.dart';

/// The account the SDK's fake homeserver has a profile for.
const newUserId = '@alice:example.com';

/// A homeserver without OAuth 2.0 that signs in with a password and lets
/// accounts register (one `m.login.dummy` stage); sync, keys and profiles
/// answer like the SDK's [FakeMatrixApi].
class RegisteringServer extends http.BaseClient {
  final FakeMatrixApi _api = FakeMatrixApi();
  final List<http.Request> requests = [];
  final UiaEndpoint register = UiaEndpoint([
    ['m.login.dummy']
  ], success: {
    'user_id': newUserId,
    'device_id': 'NEWDEVICE',
    'access_token': 'new-access-token',
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    requests.add(copy);
    final answer = _answer(copy);
    if (answer != null) {
      return http.StreamedResponse(
          Stream.value(answer.bodyBytes), answer.statusCode,
          headers: answer.headers, request: request);
    }
    return _api.send(http.Request(
        request.method, copy.url.replace(host: 'fakeserver.notexisting'))
      ..headers.addAll(request.headers)
      ..bodyBytes = body);
  }

  http.Response? _answer(http.Request request) {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/filter')) {
      return json({'filter_id': 'filter-1'});
    }
    switch (path) {
      case '/.well-known/matrix/client':
        return http.Response('', 404);
      case '/_matrix/client/versions':
        return json({
          'versions': ['v1.11'],
        });
      case '/_matrix/client/v1/auth_metadata':
        return json({'errcode': 'M_UNRECOGNIZED', 'error': 'no'}, 404);
      case '/_matrix/client/v3/login' when request.method == 'GET':
        return json({
          'flows': [
            {'type': 'm.login.password'},
          ]
        });
      case '/_matrix/client/v3/register':
        return register(request);
    }
    return null;
  }
}

void main() {
  /// Lets the database and the fake server answer until [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'an account registered on the login screen is kept and gets what '
      'follows a login', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    GlobalConfig.data = {};
    final server = RegisteringServer();
    final client = (await tester.runAsync(() async {
      if (Platform.environment['VODOZEMAC_LIB_DIR'] != null) {
        await initVodozemac();
      }
      return newAccount(server);
    }))!;
    Client? signedIn;

    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        createClient: (_) async => client,
        onSuccess: (client) => signedIn = client,
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'matrix.example.org');
    // The homeserver check waits a second after the last key.
    await tester.pump(const Duration(seconds: 2));
    final createAccount = find.text(RegisterView.promptLoginCreateAccount);
    await waitFor(tester, () => createAccount.evaluate().isNotEmpty);
    expect(createAccount, findsOneWidget,
        reason: 'a server with passwords and no OAuth 2.0 offers it');
    expect(preferences.getRegisteredMatrixClients() ?? const [],
        isNot(contains(client.identifier)));

    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('register-username')), 'alice');
    await tester.enterText(
        find.byKey(const ValueKey('register-password')), 'a long passphrase');
    await tester.enterText(
        find.byKey(const ValueKey('register-confirm')), 'a long passphrase');
    await tester.tap(find.descendant(
        of: find.byType(RegisterView),
        matching: find.text(RegisterView.promptLoginCreateAccount)));
    await waitFor(tester, () => signedIn != null);

    expect(signedIn, same(client));
    expect(client.matrixClient.userID, newUserId);
    final registered = server.requests
        .where((r) => r.url.path == '/_matrix/client/v3/register')
        .map((r) => jsonDecode(r.body) as Map)
        .toList();
    expect(registered.last['username'], 'alice');
    expect((registered.last['auth'] as Map)['type'], 'm.login.dummy');
    // Kept for the next start of the app.
    expect(
        preferences.getRegisteredMatrixClients(), contains(client.identifier));
    // What follows every login ran: the own profile is there.
    expect(client.self?.identifier, newUserId);

    // The signed-in account syncs: stopped, so no timer outlives the test.
    client.matrixClient.backgroundSync = false;
    await tester.runAsync(() => client.matrixClient.abortSync());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
  });

  test('the flow of a client that is not signed in fails', () async {
    final client = await newAccount(RegisteringServer());
    expect(await client.executeLoginFlow(const RegisteredAccountLoginFlow()),
        isA<LoginResultFailed>());
    expect(preferences.getRegisteredMatrixClients() ?? const [],
        isNot(contains(client.identifier)));
  });
}
