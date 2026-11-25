// The screens of QR code login: the login screen's button and panel (QR
// code, its text, the check code field), and Settings > Security's link
// view (pasted code, the check code it shows).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:rooster/config/global_config.dart';
import 'package:rooster/ui/pages/login/login_page_view.dart';
import 'package:rooster/ui/pages/login/qr_code_login.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/qr_login/qr_link_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'qr_homeserver.dart';

var _clients = 0;

/// A bare SDK client on [server]: the screens need no Rooster account.
Future<matrix.Client> _client(http.Client server) async {
  final client = matrix.Client('qr_widgets_${_clients++}',
      database: await matrix.MatrixSdkDatabase.init('qr_widgets_$_clients',
          database: await databaseFactoryFfi.openDatabase(':memory:',
              options: OpenDatabaseOptions(singleInstance: false)),
          sqfliteFactory: databaseFactoryFfi),
      httpClient: server);
  await client.checkHomeserver(Uri.https(homeserverHost));
  return client;
}

void main() {
  matrix.GetAuthMetadataResponse metadata({bool device = true}) =>
      matrix.GetAuthMetadataResponse.fromJson(
          deviceAuthMetadataJson(device: device));

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
  }

  /// Real time for the database, test time for the 1 s rendezvous polls.
  Future<void> waitUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(finder, findsWidgets);
  }

  /// Closes the screen and lets its last poll see the channel is gone.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 3));
    }
  }

  final button = find.text(QrLoginButton.promptLoginWithQrCode);

  testWidgets('the login screen offers it only with a device grant',
      (tester) async {
    GlobalConfig.data = {'default_homeserver': ''};
    Widget view(matrix.GetAuthMetadataResponse? authMetadata) => LoginPageView(
          isLoggingIn: false,
          isServerValid: true,
          flows: const [],
          authMetadata: authMetadata,
          doQrLogin: () {},
        );
    await tester.pumpWidget(MaterialApp(home: view(metadata())));
    expect(button, findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: view(metadata(device: false))));
    expect(button, findsNothing);
    await tester.pumpWidget(MaterialApp(home: view(null)));
    expect(button, findsNothing);
  });

  testWidgets('the panel replaces the form while signing in', (tester) async {
    GlobalConfig.data = {'default_homeserver': ''};
    await tester.pumpWidget(MaterialApp(
      home: LoginPageView(
        isLoggingIn: true,
        isServerValid: true,
        flows: const [],
        authMetadata: metadata(),
        qrLoginPanel: const Text('panel'),
      ),
    ));
    expect(find.text('panel'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'not covered by the busy overlay');
  });

  group('the new device panel', () {
    testWidgets('shows the QR code and its text, then asks for the number',
        (tester) async {
      final server = QrHomeserver(DeviceGrantServer());
      final client = (await tester.runAsync(() => _client(server)))!;
      await pump(
          tester,
          QrLoginPanel(
            client: client,
            authMetadata: metadata(),
            onSignIn: (_) async {},
            onClose: () {},
          ));
      final text = find.byKey(const ValueKey('qr-login-text'));
      await waitUntil(tester, text);
      expect(find.byType(PrettyQrView), findsOneWidget);
      expect(
          find.text(QrLoginStrings.labelQrLoginWaitingForScan), findsOneWidget);

      // The text is the QR code's bytes: the signed-in device pastes it.
      final pasted = (tester.widget(text) as SelectableText).data!;
      final data = QrCodeData.fromText(pasted);
      expect(data.mode, QrLoginMode.login);
      expect(data.rendezvousUrl.host, homeserverHost);
      // Polls every second of test time, like the panel.
      final connecting = QrSecureChannel.connect(server, data);

      await waitUntil(
          tester, find.byKey(const ValueKey('qr-login-check-code')));
      final other = await connecting;
      expect(
          find.text(QrLoginStrings.labelQrLoginEnterCheckCode), findsOneWidget);
      await tester.runAsync(other.close);
      await close(tester);
    });

    testWidgets('a server without a rendezvous says so', (tester) async {
      final server =
          QrHomeserver(DeviceGrantServer(), announcesRendezvous: false);
      final client = (await tester.runAsync(() => _client(server)))!;
      await pump(
          tester,
          QrLoginPanel(
            client: client,
            authMetadata: metadata(),
            onSignIn: (_) async {},
            onClose: () {},
          ));
      await waitUntil(
          tester, find.text(QrLoginStrings.errorQrLoginServerUnsupported));
      expect(server.rendezvous.log, isEmpty);
    });
  });

  group('Settings > Security, link a new device', () {
    testWidgets('a pasted text that is no sign-in code is refused',
        (tester) async {
      final server = QrHomeserver(DeviceGrantServer());
      final client = (await tester.runAsync(() => _client(server)))!;
      await pump(tester, QrLinkDeviceView(client: client));
      await tester.enterText(
          find.byKey(const ValueKey('qr-link-code')), 'https://example.org');
      await tester.tap(find.byKey(const ValueKey('qr-link-connect')));
      await tester.pump();
      expect(find.text(QrLoginError.errorQrLoginNotALoginCode), findsOneWidget);
      // A code that offers to sign this device in (0x04) is not for here.
      await tester.enterText(
          find.byKey(const ValueKey('qr-link-code')),
          QrCodeData(
                  mode: QrLoginMode.reciprocate,
                  publicKey: List.filled(32, 7),
                  rendezvousUrl: Uri.parse('https://$homeserverHost/r/1'),
                  serverName: homeserverHost)
              .toText());
      await tester.tap(find.byKey(const ValueKey('qr-link-connect')));
      await tester.pump();
      expect(find.text(QrLoginError.errorQrLoginNotALoginCode), findsOneWidget);
      expect(server.rendezvous.log, isEmpty);
    });

    testWidgets('connects with the code and shows the same check code',
        (tester) async {
      final server = QrHomeserver(DeviceGrantServer());
      final client = (await tester.runAsync(() => _client(server)))!;
      final invite = (await tester.runAsync(() => QrLoginInvite.create(
          server, server.rendezvous.endpoint,
          sleep: noSleep)))!;
      await pump(tester, QrLinkDeviceView(client: client));
      await tester.enterText(
          find.byKey(const ValueKey('qr-link-code')), invite.qrCode.toText());
      await tester.tap(find.byKey(const ValueKey('qr-link-connect')));
      final accepted = invite.accept();

      final shown = find.byKey(const ValueKey('qr-link-check-code'));
      await waitUntil(tester, shown);
      final newDevice = await accepted;
      expect((tester.widget(shown) as Text).data, newDevice.checkCode.display);
      expect(find.text(QrLinkDeviceView.labelQrLinkCheckCode), findsOneWidget);
      expect(jsonEncode(server.rendezvous.written), isNot(contains('m.login')));
      await tester.runAsync(newDevice.close);
      await close(tester);
    });
  });
}
