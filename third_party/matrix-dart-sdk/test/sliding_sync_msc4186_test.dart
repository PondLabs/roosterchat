// ROOSTER: Simplified Sliding Sync (MSC4186). Which transport the loop
// picks, how an answer fills the Client, the server forgetting `pos`, and
// the change back to `/v3/sync` in the middle of a session without losing
// or repeating a to-device message or a device list change. Everything
// runs against the fake homeserver below; no real server is involved.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

const _alice = '@alice:example.test';
const _bob = '@bob:example.test';
const _roomId = '!room:example.test';
const _ssPath = '/_matrix/client/unstable/org.matrix.simplified_msc3575/sync';
const _stablePath = '/_matrix/client/v5/sync';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _notFound() => http.Response('Not Found', 404);

/// A homeserver with a to-device inbox (a message is deleted once a
/// request acknowledges it) and a stream of device list changes, both
/// readable through `/v3/sync` tokens and Sliding Sync positions.
class _Homeserver {
  bool announce = true;
  bool announceStable = false;
  bool stableGone = false;

  /// Sliding Sync answers 404 `M_UNRECOGNIZED` from now on.
  bool slidingSyncGone = false;

  /// Sliding Sync answers a bare 404 page, as a reverse proxy does.
  bool slidingSyncNotFound = false;

  /// How many requests with a `pos` get `M_UNKNOWN_POS`.
  int forgetPos = 0;

  /// Every request gets `M_UNKNOWN_POS`, with a `pos` or without one.
  bool broken = false;

  final inbox = <int, Map<String, Object?>>{};
  var _toDeviceSeq = 0;
  final _deviceChanges = <(int, String)>[];
  var _deviceSeq = 0;
  final _positions = <String, int>{};
  var _posSeq = 0;
  int roomCount = 1;

  /// Answers without `lists.<name>.count`, or without `pos`.
  bool omitCount = false;
  bool omitPos = false;

  /// The rooms and extensions of the next Sliding Sync answer.
  Map<String, Object?> rooms = {};
  Map<String, Object?> extensions = {};
  Map<String, int>? oneTimeKeys;

  final slidingRequests = <(Uri, Map<String, Object?>)>[];
  final v3Requests = <Uri>[];
  final keyQueries = <Map<String, Object?>>[];
  var keyUploads = 0;

  void sendToDevice(String id) => inbox[++_toDeviceSeq] = {
        'sender': _bob,
        'type': 'org.example.ping',
        'content': {'id': id},
      };

  void devicesChanged(String userId) =>
      _deviceChanges.add((++_deviceSeq, userId));

  List<Map<String, Object?>> _deliver(int since, {required bool ack}) {
    if (ack) inbox.removeWhere((seq, _) => seq <= since);
    return [
      for (final seq in inbox.keys.where((s) => s > since).toList()..sort())
        inbox[seq]!,
    ];
  }

  int get _lastToDevice => inbox.keys.fold(0, (a, b) => a > b ? a : b);

  late final MockClient http = MockClient((request) async {
    final path = request.url.path;
    if (path == '/_matrix/client/versions') {
      return _json({
        'versions': ['v1.11', 'v1.16'],
        'unstable_features': {
          if (announce) 'org.matrix.simplified_msc3575': true,
          if (announceStable) 'org.matrix.simplified_msc3575.stable': true,
        },
      });
    }
    if (path == _ssPath || path == _stablePath) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      slidingRequests.add((request.url, body));
      if (slidingSyncNotFound) return _notFound();
      if (slidingSyncGone || (path == _stablePath && stableGone)) {
        return _json({'errcode': 'M_UNRECOGNIZED', 'error': 'gone'}, 404);
      }
      final pos = request.url.queryParameters['pos'];
      if (broken ||
          pos != null && (forgetPos > 0 || !_positions.containsKey(pos))) {
        forgetPos--;
        return _json({'errcode': 'M_UNKNOWN_POS', 'error': 'forgot'}, 400);
      }
      final toDevice = (body['extensions'] as Map)['to_device'] as Map;
      final since = int.parse(toDevice['since'] as String? ?? '0');
      final events = _deliver(since, ack: true);
      final from = pos == null ? null : _positions[pos]!;
      final newPos = 'p${++_posSeq}';
      _positions[newPos] = _deviceSeq;
      final answer = {
        if (!omitPos) 'pos': newPos,
        'lists': {
          'all_rooms': {if (!omitCount) 'count': roomCount},
        },
        'rooms': rooms,
        'extensions': {
          ...extensions,
          'to_device': {
            'next_batch': '${since > _lastToDevice ? since : _lastToDevice}',
            'events': events,
          },
          'e2ee': {
            'device_lists': {
              'changed': [
                if (from != null)
                  for (final (seq, user) in _deviceChanges)
                    if (seq > from) user,
              ],
              'left': [],
            },
            if (oneTimeKeys != null) 'device_one_time_keys_count': oneTimeKeys,
          },
        },
      };
      rooms = {};
      extensions = {};
      return _json(answer);
    }
    if (path == '/_matrix/client/v3/sync') {
      v3Requests.add(request.url);
      final since = request.url.queryParameters['since'];
      final parts = since?.split('_');
      final toDeviceFrom = parts == null ? 0 : int.parse(parts[1]);
      final deviceFrom = parts == null ? null : int.parse(parts[2]);
      final events = _deliver(toDeviceFrom, ack: since != null);
      final last = events.isEmpty ? toDeviceFrom : _lastToDevice;
      return _json({
        'next_batch': 'v3_${last}_$_deviceSeq',
        'to_device': {'events': events},
        if (deviceFrom != null)
          'device_lists': {
            'changed': [
              for (final (seq, user) in _deviceChanges)
                if (seq > deviceFrom) user,
            ],
          },
      });
    }
    if (path.endsWith('/filter')) return _json({'filter_id': 'f1'});
    if (path == '/_matrix/client/v3/keys/query') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      keyQueries.add(body);
      return _json({
        'device_keys': {
          for (final user in (body['device_keys'] as Map).keys) user: {},
        },
      });
    }
    if (path == '/_matrix/client/v3/keys/upload') {
      keyUploads++;
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final uploaded = (body['one_time_keys'] as Map?)?.length ?? 0;
      return _json({
        'one_time_key_counts': {'signed_curve25519': uploaded},
      });
    }
    return _json({});
  });

  Iterable<String> get slidingPaths =>
      slidingRequests.map((request) => request.$1.path);
}

