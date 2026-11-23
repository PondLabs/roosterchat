// The dialog to sign in again after a refused renewal: the password and
// single sign-on the server offers, its error for a wrong password, and no
// way for an OAuth session; it closes once the device is signed in again.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/login/reauthenticate_dialog.dart';

import 'soft_logout_fakes.dart';

void main() {
  Future<MatrixClient> refused(WidgetTester tester, {bool oidc = false}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    final client = (await tester.runAsync(() async {
      final server = SoftLogoutServer()
        ..refreshAnswer = () => SoftLogoutServer.json(
            {'errcode': 'M_UNKNOWN_TOKEN', 'error': 'no'},
            status: 401);
      final client = await signedIn(server, oidc: oidc);
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

  Future<void> open(WidgetTester tester, MatrixClient client) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                  body: SingleChildScrollView(
                      child: ReauthenticateDialog(client: client))))),
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

  testWidgets('an OAuth session gets no password field', (tester) async {
    final client = await refused(tester, oidc: true);
    await open(tester, client);

    expect(find.text(ReauthenticateDialog.messageReauthenticateNoMethod),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reauthenticate-password')), findsNothing);
    expect(find.text(ReauthenticateDialog.promptReauthenticateRetry),
        findsOneWidget);
  }, skip: skipWithoutVodozemac != false);
}
