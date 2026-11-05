// The HUD's states: while the hole plays (the hole bar and its calm
// timer, the scorecard, the inventory and its targeting), in the last
// fifteen seconds (the pulse), between holes (the results card), at match
// over (the verdict card).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/course_kit.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_powerup_icons.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/spectator_strip.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';

void main() {
  group('timer ring', () {
    testWidgets('calm while the hole is young', (tester) async {
      final match = PuttMatch.solo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: PuttTimerRing(
          secondsRemaining: match.secondsRemaining,
          totalSeconds: match.timerSeconds.toDouble(),
        ))),
      ));
      await tester.pump();

      expect(find.byKey(const Key('putt-timer-ring')), findsOneWidget);
      expect(find.byKey(const Key('putt-timer-pulse')), findsNothing,
          reason: 'far from the bell, the ring does not pulse');
      // The clock reads minutes and seconds.
      expect(find.text('2:00'), findsOneWidget);
    });

    testWidgets('pulses through the last fifteen seconds', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: PuttTimerRing(
          secondsRemaining: 10.0,
          totalSeconds: 120.0,
        ))),
      ));
      await tester.pump();
      expect(find.byKey(const Key('putt-timer-pulse')), findsOneWidget);
      // The count shows ceiling, so 10.0 reads as 0:10.
      expect(find.text('0:10'), findsOneWidget);
    });

    testWidgets('stops pulsing once the ring is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: PuttTimerRing(
          secondsRemaining: 0.0,
          totalSeconds: 120.0,
        ))),
      ));
      await tester.pump();
      expect(find.byKey(const Key('putt-timer-pulse')), findsNothing,
          reason: 'a hole at zero is over, not urgent');
    });
  });

  group('the scorecard', () {
    testWidgets('one row per player, me marked', (tester) async {
      final course = CourseDef(id: 'duo', holes: [stubHole(id: 'd0')]);
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 3),
        displayNames: {'me': 'Rooster', 'p2': 'Hen'},
        seatedPlayerIds: const ['p2'],
      )..boot();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();

      final card = find.byKey(const Key('putt-scorecard'));
      expect(find.descendant(of: card, matching: find.text('Rooster (you)')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Hen')),
          findsOneWidget);
      // No strokes yet on the hole, level with par so far.
      expect(find.descendant(of: card, matching: find.text('0')),
          findsNWidgets(2));
      expect(find.descendant(of: card, matching: find.text('E')),
          findsNWidgets(2));
    });
  });

  group('the scorecard on a short screen', () {
    testWidgets('the leaders and me, then how many more', (tester) async {
      final course = CourseDef(id: 'crowd', holes: [stubHole(id: 'k0')]);
      // Ids that sort before mine: I am last at a tie.
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 9),
        localPlayerId: 'zz-me',
        displayNames: const {'zz-me': 'Rooster'},
        seatedPlayerIds: [for (var i = 0; i < 7; i++) 'a$i'],
      )..boot();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: PuttScorecard(match: match, maxRows: 4),
          ),
        ),
      ));
      expect(find.text('a0'), findsOneWidget);
      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsNothing);
      expect(find.text('Rooster (you)'), findsOneWidget);
      expect(find.text('+5 more players'), findsOneWidget);
    });
  });

  group('the power-up inventory', () {
    testWidgets('three slots, filled left to right, tap spends',
        (tester) async {
      final match = PuttMatch.solo(localPlayerName: 'Tester');
      match.localPlayer!.inventory.add('hawk_eye');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();

      expect(find.byKey(const Key('putt-inventory')), findsOneWidget);
      // The filled slot shows the power-up's icon.
      expect(
          find.descendant(
            of: find.byKey(const Key('putt-slot-0')),
            matching: find.byWidgetPredicate((w) =>
                w is PuttPowerUpIcon &&
                w.effectId == 'hawk_eye' &&
                w.size == 28),
          ),
          findsOneWidget);
      // And the two empty slots are right where the cap says.
      expect(find.byKey(const Key('putt-slot-1')), findsOneWidget);
      expect(find.byKey(const Key('putt-slot-2')), findsOneWidget);

      // Tap the filled one: it is spent where the engine can see it.
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(match.localPlayer!.inventory.length, 0);
      expect(match.myInventory, isEmpty);
    });

    testWidgets('an empty slot does not spend anything', (tester) async {
      final match = PuttMatch.solo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('putt-slot-2')));
      await tester.pump();
      expect(match.myInventory, isEmpty);
    });
  });

  group('between holes', () {
    testWidgets('the results card lists the hole and continues on tap',
        (tester) async {
      final course =
          CourseDef(id: 'one-hole', holes: [stubHole(id: 'only', par: 2)]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            catalog: {'one-hole': course},
            seed: 11,
            holeTimeLimitSeconds: 2),
      )..boot();
      match.submitShot(0, 0.2);
      for (var frame = 0; frame < 40; frame++) {
        match.update(0.3);
      }
      expect(match.phase, PuttPhase.holeScoreboard);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      // A beat for the banner (and the last sink's hatch), then the card
      // rises in.
      await tester.pump(const Duration(milliseconds: 2800));
      expect(
          tester
              .widget<Text>(find.byKey(const Key('putt-results-subtitle')))
              .data,
          "TIME'S UP!");
      // The penalty scoring reads out: one weak stroke scores par + 2,
      // and the egg that never reached the nest says so.
      expect(find.text('4 strokes'), findsOneWidget);
      expect(find.text('OUT OF TIME'), findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-continue')));
      await tester.pump();
      expect(match.phase, PuttPhase.awaitingNextCourse);
    });
  });

  group('match over', () {
    testWidgets('level at the top is a tie', (tester) async {
      final course = CourseDef(id: 'duo', holes: [stubHole(id: 'd0')]);
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 3),
        displayNames: const {'me': 'Rooster', 'p2': 'Hen'},
        seatedPlayerIds: const ['p2'],
      )..boot();
      match.engine.endMatch();
      match.drainEvents();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      expect(find.text("It's a tie!"), findsOneWidget);
      expect(find.text('0 strokes'), findsNWidgets(2));
    });

    testWidgets('the verdict card names the winner and offers the exit',
        (tester) async {
      final match = PuttMatch.solo(localPlayerName: 'Tester');
      match.engine.endMatch();
      match.drainEvents();

      var left = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PuttHud(
          match: match,
          onOpenMenu: () {},
          onLeave: () => left = true,
        )),
      ));
      await tester.pump();
      expect(find.text('Tester wins!'), findsOneWidget);
      await tester.tap(find.byKey(const Key('putt-leave-green')));
      expect(left, isTrue);
    });
  });

  group('the hole bar', () {
    testWidgets('hole of the course, par, my strokes, the clock, the dots',
        (tester) async {
      final course = CourseDef(id: 'the_pond', holes: [
        stubHole(id: 'p0', par: 4),
        stubHole(id: 'p1', par: 2),
        stubHole(id: 'p2', par: 3),
      ]);
      final match = PuttMatch(
        config:
            PuttConfig(mode: GameMode.tournament, courses: [course], seed: 8),
      )..boot();
      match.submitShot(0, 0.3);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();

      final bar = find.byType(PuttHoleBar);
      expect(find.descendant(of: bar, matching: find.text('HOLE')),
          findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.text('1/3')), findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.text('PAR')), findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('STROKES')),
          findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('2:00')),
          findsOneWidget);
      // One dot per hole of the course.
      for (var hole = 1; hole <= 3; hole++) {
        expect(find.byKey(Key('putt-hole-dot-$hole')), findsOneWidget);
      }
      // And the course chip names the course and the mode.
      expect(find.text('The Pond'), findsOneWidget);
      expect(find.text('TOURNAMENT'), findsOneWidget);
    });

    testWidgets('the camera button offers the other view', (tester) async {
      final match = PuttMatch.solo();
      var toggles = 0;
      Widget hud(bool overview) => MaterialApp(
            home: Scaffold(
              body: PuttHud(
                match: match,
                onOpenMenu: () {},
                onToggleCamera: () => toggles++,
                cameraOverview: overview,
              ),
            ),
          );
      await tester.pumpWidget(hud(false));
      expect(find.byTooltip('See the whole hole (C)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('putt-camera')));
      expect(toggles, 1);

      await tester.pumpWidget(hud(true));
      expect(find.byTooltip('Back in close (C)'), findsOneWidget);
      expect(find.byTooltip('Pause (Esc)'), findsOneWidget);
    });
  });

  group('the results card', () {
    testWidgets('an ace: one stroke, its badge, under par', (tester) async {
      final course = CourseDef(id: 'ace', holes: [stubHole(id: 'a0', par: 3)]);
      final match = PuttMatch(
        config: PuttConfig(
            mode: GameMode.casual,
            courses: [course],
            seed: 4,
            wobbleMaxRadians: 0),
        displayNames: const {'me': 'Rooster'},
      )..boot();
      final shot =
          putt(match.myBall!.position, match.hole!.nest.position, arrival: 0.6);
      match.submitShot(shot.angle, shot.power);
      for (var frame = 0; frame < 600; frame++) {
        match.update(1 / 60);
        if (match.phase != PuttPhase.holePlay) break;
      }
      expect(match.phase, PuttPhase.holeScoreboard);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      // First the ace's own banner...
      expect(find.text('Hole in one!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      // ...then the card: the hole and its par, the stroke (singular),
      // the badge, two under.
      expect(find.text('Hole 1 · Par 3'), findsOneWidget);
      expect(find.text('1 stroke'), findsOneWidget);
      expect(find.text('HOLE IN ONE'), findsOneWidget);
      expect(find.text('−2'), findsOneWidget);
      expect(find.text('Rooster (you)'), findsOneWidget);
    });
  });

  group('the headline banner', () {
    testWidgets('a fresh hole announces itself', (tester) async {
      final match = PuttMatch.solo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      expect(find.text(match.headline ?? ''), findsOneWidget);
      expect(match.headline, contains('Hole 1'));
    });
  });

  group('spectators', () {
    testWidgets('the spectator strip stands where the aim would be',
        (tester) async {
      final course = CourseDef(id: 'full', holes: [stubHole(id: 'f0')]);
      final match = PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 5),
        localPlayerId: 'me',
        seatedPlayerIds: [for (var i = 0; i < 8; i++) 'p$i'],
      )..boot();
      expect(match.isSpectator, isTrue);

      // The HUD carries the strip on its hint line.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      expect(find.text("You're watching from the fence"), findsOneWidget);
      expect(find.text('8 on the green · 0 watching with you'), findsOneWidget);
      expect(find.byType(SpectatorStrip), findsOneWidget);
      // And no aim is offered to a spectator, nor a carton to tap.
      expect(match.myShotReady, isFalse);
      expect(find.byKey(const Key('putt-inventory')), findsNothing);
    });
  });
}
