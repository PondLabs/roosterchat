// The Matrix side of a call activity across the life of the call that
// holds it. Report (2026-11-05): the host hung up while alone in the call,
// and on coming back the shelf offered "Join" for the session that had just
// ended, not "Launch". Nothing ended the host's session when its call went
// away, so its room state stayed, the session (bound to the old call) stayed
// tracked and blocked a new launch, and the shelf listed the state as a
// session to join for its six hours.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/call_activity/matrix_call_activity_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

const _roomId = '!voice:example.org';
const _me = '@me:example.org';
const _myIdentity = '@me:example.org:DEVICEA';
const _alice = '@alice:example.org';
const _aliceIdentity = '@alice:example.org:ALICE';
const _type = MatrixCallActivityComponent.stateEventType;

final _putt = CallActivity(
  id: 'chat.commet.putt',
  displayName: () => 'Sunny Side Putt',
);

class _Profile implements Profile {
  _Profile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  @override
  Profile? self = _Profile(_me);

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The homeserver: every state write is kept, and comes back by sync.
class _SdkClient implements matrix.Client {
  final List<(String, String, Map<String, dynamic>)> writes = [];
  void Function(String type, String key, Map<String, dynamic> content)? echo;

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    writes.add((eventType, stateKey, Map.of(body)));
    echo?.call(eventType, stateKey, Map.of(body));
    return '\$written';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  _SdkRoom(this.client);

  @override
  final _SdkClient client;

  @override
  final String id = _roomId;

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements MatrixRoom {
  @override
  final String identifier = _roomId;

  @override
  final _SdkRoom matrixRoom = _SdkRoom(_SdkClient());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Our call in the voice channel.
class _Call implements VoipSession {
  _Call(this.client);

  @override
  final Client client;

  @override
  String get roomId => _roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Client client;
  late _Room room;
  late ClientManager clientManager;
  late MatrixCallActivityComponent component;

  /// The call on the wire, one per joined call, as LiveKit's room is.
  late InMemoryActivityCall wire;

  setUp(() {
    CallActivityRegistry.clear();
    CallActivityRegistry.register(_putt);
    client = _Client();
    room = _Room();
    clientManager = ClientManager();
    wire = InMemoryActivityCall();
    component = MatrixCallActivityComponent(client, room,
        callManager: clientManager.callManager,
        clock: HomeserverClock(),
        transportFor: (call) => wire.join(_myIdentity));
    // What the homeserver writes comes back by sync.
    room.matrixRoom.client.echo = (type, key, content) {
      final event = matrix.Event(
        type: type,
        eventId: '\$$key-${room.matrixRoom.client.writes.length}',
        senderId: _me,
        stateKey: key,
        originServerTs: DateTime.now(),
        room: room.matrixRoom,
        content: content,
      );
      (room.matrixRoom.states[type] ??= {})[key] = event;
      scheduleMicrotask(() => component.onSync(matrix.JoinedRoomUpdate(
          timeline: matrix.TimelineUpdate(events: [event]))));
    };
  });

  tearDown(CallActivityRegistry.clear);

  /// A session's state as someone else's client left it.
  void stateOf(String sessionId, {required String host}) {
    final key = MatrixCallActivityComponent.stateKeyOf(sessionId);
    final event = matrix.Event(
      type: _type,
      eventId: '\$$key',
      senderId: host,
      stateKey: key,
      originServerTs: DateTime.now(),
      room: room.matrixRoom,
      content: {
        'activity': _putt.id,
        'host': host,
        'created': DateTime.now().millisecondsSinceEpoch,
        'expires': MatrixCallActivityComponent.expires.inMilliseconds,
      },
    );
    (room.matrixRoom.states[_type] ??= {})[key] = event;
    component.onSync(matrix.JoinedRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [event])));
  }

  test(
      'hanging up alone ends the activity and clears its state; back in the '
      'call, it can be launched again', () async {
    final first = _Call(client);
    clientManager.callManager.currentSessions.add(first);
    final session = await component.launch(_putt);
    expect(session, isNotNull);
    await _settle();
    expect(component.liveSessions().map((s) => s.sessionId), [_myIdentity]);

    clientManager.callManager.currentSessions.remove(first);
    await _settle();

    final key = MatrixCallActivityComponent.stateKeyOf(_myIdentity);
    final (type, clearedKey, content) = room.matrixRoom.client.writes.last;
    expect((type, clearedKey), (_type, key));
    expect(content, isEmpty,
        reason: 'the room state of a session that ended must be cleared');
    expect(component.visibleSessions(), isEmpty);

    // Back in the channel: nothing to join, and a new launch goes through.
    wire = InMemoryActivityCall();
    final second = _Call(client);
    clientManager.callManager.currentSessions.add(second);
    await _settle();
    expect(component.liveSessions(), isEmpty,
        reason: 'the shelf must offer Launch, not Join');
    expect(await component.launch(_putt), isNotNull,
        reason: 'the session of the call we left must not block a launch');
  });

