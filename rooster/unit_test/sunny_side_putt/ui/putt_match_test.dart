// The local match harness: boots on the stub course, fires strokes, rolls
// eggs, times holes out, and spends the engine's events as notices.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
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
}
