// The dialog to sign in again after a refused renewal: the password and
// single sign-on the server offers, its error for a wrong password, and the
// server's OAuth page for an OAuth session (a new device refused with a
// warning, a closed page changing nothing); it closes once the device is
// signed in again.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/login/oidc_login_buttons.dart';
import 'package:rooster/ui/pages/login/reauthenticate_dialog.dart';

import 'oauth_reauthenticate_test.dart' show browser;
import 'soft_logout_fakes.dart';

void main() {
  Future<MatrixClient> refused(WidgetTester tester,
      {bool oidc = false, SoftLogoutServer? server}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    final client = (await tester.runAsync(() async {
      server = (server ?? SoftLogoutServer())
        ..refreshAnswer = () => SoftLogoutServer.json(
            {'errcode': 'M_UNKNOWN_TOKEN', 'error': 'no'},
            status: 401);
      final client = await signedIn(server!, oidc: oidc);
      await client.tokenRefresher.refresh();
      return client;
    }))!;
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
    return client;
  }

  /// Lets the database and the fake server answer until [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> open(WidgetTester tester, MatrixClient client,
      {FakeRedirectReceiver? receiver}) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                  body: SingleChildScrollView(
                      child: ReauthenticateDialog(
                          client: client,
                          oidcReceiverFactory: receiver == null
                              ? null
                              : ({required landingPage}) async => receiver))))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The server's sign-in ways.
    await waitFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
  }

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(
        find.byKey(const ValueKey('reauthenticate-password')), password);
    await tester.tap(find.text(ReauthenticateDialog.promptReauthenticate));
    await tester.pump();
    // Closed, or an error under the buttons.
    await waitFor(
        tester,
        () =>
            find.byType(ReauthenticateDialog).evaluate().isEmpty ||
            find.byKey(const ValueKey('reauth-error')).evaluate().isNotEmpty);
  }

  testWidgets('signs in again with the password, then closes', (tester) async {
    final client = await refused(tester);
    await open(tester, client);

    expect(find.text(ReauthenticateDialog.messageReauthenticate(userId)),
        findsOneWidget);
    expect(
        find.text(ReauthenticateDialog.promptReauthenticateSso('homeserver')),
        findsOneWidget);
    await submit(tester, 'secret');

    expect(client.tokenRefresher.state.value, TokenRefreshState.active);
    expect(client.getMatrixClient().deviceID, deviceId);
    expect(find.byType(ReauthenticateDialog), findsNothing);
  }, skip: skipWithoutVodozemac != false);

  testWidgets('a wrong password shows the server error and stays',
      (tester) async {
    final client = await refused(tester);
    await open(tester, client);

    await submit(tester, 'wrong');

    expect(find.text('Invalid password'), findsOneWidget);
    expect(find.byType(ReauthenticateDialog), findsOneWidget);
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
  }, skip: skipWithoutVodozemac != false);

  Future<void> signInWithOAuth(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('reauthenticate-oauth')));
    await tester.pump();
    await waitFor(
        tester,
        () =>
            find.byType(ReauthenticateDialog).evaluate().isEmpty ||
            find.byKey(const ValueKey('reauth-error')).evaluate().isNotEmpty);
  }

  testWidgets("an OAuth session signs this device in on the server's page",
      (tester) async {
    final server = SoftLogoutServer();
    final client = await refused(tester, oidc: true, server: server);
    await open(tester, client, receiver: browser(server));

    expect(find.text(OidcLoginButtons.promptLoginOauth(homeserverHost)),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reauthenticate-password')), findsNothing);
    expect(find.text(ReauthenticateDialog.messageReauthenticateNoMethod),
        findsNothing);
    await signInWithOAuth(tester);

    expect(client.tokenRefresher.state.value, TokenRefreshState.active);
    expect(client.getMatrixClient().deviceID, deviceId);
    expect(client.getMatrixClient().accessToken, 'at-oauth');
    expect(find.byType(ReauthenticateDialog), findsNothing);
  }, skip: skipWithoutVodozemac != false);

  testWidgets('a new device from the server is refused with a warning',
      (tester) async {
    final server = SoftLogoutServer()..oauthDeviceId = 'NEWDEVICE';
    final client = await refused(tester, oidc: true, server: server);
    await open(tester, client, receiver: browser(server));

    await signInWithOAuth(tester);

    expect(find.text(ReauthenticateDialog.errorReauthenticateNewDevice),
        findsOneWidget);
    expect(find.byType(ReauthenticateDialog), findsOneWidget);
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
    expect(client.getMatrixClient().accessToken, 'at-1');
  }, skip: skipWithoutVodozemac != false);

  testWidgets("closing the server's page keeps the dialog, without an error",
      (tester) async {
    final server = SoftLogoutServer();
    final client = await refused(tester, oidc: true, server: server);
    final receiver = browser(server, cancel: true);
    await open(tester, client, receiver: receiver);

    await tester.tap(find.byKey(const ValueKey('reauthenticate-oauth')));
    await tester.pump();
    await waitFor(tester, () => receiver.closed);

    expect(receiver.opened, hasLength(1));
    expect(find.byKey(const ValueKey('reauth-error')), findsNothing);
    expect(find.byType(ReauthenticateDialog), findsOneWidget);
    expect(client.tokenRefresher.state.value,
        TokenRefreshState.needsReauthentication);
  }, skip: skipWithoutVodozemac != false);

  testWidgets('an OAuth session the server no longer offers has no way',
      (tester) async {
    final server = SoftLogoutServer()
      ..metadata = {'errcode': 'M_UNRECOGNIZED', 'error': 'no'};
    final client = await refused(tester, oidc: true, server: server);
    await open(tester, client);

    expect(find.text(ReauthenticateDialog.messageReauthenticateNoMethod),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reauthenticate-oauth')), findsNothing);
    expect(find.byKey(const ValueKey('reauthenticate-password')), findsNothing);
    expect(find.text(ReauthenticateDialog.promptReauthenticateRetry),
        findsOneWidget);
  }, skip: skipWithoutVodozemac != false);
}
