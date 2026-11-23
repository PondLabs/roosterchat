// Regression tests for c1-2 (Criterion 3):
// With lazy_load_members: true (matrix-dart-sdk default), pending knock
// events outside the recent sync timeline window are not present in
// room.states[EventTypes.RoomMember]. MatrixRoomKnockRequests must load them
// from GET /_matrix/client/v3/rooms/{roomId}/members?membership=knock on
// initState and didUpdateWidget when canModerate is true, and listen to
// RoomJoinRules and RoomPowerLevels changes.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/ui/pages/settings/categories/room/security/matrix_room_knock_requests.dart';

import 'fakes.dart';

class _LazyMembersServer extends FakeHomeserver {
  _LazyMembersServer(this.knockMembersByRoom);

  final Map<String, List<Map<String, Object?>>> knockMembersByRoom;

  @override
  late final http.Client transport = MockClient((request) async {
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, Object?>;
    final seenRequest = Seen(request.method, request.url, body);
    seen.add(seenRequest);
    final path = seenRequest.path;

    if (request.method == 'GET' && path.endsWith('/members')) {
      final match = RegExp(r'/rooms/([^/]+)/members$').firstMatch(path);
      final roomId = match?.group(1);
      final chunk = knockMembersByRoom[roomId] ?? const [];
      return http.Response(
        jsonEncode({'chunk': chunk}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(jsonEncode(<String, Object?>{}), 200,
        headers: {'content-type': 'application/json'});
  });
}

Map<String, Object?> _knockMemberEvent({
  required String roomId,
  required String userId,
  required String displayName,
  required String reason,
  int ts = 1000,
}) =>
    {
      'type': matrix.EventTypes.RoomMember,
      'state_key': userId,
      'sender': userId,
      'event_id': '\$lazy_knock_${roomId}_$ts',
      'origin_server_ts': ts,
      'room_id': roomId,
      'content': {
        'membership': 'knock',
        'displayname': displayName,
        'reason': reason,
      },
    };

void main() {
  setUpAll(preparePreferences);

  testWidgets(
      'c1-2: moderator knock queue loads lazy-loaded knocks from /members',
      (tester) async {
    const lazyKnocker = '@lazyknocker:elsewhere.example';
    final server = _LazyMembersServer({
      '!room:example.org': [
        _knockMemberEvent(
          roomId: '!room:example.org',
          userId: lazyKnocker,
          displayName: 'Lazy Knocker',
          reason: 'Arrived before lazy sync window',
        ),
      ],
    });
    final client = LifecycleTestClient(server);
    // Room has knock join_rule and moderator power, but no knock in memory.
    final room = buildRoom(client, states: [
      powerLevels(ownLevel: 100),
      state(matrix.EventTypes.RoomJoinRules, {'join_rule': 'knock'}),
    ]);

    await tester.pumpWidget(host(MatrixRoomKnockRequests(room)));
    await settle(tester);

    final memberFetches =
        server.where('GET', '/rooms/!room:example.org/members').toList();
    expect(memberFetches, isNotEmpty);
    expect(memberFetches.single.url.queryParameters['membership'], 'knock');
    expect(find.text('Lazy Knocker'), findsOneWidget);
    expect(find.byKey(MatrixRoomKnockRequests.approveKey(lazyKnocker)),
        findsOneWidget);
    expect(find.byKey(MatrixRoomKnockRequests.declineKey(lazyKnocker)),
        findsOneWidget);
  });

  test('loadPendingKnocks requests membership=knock and respects newer state',
      () async {
    const knockerA = '@a:elsewhere.example';
    const knockerB = '@b:elsewhere.example';
    final server = _LazyMembersServer({
      '!room:example.org': [
        _knockMemberEvent(
          roomId: '!room:example.org',
          userId: knockerB,
          displayName: 'Second',
          reason: 'Second note',
          ts: 2000,
        ),
        _knockMemberEvent(
          roomId: '!room:example.org',
          userId: knockerA,
          displayName: 'First',
          reason: 'First note',
          ts: 1000,
        ),
      ],
    });
    final client = LifecycleTestClient(server);
    final room = buildRoom(client, states: [
      powerLevels(ownLevel: 100),
      state(matrix.EventTypes.RoomJoinRules, {'join_rule': 'knock'}),
    ]);
    // Simulate a newer local invite event for knockerA.
    room.setState(matrix.Event(
      type: matrix.EventTypes.RoomMember,
      stateKey: knockerA,
      eventId: r'$invited_a',
      senderId: self,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(5000),
      content: {'membership': 'invite'},
      room: room,
    ));

    final loaded = await MatrixKnockingComponent(room).loadPendingKnocks();
    expect(loaded.map((r) => r.userId), [knockerB]);
    expect(loaded.single.displayName, 'Second');
    expect(loaded.single.reason, 'Second note');
    final req = server.where('GET', '/rooms/!room:example.org/members').single;
    expect(req.url.queryParameters['membership'], 'knock');
  });

  testWidgets(
      'non-moderator does not fetch /members; gaining power or switching '
      'rooms triggers fetch', (tester) async {
    const knocker1 = '@k1:elsewhere.example';
    const knocker2 = '@k2:elsewhere.example';
    final server = _LazyMembersServer({
      '!room1:example.org': [
        _knockMemberEvent(
          roomId: '!room1:example.org',
          userId: knocker1,
          displayName: 'Knocker One',
          reason: 'Room 1',
        ),
      ],
      '!room2:example.org': [
        _knockMemberEvent(
          roomId: '!room2:example.org',
          userId: knocker2,
          displayName: 'Knocker Two',
          reason: 'Room 2',
        ),
      ],
    });
    final client = LifecycleTestClient(server);
    final room1 = buildRoom(client, id: '!room1:example.org', states: [
      powerLevels(ownLevel: 0),
      state(matrix.EventTypes.RoomJoinRules, {'join_rule': 'knock'}),
    ]);
    final room2 = buildRoom(client, id: '!room2:example.org', states: [
      powerLevels(ownLevel: 100),
      state(matrix.EventTypes.RoomJoinRules, {'join_rule': 'knock'}),
    ]);

    await tester.pumpWidget(host(MatrixRoomKnockRequests(room1)));
    await settle(tester);

    expect(server.where('GET', '/members'), isEmpty);
    expect(find.byKey(MatrixRoomKnockRequests.panelKey), findsNothing);

    // Promote to moderator via RoomPowerLevels state event: must fetch knocks.
    room1.setState(matrix.Event(
      type: matrix.EventTypes.RoomPowerLevels,
      stateKey: '',
      eventId: r'$pl_promoted',
      senderId: '@admin:example.org',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
      content: {
        'users': {self: 100, '@admin:example.org': 100},
        'users_default': 0,
        'state_default': 50,
        'events_default': 0,
        'invite': 0,
        'kick': 50,
      },
      room: room1,
    ));
    await settle(tester);

    expect(
        server.where('GET', '/rooms/!room1:example.org/members'), hasLength(1));
    expect(find.text('Knocker One'), findsOneWidget);

    // Switch room via didUpdateWidget: must fetch knocks for room2.
    await tester.pumpWidget(host(MatrixRoomKnockRequests(room2)));
    await settle(tester);

    expect(
        server.where('GET', '/rooms/!room2:example.org/members'), hasLength(1));
    expect(find.text('Knocker Two'), findsOneWidget);
    expect(find.text('Knocker One'), findsNothing);
  });
}
