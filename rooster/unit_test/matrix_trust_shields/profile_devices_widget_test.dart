@TestOn('vm')
library;

/// Account 1 opens account 2's profile: it lists both of account 2's
/// devices with their verification, the Block button blocks and unblocks
/// one in the SDK, and the shields (profile, room header, member list)
/// raise the alert once the identity account 1 verified is replaced.
/// Real encryption (vodozemac) on a homeserver in memory.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/room_header.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:rooster/ui/organisms/room_members_list/room_members_list.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';

/// Two made-up master keys of account 2: the one account 1 verifies, and
/// the one that replaces it.
final _firstMaster = 'A' * 43;
final _newMaster = 'B' * 43;

Widget _app(Widget child) => MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  late FakeHomeserver server;
  late MatrixClient alice;
  final signedIn = <MatrixClient>[];

  Future<void> setUpAccounts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The calls' WebRTC plugin, which a Matrix account starts listening to.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await tester.runAsync(() async {
      await setUpEncryption();
      // No verified identity left from another test.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      VerifiedIdentities.resetForTest();
      server = FakeHomeserver();
      signedIn.clear();
      alice = await signIn(server, _alice, 'ALICEPC');
      signedIn.add(await signIn(server, _bob, 'BOBPC'));
      signedIn.add(await signIn(server, _bob, 'BOBPHONE'));
      signedIn.add(alice);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (final client in signedIn) {
          await client.close();
        }
      });
    });
  }

  matrix.DeviceKeysList bobKeys() => alice.matrixClient.userDeviceKeys[_bob]!;

  /// Pumps on real time until [done] holds (5 s at most).
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// Pumps until [found] finds something.
  Future<void> waitFor(WidgetTester tester, Finder found) async {
    await pumpUntil(tester, () => found.evaluate().isNotEmpty);
    expect(found, findsWidgets);
  }

  Future<void> openBobsProfile(WidgetTester tester) async {
    await tester.pumpWidget(_app(UserProfile(
        key: UniqueKey(), userId: _bob, client: alice, doSafeArea: false)));
    await waitFor(tester, find.byType(UserProfileView));
    await waitFor(tester, find.byKey(const ValueKey('user-profile-sessions')));
  }

  Finder inSession(String deviceId, Finder finder) => find.descendant(
      of: find.byKey(ValueKey('user-profile-session-$deviceId')),
      matching: finder);

  /// Account 1 verifies account 2's identity and both devices, as a
  /// finished verification leaves them.
  Future<void> verifyBob(WidgetTester tester) async {
    await tester.runAsync(() async {
      server.masterKeys[_bob] = _firstMaster;
      alice.matrixClient.userDeviceKeys[_bob]?.outdated = true;
      await alice.matrixClient.updateUserDeviceKeys(additionalUsers: {_bob});
      bobKeys().masterKey!.setDirectVerified(true);
      for (final device in bobKeys().deviceKeys.values) {
        device.setDirectVerified(true);
      }
    });
  }

  /// Account 2 resets cross-signing: a new master key, which account 1
  /// never verified.
  Future<void> bobReplacesIdentity(WidgetTester tester) async {
    await tester.runAsync(() async {
      server.masterKeys[_bob] = _newMaster;
      alice.matrixClient.userDeviceKeys[_bob]?.outdated = true;
      await alice.matrixClient.updateUserDeviceKeys(additionalUsers: {_bob});
    });
    expect(bobKeys().masterKey!.ed25519Key, _newMaster);
  }

  testWidgets(
      'the profile lists every device with its verification, and Block / '
      'Unblock writes setBlocked to the SDK',
      skip: vodozemacSkip != false, (tester) async {
    final semantics = tester.ensureSemantics();
    await setUpAccounts(tester);
    await tester.runAsync(() async {
      await alice.matrixClient.updateUserDeviceKeys(additionalUsers: {_bob});
      // Account 1 verified account 2's computer, not their phone.
      await bobKeys().deviceKeys['BOBPC']!.setVerified(true, false);
    });

    await openBobsProfile(tester);
    expect(find.text('2 sessions'), findsOneWidget);
    await tester.tap(find.text('2 sessions'));
    await tester.pumpAndSettle();

    expect(inSession('BOBPC', find.text('BOBPC')), findsOneWidget);
    expect(inSession('BOBPHONE', find.text('BOBPHONE')), findsOneWidget);
    expect(
        inSession('BOBPC', find.bySemanticsLabel('Verified')), findsOneWidget);
    expect(inSession('BOBPHONE', find.bySemanticsLabel('Not verified')),
        findsOneWidget);
    // One device not verified: account 2 is not verified.
    expect(
        tester.getSemantics(find.byKey(const ValueKey('user-profile-trust'))),
        matchesSemantics(label: 'Not verified'));

    final block =
        find.byKey(const ValueKey('user-profile-session-block-BOBPHONE'));
    expect(find.descendant(of: block, matching: find.text('Block')),
        findsOneWidget);
    await tester.tap(block);
    await waitFor(
        tester, inSession('BOBPHONE', find.bySemanticsLabel('Blocked')));
    expect(bobKeys().deviceKeys['BOBPHONE']!.blocked, isTrue);
    expect(bobKeys().deviceKeys['BOBPC']!.blocked, isFalse,
        reason: 'only the device tapped');
    expect(find.descendant(of: block, matching: find.text('Unblock')),
        findsOneWidget);
    // Stored, not only in memory: what the SDK reads at the next start.
    final stored = await tester.runAsync(() =>
        alice.matrixClient.database.getUserDeviceKeys(alice.matrixClient));
    expect(stored![_bob]!.deviceKeys['BOBPHONE']!.blocked, isTrue);

    await tester.tap(block);
    await waitFor(
        tester, inSession('BOBPHONE', find.bySemanticsLabel('Not verified')));
    expect(bobKeys().deviceKeys['BOBPHONE']!.blocked, isFalse);
    expect(find.descendant(of: block, matching: find.text('Block')),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      'a verified user whose master key changes gets the alert on the '
      'profile, which Withdraw verification clears',
      skip: vodozemacSkip != false, (tester) async {
    final semantics = tester.ensureSemantics();
    await setUpAccounts(tester);
    await verifyBob(tester);

    await openBobsProfile(tester);
    await waitFor(tester, find.bySemanticsLabel('Verified'));
    // The profile remembered the identity account 1 verified.
    await pumpUntil(tester,
        () => VerifiedIdentities.loadedFor(_alice)?.keyOf(_bob) != null);
    expect(VerifiedIdentities.loadedFor(_alice)!.keyOf(_bob), _firstMaster);
    expect(
        tester.getSemantics(find.byKey(const ValueKey('user-profile-trust'))),
        matchesSemantics(label: 'Verified'));
    expect(find.byKey(const ValueKey('user-profile-identity-changed')),
        findsNothing);

    await bobReplacesIdentity(tester);
    // Opened again: what was verified was kept.
    await tester.pumpWidget(const SizedBox());
    VerifiedIdentities.resetForTest();
    await openBobsProfile(tester);
    await waitFor(
        tester, find.byKey(const ValueKey('user-profile-identity-changed')));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('user-profile-trust'))),
        matchesSemantics(label: 'Identity changed'));
    expect(find.textContaining("identity changed since you verified them"),
        findsOneWidget);
    expect(find.byKey(const ValueKey('user-profile-verify')), findsOneWidget,
        reason: 'the way to verify them again');

    await tester
        .tap(find.byKey(const ValueKey('user-profile-withdraw-verification')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byKey(const ValueKey('user-profile-identity-changed')),
        findsNothing);
    expect(
        tester.getSemantics(find.byKey(const ValueKey('user-profile-trust'))),
        isNot(matchesSemantics(label: 'Identity changed')));
    semantics.dispose();
  });

  testWidgets(
      'the room header and the member list show the shield of an encrypted '
      'room and raise the alert when a verified member changes identity',
      skip: vodozemacSkip != false, (tester) async {
    final semantics = tester.ensureSemantics();
    await setUpAccounts(tester);
    late MatrixRoom room;
    await tester.runAsync(() async {
      room = await alice.createRoom(CreateRoomArgs(
        name: 'Private',
        visibility: RoomVisibilityPrivate(),
        enableE2EE: true,
      )) as MatrixRoom;
      await until(() => room.matrixRoom.encrypted, what: 'encryption on');
      await room.matrixRoom.invite(_bob);
      await signedIn.first.joinRoom(room.identifier);
      await until(() => hasMember(room, _bob), what: 'account 2 joined');
      await alice.matrixClient.updateUserDeviceKeys(additionalUsers: {_bob});
    });

    Widget roomViews() => Column(children: [
          SizedBox(height: 50, child: RoomHeader(room, key: UniqueKey())),
          SizedBox(
              height: 400,
              child: RoomMembersListWidget(room, key: UniqueKey())),
        ]);
    final header = find.byKey(const ValueKey('room-header-trust'));
    final members = find.byKey(const ValueKey('room-members-trust'));
    final bobRow = find.byKey(const ValueKey('room-user-list-trust-$_bob'));
    Future<void> showRoom() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(roomViews()));
      await waitFor(tester, bobRow);
      // The shields read the verified identities once they are loaded.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    String? labelOf(Finder finder) => tester
        .getSemantics(find.descendant(
            of: finder, matching: find.bySemanticsLabel(RegExp('.'))))
        .label;

    await showRoom();
    expect(labelOf(header), 'Not verified');
    expect(labelOf(members), 'Not verified');
    expect(labelOf(bobRow), 'Not verified');
    expect(find.byKey(const ValueKey('room-user-list-trust-$_alice')),
        findsNothing,
        reason: 'no shield on ourselves');

    await verifyBob(tester);
    await showRoom();
    expect(labelOf(header), 'Verified');
    expect(labelOf(bobRow), 'Verified');

    await bobReplacesIdentity(tester);
    await showRoom();
    expect(labelOf(header), 'Identity changed');
    expect(labelOf(members), 'Identity changed');
    expect(labelOf(bobRow), 'Identity changed');
    semantics.dispose();
  });
}
