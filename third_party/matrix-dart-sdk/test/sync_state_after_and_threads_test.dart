// ROOSTER: Tests for Matrix v1.16 state_after/use_state_after (MSC4222),
// v1.4 unread_thread_notifications (MSC3773), and v1.15 Rich Topics m.topic (MSC3765) (T1.2).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

http.Response _jsonResponse(Object body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

MockClient _syncMockClient({
  List<String>? advertisedVersions,
  int versionsStatusCode = 200,
  void Function()? onVersionsRequest,
  void Function(Uri uri)? onSyncRequest,
  Map<String, Object?> Function(int callIndex)? syncResponseBuilder,
}) {
  var syncCalls = 0;
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/_matrix/client/versions')) {
      onVersionsRequest?.call();
      if (versionsStatusCode != 200) {
        return _jsonResponse(
          {'errcode': 'M_NOT_FOUND', 'error': 'Not found'},
          versionsStatusCode,
        );
      }
      return _jsonResponse({'versions': advertisedVersions ?? <String>[]});
    }
    if (path.endsWith('/_matrix/client/v3/login')) {
      return _jsonResponse({
        'flows': [
          {'type': AuthenticationTypes.password},
        ],
      });
    }
    if (path.endsWith('/_matrix/client/v1/auth_metadata')) {
      return _jsonResponse(
        {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized request'},
        404,
      );
    }
    if (path.contains('/_matrix/client/v3/user/') && path.endsWith('/filter')) {
      return _jsonResponse({'filter_id': 'filter_1'});
    }
    if (path.endsWith('/_matrix/client/v3/sync')) {
      syncCalls++;
      onSyncRequest?.call(request.url);
      final body = syncResponseBuilder?.call(syncCalls) ??
          {'next_batch': 's_batch_$syncCalls'};
      return _jsonResponse(body);
    }
    if (path.endsWith('/_matrix/client/v3/keys/query')) {
      return _jsonResponse({'device_keys': {}});
    }
    return _jsonResponse({});
  });
}

Map<String, Object?> _stateEvent(
  String eventId,
  String type,
  Map<String, Object?> content, {
  int ts = 1700000000000,
  String sender = '@alice:example.test',
  String stateKey = '',
}) =>
    {
      'event_id': eventId,
      'type': type,
      'sender': sender,
      'state_key': stateKey,
      'origin_server_ts': ts,
      'content': content,
    };

Map<String, Object?> _roomSync({
  String nextBatch = 's_1',
  Map<String, Map<String, Object?>>? join,
  Map<String, Map<String, Object?>>? leave,
}) =>
    {
      'next_batch': nextBatch,
      'rooms': {
        if (join != null) 'join': join,
        if (leave != null) 'leave': leave,
      },
    };

Future<Client> _createLoggedInClient(
  String name, {
  required http.Client httpClient,
  bool runCheckHomeserver = false,
  DatabaseApi? database,
}) async {
  final client = Client(
    name,
    httpClient: httpClient,
    database: database ?? await getDatabase(),
  );
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  final homeserver = Uri.parse('https://hs.example.test');
  if (runCheckHomeserver) {
    await client.checkHomeserver(homeserver, checkWellKnown: false);
  }
  await client.init(
    newHomeserver: homeserver,
    newToken: 'access_tok',
    newUserID: '@alice:example.test',
    newDeviceID: 'DEV01',
    newDeviceName: 'Test Device',
    waitForFirstSync: false,
  );
  await client.abortSync();
  return client;
}

/// A new [Client] over the database of one that was disposed with
/// `closeDatabase: false`: what the app reads when it starts again.
Future<Client> _restartClient(String name, DatabaseApi database) async {
  final client = Client(
    name,
    httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
    database: database,
  );
  client.backgroundSync = false;
  await client.init(waitForFirstSync: false);
  await client.abortSync();
  return client;
}

