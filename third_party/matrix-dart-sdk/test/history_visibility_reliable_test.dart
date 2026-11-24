// ROOSTER: `Room.historyVisibility` in memory, which decides whether a new
// Megolm session may go in an MSC4268 bundle (MSC3061 `shared_history`).
// `Room.postLoad` used to read the database while a sync was still writing
// to it: a new room then read no visibility at all, and a room that turned
// `joined` kept saying `shared`.

import 'dart:async';

import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _roomId = '!visibility:fakeServer.notExisting';
const _userId = '@othertest:fakeServer.notExisting';

void main() {
  late Client client;
  var next = 0;

  /// A session of [_userId]; with [restarting], the same one again, started
  /// from that client's database.
  Future<Client> newClient({Client? restarting}) async {
    final c = Client(
      'visibility${next++}',
      httpClient: FakeMatrixApi(),
      database: restarting?.database ?? await getDatabase(),
    );
    await c.checkHomeserver(
      Uri.parse('https://fakeserver.notexisting'),
      checkWellKnown: false,
    );
    if (restarting != null) {
      await c.init();
    } else {
      await c.init(
        newToken: 'abcd',
        newUserID: _userId,
        newHomeserver: c.homeserver,
        newDeviceName: 'VISIBILITYDEV',
        newDeviceID: 'VISIBILITYDEV',
      );
    }
    await Future.delayed(const Duration(milliseconds: 10));
    await c.abortSync();
    return c;
  }

  MatrixEvent stateEvent(
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
    DateTime? at,
  }) =>
      MatrixEvent(
        type: type,
        content: content,
        stateKey: stateKey,
        senderId: _userId,
        eventId: '\$$type${content.values.join()}${at ?? ''}',
        originServerTs: at ?? DateTime.now(),
      );

  MatrixEvent visibility(String value, {DateTime? at}) => stateEvent(
        EventTypes.HistoryVisibility,
        {'history_visibility': value},
        at: at,
      );

  List<MatrixEvent> newRoom(String value) => [
        stateEvent(EventTypes.RoomCreate, {'creator': _userId}),
        stateEvent(EventTypes.Encryption, {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
        }),
        visibility(value),
        stateEvent(
          EventTypes.RoomMember,
          {'membership': 'join'},
          stateKey: _userId,
        ),
      ];

  SyncUpdate syncOf(List<MatrixEvent> state) => SyncUpdate(
        nextBatch: 'b${next++}',
        rooms: RoomsUpdate(
          join: {
            _roomId: JoinedRoomUpdate(
              state: state,
              summary: RoomSummary.fromJson({'m.joined_member_count': 1}),
            ),
          },
        ),
      );

  /// A sync as `Client` runs one, in a database transaction that goes on a
  /// while after the sync's events are handled (the next batch and the sync
  /// continuity are stored there too). [whileSyncing] runs as the app's
  /// listener of `Client.onSync` would, before the transaction ends.
  Future<void> syncInTransaction(
    List<MatrixEvent> state, {
    void Function(Room room)? whileSyncing,
  }) async {
    final listening = client.onSync.stream.listen((_) {
      final room = client.getRoomById(_roomId);
      if (room != null) whileSyncing?.call(room);
    });
    await client.database.transaction(() async {
      await client.handleSync(syncOf(state));
      await client.database.storePrevBatch('stored');
      await Future.delayed(const Duration(milliseconds: 20));
    });
    await listening.cancel();
  }

  group('Room.historyVisibility in memory', () {
    setUp(() async => client = await newClient());
    tearDown(() async => client.dispose(closeDatabase: true));

    test('a new room loaded while the sync bringing it is stored', () async {
      final loads = <Future<void>>[];
      // The app loads a room's state as soon as a sync brings the room.
      await syncInTransaction(
        newRoom('shared'),
        whileSyncing: (room) => loads.add(room.postLoad()),
      );
      await Future.wait(loads);
      final room = client.getRoomById(_roomId)!;
      expect(loads, isNotEmpty);
      expect(room.partial, isFalse);
      expect(room.historyVisibility, HistoryVisibility.shared);
    });

    test('a room reloaded from the database', () async {
      await syncInTransaction(newRoom('shared'));
      await syncInTransaction([visibility('joined')]);
      final before = client;
      await before.dispose(closeDatabase: false);
      client = await newClient(restarting: before);
      final room = client.getRoomById(_roomId)!;
      expect(room.partial, isTrue);
      await room.postLoad();
      expect(room.historyVisibility, HistoryVisibility.joined);
    });

    test('a change to "joined" while the room is being loaded', () async {
      await syncInTransaction(newRoom('shared'));
      final before = client;
      await before.dispose(closeDatabase: false);
      client = await newClient(restarting: before);
      final room = client.getRoomById(_roomId)!;
      expect(room.partial, isTrue);

      final loads = <Future<void>>[];
      await syncInTransaction(
        [visibility('joined')],
        whileSyncing: (room) => loads.add(room.postLoad()),
      );
      await Future.wait(loads);
      expect(loads, isNotEmpty);
      expect(room.historyVisibility, HistoryVisibility.joined);
    });

    test('a change to "joined" synced while a load reads the database',
        () async {
      await syncInTransaction(newRoom('shared'));
      final before = client;
      await before.dispose(closeDatabase: false);
      client = await newClient(restarting: before);
      final room = client.getRoomById(_roomId)!;
      expect(room.partial, isTrue);

      final load = room.postLoad();
      await syncInTransaction([visibility('joined')]);
      await load;
      expect(room.historyVisibility, HistoryVisibility.joined);
    });

    test('a change to "joined" in a loaded room shows at once', () async {
      await syncInTransaction(newRoom('shared'));
      final room = client.getRoomById(_roomId)!;
      await room.postLoad();
      expect(room.historyVisibility, HistoryVisibility.shared);
      await syncInTransaction([visibility('joined')]);
      expect(room.historyVisibility, HistoryVisibility.joined);
    });

    test('a load waits for the sync being stored, not one inside it', () async {
      await syncInTransaction(newRoom('shared'));
      final before = client;
      await before.dispose(closeDatabase: false);
      client = await newClient(restarting: before);
      final room = client.getRoomById(_roomId)!;
      // A load from inside the transaction (a page of history checked
      // against the room's state) does not wait for that transaction.
      await client.database.transaction(() async {
        await room.postLoad().timeout(const Duration(seconds: 5));
      });
      expect(room.partial, isFalse);
      expect(room.historyVisibility, HistoryVisibility.shared);
    });
  });

  group('the next encrypted message', tags: 'olm', () {
    setUp(() async {
      try {
        vodInit ??= vod.init(
          wasmPath: './pkg/',
          libraryPath: './rust/target/debug/',
        );
        await vodInit;
      } catch (_) {}
      client = await newClient();
    });
    tearDown(() async => client.dispose(closeDatabase: true));

    Future<Map<String, dynamic>> say(String body) =>
        client.encryption!.encryptGroupMessagePayload(
          _roomId,
          {'msgtype': 'm.text', 'body': body},
        );

    bool? marked(Map<String, dynamic> message) => client.encryption!.keyManager
        .getInboundGroupSession(_roomId, message['session_id'] as String)!
        .content['shared_history'] as bool?;

    test('is not marked once the room turned "joined" mid-load', () async {
      await syncInTransaction(newRoom('shared'));
      final shared = await say('said under shared');
      expect(marked(shared), isTrue);

      final before = client;
      await before.dispose(closeDatabase: false);
      client = await newClient(restarting: before);
      final loads = <Future<void>>[];
      await syncInTransaction(
        [visibility('joined')],
        whileSyncing: (room) => loads.add(room.postLoad()),
      );
      await Future.wait(loads);
      expect(
        client.getRoomById(_roomId)!.historyVisibility,
        HistoryVisibility.joined,
      );
      final hidden = await say('said under joined');
      expect(hidden['session_id'], isNot(shared['session_id']));
      expect(marked(hidden), isNull);
    });

    // T3.2 review c2-1, as the reviewer reproduced it: another server's
    // clock runs behind, and the state in memory misses the event (the
    // `partial` flag set by hand stands for a load that raced the sync).
    test('review-skew: a "joined" dated earlier, missed by the state',
        () async {
      await client.handleSync(syncOf(newRoom('shared')));
      final room = client.getRoomById(_roomId)!;
      room.partial = false;
      expect(room.historyVisibility, isNull);
      final said = await say('said before the invite');
      expect(marked(said), isTrue);
      room.partial = true;
      await client.handleSync(
        syncOf([
          visibility(
            'joined',
            at: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ]),
      );
      room.partial = false;
      final hidden = await say('said under joined');
      expect(marked(hidden), isNull, reason: 'a session marked under joined');
    });

    test('a "shared" dated earlier still changes nothing', () async {
      await client.handleSync(syncOf(newRoom('joined')));
      final room = client.getRoomById(_roomId)!;
      room.partial = false;
      await client.handleSync(
        syncOf([
          visibility(
            'shared',
            at: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ]),
      );
      expect(marked(await say('still under joined')), isNull);
    });
  });
}
