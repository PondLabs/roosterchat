// Launching in a voice channel whose room refuses the activity's state
// (channels made before it was opened to everyone keep the state default,
// moderators): the failure surfaces, and leaves nothing behind that would
// make every later launch in that channel a silent no-op.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/matrix/components/call_activity/matrix_call_activity_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

const _self = '@me:example.org';
const _roomId = '!voice:example.org';

class _Profile implements Profile {
  @override
  String get identifier => _self;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  @override
  Profile? self = _Profile();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkClient implements matrix.Client {
  Object? refuseWith;

  /// Every state write, in order: (state key, content).
  final List<(String, Map<String, Object?>)> writes = [];

  /// The room's state, so a write lands in it like the homeserver's would:
  /// a clear takes the event out, and the next sync no longer sees it.
  Map<String, Map<String, matrix.StrippedStateEvent>>? states;

  @override
  String? get userID => _self;

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    if (refuseWith case final error?) throw error;
    writes.add((stateKey, Map.of(body)));
    final states = this.states;
    if (states == null) return '\$event';
    final events = states[eventType] ??= {};
    if (body.isEmpty) {
      events.remove(stateKey);
    } else {
      events[stateKey] = matrix.StrippedStateEvent(
        type: eventType,
        senderId: _self,
        stateKey: stateKey,
        content: Map.of(body),
      );
    }
    return '\$event';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  _SdkRoom(this.client) {
    client.states = states;
  }
  @override
  final _SdkClient client;
  bool allowed = true;
  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> states = {};
  @override
  bool canChangeStateEvent(String action) => allowed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements MatrixRoom {
  final _SdkRoom _sdk = _SdkRoom(_SdkClient());
  @override
  String get identifier => _roomId;
  @override
  matrix.Room get matrixRoom => _sdk;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const activity = CallActivity(id: 'test.game', displayName: _name);
  late _Room room;
  late MatrixCallActivityComponent component;
  late InMemoryActivityCall call;
  late DateTime now;

  /// Whether we are in the call: a test leaves it by clearing this.
  late bool inCall;

  setUp(() {
    room = _Room();
    call = InMemoryActivityCall();
    now = DateTime.now();
    inCall = true;
    component = MatrixCallActivityComponent(_Client(), room,
        clock: HomeserverClock(localNow: () => now),
        ownCallTransport: () => inCall ? call.join('$_self:DEVICE') : null);
  });

  /// Puts [events] in the room state and syncs them in.
  void sync(List<matrix.StrippedStateEvent> events) {
    CallActivityRegistry.register(activity);
    final states =
        room._sdk.states[MatrixCallActivityComponent.stateEventType] ??= {};
    for (final event in events) {
      states[event.stateKey!] = event;
    }
    component.onSync(matrix.JoinedRoomUpdate(state: [
      for (final event in events)
        matrix.MatrixEvent(
          type: event.type,
          content: event.content,
          senderId: event.senderId,
          stateKey: event.stateKey,
          eventId: '\$${event.stateKey}',
          originServerTs: now,
        ),
    ]));
  }

  matrix.StrippedStateEvent session(String identity,
          {String? sender, String? host, int? created, int? expires}) =>
      matrix.StrippedStateEvent(
        type: MatrixCallActivityComponent.stateEventType,
        senderId: sender ?? identity.split(':').take(2).join(':'),
        stateKey: MatrixCallActivityComponent.stateKeyOf(identity),
        content: {
          'activity': activity.id,
          'host': host ?? identity.split(':').take(2).join(':'),
          'created': created ?? now.millisecondsSinceEpoch,
          if (expires != null) 'expires': expires,
        },
      );

  const alice = '@alice:example.org:DEVICE';

  test('a refused state write fails the launch and a retry still launches',
      () async {
    room._sdk.client.refuseWith = Exception('M_FORBIDDEN');
    await expectLater(component.launch(activity),
        throwsA(isA<CallActivityLaunchException>()));
    expect(component.sessionOf('$_self:DEVICE'), isNull);

    room._sdk.client.refuseWith = null;
    final session = await component.launch(activity);
    expect(session, isNotNull,
        reason: 'the failed launch must not leave a session that blocks this');
    expect(session!.isHost, isTrue);
  });

  test('stale state from a host who left neither shows nor blocks a launch',
      () async {
    const gone = '@gone:example.org:DEVICE';
    final stale = matrix.StrippedStateEvent(
      type: MatrixCallActivityComponent.stateEventType,
      senderId: '@gone:example.org',
      stateKey: MatrixCallActivityComponent.stateKeyOf(gone),
      content: {
        'activity': activity.id,
        'host': '@gone:example.org',
        'created': DateTime.now().millisecondsSinceEpoch,
      },
    );
    CallActivityRegistry.register(activity);
    room._sdk.states[MatrixCallActivityComponent.stateEventType] = {
      stale.stateKey!: stale,
    };
    component.onSync(matrix.JoinedRoomUpdate(state: [
      matrix.MatrixEvent(
        type: stale.type,
        content: stale.content,
        senderId: stale.senderId,
        stateKey: stale.stateKey,
        eventId: '\$stale',
        originServerTs: DateTime.now(),
      ),
    ]));
    expect(component.sessionOf(gone), isNotNull);
    now = now.add(MatrixCallActivityComponent.seedGrace);
    expect(component.liveSessions(), isEmpty);

    expect(await component.launch(activity), isNotNull);
  });

  test('a live session whose host is in the call is listed and blocks a launch',
      () async {
    call.join(alice);
    sync([session(alice)]);
    now = now.add(const Duration(minutes: 1));
    expect(component.liveSessions().map((s) => s.sessionId), [alice]);
    expect(await component.launch(activity), isNull);
    expect(component.sessionOf(alice), isNotNull);
  });

  test('a session freshly seeded from state is live through its grace period',
      () async {
    sync([session(alice)]);
    expect(component.liveSessions(), isNotEmpty);
    expect(await component.launch(activity), isNull);
    now = now.add(MatrixCallActivityComponent.seedGrace);
    expect(component.liveSessions(), isEmpty);
  });

  test('a re-hosted session stays live after its first host left', () async {
    const bob = '@bob:example.org:DEVICE';
    final bobWire = call.join(bob);
    sync([session(alice)]);
    await bobWire.send({'t': CallActivityMessageType.hostElected, 'host': bob});
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 1));
    expect(component.sessionOf(alice)!.hostIdentity, bob);
    expect(component.liveSessions().map((s) => s.sessionId), [alice]);
    expect(await component.launch(activity), isNull);
  });

