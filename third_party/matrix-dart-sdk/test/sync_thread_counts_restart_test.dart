// ROOSTER: With the sync filter asking for per-thread unread counts
// (Matrix v1.4, MSC3773), the server's room counts leave the threads out
// and Rooster adds them back from Room.unreadThreadNotifications. They are
// kept across restarts, so a room with unread thread replies does not look
// read when the app starts again.
//
// And a session whose new filter cannot be defined carries on syncing with
// the filter it had.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

MockClient _mock({
  bool failFilter = false,
  String filterId = 'filter_new',
  void Function(Uri uri)? onSync,
  void Function()? onFilter,
}) {
  var syncs = 0;
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/_matrix/client/versions')) {
      return _json({
        'versions': ['v1.4', 'v1.6', 'v1.11'],
      });
    }
    if (path.contains('/_matrix/client/v3/user/') && path.endsWith('/filter')) {
      onFilter?.call();
      if (failFilter) {
        return _json({'errcode': 'M_UNKNOWN', 'error': 'boom'}, 500);
      }
      return _json({'filter_id': filterId});
    }
    if (path.endsWith('/_matrix/client/v3/sync')) {
      syncs++;
      onSync?.call(request.url);
      return _json({'next_batch': 's_$syncs'});
    }
    if (path.endsWith('/_matrix/client/v3/keys/query')) {
      return _json({'device_keys': {}});
    }
    return _json({});
  });
}

final _plain = Filter(
  room: RoomFilter(state: StateFilter(lazyLoadMembers: true)),
);
final _threads = Filter(
  room: RoomFilter(
    state: StateFilter(lazyLoadMembers: true),
    timeline: StateFilter(unreadThreadNotifications: true),
  ),
);

Future<Client> _login(
  String name,
  DatabaseApi db,
  Filter filter, {
  String filterId = 'filter_new',
}) async {
  final client = Client(
    name,
    httpClient: _mock(filterId: filterId),
    database: db,
    syncFilter: filter,
  );
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  await client.init(
    newHomeserver: Uri.parse('https://hs.example.test'),
    newToken: 'access_tok',
    newUserID: '@alice:example.test',
    newDeviceID: 'DEV01',
    newDeviceName: 'Test Device',
    waitForFirstSync: false,
  );
  await client.abortSync();
  return client;
}

/// The app starts again on [db].
Future<Client> _restart(
  String name,
  DatabaseApi db, {
  MockClient? httpClient,
  Filter? filter,
}) async {
  final client = Client(
    name,
    httpClient: httpClient ?? _mock(),
    database: db,
    syncFilter: filter ?? _threads,
  );
  client.backgroundSync = false;
  client.syncErrorTimeoutSec = 0;
  await client.init(waitForFirstSync: false);
  await client.abortSync();
  return client;
}

const _roomId = '!threads:example.test';

/// A sync with [room]'s counts and, when given, its threads' as
/// `[notifications, highlights]` by root id.
Future<void> _syncCounts(
  Client client, {
  String room = _roomId,
  int notifications = 0,
  Map<String, List<int>>? threads,
}) =>
    client.database.transaction(
      () => client.handleSync(
        SyncUpdate.fromJson({
          'next_batch': 's_counts_${DateTime.now().microsecondsSinceEpoch}',
          'rooms': {
            'join': {
              room: {
                'unread_notifications': {
                  'notification_count': notifications,
                  'highlight_count': 0,
                },
                if (threads != null)
                  'unread_thread_notifications': {
                    for (final entry in threads.entries)
                      entry.key: {
                        'notification_count': entry.value[0],
                        'highlight_count': entry.value[1],
                      },
                  },
              },
            },
          },
        }),
      ),
    );

int? _count(Client client, String root, {String room = _roomId}) => client
    .getRoomById(room)!
    .unreadThreadNotifications[root]
    ?.notificationCount;

