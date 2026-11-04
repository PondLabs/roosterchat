// Power-up targeting: a tap casts the effects that need nothing, arms the
// ones that need a spot on the green (the next press casts there), opens
// a picker for the ones that need a player - and nothing is spent on a
// cancel, a pick that cannot work, or a cast that would do nothing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_targeting.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

/// A booted match with the twelve real effects, me and [others] on the
/// stub green.
PuttMatch effectsMatch({List<String> others = const []}) {
  final course = CourseDef(id: 'aim', holes: [stubHole(id: 'aim-0')]);
  return PuttMatch(
    config: PuttConfig(
      mode: GameMode.casual,
      courses: [course],
      seed: 12,
      powerUps: puttLaunchPowerUps(),
    ),
    displayNames: const {'me': 'Rooster', 'p2': 'Hen', 'p3': 'Chick'},
    seatedPlayerIds: others,
  )..boot();
}

void main() {
  test('the twelve effects know what they aim at', () {
    expect(builtinEffectIds, hasLength(12));
    final aims = {for (final id in builtinEffectIds) id: puttPowerAimOf(id)};
    expect(
        [
          for (final entry in aims.entries)
            if (entry.value == PuttPowerAim.point) entry.key
        ]..sort(),
        ['gust', 'rabbit_hole', 'sprinkler']);
    expect(
        [
          for (final entry in aims.entries)
            if (entry.value == PuttPowerAim.player) entry.key
        ]..sort(),
        ['nest_swap', 'thieving_crow']);
    // The live session's matches carry every one of them.
    expect(puttLaunchPowerUps().grantableIds.toSet(), builtinEffectIds);
  });

  group('a spot on the green', () {
    test('a tap arms, the cast lands where it was asked', () {
      final match = effectsMatch();
      final targeting = PuttTargeting();
      match.localPlayer!.inventory.add('rabbit_hole');
      final egg = match.myBall!.position;

      targeting.tapSlot(match, 0, 'rabbit_hole');
      expect(targeting.armed, 'rabbit_hole');
      expect(targeting.armedSlot, 0);
      expect(match.myInventory, ['rabbit_hole'],
          reason: 'arming spends nothing');

      // Three steps east: within the hop's reach.
      final spot = egg + const Vec2(3, 0);
      expect(targeting.castAt(match, spot), isTrue);
      expect(match.myInventory, isEmpty);
      expect(targeting.isActive, isFalse);
      expect(match.myBall!.position.distanceTo(spot), lessThan(1e-6),
          reason: 'the Rabbit Hole popped my egg up at the spot');
    });

    test('tapping the armed slot again, or cancelling, spends nothing', () {
      final match = effectsMatch(others: const ['p2']);
      final targeting = PuttTargeting();
      match.localPlayer!.inventory.add('sprinkler');

      targeting.tapSlot(match, 0, 'sprinkler');
      expect(targeting.armed, 'sprinkler');
      targeting.tapSlot(match, 0, 'sprinkler');
      expect(targeting.isActive, isFalse);

      targeting.tapSlot(match, 0, 'sprinkler');
      targeting.cancel();
      expect(targeting.isActive, isFalse);
      expect(targeting.castAt(match, Vec2.zero), isFalse,
          reason: 'nothing armed, nothing cast');
      expect(match.myInventory, ['sprinkler']);
    });

    test('with no other egg to push, a Gust is kept and says why', () {
      final match = effectsMatch();
      final targeting = PuttTargeting();
      match.localPlayer!.inventory.add('gust');

      targeting.tapSlot(match, 0, 'gust');
      expect(targeting.armed, isNull);
      expect(targeting.notice, 'No other eggs on the green to push');
      expect(match.myInventory, ['gust']);
    });

    test('an armed slot lets go when the hole ends', () {
      final match = effectsMatch(others: const ['p2']);
      final targeting = PuttTargeting();
      match.localPlayer!.inventory.add('gust');
      targeting.tapSlot(match, 0, 'gust');
      expect(targeting.armed, 'gust');

      match.engine.endMatch();
      targeting.validate(match);
      expect(targeting.isActive, isFalse);
      expect(match.myInventory, ['gust']);
    });

    test('an armed slot follows its power-up when the carton shifts', () {
      final match = effectsMatch(others: const ['p2']);
      final targeting = PuttTargeting();
      match.localPlayer!.inventory
        ..add('hawk_eye')
        ..add('sprinkler');
      targeting.tapSlot(match, 1, 'sprinkler');
      expect(targeting.armedSlot, 1);

      // Hawk Eye goes (cast elsewhere): the sprinkler slides to slot 0.
      match.usePowerUp('hawk_eye');
      targeting.validate(match);
      expect(targeting.armed, 'sprinkler');
      expect(targeting.armedSlot, 0);
    });
  });

  group('another player', () {
    test('a Nest Swap picks a player and trades places with them', () {
      final match = effectsMatch(others: const ['p2']);
      final targeting = PuttTargeting();
      match.localPlayer!.inventory.add('nest_swap');
      // Move my egg off the tee so the swap shows.
      match.engine.world!
          .teleportBall('me', match.hole!.tee + const Vec2(4, 0));
      final mine = match.myBall!.position;
      final theirs = match.engine.world!.ball('p2')!.position;

      targeting.tapSlot(match, 0, 'nest_swap');
      expect(targeting.picking, 'nest_swap');
      expect(PuttTargeting.candidates(match, 'nest_swap'), ['p2']);
      expect(targeting.castOn(match, 'nobody'), isFalse);
      expect(match.myInventory, ['nest_swap']);

      expect(targeting.castOn(match, 'p2'), isTrue);
      expect(match.myInventory, isEmpty);
      expect(match.myBall!.position.distanceTo(theirs), lessThan(1e-6));
      expect(match.engine.world!.ball('p2')!.position.distanceTo(mine),
          lessThan(1e-6));
    });

    test('a Thieving Crow with nobody to rob is kept, and says so', () {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('thieving_crow');
      expect(PuttTargeting.candidates(match, 'thieving_crow'), isEmpty);
      expect(PuttTargeting.nobodyToPick(match, 'thieving_crow'),
          'Nobody has a power-up to steal');

      // Once the hen holds one, she is on the list.
      match.engine.player('p2')!.inventory.add('gust');
      expect(PuttTargeting.candidates(match, 'thieving_crow'), ['p2']);
    });
  });

  group('the HUD', () {
    testWidgets('a no-target power-up is spent at the tap', (tester) async {
      final match = effectsMatch();
      match.localPlayer!.inventory.add('strong_coffee');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(match.myInventory, isEmpty);
      expect(match.localPlayer!.nextShot.powerMultiplier, greaterThan(1));
    });

    testWidgets('an armed slot asks for a spot on the hint line',
        (tester) async {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('sprinkler');
      final targeting = PuttTargeting();
      addTearDown(targeting.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttHud(
            match: match,
            onOpenMenu: () {},
            targeting: targeting,
          ),
        ),
      ));
      expect(
          find.text('Drag anywhere to aim · let go to putt'), findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(targeting.armed, 'sprinkler');
      expect(find.text('Tap a spot: the sprinkler soaks the eggs around it'),
          findsOneWidget);
      expect(find.text('Tap the power-up again to cancel'), findsOneWidget);
      expect(match.myInventory, ['sprinkler']);
    });

    testWidgets('the picker lists the others and casts on the one picked',
        (tester) async {
      final match = effectsMatch(others: const ['p2', 'p3']);
      match.localPlayer!.inventory.add('thieving_crow');
      match.engine.player('p3')!.inventory.add('ghost_egg');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();

      final picker = find.byKey(const Key('putt-picker'));
      expect(picker, findsOneWidget);
      expect(find.text('Steal a power-up from…'), findsOneWidget);
      // Only the chick holds anything; the crow shows what it would take.
      expect(find.byKey(const Key('putt-pick-p2')), findsNothing);
      expect(find.byKey(const Key('putt-pick-p3')), findsOneWidget);
      expect(find.descendant(of: picker, matching: find.text('👻')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-pick-p3')));
      await tester.pump();
      expect(find.byKey(const Key('putt-picker')), findsNothing);
      expect(match.myInventory, ['ghost_egg'],
          reason: 'the crow was spent and brought the ghost egg home');
      expect(match.engine.player('p3')!.inventory.isEmpty, isTrue);
    });

    testWidgets('with nobody to pick, the picker says so and keeps it',
        (tester) async {
      final match = effectsMatch();
      match.localPlayer!.inventory.add('nest_swap');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(find.text('Nobody on the green to swap with'), findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-pick-cancel')));
      await tester.pump();
      expect(find.byKey(const Key('putt-picker')), findsNothing);
      expect(match.myInventory, ['nest_swap']);
    });
  });

  group('the view', () {
    testWidgets('Esc puts an armed power-up away before it pauses',
        (tester) async {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('gust');
      late SunnySidePuttGame game;
      await tester.pumpWidget(MaterialApp(
        home: SunnySidePuttView(match: match, onGame: (g) => game = g),
      ));
      await tester.pump(const Duration(milliseconds: 80));

      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(game.targeting.armed, 'gust');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.targeting.isActive, isFalse);
      expect(match.paused, isFalse, reason: 'the first Esc only cancels');
      expect(match.myInventory, ['gust']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(match.paused, isTrue);
    });

    testWidgets('armed, a press on the green casts instead of aiming',
        (tester) async {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('sprinkler');
      late SunnySidePuttGame game;
      await tester.pumpWidget(MaterialApp(
        home: SunnySidePuttView(match: match, onGame: (g) => game = g),
      ));
      await tester.pump(const Duration(milliseconds: 80));

      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(game.targeting.armed, 'sprinkler');

      // Press on the egg itself, where a press would otherwise aim.
      final egg = game.view3d.project(match.myBall!.position);
      await tester.tapAt(egg);
      await tester.pump();
      expect(match.myInventory, isEmpty, reason: 'the sprinkler went off');
      expect(game.targeting.isActive, isFalse);
      expect(game.aim.isActive, isFalse);
      expect(match.myStrokesThisHole, 0, reason: 'and no stroke was taken');
    });

    testWidgets('pausing puts an armed power-up back, unspent', (tester) async {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('rabbit_hole');
      late SunnySidePuttGame game;
      await tester.pumpWidget(MaterialApp(
        home: SunnySidePuttView(match: match, onGame: (g) => game = g),
      ));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();
      expect(game.targeting.armed, 'rabbit_hole');

      await tester.tap(find.byKey(const Key('putt-pause')));
      await tester.pump();
      expect(match.paused, isTrue);
      expect(game.targeting.isActive, isFalse);
      expect(match.myInventory, ['rabbit_hole']);
    });

    testWidgets('a right click cancels an armed power-up', (tester) async {
      final match = effectsMatch(others: const ['p2']);
      match.localPlayer!.inventory.add('sprinkler');
      late SunnySidePuttGame game;
      await tester.pumpWidget(MaterialApp(
        home: SunnySidePuttView(match: match, onGame: (g) => game = g),
      ));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('putt-slot-0')));
      await tester.pump();

      final egg = game.view3d.project(match.myBall!.position);
      await tester.tapAt(egg,
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(game.targeting.isActive, isFalse);
      expect(match.myInventory, ['sprinkler']);
    });
  });
}
