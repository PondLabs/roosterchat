@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'verification_test_harness.dart';

Widget _app(Widget child) => MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  late MultiUserVerificationServer server;
  late MatrixClient alice;
  late MatrixClient bob;

  Future<void> setUpPair(
    WidgetTester tester, {
    bool cacheAliceSsss = true,
  }) async {
    server = MultiUserVerificationServer();
    await tester.runAsync(() async {
      alice = await createAliceClient(server, cacheSsss: cacheAliceSsss);
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

  testWidgets(
    'UserProfile shows Verify user entry point for another user and sends '
    'in-room m.key.verification.request',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await setUpPair(tester, cacheAliceSsss: true);

      await tester.pumpWidget(
        _app(
          UserProfile(
            userId: bobUser,
            client: alice,
            doSafeArea: false,
          ),
        ),
      );

      // Wait for async profile load.
      for (var i = 0;
          i < 40 && find.byType(UserProfileView).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const ValueKey('user-profile-verify')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('user-profile-verify')));
      for (var i = 0;
          i < 40 && find.byType(MatrixVerificationPage).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(MatrixVerificationPage), findsOneWidget);
      final reqEvent = server.roomEvents.firstWhere(
        (e) =>
            e.eventType == matrix.EventTypes.Message &&
            e.content['msgtype'] == matrix.EventTypes.KeyVerificationRequest,
      );
      expect(reqEvent.content['to'], bobUser);
      expect(
        reqEvent.content['methods'],
        containsAll([
          matrix.EventTypes.Sas,
          matrix.EventTypes.QRShow,
          matrix.EventTypes.QRScan,
          matrix.EventTypes.Reciprocate,
        ]),
      );
    },
  );

  testWidgets(
    'other-user verification via SAS unlocks SSSS, compares emoji, and signs '
    'other user master key with user_signing',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Start with SSSS NOT cached so the askSSSS UI step is also exercised.
      await setUpPair(tester, cacheAliceSsss: false);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;

      late KeyVerification reqAlice;
      await tester.runAsync(() async {
        reqAlice = await aliceComp.startUserVerification(
          bobUser,
          newDirectChatEnableEncryption: false,
        );
      });
      expect(reqAlice.state, KeyVerificationState.askSSSS);

      await tester.pumpWidget(
        _app(
          MatrixVerificationPage(request: reqAlice, component: aliceComp),
        ),
      );
      await tester.pump();

      // Wrong recovery key shows inline error and keeps verification open.
      await tester.enterText(
        find.byKey(const ValueKey('verification-ssss-field')),
        'wrong-recovery-key',
      );
      await tester.tap(find.byKey(const ValueKey('verification-ssss-submit')));
      await settleUntil(
        tester,
        () => find
            .text(MatrixVerificationPageState.errorVerificationSsssUnlockFailed)
            .evaluate()
            .isNotEmpty,
        reason: 'wrong recovery key displays inline SSSS error',
      );
      expect(reqAlice.state, KeyVerificationState.askSSSS);

      // Correct recovery key unlocks SSSS and sends m.key.verification.request.
      await tester.enterText(
        find.byKey(const ValueKey('verification-ssss-field')),
        recoveryKey,
      );
      await tester.tap(find.byKey(const ValueKey('verification-ssss-submit')));
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.waitingAccept &&
            (reqAlice.room?.sendingQueue.isEmpty ?? true),
        reason: 'valid recovery key unlocks SSSS and sends request',
      );

      // Deliver request to Bob and accept.
      late KeyVerification reqBob;
      await tester.runAsync(() async {
        final incoming = Completer<KeyVerification>();
        final sub = bob.matrixClient.onKeyVerificationRequest.stream
            .listen(incoming.complete);
        await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: matrix.EventTypes.Message,
        );
        reqBob = await incoming.future.timeout(const Duration(seconds: 5));
        await sub.cancel();

        await reqBob.acceptVerification();
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationReady,
        );
      });
      await tester.pump();
      expect(reqAlice.state, KeyVerificationState.askChoice);

      // Alice chooses SAS ("Compare emoji instead") from the UI.
      await tester.ensureVisible(
        find.byKey(const ValueKey('verification-start-sas')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification-start-sas')));
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.waitingAccept &&
            (reqAlice.room?.sendingQueue.isEmpty ?? true) &&
            server.roomEvents.any(
              (e) =>
                  e.sender == aliceUser &&
                  e.eventType == matrix.EventTypes.KeyVerificationStart,
            ),
        reason: 'Alice sends SAS start event',
      );

      // Relay SAS start -> accept -> key -> key between Alice and Bob.
      await tester.runAsync(() async {
        await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationStart,
        );
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationAccept,
        );
        await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: 'm.key.verification.key',
        );
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: 'm.key.verification.key',
        );
      });
      await tester.pump();

      expect(reqAlice.state, KeyVerificationState.askSas);
      expect(reqBob.state, KeyVerificationState.askSas);
      expect(
        reqAlice.sasEmojis.map((e) => e.number).toList(),
        reqBob.sasEmojis.map((e) => e.number).toList(),
      );

      // Alice confirms emoji in the UI; Bob confirms too; relay MACs.
      await tester.ensureVisible(
        find.byKey(const ValueKey('verification-sas-accept')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification-sas-accept')));
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.waitingSas &&
            (reqAlice.room?.sendingQueue.isEmpty ?? true) &&
            server.roomEvents.any(
              (e) =>
                  e.sender == aliceUser &&
                  e.eventType == 'm.key.verification.mac',
            ),
        reason: 'Alice sends SAS MAC',
      );
      await tester.runAsync(() async {
        await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: 'm.key.verification.mac',
        );
        await reqBob.acceptSas();
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: 'm.key.verification.mac',
        );
      });
      await settleUntil(
        tester,
        () =>
            reqAlice.state == KeyVerificationState.done &&
            server.signatureUploads.isNotEmpty,
        reason: 'Alice finishes SAS and uploads user_signing signature',
      );

      expect(reqAlice.state, KeyVerificationState.done);
      expect(reqBob.state, KeyVerificationState.done);
      expect(
        find.byKey(const ValueKey('verification-done-close')),
        findsOneWidget,
      );

      // Verify Alice signed Bob's master key with Alice's user_signing key.
      expect(server.signatureUploads, isNotEmpty);
      final signedBobMaster = server.signatureUploads.last[bobUser]
          ?[bobMasterKey] as Map<String, dynamic>?;
      expect(signedBobMaster, isNotNull);
      final signature = signedBobMaster!['signatures']?[aliceUser]
          ?['ed25519:$aliceUserSigningKey'] as String?;
      expect(signature, isNotNull);

      final bobMaster = alice.matrixClient.userDeviceKeys[bobUser]!.masterKey!;
      vod.Ed25519PublicKey.fromBase64(aliceUserSigningKey).verify(
        message: bobMaster.signingContent,
        signature: vod.Ed25519Signature.fromBase64(signature!),
      );

      // Refreshing user keys picks up the server-stored user_signing signature
      // so Bob's master key is now cross-verified.
      await tester.runAsync(() => aliceComp.refreshUserKeys(bobUser));
      expect(
        alice.matrixClient.userDeviceKeys[bobUser]!.masterKey!.crossVerified,
        isTrue,
      );
    },
  );

  testWidgets(
    'clean cancellation when the other user cancels the verification',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await setUpPair(tester, cacheAliceSsss: true);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;

      late KeyVerification reqAlice;
      late KeyVerification reqBob;
      await tester.runAsync(() async {
        final incoming = Completer<KeyVerification>();
        final sub = bob.matrixClient.onKeyVerificationRequest.stream
            .listen(incoming.complete);

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
        reqBob = await incoming.future.timeout(const Duration(seconds: 5));
        await sub.cancel();
      });

      await tester.pumpWidget(
        _app(
          MatrixVerificationPage(request: reqAlice, component: aliceComp),
        ),
      );
      await tester.pump();

      // Bob rejects/cancels the incoming request.
      await tester.runAsync(() async {
        await reqBob.rejectVerification();
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationCancel,
        );
      });
      await tester.pump();

      expect(reqAlice.canceled, isTrue);
      expect(reqAlice.canceledCode, 'm.user');
      expect(reqAlice.state, KeyVerificationState.error);
      expect(
        find.byKey(const ValueKey('verification-error-message')),
        findsOneWidget,
      );
      expect(find.text('Verification was cancelled.'), findsOneWidget);
      expect(server.signatureUploads, isEmpty);
      expect(
        alice.matrixClient.userDeviceKeys[bobUser]?.masterKey?.verified,
        isFalse,
      );
    },
  );

  testWidgets(
    'clean cancellation when the verification expires (m.timeout)',
    skip: skipWithoutVodozemac != false,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await setUpPair(tester, cacheAliceSsss: true);
      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;

      late KeyVerification reqAlice;
      await tester.runAsync(() async {
        reqAlice = await aliceComp.startUserVerification(
          bobUser,
          newDirectChatEnableEncryption: false,
        );
      });

      await tester.pumpWidget(
        _app(
          MatrixVerificationPage(request: reqAlice, component: aliceComp),
        ),
      );
      await tester.pump();

      // Simulate inactivity beyond the Matrix 10-minute verification timeout
      // and run cleanup, which cancels cleanly with m.timeout.
      await tester.runAsync(() async {
        reqAlice.lastActivity =
            DateTime.now().subtract(const Duration(minutes: 11));
        await alice.matrixClient.encryption!.keyVerificationManager.cleanup();
      });
      await tester.pump();

      expect(reqAlice.canceled, isTrue);
      expect(reqAlice.canceledCode, 'm.timeout');
      expect(reqAlice.state, KeyVerificationState.error);
      expect(
        find.text('Verification timed out. Start a new request to try again.'),
        findsOneWidget,
      );

      final cancelEvt = server.roomEvents.lastWhere(
        (e) => e.eventType == matrix.EventTypes.KeyVerificationCancel,
      );
      expect(cancelEvt.content['code'], 'm.timeout');
      expect(server.signatureUploads, isEmpty);
      expect(
        alice.matrixClient.userDeviceKeys[bobUser]?.masterKey?.verified,
        isFalse,
      );
    },
  );

  testWidgets(
    'UserProfileView hides Verify user button for own profile and preview mode',
    (tester) async {
      await tester.pumpWidget(
        _app(
          UserProfileView(
            displayName: 'Alice',
            userColor: Colors.teal,
            identifier: aliceUser,
            isSelf: true,
            doSafeArea: false,
            onVerifyUser: () async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('user-profile-verify')), findsNothing);

      await tester.pumpWidget(
        _app(
          UserProfileView(
            displayName: 'Bob',
            userColor: Colors.teal,
            identifier: bobUser,
            isSelf: false,
            preview: true,
            doSafeArea: false,
            onVerifyUser: () async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('user-profile-verify')), findsNothing);

      await tester.pumpWidget(
        _app(
          UserProfileView(
            displayName: 'Bob',
            userColor: Colors.teal,
            identifier: bobUser,
            isSelf: false,
            preview: false,
            doSafeArea: false,
            onVerifyUser: () async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('user-profile-verify')), findsOneWidget);
    },
  );
}
