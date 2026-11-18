@TestOn('vm')
library;

/// Signing sessions out on a server where only its account page can (the
/// Matrix Authentication Service, as matrix.org), with what matrix.org
/// announces; and on a server that still signs them out through the
/// client API. On the SDK's fake homeserver: no request leaves the test.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'matrix_org_auth_metadata.dart';
import 'sessions_server.dart';

/// matrix.org's metadata, with only the account page's older action names
/// (from before MSC4191 named them `session_*`).
Map<String, Object?> get _olderActionsOnly => {
      ...jsonDecode(matrixOrgAuthMetadata) as Map<String, Object?>,
      'account_management_actions_supported': [
        'org.matrix.profile',
        'org.matrix.devices_list',
        'org.matrix.device_view',
        'org.matrix.device_delete',
      ],
    };

/// Answers the password prompt of [client] with the account's password,
/// as the person does in the dialog.
void _typePassword(MatrixClient client) {
  final mx = client.getMatrixClient();
  mx.onUiaRequest.stream.listen((uia) {
    if (uia.state != matrix.UiaRequestState.waitForUser) return;
    uia.completeStage(matrix.AuthenticationPassword(
        session: uia.session,
        password: password,
        identifier: matrix.AuthenticationUserIdentifier(user: mx.userID!)));
  });
}