void main() {
  Logs().level = Level.error;

  group('1. use_state_after negotiation in Client._innerSync() (v1.16+)', () {
    for (final versions in [
      ['v1.16'],
      ['v1.1', 'v1.15', 'v1.16'],
      ['v1.17'],
      ['v1.19'],
      ['v1.20'],
      ['v2.0'],
    ]) {
      test('sends use_state_after=true for $versions', () async {
        final syncUris = <Uri>[];
        final client = await _createLoggedInClient(
          'sync_v1_16_${versions.last}',
          httpClient: _syncMockClient(
            advertisedVersions: versions,
            onSyncRequest: syncUris.add,
          ),
        );
        addTearDown(() => client.dispose(closeDatabase: true));

        await client.oneShotSync(timeout: Duration.zero);

        expect(syncUris, hasLength(1));
        expect(syncUris.single.queryParameters['use_state_after'], 'true');
      });
    }

    for (final versions in [
      ['v1.15'],
      ['v1.1', 'v1.2', 'v1.9', 'v1.11', 'v1.15'],
      ['r0.6.1'],
      <String>[],
      ['v1.16-rc1', 'v1.016', 'r1.16', 'v1', 'invalid'],
    ]) {
      test('omits use_state_after for $versions', () async {
        final syncUris = <Uri>[];
        final client = await _createLoggedInClient(
          'sync_legacy_${versions.join('_')}',
          httpClient: _syncMockClient(
            advertisedVersions: versions,
            onSyncRequest: syncUris.add,
          ),
        );
        addTearDown(() => client.dispose(closeDatabase: true));

        await client.oneShotSync(timeout: Duration.zero);

        expect(syncUris, hasLength(1));
        expect(
          syncUris.single.queryParameters.containsKey('use_state_after'),
          isFalse,
        );
      });
    }

    test('omits use_state_after and succeeds when /versions errors', () async {
      final syncUris = <Uri>[];
      final client = await _createLoggedInClient(
        'sync_versions_404',
        httpClient: _syncMockClient(
          versionsStatusCode: 404,
          onSyncRequest: syncUris.add,
        ),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.oneShotSync(timeout: Duration.zero);

      expect(syncUris, hasLength(1));
      expect(
        syncUris.single.queryParameters.containsKey('use_state_after'),
        isFalse,
      );
      expect(client.prevBatch, 's_batch_1');
    });

    test('asks /versions once for several syncs (database cache)', () async {
      final syncUris = <Uri>[];
      var versionsRequests = 0;
      final client = await _createLoggedInClient(
        'sync_versions_cached',
        httpClient: _syncMockClient(
          advertisedVersions: ['v1.15', 'v1.16'],
          onVersionsRequest: () => versionsRequests++,
          onSyncRequest: syncUris.add,
        ),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.oneShotSync(timeout: Duration.zero);
      await client.oneShotSync(timeout: Duration.zero);

      expect(versionsRequests, 1);
      expect(syncUris, hasLength(2));
      for (final uri in syncUris) {
        expect(uri.queryParameters['use_state_after'], 'true');
      }
    });
  });

  group('2. state_after parsing and ordering relative to timeline (MSC4222)',
      () {
    test('roundtrips state_after in JoinedRoomUpdate and LeftRoomUpdate', () {
      final parsed = SyncUpdate.fromJson(
        _roomSync(
          nextBatch: 's_sa_1',
          join: {
            '!joined:example.test': {
              'state_after': {
                'events': [
                  _stateEvent(
                    '\$sa_join',
                    EventTypes.RoomName,
                    {'name': 'Joined After'},
                  ),
                ],
              },
            },
          },
          leave: {
            '!left:example.test': {
              'state_after': {
                'events': [
                  _stateEvent(
                    '\$sa_left',
                    EventTypes.RoomName,
                    {'name': 'Left After'},
                  ),
                ],
              },
            },
          },
        ),
      );

      expect(
        parsed.rooms?.join?['!joined:example.test']?.stateAfter?.single
            .content['name'],
        'Joined After',
      );
      expect(
        parsed.rooms?.leave?['!left:example.test']?.stateAfter?.single
            .content['name'],
        'Left After',
      );

      final roundTrip = SyncUpdate.fromJson(parsed.toJson());
      expect(
        roundTrip.rooms?.join?['!joined:example.test']?.stateAfter?.single
            .content['name'],
        'Joined After',
      );
      expect(
        roundTrip.rooms?.leave?['!left:example.test']?.stateAfter?.single
            .content['name'],
        'Left After',
      );
    });

    test('tolerates malformed state_after blocks without crashing sync', () {
      final sync = SyncUpdate.fromJson(
        _roomSync(
          nextBatch: 's_bad_sa',
          join: {
            '!bad1:example.test': {'state_after': 'not-a-map'},
            '!bad2:example.test': {
              'state_after': {'events': 'not-a-list'},
            },
            '!mixed:example.test': {
              'state_after': {
                'events': [
                  null,
                  42,
                  'bad',
                  _stateEvent(
                    '\$valid_sa',
                    EventTypes.RoomName,
                    {'name': 'Valid Name'},
                  ),
                ],
              },
            },
          },
          leave: {
            '!bad_left:example.test': {'state_after': <Object?>[]},
            '!empty_left:example.test': {'state_after': <String, Object?>{}},
          },
        ),
      );

      // A block without `events` is present and empty, not absent.
      expect(
        sync.rooms?.leave?['!empty_left:example.test']?.stateAfter,
        isEmpty,
      );

      expect(sync.rooms?.join?['!bad1:example.test']?.stateAfter, isNull);
      expect(sync.rooms?.join?['!bad2:example.test']?.stateAfter, isNull);
      expect(
        sync.rooms?.join?['!mixed:example.test']?.stateAfter?.single
            .content['name'],
        'Valid Name',
      );
      expect(sync.rooms?.leave?['!bad_left:example.test']?.stateAfter, isNull);
    });

    test(
      'JoinedRoomUpdate applies state_after AFTER timeline (name and topic reflect state_after)',
      () async {
        const roomId = '!order_join:example.test';
        final syncUris = <Uri>[];
        final client = await _createLoggedInClient(
          'state_after_order_join',
          httpClient: _syncMockClient(
            advertisedVersions: ['v1.16'],
            onSyncRequest: syncUris.add,
            syncResponseBuilder: (_) => _roomSync(
              nextBatch: 's_order_1',
              join: {
                roomId: {
                  // Earlier ts in state_after ensures only post-timeline
                  // ordering determines final room state on forward sync.
                  'timeline': {
                    'events': [
                      _stateEvent(
                        '\$tl_name',
                        EventTypes.RoomName,
                        {'name': 'Timeline Name'},
                        ts: 1700000002000,
                      ),
                      _stateEvent(
                        '\$tl_topic',
                        EventTypes.RoomTopic,
                        {'topic': 'Timeline Topic'},
                        ts: 1700000002001,
                      ),
                    ],
                  },
                  'state_after': {
                    'events': [
                      _stateEvent(
                        '\$sa_name',
                        EventTypes.RoomName,
                        {'name': 'State After Name'},
                        ts: 1700000001000,
                      ),
                      _stateEvent(
                        '\$sa_topic',
                        EventTypes.RoomTopic,
                        {'topic': 'State After Topic'},
                        ts: 1700000001001,
                      ),
                    ],
                  },
                },
              },
            ),
          ),
        );
        addTearDown(() => client.dispose(closeDatabase: true));

        await client.oneShotSync(timeout: Duration.zero);
        expect(syncUris.single.queryParameters['use_state_after'], 'true');

        final room = client.getRoomById(roomId)!;
        expect(room.name, 'State After Name');
        await room.postLoad();
        expect(room.topic, 'State After Topic');

        // Also verify in-memory ordering when room is already fully loaded.
        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_order_2',
              join: {
                roomId: {
                  'timeline': {
                    'events': [
                      _stateEvent(
                        '\$tl_topic_2',
                        EventTypes.RoomTopic,
                        {'topic': 'Timeline Topic 2'},
                        ts: 1700000004000,
                      ),
                    ],
                  },
                  'state_after': {
                    'events': [
                      _stateEvent(
                        '\$sa_topic_2',
                        EventTypes.RoomTopic,
                        {'topic': 'State After Topic 2'},
                        ts: 1700000003000,
                      ),
                    ],
                  },
                },
              },
            ),
          ),
          direction: Direction.f,
        );
        expect(room.topic, 'State After Topic 2');
      },
    );

    test('handles the timeline events before state_after', () async {
      const roomId = '!order_events:example.test';
      final client = await _createLoggedInClient(
        'state_after_order_events',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      // The one stream that carries timeline and state updates, in the order
      // they were handled.
      final handled = <String>[];
      // ignore: deprecated_member_use_from_same_package
      final sub = client.onEvent.stream.listen(
        (update) =>
            handled.add('${update.type.name} ${update.content['event_id']}'),
      );
      addTearDown(sub.cancel);

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$tl_name',
                      EventTypes.RoomName,
                      {'name': 'Timeline Name'},
                      ts: 1700000002000,
                    ),
                    {
                      'event_id': '\$tl_message',
                      'type': EventTypes.Message,
                      'sender': '@alice:example.test',
                      'origin_server_ts': 1700000002001,
                      'content': {'msgtype': 'm.text', 'body': 'hello'},
                    },
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$sa_name',
                      EventTypes.RoomName,
                      {'name': 'State After Name'},
                      ts: 1700000001000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(handled, [
        'timeline \$tl_name',
        'timeline \$tl_message',
        'state \$sa_name',
      ]);
      expect(client.getRoomById(roomId)!.name, 'State After Name');
    });

    test('LeftRoomUpdate applies state_after AFTER timeline on archived room',
        () async {
      const roomId = '!order_left:example.test';
      final client = await _createLoggedInClient(
        'state_after_order_left',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_left_0',
            join: {
              roomId: {
                'state': {
                  'events': [
                    _stateEvent(
                      '\$init',
                      EventTypes.RoomName,
                      {'name': 'Initial Name'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.f,
      );
      await client.getRoomById(roomId)!.postLoad();

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_left_1',
            leave: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$left_tl_name',
                      EventTypes.RoomName,
                      {'name': 'Timeline Left Name'},
                      ts: 1700000005000,
                    ),
                    _stateEvent(
                      '\$left_tl_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'Timeline Left Topic'},
                      ts: 1700000005001,
                    ),
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$left_sa_name',
                      EventTypes.RoomName,
                      {'name': 'State After Left Name'},
                      ts: 1700000004000,
                    ),
                    _stateEvent(
                      '\$left_sa_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'State After Left Topic'},
                      ts: 1700000004001,
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.f,
      );

      final archived = client.getArchiveRoomFromCache(roomId)!;
      expect(archived.room.membership, Membership.leave);
      expect(archived.room.name, 'State After Left Name');
      expect(archived.room.topic, 'State After Left Topic');
    });

    test('loadArchiveWithTimeline applies state_after after timeline',
        () async {
      const roomId = '!archive_sa:example.test';
      final client = await _createLoggedInClient(
        'archive_state_after',
        httpClient: _syncMockClient(
          advertisedVersions: ['v1.16'],
          syncResponseBuilder: (_) => _roomSync(
            nextBatch: 's_arch_1',
            leave: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$arch_tl_name',
                      EventTypes.RoomName,
                      {'name': 'Archive Timeline Name'},
                      ts: 1700000009000,
                    ),
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$arch_sa_name',
                      EventTypes.RoomName,
                      {'name': 'Archive State After Name'},
                      ts: 1700000008000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      final archives = await client.loadArchiveWithTimeline();
      expect(archives, hasLength(1));
      expect(archives.single.room.name, 'Archive State After Name');
    });

    test(
        'state_after wins over the timeline after a restart on the same '
        'database', () async {
      const roomId = '!persist:example.test';
      final database = await getDatabase();
      final first = await _createLoggedInClient(
        'state_after_persist',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        database: database,
      );
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$tl_name',
                      EventTypes.RoomName,
                      {'name': 'Timeline Name'},
                      ts: 1700000002000,
                    ),
                    _stateEvent(
                      '\$tl_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'Timeline Topic'},
                      ts: 1700000002001,
                    ),
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$sa_name',
                      EventTypes.RoomName,
                      {'name': 'State After Name'},
                      ts: 1700000001000,
                    ),
                    _stateEvent(
                      '\$sa_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'State After Topic'},
                      ts: 1700000001001,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      expect(first.getRoomById(roomId)!.name, 'State After Name');
      await first.dispose(closeDatabase: false);

      final second = await _restartClient('state_after_persist', database);
      addTearDown(() => second.dispose(closeDatabase: true));
      final room = second.getRoomById(roomId)!;
      await room.postLoad();
      expect(room.name, 'State After Name');
      expect(room.topic, 'State After Topic');
    });

    test(
        'with state_after present, a timeline state event it leaves out does '
        'not change room state', () async {
      const roomId = '!reset:example.test';
      final database = await getDatabase();
      final first = await _createLoggedInClient(
        'state_after_reset',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        database: database,
      );
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$n0',
                      EventTypes.RoomName,
                      {'name': 'Original'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      final room = first.getRoomById(roomId)!;
      expect(room.name, 'Original');

      // The timeline carries a name event that lost state resolution, so the
      // name at the end of the timeline is unchanged and the server leaves it
      // out of the state_after delta (which is present, here with a topic).
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$n1',
                      EventTypes.RoomName,
                      {'name': 'Losing Fork'},
                      ts: 1700000005000,
                    ),
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$t1',
                      EventTypes.RoomTopic,
                      {'topic': 'Topic'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      expect(room.name, 'Original');
      // The event is still shown in the timeline.
      expect(
        (await first.database.getEventById('\$n1', room))?.content['name'],
        'Losing Fork',
      );
      await first.dispose(closeDatabase: false);

      // The timeline was stored without becoming room state.
      final second = await _restartClient('state_after_reset', database);
      addTearDown(() => second.dispose(closeDatabase: true));
      final restored = second.getRoomById(roomId)!;
      await restored.postLoad();
      expect(restored.name, 'Original');
      expect(restored.topic, 'Topic');
    });

    test(
        'with an empty state_after block, timeline state events do not '
        'change room state', () async {
      const roomId = '!reset_empty:example.test';
      final client = await _createLoggedInClient(
        'state_after_reset_empty',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$n0',
                      EventTypes.RoomName,
                      {'name': 'Original'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      final room = client.getRoomById(roomId)!;

      var batch = 1;
      for (final emptyStateAfter in <Map<String, Object?>>[
        {'events': <Object?>[]},
        {},
      ]) {
        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_${++batch}',
              join: {
                roomId: {
                  'timeline': {
                    'events': [
                      _stateEvent(
                        '\$n$batch',
                        EventTypes.RoomName,
                        {'name': 'Losing Fork $batch'},
                        ts: 1700000005000 + batch,
                      ),
                    ],
                  },
                  'state_after': emptyStateAfter,
                },
              },
            ),
          ),
        );
        expect(room.name, 'Original', reason: 'state_after: $emptyStateAfter');
      }
    });

    test(
        'a timeline state event state_after leaves out does not reach the '
        'database of a room that is not loaded (topic and member)', () async {
      const roomId = '!reset_partial:example.test';
      const bob = '@bob:example.test';
      final database = await getDatabase();
      final first = await _createLoggedInClient(
        'state_after_reset_partial',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        database: database,
      );
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$t0',
                      EventTypes.RoomTopic,
                      {'topic': 'Original Topic'},
                    ),
                    _stateEvent(
                      '\$m0',
                      EventTypes.RoomMember,
                      {'membership': 'join', 'displayname': 'Bob'},
                      sender: bob,
                      stateKey: bob,
                      ts: 1700000000500,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      await first.dispose(closeDatabase: false);

      // After a restart the room holds neither its topic (not one of the
      // important state events) nor Bob in memory: both are in the database.
      final second =
          await _restartClient('state_after_reset_partial', database);
      final partialRoom = second.getRoomById(roomId)!;
      expect(partialRoom.partial, isTrue);
      expect(partialRoom.getState(EventTypes.RoomTopic), isNull);
      expect(partialRoom.getState(EventTypes.RoomMember, bob), isNull);
      await second.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$t1',
                      EventTypes.RoomTopic,
                      {'topic': 'Losing Topic'},
                      ts: 1700000005000,
                    ),
                    _stateEvent(
                      '\$m1',
                      EventTypes.RoomMember,
                      {'membership': 'leave'},
                      sender: bob,
                      stateKey: bob,
                      ts: 1700000005001,
                    ),
                  ],
                },
                'state_after': {'events': <Object?>[]},
              },
            },
          ),
        ),
      );
      await second.dispose(closeDatabase: false);

      final third = await _restartClient('state_after_reset_partial', database);
      addTearDown(() => third.dispose(closeDatabase: true));
      final room = third.getRoomById(roomId)!;
      await room.postLoad();
      expect(room.topic, 'Original Topic');
      final member = await third.database.getUser(bob, room);
      expect(member?.membership, Membership.join);
      expect(member?.displayName, 'Bob');
      expect(
        member?.originServerTs,
        DateTime.fromMillisecondsSinceEpoch(1700000000500),
      );
    });

    test(
        'timeline state events on keys the room never had do not come back '
        'after a restart on the same database (name, topic, encryption, call '
        'member)', () async {
      const roomId = '!unseen:example.test';
      const callMember = 'org.matrix.msc3401.call.member';
      const callKey = '_@bob:example.test_DEV2_m.call';
      final database = await getDatabase();
      final first = await _createLoggedInClient(
        'state_after_unseen',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        database: database,
      );
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$c0',
                      EventTypes.RoomCreate,
                      {'creator': '@alice:example.test'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );

      // Four state events that lost state resolution: the server shows them
      // in the timeline and leaves them out of state_after.
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$tl_name',
                      EventTypes.RoomName,
                      {'name': 'Losing Fork Name'},
                      ts: 1700000005000,
                    ),
                    _stateEvent(
                      '\$tl_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'Losing Fork Topic'},
                      ts: 1700000005001,
                    ),
                    _stateEvent(
                      '\$tl_enc',
                      EventTypes.Encryption,
                      {'algorithm': 'm.megolm.v1.aes-sha2'},
                      ts: 1700000005002,
                    ),
                    _stateEvent(
                      '\$tl_call',
                      callMember,
                      {'application': 'm.call', 'scope': 'm.room'},
                      sender: '@bob:example.test',
                      stateKey: callKey,
                      ts: 1700000005003,
                    ),
                  ],
                },
                'state_after': {'events': <Object?>[]},
              },
            },
          ),
        ),
      );

      final beforeRestart = first.getRoomById(roomId)!;
      expect(beforeRestart.name, '');
      expect(beforeRestart.topic, '');
      expect(beforeRestart.encrypted, isFalse);
      expect(beforeRestart.getState(callMember, callKey), isNull);
      await first.dispose(closeDatabase: false);

      final second = await _restartClient('state_after_unseen', database);
      addTearDown(() => second.dispose(closeDatabase: true));
      final afterRestart = second.getRoomById(roomId)!;
      await afterRestart.postLoad();
      expect(
        {
          'name': afterRestart.name,
          'topic': afterRestart.topic,
          'encrypted': afterRestart.encrypted,
          'callMemberPresent':
              afterRestart.getState(callMember, callKey) != null,
        },
        {
          'name': '',
          'topic': '',
          'encrypted': false,
          'callMemberPresent': false,
        },
      );
      // The events themselves are still in the stored timeline.
      expect(
        (await second.database.getEventList(afterRestart))
            .map((event) => event.eventId),
        unorderedEquals(['\$tl_name', '\$tl_topic', '\$tl_enc', '\$tl_call']),
      );
    });

    test(
        'on a room that is not loaded, a timeline member event state_after '
        'leaves out, followed by a message from that member, does not change '
        'the member in memory', () async {
      const roomId = '!partial_member:example.test';
      const bob = '@bob:example.test';
      final database = await getDatabase();
      final first = await _createLoggedInClient(
        'state_after_partial_member',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        database: database,
      );
      await first.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$m0',
                      EventTypes.RoomMember,
                      {'membership': 'join', 'displayname': 'Original Bob'},
                      sender: bob,
                      stateKey: bob,
                      ts: 1700000000500,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      await first.dispose(closeDatabase: false);

      final second =
          await _restartClient('state_after_partial_member', database);
      addTearDown(() => second.dispose(closeDatabase: true));
      final room = second.getRoomById(roomId)!;
      expect(room.partial, isTrue);
      expect(room.getState(EventTypes.RoomMember, bob), isNull);

      // The message makes the client read its sender from the database, where
      // the member event of the timeline must not be.
      await second.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$m1',
                      EventTypes.RoomMember,
                      {'membership': 'leave', 'displayname': 'Losing Bob'},
                      sender: bob,
                      stateKey: bob,
                      ts: 1700000005000,
                    ),
                    {
                      'event_id': '\$msg1',
                      'type': EventTypes.Message,
                      'sender': bob,
                      'origin_server_ts': 1700000005001,
                      'content': {'msgtype': 'm.text', 'body': 'hello'},
                    },
                  ],
                },
                'state_after': {'events': <Object?>[]},
              },
            },
          ),
        ),
      );

      final bobInMemory =
          room.getState(EventTypes.RoomMember, bob)?.asUser(room);
      expect(bobInMemory?.membership, Membership.join);
      expect(bobInMemory?.displayName, 'Original Bob');
    });

    test(
        'LeftRoomUpdate and the archive: timeline state events do not change '
        'room state when state_after leaves them out', () async {
      const leftId = '!reset_left:example.test';
      const archivedId = '!reset_archive:example.test';
      final client = await _createLoggedInClient(
        'state_after_reset_left',
        httpClient: _syncMockClient(
          advertisedVersions: ['v1.16'],
          syncResponseBuilder: (_) => _roomSync(
            nextBatch: 's_arch_1',
            leave: {
              archivedId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$arch_tl_name',
                      EventTypes.RoomName,
                      {'name': 'Losing Archive Name'},
                      ts: 1700000009000,
                    ),
                    _stateEvent(
                      '\$arch_tl_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'Losing Archive Topic'},
                      ts: 1700000009001,
                    ),
                  ],
                },
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$arch_sa_name',
                      EventTypes.RoomName,
                      {'name': 'Archive Name'},
                      ts: 1700000008000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              leftId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$init',
                      EventTypes.RoomName,
                      {'name': 'Initial Name'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
      );
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            leave: {
              leftId: {
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$left_tl_name',
                      EventTypes.RoomName,
                      {'name': 'Losing Left Name'},
                      ts: 1700000005000,
                    ),
                  ],
                },
                'state_after': {'events': <Object?>[]},
              },
            },
          ),
        ),
      );
      expect(
        client.getArchiveRoomFromCache(leftId)!.room.name,
        'Initial Name',
      );

      final archives = await client.loadArchiveWithTimeline();
      final archived =
          archives.singleWhere((archive) => archive.room.id == archivedId);
      expect(archived.room.name, 'Archive Name');
      expect(archived.room.topic, '');
      expect(archived.timeline.events, hasLength(2));
    });

    test('preserves legacy state-before-timeline when state_after is absent',
        () async {
      const joinedId = '!legacy_join:example.test';
      const leftId = '!legacy_left:example.test';
      final client = await _createLoggedInClient(
        'state_legacy_order',
        httpClient: _syncMockClient(advertisedVersions: ['v1.15']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_legacy_1',
            join: {
              joinedId: {
                'state': {
                  'events': [
                    _stateEvent(
                      '\$st_name',
                      EventTypes.RoomName,
                      {'name': 'Old State Name'},
                      ts: 1700000001000,
                    ),
                    _stateEvent(
                      '\$st_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'Old State Topic'},
                      ts: 1700000001001,
                    ),
                  ],
                },
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$tl_name',
                      EventTypes.RoomName,
                      {'name': 'New Timeline Name'},
                      ts: 1700000002000,
                    ),
                    _stateEvent(
                      '\$tl_topic',
                      EventTypes.RoomTopic,
                      {'topic': 'New Timeline Topic'},
                      ts: 1700000002001,
                    ),
                  ],
                },
              },
              leftId: {
                'state': {
                  'events': [
                    _stateEvent(
                      '\$left_init',
                      EventTypes.RoomName,
                      {'name': 'Before Leave'},
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.f,
      );

      final joined = client.getRoomById(joinedId)!;
      await joined.postLoad();
      expect(joined.name, 'New Timeline Name');
      expect(joined.topic, 'New Timeline Topic');

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_legacy_2',
            leave: {
              leftId: {
                'state': {
                  'events': [
                    _stateEvent(
                      '\$left_st',
                      EventTypes.RoomName,
                      {'name': 'Legacy Left State'},
                      ts: 1700000003000,
                    ),
                  ],
                },
                'timeline': {
                  'events': [
                    _stateEvent(
                      '\$left_tl',
                      EventTypes.RoomName,
                      {'name': 'Legacy Left Timeline'},
                      ts: 1700000004000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.f,
      );

      expect(
        client.getArchiveRoomFromCache(leftId)!.room.name,
        'Legacy Left Timeline',
      );
    });

    test('Direction.b guard prevents older state_after overwriting newer state',
        () async {
      const roomId = '!dir_b:example.test';
      final client = await _createLoggedInClient(
        'state_after_dir_b',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_dir_1',
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$newer',
                      EventTypes.RoomName,
                      {'name': 'Newer Name'},
                      ts: 1700000010000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.f,
      );

      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_dir_b',
            join: {
              roomId: {
                'state_after': {
                  'events': [
                    _stateEvent(
                      '\$older',
                      EventTypes.RoomName,
                      {'name': 'Older Name'},
                      ts: 1700000005000,
                    ),
                  ],
                },
              },
            },
          ),
        ),
        direction: Direction.b,
      );

      expect(client.getRoomById(roomId)?.name, 'Newer Name');
    });
  });

  group('3. unread_thread_notifications in /sync and Room (v1.4 MSC3773)', () {
    test(
      'deserializes, exposes, updates, zeroes, and roundtrips per-thread counts',
      () async {
        const roomId = '!threads:example.test';
        final client = await _createLoggedInClient(
          'thread_notifs_basic',
          httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        );
        addTearDown(() => client.dispose(closeDatabase: true));

        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_t1',
              join: {
                roomId: {
                  'unread_notifications': {
                    'notification_count': 5,
                    'highlight_count': 1,
                  },
                  'unread_thread_notifications': {
                    '\$thread_a': {
                      'notification_count': 3,
                      'highlight_count': 1,
                    },
                    '\$thread_b': {
                      'notification_count': 2,
                      'highlight_count': 0,
                    },
                  },
                },
              },
            ),
          ),
        );

        final room = client.getRoomById(roomId)!;
        expect(
          room.unreadThreadNotifications.keys,
          {'\$thread_a', '\$thread_b'},
        );
        expect(
          room.unreadThreadNotifications['\$thread_a']?.notificationCount,
          3,
        );
        expect(
          room.unreadThreadNotifications['\$thread_a']?.highlightCount,
          1,
        );
        expect(
          room.unreadThreadNotifications['\$thread_b']?.notificationCount,
          2,
        );

        // A sync with ONLY unread_thread_notifications zeroes thread_a, adds
        // thread_c, drops thread_b (the server leaves out a thread without
        // notifications), keeps the room counts and fires onUpdate.
        var roomUpdates = 0;
        // ignore: deprecated_member_use_from_same_package
        final sub = room.onUpdate.stream.listen((_) => roomUpdates++);
        addTearDown(sub.cancel);

        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_t2',
              join: {
                roomId: {
                  'unread_thread_notifications': {
                    '\$thread_a': {
                      'notification_count': 0,
                      'highlight_count': 0,
                    },
                    '\$thread_c': {'notification_count': 4},
                  },
                },
              },
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(roomUpdates, greaterThanOrEqualTo(1));
        expect(
          room.unreadThreadNotifications['\$thread_a']?.notificationCount,
          0,
        );
        expect(
          room.unreadThreadNotifications['\$thread_a']?.highlightCount,
          0,
        );
        expect(room.unreadThreadNotifications['\$thread_b'], isNull);
        expect(
          room.unreadThreadNotifications['\$thread_c']?.notificationCount,
          4,
        );
        expect(
          room.unreadThreadNotifications['\$thread_c']?.highlightCount,
          0,
        );
        expect(room.notificationCount, 5);
        expect(room.highlightCount, 1);

        // The same counts again change nothing, so nobody is told.
        final updatesBefore = roomUpdates;
        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_t2b',
              join: {
                roomId: {
                  'unread_notifications': {
                    'notification_count': 5,
                    'highlight_count': 1,
                  },
                  'unread_thread_notifications': {
                    '\$thread_a': <String, Object?>{},
                    '\$thread_c': {
                      'notification_count': 4,
                      'highlight_count': 0,
                    },
                  },
                },
              },
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(roomUpdates, updatesBefore);

        // An empty entry counts as zero, and the threads left out are dropped.
        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_t3',
              join: {
                roomId: {
                  'unread_thread_notifications': {
                    '\$thread_b': <String, Object?>{},
                  },
                },
              },
            ),
          ),
        );
        expect(
          room.unreadThreadNotifications['\$thread_b']?.notificationCount,
          0,
        );
        expect(
          room.unreadThreadNotifications['\$thread_b']?.highlightCount,
          0,
        );
        expect(room.unreadThreadNotifications.keys, {'\$thread_b'});

        // An update with neither the room counts nor the thread counts says
        // nothing about threads: the counts we hold stay.
        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_t4',
              join: {
                roomId: {
                  'summary': {'m.joined_member_count': 2},
                },
              },
            ),
          ),
        );
        expect(room.unreadThreadNotifications.keys, {'\$thread_b'});
        expect(
          room.unreadThreadNotifications['\$thread_b']?.notificationCount,
          0,
        );

        // JoinedRoomUpdate and Room JSON roundtrips.
        final update = JoinedRoomUpdate.fromJson({
          'unread_thread_notifications': {
            '\$root1': {'notification_count': 7, 'highlight_count': 2},
          },
        });
        final updateRoundTrip = JoinedRoomUpdate.fromJson(update.toJson());
        expect(
          updateRoundTrip
              .unreadThreadNotifications?['\$root1']?.notificationCount,
          7,
        );
        expect(
          updateRoundTrip.unreadThreadNotifications?['\$root1']?.highlightCount,
          2,
        );

        room.unreadThreadNotifications['\$thread_d'] =
            UnreadNotificationCounts(notificationCount: 6, highlightCount: 2);
        final restored = Room.fromJson(room.toJson(), client);
        expect(
          restored.unreadThreadNotifications['\$thread_d']?.notificationCount,
          6,
        );
        expect(
          restored.unreadThreadNotifications['\$thread_d']?.highlightCount,
          2,
        );
        expect(
          restored.unreadThreadNotifications['\$thread_b']?.notificationCount,
          0,
        );
      },
    );

    test(
        'a thread the server omits from unread_thread_notifications (no '
        'notifications left) is zeroed', () async {
      const roomId = '!threads_omit:example.test';
      final client = await _createLoggedInClient(
        'thread_notifs_omit',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'unread_notifications': {
                  'notification_count': 1,
                  'highlight_count': 0,
                },
                'unread_thread_notifications': {
                  '\$thread_a': {
                    'notification_count': 3,
                    'highlight_count': 1,
                  },
                },
              },
            },
          ),
        ),
      );
      final room = client.getRoomById(roomId)!;
      expect(
        room.unreadThreadNotifications['\$thread_a']?.notificationCount,
        3,
      );

      // Thread A was read on another device. The spec lets the server omit a
      // thread without notifications, and the whole object when no thread has
      // any; the room-level counts still come down, unchanged.
      var roomUpdates = 0;
      // ignore: deprecated_member_use_from_same_package
      final sub = room.onUpdate.stream.listen((_) => roomUpdates++);
      addTearDown(sub.cancel);
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'unread_notifications': {
                  'notification_count': 1,
                  'highlight_count': 0,
                },
              },
            },
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        room.unreadThreadNotifications['\$thread_a']?.notificationCount ?? 0,
        0,
      );
      expect(roomUpdates, 1);
    });

    test(
        'a thread missing from a later unread_thread_notifications object is '
        'zeroed', () async {
      const roomId = '!threads_partial:example.test';
      final client = await _createLoggedInClient(
        'thread_notifs_partial',
        httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
      );
      addTearDown(() => client.dispose(closeDatabase: true));
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            join: {
              roomId: {
                'unread_notifications': {
                  'notification_count': 5,
                  'highlight_count': 0,
                },
                'unread_thread_notifications': {
                  '\$thread_a': {
                    'notification_count': 3,
                    'highlight_count': 0,
                  },
                },
              },
            },
          ),
        ),
      );
      final room = client.getRoomById(roomId)!;
      await client.handleSync(
        SyncUpdate.fromJson(
          _roomSync(
            nextBatch: 's_2',
            join: {
              roomId: {
                'unread_notifications': {
                  'notification_count': 5,
                  'highlight_count': 0,
                },
                'unread_thread_notifications': {
                  '\$thread_b': {
                    'notification_count': 2,
                    'highlight_count': 0,
                  },
                },
              },
            },
          ),
        ),
      );
      expect(
        room.unreadThreadNotifications['\$thread_b']?.notificationCount,
        2,
      );
      expect(
        room.unreadThreadNotifications['\$thread_a']?.notificationCount ?? 0,
        0,
      );
    });

    test(
      'ignores malformed unread_thread_notifications without crashing sync',
      () async {
        const roomId = '!threads_malformed:example.test';
        final client = await _createLoggedInClient(
          'thread_notifs_malformed',
          httpClient: _syncMockClient(advertisedVersions: ['v1.16']),
        );
        addTearDown(() => client.dispose(closeDatabase: true));

        for (final badTopLevel in [
          null,
          'oops',
          123,
          [1, 2],
          true,
        ]) {
          final parsed = SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_bad_top',
              join: {
                roomId: {'unread_thread_notifications': badTopLevel},
              },
            ),
          );
          expect(
            parsed.rooms?.join?[roomId]?.unreadThreadNotifications,
            isNull,
          );
          await client.handleSync(parsed);
        }

        await client.handleSync(
          SyncUpdate.fromJson(
            _roomSync(
              nextBatch: 's_mixed_threads',
              join: {
                roomId: {
                  'unread_thread_notifications': {
                    '\$valid_thread': {
                      'notification_count': 2,
                      'highlight_count': 1,
                    },
                    '': {'notification_count': 9},
                    '\$null_value': null,
                    '\$string_value': 'bad',
                    '\$list_value': [1, 2],
                    '\$bad_count_type': {'notification_count': 'three'},
                    '\$bad_highlight_type': {
                      'notification_count': 1,
                      'highlight_count': 1.5,
                    },
                    '\$negative_count': {'notification_count': -1},
                    '\$negative_highlight': {'highlight_count': -2},
                  },
                },
              },
            ),
          ),
        );

        final room = client.getRoomById(roomId)!;
        expect(room.unreadThreadNotifications.keys, {'\$valid_thread'});
        expect(
          room.unreadThreadNotifications['\$valid_thread']?.notificationCount,
          2,
        );
        expect(
          room.unreadThreadNotifications['\$valid_thread']?.highlightCount,
          1,
        );
      },
    );
  });

  group('4. Rich Topics m.topic in Room (v1.15 MSC3765)', () {
    late Client client;
    late Room room;
    final sentTopicPayloads = <Map<String, Object?>>[];

    setUp(() async {
      sentTopicPayloads.clear();
      client = await _createLoggedInClient(
        'rich_topics_test',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path.contains('/state/m.room.topic')) {
            sentTopicPayloads.add(
              jsonDecode(request.body) as Map<String, Object?>,
            );
            return _jsonResponse(
              {'event_id': '\$topic_evt_${sentTopicPayloads.length}'},
            );
          }
          return _jsonResponse({});
        }),
      );
      room = Room(
        id: '!topic_room:example.test',
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(room);
    });

    tearDown(() => client.dispose(closeDatabase: true));

    void setTopicContent(Map<String, Object?> content) {
      room.setState(
        Event(
          eventId: '\$topic_state',
          type: EventTypes.RoomTopic,
          stateKey: '',
          senderId: '@alice:example.test',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          content: content,
          room: room,
        ),
      );
    }

    test('reads unset, legacy, and MSC3765 m.topic representations accurately',
        () {
      expect(room.topic, '');
      expect(room.topicHtml, isNull);

      setTopicContent({'topic': 'Legacy room topic'});
      expect(room.topic, 'Legacy room topic');
      expect(room.topicHtml, isNull);

      // Prefers m.topic text/plain over legacy topic and reads text/html.
      setTopicContent({
        'topic': 'Legacy fallback',
        'm.topic': {
          'm.text': [
            {'body': 'Rich plain topic', 'mimetype': 'text/plain'},
            {'body': '<b>Rich</b> HTML topic', 'mimetype': 'text/html'},
          ],
        },
      });
      expect(room.topic, 'Rich plain topic');
      expect(room.topicHtml, '<b>Rich</b> HTML topic');

      // Omitted mimetype defaults to text/plain; MIME parameters normalized.
      setTopicContent({
        'topic': 'Legacy fallback',
        'm.topic': {
          'm.text': [
            {'body': 'Implicit plain topic'},
            {
              'body': '<em>Normalized</em>',
              'mimetype': 'TEXT/HTML; charset=utf-8',
            },
          ],
        },
      });
      expect(room.topic, 'Implicit plain topic');
      expect(room.topicHtml, '<em>Normalized</em>');

      // Falls back to legacy topic when m.topic contains only text/html.
      setTopicContent({
        'topic': 'Legacy plain fallback',
        'm.topic': {
          'm.text': [
            {'body': '<i>Only HTML</i>', 'mimetype': 'text/html'},
          ],
        },
      });
      expect(room.topic, 'Legacy plain fallback');
      expect(room.topicHtml, '<i>Only HTML</i>');
    });

    test('handles malformed m.topic safely with fallback to legacy topic', () {
      for (final malformed in [
        'not-a-map',
        123,
        {'m.text': 'not-a-list'},
        {
          'm.text': [
            null,
            42,
            {'body': 123, 'mimetype': 'text/plain'},
            {'mimetype': 'text/plain'},
            {'body': 'Bad mime type', 'mimetype': 999},
          ],
        },
      ]) {
        setTopicContent({
          'topic': 'Safe legacy fallback',
          'm.topic': malformed,
        });
        expect(room.topic, 'Safe legacy fallback');
        expect(room.topicHtml, isNull);
      }

      setTopicContent({
        'topic': 'Legacy',
        'm.topic': {
          'm.text': [
            null,
            {'body': 123},
            {'body': 'Recovered plain', 'mimetype': 'text/plain'},
            {'body': '<b>Recovered html</b>', 'mimetype': 'text/html'},
          ],
        },
      });
      expect(room.topic, 'Recovered plain');
      expect(room.topicHtml, '<b>Recovered html</b>');
    });

    test('setDescription writes legacy topic and MSC3765 m.topic', () async {
      final eventId1 = await room.setDescription('Plain topic');
      expect(eventId1, '\$topic_evt_1');
      expect(sentTopicPayloads.last, {
        'topic': 'Plain topic',
        'm.topic': {
          'm.text': [
            {'body': 'Plain topic', 'mimetype': 'text/plain'},
          ],
        },
      });

      final eventId2 = await room.setDescription(
        'Formatted topic',
        html: '<strong>Formatted</strong> topic',
      );
      expect(eventId2, '\$topic_evt_2');
      expect(sentTopicPayloads.last, {
        'topic': 'Formatted topic',
        'm.topic': {
          'm.text': [
            {'body': 'Formatted topic', 'mimetype': 'text/plain'},
            {
              'body': '<strong>Formatted</strong> topic',
              'mimetype': 'text/html',
            },
          ],
        },
      });

      // Roundtrip written payload through Room.topic / Room.topicHtml.
      setTopicContent(sentTopicPayloads.last);
      expect(room.topic, 'Formatted topic');
      expect(room.topicHtml, '<strong>Formatted</strong> topic');

      // Empty html omits text/html entry.
      await room.setDescription('Plain no empty html', html: '');
      expect(sentTopicPayloads.last, {
        'topic': 'Plain no empty html',
        'm.topic': {
          'm.text': [
            {'body': 'Plain no empty html', 'mimetype': 'text/plain'},
          ],
        },
      });
    });
  });
}
