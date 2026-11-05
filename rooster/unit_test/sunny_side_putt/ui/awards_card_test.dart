// The course's awards card: after the last hole's results, a podium of the
// top three chicks (second, first, third; ties share a step; spectators
// get none) and the awards the course earned, only those, then the
// Continue on to whatever is next. It fits a laptop and a phone, in
// English and in Portuguese.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';

import '../core/fixtures.dart';

/// A one-hole course where I hole in one and everyone else runs out of
/// time (a tie behind me), up to the course's awards.
PuttMatch _matchAtAwards({
  List<String> others = const ['p2', 'p3'],
  Map<String, String> names = const {
    'me': 'Gabriel',
    'p2': 'Maya',
    'p3': 'Jonas',
    'p9': 'Lou',
  },
  int maxPlayers = 8,
  void Function(PuttEngine engine)? meanwhile,
}) {
  final course = CourseDef(id: 'one', holes: [stubHole(id: 'o0', par: 2)]);
  final match = PuttMatch(
    config: PuttConfig(
      mode: GameMode.casual,
      courses: [course],
      catalog: {'one': course},
      seed: 21,
      holeTimeLimitSeconds: 6,
      wobbleMaxRadians: 0,
      maxPlayers: maxPlayers,
    ),
    displayNames: names,
    seatedPlayerIds: others,
  )..boot();
  meanwhile?.call(match.engine);
  final ball = match.myBall!;
  final (angle, power) = puttFor(match.hole!, ball.position);
  expect(match.submitShot(angle, power), isTrue);
  for (var frame = 0;
      frame < 60 && match.phase == PuttPhase.holePlay;
      frame++) {
    match.update(0.3);
  }
  expect(match.phase, PuttPhase.holeScoreboard);
  expect(match.engine.holeStrokes('me'), [1], reason: 'an ace');
  expect(match.advance(), isTrue);
  expect(match.engine.courseAwardsUp, isTrue);
  return match;
}

