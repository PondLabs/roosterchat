// The login screen's OAuth buttons: "Sign in with <server>" always,
// "Create account" only for a server that announces prompt=create.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/ui/pages/login/oidc_login_buttons.dart';

import 'oidc_fakes.dart';

void main() {
  MatrixOidcLoginFlow flow(matrix.GetAuthMetadataResponse metadata,
          {bool create = false}) =>
      MatrixOidcLoginFlow(
        authMetadata: metadata,
        serverName: homeserverHost,
        createAccount: create,
      );

  Future<List<MatrixOidcLoginFlow>> pump(
    WidgetTester tester,
    List<MatrixOidcLoginFlow> flows, {
    double width = 400,
  }) async {
    final tapped = <MatrixOidcLoginFlow>[];
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OidcLoginButtons(flows: flows, onLogin: tapped.add),
      ),
    ));
    return tapped;
  }

  testWidgets('sign in and create account when create is announced',
      (tester) async {
    final metadata = matrix.GetAuthMetadataResponse.fromJson(
      authMetadataJson(prompts: ['create']),
    );
    final signIn = flow(metadata);
    final create = flow(metadata, create: true);
    final tapped = await pump(tester, [signIn, create]);

    final signInText = OidcLoginButtons.promptLoginOauth(homeserverHost);
    expect(find.text(signInText), findsOneWidget);
    expect(find.text(OidcLoginButtons.promptLoginOauthCreateAccount),
        findsOneWidget);

    await tester.tap(find.text(OidcLoginButtons.promptLoginOauthCreateAccount));
    await tester.tap(find.text(signInText));
    expect(tapped, [create, signIn]);
    expect(tapped.first.createAccount, isTrue);
  });

  testWidgets('no create account button without create', (tester) async {
    final metadata =
        matrix.GetAuthMetadataResponse.fromJson(authMetadataJson());
    await pump(tester, [flow(metadata)]);
    expect(find.text(OidcLoginButtons.promptLoginOauthCreateAccount),
        findsNothing);
    expect(find.text(OidcLoginButtons.promptLoginOauth(homeserverHost)),
        findsOneWidget);
  });

  testWidgets('holds text a third longer at phone width', (tester) async {
    final metadata = matrix.GetAuthMetadataResponse.fromJson(
      authMetadataJson(prompts: ['create']),
    );
    await pump(
      tester,
      [
        MatrixOidcLoginFlow(
          authMetadata: metadata,
          serverName: 'a-rather-long-homeserver-name.example.org',
        ),
        flow(metadata, create: true),
      ],
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });
}
