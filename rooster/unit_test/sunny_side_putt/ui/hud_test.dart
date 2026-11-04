// The HUD's states: while the hole plays (calm timer, chips, inventory),
// in the last fifteen seconds (the pulse), between holes (the results
// card), at match over (the verdict card).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
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
      // The seconds are on the face.
      expect(find.text('120'), findsOneWidget);
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
      // The count shows ceiling, so 10.0 reads as 10.
      expect(find.text('10'), findsOneWidget);
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

  group('the scorecard strip', () {
    testWidgets('one chip per player, me marked', (tester) async {
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

      expect(find.text('Rooster (you)'), findsOneWidget);
      expect(find.text('Hen'), findsOneWidget);
      // Total chip counts read "0 total · 0 here".
      expect(find.text('0 total · 0 here'), findsNWidgets(2));
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
      // The filled slot and its tooltip label.
      expect(find.text('HE'), findsOneWidget);
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
      expect(find.text("Time's up!"), findsOneWidget);
      // The penalty scoring reads out: one weak stroke scores par + 2.
      expect(find.text('4 strokes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-continue')));
      await tester.pump();
      expect(match.phase, PuttPhase.awaitingNextCourse);
    });
  });

  group('match over', () {
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

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
          PuttHud(match: match, onOpenMenu: () {}),
          Align(
            alignment: Alignment.bottomCenter,
            child: SpectatorStrip(match: match),
          ),
        ])),
      ));
      await tester.pump();
      expect(find.text("You're watching from the fence"), findsOneWidget);
      expect(find.text('8 on the green · 0 watching with you'), findsOneWidget);
      // And no aim is offered to a spectator.
      expect(match.myShotReady, isFalse);
    });
  });
}
