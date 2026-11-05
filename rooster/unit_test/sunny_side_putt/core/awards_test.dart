// A course's awards: the engine tallies, per player and per course, the
// knocks they dealt, their longest kicker flight, their holes in one, the
// power-ups they stole, the casts their shell stopped and their dunks,
// from its own events, so a replay and a snapshot agree; the awards go to
// whoever did the most (a tie to the better card) and only when earned;
// the course's last hole's results give way to its awards before the
// match moves on.
library;

import 'dart:convert';

import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

HoleDef _plain(String id) => boxHole(
    id: id,
    par: 2,
    width: 24,
    height: 16,
    tee: const Vec2(4, 8),
    nest: const Nest(Vec2(20, 8), 0.8),
    friction: 4);

/// A long field with a kicker across its middle (foot at x 7, lip at x 9),
/// throwing east, the nest far off in a corner.
HoleDef _kickerField(String id) => boxHole(
      id: id,
      width: 40,
      height: 12,
      tee: const Vec2(3, 6),
      nest: const Nest(Vec2(37, 10.5), 0.8),
      kickers: const [Kicker(Vec2(7, 6), Vec2(9, 6), width: 3)],
    );

PuttConfig _config({
  List<CourseDef>? courses,
  GameMode mode = GameMode.casual,
  int scoreboardSeconds = 0,
  PowerUpRegistry? powerUps,
}) {
  final played = courses ??
      [
        CourseDef(id: 'c0', holes: [_plain('h0'), _plain('h1')]),
      ];
  return PuttConfig(
    mode: mode,
    courses: played,
    catalog: {for (final course in played) course.id: course},
    seed: 77,
    holeTimeLimitSeconds: 30,
    wobbleMaxRadians: 0,
    scoreboardSeconds: scoreboardSeconds,
    powerUps: powerUps,
  );
}

/// The twelve real power-ups, as a session registers them.
PowerUpRegistry _launchPowerUps() {
  final registry = PowerUpRegistry();
  registerBuiltinEffects(registry);
  return registry;
}

PuttEngine _started(PuttConfig config, List<String> ids) {
  final engine = PuttEngine(config);
  for (final id in ids) {
    engine.join(id);
  }
  engine.start();
  engine.drainEvents();
  return engine;
}

/// Ticks until every egg rests (or the hole ends).
void _settle(PuttEngine engine) {
  for (var i = 0; i < 7200; i++) {
    engine.tickForward();
    engine.drainWorldEvents();
    if (engine.phase != PuttPhase.holePlay) return;
    if (engine.world!.allSettled) return;
  }
}

/// Everyone still out putts straight for the nest until the hole ends.
void _playOut(PuttEngine engine) {
  for (var round = 0;
      round < 12 && engine.phase == PuttPhase.holePlay;
      round++) {
    for (final player in engine.players) {
      final ball = engine.world!.ball(player.id);
      if (ball == null || ball.holed || !ball.asleep) continue;
      final (angle, power) = puttFor(engine.currentHole!, ball.position);
      engine.submitShot(player.id, angle, power);
    }
    _settle(engine);
  }
  // Time runs out on anyone left.
  while (engine.phase == PuttPhase.holePlay) {
    engine.tickForward();
  }
}

