@TestOn('vm')
library;

/// The prompt to verify this device: after a fresh login of an account with
/// cross-signing, as a notice in the Home screen until it is verified, and
/// on the line of a message that did not decrypt. On the SDK's fake
/// homeserver, signed in through the app's own login path.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:rooster/ui/molecules/timeline_events/events/undecrypted_message_line.dart';
import 'package:rooster/ui/organisms/home_screen/home_screen_view.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../speed_log/fake_account.dart' show plainRoom;
import 'device_verification_fakes.dart';

const _why = ValueKey("verify-device-why");
const _recoveryKey = ValueKey("verify-device-recovery-key");
const _otherDevice = ValueKey("verify-device-other-device");
const _later = ValueKey("verify-device-later");
const _line = ValueKey("undecrypted-unverified-device");

/// The Home screen's alerts as the app shows them, redrawn on every
/// alert added or removed, as `HomeScreen` does.
class _Home extends StatefulWidget {
  const _Home(this.manager);
  final ClientManager manager;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final List<StreamSubscription> subscriptions = [
    widget.manager.alertManager.onAlertAdded.listen((_) => setState(() {})),
    widget.manager.alertManager.onAlertRemoved.listen((_) => setState(() {})),
  ];

  @override
  void initState() {
    super.initState();
    subscriptions;
  }

  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      child: HomeScreenView(
          clientManager: widget.manager, rooms: const [], recentActivity: []));
}

Widget _app(Widget home) => MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(body: home),
    );

/// Lets the account's real work (database, crypto, the fake server) run
/// between frames until [done].
Future<void> _settle(WidgetTester tester, bool Function() done,
    {String? reason}) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: reason);
}

