// The screens around the account actions: the terms dialog only continues
// with every policy accepted, a closed UIA dialog ends its request, the
// deactivation button stays off until the explicit confirmation (and no
// request goes out before it), the account page of an OAuth server shows
// only the actions it announces, and registration errors read as such.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/ui/pages/login/register_view.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:rooster/ui/pages/matrix/authentication/uia_dialog_prompter.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_management/matrix_account_settings.dart';
import 'package:rooster/utils/common_strings.dart';

import '../matrix_auth_oidc/oidc_fakes.dart' show newAccount;
import 'lifecycle_fakes.dart';

void main() {
  Future<BuildContext> pumpHome(WidgetTester tester, [Widget? child]) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          context = c;
          return SingleChildScrollView(child: child ?? const SizedBox());
        }),
      ),
    ));
    return context;
  }

  ElevatedButton button(WidgetTester tester, String text) =>
      tester.widget<ElevatedButton>(find.ancestor(
          of: find.text(text), matching: find.byType(ElevatedButton)));

  testWidgets('the terms continue only with every policy accepted',
      (tester) async {
    final context = await pumpHome(tester);
    final accepted = DialogUiaPrompter(context).acceptTerms([
      UiaTermsPolicy('privacy', '1', 'Privacy Policy',
          Uri(scheme: 'https', host: 'example.org', path: 'privacy')),
      UiaTermsPolicy('tos', '2', 'Terms of Service',
          Uri(scheme: 'https', host: 'example.org', path: 'tos')),
    ]);
    await tester.pumpAndSettle();

    expect(find.text(DialogUiaPrompter.promptUiaAcceptPolicy('Privacy Policy')),
        findsOneWidget);
    expect(button(tester, CommonStrings.promptContinue).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('uia-terms-privacy')));
    await tester.pump();
    expect(button(tester, CommonStrings.promptContinue).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('uia-terms-tos')));
    await tester.pump();
    await tester.tap(find.text(CommonStrings.promptContinue));
    await tester.pumpAndSettle();

    expect(await accepted, isTrue);
  });

  testWidgets('a closed terms dialog is a refusal', (tester) async {
    final context = await pumpHome(tester);
    final accepted = DialogUiaPrompter(context).acceptTerms([]);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await accepted, isFalse);
  });

  testWidgets('closing the password dialog ends the request', (tester) async {
    final context = await pumpHome(tester);
    final endpoint = UiaEndpoint([
      ['m.login.password']
    ]);
    final server = FakeAccountServer(
        {'POST /_matrix/client/v3/account/deactivate': endpoint.call});
    Object? outcome;
    unawaited(server
        .lifecycle()
        .deactivate(
            confirmed: true, erase: false, prompter: DialogUiaPrompter(context))
        .then((_) => outcome = 'done', onError: (Object e) => outcome = e));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    expect(find.text(DialogUiaPrompter.labelUiaPassword), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(Duration.zero));

    expect(outcome, isA<UiaCancelledException>());
    expect(endpoint.completed, isEmpty);
    expect(server.requests, hasLength(1));
  });

  testWidgets('a closed Client.onUiaRequest dialog ends its request',
      (tester) async {
    final client = (await tester.runAsync(() => newAccount(
        MockClient((_) async => json({'errcode': 'M_UNRECOGNIZED'}, 404)))))!;
    final uia = UiaRequest(
        request: (auth) async => throw MatrixException.fromJson({
              'session': 'uia-session',
              'flows': [
                {
                  'stages': ['m.login.password']
                }
              ],
            }));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    expect(uia.state, UiaRequestState.waitForUser);

    await pumpHome(tester, MatrixUIARequest(uia, client));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(uia.state, UiaRequestState.fail);
  });

  group('deactivation', () {
    late FakeAccountServer server;
    late FakePrompter prompter;

    setUp(() {
      server = FakeAccountServer({
        'POST /_matrix/client/v3/account/deactivate': UiaEndpoint([
          ['m.login.password']
        ], success: {
          'id_server_unbind_result': 'success'
        }).call,
      });
      prompter = FakePrompter()..passwords.add('secret');
    });

    Future<void> open(WidgetTester tester) => pumpHome(
        tester,
        DeactivateAccountView(
            lifecycle: server.lifecycle(), prompter: prompter));

    testWidgets('the button stays off, and sends nothing, unconfirmed',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('deactivate-erase')));
      await tester.pump();

      final submit = find.byKey(const ValueKey('deactivate-submit'));
      expect(
          tester
              .widget<ElevatedButton>(find.descendant(
                  of: submit, matching: find.byType(ElevatedButton)))
              .onPressed,
          isNull);
      await tester.tap(submit, warnIfMissed: false);
      await tester.pump();

      expect(server.requests, isEmpty);
      expect(prompter.asked, isEmpty);
    });

    testWidgets('confirmed, it deactivates with erase', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('deactivate-erase')));
      await tester.tap(find.byKey(const ValueKey('deactivate-confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('deactivate-submit')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
      }

      final bodies = server.bodies('/_matrix/client/v3/account/deactivate');
      expect(bodies.map((b) => b['erase']), [true, true]);
      expect((bodies.last['auth'] as Map)['password'], 'secret');
    });
  });

  testWidgets('an OAuth server shows only the actions it announces',
      (tester) async {
    final server = FakeAccountServer({
      'GET /_matrix/client/v1/auth_metadata': (_) => json({
            'issuer': 'https://auth.example.org/',
            'authorization_endpoint': 'https://auth.example.org/authorize',
            'token_endpoint': 'https://auth.example.org/token',
            'response_types_supported': ['code'],
            'response_modes_supported': ['query'],
            'grant_types_supported': ['authorization_code'],
            'code_challenge_methods_supported': ['S256'],
            'account_management_uri': 'https://account.example.org/',
            'account_management_actions_supported': [
              'org.matrix.profile',
              'org.matrix.sessions_list',
            ],
          }),
    });
    await pumpHome(
        tester, MatrixAccountSettings(lifecycle: server.lifecycle()));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    expect(
        find.text(MatrixAccountSettings.promptAccountProfile), findsOneWidget);
    expect(
        find.text(MatrixAccountSettings.promptAccountSessions), findsOneWidget);
    expect(
        find.text(MatrixAccountSettings.promptAccountManage), findsOneWidget);
    expect(find.text(MatrixAccountSettings.promptAccountResetIdentity),
        findsNothing);
    expect(
        find.text(MatrixAccountSettings.labelDeactivateAccount), findsNothing);
    // Nothing of the legacy API is asked on such a server.
    expect(find.text(MatrixAccountSettings.promptChangePassword), findsNothing);
    expect(server.requests.map((r) => r.url.path),
        ['/_matrix/client/v1/auth_metadata']);
  });

  testWidgets('a taken username reads as such on the form', (tester) async {
    final server = FakeAccountServer({
      'POST /_matrix/client/v3/register': (_) =>
          json({'errcode': 'M_USER_IN_USE', 'error': 'taken'}, 400),
    });
    await pumpHome(
        tester,
        RegisterView(
            lifecycle: MatrixAccountLifecycle(server.api(signedIn: false)),
            prompter: FakePrompter()));
    await tester.enterText(
        find.byKey(const ValueKey('register-username')), 'alice');
    await tester.enterText(
        find.byKey(const ValueKey('register-password')), 'passphrase');
    await tester.enterText(
        find.byKey(const ValueKey('register-confirm')), 'passphrase');
    await tester.tap(find.text(RegisterView.promptLoginCreateAccount));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    expect(find.text(RegisterView.errorRegisterUserInUse), findsOneWidget);
  });

  testWidgets('registration does not start with passwords that differ',
      (tester) async {
    final server = FakeAccountServer();
    await pumpHome(
        tester,
        RegisterView(
            lifecycle: MatrixAccountLifecycle(server.api(signedIn: false)),
            prompter: FakePrompter()));
    await tester.enterText(
        find.byKey(const ValueKey('register-password')), 'one');
    await tester.enterText(
        find.byKey(const ValueKey('register-confirm')), 'two');
    await tester.tap(find.text(RegisterView.promptLoginCreateAccount));
    await tester.pump();

    expect(find.text(RegisterView.errorPasswordsDiffer), findsOneWidget);
    expect(server.requests, isEmpty);
  });
}