  test(
      'hanging up while others play leaves the session and its state to '
      'them', () async {
    final first = _Call(client);
    clientManager.callManager.currentSessions.add(first);
    final session = (await component.launch(_putt))!;
    final aliceSide = wire.join(_aliceIdentity);
    addTearDown(aliceSide.dispose);
    // Alice joins as a player.
    await aliceSide.send({'t': 'join', 'id': _myIdentity, 'as': 'player'},
        to: [_myIdentity]);
    await _settle();
    expect(session.snapshot.players, contains(_aliceIdentity));
    final writesBefore = room.matrixRoom.client.writes.length;

    clientManager.callManager.currentSessions.remove(first);
    await _settle();

    expect(room.matrixRoom.client.writes.length, writesBefore,
        reason: 'Alice plays on: the state stays until the last one ends it');
  });

  test(
      "a session nobody hosts (its host's app died) is not offered as one to "
      'join, nor does it block a launch', () async {
    stateOf(_aliceIdentity, host: _alice);
    clientManager.callManager.currentSessions.add(_Call(client));
    await _settle();

    expect(
        component.visibleSessions().map((s) => s.sessionId), [_aliceIdentity]);
    expect(component.liveSessions(), isEmpty);
    expect(await component.launch(_putt), isNotNull);
  });

  test('a session whose host is in the call is offered as one to join',
      () async {
    final aliceSide = wire.join(_aliceIdentity);
    addTearDown(aliceSide.dispose);
    stateOf(_aliceIdentity, host: _alice);
    clientManager.callManager.currentSessions.add(_Call(client));
    await _settle();
    final changes = <void>[];
    final sub = component.onChanged.listen(changes.add);
    addTearDown(sub.cancel);

    // The host's beat reaches us.
    await aliceSide.send({
      't': 'state',
      'id': _aliceIdentity,
      'activity': _putt.id,
      'host': _alice,
      'seq': 1,
      'players': [_aliceIdentity],
    });
    await _settle();

    expect(component.liveSessions().map((s) => s.sessionId), [_aliceIdentity]);
    expect(changes, isNotEmpty,
        reason: 'the call view rebuilds its pill and shelf off onChanged');
  });

  // Report (2026-11-07): leaving the activity normally and then the voice
  // channel left the session registered as if we were still playing, and it
  // could not be launched again until Rooster restarted. The clear hung on
  // _everHostedByUs, which only _onSessionChanged filled while isHost was
  // true: a host alone in its session never got such a notification (the
  // listener attaches after launch()'s notify, and sendState() does not
  // notify), and _endHosting() drops isHost before the notify that ends it.
  test(
      'leaving the activity and then hanging up clears its state, so the '
      'room does not keep it as if we were still playing', () async {
    final first = _Call(client);
    clientManager.callManager.currentSessions.add(first);
    final session = (await component.launch(_putt))!;
    await _settle();
    expect(component.liveSessions().map((s) => s.sessionId), [_myIdentity]);

    // The game's exit button: PuttSessionController.leave() -> session.leave().
    await session.leave();
    await _settle();

    // Then hang up.
    clientManager.callManager.currentSessions.remove(first);
    await _settle();

    final key = MatrixCallActivityComponent.stateKeyOf(_myIdentity);
    final (type, clearedKey, content) = room.matrixRoom.client.writes.last;
    expect((type, clearedKey), (_type, key));
    expect(content, isEmpty,
        reason: 'the state of the session we left must be cleared');
    expect(component.visibleSessions(), isEmpty);
  });

  test(
      'back in the channel after leaving the activity, nothing is left to '
      'block a launch', () async {
    final first = _Call(client);
    clientManager.callManager.currentSessions.add(first);
    final session = (await component.launch(_putt))!;
    await _settle();

    await session.leave();
    await _settle();
    clientManager.callManager.currentSessions.remove(first);
    await _settle();

    // Back in the channel.
    wire = InMemoryActivityCall();
    clientManager.callManager.currentSessions.add(_Call(client));
    await _settle();

    expect(component.visibleSessions(), isEmpty,
        reason: 'the shelf must offer Launch, not a session to join');
    expect(component.sessionOf(_myIdentity), isNull,
        reason: 'a stale state must not be seeded back into the sessions');
    expect(await component.launch(_putt), isNotNull,
        reason: 'the activity must be launchable again without a restart');
  });
}