void main() {
  group('the tally', () {
    test('counts knocks for the egg that rolled into the other', () {
      final tally = PuttCourseTally()
        ..seeWorld(
            const BallKnocked(playerId: 'b', byPlayerId: 'a', impactSpeed: 3))
        ..seeWorld(
            const BallKnocked(playerId: 'c', byPlayerId: 'a', impactSpeed: 2))
        ..seeWorld(
            const BallKnocked(playerId: 'a', byPlayerId: 'b', impactSpeed: 2));
      expect(tally.of('a').knocks, 2);
      expect(tally.of('b').knocks, 1);
      expect(tally.of('c').knocks, 0);
    });

    test('a flight runs from takeoff to the first touchdown', () {
      final tally = PuttCourseTally()
        ..seeWorld(const BallLaunched(playerId: 'a', at: Vec2(9, 6), speed: 7))
        ..seeWorld(
            const BallLanded(playerId: 'a', at: Vec2(17, 6), impactSpeed: 6))
        // The hop after a hard landing is no second flight.
        ..seeWorld(
            const BallLanded(playerId: 'a', at: Vec2(19, 6), impactSpeed: 2))
        ..seeWorld(const BallLaunched(playerId: 'a', at: Vec2(9, 6), speed: 5))
        ..seeWorld(
            const BallLanded(playerId: 'a', at: Vec2(12, 10), impactSpeed: 4));
      expect(tally.of('a').longestFlight, closeTo(8, 1e-9),
          reason: 'the longer of 8 and 5');
    });

    test('an egg that splashes in flight has flown nowhere, and is dunked', () {
      final tally = PuttCourseTally()
        ..seeWorld(const BallLaunched(playerId: 'a', at: Vec2(9, 6), speed: 7))
        ..seeWorld(const BallSplashed(playerId: 'a', at: Vec2(3, 6)))
        ..seeWorld(
            const BallLanded(playerId: 'a', at: Vec2(30, 6), impactSpeed: 6))
        ..seeWorld(const BallOutOfBounds(playerId: 'a', at: Vec2(3, 6)))
        ..seeWorld(const BallSwallowed(playerId: 'a', at: Vec2(3, 6)));
      expect(tally.of('a').longestFlight, 0);
      expect(tally.of('a').dunks, 3);
    });

    test('holes in one, thefts and shields', () {
      final tally = PuttCourseTally()
        ..holed('a', 1)
        ..holed('a', 3)
        ..holed('b', 1)
        ..holed('b', 1)
        ..stole('c')
        ..blocked('d');
      expect(tally.of('a').holesInOne, 1);
      expect(tally.of('b').holesInOne, 2);
      expect(tally.of('c').steals, 1);
      expect(tally.of('d').blocks, 1);
    });

    test('round-trips, an egg in the air included', () {
      final tally = PuttCourseTally()
        ..seeWorld(
            const BallKnocked(playerId: 'b', byPlayerId: 'a', impactSpeed: 3))
        ..seeWorld(const BallLaunched(playerId: 'b', at: Vec2(9, 6), speed: 7));
      final json = jsonDecode(jsonEncode(tally.toJson()));
      final restored = PuttCourseTally()..restore(json);
      expect(restored.toJson(), tally.toJson());
      restored.seeWorld(
          const BallLanded(playerId: 'b', at: Vec2(15, 6), impactSpeed: 1));
      expect(restored.of('b').longestFlight, closeTo(6, 1e-9),
          reason: 'the takeoff rode the snapshot');
      // A snapshot from before the tally: a course with nothing done.
      expect((PuttCourseTally()..restore(null)).all, isEmpty);
    });
  });

  group('the awards', () {
    PuttCourseStats stats(
            {int knocks = 0,
            double flight = 0,
            int aces = 0,
            int steals = 0,
            int blocks = 0,
            int dunks = 0}) =>
        PuttCourseStats()
          ..knocks = knocks
          ..longestFlight = flight
          ..holesInOne = aces
          ..steals = steals
          ..blocks = blocks
          ..dunks = dunks;

    test('go to whoever did the most, only when someone did', () {
      final awards = puttCourseAwards({
        'a': stats(knocks: 1, flight: 4),
        'b': stats(knocks: 3),
        'c': stats(flight: 9.5),
      }, standing: const [
        'a',
        'b',
        'c'
      ]);
      expect(awards, const [
        PuttAward(kind: PuttAwardKind.bowlingBall, playerId: 'b', figure: 3),
        PuttAward(kind: PuttAwardKind.highFlyer, playerId: 'c', figure: 9.5),
      ]);
      expect(puttCourseAwards({}, standing: const ['a']), isEmpty);
      expect(puttCourseAwards({'a': stats()}, standing: const ['a']), isEmpty,
          reason: 'nothing earned, no "nobody" line');
    });

    test('a tie goes to the better card', () {
      final awards = puttCourseAwards({
        'a': stats(steals: 2),
        'b': stats(steals: 2),
      }, standing: const [
        'b',
        'a'
      ]);
      expect(awards.single.playerId, 'b');
    });

    test('four at most, in the card\'s order', () {
      final awards = puttCourseAwards({
        'a': stats(
            knocks: 1, flight: 2, aces: 1, steals: 1, blocks: 1, dunks: 1),
      }, standing: const [
        'a'
      ]);
      expect(awards.map((a) => a.kind), const [
        PuttAwardKind.ace,
        PuttAwardKind.bowlingBall,
        PuttAwardKind.highFlyer,
        PuttAwardKind.stickyFingers,
      ]);
    });

    test('only for players who can win one (no spectators)', () {
      final awards =
          puttCourseAwards({'watcher': stats(knocks: 5)}, standing: const []);
      expect(awards, isEmpty);
    });
  });

  group('the engine', () {
    test('a hole in one counts', () {
      final engine = _started(_config(), ['p1']);
      final ball = engine.world!.ball('p1')!;
      final (angle, power) = puttFor(engine.currentHole!, ball.position);
      engine.submitShot('p1', angle, power);
      _settle(engine);
      expect(engine.holeStrokes('p1'), [1]);
      expect(engine.courseTally.of('p1').holesInOne, 1);
    });

    test('an egg rolled into a resting one is a knock for the roller', () {
      final engine = _started(_config(), ['p1', 'p2']);
      // p2 dinks off the tee and rests; p1 rolls straight into it.
      engine.submitShot('p2', 1.2, 0.12);
      _settle(engine);
      final from = engine.world!.ball('p1')!.position;
      final target = engine.world!.ball('p2')!.position;
      engine.submitShot('p1', (target - from).angle, 0.5);
      _settle(engine);
      expect(engine.courseTally.of('p1').knocks, 1);
      expect(engine.courseTally.of('p2').knocks, 0);
    });

    test('a kicker flight is measured from the lip to the landing', () {
      final engine = _started(
          _config(courses: [
            CourseDef(id: 'k', holes: [_kickerField('k0')])
          ]),
          ['p1']);
      engine.submitShot('p1', 0, 0.6);
      Vec2? takeoff;
      Vec2? landing;
      for (var i = 0; i < 2400 && landing == null; i++) {
        engine.tickForward();
        for (final event in engine.drainWorldEvents()) {
          if (event is BallLaunched) takeoff = event.at;
          if (event is BallLanded && takeoff != null) landing ??= event.at;
        }
      }
      expect(takeoff, isNotNull);
      expect(landing, isNotNull);
      expect(engine.courseTally.of('p1').longestFlight,
          closeTo((landing! - takeoff!).length, 1e-9));
      expect(engine.courseTally.of('p1').longestFlight, greaterThan(2));
    });

    test('a Thieving Crow theft and a Thick Shell block count', () {
      final engine =
          _started(_config(powerUps: _launchPowerUps()), ['p1', 'p2', 'p3']);
      engine.player('p2')!.inventory.add('hawk_eye');
      engine.player('p1')!.inventory.add('thieving_crow');
      expect(
          engine.usePowerUp(
              'p1', 'thieving_crow', const PowerUpTarget.player('p2')),
          isTrue);
      expect(engine.courseTally.of('p1').steals, 1);
      // p3's shell holds against the next crow.
      engine.player('p3')!.inventory
        ..add('thick_shell')
        ..add('gust');
      engine.usePowerUp('p3', 'thick_shell');
      engine.player('p1')!.inventory.add('thieving_crow');
      engine.usePowerUp(
          'p1', 'thieving_crow', const PowerUpTarget.player('p3'));
      expect(engine.courseTally.of('p3').blocks, 1);
      expect(engine.courseTally.of('p1').steals, 1, reason: 'blocked');
    });

    test('the tally runs over the whole course and starts again with the next',
        () {
      final engine = _started(_config(), ['p1']);
      for (var hole = 0; hole < 2; hole++) {
        final ball = engine.world!.ball('p1')!;
        final (angle, power) = puttFor(engine.currentHole!, ball.position);
        engine.submitShot('p1', angle, power);
        _settle(engine);
        expect(engine.phase, PuttPhase.holeScoreboard);
        expect(engine.courseAwardsUp, isFalse,
            reason: "the hole's own results first");
        engine.advance();
      }
      // The second hole's results, then its Continue: the course's awards.
      expect(engine.courseAwardsUp, isTrue);
      expect(engine.drainEvents().whereType<CourseAwardsShown>(), hasLength(1));
      expect(engine.courseTally.of('p1').holesInOne, 2);
      engine.advance();
      expect(engine.phase, PuttPhase.awaitingNextCourse);
      expect(engine.courseTally.of('p1').holesInOne, 2,
          reason: 'still the last course\'s while the vote runs');
      engine.startCourse('c0');
      expect(engine.courseTally.all, isEmpty, reason: 'a new course');
    });

    test('the awards keep a pause of their own, then the match moves on', () {
      final engine = _started(
          _config(scoreboardSeconds: 2, courses: [
            CourseDef(id: 'one', holes: [_plain('o0')])
          ]),
          ['p1']);
      _playOut(engine);
      expect(engine.phase, PuttPhase.holeScoreboard);
      engine.advanceSeconds(2.01);
      expect(engine.courseAwardsUp, isTrue);
      expect(engine.scoreboardSecondsLeft, closeTo(2, 0.02),
          reason: 'the pause starts over for the awards');
      engine.advanceSeconds(2.01);
      expect(engine.phase, PuttPhase.awaitingNextCourse);
    });

    test('a tournament shows each course its awards, the last before the end',
        () {
      final engine = _started(
          _config(mode: GameMode.tournament, courses: [
            CourseDef(id: 'a', holes: [_plain('a0')]),
            CourseDef(id: 'b', holes: [_plain('b0')]),
          ]),
          ['p1']);
      _playOut(engine);
      engine.advance();
      expect(engine.courseAwardsUp, isTrue);
      engine.advance();
      expect(engine.currentCourse!.id, 'b');
      expect(engine.courseTally.all, isEmpty);
      _playOut(engine);
      engine.advance();
      expect(engine.courseAwardsUp, isTrue);
      engine.advance();
      expect(engine.phase, PuttPhase.matchOver);
      expect(engine.courseAwardsUp, isFalse);
    });

    test('the tally and the awards ride the snapshot and the journal', () {
      final config = _config(courses: [
        CourseDef(id: 'k', holes: [_kickerField('k0')])
      ]);
      final engine = _started(config, ['p1', 'p2']);
      final snapshot =
          jsonDecode(jsonEncode(engine.toJson())) as Map<String, Object?>;
      final seq = engine.lastSeq;
      engine.submitShot('p1', 0, 0.6);
      engine.submitShot('p2', 0.3, 0.12);
      for (var i = 0; i < 900; i++) {
        engine.tickForward();
      }
      final journal = [
        for (final entry in engine.journalSince(seq)) entry.toJson(),
      ];
      final replayed = PuttEngine.replay(snapshot, journal,
          config: config, untilTick: engine.tick);
      expect(jsonEncode(replayed.toJson()), jsonEncode(engine.toJson()));
      expect(engine.courseTally.of('p1').longestFlight, greaterThan(0));

      // And the awards' stage itself.
      _playOut(engine);
      engine.advance();
      expect(engine.courseAwardsUp, isTrue);
      final restored = PuttEngine.fromJson(
          jsonDecode(jsonEncode(engine.toJson())) as Map<String, Object?>,
          config: config);
      expect(restored.courseAwardsUp, isTrue);
      expect(restored.courseTally.of('p1').longestFlight,
          engine.courseTally.of('p1').longestFlight);
    });
  });
}
