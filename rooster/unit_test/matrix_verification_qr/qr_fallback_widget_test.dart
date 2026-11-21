@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_qr_verification_payload.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages;
import 'verification_test_harness.dart';

Widget _wrapDialog(Widget child) => MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  late MultiUserVerificationServer server;
  late MatrixClient alice;
  late MatrixClient bob;

  setUpAll(loadFontsAndLanguages);

  tearDown(() async {
    intl.Intl.defaultLocale = null;
  });

  Future<void> setUpClients(WidgetTester tester) async {
    server = MultiUserVerificationServer();
    await tester.runAsync(() async {
      alice = await createAliceClient(server, cacheSsss: true);
      bob = await createBobClient(server);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await alice.close();
        await bob.close();
      });
    });
  }

  Future<(KeyVerification reqAlice, KeyVerification reqBob)> reachAskChoice(
      WidgetTester tester) async {
    late KeyVerification reqAlice;
    late KeyVerification reqBob;
    await tester.runAsync(() async {
      final bobIncoming = Completer<KeyVerification>();
      final sub = bob.matrixClient.onKeyVerificationRequest.stream
          .listen(bobIncoming.complete);

      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;
      reqAlice = await aliceComp.startUserVerification(
        bobUser,
        newDirectChatEnableEncryption: false,
      );
      await relayLastRoomEvent(
        server: server,
        sender: aliceUser,
        recipient: bob.matrixClient,
        eventType: matrix.EventTypes.Message,
      );
      reqBob = await bobIncoming.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      await reqBob.acceptVerification();
      await relayLastRoomEvent(
        server: server,
        sender: bobUser,
        recipient: alice.matrixClient,
        eventType: matrix.EventTypes.KeyVerificationReady,
      );
    });
    return (reqAlice, reqBob);
  }

  testWidgets(
    'desktop/web no-camera fallback: displays PrettyQrView, copies payload, '
    'shows friendly error for corrupted payloads, and completes reciprocation '
    'when valid QR payload is pasted',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await setUpClients(tester);
      final (reqAlice, reqBob) = await reachAskChoice(tester);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;
      final bobComp = bob.getComponent<MatrixKeyVerificationComponent>()!;

      await tester.pumpWidget(
        _wrapDialog(
          MatrixVerificationPage(request: reqAlice, component: aliceComp),
        ),
      );
      await tester.pump();

      // 1. PrettyQrView renders the binary Matrix QR code and Copy works.
      expect(find.byType(PrettyQrView), findsOneWidget);
      expect(
          find.byKey(const ValueKey('verification-qr-view')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('verification-qr-copy')));
      await tester.pump();
      expect(
        clipboardText,
        MatrixQrVerificationPayload.encodeText(
          Uint8List.fromList(reqAlice.qrCode!.qrDataRawBytes),
        ),
      );

      // 2. Empty submit shows friendly error without cancelling verification.
      await tester.tap(find.byKey(const ValueKey('verification-qr-submit')));
      await tester.pump();
      expect(
        find.text(MatrixVerificationPageState.errorVerificationQrEmpty),
        findsOneWidget,
      );
      expect(reqAlice.canceled, isFalse);

      // 3. Corrupted / garbage payload shows friendly decoding error.
      await tester.enterText(
        find.byKey(const ValueKey('verification-qr-payload-field')),
        '%%%corrupted-qr-payload%%%',
      );
      await tester.tap(find.byKey(const ValueKey('verification-qr-submit')));
      await tester.pump();
      expect(
        find.text(
          MatrixVerificationPageState.errorVerificationQrInvalidEncoding,
        ),
        findsOneWidget,
      );
      expect(reqAlice.canceled, isFalse);
      expect(reqAlice.state, KeyVerificationState.askChoice);

      // 4. Truncated Matrix header shows friendly corrupted-payload error.
      final truncated = base64Encode(
        Uint8List.fromList([
          ...ascii.encode('MATRIX'),
          0x02,
          0x00,
          0x00,
          0x04,
          ...utf8.encode('abcd'),
        ]),
      );
      await tester.enterText(
        find.byKey(const ValueKey('verification-qr-payload-field')),
        truncated,
      );
      await tester.tap(find.byKey(const ValueKey('verification-qr-submit')));
      await tester.pump();
      expect(
        find.text(MatrixVerificationPageState.errorVerificationQrTruncated),
        findsOneWidget,
      );
      expect(reqAlice.canceled, isFalse);

      // 5. Pasting Bob's valid QR payload completes reciprocation!
      final bobEncodedQr = MatrixQrVerificationPayload.encodeText(
        Uint8List.fromList(reqBob.qrCode!.qrDataRawBytes),
      );
      await tester.enterText(
        find.byKey(const ValueKey('verification-qr-payload-field')),
        bobEncodedQr,
      );
      await tester.pump();
      // Editing clears previous inline error.
      expect(find.byKey(const ValueKey('verification-qr-error')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('verification-qr-submit')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification-qr-submit')));
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.showQRSuccess &&
            (reqAlice.room?.sendingQueue.isEmpty ?? true) &&
            server.roomEvents.any(
              (e) =>
                  e.sender == aliceUser &&
                  e.eventType == matrix.EventTypes.KeyVerificationStart,
            ),
        reason:
            'Alice transitions to showQRSuccess and sends reciprocate start',
      );
      expect(
        find.byKey(const ValueKey('verification-qr-success-message')),
        findsOneWidget,
      );

      // Relay Alice's reciprocate start to Bob and show Bob's confirm screen.
      await tester.runAsync(() async {
        await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationStart,
        );
      });
      expect(reqBob.state, KeyVerificationState.confirmQRScan);

      await tester.pumpWidget(
        _wrapDialog(
          MatrixVerificationPage(request: reqBob, component: bobComp),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('verification-qr-confirm-message')),
        findsOneWidget,
      );
      await tester
          .tap(find.byKey(const ValueKey('verification-qr-confirm-yes')));
      await settleUntil(
        tester,
        () =>
            reqBob.state == KeyVerificationState.done &&
            (reqBob.room?.sendingQueue.isEmpty ?? true) &&
            (bob.matrixClient.userDeviceKeys[aliceUser]?.outdated == false) &&
            server.roomEvents.any(
              (e) =>
                  e.sender == bobUser &&
                  e.eventType == matrix.EventTypes.KeyVerificationDone,
            ),
        reason:
            'Bob completes verification and sends done after confirming QR scan',
      );
      expect(find.byKey(const ValueKey('verification-done-close')),
          findsOneWidget);

      await tester.runAsync(() async {
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationDone,
        );
      });
      expect(reqAlice.state, KeyVerificationState.done);
    },
  );

  testWidgets(
    'no-camera fallback: loads QR payload from file (raw bytes) and completes reciprocation',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await setUpClients(tester);
      final (reqAlice, reqBob) = await reachAskChoice(tester);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;

      Uint8List? nextFileBytes = Uint8List.fromList(utf8.encode('not-a-qr'));

      await tester.pumpWidget(
        _wrapDialog(
          MatrixVerificationPage(
            request: reqAlice,
            component: aliceComp,
            onLoadQrPayloadFile: () async => nextFileBytes,
          ),
        ),
      );
      await tester.pump();

      // Invalid file shows friendly error and does not cancel.
      await tester.ensureVisible(
        find.byKey(const ValueKey('verification-qr-load-file')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification-qr-load-file')));
      await settleUntil(
        tester,
        () => find
            .byKey(const ValueKey('verification-qr-error'))
            .evaluate()
            .isNotEmpty,
        reason: 'invalid QR file shows inline error',
      );
      expect(reqAlice.canceled, isFalse);

      // Valid raw MATRIX binary file completes reciprocation.
      nextFileBytes = Uint8List.fromList(reqBob.qrCode!.qrDataRawBytes);
      await tester.ensureVisible(
        find.byKey(const ValueKey('verification-qr-load-file')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification-qr-load-file')));
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.showQRSuccess &&
            (reqAlice.room?.sendingQueue.isEmpty ?? true) &&
            server.roomEvents.any(
              (e) =>
                  e.sender == aliceUser &&
                  e.eventType == matrix.EventTypes.KeyVerificationStart,
            ),
        reason: 'valid raw QR file completes reciprocation',
      );
      expect(find.byKey(const ValueKey('verification-qr-error')), findsNothing);
    },
  );

  testWidgets(
    'QR choice UI renders cleanly at 320 px in Portuguese without overflow',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      intl.Intl.defaultLocale = 'pt';

      await setUpClients(tester);
      final (reqAlice, _) = await reachAskChoice(tester);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;

      await tester.pumpWidget(
        _wrapDialog(
          MatrixVerificationPage(request: reqAlice, component: aliceComp),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Verificar com código QR'), findsOneWidget);
      expect(find.text('Copiar código QR'), findsOneWidget);
      expect(find.text('Verificar código QR'), findsOneWidget);
    },
  );
}