void main() {
  late FakeBrowser browser;

  setUp(() {
    browser = FakeBrowser();
    UrlLauncherPlatform.instance = browser;
  });

  testWidgets(
      'on matrix.org, a session ended on the account page leaves the list '
      'when the person comes back', (tester) async {
    final server = SessionsServer(SessionsKind.accountService);
    final client = await signIn(tester, server);
    await openSessions(tester, client);
    expect(removeButton('E2ETESTA'), findsOneWidget);

    await press(tester, removeButton('E2ETESTA'));
    await settle(tester, () => browser.opened.isNotEmpty || _askedToOpen());
    // As the person would: yes, open it.
    if (_askedToOpen()) {
      // The dialog's opening animation.
      await tester.pump(const Duration(seconds: 1));
      await press(tester, find.text(CommonStrings.promptOpen));
      await settle(tester, () => browser.opened.isNotEmpty);
    }
    final page = browser.opened.single;
    printOnFailure('The app opened $page');
    printOnFailure(
        'The app asked the server: ${server.requests.where((r) => !r.contains('/sync')).join(', ')}');
    expect(page.host, 'account.matrix.org');
    expect(page.queryParameters['device_id'], 'E2ETESTA');

    // On the account page the person ends it, then comes back.
    server.endOnAccountPage('E2ETESTA');
    await leaveAndComeBack(tester);
    await settle(tester, () => find.text('E2ETESTA').evaluate().isEmpty,
        reason: 'the list still shows the session ended on the account page');
    expect(find.text('OLDPHONE'), findsOneWidget);
  });

  testWidgets(
      'on matrix.org, removing a session opens the account page on ending '
      'it, and the client API is never asked', (tester) async {
    final server = SessionsServer(SessionsKind.accountService);
    final client = await signIn(tester, server);
    await openSessions(tester, client);
    expect(find.text(MatrixSecurityTab.messageSettingsSessionsOnAccountPage),
        findsOneWidget);

    await press(tester, removeButton('E2ETESTA'));
    await settle(tester, () => browser.opened.isNotEmpty);
    expect(browser.opened.single.toString(),
        'https://account.matrix.org/account/?action=org.matrix.session_end&device_id=E2ETESTA');
    expect(_askedToOpen(), isFalse);
    expect(server.deletions, isEmpty);
  });

  testWidgets('a server that announces only the older action names gets them',
      (tester) async {
    final server = SessionsServer(SessionsKind.accountService,
        authMetadata: _olderActionsOnly);
    final client = await signIn(tester, server);
    await openSessions(tester, client);

    await press(tester, removeButton('E2ETESTA'));
    await press(tester, endInactiveButton);
    await settle(tester, () => browser.opened.length == 2);
    expect(browser.opened.map((page) => page.toString()), [
      'https://account.matrix.org/account/?action=org.matrix.device_delete&device_id=E2ETESTA',
      'https://account.matrix.org/account/?action=org.matrix.devices_list',
    ]);
    expect(server.deletions, isEmpty);
  });

  testWidgets(
      'on matrix.org, ending the inactive sessions opens the account '
      'page\'s list of sessions, and coming back shows them gone',
      (tester) async {
    final server = SessionsServer(SessionsKind.accountService);
    final client = await signIn(tester, server);
    await openSessions(tester, client);
    expect(endInactiveButton, findsOneWidget);

    await press(tester, endInactiveButton);
    await settle(tester, () => browser.opened.isNotEmpty);
    expect(browser.opened.single.toString(),
        'https://account.matrix.org/account/?action=org.matrix.sessions_list');

    server
      ..endOnAccountPage('OLDPHONE')
      ..endOnAccountPage('OLDWEBXX');
    await leaveAndComeBack(tester);
    await settle(tester, () => find.text('OLDPHONE').evaluate().isEmpty);
    expect(find.text('OLDWEBXX'), findsNothing);
    expect(find.text('E2ETESTA'), findsOneWidget);
    expect(find.text(MatrixSecurityTab.messageSettingsSessionsSignedOut(2)),
        findsOneWidget);
    expect(endInactiveButton, findsNothing);
    expect(server.deletions, isEmpty);
  });

  testWidgets(
      'on a server without the account service, the inactive sessions are '
      'signed out through the client API with the password', (tester) async {
    final server = SessionsServer(SessionsKind.legacy);
    final client = await signIn(tester, server);
    _typePassword(client);
    await openSessions(tester, client);
    expect(find.text(MatrixSecurityTab.messageSettingsSessionsOnAccountPage),
        findsNothing);

    await press(tester, endInactiveButton);
    await tester.pump(const Duration(seconds: 1));
    await press(tester, find.text(CommonStrings.promptYes));
    await settle(tester, () => find.text('OLDPHONE').evaluate().isEmpty);
    expect(find.text('OLDWEBXX'), findsNothing);
    expect(find.text('E2ETESTA'), findsOneWidget);
    expect(server.devices.keys, isNot(contains('OLDPHONE')));
    expect(
        server.requests
            .where((r) => r == 'POST /_matrix/client/v3/delete_devices'),
        hasLength(2),
        reason: 'once without the password, once with it');
    expect(browser.opened, isEmpty);
  });

  testWidgets(
      'on a server without the account service, removing a session signs '
      'it out through the client API with the password', (tester) async {
    final server = SessionsServer(SessionsKind.legacy);
    final client = await signIn(tester, server);
    _typePassword(client);
    await openSessions(tester, client);

    await press(tester, removeButton('E2ETESTA'));
    await settle(tester, () => find.text('E2ETESTA').evaluate().isEmpty);
    expect(server.devices.keys, isNot(contains('E2ETESTA')));
    expect(server.requests,
        contains('DELETE /_matrix/client/v3/devices/E2ETESTA'));
    expect(browser.opened, isEmpty);
  });

  testWidgets(
      'a server with neither an account page nor the client API says so, '
      'with no button that does nothing', (tester) async {
    final server = SessionsServer(SessionsKind.neither);
    final client = await signIn(tester, server);
    await openSessions(tester, client);

    expect(find.text(MatrixSecurityTab.messageSettingsSessionsCannotSignOut),
        findsOneWidget);
    expect(find.text(MatrixSecurityTab.messageSettingsSessionsOnAccountPage),
        findsNothing);
    expect(find.text('OLDPHONE'), findsOneWidget);
    expect(removeButton('E2ETESTA'), findsNothing);
    expect(endInactiveButton, findsNothing);
  });
}

bool _askedToOpen() =>
    find.text(CommonStrings.promptOpen).evaluate().isNotEmpty;
