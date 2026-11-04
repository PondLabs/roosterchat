// The call-activity framework's own contracts: the wire (split/assemble),
// and the host-authoritative session run over the in-memory transport —
// launch, join, capacity, leave, host election, handoff, and the input
// lane.


import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';

CallActivity _activity({int maxPlayers = 8}) => CallActivity(
      id: 'chat.commet.putt',
      displayName: () => 'Sunny Side Putt',
      maxPlayers: maxPlayers,
    );

/// Runs [body] until the transports' microtask-queued deliveries settle.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('CallActivityProtocol', () {
    test('a large state splits and reassembles whole', () {
      final message = {
        't': 'state',
        'id': 'session',
        'game': {
          'details': List.generate(4000, (i) => 'piece-$i'),
        },
      };
      final parts = CallActivityProtocol.split(message);
      expect(parts, isNotNull, reason: 'a big state must split, not be lost');
      expect(parts!.length, greaterThan(1));

      final assembled = CallPartAssembler();
      Map<String, Object?>? whole;
      for (final part in parts) {
        whole = assembled.add('host', part);
      }
      expect(whole, isNotNull);
      expect(whole!['t'], 'state');
      final game = whole['game'] as Map;
      expect((game['details'] as List).length, 4000);
    });

    test('a small message travels whole, no pieces', () {
      final parts = CallActivityProtocol.split({'t': 'bye'});
      expect(parts, isNotNull);
      expect(parts!.length, 1);
    });
  });

  group('CallActivitySession', () {
    test('launch announces the session and sends the first state', () async {
      final call = InMemoryActivityCall();
      final host = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));

      await host.launch();
      await _settle();

      expect(host.isHost, isTrue);
      expect(host.hasSession, isTrue);
      expect(host.snapshot.players, {'alice'});
      final wire = call.log;
      expect(
        wire.any((m) => m.$1 == 'alice' && m.$2['t'] == 'announce'),
        isTrue,
      );
      final state = wire.lastWhere((m) => m.$2['t'] == 'state').$2;
      expect(state['activity'], 'chat.commet.putt');
      expect(state['host'], '@alice:example.org');
      expect(state['seq'], 1);
      await call.close();
    });

    test('a joiner seeded from room state becomes a player', () async {
      final call = InMemoryActivityCall();
      final host = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      await host.launch();
      await _settle();

      final bob = CallActivitySession(
          activity: _activity(), selfUserId: '@bob:example.org',
          transport: call.join('bob'));
      // The room state told him there is a session and who hosts it.
      bob.seedFromRoom(
        sessionId: host.snapshot.sessionId,
        activityId: 'chat.commet.putt',
        hostUserId: '@alice:example.org',
      );
      await bob.join();
      await _settle();

      expect(bob.role, CallActivityRole.player);
      expect(bob.snapshot.players, {'alice', 'bob'});
      final joined =
          call.log.lastWhere((m) => m.$1 == 'alice' && m.$2['t'] == 'joined',
              orElse: () => ('', {}, <String>[]));
      expect(joined.$2['as'], 'player');
      await call.close();
    });

    test('the player past capacity becomes a spectator', () async {
      final call = InMemoryActivityCall();
      final host = CallActivitySession(
          activity: _activity(maxPlayers: 2), selfUserId: '@a:example.org',
          transport: call.join('a'));
      await host.launch();
      await _settle();
      for (final identity in ['b', 'c']) {
        final joiner = CallActivitySession(
            activity: _activity(maxPlayers: 2),
            selfUserId: '@$identity:example.org',
            transport: call.join(identity));
        joiner.seedFromRoom(
          sessionId: host.snapshot.sessionId,
          activityId: 'chat.commet.putt',
          hostUserId: '@a:example.org',
        );
        await joiner.join();
        await _settle();
      }
      expect(host.snapshot.players, {'a', 'b'});
      expect(host.snapshot.spectators, {'c'});
      await call.close();
    });

    test('the last one out ends the session with a bye', () async {
      final call = InMemoryActivityCall();
      final witness = CallActivitySession(
          activity: _activity(), selfUserId: '@mallory:example.org',
          transport: call.join('mallory'));
      final host = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      await host.launch();
      await _settle();

      await host.leave();
      await _settle();

      expect(host.hasSession, isFalse);
      final bye = call.log.lastWhere((m) => m.$2['t'] == 'bye',
          orElse: () => ('', {}, <String>[]));
      expect(bye.$1, 'alice');
      // The witness's copy folded: no session left on their side either.
      await witness.leave();
      expect(witness.hasSession, isFalse);
      await call.close();
    });

    test('the host vanishing elects the lowest present identity',
        () async {
      final call = InMemoryActivityCall();
      final carol = CallActivitySession(
          activity: _activity(), selfUserId: '@carol:example.org',
          transport: call.join('carol'));
      final alice = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      final bob = CallActivitySession(
          activity: _activity(), selfUserId: '@bob:example.org',
          transport: call.join('bob'));
      await alice.launch();
      await _settle();
      for (final joiner in [bob, carol]) {
        await joiner.join();
        await _settle();
      }

      // Alice's client dies mid-call: her identity drops off the wire
      // without a bye.
      call.leave('alice');
      await _settle();

      expect(bob.isHost, isTrue, reason: 'bob sorts before carol');
      expect(bob.snapshot.players, {'bob', 'carol'});
      await call.close();
    });

    test('handoff moves the seat only when the target acknowledges',
        () async {
      final call = InMemoryActivityCall();
      final alice = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      final bob = CallActivitySession(
          activity: _activity(), selfUserId: '@bob:example.org',
          transport: call.join('bob'));
      await alice.launch();
      await _settle();
      await bob.join();
      await _settle();

      // Bob has told the room he can host (the hello/caps flow).
      bob.transport.send({
        't': 'caps',
        'u': '@bob:example.org',
        'acts': ['chat.commet.putt'],
        'host': true,
      });
      await _settle();
      expect(alice.canHandoffTo('bob'), isTrue);

      await alice.handoffOffer('bob');
      await _settle();

      expect(bob.isHost, isTrue);
      expect(alice.isHost, isFalse);
      await call.close();
    });

    test('player input reaches the host and nobody else', () async {
      final call = InMemoryActivityCall();
      final host = CallActivitySession(
          activity: _activity(), selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      final bob = CallActivitySession(
          activity: _activity(), selfUserId: '@bob:example.org',
          transport: call.join('bob'));
      await host.launch();
      await _settle();
      await bob.join();
      await _settle();

      final inputs = <Map<String, Object?>>[];
      host.inputs.listen(inputs.add);
      final others = <Map<String, Object?>>[];
      // A third ear hears nothing of the input lane.
      call
          .join('mallory')
          .incoming
          .listen((i) => others.add(i.message));

      await bob.sendInput({
        'kind': 'shot',
        'angle': 1.2,
        'power': 0.7,
      });
      await _settle();

      expect(inputs, hasLength(1));
      expect(inputs.single['kind'], 'shot');
      expect(others.any((m) => m['t'] == 'input'), isFalse);
      await call.close();
    });
  });
}
