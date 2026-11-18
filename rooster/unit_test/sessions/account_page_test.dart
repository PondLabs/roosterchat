@TestOn('vm')
library;

/// Signing sessions out on a server where only its account page can (the
/// Matrix Authentication Service, as matrix.org), with what matrix.org
/// announces; and on a server that still signs them out through the
/// client API. On the SDK's fake homeserver: no request leaves the test.

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'sessions_server.dart';

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
}

bool _askedToOpen() =>
    find.text(CommonStrings.promptOpen).evaluate().isNotEmpty;