void main() {
  late ClientManager manager;
  late MatrixClient client;
  late VerificationServer server;

  setUp(() {
    manager = clientManager = ClientManager();
  });

  Future<void> desktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  }

  /// Signs in the way the login page does: the login flow, then the
  /// account joins the app's clients.
  Future<void> freshLogin(WidgetTester tester, VerificationServer s) async {
    server = s;
    await tester.runAsync(() async {
      client = await newAccount(server);
      final result =
          await client.executeLoginFlow(FakeLogin(verified: s.signed));
      expect(result, isA<Object>());
      manager.addClient(client);
    });
  }

  /// The app opening on an account signed in before: the session comes
  /// from the database and every component runs its post-login setup.
  Future<void> reopen(WidgetTester tester, VerificationServer s) async {
    server = s;
    await tester.runAsync(() async {
      client = await newAccount(server);
      await FakeLogin(verified: s.signed).submit(client);
      manager.addClient(client);
      for (final component in client.getAllComponents()!) {
        if (component is NeedsPostLoginInit) {
          (component as NeedsPostLoginInit).postLoginInit();
        }
      }
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // The profile requests the message started: the fake server answers
    // them on a timer of its own, once their real work ran.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.runAsync(() => client.close());
    await tester.pump(const Duration(seconds: 1));
  }

  MatrixKeyVerificationComponent component() =>
      client.getComponent<MatrixKeyVerificationComponent>()!;

  testWidgets(
      'a fresh login of an account with cross-signing asks to verify this '
      'device, with both ways and why; Later leaves a notice in Home that '
      'opens it again; the recovery key signs the device and the prompt and '
      'the notice go',
      skip: skipWithoutVodozemac != false, (tester) async {
    await desktop(tester);
    await tester.pumpWidget(_app(_Home(manager)));
    await freshLogin(tester, VerificationServer());
    await tester.pumpAndSettle();

    expect(client.matrixClient.isUnknownSession, isTrue);
    expect(client.matrixClient.userDeviceKeys[ownUser]?.masterKey, isNotNull);
    expect(find.text(VerifyThisDevice.labelVerifyThisDevice), findsOneWidget);
    expect(
        find.text(VerifyThisDevice.messageVerifyThisDeviceWhy), findsOneWidget);
    expect(find.byKey(_recoveryKey), findsOneWidget);
    expect(find.byKey(_otherDevice), findsOneWidget);

    // Later: the prompt goes, the app stays usable, the notice stays.
    await tester.tap(find.byKey(_later));
    await tester.pumpAndSettle();
    expect(find.byKey(_why), findsNothing);
    expect(find.text(MatrixKeyVerificationComponent.labelDeviceNotVerified),
        findsOneWidget);
    expect(manager.alertManager.alerts, hasLength(1));

    // The next sync does not ask again: the notice is enough.
    await tester.runAsync(() => emptySync(client, 'later'));
    await tester.pumpAndSettle();
    expect(find.byKey(_why), findsNothing);
    expect(manager.alertManager.alerts, hasLength(1));

    // The notice opens the prompt again.
    await tester
        .tap(find.text(MatrixKeyVerificationComponent.labelDeviceNotVerified));
    await tester.pumpAndSettle();
    expect(find.byKey(_why), findsOneWidget);

    // The recovery key: the cross-signing page asks for it and signs.
    await tester.tap(find.byKey(_recoveryKey));
    await _settle(tester, () => find.byType(TextField).evaluate().isNotEmpty,
        reason: 'the recovery key field');
    await tester.enterText(find.byType(TextField), recoveryKey);
    await tester.ensureVisible(find.text(CommonStrings.promptConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.promptConfirm));
    await _settle(tester, () => !client.matrixClient.isUnknownSession,
        reason: 'this device signed by the account');
    await _settle(tester, () => find.byKey(_why).evaluate().isEmpty,
        reason: 'the prompt closes itself');

    expect(server.uploaded?.keys, isNotEmpty);
    expect(component().needed.value, isFalse);
    expect(manager.alertManager.alerts, isEmpty);
    expect(find.text(MatrixKeyVerificationComponent.labelDeviceNotVerified),
        findsNothing);
    // The key went nowhere but its own use: not in any request.
    for (final body in server.signatureUploads) {
      expect(body, isNot(contains(recoveryKey)));
      expect(body, isNot(contains(recoveryKey.replaceAll(' ', ''))));
    }

    await close(tester);
  });

  for (final (name, s) in [
    (
      'an account without cross-signing',
      () => VerificationServer(crossSigning: false)
    ),
    ('a device already verified', () => VerificationServer(signed: true)),
  ]) {
    testWidgets('$name: no prompt and no notice after a fresh login',
        skip: skipWithoutVodozemac != false, (tester) async {
      await desktop(tester);
      await tester.pumpWidget(_app(_Home(manager)));
      await freshLogin(tester, s());
      await tester.runAsync(() => emptySync(client, 'next'));
      await tester.pumpAndSettle();

      expect(component().needed.value, isFalse);
      expect(find.byKey(_why), findsNothing);
      expect(manager.alertManager.alerts, isEmpty);
      await close(tester);
    });
  }

  testWidgets(
      'opening the app on a device still not verified shows the notice, '
      'not the prompt',
      skip: skipWithoutVodozemac != false, (tester) async {
    await desktop(tester);
    await tester.pumpWidget(_app(_Home(manager)));
    await reopen(tester, VerificationServer());
    await tester.runAsync(() => emptySync(client, 'opened'));
    await tester.pumpAndSettle();

    expect(component().needed.value, isTrue);
    expect(find.byKey(_why), findsNothing);
    expect(find.text(MatrixKeyVerificationComponent.labelDeviceNotVerified),
        findsOneWidget);
    await close(tester);
  });

  Future<MatrixRoom> roomWithUndecrypted(WidgetTester tester) async {
    late MatrixRoom room;
    await tester.runAsync(() async {
      room = await plainRoom(client);
    });
    return room;
  }

  Widget undecrypted(MatrixRoom room) => TimelineEventViewMessage(
      room: room,
      initialEvent: room.convertEvent(matrix.Event(
        type: matrix.EventTypes.Encrypted,
        senderId: '@alice:example.com',
        eventId: r'$undecrypted',
        originServerTs: DateTime(2026, 11, 18),
        room: room.matrixRoom,
        content: {
          'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
          'ciphertext': 'AwgA',
          'device_id': 'JLAFKJWSCS',
          'sender_key': 'L+4+JCl8MD63dgo8z5Ta+9QAHXiANyOVSfgbHA5d3H8',
          'session_id': 'unknown-session',
        },
      )),
      initialIndex: 0,
      overrideShowSender: true);

  testWidgets(
      'on a device not verified the undecrypted message says so and opens '
      'the prompt',
      skip: skipWithoutVodozemac != false, (tester) async {
    await desktop(tester);
    await tester.pumpWidget(_app(const SizedBox()));
    await reopen(tester, VerificationServer());
    final room = await roomWithUndecrypted(tester);
    await tester.pumpWidget(_app(undecrypted(room)));
    await tester.pump();

    expect(
        find.text(UndecryptedMessageLine.messageUndecryptedOnUnverifiedDevice),
        findsOneWidget);
    await tester.tap(find.byKey(_line));
    await tester.pumpAndSettle();
    expect(find.byKey(_why), findsOneWidget);
    await close(tester);
  });

  testWidgets('on a verified device the undecrypted message reads as it did',
      skip: skipWithoutVodozemac != false, (tester) async {
    await desktop(tester);
    await tester.pumpWidget(_app(const SizedBox()));
    await reopen(tester, VerificationServer(signed: true));
    final room = await roomWithUndecrypted(tester);
    await tester.pumpWidget(_app(undecrypted(room)));
    await tester.pump();

    expect(client.matrixClient.isUnknownSession, isFalse);
    expect(find.text("Failed to decrypt event"), findsOneWidget);
    expect(find.byKey(_line), findsNothing);
    await close(tester);
  });
}
