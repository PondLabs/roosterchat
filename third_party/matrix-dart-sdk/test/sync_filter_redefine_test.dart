// ROOSTER: A stored sync filter id is defined again when the client's
// sync filter is no longer the one it was defined from (Rooster asking for
// per-thread unread counts, Matrix v1.4), and not while it is. (The
// SDK's clearCache forgets what it was defined from, which costs one more
// definition after it.)

import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

const _clientName = 'sync_filter_redefine';

final _plain = Filter(
  room: RoomFilter(state: StateFilter(lazyLoadMembers: true)),
);

final _threads = Filter(
  room: RoomFilter(
    state: StateFilter(lazyLoadMembers: true),
    timeline: StateFilter(unreadThreadNotifications: true),
  ),
);

/// Runs a client on [database] until its first sync, and returns how many
/// filters it defined.
Future<int> _run(
  DatabaseApi database,
  Filter filter, {
  bool login = false,
}) async {
  final api = FakeMatrixApi();
  final client = Client(
    _clientName,
    httpClient: api,
    database: database,
    syncFilter: filter,
  );
  FakeMatrixApi.client = client;
  if (login) {
    await client.checkHomeserver(
      Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false,
    );
    await client.init(
      newToken: 'abcd',
      newUserID: '@test:fakeServer.notExisting',
      newHomeserver: client.homeserver,
      newDeviceName: 'Text Matrix Client',
      newDeviceID: 'GHTYAJCE',
    );
  } else {
    await client.init();
  }
  await client.abortSync();
  final defined = FakeMatrixApi.calledEndpoints.entries
      .where((e) => e.key.endsWith('/filter'))
      .fold<int>(0, (sum, e) => sum + e.value.length);
  expect(client.syncFilterId, isNotNull);
  await client.dispose(closeDatabase: false);
  return defined;
}

void main() {
  group('sync filter', () {
    test('is defined once at login, and not again while it is the same',
        () async {
      final database = await getDatabase();
      expect(await _run(database, _plain, login: true), 1);
      expect(await _run(database, _plain), 0);
    });

    test('is defined again, once, when the client asks for another', () async {
      final database = await getDatabase();
      expect(await _run(database, _plain, login: true), 1);
      expect(await _run(database, _threads), 1);
    });

    test('is defined again for a session stored before it was remembered',
        () async {
      final database = await getDatabase();
      expect(await _run(database, _threads, login: true), 1);
      // What a session from before this change has: an id, nothing else.
      await database.cacheCustomObject('rooster_defined_sync_filter', {});
      expect(await _run(database, _threads), 1);
    });
  });
}
