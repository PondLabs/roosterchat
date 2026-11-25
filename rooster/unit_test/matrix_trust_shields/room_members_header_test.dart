@TestOn('vm')
library;

/// The header over a room's members (its title and the room's shield)
/// lays out both where the desktop side panel gives it no width limit
/// (the panel sits unsized in the main page's row) and in a narrow
/// column, and keeps the shield of an encrypted room in both. The room
/// is on a homeserver in memory; the shield only needs the room's
/// encryption state, so no vodozemac.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:rooster/ui/organisms/room_members_list/room_members_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';

final _title = find.text('Room Members');
final _shield = find.descendant(
    of: find.byKey(const ValueKey('room-members-trust')),
    matching: find.byType(E2eeTrustShield));

void main() {
  late MatrixClient alice;
  late MatrixRoom room;

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    VerifiedIdentities.resetForTest();
  });

  Future<void> setUpRoom(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The calls' WebRTC plugin, which a Matrix account starts listening to.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await tester.runAsync(() async {
      await preferences.init();
      alice = await signIn(FakeHomeserver(), _alice, 'ALICEPC');
      room = await alice.createRoom(CreateRoomArgs(
        name: 'Private',
        visibility: RoomVisibilityPrivate(),
        enableE2EE: true,
      )) as MatrixRoom;
      await until(() => room.matrixRoom.encrypted, what: 'encryption on');
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(alice.close);
    });
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(body: child),
    ));
    // The shield reads the verified identities once they are loaded, and
    // the list asks for the members' profiles: let both answer.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets(
      'on desktop the header lays out with no width limit, as in the side '
      'panel, and keeps the shield', (tester) async {
    await setUpRoom(tester, const Size(1280, 800));
    // The desktop main page: the panel is an unsized child of a row.
    await show(
        tester,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(child: SizedBox()),
          Column(children: [
            Flexible(child: RoomMembersListWidget(room)),
          ]),
        ]));

    expect(tester.takeException(), isNull);
    expect(_title, findsOneWidget);
    expect(_shield, findsOneWidget);
    // The header is as wide as the member list under it.
    expect(tester.getSize(find.byType(RoomMembersListWidget)).width, 200);
  });

  testWidgets(
      'in a narrow column (the mobile panel, 200 wide) the title fits and the shield stays in sight',
      (tester) async {
    await setUpRoom(tester, const Size(400, 800));
    await show(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 200, height: 600, child: RoomMembersListWidget(room)),
        ));

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(_shield, findsOneWidget);
    final shield = tester.getRect(_shield);
    expect(shield.right, lessThanOrEqualTo(200));
    expect(tester.getRect(_title).right, lessThanOrEqualTo(shield.left));
  });
}
