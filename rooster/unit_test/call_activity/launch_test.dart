// Launching in a voice channel whose room refuses the activity's state
// (channels made before it was opened to everyone keep the state default,
// moderators): the failure surfaces, and leaves nothing behind that would
// make every later launch in that channel a silent no-op.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
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
  @override
  String? get userID => _self;

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    if (refuseWith case final error?) throw error;
    return '\$event';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  _SdkRoom(this.client);
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

  setUp(() {
    room = _Room();
    call = InMemoryActivityCall();
    now = DateTime.now();
    component = MatrixCallActivityComponent(_Client(), room,
        clock: HomeserverClock(localNow: () => now),
        ownCallTransport: () => call.join('$_self:DEVICE'));
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

  test('without permission for the state, the launch says so', () async {
    room._sdk.allowed = false;
    await expectLater(
        component.launch(activity),
        throwsA(isA<CallActivityLaunchException>()
            .having((e) => e.notAllowed, 'notAllowed', isTrue)));
  });
}

String _name() => 'Test game';