var _clients = 0;

Future<Client> _client(
  _Homeserver server, {
  DatabaseApi? database,
  bool forceLegacySync = false,
  String? name,
  bool restart = false,
}) async {
  final client = Client(
    name ?? 'sliding_sync_${_clients++}',
    httpClient: server.http,
    database: database ?? await getDatabase(),
  );
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  client.forceLegacySync = forceLegacySync;
  if (restart) {
    await client.init(waitForFirstSync: false);
  } else {
    await client.init(
      newHomeserver: Uri.parse('https://hs.example.test'),
      newToken: 'access_token',
      newUserID: _alice,
      newDeviceID: 'ALICEDEV',
      newDeviceName: 'Test',
      waitForFirstSync: false,
    );
  }
  await client.abortSync();
  return client;
}

/// What a sync delivered, counted as the Client handed it on.
class _Delivered {
  final toDevice = <String>[];
  final changed = <String>[];
  _Delivered(Client client) {
    client.onToDeviceEvent.stream.listen((event) {
      if (event.type == 'org.example.ping') {
        toDevice.add(event.content['id'] as String);
      }
    });
    client.onSync.stream.listen((sync) {
      changed.addAll(sync.deviceLists?.changed ?? const []);
    });
  }
}

Map<String, Object?> _state(
  String type,
  Map<String, Object?> content, {
  String stateKey = '',
  String sender = _alice,
  String? eventId,
}) =>
    {
      'type': type,
      'state_key': stateKey,
      'sender': sender,
      'content': content,
      'event_id': eventId ?? '\$${type}_$stateKey',
      'origin_server_ts': 1000,
    };

Map<String, Object?> _encryptedRoomWithBob() => {
      _roomId: {
        'initial': true,
        'required_state': [
          _state('m.room.create', {'creator': _alice}),
          _state('m.room.encryption', {'algorithm': 'm.megolm.v1.aes-sha2'}),
          _state('m.room.member', {'membership': 'join'}, stateKey: _alice),
          _state(
            'm.room.member',
            {'membership': 'join'},
            stateKey: _bob,
            sender: _bob,
          ),
        ],
        'timeline': [],
        'joined_count': 2,
      },
    };

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 50));

// Review c1-1 (T6.6): a homeserver that announces Sliding Sync and
// refuses it, whose first `/v3/sync` brings a room with an unread thread.
MockClient _refusingServer({
  required bool bare404,
  required int Function() nextV3,
}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path == '/_matrix/client/versions') {
        return _json({
          'versions': ['v1.11', 'v1.16'],
          'unstable_features': {'org.matrix.simplified_msc3575': true},
        });
      }
      if (path == _ssPath) {
        if (bare404) return http.Response('Not Found', 404);
        return _json({'errcode': 'M_UNRECOGNIZED', 'error': 'gone'}, 404);
      }
      if (path.endsWith('/filter')) return _json({'filter_id': 'f1'});
      // With vodozemac loaded (this file), the client uploads its keys.
      if (path == '/_matrix/client/v3/keys/upload') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final uploaded = (body['one_time_keys'] as Map?)?.length ?? 0;
        return _json({
          'one_time_key_counts': {'signed_curve25519': uploaded},
        });
      }
      if (path == '/_matrix/client/v3/keys/query') {
        return _json({'device_keys': {}});
      }
      if (path == '/_matrix/client/v3/sync') {
        final seq = nextV3();
        if (seq == 1) {
          return _json({
            'next_batch': 'v3_1',
            'rooms': {
              'join': {
                _roomId: {
                  'state': {
                    'events': [
                      {
                        'type': 'm.room.member',
                        'state_key': _alice,
                        'sender': _alice,
                        'event_id': r'$m1',
                        'origin_server_ts': 1,
                        'content': {'membership': 'join'},
                      },
                    ],
                  },
                  'unread_notifications': {
                    'notification_count': 0,
                    'highlight_count': 0,
                  },
                  'unread_thread_notifications': {
                    r'$thread_root': {
                      'notification_count': 2,
                      'highlight_count': 1,
                    },
                  },
                },
              },
            },
          });
        }
        // Incremental /v3/sync omits rooms without new events.
        return _json({'next_batch': 'v3_$seq'});
      }
      return _json({});
    });

