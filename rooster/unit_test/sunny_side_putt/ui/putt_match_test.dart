// The local match harness: boots on the stub course, fires strokes, rolls
// eggs, times holes out, and spends the engine's events as notices.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/course_kit.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';

void main() {
  group('boot', () {
    test('the solo match is on hole 1 immediately, no network', () {
      final match = PuttMatch.solo(localPlayerName: 'Tester');
      expect(match.phase, PuttPhase.holePlay);
      expect(match.hole, isNotNull);
      expect(match.hole!.id, 'stub-course-h0');
      expect(match.holeNumber, 1);
      expect(match.myBall, isNotNull);
      expect(match.isSpectator, isFalse);
    });

    test('the boot notices carry the hole-start headline', () {
      final match = PuttMatch.solo();
      // boot() drained: the headline the HUD shows is hole 1's.
      expect(match.headline, isNotNull);
      expect(match.headline, contains('Hole 1'));
    });

    test('eight friends fit on the green; a ninth watches', () {
      final course = CourseDef(id: 'solo-seats', holes: [stubHole(id: 's0')]);
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 5),
        localPlayerId: 'me',
        seatedPlayerIds: [for (var i = 0; i < 8; i++) 'p$i'],
      )..boot();
      expect(match.isSpectator, isTrue);
      expect(match.myBall, isNull,
          reason: 'a spectator has no egg on the green');
      expect(match.myShotReady, isFalse);
    });
  });

  group('reactions', () {
    test('my reaction shows at once on a local match', () {
      final match = PuttMatch.solo();
      expect(match.react('cheer'), isTrue);
      expect(match.reactions.single.playerId, 'me');
      expect(match.reactions.single.reaction, 'cheer');
    });

    test('a reaction from the wire surfaces on the next frame', () {
      final match = PuttMatch.solo();
      match.engine.react('me', 'wow');
      match.update(1 / 60);
      expect(match.reactions.map((r) => r.reaction), contains('wow'));
    });
  });

  group('resets', () {
    test('a fast egg into the pond splashes there and pops up home', () {
      final match = PuttMatch.solo();
      final hole = match.hole!;
      final pond = hole.water.first as WaterCircle;
      final from = match.myBall!.position;
      // Hard at the pond's middle: in and put back within one tick.
      final toward = pond.center - from;
      expect(match.submitShot(toward.angle, 0.9), isTrue);
      final spots = <PuttFxSpot>[];
      for (var frame = 0; frame < 120; frame++) {
        match.update(1 / 60);
        spots.addAll(match.fxSpots);
        match.fxSpots.clear();
      }
      final splash =
          spots.where((spot) => spot.kind == PuttFxSpotKind.splash).toList();
      expect(splash, hasLength(1));
      expect(splash.single.at!.distanceTo(pond.center),
          lessThanOrEqualTo(pond.radius + 0.5));
      final back =
          spots.where((spot) => spot.kind == PuttFxSpotKind.back).toList();
      expect(back.single.at!.distanceTo(from), lessThan(0.5),
          reason: 'it pops up where it was putted from');
    });
  });

  group('strokes', () {
    test('a submitted shot counts a stroke and rolls the egg', () {
      final match = PuttMatch.solo();
      final before = match.myBall!.position;
      expect(match.submitShot(0, 0.6), isTrue);
      expect(match.myStrokesThisHole, 1);
      // Let the world run a second of frames.
      for (var frame = 0; frame < 60; frame++) {
        match.update(1 / 60);
      }
      final after = match.currentPositions['me']!;
      expect(after.distanceTo(before), greaterThan(0.5),
          reason: '60% power for a second moves an egg well over half a '
              'unit');
    });

    test('renderPosition interpolates between the last two ticks', () {
      final match = PuttMatch.solo();
      match.submitShot(0, 0.6);
      match.update(1 / 120); // tick 1: no from-end yet
      match.update(1 / 120); // tick 2: from-end and to-end both real
      match.update(1 / 240); // half a step of accumulation
      final previous = match.previousPositions['me'];
      final current = match.currentPositions['me'];
      expect(previous, isNotNull,
          reason: 'the egg has rolled: every whole tick leaves a from-end');
      expect(current, isNotNull);
      final between = current!.distanceTo(previous!);
      expect(between, greaterThan(1e-6),
          reason: 'a 60% shot keeps rolling between whole ticks');
      final drawn = match.renderPositionOf('me');
      expect(drawn.distanceTo(current), lessThan(between),
          reason: 'the drawn egg sits between the ticks, not past them');
    });

    test('a rolling egg cannot be struck again', () {
      final match = PuttMatch.solo();
      expect(match.submitShot(0, 0.5), isTrue);
      expect(match.myShotReady, isFalse);
      expect(match.submitShot(0, 0.5), isFalse,
          reason: 'the engine rejects shots at a rolling egg');
    });
  });

  group('the hole clock', () {
    test('the timer counts down while the hole plays', () {
      final match = PuttMatch.solo();
      final before = match.secondsRemaining;
      match.update(1.0);
      expect(match.secondsRemaining, lessThan(before));
    });

    test('the short hole times out into the scoreboard with the penalty', () {
      final course = CourseDef(
        id: 'quick',
        holes: [
          stubHole(id: 'q0', par: 2, width: 24, height: 14),
        ],
      );
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 7,
            holeTimeLimitSeconds: 2),
      )..boot();
      match.submitShot(0, 0.2); // a weak stroke that ends on the green
      // Frames, as the game delivers them; the harness clamps each frame
      // to 250 ms of catch-up.
      for (var frame = 0; frame < 40; frame++) {
        match.update(0.3);
      }
      expect(match.phase, PuttPhase.holeScoreboard);
      // No second stroke, no nest: scores max(0, par + 2)? No: strokes
      // taken was 1, so max(1, 4) = 4.
      expect(match.myTotal, 4);
      expect(match.headline, isNotNull);
      final kinds = match.notices.map((n) => n.sfx).toSet();
      expect(kinds, contains(PuttSfx.timerCue),
          reason: 'a warning cue was due in the last seconds');
    });

    test(
        'advancing lands on the next hole; a one-hole course waits on the '
        'vote', () {
      final course = CourseDef(id: 'one-hole', holes: [stubHole(id: 'only')]);
      final catalog = {
        'one-hole': course,
        'other': CourseDef(id: 'other', holes: [stubHole(id: 'o0', par: 3)]),
      };
      final match = PuttMatch(
        config: PuttConfig(
          mode: GameMode.casual,
          courses: [catalog['one-hole']!],
          catalog: catalog,
          seed: 9,
          holeTimeLimitSeconds: 2,
        ),
      )..boot();
      for (var frame = 0; frame < 40; frame++) {
        match.update(0.3); // run the hole out, frame by frame
      }
      expect(match.advance(), isTrue);
      expect(match.phase, PuttPhase.awaitingNextCourse);
      expect(match.startCourse('other'), isTrue);
      expect(match.phase, PuttPhase.holePlay);
      expect(match.hole!.id, 'o0');
    });
  });

  group('the results\' pause', () {
    test('a live session\'s results move on by themselves', () {
      final course = CourseDef(id: 'two', holes: [
        stubHole(id: 't0', par: 2),
        stubHole(id: 't1', par: 3),
      ]);
      final match = PuttMatch(
        config: PuttConfig(
          mode: GameMode.casual,
          courses: [course],
          seed: 13,
          holeTimeLimitSeconds: 2,
          scoreboardSeconds: 8,
        ),
      )..boot();
      for (var frame = 0;
          frame < 40 && match.phase == PuttPhase.holePlay;
          frame++) {
        match.update(0.3); // run the hole out, frame by frame
      }
      expect(match.phase, PuttPhase.holeScoreboard);
      expect(match.engine.scoreboardSecondsLeft, closeTo(8, 0.05));

      // Frames through the pause, as the game delivers them.
      for (var frame = 0; frame < 25; frame++) {
        match.update(0.2);
      }
      expect(match.phase, PuttPhase.holeScoreboard);
      expect(match.engine.scoreboardSecondsLeft, closeTo(3, 0.1));
      for (var frame = 0; frame < 20; frame++) {
        match.update(0.2);
      }
      expect(match.phase, PuttPhase.holePlay, reason: 'on to the next hole');
      expect(match.hole!.id, 't1');
      expect(match.headline, contains('Hole 2'));
    });

    test('without a pause the results wait for Continue', () {
      final course = CourseDef(id: 'two', holes: [
        stubHole(id: 't0', par: 2),
        stubHole(id: 't1', par: 3),
      ]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 13,
            holeTimeLimitSeconds: 2),
      )..boot();
      for (var frame = 0; frame < 60; frame++) {
        match.update(0.3);
      }
      expect(match.phase, PuttPhase.holeScoreboard);
    });
  });

  group('power-ups', () {
    test('an empty inventory has nothing to use', () {
      final match = PuttMatch.solo();
      expect(match.myInventory, isEmpty);
      expect(match.usePowerUp('hawk_eye'), isFalse);
    });

    test('a granted effect is spent by the view and gone after', () {
      final match = PuttMatch.solo();
      // The engine's inventory is public state; the effects ticket wires
      // real grants later. These two are what the view must render.
      match.localPlayer!.inventory
        ..add('hawk_eye')
        ..add('strong_coffee');
      expect(match.myInventory, ['hawk_eye', 'strong_coffee']);
      expect(match.usePowerUp('hawk_eye'), isTrue);
      expect(match.myInventory, ['strong_coffee']);
      expect(match.myNextShotSteady, isFalse,
          reason: 'with no effects ticket, nothing sets the modifier yet');
    });
  });

  group('headlines', () {
    test('a hole starts with its number big, its par and course under it', () {
      final course = CourseDef(id: 'the_coop', holes: [
        stubHole(id: 'c0', par: 3),
        stubHole(id: 'c1', par: 2),
      ]);
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 2),
      )..boot();
      expect(match.headlineKind, PuttHeadlineKind.holeStart);
      expect(match.headline, 'Hole 1');
      // The catalog's name, not the id.
      expect(match.headlineDetail, 'Par 3 · The Coop');
      expect(match.courseName, 'The Coop');
    });

    test('course ids read as their names; unknown ones as themselves', () {
      expect(puttCourseName('the_corn_maze'), 'Corn Maze');
      expect(puttCourseName('the_barn'), 'The Barn');
      expect(puttCourseName('stubs'), 'stubs');
    });

    test('my last stroke keeps its term when the hole ends with it', () {
      final course = CourseDef(id: 'ace', holes: [stubHole(id: 'a0', par: 3)]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 4,
            wobbleMaxRadians: 0),
      )..boot();
      expect(match.hasPutted, isFalse);
      final shot =
          putt(match.myBall!.position, match.hole!.nest.position, arrival: 0.6);
      expect(match.submitShot(shot.angle, shot.power), isTrue);
      expect(match.hasPutted, isTrue);
      for (var frame = 0; frame < 600; frame++) {
        match.update(1 / 60);
        if (match.phase != PuttPhase.holePlay) break;
      }
      expect(match.phase, PuttPhase.holeScoreboard);
      // Alone on the green: the nest takes the egg and the hole ends on
      // the same tick, and the ace is what the banner calls.
      expect(match.headlineKind, PuttHeadlineKind.scoreTerm);
      expect(match.headlineTerm, ScoreTerm.holeInOne);
      expect(match.headline, 'Hole in one!');
      expect(match.holeEndLine, 'Hole cleared!');
    });

    test('a hole that times out says so', () {
      final course = CourseDef(id: 'slow', holes: [stubHole(id: 's0')]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 6,
            holeTimeLimitSeconds: 2),
      )..boot();
      for (var frame = 0; frame < 40; frame++) {
        match.update(0.3);
      }
      expect(match.headlineKind, PuttHeadlineKind.holeEnd);
      expect(match.headline, "Time's up!");
      expect(match.holeEndLine, "Time's up!");
    });

    test('names come from the map, then the roster lookup', () {
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [stubCourse(holeCount: 1)],
            seed: 1),
        displayNames: const {'me': 'Rooster'},
        nameOf: (id) => id == 'p2' ? 'Hen' : id.toUpperCase(),
      );
      expect(displayNameOf(match, 'me'), 'Rooster');
      expect(displayNameOf(match, 'p2'), 'Hen');
      expect(displayNameOf(match, 'p3'), 'P3');
    });
  });

  group('notices', () {
    test(
        'my stroke is sounding, their strokes are not (solo: there are '
        'none)', () {
      final match = PuttMatch.solo();
      match.drainEvents(); // drop the boot's hole-start chatter
      match.notices.clear();
      expect(match.submitShot(0, 0.5), isTrue);
      // submitShot drains as it goes: the batch lands in notices.
      expect(match.notices.map((n) => n.sfx), contains(PuttSfx.putt));
    });

    test('my stroke fires one putt sound, however strong', () {
      final match = PuttMatch.solo();
      match.submitShot(math.pi, 0.4);
      match.update(0.5);
      final puttNotices =
          match.notices.where((n) => n.sfx == PuttSfx.putt).length;
      expect(puttNotices, lessThanOrEqualTo(2));
    });
  });

  group('sounds', () {
    /// Frames [match] like the game does, gathering what it asks to hear
    /// (the game spends the notices once a frame).
    List<PuttNotice> listen(PuttMatch match, {int frames = 120}) {
      final heard = <PuttNotice>[];
      for (var frame = 0; frame < frames; frame++) {
        match.update(1 / 60);
        heard.addAll(match.notices);
        match.notices.clear();
        if (match.phase != PuttPhase.holePlay) break;
      }
      return heard;
    }

    test('a putt tocks as hard as it was struck', () {
      expect(puttSfxFor(0.1), PuttSfx.puttSoft);
      expect(puttSfxFor(0.5), PuttSfx.putt);
      expect(puttSfxFor(0.95), PuttSfx.puttFirm);
      final match = PuttMatch.solo();
      match.notices.clear();
      expect(match.submitShot(0, 0.95), isTrue);
      expect(match.notices.map((n) => n.sfx), [PuttSfx.puttFirm]);
    });

    test('a hole opens on the banjo, not on a putt', () {
      final match = PuttMatch.solo();
      final heard = match.notices.map((n) => n.sfx);
      expect(heard, contains(PuttSfx.holeStart));
      expect(heard, isNot(contains(PuttSfx.putt)));
    });

    test('an egg off the fence knocks, as loud as it hit', () {
      final match = PuttMatch.solo();
      // Due left from the tee: the fence is four units off.
      expect(match.submitShot(math.pi, 0.7), isTrue);
      final knocks =
          listen(match).where((n) => n.sfx == PuttSfx.bounce).toList();
      expect(knocks, isNotEmpty);
      expect(knocks.first.volume, greaterThan(0.8));
      expect(knocks.every((n) => n.volume > 0 && n.volume <= 1), isTrue);
    });

    test('two eggs meeting clack once', () {
      final course = CourseDef(id: 'pair', holes: [stubHole(id: 'p0')]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 8,
            wobbleMaxRadians: 0),
        seatedPlayerIds: const ['friend'],
      )..boot();
      final mine = match.myBall!.position;
      final theirs = match.engine.world!.ball('friend')!.position;
      expect(match.submitShot((theirs - mine).angle, 0.35), isTrue);
      final clacks = listen(match, frames: 30)
          .where((n) => n.sfx == PuttSfx.clack)
          .toList();
      expect(clacks, hasLength(1));
    });

    test('a sink hatches with a peep; an ace has the host crow too', () {
      PuttMatch onTee() => PuttMatch(
            config: PuttConfig(
                mode: GameMode.casual,
                courses: [
                  CourseDef(id: 'ace', holes: [stubHole(id: 'a0', par: 3)]),
                ],
                seed: 4,
                wobbleMaxRadians: 0),
          )..boot();

      final ace = onTee();
      final shot =
          putt(ace.myBall!.position, ace.hole!.nest.position, arrival: 0.6);
      expect(ace.submitShot(shot.angle, shot.power), isTrue);
      final aceHeard = listen(ace, frames: 600).map((n) => n.sfx).toSet();
      expect(
          aceHeard,
          containsAll([
            PuttSfx.holed,
            PuttSfx.hatch,
            PuttSfx.crow,
            PuttSfx.holeEnd,
          ]));

      final birdie = onTee();
      // A nudge first (straight back, a short way), then the putt home.
      expect(birdie.submitShot(math.pi, 0.08), isTrue);
      listen(birdie, frames: 240);
      final again = putt(birdie.myBall!.position, birdie.hole!.nest.position,
          arrival: 0.6);
      expect(birdie.submitShot(again.angle, again.power), isTrue);
      final birdieHeard = listen(birdie, frames: 600).map((n) => n.sfx).toSet();
      expect(birdieHeard, containsAll([PuttSfx.holed, PuttSfx.hatch]));
      expect(birdieHeard, isNot(contains(PuttSfx.crow)));
    });

    test('the last seconds go tick, tock', () {
      final course = CourseDef(id: 'clock', holes: [stubHole(id: 'c0')]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 3,
            holeTimeLimitSeconds: 16),
      )..boot();
      final clock = listen(match, frames: 60 * 17)
          .map((n) => n.sfx)
          .where((s) => s == PuttSfx.timerTick || s == PuttSfx.timerTock)
          .toList();
      // Fourteen seconds counted down, never the same sound twice running.
      expect(clock, hasLength(14));
      for (var i = 1; i < clock.length; i++) {
        expect(clock[i], isNot(clock[i - 1]));
      }
    });
  });
}
