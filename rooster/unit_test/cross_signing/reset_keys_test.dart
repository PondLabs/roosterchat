@TestOn('vm')
library;

/// Making new verification (cross-signing) keys from Settings > Security,
/// as the person does it: the wizard, then the server's own step. On
/// matrix.org the server asks for the reset to be approved on its account
/// page (`m.oauth`, or `org.matrix.cross_signing_reset` before Matrix 1.15);
/// on an older server it asks for the password. On the SDK's fake
/// homeserver: no request leaves the test.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart' show BootstrapState;
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_page.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../device_verification/device_verification_fakes.dart';
import '../sessions/sessions_server.dart' show FakeBrowser, leaveAndComeBack;
import 'reset_server.dart';

/// What the dialog said before Rooster knew the account page's step.
const _noMethod =
    'Sorry, none of the authentication methods provided by the server are supported.';
const _approveOnWebsite = 'Your server approves this change on its own '
    'website: open it, approve the change, and come back.';
const _notApprovedYet = 'The server has not seen the approval yet. Approve '
    'the change on the website, then try again.';
const _openWebsite = 'Open the website';

/// Lets the account's real work (database, crypto, the fake server) run
/// between frames until [done], then lets a dialog that opened finish its
/// animation.
Future<void> _settle(WidgetTester tester, bool Function() done,
    {String? reason, int rounds = 150}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: reason);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late MatrixClient client;
  late ResetServer server;
  late FakeBrowser browser;

  setUp(() {
    browser = FakeBrowser();
    UrlLauncherPlatform.instance = browser;
  });

  /// A verified device of an account with verification keys and a backup,
  /// with the app's dialog for the server's steps listening.
  Future<void> signIn(WidgetTester tester, ResetKind kind,
      {String url = resetPage}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    server = ResetServer(kind, url: url);
    await tester.runAsync(() async {
      client = await newAccount(server);
      await FakeLogin(verified: true).submit(client);
      server.remember(client.getMatrixClient());
      client.getComponent<MatrixKeyVerificationComponent>()!.postLoginInit();
    });
  }

  /// Settings > Security > Cross signing > Reset, as the app opens it.
  Future<void> openReset(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Center(
          child: MatrixCrossSigningPage(
              client: client, mode: MatrixCrossSigningMode.resetCrossSigning),
        ),
      ),
    ));
    await tester.pump();
  }

  MatrixCrossSigningPageState wizard(WidgetTester tester) => tester
      .state<MatrixCrossSigningPageState>(find.byType(MatrixCrossSigningPage));

  Future<void> tap(WidgetTester tester, String text) async {
    final button = find.text(text).last;
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
  }

  /// Through the wizard to the upload of the new keys: wipe the old keys,
  /// make a recovery key, wipe the old verification keys, confirm. Gives
  /// back the new recovery key.
  Future<String> upToTheUpload(WidgetTester tester) async {
    await openReset(tester);
    await tap(tester, 'Wipe Keys');
    await tap(tester, 'Generate Key');
    await _settle(
        tester,
        () => find
            .textContaining('wipe your cross signing')
            .evaluate()
            .isNotEmpty);
    await tap(tester, 'Wipe Keys');
    await _settle(tester,
        () => wizard(tester).bootstrapper?.newSsssKey?.recoveryKey != null);
    final recoveryKey = wizard(tester).bootstrapper!.newSsssKey!.recoveryKey!;
    await tap(tester, CommonStrings.promptConfirm);
    return recoveryKey;
  }

  testWidgets(
      'on matrix.org the reset is approved on the account page, nothing '
      'changes before that, and a new session opens with the new recovery '
      'key',
      skip: skipWithoutVodozemac != false, (tester) async {
    await signIn(tester, ResetKind.accountService);
    final before = server.defaultKey;
    final recoveryKey = await upToTheUpload(tester);
    await _settle(tester, () => server.uploads.isNotEmpty);
    await _settle(
        tester,
        () =>
            find.text(_noMethod).evaluate().isNotEmpty ||
            find.text(_approveOnWebsite).evaluate().isNotEmpty);

    // What the person saw, and what the server was left with, before
    // Rooster knew the step.
    final problems = [
      if (find.text(_noMethod).evaluate().isNotEmpty)
        'the dialog says: "$_noMethod" '
            '${find.textContaining('m.oauth').evaluate().map((e) => (e.widget as Text).data).join()}',
      if (server.writes.isNotEmpty)
        'written before the server took the new keys: ${server.writes}',
      if (server.defaultKey != before)
        'the default key is now a new one, holding '
            '${[
          for (final type in secretTypes)
            if ((server.accountData[type]?['encrypted'] as Map?)
                    ?.containsKey(server.defaultKey) ==
                true)
              type
        ]} of $secretTypes',
    ];
    expect(problems, isEmpty);

    // The account page opens on a tap, then "Continue" before approving.
    expect(find.text(_approveOnWebsite), findsOneWidget);
    // Opened by the tap itself, before any frame: on the web the page
    // opens in the same task as the tap, so no popup blocker stops it.
    await tester.tap(find.text(_openWebsite));
    expect(browser.opened, [Uri.parse(resetPage)]);
    await tester.pump();
    await tap(tester, CommonStrings.promptContinue);
    await _settle(
        tester, () => find.text(_notApprovedYet).evaluate().isNotEmpty);
    expect(server.uploads, hasLength(2));
    expect(server.writes, isEmpty);

    // Approved there; coming back to the app sends the keys again.
    await tap(tester, _openWebsite);
    server.approved = true;
    await leaveAndComeBack(tester);
    await _settle(tester,
        () => find.text('Existing backup found!').evaluate().isNotEmpty);
    expect([for (final (auth, _) in server.uploads.skip(1)) auth],
        everyElement({'session': resetSession}));
    expect(server.uploads.last.$2, isTrue);
    expect(find.text(_approveOnWebsite), findsNothing,
        reason: 'one dialog, closed once the server took the keys');

    await tap(tester, 'Wipe backup');
    await tap(tester, 'Enable backup');
    await _settle(tester,
        () => find.text(CommonStrings.promptDone).evaluate().isNotEmpty);
    await tester.runAsync(
        () => server.expectNewSessionVerifies(recoveryKey, backup: true));
    expect(server.defaultKey, isNot(before));
  });

  testWidgets(
      'a server that asks for the password still gets it, and the reset '
      'goes through',
      skip: skipWithoutVodozemac != false, (tester) async {
    await signIn(tester, ResetKind.password);
    final recoveryKey = await upToTheUpload(tester);
    await _settle(
        tester, () => find.text('Account Password').evaluate().isNotEmpty);
    expect(find.text(_noMethod), findsNothing);
    await tester.enterText(find.byType(TextField).last, accountPassword);
    await tap(tester, CommonStrings.promptSubmit);
    await _settle(tester,
        () => find.text('Existing backup found!').evaluate().isNotEmpty);
    expect(
        server.uploads.map((u) => u.$1?['type']), [null, 'm.login.password']);

    await tap(tester, 'Wipe backup');
    await tap(tester, 'Enable backup');
    await _settle(tester,
        () => find.text(CommonStrings.promptDone).evaluate().isNotEmpty);
    await tester.runAsync(
        () => server.expectNewSessionVerifies(recoveryKey, backup: true));
  });

  testWidgets(
      'a step whose page is not a web page opens nothing and changes '
      'nothing',
      skip: skipWithoutVodozemac != false, (tester) async {
    await signIn(tester, ResetKind.accountService, url: 'javascript:alert(1)');
    await upToTheUpload(tester);
    await _settle(tester, () => find.text(_noMethod).evaluate().isNotEmpty);
    expect(find.text(_openWebsite), findsNothing);
    expect(browser.opened, isEmpty);
    expect(server.writes, isEmpty);
  });

  testWidgets(
      '"Wait, No!" to wiping the verification keys, after wiping the '
      'secret storage, changes nothing on the account',
      skip: skipWithoutVodozemac != false, (tester) async {
    await signIn(tester, ResetKind.accountService);
    final before = server.defaultKey;
    final secrets = await tester.runAsync(() =>
        server.openWith(recoveryKey, types: [...secretTypes, backupType]));
    await openReset(tester);
    await tap(tester, 'Wipe Keys');
    await tap(tester, 'Generate Key');
    await _settle(
        tester,
        () => find
            .textContaining('wipe your cross signing')
            .evaluate()
            .isNotEmpty);
    await tap(tester, 'Wait, No!');
    await _settle(
        tester,
        () => ![BootstrapState.loading, BootstrapState.askWipeCrossSigning]
            .contains(wizard(tester).state));

    expect(server.writes, isEmpty,
        reason: 'a recovery key the person never saw would hold nothing');
    expect(server.uploads, isEmpty);
    expect(server.defaultKey, before);
    expect(
        await tester.runAsync(() =>
            server.openWith(recoveryKey, types: [...secretTypes, backupType])),
        secrets);
    expect(wizard(tester).state, BootstrapState.done);
  });
}
