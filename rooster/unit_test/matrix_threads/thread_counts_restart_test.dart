// Review c1-1: the threads' unread counts survive a restart of the app.
//
// With per-thread counts in the sync filter the server leaves the threads
// out of a room's own counts, and `MatrixRoom` adds them back from
// `Room.unreadThreadNotifications`. Outside the browser the rooms are kept
// in the drift database, a package of its own; the SDK keeps the counts
// in its custom cache, which that database implements too. These tests run
// over it, and read the room again the way the app does when it starts.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_unread.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

void main() {
  const roomId = '!threads:example.test';

  http.Response json(Object body) => http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json'});

  MockClient homeserver() => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/_matrix/client/versions')) {
          return json({
            'versions': ['v1.4', 'v1.11']
          });
        }
        if (path.endsWith('/filter')) return json({'filter_id': 'filter'});
        if (path.endsWith('/_matrix/client/v3/sync')) {
          return json({'next_batch': 's_empty'});
        }
        return json({});
      });

  /// A client over [database] with the app's sync filter: signed in when
  /// [signIn], and otherwise the account [database] holds, as after a
  /// restart of the app.
  Future<matrix.Client> open(String name, MatrixSdkDriftDatabase database,
      {bool signIn = false}) async {
    final client = matrix.Client(name,
        httpClient: homeserver(),
        database: database,
        syncFilter: MatrixClient.syncFilter);
    client.backgroundSync = false;
    client.syncErrorTimeoutSec = 0;
    if (signIn) {
      await client.init(
        newHomeserver: Uri.parse('https://hs.example.test'),
        newToken: 'token',
        newUserID: '@alice:example.test',
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

  /// A sync with the room's counts and its threads', as
  /// `(notifications, highlights)` by root id.
  Future<void> syncCounts(matrix.Client client,
          {int notifications = 0, Map<String, (int, int)>? threads}) =>
      client.handleSync(matrix.SyncUpdate.fromJson({
        'next_batch': 's_${DateTime.now().microsecondsSinceEpoch}',
        'rooms': {
          'join': {
            roomId: {
              'unread_notifications': {
                'notification_count': notifications,
                'highlight_count': 0,
              },
              if (threads != null)
                'unread_thread_notifications': {
                  for (final entry in threads.entries)
                    entry.key: {
                      'notification_count': entry.value.$1,
                      'highlight_count': entry.value.$2,
                    },
                },
            },
          },
        },
      }));

  test("a room's threads are still unread after a restart", () async {
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'thread_counts_restart');
    addTearDown(database.db.close);

    final first = await open('thread_counts_restart', database, signIn: true);
    await syncCounts(first, notifications: 1, threads: {r'$root': (2, 1)});
    await first.dispose(closeDatabase: false);

    final second = await open('thread_counts_restart', database);
    final room = second.getRoomById(roomId)!;
    expect(room.notificationCount, 1);
    expect(
        MatrixThreadUnread.of(room, r'$root'), const ThreadUnreadCounts(2, 1));
    await second.dispose(closeDatabase: false);
  });

  test('a thread read here stays read after a restart', () async {
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'thread_counts_read_here');
    addTearDown(database.db.close);

    final first = await open('thread_counts_read_here', database, signIn: true);
    await syncCounts(first, threads: {r'$read': (2, 0), r'$unread': (1, 0)});
    MatrixThreadUnread.clearLocally(first.getRoomById(roomId)!, r'$read');
    // The store is not awaited by the caller.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await first.dispose(closeDatabase: false);

    final second = await open('thread_counts_read_here', database);
    final room = second.getRoomById(roomId)!;
    expect(MatrixThreadUnread.of(room, r'$read').isEmpty, isTrue);
    expect(MatrixThreadUnread.of(room, r'$unread').notifications, 1);
    await second.dispose(closeDatabase: false);
  });

  test('"Mark as Read" leaves no thread unread after a restart', () async {
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'thread_counts_mark_read');
    addTearDown(database.db.close);

    final first = await open('thread_counts_mark_read', database, signIn: true);
    await syncCounts(first, threads: {r'$a': (2, 0), r'$b': (1, 0)});
    MatrixThreadUnread.clearAllLocally(first.getRoomById(roomId)!);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await first.dispose(closeDatabase: false);

    final second = await open('thread_counts_mark_read', database);
    expect(MatrixThreadUnread.all(second.getRoomById(roomId)!), isEmpty);
    await second.dispose(closeDatabase: false);
  });
}
