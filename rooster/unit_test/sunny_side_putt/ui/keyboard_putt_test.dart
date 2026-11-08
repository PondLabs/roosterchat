// Putting from the keyboard: Left and Right turn the aim (Shift for fine
// steps), Up and Down set the power in 5% steps, Space or Enter putts
// through the same release a drag ends in, Esc drops the aim unspent, and
// Tab with Enter uses a power-up as a click on its slot does.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/aim_controller.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

/// A booted match on the stub green, every shot and cast also told to
/// [moves] (the wire a guest's moves go out on).
PuttMatch keyMatch(List<EngineInput> moves) {
  final course = CourseDef(id: 'keys', holes: [stubHole(id: 'keys-0')]);
  return PuttMatch(
    config: PuttConfig(
      mode: GameMode.casual,
      courses: [course],
      seed: 7,
      powerUps: puttLaunchPowerUps(),
      // The keys' own aim, still: the sway has its tests in aim_test.
      wobbleMaxRadians: 0,
    ),
    displayNames: const {'me': 'Rooster', 'p2': 'Hen'},
    seatedPlayerIds: const ['p2'],
    remoteMove: moves.add,
  )..boot();
}

double wrap(double angle) => math.atan2(math.sin(angle), math.cos(angle));

void main() {
  group('the aim held by the keys', () {
    test('holds an angle and a power, read as the pull that gives it', () {
      final aim = AimController();
      aim.hold(const Vec2(1, 2), angle: 0.3, power: 0.5);
      expect(aim.isActive, isTrue);
      expect(aim.origin, const Vec2(1, 2));
      expect(aim.state!.angle, closeTo(0.3, 1e-9));
      expect(aim.state!.power, closeTo(0.5, 1e-9));
      expect(aim.powerFor(aim.state!.dragLength), closeTo(0.5, 1e-9));
    });

    test('turns and steps the power on a 5% grid, within the stroke', () {
      final aim = AimController();
      aim.hold(Vec2.zero, angle: 0, power: AimController.keyPowerStart);
      aim.stepPower(1);
      expect(aim.state!.power, closeTo(0.55, 1e-9));
      aim.stepPower(-3);
      expect(aim.state!.power, closeTo(0.40, 1e-9));
      for (var i = 0; i < 40; i++) {
        aim.stepPower(1);
      }
      expect(aim.state!.power, 1.0);
      for (var i = 0; i < 40; i++) {
        aim.stepPower(-1);
      }
      // The softest is the first step a pull out of the dead zone reaches:
      // a softer one would be a tap, and fire nothing.
      expect(aim.state!.power, closeTo(aim.keyPowerMin, 1e-9));
      expect(
          aim.state!.dragLength, greaterThanOrEqualTo(AimController.deadZone));
      expect(aim.keyPowerMin, closeTo(0.30, 1e-9));

      aim.turnBy(AimController.keyTurnStep);
      expect(aim.state!.angle, closeTo(AimController.keyTurnStep, 1e-9));
      // Committed like a drag: the angle and power it holds.
      final shot = aim.commit();
      expect(shot, isNotNull);
      expect(shot!.power, closeTo(0.30, 1e-9));
      expect(aim.isActive, isFalse);
    });
  });

  group('the view', () {
    late List<EngineInput> moves;
    late PuttMatch match;
    late SunnySidePuttGame game;

    Future<void> boot(WidgetTester tester) async {
      moves = [];
      match = keyMatch(moves);
      await tester.pumpWidget(MaterialApp(
        home: SunnySidePuttView(match: match, onGame: (g) => game = g),
      ));
      await tester.pump(const Duration(milliseconds: 80));
    }

    double towardNest() =>
        (match.hole!.nest.position - match.myBall!.position).angle;

    testWidgets('Left and Right turn the aim, from the way to the nest',
        (tester) async {
      await boot(tester);
      expect(game.aim.isActive, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(game.aim.isActive, isTrue, reason: 'the first key starts it');
      expect(game.keyAiming, isTrue);
      expect(game.aim.origin, match.myBall!.position);
      expect(game.aim.state!.power, AimController.keyPowerStart);
      expect(game.aim.state!.angle,
          closeTo(wrap(towardNest() + AimController.keyTurnStep), 1e-9));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(game.aim.state!.angle,
          closeTo(wrap(towardNest() - AimController.keyTurnStep), 1e-9));
    });

    testWidgets('Shift turns in fine steps', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      final start = game.aim.state!.angle;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(game.aim.state!.angle,
          closeTo(wrap(start + AimController.keyFineTurnStep), 1e-9));
      expect(AimController.keyFineTurnStep,
          lessThan(AimController.keyTurnStep / 4));
    });

    testWidgets('Up and Down set the power in 5% steps', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(game.aim.state!.power, closeTo(0.55, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(game.aim.state!.power, closeTo(0.60, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(game.aim.state!.power, closeTo(0.45, 1e-9));
      // The arrow shows it live: the world's frame carries the aim.
      final frame = game.buildWorldFrame();
      expect(frame.aim, isNotNull);
      expect(frame.aim!.power, closeTo(0.45, 1e-9));
      expect(frame.aim!.dragLength, closeTo(game.aim.dragFor(0.45), 1e-9),
          reason: 'and its band, as long as the pull that gives it');
    });

    testWidgets('Space putts the angle and power the aim holds',
        (tester) async {
      await boot(tester);
      // Down twice: 40%.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      final held = game.aim.state!;
      expect(held.power, closeTo(0.40, 1e-9));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      final shots = moves.whereType<ShotInput>().toList();
      expect(shots, hasLength(1));
      expect(shots.single.angle, closeTo(held.angle, 1e-9));
      expect(shots.single.power, closeTo(held.power, 1e-9));
      expect(match.myStrokesThisHole, 1);
      expect(game.aim.isActive, isFalse);
    });

    testWidgets('Enter putts too', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(moves.whereType<ShotInput>(), hasLength(1));
    });

    testWidgets('the keys neither aim nor putt while the hole builds',
        (tester) async {
      await boot(tester);
      game.holeLoading.value = (0, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(game.aim.isActive, isFalse);
      expect(moves.whereType<ShotInput>(), isEmpty);
      game.holeLoading.value = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(game.aim.isActive, isTrue, reason: 'built, the keys are back');
    });

    testWidgets('a drag does not fire a keyboard aim on a stray release',
        (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      game.endAim(match.myBall!.position + const Vec2(0, 4));
      expect(moves.whereType<ShotInput>(), isEmpty);
      expect(game.keyAiming, isTrue);
    });

    testWidgets('a right click mid-pull takes the aim back, unspent',
        (tester) async {
      await boot(tester);
      final egg = game.view3d.project(match.myBall!.position);
      final mouse =
          TestPointer(1, PointerDeviceKind.mouse, null, kPrimaryMouseButton);
      await tester.sendEventToBinding(mouse.addPointer(location: egg));
      await tester.sendEventToBinding(mouse.down(egg));
      await tester.sendEventToBinding(mouse.move(egg + const Offset(0, 90)));
      expect(game.aim.dragLength, greaterThan(AimController.deadZone));

      // The right button joins the left: the same pointer, its buttons
      // changed.
      await tester.sendEventToBinding(mouse.move(egg + const Offset(0, 100),
          buttons: kPrimaryMouseButton | kSecondaryMouseButton));
      expect(game.aim.isActive, isFalse);
      // Still pulling with the left: nothing comes back, nothing fires.
      await tester.sendEventToBinding(mouse.move(egg + const Offset(0, 120)));
      expect(game.aim.isActive, isFalse);
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();
      expect(moves.whereType<ShotInput>(), isEmpty);
      expect(match.myStrokesThisHole, 0);
      await tester.sendEventToBinding(mouse.removePointer());
    });

    testWidgets('a release inside the dead zone is a cancel', (tester) async {
      await boot(tester);
      final at = match.myBall!.position;
      game.beginAim(at);
      expect(game.aim.state!.power, 0);
      game.endAim(at + const Vec2(0, AimController.deadZone / 2));
      expect(game.aim.isActive, isFalse);
      expect(moves.whereType<ShotInput>(), isEmpty);
    });

    testWidgets('Esc drops the aim unspent before it pauses', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(game.aim.isActive, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.aim.isActive, isFalse);
      expect(match.paused, isFalse, reason: 'the first Esc only cancels');
      expect(moves.whereType<ShotInput>(), isEmpty);
      expect(match.myStrokesThisHole, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Game settings'), findsOneWidget);
      expect(match.paused, isFalse, reason: 'with others the hole runs on');
      // With the menu up the arrows are the menu's, not the aim's.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(game.aim.isActive, isFalse);
    });

    testWidgets('Tab highlights a slot and Enter uses it as a click does',
        (tester) async {
      await boot(tester);
      match.localPlayer!.inventory.add('hawk_eye');
      match.localPlayer!.inventory.add('gust');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(game.targeting.keySlot, 0);
      expect(find.byKey(const Key('putt-slot-highlight')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(game.targeting.keySlot, 1);
      // Past the last filled slot, the keys go back to aiming.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(game.targeting.keySlot, isNull);
      expect(find.byKey(const Key('putt-slot-highlight')), findsNothing);

      // Shift+Tab comes in from the end; Enter on Gust arms it for a spot.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(game.targeting.keySlot, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(game.targeting.armed, 'gust');
      expect(match.myInventory, ['hawk_eye', 'gust'], reason: 'unspent yet');
      expect(game.aim.isActive, isFalse);

      // Esc puts it away first, then the highlight.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.targeting.isActive, isFalse);
      expect(game.targeting.keySlot, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.targeting.keySlot, isNull);
      expect(match.paused, isFalse);

      // Hawk Eye needs no target: Space on it casts at once.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(match.myInventory, ['gust']);
      expect(moves.whereType<ShotInput>(), isEmpty,
          reason: 'using a power-up is not a putt');
    });

    testWidgets('Tab with an empty carton does nothing', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(game.targeting.keySlot, isNull);
    });
  });

  group('the hint line', () {
    testWidgets('names the keys where a keyboard is likely', (tester) async {
      final match = keyMatch([]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      expect(find.text(labelPuttAimHint()), findsOneWidget);
      expect(find.text(labelPuttKeysHint()), findsOneWidget);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('and not on a phone', (tester) async {
      final match = keyMatch([]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      expect(find.text(labelPuttAimHint()), findsOneWidget);
      expect(find.text(labelPuttKeysHint()), findsNothing);
    }, variant: TargetPlatformVariant.mobile());

    testWidgets('a pull held by the keys says how they putt', (tester) async {
      final match = keyMatch([]);
      final busy = ValueNotifier(true);
      final keys = ValueNotifier(true);
      addTearDown(busy.dispose);
      addTearDown(keys.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttHud(
              match: match, onOpenMenu: () {}, busy: busy, keyAiming: keys),
        ),
      ));
      await tester.pump();
      expect(find.text(labelPuttKeyReleaseHint()), findsOneWidget);
      expect(find.text(labelPuttReleaseHint()), findsNothing);

      keys.value = false;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(labelPuttReleaseHint()), findsOneWidget);
    });
  });

  test('the platform guess', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(PuttHintLine.hasKeyboard, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PuttHintLine.hasKeyboard, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
