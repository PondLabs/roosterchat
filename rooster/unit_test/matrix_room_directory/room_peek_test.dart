// Criterion 3: a `world_readable` room is read without joining it: its
// messages show read only, with a button to join; a private room
// (M_FORBIDDEN) shows a translated error. Neither joins the room or adds it
// to the client's rooms.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/room_directory/matrix_room_peek.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/explore/room_peek_view.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

const openRoom = '!open:example.org';
const privateRoom = '!private:example.org';

Map<String, Object?> event(String id, String type, Map<String, Object?> content,
        {String sender = '@alice:example.org', String? stateKey}) =>
    {
      'event_id': id,
      'type': type,
      'sender': sender,
      'origin_server_ts': 1000,
      'room_id': openRoom,
      'content': content,
      if (stateKey != null) 'state_key': stateKey,
    };

Map<String, Object?> text(String id, String body,
        {String sender = '@alice:example.org'}) =>
    event(id, 'm.room.message', {'msgtype': 'm.text', 'body': body},
        sender: sender);

final openState = [
  event(r'$name', 'm.room.name', {'name': 'Open Garden'}, stateKey: ''),
  event(r'$hv', 'm.room.history_visibility',
      {'history_visibility': 'world_readable'},
      stateKey: ''),
  event(r'$alice', 'm.room.member',
      {'membership': 'join', 'displayname': 'Alice'},
      stateKey: '@alice:example.org'),
];

/// `initialSync` of [openRoom], `M_FORBIDDEN` for [privateRoom], and the
/// newer events from `/events`.
FakeRoute peekServer({bool initialSyncGone = false}) => (request) {
      final path = request.path;
      if (path.contains('/rooms/$privateRoom/')) {
        return matrixError('M_FORBIDDEN');
      }
      if (path == '/_matrix/client/v3/rooms/$openRoom/initialSync') {
        if (initialSyncGone) return matrixError('M_UNRECOGNIZED', status: 404);
        return json({
          'room_id': openRoom,
          'membership': 'leave',
          'messages': {
            'chunk': [
              text(r'$1', 'First message'),
              event(r'$enc', 'm.room.encrypted', {'algorithm': 'x'}),
              text(r'$2', 'Second message', sender: '@bob:example.org'),
            ],
            'start': 's0',
            'end': 'e1',
          },
          'state': openState,
        });
      }
      if (path == '/_matrix/client/v3/rooms/$openRoom/state') {
        return json(openState);
      }
      if (path == '/_matrix/client/v3/rooms/$openRoom/messages') {
        // dir=b: newest first.
        return json({
          'chunk': [
            text(r'$2', 'Second message'),
            text(r'$1', 'First message')
          ],
          'start': 't0',
        });
      }
      if (path == '/_matrix/client/v3/events') {
        return json({
          'chunk': [text(r'$3', 'Third message')],
          'start': request.url.queryParameters['from'],
          'end': 'e2',
        });
      }
      return null;
    };

void main() {
  group('MatrixRoomPeek', () {
    test('reads a world-readable room with initialSync, oldest first',
        () async {
      final script = Script()..routes.add(peekServer());
      final client = DirectoryTestClient(script);
      final peek = MatrixRoomPeek(client, openRoom);

      await peek.load();

      expect(peek.name, 'Open Garden');
      expect(peek.messages.map((m) => m.body),
          ['First message', '', 'Second message']);
      expect(peek.messages.map((m) => m.encrypted), [false, true, false]);
      expect(peek.messages.first.senderName, 'Alice');
      expect(peek.messages.last.senderName, '@bob:example.org');

      await peek.loadNewer();
      expect(peek.messages.last.body, 'Third message');
      final events = script.where('GET', '/_matrix/client/v3/events').single;
      expect(events.url.queryParameters['from'], 'e1');
      expect(events.url.queryParameters['room_id'], openRoom);

      expect(script.where('POST', '/join'), isEmpty);
      expect(client.getRoomById(openRoom), isNull);
    });

    test('falls back to /messages and /state without initialSync', () async {
      final script = Script()..routes.add(peekServer(initialSyncGone: true));
      final peek = MatrixRoomPeek(DirectoryTestClient(script), openRoom);

      await peek.load();

      expect(peek.messages.map((m) => m.body),
          ['First message', 'Second message']);
      expect(peek.name, 'Open Garden');
      expect(peek.end, isNull, reason: 'no token to follow');
    });

    test('a private room is RoomPeekForbidden', () async {
      final script = Script()..routes.add(peekServer());
      final client = DirectoryTestClient(script);

      await expectLater(MatrixRoomPeek(client, privateRoom).load(),
          throwsA(isA<RoomPeekForbidden>()));
      expect(client.getRoomById(privateRoom), isNull);
      expect(script.where('POST', '/join'), isEmpty);
    });
  });

  group('RoomPeekView', () {
    setUpAll(prepareTests);

    Future<(Script, MatrixClient)> open(
        WidgetTester tester, String roomId) async {
      final script = Script()..routes.add(peekServer());
      final client = await tester.runAsync(() => fakeAccount(
          'peek_${DateTime.now().microsecondsSinceEpoch}',
          ScriptedAccountTransport(script)));
      await tester.pumpWidget(host(
          RoomPeekView(
              client: client!,
              roomId: roomId,
              title: 'Directory title',
              joinAddress: roomId),
          scroll: false));
      await settle(tester);
      return (script, client);
    }

    testWidgets('shows a world-readable room read only, with Join',
        (tester) async {
      final (script, client) = await open(tester, openRoom);

      expect(find.text('Open Garden'), findsOneWidget);
      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text(RoomPeekView.labelRoomPeekEncrypted), findsOneWidget);
      // Alice sent the first and the encrypted one.
      expect(find.text('Alice'), findsNWidgets(2));
      expect(find.text(RoomPeekView.labelRoomPeekReadOnly), findsOneWidget);
      expect(find.byKey(RoomPeekView.joinKey), findsOneWidget);
      // Read only: nowhere to type.
      expect(find.byType(TextField), findsNothing);

      expect(script.where('POST', '/join'), isEmpty);
      expect(client.hasRoom(openRoom), isFalse);
      expect(client.getMatrixClient().getRoomById(openRoom), isNull);
    });

    testWidgets('a private room shows the translated error, not joined',
        (tester) async {
      final (script, client) = await open(tester, privateRoom);

      expect(find.text(RoomPeekView.messageRoomPeekForbidden), findsOneWidget);
      expect(find.text(RoomPeekView.labelRoomPeekReadOnly), findsNothing);
      expect(
          script.where('GET', '/rooms/$privateRoom/initialSync'), hasLength(1));
      expect(script.where('POST', '/join'), isEmpty);
      expect(client.hasRoom(privateRoom), isFalse);
      expect(client.getMatrixClient().getRoomById(privateRoom), isNull);
    });
  });
}
