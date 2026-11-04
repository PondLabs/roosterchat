// The live-session bridge: two clients over the in-memory transport —
// the launch, the guest's adoption of the host's match, a guest's shot
// landing on the host's engine, and the host leaving handing the seat
// over instead of ending the game. Timers run on fake async; the wire's
// hops settle inside `elapse`.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_launch_options.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';

CallActivity get _descriptor => CallActivity(
      id: 'chat.commet.putt',
      displayName: () => 'Sunny Side Putt',
      maxPlayers: 8,
    );

void main() {
  test('the host launches, the guest adopts, a guest shot lands twice',
      () {
    fakeAsync((async) {
      final call = InMemoryActivityCall();
      final hostSession = CallActivitySession(
          activity: _descriptor,
          selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      final guestSession = CallActivitySession(
          activity: _descriptor,
          selfUserId: '@bob:example.org',
          transport: call.join('bob'));

      final host =
          PuttSessionController(session: hostSession, nameOf: (id) => id);
      final config = PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual));
      host.hostStart(config);
      async.elapse(const Duration(milliseconds: 100));

      // The host's payload is out; the guest adopts it from the state.
      final guest =
          PuttSessionController(session: guestSession, nameOf: (id) => id);
      guest.adoptForTest();
      expect(guest.match, isNotNull, reason: 'the payload came through');
      expect(guest.match!.config.seed, host.match!.config.seed,
          reason: 'both engines share the exact config');

      // The guest asks in; the host's roster and engine take them.
      guestSession.join();
      async.elapse(const Duration(milliseconds: 600));
      host.adoptRosterForTest();
      expect(host.match!.engine.players.map((p) => p.id), contains('bob'));

      // The guest putts: optimistic at home, real at the host.
      expect(guest.match!.submitShot(0.3, 0.6), isTrue);
      async.elapse(const Duration(milliseconds: 200));
      expect(host.match!.engine.strokesInHole('bob'), 1,
          reason: 'the move reached the host through the session');
      expect(guest.match!.engine.strokesInHole('bob'), 1,
          reason: 'the optimistic shot stands; the relay does not double it');

      host.dispose();
      guest.dispose();
    });
  });

  test('the host leaving hands the session over, not out with it', () {
    fakeAsync((async) {
      final call = InMemoryActivityCall();
      final hostSession = CallActivitySession(
          activity: _descriptor,
          selfUserId: '@alice:example.org',
          transport: call.join('alice'));
      final guestSession = CallActivitySession(
          activity: _descriptor,
          selfUserId: '@bob:example.org',
          transport: call.join('bob'));

      final host =
          PuttSessionController(session: hostSession, nameOf: (id) => id);
      final config = PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.barnyardChaos));
      host.hostStart(config);
      async.elapse(const Duration(milliseconds: 100));

      guestSession.join();
      async.elapse(const Duration(milliseconds: 600));
      final guest =
          PuttSessionController(session: guestSession, nameOf: (id) => id);
      guest.adoptForTest();
      expect(guest.match, isNotNull,
          reason: 'the guest plays from the host\'s payload');

      // The host goes; the session survives and bob takes the seat.
      hostSession.leave();
      async.elapse(const Duration(milliseconds: 100));
      expect(guestSession.snapshot.sessionId, isNotEmpty,
          reason: 'a player remained, so the session does not die');
      expect(guestSession.isHost, isTrue,
          reason: 'bob is the only one left and takes over');

      host.dispose();
      guest.dispose();
    });
  });
}
