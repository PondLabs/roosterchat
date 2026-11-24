// ROOSTER: MatrixRTC's newer pieces (T5.2): sticky events (MSC4354) from
// both sync transports, kept across a restart; delayed events (MSC4140) on
// the stable API where the homeserver has it, each one managed on the API
// it was scheduled with; and memberships of the newer format (MSC4143)
// listed beside the legacy ones, once per device.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';
import 'webrtc_stub.dart';

const _roomId = '!call:example.test';
const _me = '@alice:example.test';
const _rtcType = 'org.matrix.msc4143.rtc.member';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A homeserver announcing [versions] and [features], recording every
/// request but `/versions` and `/sync`.
class _Homeserver {
  _Homeserver({
    this.versions = const ['v1.11'],
    this.features = const {},
  });

  List<String> versions;
  Map<String, bool> features;
  final List<http.Request> requests = [];

  late final MockClient mock = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/_matrix/client/versions')) {
      return _json({'versions': versions, 'unstable_features': features});
    }
    if (path.endsWith('/_matrix/client/v3/sync')) {
      return _json({'next_batch': 's_1'});
    }
    if (path.contains('/keys/query')) return _json({'device_keys': {}});
    requests.add(request);
    if (path.contains('/state/') &&
        request.url.queryParameters.keys
            .any((k) => k == 'delay' || k == 'org.matrix.msc4140.delay')) {
      return _json({'delay_id': 'delay_1'});
    }
    if (path.contains('/state/')) return _json({'event_id': r'$state'});
    if (path.endsWith('delayed_events') ||
        path.endsWith('delayed_events/scheduled')) {
      return _json({'delayed_events': []});
    }
    return _json({});
  });
}

Future<Client> _login(String name, DatabaseApi db, _Homeserver server) async {
  final client = Client(name, httpClient: server.mock, database: db);
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  await client.init(
    newHomeserver: Uri.parse('https://hs.example.test'),
    newToken: 'access_tok',
    newUserID: _me,
    newDeviceID: 'DEV01',
    newDeviceName: 'Test Device',
    waitForFirstSync: false,
  );
  await client.abortSync();
  return client;
}

/// A sticky rtc membership of [sender]'s [device], sent [sentAt].
Map<String, Object?> _sticky(
  String eventId, {
  String sender = '@bob:example.test',
  String device = 'BOB',
  required DateTime sentAt,
  int durationMs = 120000,
  bool left = false,
  String key = 'stable',
}) =>
    {
      'type': _rtcType,
      'event_id': eventId,
      'sender': sender,
      'origin_server_ts': sentAt.millisecondsSinceEpoch,
      'msc4354_sticky': {'duration_ms': durationMs},
      'content': {
        'msc4354_sticky_key': '${sender}_${device}_$key',
        if (!left) ...{
          'slot_id': 'm.call#',
          'application': {'type': 'm.call', 'm.call.id': ''},
          'member': {'id': 'm_$device', 'device_id': device, 'user_id': sender},
          'rtc_transports': [
            {
              'type': 'livekit',
              'livekit_service_url': 'https://sfu.example.test',
            },
          ],
          'versions': [],
        },
      },
    };

Future<void> _sync(Client client, Map<String, Object?> room) =>
    client.database.transaction(
      () => client.handleSync(
        SyncUpdate.fromJson({
          'next_batch': 's_${DateTime.now().microsecondsSinceEpoch}',
          'rooms': {
            'join': {_roomId: room},
          },
        }),
      ),
    );