  test('forged sessions are not shown', () {
    call.join(alice);
    final hour = const Duration(hours: 1).inMilliseconds;
    sync([
      // Someone else's key.
      session(alice, sender: '@mallory:example.org'),
      // Own key, someone else named as host.
      session('@mallory:example.org:X', host: '@alice:example.org'),
      // Created in the future, to never expire.
      session('@carol:example.org:X',
          created: now.millisecondsSinceEpoch + hour),
      // An expiry past the default.
      session('@dave:example.org:X',
          created: now.millisecondsSinceEpoch - 7 * hour, expires: 100 * hour),
    ]);
    expect(component.visibleSessions(), isEmpty);
  });

  test("blanking someone else's session state is ignored", () {
    call.join(alice);
    sync([session(alice)]);
    expect(component.visibleSessions(), hasLength(1));
    sync([
      matrix.StrippedStateEvent(
        type: MatrixCallActivityComponent.stateEventType,
        senderId: '@mallory:example.org',
        stateKey: MatrixCallActivityComponent.stateKeyOf(alice),
        content: const {},
      ),
    ]);
    expect(component.visibleSessions(), hasLength(1));
    expect(component.sessionOf(alice), isNotNull);
  });

  test('leaving the call drops the activity it was playing', () async {
    // The call is gone (we left it, or the connection took it down): its
    // activity goes with it. A session left behind kept the game running
    // and, its transport dead but its roster still naming everyone, made
    // every later launch in that channel a silent no-op.
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    final id = launched!.snapshot.sessionId;
    expect(component.sessionOf(id), isNotNull);

    inCall = false;
    sync([session(alice)]);
    await pumpEventQueue();

    expect(component.liveSessions(), isEmpty,
        reason: 'nothing of the call we left is ours to follow');
    expect(component.sessionOf(id), isNull);
    expect(launched.isDisposed, isTrue, reason: 'and it stops running');
  });

  test('a call joined again starts from the room state, not the old session',
      () async {
    final first = await component.launch(activity);
    expect(first, isNotNull);
    final firstId = first!.snapshot.sessionId;

    // Out of the call and back into it: the session we followed was the
    // old call's, and its transport is dead.
    inCall = false;
    sync([session(alice)]);
    await pumpEventQueue();
    inCall = true;
    sync([session(alice)]);
    await pumpEventQueue();

    expect(component.sessionOf(firstId), isNull);
    expect(component.liveSessions().map((s) => s.sessionId), [alice],
        reason: 'the room state is the truth again');
  });

