@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

/// Outside the browser the app keeps its rooms in the drift database, which
/// implements the SDK's `DatabaseApi` in a package of its own.
///
/// A Matrix v1.16 server answers `use_state_after=true` with `state_after`,
/// and the timeline of such a sync does not define room state: a state event
/// it carries may have lost state resolution. These tests run a sync like
/// that over the drift database, and read the room again the way the app
/// does when it starts.
void main() {
  const alice = '@alice:example.test';
  const bob = '@bob:example.test';

  http.Response json(Object body) => http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json'});

  MockClient homeserver() => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/_matrix/client/versions')) {
          return json({
            'versions': ['v1.16']
          });
        }
        if (path.endsWith('/filter')) return json({'filter_id': 'filter'});
        if (path.endsWith('/_matrix/client/v3/sync')) {
          return json({'next_batch': 's_empty'});
        }
        return json({});
      });

  /// A client over [database]: signed in when [signIn], and otherwise the
  /// account [database] holds, as after a restart of the app.
  Future<matrix.Client> open(String name, MatrixSdkDriftDatabase database,
      {bool signIn = false}) async {
    final client =
        matrix.Client(name, httpClient: homeserver(), database: database);
    client.backgroundSync = false;
    client.syncErrorTimeoutSec = 0;
    if (signIn) {
      await client.init(
        newHomeserver: Uri.parse('https://hs.example.test'),
        newToken: 'token',
        newUserID: alice,
        newDeviceID: 'DEVICE',
        newDeviceName: 'Device',
        waitForFirstSync: false,
      );
    } else {
      await client.init(waitForFirstSync: false);
    }
    await client.abortSync();
    return client;
  }

  Map<String, Object?> stateEvent(
          String id, String type, Map<String, Object?> content,
          {int ts = 1700000000000,
          String sender = alice,
          String stateKey = ''}) =>
      {
        'event_id': id,
        'type': type,
        'sender': sender,
        'state_key': stateKey,
        'origin_server_ts': ts,
        'content': content,
      };

  matrix.SyncUpdate sync(
          String batch, String roomId, Map<String, Object?> update) =>
      matrix.SyncUpdate.fromJson({
        'next_batch': batch,
        'rooms': {
          'join': {roomId: update},
        },
      });

  test(
      'state events of a timeline that state_after leaves out are not room '
      'state after a restart', () async {
    const roomId = '!reset:example.test';
    const callMember = 'org.matrix.msc3401.call.member';
    const callKey = '_${bob}_DEVICE2_m.call';
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'state_after_reset');
    addTearDown(database.db.close);

    final first = await open('state_after_reset', database, signIn: true);
    await first.handleSync(sync('s_1', roomId, {
      'state_after': {
        'events': [
          stateEvent(r'$name0', matrix.EventTypes.RoomName, {'name': 'Yard'}),
        ],
      },
    }));

    // The name the room has, and four keys it never had: all of them in the
    // timeline, none of them in state_after.
    await first.handleSync(sync('s_2', roomId, {
      'timeline': {
        'events': [
          stateEvent(r'$name1', matrix.EventTypes.RoomName,
              {'name': 'Losing Fork Name'},
              ts: 1700000005000),
          stateEvent(r'$topic1', matrix.EventTypes.RoomTopic,
              {'topic': 'Losing Fork Topic'},
              ts: 1700000005001),
          stateEvent(r'$encryption1', matrix.EventTypes.Encryption,
              {'algorithm': 'm.megolm.v1.aes-sha2'},
              ts: 1700000005002),
          stateEvent(r'$call1', callMember, {'application': 'm.call'},
              sender: bob, stateKey: callKey, ts: 1700000005003),
        ],
      },
      'state_after': {'events': <Object?>[]},
    }));
    expect(first.getRoomById(roomId)!.name, 'Yard');
    await first.dispose(closeDatabase: false);

    final second = await open('state_after_reset', database);
    addTearDown(() => second.dispose(closeDatabase: false));
    final room = second.getRoomById(roomId)!;
    await room.postLoad();
    expect({
      'name': room.name,
      'topic': room.topic,
      'encrypted': room.encrypted,
      'inCall': room.getState(callMember, callKey) != null,
    }, {
      'name': 'Yard',
      'topic': '',
      'encrypted': false,
      'inCall': false,
    });

    // The events are in the stored timeline all the same, as state events.
    final stored = await second.database.getEventList(room);
    expect({
      for (final event in stored) event.eventId: event.stateKey
    }, {
      r'$name1': '',
      r'$topic1': '',
      r'$encryption1': '',
      r'$call1': callKey,
    });
  });

  test(
      'a member event of a timeline that state_after leaves out is not read '
      'back by a message of that member', () async {
    const roomId = '!member:example.test';
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'state_after_member');
    addTearDown(database.db.close);

    final first = await open('state_after_member', database, signIn: true);
    await first.handleSync(sync('s_1', roomId, {
      'state_after': {
        'events': [
          stateEvent(r'$member0', matrix.EventTypes.RoomMember,
              {'membership': 'join', 'displayname': 'Bob'},
              sender: bob, stateKey: bob, ts: 1700000000500),
        ],
      },
    }));
    await first.dispose(closeDatabase: false);

    // After a restart Bob is in the database, and not in memory.
    final second = await open('state_after_member', database);
    addTearDown(() => second.dispose(closeDatabase: false));
    final room = second.getRoomById(roomId)!;
    expect(room.getState(matrix.EventTypes.RoomMember, bob), isNull);

    // A message makes the client read its sender from the database.
    await second.handleSync(sync('s_2', roomId, {
      'timeline': {
        'events': [
          stateEvent(r'$member1', matrix.EventTypes.RoomMember,
              {'membership': 'leave', 'displayname': 'Losing Bob'},
              sender: bob, stateKey: bob, ts: 1700000005000),
          {
            'event_id': r'$message1',
            'type': matrix.EventTypes.Message,
            'sender': bob,
            'origin_server_ts': 1700000005001,
            'content': {'msgtype': 'm.text', 'body': 'hello'},
          },
        ],
      },
      'state_after': {'events': <Object?>[]},
    }));

    final inMemory =
        room.getState(matrix.EventTypes.RoomMember, bob)?.asUser(room);
    expect(inMemory?.membership, matrix.Membership.join);
    expect(inMemory?.displayName, 'Bob');
    final inDatabase = await second.database.getUser(bob, room);
    expect(inDatabase?.membership, matrix.Membership.join);
    expect(inDatabase?.displayName, 'Bob');
  });
}