void main() {
  Logs().level = Level.error;

  group('per-thread unread counts', () {
    test('c1-1: survive a restart', () async {
      final db = await getDatabase();
      final first = await _login('thread_counts_restart', db, _threads);
      await first.oneShotSync(timeout: Duration.zero);
      await _syncCounts(
        first,
        notifications: 1,
        threads: {
          r'$root': [2, 1],
        },
      );
      expect(_count(first, r'$root'), 2);
      await first.dispose(closeDatabase: false);

      final second = await _restart('thread_counts_restart', db);
      final room = second.getRoomById(_roomId)!;
      expect(room.notificationCount, 1);
      // What MatrixRoom.notificationCount adds to the room's count.
      expect(
        room.unreadThreadNotifications[r'$root']?.notificationCount,
        2,
        reason: 'the thread replies are gone from the room badge after a '
            'restart',
      );
      expect(room.unreadThreadNotifications[r'$root']?.highlightCount, 1);
      await second.dispose(closeDatabase: false);
    });

    test('are kept per room, as the last sync of each left them', () async {
      const other = '!other:example.test';
      final db = await getDatabase();
      final first = await _login('thread_counts_rooms', db, _threads);
      await _syncCounts(
        first,
        threads: {
          r'$a': [2, 0],
          r'$b': [1, 0],
        },
      );
      await _syncCounts(
        first,
        room: other,
        threads: {
          r'$c': [4, 0],
        },
      );
      // The server names every thread with any: `$a` has none left.
      await _syncCounts(
        first,
        threads: {
          r'$b': [3, 0],
        },
      );
      await first.dispose(closeDatabase: false);

      final second = await _restart('thread_counts_rooms', db);
      expect(_count(second, r'$a'), isNull);
      expect(_count(second, r'$b'), 3);
      expect(_count(second, r'$c', room: other), 4);
      await second.dispose(closeDatabase: false);
    });

    test('read by a sync stay read after a restart', () async {
      final db = await getDatabase();
      final first = await _login('thread_counts_read', db, _threads);
      await _syncCounts(
        first,
        threads: {
          r'$root': [2, 0],
        },
      );
      // The room's counts with no thread: none has any.
      await _syncCounts(first);
      await first.dispose(closeDatabase: false);

      final second = await _restart('thread_counts_read', db);
      expect(second.getRoomById(_roomId)!.unreadThreadNotifications, isEmpty);
      await second.dispose(closeDatabase: false);
    });

    test('changed by hand are kept with storeUnreadThreadNotifications',
        () async {
      final db = await getDatabase();
      final first = await _login('thread_counts_local', db, _threads);
      await _syncCounts(
        first,
        threads: {
          r'$read': [2, 0],
          r'$unread': [1, 0],
        },
      );
      // A thread read here, before any sync says so.
      first.getRoomById(_roomId)!.unreadThreadNotifications.remove(r'$read');
      await first.storeUnreadThreadNotifications();
      await first.dispose(closeDatabase: false);

      final second = await _restart('thread_counts_local', db);
      expect(_count(second, r'$read'), isNull);
      expect(_count(second, r'$unread'), 1);
      await second.dispose(closeDatabase: false);
    });

    test('of a room we left are not brought back', () async {
      final db = await getDatabase();
      final first = await _login('thread_counts_left', db, _threads);
      await _syncCounts(
        first,
        threads: {
          r'$root': [2, 0],
        },
      );
      await first.database.transaction(
        () => first.handleSync(
          SyncUpdate.fromJson({
            'next_batch': 's_left',
            'rooms': {
              'leave': {_roomId: <String, Object?>{}},
            },
          }),
        ),
      );
      final stored = await first.database
          .getCustomCacheObject('rooster_unread_thread_notifications');
      expect(stored?.content['rooms'], isEmpty);
      await first.dispose(closeDatabase: false);
    });

    test('unreadable in the cache do not stop the client from starting',
        () async {
      final db = await getDatabase();
      final first = await _login('thread_counts_bad', db, _threads);
      await _syncCounts(
        first,
        threads: {
          r'$root': [2, 0],
        },
      );
      await db.cacheCustomObject('rooster_unread_thread_notifications', {
        'rooms': {
          _roomId: {r'$root': 'not counts', r'$ok': <String, Object?>{}},
          '!gone:example.test': 7,
        },
      });
      await first.dispose(closeDatabase: false);

      final second = await _restart('thread_counts_bad', db);
      final threads = second.getRoomById(_roomId)!.unreadThreadNotifications;
      expect(threads.containsKey(r'$root'), isFalse);
      expect(threads[r'$ok']?.notificationCount, 0);
      await second.dispose(closeDatabase: false);
    });
  });

  group('c1-2: a new filter that cannot be defined', () {
    test('keeps the session syncing with the filter it had', () async {
      final db = await getDatabase();
      final first =
          await _login('filter_failure', db, _plain, filterId: 'filter_old');
      await first.oneShotSync(timeout: Duration.zero);
      expect(first.syncFilterId, 'filter_old');
      await first.dispose(closeDatabase: false);

      final syncs = <Uri>[];
      var filters = 0;
      final second = await _restart(
        'filter_failure',
        db,
        httpClient: _mock(
          failFilter: true,
          onSync: syncs.add,
          onFilter: () => filters++,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await second.oneShotSync(timeout: Duration.zero);
      }

      expect(
        syncs,
        hasLength(3),
        reason: 'no sync ran while the filter failed',
      );
      expect(syncs.map((uri) => uri.queryParameters['filter']).toSet(), {
        'filter_old',
      });
      // Asked once in this run, not on every sync.
      expect(filters, 1);
      expect(second.syncFilterId, 'filter_old');
      await second.dispose(closeDatabase: false);

      // The next run tries again, and gets it.
      final third = await _restart(
        'filter_failure',
        db,
        httpClient: _mock(filterId: 'filter_threads', onSync: syncs.add),
      );
      await third.oneShotSync(timeout: Duration.zero);
      expect(third.syncFilterId, 'filter_threads');
      expect(syncs.last.queryParameters['filter'], 'filter_threads');
      await third.dispose(closeDatabase: false);
    });

    test('at login still fails the sync, as before', () async {
      final db = await getDatabase();
      final client = Client(
        'filter_failure_login',
        httpClient: _mock(failFilter: true),
        database: db,
        syncFilter: _threads,
      );
      client.backgroundSync = false;
      client.syncErrorTimeoutSec = 0;
      await client.init(
        newHomeserver: Uri.parse('https://hs.example.test'),
        newToken: 'access_tok',
        newUserID: '@alice:example.test',
        newDeviceID: 'DEV01',
        newDeviceName: 'Test Device',
        waitForFirstSync: false,
      );
      await client.abortSync();
      expect(client.syncFilterId, isNull);
      await client.dispose(closeDatabase: false);
    });
  });
}
