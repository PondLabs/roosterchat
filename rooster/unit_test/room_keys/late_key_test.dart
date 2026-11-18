@TestOn('vm')
library;

/// A message that could not be decrypted is decrypted when its room key
/// arrives later, in the timeline already open: the row's "Failed to
/// decrypt event" turns into the text without opening the room again.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/timeline_events/timeline_event_encrypted.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/generated/l10n.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'fake_homeserver.dart';
import 'two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';
const _text = 'The key came late';
const _failed = 'Failed to decrypt event';

void main() {
  testWidgets(
      "the row of a message whose room key comes late shows the text once "
      "it arrives, without opening the room again",
      skip: vodozemacSkip != false, (tester) async {
    late FakeHomeserver server;
    late MatrixClient alice;
    late MatrixClient bob;
    late MatrixRoom aliceRoom;
    late Timeline timeline;
    // The call components listen to WebRTC's events, absent here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await tester.runAsync(() async {
      await setUpEncryption();
      await T.load(const Locale('en'));
      await initializeDateFormatting('en');
      await preferences.layoutOverride.set('desktop');
      UserIdleWatcher.instance.dispose();
      server = FakeHomeserver();
      alice = await signIn(server, _alice, 'ALICEPC');
      bob = await signIn(server, _bob, 'BOBPC');
      aliceRoom = await alice.createRoom(CreateRoomArgs(
        name: 'Private',
        visibility: RoomVisibilityPrivate(),
        enableE2EE: true,
      )) as MatrixRoom;
      await until(() => aliceRoom.matrixRoom.encrypted, what: 'encryption');
      await aliceRoom.matrixRoom.invite(_bob);
      await bob.joinRoom(aliceRoom.identifier);
      await until(() => hasMember(aliceRoom, _bob), what: 'account 2 in');
      await until(
          () =>
              alice
                  .getMatrixClient()
                  .userDeviceKeys[_bob]
                  ?.deviceKeys
                  .isNotEmpty ==
              true,
          what: "account 2's devices known");

      // The room key waits on the homeserver: the message arrives first.
      server.holdToDevice.add(_bob);
      final bobRoom = await roomOf(bob, aliceRoom.identifier);
      timeline = await bobRoom.getTimeline();
      await aliceRoom.sendMessage(message: _text);
      await until(() => timeline.events.any((e) => e is TimelineEventEncrypted),
          what: 'the message, encrypted, on account 2');
    });

    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining(_text, findRichText: true), findsNothing);

    // The key arrives, in a later sync.
    await tester.runAsync(() async {
      server.releaseToDevice(_bob);
      await until(
          () => timeline.events
              .any((e) => e is TimelineEventMessage && e.body == _text),
          what: 'the message decrypted on account 2');
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining(_text, findRichText: true), findsOneWidget);
    expect(find.text(_failed), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() async {
      await timeline.close();
      // The SDK's clients alone, their in-memory databases left open: the
      // app's close, and the database's, wait on work begun under the
      // widget test's fake clock, which no longer runs.
      for (final client in [alice, bob]) {
        await client.getMatrixClient().dispose(closeDatabase: false);
      }
    });
  });
}