Future<void> _show(WidgetTester tester, PuttMatch match, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Finder _chick(String id) => find.byKey(Key('putt-podium-chick-$id'));
Finder _step(int rank) => find.byKey(Key('putt-podium-step-$rank'));
Finder _award(PuttAwardKind kind) => find.byKey(Key('putt-award-${kind.name}'));

void main() {
  group('the podium', () {
    ScoreRow row(String id, int total) =>
        ScoreRow(playerId: id, total: total, relative: 0, holeStrokes: []);

    test('ties share a step, the next place skips ahead', () {
      final podium =
          puttPodium([row('a', 3), row('b', 3), row('c', 5), row('d', 6)]);
      expect([for (final (rank, rows) in podium) (rank, rows.length)],
          [(1, 2), (3, 1)]);
      expect(
          puttPodium([row('a', 2), row('b', 3), row('c', 3), row('d', 4)])
              .map((step) => step.$1),
          [1, 2],
          reason: 'fourth place stands on no step');
      expect(puttPodium([row('solo', 4)]).single.$2.single.playerId, 'solo');
    });
  });

  group('the awards card', () {
    testWidgets('a podium of the top three, and the awards earned',
        (tester) async {
      final match = _matchAtAwards();
      // Things the course raised along the way (the engine's own tally).
      match.engine.courseTally
        ..seeWorld(
            const BallKnocked(playerId: 'me', byPlayerId: 'p3', impactSpeed: 3))
        ..seeWorld(
            const BallKnocked(playerId: 'p2', byPlayerId: 'p3', impactSpeed: 3))
        ..stole('p2');
      await _show(tester, match, const Size(1280, 800));
      expect(tester.takeException(), isNull);

      expect(find.byType(PuttCourseAwardsCard), findsOneWidget);
      expect(find.text('And the awards go to…'), findsOneWidget);
      // First me, alone; Maya and Jonas tied behind; no third step.
      expect(find.descendant(of: _step(1), matching: find.text('1')),
          findsOneWidget);
      expect(_step(2), findsOneWidget);
      expect(_step(3), findsNothing);
      for (final id in ['me', 'p2', 'p3']) {
        expect(_chick(id), findsOneWidget);
      }
      // Second on the left of first, first the tallest.
      expect(tester.getCenter(_chick('p2')).dx,
          lessThan(tester.getCenter(_chick('me')).dx));
      expect(tester.getSize(_step(1)).height,
          greaterThan(tester.getSize(_step(2)).height));
      expect(tester.getCenter(_chick('me')).dy,
          lessThan(tester.getCenter(_chick('p2')).dy));

      // Only what someone earned, in the card's order.
      expect(_award(PuttAwardKind.ace), findsOneWidget);
      expect(find.text('1 hole in one'), findsOneWidget);
      expect(_award(PuttAwardKind.bowlingBall), findsOneWidget);
      expect(find.text('2 eggs knocked'), findsOneWidget);
      expect(
          find.descendant(
              of: _award(PuttAwardKind.bowlingBall),
              matching: find.text('Jonas')),
          findsOneWidget);
      expect(_award(PuttAwardKind.stickyFingers), findsOneWidget);
      expect(find.text('1 power-up pinched'), findsOneWidget);
      for (final kind in [
        PuttAwardKind.highFlyer,
        PuttAwardKind.hardBoiled,
        PuttAwardKind.makingASplash,
      ]) {
        expect(_award(kind), findsNothing, reason: '$kind: nobody earned it');
      }
      expect(tester.getCenter(_award(PuttAwardKind.ace)).dy,
          lessThan(tester.getCenter(_award(PuttAwardKind.stickyFingers)).dy));

      // The Continue moves on: the vote.
      await tester.tap(find.byKey(const Key('putt-continue')));
      await tester.pump();
      expect(match.phase, PuttPhase.awaitingNextCourse);
    });

    testWidgets('a spectator stands on no step and wins nothing',
        (tester) async {
      final match = _matchAtAwards(
        maxPlayers: 3,
        meanwhile: (engine) {
          // The table is full: Lou watches.
          expect(engine.join('p9'), isTrue);
          expect(engine.isSpectator('p9'), isTrue);
        },
      );
      match.engine.courseTally.stole('p9');
      await _show(tester, match, const Size(1280, 800));
      expect(_chick('p9'), findsNothing);
      expect(_award(PuttAwardKind.stickyFingers), findsNothing);
      expect(find.text('Lou'), findsNothing);
    });

    testWidgets('a solo match: a podium of one, no award nobody earned',
        (tester) async {
      final match = _matchAtAwards(others: const []);
      await _show(tester, match, const Size(1280, 800));
      expect(tester.takeException(), isNull);
      expect(_chick('me'), findsOneWidget);
      expect(_step(1), findsOneWidget);
      expect(_step(2), findsNothing);
      // The ace I made, and nothing else.
      expect(_award(PuttAwardKind.ace), findsOneWidget);
      expect(find.byKey(const Key('putt-award-bowlingBall')), findsNothing);
    });

    for (final (label, size) in const [
      ('a laptop', Size(1280, 800)),
      ('a phone', Size(360, 640)),
      ('a phone on its side', Size(740, 360)),
    ]) {
      testWidgets('eight players in Portuguese fit $label', (tester) async {
        await initializeMessages('pt');
        Intl.defaultLocale = 'pt';
        addTearDown(() => Intl.defaultLocale = null);
        final others = [for (var i = 2; i <= 8; i++) 'p$i'];
        final match = _matchAtAwards(
          others: others,
          names: {
            'me': 'Gabriel Albuquerque',
            for (final id in others) id: 'Maria Eduarda $id',
          },
        );
        final tally = match.engine.courseTally
          ..seeWorld(const BallKnocked(
              playerId: 'p2', byPlayerId: 'p5', impactSpeed: 3))
          ..seeWorld(
              const BallLaunched(playerId: 'p4', at: Vec2(3, 3), speed: 5))
          ..seeWorld(
              const BallLanded(playerId: 'p4', at: Vec2(12, 3), impactSpeed: 1))
          ..stole('p6')
          ..blocked('p7');
        tally.seeWorld(const BallSplashed(playerId: 'p8', at: Vec2(3, 3)));
        await _show(tester, match, size);
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        expect(find.text('E os prêmios vão para…'), findsOneWidget);
        // Everyone else tied behind me: one step of seven.
        expect(
            find.descendant(
                of: find.byKey(const Key('putt-podium')),
                matching: find.byType(CustomPaint)),
            findsNWidgets(8));
        // Four lines at most: the ace, the knocks, the flight, the theft.
        expect(find.text('Ás'), findsOneWidget);
        expect(find.text('1 ovo atropelado'), findsOneWidget);
        expect(find.text('10 ovos de distância'), findsOneWidget,
            reason: '9 units is ten eggs of 0.9');
        expect(find.text('Mão leve'), findsOneWidget);
        expect(_award(PuttAwardKind.hardBoiled), findsNothing);
        // The card stays on the screen.
        final card = tester.getRect(find.byType(PuttCourseAwardsCard));
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(size.width));
        expect(card.bottom, lessThanOrEqualTo(size.height));
      });
    }
  });
}