Future<Client> _open(
  String name,
  DatabaseApi database,
  http.Client httpClient, {
  bool restart = false,
  bool forceLegacySync = false,
}) async {
  final client = Client(
    name,
    httpClient: httpClient,
    database: database,
  );
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  client.forceLegacySync = forceLegacySync;
  if (restart) {
    await client.init(waitForFirstSync: false);
  } else {
    await client.init(
      newHomeserver: Uri.parse('https://hs.example.test'),
      newToken: 'access_token',
      newUserID: _alice,
      newDeviceID: 'ALICEDEV',
      newDeviceName: 'Test',
      waitForFirstSync: false,
    );
  }
  await client.abortSync();
  return client;
}

void main() {
  Logs().level = Level.error;

  setUpAll(() async {
    try {
      await vod.init(wasmPath: './pkg/', libraryPath: './rust/target/debug/');
    } catch (_) {
      Logs().w('vodozemac not loaded: the E2EE counter test is skipped');
    }
  });

  group('detection', () {
    test('a server announcing it gets Sliding Sync, not /v3/sync', () async {
      final server = _Homeserver();
      final client = await _client(server);
      await client.oneShotSync();
      expect(server.slidingPaths, [_ssPath]);
      expect(server.v3Requests, isEmpty);
      expect(client.syncTransport, SyncTransport.slidingSync);

      final (uri, body) = server.slidingRequests.single;
      expect(uri.queryParameters.containsKey('pos'), isFalse);
      expect(uri.queryParameters['timeout'], '0');
      expect(body['conn_id'], 'rooster');
      final list = (body['lists'] as Map)['all_rooms'] as Map;
      expect(list['ranges'], [
        [0, 49],
      ]);
      expect(list['required_state'], [
        ['*', '*'],
      ]);
      expect(list['timeline_limit'], isPositive);
      expect(
        (body['extensions'] as Map).keys,
        containsAll(
          ['to_device', 'e2ee', 'account_data', 'receipts', 'typing'],
        ),
      );
      await client.dispose();
    });

    test('a server without the flag gets /v3/sync and nothing else', () async {
      final server = _Homeserver()..announce = false;
      final client = await _client(server);
      await client.oneShotSync();
      await client.oneShotSync();
      expect(server.slidingRequests, isEmpty);
      expect(server.v3Requests, hasLength(2));
      expect(client.syncTransport, SyncTransport.v3);
      await client.dispose();
    });

    test('forcing /v3/sync keeps the loop off Sliding Sync', () async {
      final server = _Homeserver();
      final client = await _client(server, forceLegacySync: true);
      await client.oneShotSync();
      await client.oneShotSync();
      expect(server.slidingRequests, isEmpty);
      expect(server.v3Requests, hasLength(2));
      expect(client.syncTransport, SyncTransport.v3);
      await client.dispose();
    });

    test(
        'the stable path is used when announced, the unstable one after it '
        'refuses', () async {
      final server = _Homeserver()
        ..announceStable = true
        ..stableGone = true;
      final client = await _client(server);
      await client.oneShotSync();
      expect(server.slidingPaths, [_stablePath, _ssPath]);
      expect(client.syncTransport, SyncTransport.slidingSync);
      expect(server.v3Requests, isEmpty);
      await client.dispose();
    });
  });

  group('hydration', () {
    test('rooms, account data, to-device and E2EE fields fill the Client',
        () async {
      final server = _Homeserver();
      final client = await _client(server);
      server
        ..sendToDevice('first')
        ..oneTimeKeys = {'signed_curve25519': 42}
        ..rooms = {
          _roomId: {
            'initial': true,
            'required_state': [
              _state('m.room.create', {'creator': _alice}),
              _state('m.room.name', {'name': 'Sliding room'}),
              _state('m.room.member', {'membership': 'join'}, stateKey: _alice),
            ],
            'timeline': [
              {
                'type': 'm.room.message',
                'sender': _bob,
                'event_id': r'$message',
                'origin_server_ts': 2000,
                'content': {'msgtype': 'm.text', 'body': 'hello'},
              },
            ],
            'prev_batch': 'prev_1',
            'limited': true,
            'notification_count': 3,
            'highlight_count': 1,
            'joined_count': 2,
            'invited_count': 1,
            'heroes': [
              {'user_id': _bob},
            ],
          },
          '!invite:example.test': {
            'invite_state': [
              {
                'type': 'm.room.member',
                'state_key': _alice,
                'sender': _bob,
                'content': {'membership': 'invite'},
              },
            ],
          },
        }
        ..extensions = {
          'account_data': {
            'global': [
              {
                'type': 'org.example.settings',
                'content': {'theme': 'dark'},
              },
            ],
            'rooms': {
              _roomId: [
                {
                  'type': 'm.tag',
                  'content': {
                    'tags': {'m.favourite': {}},
                  },
                },
              ],
            },
          },
          'receipts': {
            'rooms': {
              _roomId: {
                'content': {
                  r'$message': {
                    'm.read': {
                      _bob: {'ts': 2001},
                    },
                  },
                },
              },
            },
          },
          'typing': {
            'rooms': {
              _roomId: {
                'content': {
                  'user_ids': [_bob],
                },
              },
            },
          },
        };
      final delivered = _Delivered(client);
      await client.oneShotSync();
      await _settle();

      final room = client.getRoomById(_roomId)!;
      expect(room.membership, Membership.join);
      expect(room.getLocalizedDisplayname(), 'Sliding room');
      expect(room.notificationCount, 3);
      expect(room.highlightCount, 1);
      expect(room.summary.mJoinedMemberCount, 2);
      expect(room.summary.mInvitedMemberCount, 1);
      expect(room.summary.mHeroes, [_bob]);
      expect(room.lastEvent?.eventId, r'$message');
      expect(room.prev_batch, 'prev_1');
      expect(room.isFavourite, isTrue);
      expect(room.typingUsers.map((u) => u.id), [_bob]);
      expect(room.receiptState.global.otherUsers[_bob]?.eventId, r'$message');
      expect(
        client.getRoomById('!invite:example.test')?.membership,
        Membership.invite,
      );
      expect(
        client.accountData['org.example.settings']?.content['theme'],
        'dark',
      );
      expect(delivered.toDevice, ['first']);
      expect(
        client.onSync.value?.deviceOneTimeKeysCount,
        {'signed_curve25519': 42},
      );

      // The next request goes on from the answer.
      await client.oneShotSync();
      final (uri, body) = server.slidingRequests.last;
      expect(uri.queryParameters['pos'], 'p1');
      expect(
        ((body['extensions'] as Map)['to_device'] as Map)['since'],
        '1',
      );
      await client.dispose();
    });

    test('a member event saying leave makes a left room', () {
      final update = slidingSyncToSyncUpdate(
        {
          'pos': 'p9',
          'rooms': {
            _roomId: {
              'timeline': [
                _state(
                  'm.room.member',
                  {'membership': 'leave'},
                  stateKey: _alice,
                ),
              ],
            },
          },
        },
        userId: _alice,
      );
      expect(update.rooms?.leave?.keys, [_roomId]);
      expect(update.rooms?.join, isNull);
      expect(update.nextBatch, 'p9');
    });

    test('the list range grows until it covers every room', () async {
      final server = _Homeserver()..roomCount = 120;
      final client = await _client(server);
      for (var i = 0; i < 4; i++) {
        await client.oneShotSync();
      }
      List<Object?> range(int i) =>
          ((server.slidingRequests[i].$2['lists'] as Map)['all_rooms']
              as Map)['ranges'] as List<Object?>;
      expect(range(0), [
        [0, 49],
      ]);
      expect(range(1), [
        [0, 99],
      ]);
      expect(range(2), [
        [0, 119],
      ]);
      // Growing, the request does not wait; every room covered, it waits
      // for news.
      expect(server.slidingRequests[1].$1.queryParameters['timeout'], '0');
      expect(server.slidingRequests[2].$1.queryParameters['timeout'], '30000');
      await client.dispose();
    });

    test('one-time key counts reach the olm account', () async {
      final server = _Homeserver();
      final client = await _client(server);
      if (!client.encryptionEnabled) {
        markTestSkipped('vodozemac is not loaded');
        return;
      }
      await _settle();
      final before = server.keyUploads;
      server.oneTimeKeys = {'signed_curve25519': 0};
      await client.oneShotSync();
      await _settle();
      expect(
        server.keyUploads,
        greaterThan(before),
        reason: 'no one-time keys left on the server: new ones go up',
      );
      await client.dispose();
    });
  });

  group('M_UNKNOWN_POS', () {
    test('drops pos and starts again at once, keeping the to-device since',
        () async {
      final server = _Homeserver();
      final client = await _client(server);
      server.sendToDevice('a');
      await client.oneShotSync();
      server
        ..forgetPos = 1
        ..sendToDevice('b');
      final delivered = _Delivered(client);
      await client.oneShotSync();

      expect(server.slidingRequests, hasLength(3));
      final (forgotten, _) = server.slidingRequests[1];
      final (again, body) = server.slidingRequests[2];
      expect(forgotten.queryParameters['pos'], 'p1');
      expect(again.queryParameters.containsKey('pos'), isFalse);
      expect(((body['extensions'] as Map)['to_device'] as Map)['since'], '1');
      expect(delivered.toDevice, ['b']);
      expect(client.isLogged(), isTrue);
      expect(client.syncTransport, SyncTransport.slidingSync);

      // The new connection goes on normally.
      await client.oneShotSync();
      expect(server.slidingRequests.last.$1.queryParameters['pos'], 'p2');
      await client.dispose();
    });

    test(
        'a server that keeps refusing costs two requests per sync, no loop '
        'and no logout', () async {
      final server = _Homeserver();
      final client = await _client(server);
      await client.oneShotSync();
      server.broken = true;
      final errors = <Object?>[];
      client.onSyncStatus.stream
          .where((s) => s.status == SyncStatus.error)
          .listen((s) => errors.add(s.error?.exception));
      // pos dropped and asked again without it, refused too: an error.
      await client.oneShotSync();
      // No pos left to drop: one request.
      await client.oneShotSync();
      server.broken = false;
      await client.oneShotSync();
      await _settle();
      expect(
        server.slidingRequests.map((r) => r.$1.queryParameters['pos']),
        [null, 'p1', null, null, null],
      );
      expect(errors, hasLength(2));
      expect(
        errors.every(
          (e) => e is MatrixException && e.errcode == 'M_UNKNOWN_POS',
        ),
        isTrue,
      );
      expect(client.isLogged(), isTrue);
      expect(client.syncTransport, SyncTransport.slidingSync);
      expect(client.onSyncStatus.value?.status, SyncStatus.finished);
      await client.dispose();
    });

    test('a new connection has every tracked device list downloaded again',
        () async {
      final server = _Homeserver()..rooms = _encryptedRoomWithBob();
      final client = await _client(server);
      await client.oneShotSync();
      await _settle();
      expect(client.userDeviceKeys[_bob]?.outdated, isFalse);
      final queries = server.keyQueries.length;

      server.forgetPos = 1;
      await client.oneShotSync();
      await _settle();
      expect(
        server.keyQueries.skip(queries).any(
              (q) => (q['device_keys'] as Map).containsKey(_bob),
            ),
        isTrue,
        reason: 'changes while there was no connection are not reported',
      );
      await client.dispose();
    });
  });

  group('back to /v3/sync in the middle of a session', () {
    test('no to-device message or device list change is lost or repeated',
        () async {
      final server = _Homeserver();
      // A session that had /v3/sync before the server offered Sliding Sync.
      final client = await _client(server, forceLegacySync: true);
      final delivered = _Delivered(client);
      await client.oneShotSync();
      expect(client.prevBatch, 'v3_0_0');

      server
        ..devicesChanged('@u1:example.test')
        ..sendToDevice('t1')
        ..sendToDevice('t2');
      client.forceLegacySync = false;
      await client.oneShotSync();
      expect(client.syncTransport, SyncTransport.slidingSync);

      server
        ..sendToDevice('t3')
        ..devicesChanged('@u2:example.test');
      await client.oneShotSync();
      expect(delivered.toDevice, ['t1', 't2', 't3']);
      expect(delivered.changed, ['@u2:example.test']);

      // t3 is not acknowledged yet when Sliding Sync goes away.
      server
        ..sendToDevice('t4')
        ..devicesChanged('@u3:example.test')
        ..slidingSyncGone = true;
      await client.oneShotSync();
      expect(client.slidingSyncFallbackReason, 'M_UNRECOGNIZED');
      expect(client.syncTransport, SyncTransport.v3);

      await client.oneShotSync();
      expect(
        server.v3Requests.last.queryParameters['since'],
        'v3_0_0',
        reason: '/v3/sync goes on from its own token, not from pos',
      );
      await client.oneShotSync();
      server.sendToDevice('t5');
      await client.oneShotSync();
      await client.oneShotSync();

      expect(
        delivered.toDevice,
        ['t1', 't2', 't3', 't4', 't5'],
        reason: 'each message once, none lost',
      );
      expect(
        delivered.changed..sort(),
        ['@u1:example.test', '@u2:example.test', '@u3:example.test'],
        reason: 'each change once, none lost',
      );
      expect(server.inbox, isEmpty);
      await client.dispose();
    });

    test('a bare 404 from a proxy also sends the loop back', () async {
      final server = _Homeserver();
      final client = await _client(server);
      await client.oneShotSync();
      server.slidingSyncNotFound = true;
      await client.oneShotSync();
      expect(client.slidingSyncFallbackReason, 'HTTP 404');
      await client.oneShotSync();
      expect(server.v3Requests, hasLength(1));
      expect(client.syncTransport, SyncTransport.v3);
      await client.dispose();
    });

    test(
        'a tracked user Sliding Sync reported is not delivered again, but '
        'its keys are checked once', () async {
      final server = _Homeserver();
      final client = await _client(server, forceLegacySync: true);
      final delivered = _Delivered(client);
      await client.oneShotSync();

      server.rooms = _encryptedRoomWithBob();
      client.forceLegacySync = false;
      await client.oneShotSync();
      await _settle();
      server.devicesChanged(_bob);
      await client.oneShotSync();
      await _settle();
      expect(delivered.changed, [_bob]);
      expect(client.userDeviceKeys[_bob]?.outdated, isFalse);
      final queries = server.keyQueries.length;

      server.slidingSyncGone = true;
      await client.oneShotSync();
      await client.oneShotSync();
      await _settle();
      expect(delivered.changed, [_bob], reason: 'reported once');
      // The stale /v3 token cannot tell this repeat from a newer change.
      expect(
        server.keyQueries.skip(queries).any(
              (q) => (q['device_keys'] as Map).containsKey(_bob),
            ),
        isTrue,
      );
      await client.dispose();
    });

    test('the change survives a restart, and back again', () async {
      final server = _Homeserver();
      final database = await getDatabase();
      const name = 'sliding_sync_restart';
      final first = await _client(server, database: database, name: name);
      final firstDelivered = _Delivered(first);
      server.sendToDevice('t1');
      await first.oneShotSync();
      server.sendToDevice('t2');
      await first.oneShotSync();
      await first.dispose(closeDatabase: false);

      // Restarted with /v3/sync forced: t2 was never acknowledged.
      server.sendToDevice('t3');
      final second = await _client(
        server,
        database: database,
        name: name,
        forceLegacySync: true,
        restart: true,
      );
      final secondDelivered = _Delivered(second);
      await second.oneShotSync();
      await second.dispose(closeDatabase: false);

      // And Sliding Sync again: t3 was never acknowledged either.
      server.sendToDevice('t4');
      final third =
          await _client(server, database: database, name: name, restart: true);
      final thirdDelivered = _Delivered(third);
      await third.oneShotSync();
      expect(server.slidingRequests.last.$1.queryParameters['pos'], isNull);

      expect(
        [
          ...firstDelivered.toDevice,
          ...secondDelivered.toDevice,
          ...thirdDelivered.toDevice,
        ],
        ['t1', 't2', 't3', 't4'],
      );
      await third.dispose();
    });

    test(
        'with no /v3 token to go on from, every device list is downloaded '
        'again', () async {
      final server = _Homeserver()..rooms = _encryptedRoomWithBob();
      final client = await _client(server);
      await client.oneShotSync();
      await _settle();
      expect(client.userDeviceKeys[_bob]?.outdated, isFalse);
      final queries = server.keyQueries.length;

      server.slidingSyncGone = true;
      await client.oneShotSync();
      await client.oneShotSync();
      await _settle();
      expect(server.v3Requests.single.queryParameters['since'], isNull);
      expect(
        server.keyQueries.skip(queries).any(
              (q) => (q['device_keys'] as Map).containsKey(_bob),
            ),
        isTrue,
        reason: 'an initial /v3/sync reports no device list change',
      );
      await client.dispose();
    });
  });

  group('review c1', () {
    Map<String, Object?> pushRules() => {
          'type': 'm.push_rules',
          'content': {
            'global': {
              'underride': [
                {
                  'rule_id': '.m.rule.message',
                  'default': true,
                  'enabled': true,
                  'conditions': [
                    {
                      'kind': 'event_match',
                      'key': 'type',
                      'pattern': 'm.room.message',
                    },
                  ],
                  'actions': ['notify'],
                },
              ],
            },
          },
        };

    Map<String, Object?> message(String id, int ts) => {
          'type': 'm.room.message',
          'sender': _bob,
          'event_id': id,
          'origin_server_ts': ts,
          'content': {'msgtype': 'm.text', 'body': id},
        };

    Map<String, Object?> room(
      List<Map<String, Object?>> timeline, {
      bool initial = true,
      bool limited = false,
    }) =>
        {
          if (initial) 'initial': true,
          if (initial)
            'required_state': [
              _state('m.room.create', {'creator': _alice}),
              _state('m.room.member', {'membership': 'join'}, stateKey: _alice),
            ],
          'timeline': timeline,
          'limited': limited,
          'notification_count': 1,
        };

    Future<(_Homeserver, Client, List<String>)> started() async {
      final server = _Homeserver()
        ..rooms = {
          _roomId: room([message(r'$older', 1000), message(r'$old', 2000)]),
        }
        ..extensions = {
          'account_data': {
            'global': [pushRules()],
          },
        };
      final client = await _client(server);
      final notified = <String>[];
      client.onNotification.stream.listen((e) => notified.add(e.eventId));
      await client.oneShotSync();
      await client.oneShotSync();
      return (server, client, notified);
    }

    test(
        'c1-1: an event already delivered does not notify again on a new '
        'connection', () async {
      final (server, client, notified) = await started();
      expect(client.getRoomById(_roomId)?.lastEvent?.eventId, r'$old');
      // The server forgets pos and sends the room as it is now.
      server
        ..forgetPos = 1
        ..rooms = {
          _roomId: room([message(r'$old', 2000)], limited: true),
        };
      await client.oneShotSync();
      await _settle();
      expect(
        notified,
        isEmpty,
        reason: r'$old was already in the room before the new connection',
      );
      await client.dispose();
    });

    test('c1-1: a new message on the same connection still notifies', () async {
      final (server, client, notified) = await started();
      server.rooms = {
        _roomId: room([message(r'$new', 3000)], initial: false),
      };
      await client.oneShotSync();
      await _settle();
      expect(notified, [r'$new']);
      await client.dispose();
    });

    test(
        'c1-1: a limited timeline that overlaps the stored one keeps it; '
        'one with a gap drops it', () async {
      final (server, client, _) = await started();
      final stored = client.getRoomById(_roomId)!;
      server
        ..forgetPos = 1
        ..rooms = {
          _roomId: room([message(r'$old', 2000)], limited: true),
        };
      await client.oneShotSync();
      expect(
        await client.database.getEventIdList(stored),
        contains(r'$older'),
        reason: 'no gap: the stored timeline stays',
      );

      server
        ..forgetPos = 1
        ..rooms = {
          _roomId: room([message(r'$after_gap', 9000)], limited: true),
        };
      await client.oneShotSync();
      expect(
        await client.database.getEventIdList(stored),
        isNot(contains(r'$older')),
        reason: 'a gap: dropped, as /v3/sync does',
      );
      await client.dispose();
    });

    // ROOSTER: T6.6. MSC4186 has no per-thread unread counts, so under
    // Sliding Sync the room's own counts from the server are the
    // authority: the per-thread ones `/v3/sync` left are dropped, and not
    // stored, instead of adding to the badge until a thread is read here.
    group('per-thread unread counts', () {
      const otherRoomId = '!other:example.test';

      /// A `/v3/sync` naming [roomIds] with a room count of 1 and an
      /// unread thread of 2 notifications, 1 highlight.
      Future<void> v3ThreadCounts(Client client, List<String> roomIds) =>
          client.database.transaction(
            () => client.handleSync(
              SyncUpdate.fromJson({
                'next_batch': 'v3_0_0',
                'rooms': {
                  'join': {
                    for (final roomId in roomIds)
                      roomId: {
                        'state': {
                          'events': [
                            _state(
                              'm.room.member',
                              {'membership': 'join'},
                              stateKey: _alice,
                            ),
                          ],
                        },
                        'unread_notifications': {
                          'notification_count': 1,
                          'highlight_count': 0,
                        },
                        'unread_thread_notifications': {
                          r'$thread_root': {
                            'notification_count': 2,
                            'highlight_count': 1,
                          },
                        },
                      },
                  },
                },
              }),
            ),
          );

      Map<String, Object?> slidingRoom(int count, {bool initial = false}) => {
            if (initial) 'initial': true,
            if (initial)
              'required_state': [
                _state(
                  'm.room.member',
                  {'membership': 'join'},
                  stateKey: _alice,
                ),
              ],
            'timeline': [],
            // MSC4186 only has the room's own counts.
            'notification_count': count,
            'highlight_count': 0,
          };

      Map<String, UnreadNotificationCounts> threadsOf(
        Client client,
        String roomId,
      ) =>
          client.getRoomById(roomId)!.unreadThreadNotifications;

      test(
          'after the change to Sliding Sync a room has only the count from '
          'the server, a read on another device clears it, and a restart '
          'does not bring the old thread counts back', () async {
        final server = _Homeserver();
        final database = await getDatabase();
        const name = 'sliding_sync_thread_counts';
        final client = await _client(
          server,
          database: database,
          name: name,
          forceLegacySync: true,
        );
        await v3ThreadCounts(client, [_roomId]);
        expect(
          threadsOf(client, _roomId)[r'$thread_root']?.notificationCount,
          2,
        );

        client.forceLegacySync = false;
        server.rooms = {_roomId: slidingRoom(3, initial: true)};
        await client.oneShotSync();
        expect(client.syncTransport, SyncTransport.slidingSync);
        final room = client.getRoomById(_roomId)!;
        expect(room.notificationCount, 3);
        expect(
          room.unreadThreadNotifications,
          isEmpty,
          reason: 'the thread counts /v3/sync left no longer count',
        );

        // Read on another device: the server's count drops to zero.
        server.rooms = {_roomId: slidingRoom(0)};
        await client.oneShotSync();
        expect(room.notificationCount, 0);
        expect(room.unreadThreadNotifications, isEmpty);
        await client.dispose(closeDatabase: false);

        final restarted = await _client(
          server,
          database: database,
          name: name,
          restart: true,
        );
        expect(
          threadsOf(restarted, _roomId),
          isEmpty,
          reason: 'the stored thread counts were cleared',
        );
        await restarted.dispose();
      });

      test(
          'a room the Sliding Sync answer leaves out loses its thread counts '
          'too', () async {
        final server = _Homeserver();
        final client = await _client(server, forceLegacySync: true);
        await v3ThreadCounts(client, [_roomId, otherRoomId]);

        client.forceLegacySync = false;
        server.rooms = {_roomId: slidingRoom(0, initial: true)};
        await client.oneShotSync();
        expect(client.syncTransport, SyncTransport.slidingSync);
        expect(threadsOf(client, otherRoomId), isEmpty);
        expect(threadsOf(client, _roomId), isEmpty);
        await client.dispose();
      });

      test(
          'counts stored before T6.6 on an account already on Sliding Sync '
          'are cleared before its first answer, and not stored again',
          () async {
        final server = _Homeserver();
        final database = await getDatabase();
        const name = 'sliding_sync_thread_counts_restart';
        final first = await _client(server, database: database, name: name);
        server.rooms = {_roomId: slidingRoom(0, initial: true)};
        await first.oneShotSync();
        expect(first.syncTransport, SyncTransport.slidingSync);
        // What a build before T6.6 kept under Sliding Sync.
        await v3ThreadCounts(first, [_roomId]);
        await first.dispose(closeDatabase: false);

        final second = await _client(
          server,
          database: database,
          name: name,
          restart: true,
        );
        expect(threadsOf(second, _roomId), isNotEmpty);
        server.broken = true;
        await second.oneShotSync();
        expect(second.syncTransport, SyncTransport.slidingSync);
        expect(
          threadsOf(second, _roomId),
          isEmpty,
          reason: 'Sliding Sync is already the transport: no need to wait',
        );
        await second.dispose(closeDatabase: false);

        final third = await _client(
          server,
          database: database,
          name: name,
          restart: true,
        );
        expect(threadsOf(third, _roomId), isEmpty);
        await third.dispose();
      });

      test('back on /v3/sync the thread counts come from the server again',
          () async {
        final server = _Homeserver();
        final database = await getDatabase();
        const name = 'sliding_sync_thread_counts_back';
        final client = await _client(server, database: database, name: name);
        server.rooms = {_roomId: slidingRoom(0, initial: true)};
        await client.oneShotSync();
        expect(client.syncTransport, SyncTransport.slidingSync);

        client.forceLegacySync = true;
        await client.oneShotSync();
        expect(client.syncTransport, SyncTransport.v3);
        await v3ThreadCounts(client, [_roomId]);
        expect(
          threadsOf(client, _roomId)[r'$thread_root']?.notificationCount,
          2,
        );
        await client.dispose(closeDatabase: false);

        final restarted = await _client(
          server,
          database: database,
          name: name,
          forceLegacySync: true,
          restart: true,
        );
        expect(
          threadsOf(restarted, _roomId)[r'$thread_root']?.highlightCount,
          1,
          reason: '/v3/sync stores them as before',
        );
        await restarted.dispose();
      });

      // Review c1-1: a server that announces Sliding Sync and refuses it
      // keeps /v3/sync, and its per-thread counts.
      test(
          'c1-1: a 404 fallback on restart keeps the /v3/sync per-thread unread '
          'counts', () async {
        final db = await getDatabase();
        const name = 't66_c1_1_fallback_restart';
        var v3Seq = 0;

        final first = await _open(
          name,
          db,
          _refusingServer(bare404: false, nextV3: () => ++v3Seq),
        );
        await first
            .oneShotSync(); // Sliding Sync refused -> fallback to /v3/sync.
        expect(first.slidingSyncFallbackReason, 'M_UNRECOGNIZED');
        await first.oneShotSync(); // /v3/sync delivers unread thread counts.
        expect(
          first
              .getRoomById(_roomId)!
              .unreadThreadNotifications[r'$thread_root']
              ?.notificationCount,
          2,
        );
        await first.dispose(closeDatabase: false);

        // Restart: fallback reason is per-run, so Sliding Sync is tried again,
        // refused again, and incremental /v3/sync omits the quiet room.
        final second = await _open(
          name,
          db,
          _refusingServer(bare404: false, nextV3: () => ++v3Seq),
          restart: true,
        );
        await second.oneShotSync();
        expect(second.slidingSyncFallbackReason, 'M_UNRECOGNIZED');
        expect(second.syncTransport, SyncTransport.v3);
        await second.oneShotSync();

        final room = second.getRoomById(_roomId)!;
        expect(
          room.unreadThreadNotifications[r'$thread_root']?.notificationCount,
          2,
          reason: 'Sliding Sync was refused; /v3/sync thread counts must stay',
        );
        expect(
          room.unreadThreadNotifications[r'$thread_root']?.highlightCount,
          1,
        );
        final stored = await db
            .getCustomCacheObject('rooster_unread_thread_notifications');
        expect(
          (stored?.content['rooms'] as Map?)?[_roomId],
          isNotNull,
          reason:
              'the stored /v3/sync thread counts must not be overwritten empty',
        );
        await second.dispose();
      });

      test(
          'c1-1: leaving forceLegacySync on a server that returns HTTP 404 keeps '
          'the /v3/sync per-thread unread counts', () async {
        final db = await getDatabase();
        const name = 't66_c1_1_fallback_proxy';
        var v3Seq = 0;
        final server = _refusingServer(bare404: true, nextV3: () => ++v3Seq);

        final client = await _open(name, db, server, forceLegacySync: true);
        await client.oneShotSync();
        expect(
          client
              .getRoomById(_roomId)!
              .unreadThreadNotifications[r'$thread_root']
              ?.notificationCount,
          2,
        );

        client.forceLegacySync = false;
        await client
            .oneShotSync(); // Bare 404 from proxy -> fallback to /v3/sync.
        expect(client.slidingSyncFallbackReason, 'HTTP 404');
        expect(client.syncTransport, SyncTransport.v3);
        await client.oneShotSync();

        expect(
          client
              .getRoomById(_roomId)!
              .unreadThreadNotifications[r'$thread_root']
              ?.notificationCount,
          2,
          reason: 'a refused switch to Sliding Sync must not wipe /v3 counts',
        );
        await client.dispose();
      });
    });

    test('b-1: without a count or a pos the requests wait instead of polling',
        () async {
      final server = _Homeserver()
        ..omitCount = true
        ..omitPos = true;
      final client = await _client(server);
      await client.oneShotSync();
      await client.oneShotSync();
      await client.oneShotSync();
      final timeouts = server.slidingRequests
          .map((r) => r.$1.queryParameters['timeout'])
          .toList();
      expect(timeouts, ['0', '30000', '30000']);
      final ranges = server.slidingRequests
          .map(
            (r) => jsonEncode(
              ((r.$2['lists'] as Map)['all_rooms'] as Map)['ranges'],
            ),
          )
          .toSet();
      expect(ranges, hasLength(1), reason: 'the range does not grow blindly');
      await client.dispose();
    });
  });
}
