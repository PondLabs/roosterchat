// The login screen's device grant: the button only for a server with a
// device authorization endpoint, and the panel with the code, its copy
// buttons and cancel.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/config/global_config.dart';
import 'package:rooster/ui/pages/login/device_auth_login.dart';
import 'package:rooster/ui/pages/login/login_page_view.dart';
import 'package:rooster/utils/common_strings.dart';

import 'device_grant_fakes.dart';

void main() {
  matrix.GetAuthMetadataResponse metadata({bool device = true}) =>
      matrix.GetAuthMetadataResponse.fromJson(
          deviceAuthMetadataJson(device: device));

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
  }

  final button = find.text(DeviceAuthLoginButton.promptLoginDeviceAuth);

  group('the button', () {
    testWidgets('shown with a device authorization endpoint', (tester) async {
      var tapped = 0;
      await pump(
          tester,
          DeviceAuthLoginButton(
            authMetadata: metadata(),
            onPressed: () => tapped++,
          ));
      expect(button, findsOneWidget);
      await tester.tap(button);
      expect(tapped, 1);
    });

    testWidgets('hidden without one, or without auth_metadata', (tester) async {
      await pump(
          tester,
          Column(children: [
            DeviceAuthLoginButton(
                authMetadata: metadata(device: false), onPressed: () {}),
            const DeviceAuthLoginButton(authMetadata: null, onPressed: null),
          ]));
      expect(button, findsNothing);
    });

    Widget view(matrix.GetAuthMetadataResponse? authMetadata) => LoginPageView(
          isLoggingIn: false,
          isServerValid: true,
          flows: const [],
          authMetadata: authMetadata,
          doDeviceLogin: () {},
        );

    testWidgets('on the login screen only for such a server', (tester) async {
      // No homeserver typed: the view checks nothing on its own.
      GlobalConfig.data = {'default_homeserver': ''};
      await tester.pumpWidget(MaterialApp(home: view(metadata())));
      expect(button, findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: view(metadata(device: false))));
      expect(button, findsNothing);

      await tester.pumpWidget(MaterialApp(home: view(null)));
      expect(button, findsNothing);
    });
  });

  testWidgets('while it polls the panel replaces the form and stays usable',
      (tester) async {
    GlobalConfig.data = {'default_homeserver': ''};
    final flow = MatrixDeviceAuthFlow(authMetadata: metadata());
    await tester.pumpWidget(MaterialApp(
      home: LoginPageView(
        isLoggingIn: true,
        isServerValid: true,
        flows: const [],
        authMetadata: metadata(),
        deviceAuthFlow: flow,
      ),
    ));
    expect(find.byType(DeviceAuthPanel), findsOneWidget);
    expect(button, findsOneWidget, reason: 'the panel title');
    await tester.tap(find.byKey(const ValueKey('device-auth-cancel')));
    expect(flow.isCancelled, isTrue);
  });

  group('the panel', () {
    final copied = <String>[];
    setUp(() {
      copied.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    testWidgets('waits for the code, then shows it with its link',
        (tester) async {
      final flow = MatrixDeviceAuthFlow(authMetadata: metadata());
      await pump(tester, DeviceAuthPanel(flow: flow));
      expect(find.text(DeviceAuthPanel.labelDeviceAuthWaitingForCode),
          findsOneWidget);

      flow.prompt.value = DeviceAuthorizationPrompt(
        userCode: 'ABCD-EFGH',
        verificationUri: Uri.parse('https://auth.example.org/link'),
        verificationUriComplete:
            Uri.parse('https://auth.example.org/link?code=ABCD-EFGH'),
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      await tester.pump();

      expect(find.text('ABCD-EFGH'), findsOneWidget);
      expect(find.text('https://auth.example.org/link?code=ABCD-EFGH'),
          findsOneWidget);
      expect(find.text(DeviceAuthPanel.labelDeviceAuthWaitingForApproval),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('device-auth-copy-code')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('device-auth-copy-link')));
      await tester.pump();
      expect(copied,
          ['ABCD-EFGH', 'https://auth.example.org/link?code=ABCD-EFGH']);
      expect(find.text(CommonStrings.promptCopyComplete), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('device-auth-cancel')));
      expect(flow.isCancelled, isTrue);
    });

    testWidgets('fits a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final flow = MatrixDeviceAuthFlow(authMetadata: metadata())
        ..prompt.value = DeviceAuthorizationPrompt(
          userCode: 'ABCD-EFGH',
          verificationUri: Uri.parse('https://auth.example.org/link'),
          expiresAt: DateTime.now(),
        );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DeviceAuthPanel(flow: flow))),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('https://auth.example.org/link'), findsOneWidget);
    });
  });
}
