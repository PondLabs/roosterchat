// The live-session bridge: two clients over the in-memory transport —
// the launch, the guest's adoption of the host's match, a guest's shot
// landing on the host's engine, a guest's look reaching everyone, and the
// host leaving handing the seat over instead of ending the game. Timers
// run on fake async; the wire's hops settle inside `elapse`.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/config/preferences/preference.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_launch_options.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

CallActivity get _descriptor => CallActivity(
      id: 'chat.commet.putt',
      displayName: () => 'Sunny Side Putt',
      maxPlayers: 8,
    );

void main() {
  test('the host launches, the guest adopts, a guest shot lands twice', () {
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

  test('a guest on another version of the game does not play it', () {
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
      host.hostStart(PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual)));
      async.elapse(const Duration(milliseconds: 100));
      final payload = hostSession.snapshot.game;
      final config = payload['config']! as Map;
      expect(config['physics'], puttPhysicsVersion);

      final guest =
          PuttSessionController(session: guestSession, nameOf: (id) => id);
      Map<String, Object?> sent(Map<String, Object?> change) => {
            ...payload,
            'config': {...config, ...change},
          };
      for (final skew in [
        sent({'physics': puttPhysicsVersion + 1}),
        sent({'physics': null}), // an older host's, before versions
        sent({'courseHash': -1}),
      ]) {
        hostSession.hostGamePayload(skew);
        hostSession.sendState();
        async.elapse(const Duration(milliseconds: 100));
        guest.adoptForTest();
        expect(guest.match, isNull, reason: '$skew');
        expect(guest.outdated, isTrue);
      }
      // Who should update: a newer host's game (or the same version with
      // other courses) is ours to catch up with; an older host's is not.
      expect(guest.hostOutdated, isFalse);
      hostSession.hostGamePayload(sent({'physics': null}));
      hostSession.sendState();
      async.elapse(const Duration(milliseconds: 100));
      guest.adoptForTest();
      expect(guest.hostOutdated, isTrue, reason: 'an older host');

      // The host's own payload again: the guest plays.
      hostSession.hostGamePayload(payload);
      hostSession.sendState();
      async.elapse(const Duration(milliseconds: 100));
      guest.adoptForTest();
      expect(guest.match, isNotNull);
      expect(guest.outdated, isFalse);

      host.dispose();
      guest.dispose();
    });
  });

  test('a guest wears its saved look into the match, and everyone sees it',
      () async {
    // Both clients share this process's preferences: the host wears the
    // saved look from its launch, the guest from the moment it is seated.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'putt_egg_look': 'hearts/daisy'});
    Preference.preferences = await SharedPreferences.getInstance();
    addTearDown(() => Preference.preferences = null);
    const saved = PuttLook(pattern: EggPattern.hearts, hat: HatchlingHat.daisy);
    const crown = PuttLook(pattern: EggPattern.stars, hat: HatchlingHat.crown);
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
      host.hostStart(PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual)));
      async.elapse(const Duration(milliseconds: 100));
      expect(host.match!.engine.player('alice')!.look, saved,
          reason: 'the host joins its own match in its look');

      final guest =
          PuttSessionController(session: guestSession, nameOf: (id) => id);
      guest.adoptForTest();
      expect(guest.match!.engine.player('alice')!.look, saved,
          reason: 'the look rides the host\'s snapshot');
      guestSession.join();
      async.elapse(const Duration(milliseconds: 600));
      host.adoptRosterForTest();
      // The host seats bob knowing no look; its beat relays the seat.
      expect(host.match!.engine.player('bob')!.look, PuttLook.standard);
      async.elapse(const Duration(milliseconds: 600));
      expect(guest.match!.engine.player('bob'), isNotNull);

      // The guest's next frame sees its seat in the wrong look and asks.
      guest.match!.update(0.016);
      async.elapse(const Duration(milliseconds: 200));
      expect(host.match!.engine.player('bob')!.look, saved,
          reason: 'the look reached the host through the session');

      // A pick mid-match: home at once, the host's engine, and back.
      guest.match!.wear(crown);
      expect(guest.match!.engine.player('bob')!.look, crown);
      async.elapse(const Duration(milliseconds: 200));
      expect(host.match!.engine.player('bob')!.look, crown);
      async.elapse(const Duration(milliseconds: 2500));
      expect(guest.match!.engine.player('bob')!.look, crown,
          reason: 'the host\'s snapshots carry it from then on');

      host.dispose();
      guest.dispose();
    });
  });

  test("a host's view built again takes its match back and goes on hosting",
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
      final first =
          PuttSessionController(session: hostSession, nameOf: (id) => id);
      first.hostStart(PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual)));
      async.elapse(const Duration(milliseconds: 100));
      final seed = first.match!.config.seed;
      expect(first.match!.submitShot(0.2, 0.5), isTrue);
      async.elapse(const Duration(milliseconds: 1200));

      // The call's view goes and comes back: its controller with it.
      first.dispose();
      final again =
          PuttSessionController(session: hostSession, nameOf: (id) => id);
      expect(again.match, isNotNull, reason: 'not "Loading" for good');
      expect(again.match!.config.seed, seed, reason: 'the same match');
      expect(again.match!.engine.strokesInHole('alice'), 1,
          reason: 'from where it stood');

      // Still the host: a guest's shot lands on its engine.
      final guest =
          PuttSessionController(session: guestSession, nameOf: (id) => id);
      guestSession.join();
      async.elapse(const Duration(milliseconds: 1200));
      expect(again.match!.engine.players.map((p) => p.id), contains('bob'));
      expect(guest.match, isNotNull);
      expect(guest.match!.submitShot(0.3, 0.6), isTrue);
      async.elapse(const Duration(milliseconds: 300));
      expect(again.match!.engine.strokesInHole('bob'), 1);
      // Its own moves go straight into its own engine, not out to a host.
      expect(again.match!.remoteMove, isNull);

      again.dispose();
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

  test("the guest who takes the host's seat plays into its own engine", () {
    fakeAsync((async) {
      final call = InMemoryActivityCall();
      CallActivitySession seat(String name) => CallActivitySession(
          activity: _descriptor,
          selfUserId: '@$name:example.org',
          transport: call.join(name));
      final aliceSession = seat('alice');
      final bobSession = seat('bob');
      final carolSession = seat('carol');
      final alice =
          PuttSessionController(session: aliceSession, nameOf: (id) => id);
      alice.hostStart(PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual)));
      async.elapse(const Duration(milliseconds: 100));
      final bob =
          PuttSessionController(session: bobSession, nameOf: (id) => id);
      final carol =
          PuttSessionController(session: carolSession, nameOf: (id) => id);
      bobSession.join();
      carolSession.join();
      async.elapse(const Duration(milliseconds: 1200));
      expect(bob.match, isNotNull);
      expect(bob.match!.remoteMove, isNotNull, reason: 'a guest, for now');

      // The host goes; bob (the lowest identity left) takes over.
      aliceSession.leave();
      async.elapse(const Duration(milliseconds: 300));
      expect(bobSession.isHost, isTrue);
      expect(bob.match!.remoteMove, isNull,
          reason: 'its moves no longer go to a host that is itself');

      // Its own reaction (like its vote at "Course done") lands at once,
      // and carol's reaches its engine.
      expect(bob.match!.react('cheer'), isTrue);
      carol.match!.react('gg');
      async.elapse(const Duration(milliseconds: 300));
      bob.match!.drainEvents();
      expect(bob.match!.reactions.map((r) => (r.playerId, r.reaction)),
          containsAll([('bob', 'cheer'), ('carol', 'gg')]));

      alice.dispose();
      bob.dispose();
      carol.dispose();
    });
  });

  test('a client on an older game watches: never seated, never elected', () {
    fakeAsync((async) {
      final call = InMemoryActivityCall();
      CallActivitySession seat(String name) => CallActivitySession(
          activity: _descriptor,
          selfUserId: '@$name:example.org',
          transport: call.join(name));
      final aliceSession = seat('alice');
      final bobSession = seat('bob');
      final carolSession = seat('carol');
      final alice =
          PuttSessionController(session: aliceSession, nameOf: (id) => id);
      alice.hostStart(PuttSessionController.buildConfig(
          const PuttLaunchOptions(mode: GameMode.casual)));
      async.elapse(const Duration(milliseconds: 100));
      final bob = PuttSessionController(
          session: bobSession,
          nameOf: (id) => id,
          physicsVersion: puttPhysicsVersion - 1);
      final carol =
          PuttSessionController(session: carolSession, nameOf: (id) => id);
      bobSession.join();
      carolSession.join();
      async.elapse(const Duration(milliseconds: 1200));

      expect(bob.outdated, isTrue);
      expect(bob.hostOutdated, isFalse, reason: 'bob is the one to update');
      expect(aliceSession.snapshot.players, isNot(contains('bob')));
      expect(aliceSession.snapshot.spectators, contains('bob'));
      expect(
          alice.match!.engine.players.map((p) => p.id), isNot(contains('bob')),
          reason: 'no egg that never putts holds every hole to its timer');

      // The host goes: carol takes over, not bob (who sorts first).
      aliceSession.leave();
      async.elapse(const Duration(milliseconds: 300));
      expect(bobSession.isHost, isFalse);
      expect(carolSession.isHost, isTrue);
      expect(carol.match!.remoteMove, isNull);

      alice.dispose();
      bob.dispose();
      carol.dispose();
    });
  });
}
