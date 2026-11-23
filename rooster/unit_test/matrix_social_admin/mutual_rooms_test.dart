// Criterion 1: the profile card lists the rooms in common from
// `GET /v1/mutual_rooms` (Matrix v1.19) batch by batch with `next_batch`, and
// falls back to this device's own list on a server that answers 404 or
// M_UNRECOGNIZED.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/social_admin/matrix_mutual_rooms.dart';
import 'package:rooster/ui/organisms/user_profile/mutual_rooms_view.dart';

import '../matrix_room_directory/fakes.dart';

const friend = '@friend:example.org';
const mutualPath = '/_matrix/client/v1/mutual_rooms';

/// Room names as the card shows them: `Room <id>`.
String name(String id) => 'Room $id';

void addMember(matrix.Room room, String userId, String membership) =>
    room.setState(matrix.Event(
      type: matrix.EventTypes.RoomMember,
      stateKey: userId,
      eventId: '\$member_${room.id}_$userId',
      senderId: userId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(10),
      content: {'membership': membership},
      room: room,
    ));

void main() {
  setUpAll(prepareTests);

  Future<(Script, List<String>)> pumpRooms(WidgetTester tester, FakeRoute route,
      {void Function(matrix.Client client)? rooms}) async {
    final script = Script()..routes.add(route);
    final client = DirectoryTestClient(script);
    rooms?.call(client);
    final opened = <String>[];
    await tester.pumpWidget(host(MutualRoomsView(
      source: MatrixMutualRooms(client, friend),
      roomName: name,
      onOpenRoom: opened.add,
    )));
    await settle(tester);
    return (script, opened);
  }

  testWidgets('shows every batch, following next_batch', (tester) async {
    final (script, opened) = await pumpRooms(tester, (r) {
      if (r.path != mutualPath) return null;
      expect(r.url.queryParameters['user_id'], friend);
      return switch (r.url.queryParameters['from']) {
        null => json({
            'joined': ['!a:x', '!b:x'],
            'count': 3,
            'next_batch': 'page2'
          }),
        'page2' => json({
            'joined': ['!c:x'],
            'count': 3
          }),
        _ => json({'errcode': 'M_INVALID_PARAM'}, status: 400),
      };
    });

    expect(find.text(name('!a:x')), findsOneWidget);
    expect(find.text(name('!b:x')), findsOneWidget);
    expect(find.text(name('!c:x')), findsNothing);
    expect(find.text(MutualRoomsView.messageProfileMutualRoomsLocal),
        findsNothing);

    await tester.tap(find.byKey(MutualRoomsView.moreKey));
    await settle(tester);
    expect(find.text(name('!c:x')), findsOneWidget);
    expect(find.byKey(MutualRoomsView.moreKey), findsNothing);
    expect(script.where('GET', mutualPath).map((r) => r.url.query), [
      'user_id=%40friend%3Aexample.org',
      'user_id=%40friend%3Aexample.org&from=page2',
    ]);

    await tester.tap(find.text(name('!b:x')));
    expect(opened, ['!b:x']);
  });

  testWidgets('says when there is no room in common', (tester) async {
    await pumpRooms(tester,
        (r) => r.path == mutualPath ? json({'joined': <String>[]}) : null);
    expect(find.text(MutualRoomsView.messageProfileMutualRoomsNone),
        findsOneWidget);
  });

  // The rooms this device knows: both joined in !shared, they left !left,
  // and !mine has only us.
  void localRooms(matrix.Client client) {
    addMember(joinedRoom(client, id: '!shared:x'), friend, 'join');
    addMember(joinedRoom(client, id: '!left:x'), friend, 'leave');
    joinedRoom(client, id: '!mine:x');
  }

  for (final (what, answer) in [
    ('404 M_UNRECOGNIZED', () => matrixError('M_UNRECOGNIZED', status: 404)),
    ('a bare 404', () => json(<String, Object?>{}, status: 404)),
  ]) {
    testWidgets('$what falls back to the rooms this device knows',
        (tester) async {
      final (script, _) = await pumpRooms(
          tester, (r) => r.path == mutualPath ? answer() : null,
          rooms: localRooms);
      expect(find.text(name('!shared:x')), findsOneWidget);
      expect(find.text(name('!left:x')), findsNothing);
      expect(find.text(name('!mine:x')), findsNothing);
      expect(find.text(MutualRoomsView.messageProfileMutualRoomsLocal),
          findsOneWidget);
      expect(find.text(MutualRoomsView.messageProfileMutualRoomsFailed),
          findsNothing);
      expect(script.where('GET', mutualPath), hasLength(1));
    });
  }

  test('an unsupported server is not asked again for the same account',
      () async {
    final script = Script()
      ..routes.add((r) => r.path == mutualPath
          ? matrixError('M_UNRECOGNIZED', status: 404)
          : null);
    final client = DirectoryTestClient(script);
    localRooms(client);
    final first = await MatrixMutualRooms(client, friend).load();
    final again = await MatrixMutualRooms(client, friend).load();
    expect(first.local && again.local, isTrue);
    expect(again.roomIds, ['!shared:x']);
    expect(script.where('GET', mutualPath), hasLength(1));
  });

  testWidgets('another refusal shows an error with a retry, no crash',
      (tester) async {
    var refuse = true;
    await pumpRooms(tester, (r) {
      if (r.path != mutualPath) return null;
      return refuse
          ? matrixError('M_FORBIDDEN')
          : json({
              'joined': ['!a:x']
            });
    }, rooms: localRooms);
    expect(find.text(MutualRoomsView.messageProfileMutualRoomsFailed),
        findsOneWidget);
    expect(find.text(name('!shared:x')), findsNothing);

    refuse = false;
    await tester.tap(find.byKey(MutualRoomsView.retryKey));
    await settle(tester);
    expect(find.text(name('!a:x')), findsOneWidget);
    expect(find.text(MutualRoomsView.messageProfileMutualRoomsFailed),
        findsNothing);
  });
}
