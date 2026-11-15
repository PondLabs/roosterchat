// Messages for chosen participants, and a component's own part of the
// session's state: what a game with secrets (Cock-a-Doodle-Who?'s plaques)
// needs from the framework. Run over the in-memory transport, and against a
// fake LiveKit room for what the real transport publishes.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/matrix/components/call_activity/livekit_call_activity_transport.dart';

final _activity = CallActivity(id: 'chat.commet.who', displayName: () => 'Who');

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

CallActivitySession _session(InMemoryActivityCall call, String identity) =>
    CallActivitySession(
        activity: _activity,
        selfUserId: '@$identity:example.org',
        transport: call.join(identity));

class _Published {
  _Published(this.message, this.to, this.topic, this.reliable);
  final Map<String, Object?> message;
  final List<String>? to;
  final String? topic;
  final bool? reliable;
}

class _LocalParticipant implements lk.LocalParticipant {
  final List<_Published> published = [];

  @override
  String get identity => '@me:example.org:DEVICE';

  @override
  Future<void> publishData(List<int> data,
      {bool? reliable,
      List<String>? destinationIdentities,
      String? topic}) async {
    published.add(_Published(
        jsonDecode(utf8.decode(data)) as Map<String, Object?>,
        destinationIdentities,
        topic,
        reliable));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Listener implements lk.EventsListener<lk.RoomEvent> {
  @override
  Future<void> Function() on<E>(FutureOr<void> Function(E) then,
          {bool Function(E)? filter}) =>
      () async {};

  @override
  Future<bool> dispose() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements lk.Room {
  @override
  final _LocalParticipant localParticipant = _LocalParticipant();

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView(const {});

  @override
  lk.EventsListener<lk.RoomEvent> createListener({bool synchronized = false}) =>
      _Listener();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('the in-memory transport', () {
    test('delivers an addressed message to the chosen identities alone',
        () async {
      final call = InMemoryActivityCall();
      final heard = <String, List<Map<String, Object?>>>{};
      final transports = {
        for (final identity in ['alice', 'bob', 'carol', 'dave'])
          identity: call.join(identity)
            ..incoming.listen(
                (i) => heard.putIfAbsent(identity, () => []).add(i.message)),
      };

      await transports['alice']!.send({'t': 'x', 'n': 1}, to: ['bob', 'dave']);
      await _settle();

      expect(heard.keys.toSet(), {'bob', 'dave'});
      expect(
          call.delivered.map((d) => (d.to, d.from, d.message['n'])).toSet(), {
        ('bob', 'alice', 1),
        ('dave', 'alice', 1),
      });
      await call.close();
    });

    test('a message for nobody reaches nobody', () async {
      final call = InMemoryActivityCall();
      final alice = call.join('alice');
      call.join('bob');

      await alice.send({'t': 'x'}, to: const []);
      await _settle();

      expect(call.delivered, isEmpty);
      await call.close();
    });
  });

  group('the LiveKit transport', () {
    test('publishes an addressed message with its identities as destination',
        () async {
      final room = _Room();
      final transport = LivekitCallActivityTransport(room);

      await transport.send({'t': 'direct', 'm': 1}, to: ['bob', 'dave']);

      final sent = room.localParticipant.published.single;
      expect(sent.to, ['bob', 'dave']);
      expect(sent.message, {'t': 'direct', 'm': 1});
      expect(sent.topic, CallActivityProtocol.topic);
      expect(sent.reliable, isTrue);
    });

    test('publishes nothing for an empty list, which LiveKit reads as everyone',
        () async {
      final room = _Room();
      final transport = LivekitCallActivityTransport(room);

      await transport.send({'t': 'direct'}, to: const []);

      expect(room.localParticipant.published, isEmpty);
    });

    test('still publishes to everyone when no identities are given', () async {
      final room = _Room();
      final transport = LivekitCallActivityTransport(room);

      await transport.send({'t': 'state'});

      expect(room.localParticipant.published.single.to, isNull);
    });
  });

  group('CallActivitySession.sendTo', () {
    late InMemoryActivityCall call;
    late Map<String, CallActivitySession> sessions;
    late Map<String, List<CallActivityDirect>> heard;

    setUp(() async {
      call = InMemoryActivityCall();
      heard = {};
      sessions = {
        for (final identity in ['alice', 'bob', 'carol'])
          identity: _session(call, identity),
      };
      for (final MapEntry(key: identity, value: session) in sessions.entries) {
        session.direct
            .listen((d) => heard.putIfAbsent(identity, () => []).add(d));
      }
      await sessions['alice']!.launch();
      await _settle();
      await sessions['bob']!.join();
      await sessions['carol']!.join();
      await _settle();
    });

    tearDown(() => call.close());

    test('reaches the chosen participants with its sender, whoever sends it',
        () async {
      // Bob does not host: unlike the relay lane, anyone may address anyone.
      await sessions['bob']!.sendTo(['carol'], {'secret': 'for carol'});
      await _settle();

      expect(heard.keys, ['carol']);
      expect(heard['carol']!.single.sender, 'bob');
      expect(heard['carol']!.single.message, {'secret': 'for carol'});
      final wire = call.log.where((m) => m.$2['t'] == 'direct').single;
      expect(wire.$3, ['carol']);
    });

    test('sends nothing when nobody else is addressed', () async {
      final before = call.log.length;

      await sessions['bob']!.sendTo(const [], {'secret': 1});
      await sessions['bob']!.sendTo(['bob'], {'secret': 2});
      await _settle();

      expect(call.log.length, before);
      expect(heard, isEmpty);
    });

    test('a message past the packet limit arrives whole, to its addressees',
        () async {
      final big = {'words': List.generate(4000, (i) => 'word-$i')};

      await sessions['alice']!.sendTo(['bob'], big);
      await _settle();

      expect(heard.keys, ['bob']);
      expect((heard['bob']!.single.message['words'] as List).length, 4000);
      expect(
          call.delivered
              .where((d) => d.to == 'carol' && d.message['t'] == 'part'),
          isEmpty);
    });
  });

  group('CallActivitySession.hostPart', () {
    test('a part rides every state, beside the game, and outlives its host',
        () async {
      final call = InMemoryActivityCall();
      final alice = _session(call, 'alice');
      final bob = _session(call, 'bob');
      final carol = _session(call, 'carol');
      await alice.launch();
      await _settle();
      await bob.join();
      await carol.join();
      await _settle();

      alice.hostPart('plaques', {'round': 1});
      alice.hostGamePayload({'phase': 'writing'});
      await alice.sendState();
      await _settle();
      expect(bob.snapshot.parts['plaques'], {'round': 1});
      expect(bob.snapshot.game, {'phase': 'writing'});

      // The game's next payload leaves the part where it is.
      alice.hostGamePayload({'phase': 'asking'});
      await alice.sendState();
      await _settle();
      expect(carol.snapshot.parts['plaques'], {'round': 1});

      // Only the host's word counts.
      bob.hostPart('plaques', {'round': 99});
      expect(bob.snapshot.parts['plaques'], {'round': 1});

      // The elected host carries the part on.
      call.leave('alice');
      await _settle();
      expect(bob.isHost, isTrue);
      expect(carol.snapshot.parts['plaques'], {'round': 1});
      await call.close();
    });

    test('a session without parts sends the state it always sent', () async {
      final call = InMemoryActivityCall();
      final alice = _session(call, 'alice');
      await alice.launch();
      await _settle();

      final state = call.log.lastWhere((m) => m.$2['t'] == 'state').$2;
      expect(state.containsKey('parts'), isFalse);
      await call.close();
    });
  });
}
