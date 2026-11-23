import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';

import '../matrix_room_directory/fakes.dart';
import '../speed_log/fake_account.dart';

export '../matrix_room_directory/fakes.dart'
    show Script, Seen, json, matrixError, prepareTests, host, settle;

const alice = '@alice:fakeServer.notExisting';

var _accounts = 0;

/// A Rooster account on a fake homeserver that announces [versions], in a
/// plain room. Receipts and read markers are answered; [routes] go first.
Future<(Script, MatrixClient, MatrixRoom)> threadAccount({
  List<String> versions = const ['v1.1', 'v1.4', 'v1.6', 'v1.11'],
  List<http.Response? Function(Seen)> routes = const [],
}) async {
  final script = Script()
    ..routes.addAll(routes)
    ..routes.add((r) => r.method == 'GET' && r.path.endsWith('/versions')
        ? json({'versions': versions})
        : null)
    ..routes.add((r) => r.method == 'POST' &&
            (r.path.contains('/receipt/') || r.path.endsWith('/read_markers'))
        ? json(<String, Object?>{})
        : null);
  final name =
      'threads_${_accounts++}_${DateTime.now().microsecondsSinceEpoch}';
  final client = await fakeAccount(name, ScriptedAccountTransport(script));
  final room = await plainRoom(client);
  script.seen.clear();
  return (script, client, room);
}

/// A text message in [room]; in the thread of [threadRoot] when given.
matrix.Event message(MatrixRoom room, String id,
        {String? threadRoot,
        String sender = alice,
        int ts = 1000,
        String body = 'hello'}) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      eventId: id,
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      content: {
        'msgtype': 'm.text',
        'body': body,
        if (threadRoot != null)
          'm.relates_to': {
            'rel_type': matrix.RelationshipTypes.thread,
            'event_id': threadRoot,
          },
      },
      room: room.matrixRoom,
    );

/// The room's timeline holding [newestFirst].
MatrixTimeline timelineOf(
    MatrixClient client, MatrixRoom room, List<matrix.Event> newestFirst) {
  final sdkTimeline = matrix.Timeline(
    room: room.matrixRoom,
    chunk: TimelineChunk(events: newestFirst),
  );
  return MatrixTimeline(client, room, room.matrixRoom,
      initialTimeline: sdkTimeline);
}

/// A sync that brings [room]'s counts: [threads] by root id, as
/// `(notifications, highlights)`.
Future<void> syncCounts(MatrixRoom room,
    {int notifications = 0,
    int highlights = 0,
    Map<String, (int, int)>? threads}) async {
  final mx = room.matrixRoom.client;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'counts_${DateTime.now().microsecondsSinceEpoch}',
        rooms: matrix.RoomsUpdate(join: {
          room.matrixRoom.id: matrix.JoinedRoomUpdate(
            unreadNotifications: matrix.UnreadNotificationCounts(
                notificationCount: notifications, highlightCount: highlights),
            unreadThreadNotifications: threads?.map((id, counts) => MapEntry(
                id,
                matrix.UnreadNotificationCounts(
                    notificationCount: counts.$1, highlightCount: counts.$2))),
          ),
        }),
      )));
  await Future<void>.delayed(Duration.zero);
}

/// The receipts the homeserver received: (type, event id, JSON body).
List<(String, String, String)> receipts(Script script) => [
      for (final s in script.where('POST', '/receipt/'))
        (
          s.path.split('/receipt/').last.split('/').first,
          s.path.split('/').last,
          jsonEncode(s.body),
        ),
    ];

/// The JSON body of a receipt in [threadId].
String threaded(String threadId) => jsonEncode({'thread_id': threadId});
