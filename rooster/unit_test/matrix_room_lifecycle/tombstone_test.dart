// Criterion 1: an upgraded room shows a banner whose button joins the
// replacement room through the tombstone's `via` servers (Matrix v1.19),
// a tombstone without `via` still works, and a room without one shows no
// banner. The tombstone also reaches the timeline as its own event.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_lifecycle_component.dart';
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_tombstone.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_tombstone.dart';
import 'package:rooster/ui/organisms/chat/room_tombstone_banner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await preparePreferences();
  });

  StateSpec tombstone(Map<String, Object?> content,
          {String sender = '@admin:old.example'}) =>
      state(matrix.EventTypes.RoomTombstone, content, sender: sender);

  group('MatrixRoomTombstone', () {
    test('reads replacement_room and via', () {
      final t = MatrixRoomTombstone.fromContent({
        'replacement_room': '!new:example.org',
        'via': ['example.org', 'other.example', 'example.org', 3, ''],
        'body': 'This room has moved',
      }, senderId: '@admin:old.example')!;
      expect(t.replacementRoomId, '!new:example.org');
      expect(t.via, ['example.org', 'other.example']);
      expect(t.body, 'This room has moved');
    });

    test('without via, routes through the sender\'s server', () {
      final t = MatrixRoomTombstone.fromContent({'replacement_room': '!new'},
          senderId: '@admin:old.example')!;
      expect(t.via, ['old.example']);
    });

    test('an empty via falls back too; a bare sender gives no server', () {
      expect(
          MatrixRoomTombstone.fromContent(
                  {'replacement_room': '!new', 'via': []},
                  senderId: '@admin:old.example')!
              .via,
          ['old.example']);
      expect(
          MatrixRoomTombstone.fromContent({'replacement_room': '!new'},
                  senderId: 'nobody')!
              .via,
          isEmpty);
    });

    test('no replacement room, no tombstone', () {
      expect(
          MatrixRoomTombstone.fromContent({'body': 'gone'}, senderId: '@a:b'),
          isNull);
      expect(
          MatrixRoomTombstone.fromContent({'replacement_room': ''},
              senderId: '@a:b'),
          isNull);
    });
  });

  group('followTombstone', () {
    test('joins with via as server names on /join/{roomId}', () async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client, states: [
        tombstone({
          'replacement_room': '!new:example.org',
          'via': ['example.org'],
        }),
      ]);

      final id = await MatrixRoomLifecycleComponent(room).followTombstone();

      expect(id, '!new:example.org');
      final joins = server.where('POST', '/join').toList();
      expect(joins, hasLength(1));
      expect(joins.single.path, '/_matrix/client/v3/join/!new:example.org');
      expect(joins.single.url.queryParametersAll['via'], ['example.org']);
    });

    test('a tombstone without via still joins, via the sender\'s server',
        () async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client, states: [
        tombstone({'replacement_room': '!new:example.org'}),
      ]);

      await MatrixRoomLifecycleComponent(room).followTombstone();

      final join = server.where('POST', '/join/').single;
      expect(join.url.queryParametersAll['via'], ['old.example']);
    });

    test('already in the replacement room: no join, just its id', () async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client, states: [
        tombstone({
          'replacement_room': '!new:example.org',
          'via': ['example.org'],
        }),
      ]);
      client.rooms.add(buildRoom(client, id: '!new:example.org'));

      final id = await MatrixRoomLifecycleComponent(room).followTombstone();

      expect(id, '!new:example.org');
      expect(server.where('POST', '/join'), isEmpty);
    });

    test('a room that was not replaced refuses', () async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server));
      await expectLater(MatrixRoomLifecycleComponent(room).followTombstone(),
          throwsStateError);
      expect(server.seen, isEmpty);
    });
  });

  group('RoomTombstoneBanner', () {
    testWidgets('renders and its button joins with via, then opens the room',
        (tester) async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client, states: [
        tombstone({
          'replacement_room': '!new:example.org',
          'via': ['example.org'],
        }),
      ]);
      final opened = <String>[];

      await tester.pumpWidget(host(
          RoomTombstoneBanner(room: room, onOpenRoom: (id) => opened.add(id))));

      expect(find.byKey(RoomTombstoneBanner.bannerKey), findsOneWidget);
      expect(
          find.text(RoomTombstoneBanner.messageRoomReplaced), findsOneWidget);

      await tester
          .tap(find.text(RoomTombstoneBanner.promptGoToReplacementRoom));
      await settle(tester);

      final join = server.where('POST', '/join').single;
      expect(join.path, '/_matrix/client/v3/join/!new:example.org');
      expect(join.url.queryParametersAll['via'], ['example.org']);
      expect(opened, ['!new:example.org']);
    });

    testWidgets('a tombstone without via still shows and joins',
        (tester) async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client, states: [
        tombstone({'replacement_room': '!new:example.org'}),
      ]);
      final opened = <String>[];

      await tester.pumpWidget(host(
          RoomTombstoneBanner(room: room, onOpenRoom: (id) => opened.add(id))));
      expect(find.byKey(RoomTombstoneBanner.bannerKey), findsOneWidget);

      await tester
          .tap(find.text(RoomTombstoneBanner.promptGoToReplacementRoom));
      await settle(tester);

      expect(server.where('POST', '/join/!new:example.org'), hasLength(1));
      expect(opened, ['!new:example.org']);
    });

    testWidgets('a room without a tombstone shows no banner', (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server));

      await tester.pumpWidget(
          host(RoomTombstoneBanner(room: room, onOpenRoom: (_) {})));

      expect(find.byKey(RoomTombstoneBanner.bannerKey), findsNothing);
      expect(find.text(RoomTombstoneBanner.messageRoomReplaced), findsNothing);
    });

    testWidgets('appears when the tombstone arrives', (tester) async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = buildRoom(client);

      await tester.pumpWidget(
          host(RoomTombstoneBanner(room: room, onOpenRoom: (_) {})));
      expect(find.byKey(RoomTombstoneBanner.bannerKey), findsNothing);

      final event = matrix.Event(
        type: matrix.EventTypes.RoomTombstone,
        stateKey: '',
        eventId: r'$tomb',
        senderId: '@admin:example.org',
        originServerTs: DateTime.now(),
        content: {'replacement_room': '!new:example.org'},
        room: room,
      );
      room.setState(event);
      client.onRoomState.add((roomId: room.id, state: event));
      await tester.pump();

      expect(find.byKey(RoomTombstoneBanner.bannerKey), findsOneWidget);
    });
  });

  test('the timeline turns m.room.tombstone into its own event', () async {
    final account = await fakeAccount('tombstone_timeline', FakeTransport());
    addTearDown(() => account.getMatrixClient().dispose(closeDatabase: true));
    final room = await plainRoom(account);

    final converted = room.convertEvent(matrix.Event(
      type: matrix.EventTypes.RoomTombstone,
      stateKey: '',
      eventId: r'$tomb',
      senderId: '@admin:example.org',
      originServerTs: DateTime.now(),
      content: {
        'replacement_room': '!new:example.org',
        'via': ['example.org'],
      },
      room: room.matrixRoom,
    ));

    expect(converted, isA<MatrixTimelineEventTombstone>());
    final event = converted as MatrixTimelineEventTombstone;
    expect(event.tombstone!.via, ['example.org']);
    expect(event.getBody(), contains('upgraded this room'));
  });
}