  test('closing the room drops the activity with it', () async {
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    component.close();
    await pumpEventQueue();
    expect(component.liveSessions(), isEmpty);
    expect(launched!.isDisposed, isTrue);
  });

  // Report (2026-11-07): leaving the activity normally and then the voice
  // channel left the session registered as if we were still playing, and it
  // could not be launched again until Rooster restarted. The clear hung on
  // _everHostedByUs, which only _onSessionChanged filled while isHost was
  // true: a host alone in its session never got such a notification (the
  // listener attaches after launch()'s notify, and sendState() does not
  // notify), and _endHosting() drops isHost before the notify that ends it.
  test(
      'leaving the activity and then the call clears its state, so the room '
      'does not keep it as if we were still playing', () async {
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    final id = launched!.snapshot.sessionId;
    final key = MatrixCallActivityComponent.stateKeyOf(id);
    expect(room._sdk.client.writes.map((write) => write.$1), [key],
        reason: 'the launch wrote the state');

    // The game's exit button: PuttSessionController.leave() -> session.leave().
    await launched.leave();
    await pumpEventQueue();

    final (clearedKey, clearedContent) = room._sdk.client.writes.last;
    expect(clearedKey, key);
    expect(clearedContent, isEmpty,
        reason: 'the state of the session we left must be cleared');

    // Then the call goes.
    inCall = false;
    sync([session(alice)]);
    await pumpEventQueue();

    expect(component.sessionOf(id), isNull);
  });

  test('back in the channel after leaving the activity, a launch goes through',
      () async {
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    final id = launched!.snapshot.sessionId;

    await launched.leave();
    await pumpEventQueue();

    inCall = false;
    sync([session(alice)]);
    await pumpEventQueue();

    inCall = true;
    sync([session(alice)]);
    await pumpEventQueue();

    expect(component.sessionOf(id), isNull,
        reason: 'a stale state must not be seeded back into the sessions');

    // Alice's session is a stranger's, seeded a moment ago: past its grace
    // period it is nobody's, and does not block our launch.
    now = now.add(MatrixCallActivityComponent.seedGrace * 2);
    expect(await component.launch(activity), isNotNull,
        reason: 'the activity must be launchable again without a restart');
  });

  test('without permission for the state, the launch says so', () async {
    room._sdk.allowed = false;
    await expectLater(
        component.launch(activity),
        throwsA(isA<CallActivityLaunchException>()
            .having((e) => e.notAllowed, 'notAllowed', isTrue)));
  });

  // Report (2026-11-07): the host left the activity while a friend kept
  // playing. The friend's client showed the host gone; the host's own
  // client kept its "playing" badge until the friend left too. The badge
  // reads the session's roster, and the host that left stayed in its own
  // copy of it.
  test('a host that leaves the activity is out of the roster the badge reads',
      () async {
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    final id = launched!.snapshot.sessionId;

    // A friend in the same call joins the session.
    final bob = CallActivitySession(
      activity: activity,
      selfUserId: '@bob:example.org',
      transport: call.join('@bob:example.org:DEVICE'),
    );
    bob.seedFromRoom(
      sessionId: id,
      activityId: activity.id,
      hostUserId: _self,
    );
    await bob.join();
    await pumpEventQueue();
    expect(MatrixCallActivityComponent.rosterOf(launched),
        {'$_self:DEVICE', '@bob:example.org:DEVICE'});

    // The host leaves the activity; the friend plays on.
    await launched.leave();
    await pumpEventQueue();

    expect(MatrixCallActivityComponent.rosterOf(launched),
        {'@bob:example.org:DEVICE'},
        reason: 'the badge reads this roster: the host that left is not in it');
    expect(bob.isHost, isTrue, reason: 'the seat went to who stayed');

    // The friend leaves too: the session ends, and its state goes with it.
    await bob.leave();
    await pumpEventQueue();

    final (clearedKey, clearedContent) = room._sdk.client.writes.last;
    expect(clearedKey, MatrixCallActivityComponent.stateKeyOf(id));
    expect(clearedContent, isEmpty,
        reason: 'a session that ended is not left in the room state');
  });

  test('a session that ends is retired, not left running', () async {
    final launched = await component.launch(activity);
    expect(launched, isNotNull);
    final id = launched!.snapshot.sessionId;

    await launched.leave();
    await pumpEventQueue();

    expect(launched.isDisposed, isTrue,
        reason: 'a session that ended is not left running');
    expect(component.sessionOf(id), isNull);
  });
}

String _name() => 'Test game';
