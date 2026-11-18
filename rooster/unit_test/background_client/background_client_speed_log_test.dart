@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:rooster/client/matrix_background/matrix_background_client.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

/// The Android background client (push notifications) sends its requests
/// through the same speed-log client as the app's own accounts.
void main() {
  const roomId = '!room:example.org';
  const eventId = '\$event';

  test('fetching a notified event is recorded in the speed log', () async {
    SpeedLog.instance.requests.clear();
    final seen = <String>[];
    final transport = MockClient((request) async {
      seen.add('${request.method} ${request.url.path}');
      return http.Response(
        jsonEncode({
          'type': 'm.room.message',
          'content': {'msgtype': 'm.text', 'body': 'hi'},
          'event_id': eventId,
          'room_id': roomId,
          'sender': '@a:example.org',
          'origin_server_ts': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    // A closed port on this machine: a request that skipped the transport
    // fails here instead of leaving it.
    final client =
        MatrixBackgroundClient(databaseId: 'speed_log', transport: transport)
          ..connect(
              homeserver: Uri.parse('http://127.0.0.1:9'),
              accessToken: 'token');
    client.allRooms = [const RoomDataData(roomId: roomId, content: '{}')];

    // What the notification handler does for each push.
    final event = await client.getRoom(roomId)!.getEvent(eventId);

    expect(event?.eventId, eventId);
    expect(seen, hasLength(1));
    final fetches = SpeedLog.instance.requests.toList().where((r) =>
        r.method == 'GET' &&
        r.route == '/_matrix/client/v3/rooms/{roomId}/event/{eventId}');
    expect(fetches, hasLength(1),
        reason: 'the fetch reached the server without passing through '
            'SpeedHttpClient');
    expect(fetches.single.status, 200);
    expect(fetches.single.hostClass, HostClass.homeserver);
  });
}
