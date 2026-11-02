import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Database implements matrix.DatabaseApi {
  @override
  Future<List<matrix.Event>> getUnimportantRoomEventStatesForRoom(
          List<String> types, matrix.Room room) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A client in [count] rooms, after the sync that listed them. With
/// [spaces], the rooms are split among that many spaces.
MatrixClient _clientInRooms(int count, {int spaces = 0}) {
  final client =
      MatrixClient(identifier: 'rooms-$count', database: _Database());
  client.mockComponents();
  final mx = client.getMatrixClient();
  for (var i = 0; i < count; i++) {
    mx.rooms.add(matrix.Room(id: '!room$i:example.com', client: mx));
  }
  for (var s = 0; s < spaces; s++) {
    final space = matrix.Room(id: '!space$s:example.com', client: mx);
    space.setState(matrix.Event.fromJson({
      'type': matrix.EventTypes.RoomCreate,
      'state_key': '',
      'sender': '@owner:example.com',
      'event_id': '\$create$s',
      'origin_server_ts': 0,
      'content': {'type': 'm.space'},
    }, space));
    for (var i = s; i < count; i += spaces) {
      space.setState(matrix.Event.fromJson({
        'type': matrix.EventTypes.SpaceChild,
        'state_key': '!room$i:example.com',
        'sender': '@owner:example.com',
        'event_id': '\$child$s-$i',
        'origin_server_ts': 0,
        'content': {
          'via': ['example.com']
        },
      }, space));
    }
    mx.rooms.add(space);
  }
  client.onMatrixClientSync(matrix.SyncUpdate(nextBatch: 'first'));
  return client;
}

/// What one more sync costs the main thread: every message sent or received
/// waits behind it.
Duration _syncCost(MatrixClient client) {
  const syncs = 5;
  final clock = Stopwatch()..start();
  for (var i = 0; i < syncs; i++) {
    client.onMatrixClientSync(matrix.SyncUpdate(nextBatch: 'sync $i'));
  }
  return clock.elapsed ~/ syncs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('a sync costs no more per room in a big account than in a small one',
      () {
    final small = _clientInRooms(250);
    final large = _clientInRooms(2000);
    expect(small.rooms, hasLength(250));
    expect(large.rooms, hasLength(2000));

    _syncCost(small);
    _syncCost(large); // warm up
    final smallCost = _syncCost(small);
    final largeCost = _syncCost(large);
    // ignore: avoid_print
    print('one sync: 250 rooms $smallCost, 2000 rooms $largeCost');

    // 8 times the rooms. Linear work grows about 8 times; work that compares
    // every room with every other grows 64 times.
    expect(largeCost.inMicroseconds,
        lessThan(smallCost.inMicroseconds * 20 + 2000));
  });

  test('the sidebar\'s unread count costs no more per room in a big account',
      () {
    // Recounted on every update to any room: the rooms outside spaces.
    ClientManager managerFor(int rooms) =>
        ClientManager()..addClient(_clientInRooms(rooms, spaces: 5));
    final small = managerFor(250);
    final large = managerFor(2000);
    expect(small.clients.single.spaces, hasLength(5));
    expect(small.clients.single.spaces.first.containsRoom('!room0:example.com'),
        isTrue);
    expect(small.clients.single.spaces.first.containsRoom('!room1:example.com'),
        isFalse);
    expect(small.singleRooms(), isEmpty, reason: 'every room is in a space');

    Duration cost(ClientManager manager) {
      final clock = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        manager.singleRooms();
      }
      return clock.elapsed ~/ 5;
    }

    cost(small);
    cost(large); // warm up
    final smallCost = cost(small);
    final largeCost = cost(large);
    // ignore: avoid_print
    print('unread count: 250 rooms $smallCost, 2000 rooms $largeCost');
    expect(largeCost.inMicroseconds,
        lessThan(smallCost.inMicroseconds * 20 + 2000));
  });
}
