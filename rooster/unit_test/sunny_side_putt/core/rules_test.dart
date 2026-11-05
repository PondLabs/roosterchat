// Headless rules-engine scenarios: simultaneous strokes, hole timer with
// the max(strokes, par + 2) timeout scoring, tick cues and the final
// warning stream, mid-join par crediting, the spectator queue, casual's
// vote-next flow, Barnyard Chaos dealing, snapshot round trips and host
// handoff determinism via the input journal.
library;

import 'dart:convert';

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

PuttConfig rulesConfig({
  GameMode mode = GameMode.casual,
  int seed = 4242,
  int holeTimeLimitSeconds = 120,
  double wobbleMaxRadians = 0,
  PowerUpRegistry? powerUps,
  List<CourseDef>? courses,
  int scoreboardSeconds = 0,
}) {
  final course = courses ??
      [
        CourseDef(id: 'test-course', holes: [
          boxHole(
              id: 'h0',
              par: 2,
              width: 24,
              height: 16,
              tee: const Vec2(4, 8),
              nest: const Nest(Vec2(20, 8), 0.8),
              friction: 4),
          boxHole(
              id: 'h1',
              par: 3,
              width: 24,
              height: 16,
              tee: const Vec2(4, 8),
              nest: const Nest(Vec2(20, 8), 0.8),
              friction: 4),
          boxHole(
              id: 'h2',
              par: 4,
              width: 24,
              height: 16,
              tee: const Vec2(4, 8),
              nest: const Nest(Vec2(20, 6), 0.8),
              friction: 4),
        ]),
      ];
  return PuttConfig(
    mode: mode,
    courses: course,
    seed: seed,
    holeTimeLimitSeconds: holeTimeLimitSeconds,
    wobbleMaxRadians: wobbleMaxRadians,
    powerUps: powerUps,
    catalog: courses == null
        ? {
            'meadow': CourseDef(id: 'meadow', holes: [
              boxHole(
                  id: 'm0',
                  par: 3,
                  width: 24,
                  height: 16,
                  tee: const Vec2(4, 8),
                  nest: const Nest(Vec2(20, 8), 0.8),
                  friction: 4),
              boxHole(
                  id: 'm1',
                  par: 2,
                  width: 24,
                  height: 16,
                  tee: const Vec2(4, 8),
                  nest: const Nest(Vec2(20, 6), 0.8),
                  friction: 4),
            ]),
          }
        : const {},
    scoreboardSeconds: scoreboardSeconds,
  );
}

/// Runs one stroke volley: waits for any kicked eggs to settle, then every
/// egg still in play submits - [golfer] plays a real putt (dead-straight to
/// the nest at capture-gate speed) while everyone else dinks a millimeter
/// AWAY from the nest, so converging putts never collide mid-flight.
/// Returns the events seen.
List<PuttEvent> strokeRound(PuttEngine engine, {String? golfer}) {
  final events = <PuttEvent>[];
  var settleGuard = 0;
  while (settleGuard < 7200 &&
      engine.phase == PuttPhase.holePlay &&
      !engine.world!.allSettled) {
    settleGuard++;
    engine.tickForward();
    events.addAll(engine.drainEvents());
  }
  for (final p in engine.players) {
    if (p.spectator || p.leftMidHole) continue;
    final ball = engine.world?.ball(p.id);
    if (ball == null || ball.holed) continue;
    if (golfer != null && p.id != golfer) {
      final away = (ball.position - engine.currentHole!.nest.position).angle;
      expect(engine.submitShot(p.id, away, 0.02), isTrue);
      continue;
    }
    final (angle, power) = puttFor(engine.currentHole!, ball.position);
    expect(engine.submitShot(p.id, angle, power), isTrue,
        reason: '$p should be able to putt now');
  }
  events.addAll(engine.drainEvents());
  var guard = 0;
  while (guard < 7200) {
    guard++;
    engine.tickForward();
    events.addAll(engine.drainEvents());
    if (engine.phase != PuttPhase.holePlay) break;
    if (engine.world!.allSettled) break; // this stroke volley is over
  }
  return events;
}

/// Plays the current hole out, one real putter per volley, returning every
/// event seen along the way.
List<PuttEvent> playHoleOut(PuttEngine engine) {
  final events = <PuttEvent>[];
  var guard = 0;
  while (engine.phase == PuttPhase.holePlay && guard < 40) {
    guard++;
    String? golfer;
    for (final p in engine.players) {
      final ball = engine.world?.ball(p.id);
      if (p.spectator || p.leftMidHole || ball == null || ball.holed) {
        continue;
      }
      golfer = p.id;
      break;
    }
    if (golfer == null) break;
    events.addAll(strokeRound(engine, golfer: golfer));
  }
  return events;
}