void main() {
  Logs().level = Level.error;
  // To the millisecond, as events carry it.
  final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch);

  group('sticky events (MSC4354)', () {
    test('come from the sticky section and the timeline, once each', () {
      final update = JoinedRoomUpdate.fromJson({
        'msc4354_sticky': {
          'events': [
            _sticky(r'$a', sentAt: now, durationMs: 60000),
            _sticky(r'$b', sentAt: now, device: 'B2'),
          ],
        },
        'timeline': {
          'events': [
            _sticky(r'$a', sentAt: now, durationMs: 60000),
            {
              'type': 'm.room.message',
              'event_id': r'$m',
              'sender': '@bob:example.test',
              'origin_server_ts': now.millisecondsSinceEpoch,
              'content': {'body': 'hi'},
            },
          ],
        },
      });
      expect(update.sticky!.map((e) => e.eventId), [r'$a', r'$b']);
      expect(
        update.sticky!.first.unsigned![JoinedRoomUpdate.stickyDurationKey],
        60000,
      );
      // The stable name of the section too.
      final stable = JoinedRoomUpdate.fromJson({
        'sticky': {
          'events': [_sticky(r'$s', sentAt: now)],
        },
      });
      expect(stable.sticky!.single.eventId, r'$s');
      expect(JoinedRoomUpdate.fromJson({}).sticky, isNull);
      // Written back with the duration where it came from.
      final again = JoinedRoomUpdate.fromJson(update.toJson());
      expect(
        again.sticky!.first.unsigned![JoinedRoomUpdate.stickyDurationKey],
        60000,
      );
    });

    test('stay sticky for their duration, an hour at most', () {
      final event = MatrixEvent.fromJson(_sticky(r'$a', sentAt: now));
      expect(RoomStickyEvents.stickyExpiresAt(event), isNull);
      final update = JoinedRoomUpdate.fromJson({
        'sticky': {
          'events': [
            _sticky(r'$a', sentAt: now, durationMs: 5 * 3600 * 1000),
          ],
        },
      });
      expect(
        RoomStickyEvents.stickyExpiresAt(update.sticky!.single),
        now.add(const Duration(hours: 1)),
      );
    });

    test('from /v3/sync are kept by sticky key and survive a restart',
        () async {
      final db = await getDatabase();
      final server = _Homeserver();
      final first = await _login('sticky_restart', db, server);
      await _sync(first, {
        'msc4354_sticky': {
          'events': [
            _sticky(r'$join', sentAt: now),
            _sticky(r'$carol', sender: '@carol:example.test', sentAt: now),
          ],
        },
      });
      // A newer one of the same key replaces it, an older one does not.
      await _sync(first, {
        'msc4354_sticky': {
          'events': [
            _sticky(
              r'$left',
              sentAt: now.add(const Duration(seconds: 5)),
              left: true,
            ),
            _sticky(r'$old', sentAt: now.subtract(const Duration(minutes: 1))),
          ],
        },
      });
      final room = first.getRoomById(_roomId)!;
      expect(
        room.stickyEventsOfType(_rtcType).map((e) => e.eventId).toSet(),
        {r'$left', r'$carol'},
      );
      await first.dispose(closeDatabase: false);

      final second =
          Client('sticky_restart', httpClient: server.mock, database: db)
            ..backgroundSync = false;
      await second.init(waitForFirstSync: false);
      await second.abortSync();
      final restored = second.getRoomById(_roomId)!;
      expect(
        restored.stickyEventsOfType(_rtcType).map((e) => e.eventId).toSet(),
        {r'$left', r'$carol'},
        reason: 'an incremental sync never hands them out again',
      );
      expect(
        RoomStickyEvents.stickyExpiresAt(
          restored.stickyEventsOfType(_rtcType).first,
        ),
        isNotNull,
      );
      await second.dispose();
    });

    test('from Sliding Sync are asked for and land in the same place',
        () async {
      final transport = SlidingSyncTransport(
        MatrixApi(homeserver: Uri.parse('https://hs.example.test')),
        paths: const [
          '_matrix/client/unstable/org.matrix.simplified_msc3575/sync',
        ],
      );
      final extensions =
          transport.requestBody()['extensions'] as Map<String, Object?>;
      expect(
        extensions[SlidingSyncTransport.stickyExtension],
        {'enabled': true},
      );

      final update = slidingSyncToSyncUpdate(
        {
          'pos': '1',
          'rooms': {
            _roomId: {'initial': true, 'timeline': []},
          },
          'extensions': {
            SlidingSyncTransport.stickyExtension: {
              'rooms': {
                _roomId: {
                  'events': [_sticky(r'$ss', sentAt: now)],
                },
                // A room the list did not bring this time.
                '!other:example.test': {
                  'events': [_sticky(r'$other', sentAt: now)],
                },
              },
            },
          },
        },
        userId: _me,
        isJoinedRoom: (id) => id == '!other:example.test',
      );
      final join = update.rooms!.join!;
      expect(join[_roomId]!.sticky!.single.eventId, r'$ss');
      expect(join['!other:example.test']!.sticky!.single.eventId, r'$other');

      final db = await getDatabase();
      final client = await _login('sticky_sliding', db, _Homeserver());
      await client.database.transaction(() => client.handleSync(update));
      expect(
        client
            .getRoomById(_roomId)!
            .stickyEventsOfType(_rtcType)
            .single
            .eventId,
        r'$ss',
      );
      await client.dispose();
    });
  });

  group('delayed events (MSC4140)', () {
    DelayedEventsSupport of(List<String> versions, [Map<String, bool>? f]) =>
        DelayedEventsSupport.of(
          GetVersionsResponse(versions: versions, unstableFeatures: f),
        );

    test('stable from v1.20 or with the stable flag, else unstable', () {
      expect(of(['v1.11', 'v1.20']), DelayedEventsSupport.stable);
      expect(of(['v1.21']), DelayedEventsSupport.stable);
      expect(
        of(['v1.11'], {'org.matrix.msc4140.stable': true}),
        DelayedEventsSupport.stable,
      );
      expect(
        of(['v1.11', 'v1.19'], {'org.matrix.msc4140': true}),
        DelayedEventsSupport.unstable,
      );
      expect(of(['v1.2', 'v1.9']), DelayedEventsSupport.none);
    });

    test('are scheduled and managed on the API asked for', () async {
      final server = _Homeserver();
      final client = await _login('delayed_paths', await getDatabase(), server);

      await client.setRoomStateWithKeyWithDelay(
        _roomId,
        'm.x',
        'k',
        1000,
        {},
        via: DelayedEventsSupport.stable,
      );
      await client.manageDelayedEvent(
        'delay_1',
        DelayedEventAction.restart,
        via: DelayedEventsSupport.stable,
      );
      await client.setRoomStateWithKeyWithDelay(_roomId, 'm.x', 'k', 1000, {});
      await client.manageDelayedEvent('delay_1', DelayedEventAction.send);

      final [stableArm, stableRestart, unstableArm, unstableSend] =
          server.requests;
      expect(stableArm.url.queryParameters, {'delay': '1000'});
      expect(
        stableRestart.url.path,
        '/_matrix/client/v1/delayed_events/delay_1',
      );
      expect(jsonDecode(stableRestart.body), {'action': 'restart'});
      expect(
        unstableArm.url.queryParameters,
        {'org.matrix.msc4140.delay': '1000'},
      );
      expect(
        unstableSend.url.path,
        '/_matrix/client/unstable/org.matrix.msc4140/delayed_events/delay_1',
      );
      await client.dispose();
    });

    for (final (name, versions, features, prefix) in [
      ('v1.20', ['v1.20'], <String, bool>{}, '/_matrix/client/v1/'),
      (
        'older',
        ['v1.11'],
        {'org.matrix.msc4140': true},
        '/_matrix/client/unstable/org.matrix.msc4140/',
      ),
    ]) {
      test('a call membership on a $name homeserver uses $prefix', () async {
        final server = _Homeserver(versions: versions, features: features);
        final client =
            await _login('delayed_call_$name', await getDatabase(), server);
        await _sync(client, {
          'state': {
            'events': [
              {
                'type': EventTypes.RoomPowerLevels,
                'state_key': '',
                'event_id': r'$pl',
                'sender': _me,
                'origin_server_ts': now.millisecondsSinceEpoch,
                'content': {
                  'users': {_me: 100},
                },
              },
            ],
          },
        });
        final room = client.getRoomById(_roomId)!;
        final voip = VoIP(client, MockWebRTCDelegate());
        await room.updateFamedlyCallMemberStateEvent(
          CallMembership(
            userId: _me,
            roomId: _roomId,
            callId: '',
            backend: LiveKitBackend(
              livekitServiceUrl: 'https://sfu.example.test',
              livekitAlias: _roomId,
            ),
            deviceId: 'DEV01',
            expiresTs: now.add(const Duration(hours: 4)).millisecondsSinceEpoch,
            membershipId: 'm1',
            voip: voip,
          ),
        );
        final canceller = voip.delayedEventCancellers.values.single;
        canceller.restartTimer.cancel();

        final delayed = server.requests.where(
          (r) => r.url.path.contains('delayed_events'),
        );
        expect(delayed, isNotEmpty);
        expect(delayed.every((r) => r.url.path.startsWith(prefix)), isTrue);
        final arm = server.requests.firstWhere(
          (r) => r.url.queryParameters.isNotEmpty,
        );
        expect(
          arm.url.queryParameters.keys.single,
          name == 'v1.20' ? 'delay' : 'org.matrix.msc4140.delay',
        );

        // The homeserver upgrades mid-call: the leave scheduled before is
        // still cancelled where it lives.
        server.versions = name == 'v1.20' ? ['v1.11'] : ['v1.20'];
        server.features = {'org.matrix.msc4140': true};
        server.requests.clear();
        await room.removeFamedlyCallMemberEvent('', voip);
        final cancel = server.requests.lastWhere(
          (r) => r.url.path.contains('delayed_events'),
        );
        expect(cancel.url.path, '${prefix}delayed_events/delay_1');
        expect(jsonDecode(cancel.body), {'action': 'cancel'});
        await client.dispose();
      });
    }
  });

  group('memberships of the newer format (MSC4143)', () {
    test('are listed beside the legacy ones, once per device', () async {
      final client =
          await _login('rtc_listing', await getDatabase(), _Homeserver());
      await _sync(client, {
        'state': {
          'events': [
            {
              'type': EventTypes.GroupCallMember,
              'state_key': '_@bob:example.test_BOB_m.call',
              'event_id': r'$legacy',
              'sender': '@bob:example.test',
              'origin_server_ts': now.millisecondsSinceEpoch,
              'content': {
                'memberships': [
                  {
                    'call_id': '',
                    'application': 'm.call',
                    'scope': 'm.room',
                    'device_id': 'BOB',
                    'expires_ts': now
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch,
                    'foci_active': [
                      {
                        'type': 'livekit',
                        'livekit_alias': _roomId,
                        'livekit_service_url': 'https://sfu.example.test',
                      },
                    ],
                    'membershipID': 'legacy',
                  },
                ],
              },
            },
          ],
        },
        'msc4354_sticky': {
          'events': [
            // Bob writes both formats: listed once.
            _sticky(r'$bob', sentAt: now),
            _sticky(
              r'$carol',
              sender: '@carol:example.test',
              device: 'C',
              sentAt: now,
            ),
            _sticky(
              r'$dave',
              sender: '@dave:example.test',
              device: 'D',
              sentAt: now,
              left: true,
            ),
          ],
        },
      });
      final room = client.getRoomById(_roomId)!;
      final voip = VoIP(client, MockWebRTCDelegate());
      final memberships = room
          .getCallMembershipsFromRoom(voip)
          .values
          .expand((list) => list)
          .toList();
      expect(
        memberships.map((m) => (m.userId, m.deviceId)).toList(),
        unorderedEquals([
          ('@bob:example.test', 'BOB'),
          ('@carol:example.test', 'C'),
        ]),
      );
      final carol = memberships.firstWhere((m) => m.deviceId == 'C');
      expect(carol.membershipId, 'm_C');
      expect(carol.application, 'm.call');
      expect(
        carol.expiresTs,
        now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      );
      expect(room.activeGroupCallIds(voip), ['']);
      await client.dispose();
    });
  });
}
