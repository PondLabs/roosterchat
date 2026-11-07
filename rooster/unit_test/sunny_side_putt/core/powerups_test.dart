// The power-up contract, exercised with fake effects (the twelve real ones
// are another ticket): the inventory cap of 3 with extras discarded, the
// caster-immunity hard rule, shields blocking harmful effects, next-shot
// modifiers applying exactly once, and the "?" box grant flow (doubled in
// Barnyard Chaos).
library;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

PowerUpRegistry only(PowerUpEffect effect) =>
    PowerUpRegistry()..register(effect);

/// A course whose first hole runs (4,8) -> (20,8) with a "?" box sitting on
/// that line at (12,8): any straight drive through the middle picks it up.
PuttConfig boxedConfig({
  required PowerUpRegistry powerUps,
  GameMode mode = GameMode.casual,
}) {
  return PuttConfig(
    mode: mode,
    courses: [
      CourseDef(id: 'test-course', holes: [
        boxHole(
            id: 'h0',
            par: 2,
            width: 24,
            height: 16,
            tee: const Vec2(4, 8),
            nest: const Nest(Vec2(20, 8), 0.8),
            friction: 4,
            boxes: [QuestionBox('box1', const Vec2(12, 8))]),
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
    ],
    seed: 4242,
    holeTimeLimitSeconds: 30,
    wobbleMaxRadians: 0,
    powerUps: powerUps,
  );
}

/// An engine with [players] joined and the match started; nobody has putted.
PuttEngine startedEngine({
  List<String> players = const ['p1', 'p2', 'p3'],
  required PowerUpRegistry powerUps,
  GameMode mode = GameMode.casual,
  bool boxed = false,
}) {
  final engine = PuttEngine(boxed
      ? boxedConfig(powerUps: powerUps, mode: mode)
      : PuttConfig(
          mode: mode,
          courses: [
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
          ],
          seed: 4242,
          holeTimeLimitSeconds: 30,
          wobbleMaxRadians: 0,
          powerUps: powerUps,
        ));
  for (final p in players) {
    engine.join(p);
  }
  expect(engine.start(), isTrue);
  return engine;
}

/// Fires [playerId]'s shot and simulates until the volley settles, drain
/// collecting every engine event.
List<PuttEvent> driveAndSettle(
    PuttEngine engine, String playerId, double angle, double power) {
  expect(engine.submitShot(playerId, angle, power), isTrue);
  final events = engine.drainEvents();
  var guard = 0;
  while (guard < 7200) {
    guard++;
    engine.tickForward();
    events.addAll(engine.drainEvents());
    if (engine.phase != PuttPhase.holePlay) break;
    if (engine.world!.allSettled) break;
  }
  return events;
}

void main() {
  group('PowerUpInventory', () {
    test('caps at 3 and discards the extra', () {
      final inventory = PowerUpInventory();
      expect(inventory.add('a'), isTrue);
      expect(inventory.add('b'), isTrue);
      expect(inventory.add('c'), isTrue);
      expect(inventory.add('d'), isFalse); // cap: discarded, not queued
      expect(inventory.toList(), ['a', 'b', 'c']);
      expect(inventory.isFull, isTrue);
    });

    test('takeFirst and removeById keep the order', () {
      final inventory = PowerUpInventory();
      inventory.add('a');
      inventory.add('b');
      expect(inventory.takeFirst(), 'a');
      expect(inventory.toList(), ['b']);
      inventory.add('c');
      expect(inventory.removeById('c'), isTrue);
      expect(inventory.toList(), ['b']);
      expect(inventory.removeById('nope'), isFalse);
      expect(inventory.takeFirst(), 'b');
      expect(inventory.takeFirst(), isNull); // empty, not an error
    });
  });

  group('caster immunity (hard rule)', () {
    test('a harmful area effect never touches its caster', () {
      final engine = startedEngine(powerUps: only(StormEffect()), boxed: true);
      engine.player('p1')!.inventory.add('test/storm');
      final casterBall = engine.world!.ball('p1')!;
      final othersBefore = engine.world!.ball('p2')!.position;
      expect(engine.usePowerUp('p1', 'test/storm'), isTrue);

      // The caster's egg: untouched. Everyone else: shoved +6 x.
      expect(casterBall.velocity, Vec2.zero);
      final other = engine.world!.ball('p2')!;
      expect(other.velocity.x, closeTo(6, 1e-9));
      expect(other.position, othersBefore); // moves only when time passes
    });

    test('a shield blocks one harmful effect and is consumed', () {
      final engine = startedEngine(powerUps: testRegistry(), boxed: true);
      engine.player('p3')!.inventory
        ..add('test/shell')
        ..add('test/storm');
      engine.player('p2')!.inventory.add('test/storm');
      expect(engine.usePowerUp('p3', 'test/shell'), isTrue); // shield up
      expect(engine.player('p3')!.shields, 1);

      expect(engine.usePowerUp('p3', 'test/storm'), isTrue);
      // p3's own storm: hits p1 and p2, never p3 (caster) - no shield spent.
      expect(engine.player('p3')!.shields, 1);
      engine.drainEvents();

      // p2's storm: p3's shield eats it.
      expect(engine.usePowerUp('p2', 'test/storm'), isTrue);
      final blocked = engine.drainEvents().whereType<ShieldBlocked>().toList();
      expect(blocked.map((b) => b.playerId), ['p3']);
      expect(blocked.single.casterId, 'p2');
      expect(engine.player('p3')!.shields, 0);
      expect(engine.world!.ball('p3')!.velocity, Vec2.zero);
    });
  });

  group('next-shot modifiers', () {
    test('apply once, exactly, then clear', () {
      final engine = startedEngine(powerUps: only(CoffeeEffect()), boxed: true);
      engine.player('p1')!.inventory.add('test/coffee');
      expect(engine.usePowerUp('p1', 'test/coffee'), isTrue);
      expect(engine.player('p1')!.nextShot.powerMultiplier, 1.3);

      // Aimed wide of the nest: the egg must still be out for a second shot.
      final events = driveAndSettle(engine, 'p1', 0.3, 0.5);
      final shot = events
          .whereType<ShotApplied>()
          .where((s) => s.playerId == 'p1')
          .single;
      expect(shot.power, closeTo(0.65, 1e-9)); // 0.5 x 1.3
      expect(engine.player('p1')!.nextShot.isEmpty, isTrue); // consumed

      // The NEXT shot is back to normal.
      final (angle, _) =
          puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
      final second = driveAndSettle(engine, 'p1', angle, 0.5)
          .whereType<ShotApplied>()
          .last;
      expect(second.power, closeTo(0.5, 1e-9));
    });
  });

  group('"?" boxes', () {
    test('a pickup grants a random registered effect', () {
      final engine = startedEngine(powerUps: only(CoffeeEffect()), boxed: true);
      final (angle, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
      // Degree of aim wobble is 0 in this config, so the drive hugs y=8
      // and rolls straight over the box at (12,8) on its way to the nest.
      final driven = driveAndSettle(engine, 'p1', angle, power);
      expect(driven.whereType<PowerUpPicked>().map((p) => p.effectId).toList(),
          ['test/coffee']);
      expect(engine.player('p1')!.inventory.toList(), ['test/coffee']);
    });

    test('a full inventory discards the pickup', () {
      final engine = startedEngine(powerUps: only(CoffeeEffect()), boxed: true);
      final inventory = engine.player('p1')!.inventory;
      inventory
        ..add('test/coffee')
        ..add('test/coffee')
        ..add('test/coffee');
      final (angle, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
      final driven = driveAndSettle(engine, 'p1', angle, power);
      expect(driven.whereType<PowerUpDropped>().map((p) => p.playerId).toList(),
          ['p1']);
      expect(inventory.length, 3);
    });

    test('barnyard chaos doubles the pickup', () {
      final engine = startedEngine(
        powerUps: only(CoffeeEffect()),
        mode: GameMode.barnyardChaos,
        boxed: true,
      );
      engine.drainEvents(); // the two starting deals per player
      expect(engine.player('p1')!.inventory.length, 2);
      final (angle, power) =
          puttFor(engine.currentHole!, engine.world!.ball('p1')!.position);
      final driven = driveAndSettle(engine, 'p1', angle, power);
      // One box, two grant rolls: the first fills the last slot, the second
      // is discarded by the cap (2 held + 1 picked = 3).
      expect(driven.whereType<PowerUpPicked>().length, 1);
      expect(driven.whereType<PowerUpDropped>().length, 1);
      expect(engine.player('p1')!.inventory.length, 3);
    });
  });
}