void main() {
  group('putting', () {
    test('strokes fire simultaneously for everyone who submitted', () {
      final engine = PuttEngine(rulesConfig());
      engine.join('p1');
      engine.join('p2');
      engine.join('p3');
      expect(engine.start(), isTrue);
      engine.drainEvents();

      // No turn order: p1 fires the moment they submit.
      final (_, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
      expect(engine.submitShot('p1', 0, power), isTrue);
      expect(engine.strokesInHole('p1'), 1);
      expect(engine.world!.ball('p1')!.asleep, isFalse); // rolling

      // While p1's egg is still rolling, p2 and p3 fire theirs too: three
      // balls in motion at once, nobody waiting on anybody.
      final (a2, p2power) =
          puttFor(engine.currentHole!, engine.world!.ball('p2')!.position);
      expect(engine.submitShot('p2', a2, p2power), isTrue);
      final (a3, p3power) =
          puttFor(engine.currentHole!, engine.world!.ball('p3')!.position);
      expect(engine.submitShot('p3', a3, p3power), isTrue);
      expect(engine.world!.balls.map((b) => b.asleep), everyElement(isFalse));

      // Strokes counted once each, in submission (id) order.
      final events = engine.drainEvents();
      final shots = events.whereType<ShotApplied>().toList();
      expect(shots.map((s) => s.playerId), ['p1', 'p2', 'p3']);
      expect(engine.strokesInHole('p1'), 1);

      // No striking a rolling (or holed) egg.
      expect(engine.submitShot('p1', 0, 0.5), isFalse);
    });

    test('a hole plays out until every egg is nested', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      final ended = playHoleOut(engine).whereType<HoleEnded>().single;
      expect(ended.completed, isTrue);
      expect(ended.strokes, {'p1': 1, 'p2': 2});
      expect(ended.terms['p1'], ScoreTerm.holeInOne);
      expect(ended.terms['p2'], ScoreTerm.par);
      expect(engine.phase, PuttPhase.holeScoreboard);
      expect(engine.holeStrokes('p1'), [1]);
    });

    test('the timer expires and scores max(strokes, par + 2)', () {
      // Two players on a par 2 hole. One takes 7 hops-in-place strokes
      // (above par + 2 = 4), the other never strokes (0 -> 4).
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 8));
      engine.join('busy');
      engine.join('idle');
      engine.start();
      engine.drainEvents();
      for (var i = 0; i < 7 && engine.phase == PuttPhase.holePlay; i++) {
        expect(engine.submitShot('busy', 0, 0.03), isTrue);
        engine.advanceSeconds(0.25);
      }
      expect(engine.strokesInHole('busy'), 7);
      engine.advanceSeconds(8); // out of time

      final events = engine.drainEvents();
      final ended = events.whereType<HoleEnded>().single;
      expect(ended.completed, isFalse);
      expect(ended.strokes['busy'], 7); // strokes ABOVE par + 2 win out
      expect(ended.strokes['idle'], 4); // par + 2 floor for a benchwarmer
      expect(ended.terms['idle'], ScoreTerm.doubleBogey);
      expect(engine.phase, PuttPhase.holeScoreboard);
    });

    test('the timer fires nothing when the hole completes first', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.start();
      engine.advanceSeconds(10); // half the clock gone
      final events = strokeRound(engine);
      expect(events.whereType<HoleEnded>().single.completed, isTrue);
      expect(events.whereType<TimerCue>(), isEmpty); // 30/15/5 never hit
    });

    test('tick cues at 60/30/15/5 and the per-second stream in the last 15',
        () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 17));
      engine.join('p1');
      engine.start();
      engine.advanceSeconds(17.1);
      final events = engine.drainEvents();
      final cues =
          events.whereType<TimerCue>().map((c) => c.remainingSeconds).toSet();
      expect(cues, {15, 5}); // 60 and 30 are beyond this hole's clock
      final stream =
          events.whereType<TimerTick>().map((c) => c.remainingSeconds).toSet();
      expect(stream, {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1});
      expect(events.whereType<HoleEnded>().single.completed, isFalse);
    });

    test('a shot fires exactly where it was aimed', () {
      ShotApplied run() {
        final engine = PuttEngine(rulesConfig(
            seed: 31337, wobbleMaxRadians: 0.05, holeTimeLimitSeconds: 30));
        engine.join('p1');
        engine.start();
        final (angle, power) =
            puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
        expect(engine.submitShot('p1', angle, power), isTrue); // fires at once
        return engine.drainEvents().whereType<ShotApplied>().single;
      }

      final first = run();
      final second = run();
      expect(second.actualAngle, first.actualAngle);
      // The sway is the view's, drawn on the arrow and in the angle sent.
      expect(first.actualAngle, first.aimedAngle);
    });
  });

  group('reactions', () {
    test('a known reaction from someone in the match is an event', () {
      final engine = PuttEngine(rulesConfig());
      engine.join('p1');
      engine.start();
      engine.drainEvents();
      expect(engine.react('p1', 'fire'), isTrue);
      final events = engine.drainEvents().whereType<PlayerReacted>().toList();
      expect(events.single.playerId, 'p1');
      expect(events.single.reaction, 'fire');
      // Nothing in the game changed.
      expect(engine.strokesInHole('p1'), 0);
    });

    test('unknown reactions and strangers are refused', () {
      final engine = PuttEngine(rulesConfig());
      engine.join('p1');
      engine.start();
      expect(engine.react('p1', 'boo'), isFalse);
      expect(engine.react('nobody', 'cheer'), isFalse);
    });

    test('a reaction rides the journal and the wire', () {
      const input = ReactInput(playerId: 'p1', reaction: 'gg');
      final back = EngineInput.fromJson(input.toJson());
      expect(back, isA<ReactInput>());
      expect((back as ReactInput).playerId, 'p1');
      expect(back.reaction, 'gg');
    });
  });

  group('the results pause', () {
    PuttEngine endedHole({int scoreboardSeconds = 3}) {
      final engine = PuttEngine(rulesConfig(
          holeTimeLimitSeconds: 2, scoreboardSeconds: scoreboardSeconds));
      engine.join('p1');
      engine.start();
      engine.advanceSeconds(2.1); // the clock runs out
      expect(engine.phase, PuttPhase.holeScoreboard);
      return engine;
    }

    test('moves on by itself when the config says so', () {
      final engine = endedHole();
      // The hole ended a tenth of a second before the clock stopped.
      expect(engine.scoreboardSecondsLeft, inInclusiveRange(2.85, 3.0));
      engine.advanceSeconds(2.4);
      expect(engine.phase, PuttPhase.holeScoreboard);
      engine.advanceSeconds(0.6);
      expect(engine.phase, PuttPhase.holePlay);
      expect(engine.currentHole!.id, 'h1');
    });

    test('a Continue first moves on at once, and only once', () {
      final engine = endedHole();
      expect(engine.advance(), isTrue);
      expect(engine.currentHole!.id, 'h1');
      // Past where the pause would have run out, within h1's own clock.
      engine.advanceSeconds(1.5);
      expect(engine.phase, PuttPhase.holePlay);
      expect(engine.currentHole!.id, 'h1');
    });

    test('waits for a Continue by default', () {
      final engine = endedHole(scoreboardSeconds: 0);
      engine.advanceSeconds(30);
      expect(engine.phase, PuttPhase.holeScoreboard);
      expect(engine.scoreboardSecondsLeft, 0);
    });

    test('its countdown rides a snapshot', () {
      final engine = endedHole();
      engine.advanceSeconds(1);
      final copy = PuttEngine.fromJson(engine.toJson(), config: engine.config);
      expect(copy.scoreboardSecondsLeft,
          closeTo(engine.scoreboardSecondsLeft, 1e-9));
      copy.advanceSeconds(2.1);
      expect(copy.phase, PuttPhase.holePlay);
    });
  });

  group('joining and leaving', () {
    test('a mid-game join plays the current hole; missed holes score par', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      strokeRound(engine); // hole 0 done
      expect(engine.advance(), isTrue); // onto hole 1
      expect(engine.currentHole!.id, 'h1');

      engine.join('p3'); // mid-game, straight onto the tee
      expect(engine.phase, PuttPhase.holePlay);
      expect(engine.world!.ball('p3'), isNotNull);
      expect(engine.holeStrokes('p3'), [2, null]); // missed hole 0: its par
      expect(engine.holeStrokes('p1'), [1, null]); // p1's real strokes stay

      strokeRound(engine, golfer: 'p3'); // the newcomer holes in one
      playHoleOut(engine); // then the others finish
      expect(engine.holeStrokes('p3'), [2, 1]);
      // Totals: p3 carries the credited par.
      expect(engine.totals['p3'], 3);
    });

    test('the 9th player queues as spectator and gets promoted on a free slot',
        () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      for (var i = 1; i <= 8; i++) {
        expect(engine.join('p$i'), isTrue);
      }
      expect(engine.join('p9'), isTrue);
      expect(engine.isSpectator('p9'), isTrue);
      engine.start();
      expect(engine.world!.ball('p9'), isNull); // watching beside the green

      expect(engine.leave('p4'), isTrue);
      expect(engine.world!.ball('p4'), isNull); // removed mid-hole
      // Still a spectator this hole; promotion happens from the next tee.
      expect(engine.isSpectator('p9'), isTrue);
      engine.advanceSeconds(30);
      expect(engine.phase, PuttPhase.holeScoreboard);
      // p4 left mid-hole: benchwarmer scoring, like any timeout.
      expect(engine.holeStrokes('p4'), [4]);

      engine.advance(); // next hole
      expect(engine.isSpectator('p9'), isFalse);
      expect(engine.world!.ball('p9'), isNotNull);
      expect(engine.holeStrokes('p9'), [2, null]); // credited hole 0's par
    });

    test('leaving mid-hole and rejoining the same hole restores the egg', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      // Round 1: p1 dinks (keeps a stroke on the books), p2 sinks.
      engine.submitShot('p1', 0, 0.03);
      final (angle2, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p2')!.position);
      engine.submitShot('p2', angle2, power);
      engine.advanceSeconds(3.5); // the putt needs ~2.5 s to cross the green
      expect(engine.strokesInHole('p1'), 1);
      expect(engine.world!.ball('p2')!.holed, isTrue);
      expect(engine.leave('p1'), isTrue);
      expect(engine.world!.ball('p1'), isNull);
      engine.join('p1'); // back on
      expect(engine.world!.ball('p1'), isNotNull);
      expect(engine.strokesInHole('p1'), 1); // strokes kept across the exit
      strokeRound(engine); // p1 putts in
      expect(engine.holeStrokes('p1'), [2]);
      expect(engine.holeStrokes('p2'), [1]);
    });
  });

  group('modes', () {
    test('a match can open mid-course (the demo, practice)', () {
      final base = rulesConfig();
      final engine = PuttEngine(PuttConfig(
        mode: base.mode,
        courses: base.courses,
        seed: base.seed,
        startHoleIndex: 2,
      ));
      engine.join('p1');
      engine.start();
      expect(engine.phase, PuttPhase.holePlay);
      expect(engine.currentHole!.id, 'h2', reason: 'the third hole first');
      playHoleOut(engine);
      expect(engine.advance(), isTrue);
      expect(engine.phase, PuttPhase.awaitingNextCourse,
          reason: 'the course ends after its last hole as usual');
    });

    test('casual: scoreboard then a vote for the next course', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.start();
      playHoleOut(engine); // hole 0
      expect(engine.advance(), isTrue); // hole 1
      playHoleOut(engine); // hole 1
      expect(engine.advance(), isTrue); // hole 2
      playHoleOut(engine); // hole 2
      expect(engine.advance(), isTrue); // course over
      expect(engine.phase, PuttPhase.awaitingNextCourse);
      engine.player('p1')!.inventory.add('test/coffee'); // carried over
      expect(engine.startCourse('meadow'), isTrue);
      expect(engine.phase, PuttPhase.holePlay);
      expect(engine.currentCourse!.id, 'meadow');
      expect(engine.currentHole!.id, 'm0');
      playHoleOut(engine);
      // Scores accumulate across courses; the held power-up survives.
      expect(engine.holeStrokes('p1').length, 4);
      expect(engine.player('p1')!.inventory.contains('test/coffee'), isTrue);
    });

    test('tournament: courses run their full list, then the match ends', () {
      final config = rulesConfig(
        mode: GameMode.tournament,
        holeTimeLimitSeconds: 30,
        courses: [
          CourseDef(id: 'c0', holes: [
            boxHole(
                id: 'a0',
                par: 2,
                width: 24,
                height: 16,
                tee: const Vec2(4, 8),
                nest: const Nest(Vec2(20, 8), 0.8),
                friction: 4),
          ]),
          CourseDef(id: 'c1', holes: [
            boxHole(
                id: 'b0',
                par: 3,
                width: 24,
                height: 16,
                tee: const Vec2(4, 8),
                nest: const Nest(Vec2(20, 8), 0.8),
                friction: 4),
          ]),
        ],
      );
      final engine = PuttEngine(config);
      engine.join('p1');
      engine.start();
      playHoleOut(engine);
      expect(engine.advance(), isTrue); // next COURSE, not awaiting votes
      expect(engine.currentCourse!.id, 'c1');
      playHoleOut(engine);
      engine.advance();
      expect(engine.phase, PuttPhase.matchOver);
      expect(engine.totals['p1'], 2); // a hole-in-one on each course
    });

    test('barnyard chaos deals two power-ups to everyone', () {
      final engine = PuttEngine(
          rulesConfig(mode: GameMode.barnyardChaos, powerUps: testRegistry()));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      final events = engine.drainEvents();
      final picks = events.whereType<PowerUpPicked>().toList();
      expect(picks.length, 4); // 2 players x 2 deals
      for (final p in ['p1', 'p2']) {
        expect(engine.player(p)!.inventory.length, 2);
      }
    });
  });

  group('snapshots and handoff', () {
    test('a snapshot round-trips through JSON exactly', () {
      final engine = PuttEngine(
          rulesConfig(holeTimeLimitSeconds: 30, powerUps: testRegistry()));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      playHoleOut(engine);
      engine.advance(); // onto hole 1
      engine.join('p3');
      engine.player('p1')!.inventory.add('test/storm');
      expect(
          engine.usePowerUp('p1', 'test/storm'), isTrue); // blasts the others
      var guard = 0;
      while (guard < 600 && !engine.world!.allSettled) {
        guard++;
        engine.tickForward();
        engine.drainEvents();
      }

      final before = engine.toJson();
      final json = jsonDecode(jsonEncode(before)) as Map<String, Object?>;
      final rebuilt = PuttEngine.fromJson(json, config: engine.config);
      expect(rebuilt.toJson(), before);
      // Still LIVE: the rebuilt engine plays on.
      strokeRound(rebuilt, golfer: 'p3'); // the newcomer holes in one
      playHoleOut(rebuilt);
      expect(rebuilt.holeStrokes('p3'), [2, 1]);
    });

    test('host handoff: snapshot + journal replay equals the original', () {
      final engine = PuttEngine(
          rulesConfig(holeTimeLimitSeconds: 30, powerUps: testRegistry()));
      engine.join('p1');
      engine.join('p2');
      engine.join('p3');
      engine.start();
      playHoleOut(engine);
      // Load up BEFORE the snapshot: the snapshot must carry the bags.
      engine.player('p2')!.inventory.add('test/storm');
      engine.player('p1')!.inventory.add('test/shell');
      final snapshotSeq = engine.lastSeq;
      final snapshot = engine.toJson();

      // Life continues on the original host - journalled inputs only.
      expect(engine.advance(), isTrue); // onto hole 1
      engine.join('p4'); // mid-game join
      expect(engine.usePowerUp('p2', 'test/storm'), isTrue);
      expect(engine.usePowerUp('p1', 'test/shell'), isTrue);
      playHoleOut(engine);
      final journal =
          engine.journalSince(snapshotSeq).map((e) => e.toJson()).toList();
      expect(journal, isNotEmpty);

      // A second host rebuilds from the snapshot and replays the journal.
      final handoff = PuttEngine.replay(
        jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>,
        [
          for (final e in journal)
            jsonDecode(jsonEncode(e)) as Map<String, Object?>
        ],
        config: engine.config,
        untilTick: engine.tick,
      );
      expect(handoff.tick, engine.tick);
      expect(handoff.toJson(), engine.toJson());
      expect(
        handoff.players.map((p) => p.id),
        engine.players.map((p) => p.id),
      );
    });

    test('handoff mid-simulation (a ball mid-flight)', () {
      final engine = PuttEngine(rulesConfig(holeTimeLimitSeconds: 30));
      engine.join('p1');
      engine.join('p2');
      engine.start();
      final (_, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p2')!.position);
      expect(engine.submitShot('p1', 0, power), isTrue);
      expect(engine.submitShot('p2', 0, power * 0.8), isTrue);
      for (var i = 0; i < 23; i++) {
        engine.tickForward(); // balls rolling when the snapshot happens
      }
      final snapshotSeq = engine.lastSeq;
      final snapshot = engine.toJson();
      final journal =
          engine.journalSince(snapshotSeq).map((e) => e.toJson()).toList();
      for (var i = 0; i < 40; i++) {
        engine.tickForward();
      }
      final handoff = PuttEngine.replay(
          jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>, journal,
          config: engine.config, untilTick: engine.tick);
      expect(handoff.toJson(), engine.toJson());
    });
  });
}
