// Headless physics scenarios: bounce with restitution, tunnel-proof fast
// shots, water return, the nest capture speed gate, boost strips, portal
// speed preservation, gravity-well attraction and swallow, the hen's
// nudge, the "?" box pickup, plus the determinism contract itself.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('PhysicsWorld scenarios', () {
    test('bounces lose energy per the wall restitution', () {
      // Egg at (2,5); wall x=16; full-ish shot right. Rolling friction 7.
      final hole =
          boxHole(tee: const Vec2(2, 5), nest: const Nest(Vec2(2.5, 8.5), 0.8));
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.8); // 20.8 u/s
      runUntilSettled(world);

      final bounces = world.drainEvents().whereType<BallBounced>().toList();
      final wallBounce = bounces.firstWhere((e) => e.kind == BounceKind.wall);
      // Impact speed: sqrt(20.8^2 - 2*7*13.55) ~ 15.6.
      expect(wallBounce.impactSpeed, closeTo(15.6, 0.6));
      final ball = world.ball('a')!;
      // Reflected at 0.7: rolls back ~8.5 units from the wall.
      expect(ball.position.x, inExclusiveRange(6, 9.5));
      expect(ball.asleep, isTrue);
      expect(ball.velocity, Vec2.zero);
    });

    test('a max-speed egg cannot tunnel a zero-thickness wall', () {
      final hole = boxHole(
        width: 16,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        extraWalls: [WallSegment(const Vec2(8, 2), const Vec2(8, 8))],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 1.0); // 26 u/s straight at the wall
      runUntilSettled(world);

      final bounces = world.drainEvents().whereType<BallBounced>().toList();
      expect(bounces.map((e) => e.kind), contains(BounceKind.wall));
      expect(world.ball('a')!.position.x, lessThan(8));
    });

    test('an arc wall (round pillar) bounces eggs too', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        arcs: [
          WallArc.custom(const Vec2(8, 5), 1.2,
              startAngle: 0, sweep: 2 * math.pi),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.5); // dead center into the pillar
      runUntilSettled(world);

      final bounces = world.drainEvents().whereType<BallBounced>().toList();
      expect(bounces.map((e) => e.kind), contains(BounceKind.arc));
      // Bounced straight back: it never got around the pillar.
      expect(world.ball('a')!.position.x, lessThan(8 - 1.2 - 0.45));
    });

    test('an absurdly fast egg also bounces (sweep works at any speed)', () {
      final hole = boxHole(
        width: 16,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        extraWalls: [WallSegment(const Vec2(8, 2), const Vec2(8, 8))],
      );
      // 60 u/s: 0.5 units per tick against a wall with no thickness.
      final config = const PhysicsConfig(maxShotSpeed: 60, maxSpeed: 120);
      final world =
          PhysicsWorld(hole: hole, config: config, playerIds: const ['a']);
      world.applyShot('a', 0, 1.0);
      runUntilSettled(world, maxTicks: 4000);

      final bounces = world.drainEvents().whereType<BallBounced>().toList();
      expect(bounces.map((e) => e.kind), contains(BounceKind.wall));
      expect(world.ball('a')!.position.x, lessThan(8));
    });

    test('water returns the egg to its pre-stroke position', () {
      final hole = boxHole(
        water: [WaterRect(Rect(const Vec2(8, 3.5), const Vec2(12, 6.5)))],
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.6); // rolls straight through the pond
      runUntilSettled(world);

      final events = world.drainEvents();
      expect(events.whereType<BallSplashed>(), isNotEmpty);
      final ball = world.ball('a')!;
      expect(ball.position.approximates(const Vec2(2, 5)), isTrue);
      expect(ball.asleep, isTrue);
      // The stroke was the caller's business (rules engine); physics set
      // the egg down precisely where the stroke began.
      expect(ball.position, ball.lastSafePosition);
    });

    test('polygon water also catches eggs', () {
      final hole = boxHole(
        water: [
          WaterPolygon([
            const Vec2(8, 3),
            const Vec2(12, 3),
            const Vec2(12, 7),
            const Vec2(8, 7),
          ]),
        ],
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.7);
      runUntilSettled(world);
      expect(world.drainEvents().whereType<BallSplashed>(), isNotEmpty);
      expect(world.ball('a')!.position.approximates(const Vec2(2, 5)), isTrue);
    });

    test('the nest captures slow eggs, fast eggs roll across', () {
      // fricção do hole: 4; capture zone at 3.425 from the tee.
      final hole = boxHole(
          tee: const Vec2(2, 5),
          nest: const Nest(Vec2(6, 5), 0.8),
          friction: 4);
      final slow =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      slow.applyShot('a', 0, 0.216); // arrives inside the zone under 3 u/s
      runUntilSettled(slow);
      final slowEvents = slow.drainEvents();
      expect(slowEvents.whereType<BallCaptured>(), isNotEmpty);
      expect(slow.ball('a')!.holed, isTrue);
      expect(slow.ball('a')!.position, hole.nest.position);

      final fast =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      fast.applyShot('a', 0, 0.5); // arrival ~7 u/s: rolls across the nest
      runUntilSettled(fast);
      final fastEvents = fast.drainEvents();
      expect(fastEvents.whereType<BallCaptured>(), isEmpty);
      final fastBall = fast.ball('a')!;
      expect(fastBall.holed, isFalse);
      expect(fastBall.position.distanceTo(hole.nest.position), greaterThan(1));
    });

    test('boost strips raise speed along their direction', () {
      final hole = boxHole(
        width: 40,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(6, 8.5), 0.8),
        boosts: [
          BoostStrip(const Vec2(5, 5), const Vec2(9, 5), width: 1.2, speed: 18),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.3); // ambles onto the strip at ~6 u/s
      runUntilSettled(world);

      final events = world.drainEvents();
      expect(events.whereType<BallBoosted>(), isNotEmpty);
      // Carried far beyond what ~6 u/s could give (~1.3 units of roll).
      expect(world.ball('a')!.position.x, greaterThan(20));
      expect(world.ball('a')!.position.y, closeTo(5, 1e-6));
    });

    test('portals swap position and preserve speed exactly', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        portals: [
          PortalPair('burrow', const Vec2(8, 5), const Vec2(12, 2),
              radius: 0.9),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.45);
      var speedBeforeTeleport = 0.0;
      for (var i = 0; i < 3600; i++) {
        world.stepTick();
        final teleports =
            world.drainEvents().whereType<BallTeleported>().toList();
        if (teleports.isNotEmpty) {
          expect(teleports.single.portalId, 'burrow');
          final ball = world.ball('a')!;
          expect(ball.position.approximates(const Vec2(12, 2), 1e-6), isTrue);
          // Same speed through the portal (at most one tick of friction
          // between the two readings), same direction.
          expect(ball.speed, closeTo(speedBeforeTeleport, 0.15));
          expect(ball.velocity.x, greaterThan(0));
          expect(ball.velocity.y.abs(), closeTo(0, 1e-9));
          break;
        }
        speedBeforeTeleport = world.ball('a')!.speed;
      }
      runUntilSettled(world);
      expect(world.ball('a')!.position.x, greaterThan(12.3));
    });

    test('a slow egg pops out of a rabbit hole and stays out', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        portals: [
          PortalPair('burrow', const Vec2(5, 5), const Vec2(12, 2),
              radius: 0.9),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      // Arrives at the hole at about 1.5 units/s.
      world.applyShot('a', 0,
          puttStopPower(hole, hole.tee, const Vec2(4.3, 5), arrivalSpeed: 1.5));
      runUntilSettled(world);
      final teleports =
          world.drainEvents().whereType<BallTeleported>().toList();
      expect(teleports, hasLength(1), reason: 'no ping-pong between ends');
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.distanceTo(const Vec2(12, 2)), greaterThan(0.9),
          reason: 'it rolled clear of the exit');
    });

    test('an egg inside a ring of wall bounces off its inside face', () {
      final hole = boxHole(
        width: 30,
        height: 20,
        tee: const Vec2(15, 10),
        nest: const Nest(Vec2(15, 13), 0.8),
        arcs: [
          WallArc.custom(const Vec2(15, 10), 6,
              startAngle: 0, sweep: 2 * math.pi),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.7); // 18.2 u/s toward the ring's east side
      var bounced = false;
      for (var i = 0; i < 600 && !bounced; i++) {
        world.stepTick();
        bounced = world
            .drainEvents()
            .whereType<BallBounced>()
            .any((e) => e.kind == BounceKind.arc);
      }
      expect(bounced, isTrue);
      final ball = world.ball('a')!;
      expect(ball.velocity.x, lessThan(-5), reason: 'it came back with pace');
      runUntilSettled(world);
      expect(world.ball('a')!.position.distanceTo(const Vec2(15, 10)),
          lessThan(6 - 0.45 + 1e-6));
    });

    test('the silo pulls resting eggs toward it (pure attractor)', () {
      final hole = boxHole(
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        wells: [
          // 3.5 units from the tee: pull (30/3.5 ~ 8.6) beats friction 7.
          GravityWell(const Vec2(5.5, 5),
              radius: 4, strength: 30, captureRadius: 0),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      final wellAt = const Vec2(5.5, 5);
      world.stepTick(); // wakes it (pull 8.6 > friction 7)
      var closest = world.ball('a')!.position.distanceTo(wellAt);
      for (var i = 0; i < 360; i++) {
        world.stepTick(); // 3 s of being pulled
        closest =
            math.min(closest, world.ball('a')!.position.distanceTo(wellAt));
      }
      // It crossed the well's center region.
      expect(closest, lessThan(1.0));
    });

    test('a strong silo swallows eggs, which return home like water', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        wells: [GravityWell(const Vec2(12, 5), radius: 4, strength: 60)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.6); // rolls into the pull, gets sucked in
      runUntilSettled(world);

      final events = world.drainEvents();
      expect(events.whereType<BallSwallowed>(), isNotEmpty);
      // The pre-stroke spot (2,5) sits inside the pull, so the safe-home
      // net picks nowhere better: the egg rests where the stroke began
      // (content authors keep tees out of wells; text covers the fallback).
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.velocity, Vec2.zero);
    });

    test('the hen nudges sleeping eggs by contact', () {
      final hole = boxHole(
        width: 20,
        tee: const Vec2(8, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        obstacles: [
          MovingObstacle(
            id: 'hen',
            radius: 0.9,
            stops: [
              ObstacleStop(const Vec2(4, 5), dwellSeconds: 0.3),
              ObstacleStop(const Vec2(11, 5), dwellSeconds: 4),
            ],
          ),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      final events = <PhysicsEvent>[];
      Vec2 peak = world.ball('a')!.position;
      for (var i = 0; i < 720; i++) {
        // 6 s: the hen walks from (4,5) over the egg and dwells at (11,5).
        world.stepTick();
        events.addAll(world.drainEvents());
        final position = world.ball('a')!.position;
        if (position.x > peak.x) peak = position;
      }
      expect(
          events
              .where((e) => e is BallBounced && e.kind == BounceKind.obstacle),
          isNotEmpty);
      // Shoved along by the hen, then settled during its long dwell.
      expect(peak.x, greaterThan(8.5));
      expect(world.ball('a')!.asleep, isTrue);
    });

    test("a '?' box is picked up once and only once", () {
      final hole = boxHole(
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        boxes: [QuestionBox('carton', const Vec2(6, 5))],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.7); // rolls through, bounces around
      runUntilSettled(world, maxTicks: 3600);
      var pickups = 0;
      for (final event in world.drainEvents()) {
        if (event is BallPickedBox) pickups++;
      }
      expect(pickups, 1);
    });

    test('ghost passes through walls; hop passes over the hen but not walls',
        () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        extraWalls: [WallSegment(const Vec2(8, 2), const Vec2(8, 8))],
        obstacles: [
          MovingObstacle(
            id: 'hen',
            radius: 0.9,
            stops: [ObstacleStop(const Vec2(10.5, 5), dwellSeconds: 10)],
          ),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.setBallFlagFor('a', PowerUpFlag.ghost, 600); // 5 s of ghost
      world.applyShot('a', 0, 0.4);
      runUntilSettled(world);
      final events = world.drainEvents();
      expect(
        events.where((e) => e is BallBounced && e.kind == BounceKind.wall),
        isEmpty,
      );
      // Straight through the wall, stopped before the course edge.
      expect(world.ball('a')!.position.x, greaterThan(8));
      expect(world.ball('a')!.position.x, lessThan(15));

      final hopped =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      hopped.setBallFlagUntilRest('a', PowerUpFlag.hop);
      hopped.applyShot('a', 0, 0.4);
      runUntilSettled(hopped);
      final hoppedEvents = hopped.drainEvents();
      expect(
        hoppedEvents
            .where((e) => e is BallBounced && e.kind == BounceKind.obstacle),
        isEmpty,
      );
      // But the wall is still solid.
      expect(
        hoppedEvents
            .where((e) => e is BallBounced && e.kind == BounceKind.wall),
        isNotEmpty,
      );
      expect(hopped.ball('a')!.position.x, lessThan(8));
    });

    test('egg-egg contact is symmetric and wakes sleepers', () {
      final hole = boxHole(
          width: 24,
          height: 16,
          tee: const Vec2(4, 8),
          nest: const Nest(Vec2(20, 8), 0.8));
      final world = PhysicsWorld(
          hole: hole, config: testPhysics, playerIds: const ['a', 'b']);
      // b has putted already: a waiting egg would be a ghost.
      world.ball('b')!.putted = true;
      final from = world.ball('a')!.position;
      final target = world.ball('b')!.position;
      world.applyShot('a', (target - from).angle, 0.5);
      runUntilSettled(world);
      final ballEvents = world
          .drainEvents()
          .whereType<BallBounced>()
          .where((e) => e.kind == BounceKind.ball)
          .toList();
      expect(ballEvents.length, 2); // one event per egg in the pair
      expect(ballEvents.first.impactSpeed, greaterThan(5));
      // The struck egg was knocked away from the shooter.
      expect(
        world.ball('b')!.position.distanceTo(world.ball('a')!.position),
        greaterThan(0.5),
      );
    });

    group('eggs that have not putted are ghosts', () {
      PhysicsWorld pair() => PhysicsWorld(
          hole: boxHole(
              width: 24,
              height: 16,
              tee: const Vec2(4, 8),
              nest: const Nest(Vec2(20, 8), 0.8)),
          config: testPhysics,
          playerIds: const ['a', 'b']);

      test('a putt off the tee rolls through an egg still waiting', () {
        final world = pair();
        final before = world.ball('b')!.position;
        final from = world.ball('a')!.position;
        world.applyShot('a', (before - from).angle, 0.5);
        runUntilSettled(world);
        final events = world.drainEvents();
        expect(
            events
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isEmpty);
        expect(events.whereType<BallKnocked>(), isEmpty);
        expect(world.ball('b')!.position, before, reason: 'never knocked');
        expect(world.ball('a')!.putted, isTrue);
        expect(world.ball('b')!.putted, isFalse);
      });

      test('a putted egg that stops inside a waiting one rolls clear of it',
          () {
        final world = pair();
        final b = world.ball('b')!;
        final a = world.ball('a')!..position = b.position + const Vec2(0.3, 0);
        a.putted = true;
        final waiting = b.position;
        world.stepTick();
        runUntilSettled(world);
        expect(a.position.distanceTo(b.position),
            greaterThan(testPhysics.ballRadius * 2 * 0.95),
            reason: 'clear of each other');
        expect(b.position, waiting, reason: 'the waiting egg stays put');
        expect(
            world
                .drainEvents()
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isEmpty,
            reason: 'no knock');
      });

      test('two waiting eggs set inside each other drift apart, half each', () {
        final world = pair();
        final b = world.ball('b')!;
        final a = world.ball('a')!..position = b.position + const Vec2(0.3, 0);
        final middle = (a.position + b.position) * 0.5;
        world.stepTick();
        runUntilSettled(world);
        expect(a.position.distanceTo(b.position),
            greaterThan(testPhysics.ballRadius * 2 * 0.95));
        expect(((a.position + b.position) * 0.5).distanceTo(middle),
            lessThan(0.05));
      });

      test('two that met as ghosts pass through until they part', () {
        final world = pair();
        final b = world.ball('b')!;
        final a = world.ball('a')!..position = b.position + const Vec2(0.3, 0);
        world.stepTick();
        // b putts (a soft one, away from a), a has putted too: both solid,
        // but they still overlap, and do not spring apart.
        a.putted = true;
        world.applyShot('b', math.pi, 0.02);
        world.stepTick();
        expect(
            world
                .drainEvents()
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isEmpty,
            reason: 'no spring apart');
        runUntilSettled(world);
        // Parted, they meet as eggs again.
        world.drainEvents();
        world.applyShot('a', (b.position - a.position).angle, 0.5);
        runUntilSettled(world);
        expect(
            world
                .drainEvents()
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isNotEmpty);
      });

      test('a resting egg knocked by another hears who did it', () {
        final world = pair();
        world.ball('b')!.putted = true;
        final from = world.ball('a')!.position;
        final target = world.ball('b')!.position;
        world.applyShot('a', (target - from).angle, 0.5);
        runUntilSettled(world);
        final knocks = world.drainEvents().whereType<BallKnocked>().toList();
        expect(knocks, hasLength(1));
        expect(knocks.single.playerId, 'b');
        expect(knocks.single.byPlayerId, 'a');
      });

      test('a snapshot keeps who has putted and who is passing through', () {
        final world = pair();
        final b = world.ball('b')!;
        world.ball('a')!.position = b.position + const Vec2(0.3, 0);
        world.stepTick();
        world.applyShot('a', 0, 0.01);
        final state = world.toJson();
        expect(state['passing'], ['a|b']);
        final restored = PhysicsWorld.restore(
            hole: world.hole, config: testPhysics, state: state);
        expect(restored.ball('a')!.putted, isTrue);
        expect(restored.ball('b')!.putted, isFalse);
        expect(restored.toJson(), state);
      });
    });

    test('same seed and inputs, same world, bit for bit', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13, 2.5), 0.8),
        extraWalls: [
          WallSegment(const Vec2(8, 2), const Vec2(8, 4.2)),
          WallSegment(const Vec2(10, 9), const Vec2(13, 6)),
        ],
        water: [WaterCircle(const Vec2(9, 8.5), 1.4)],
      );
      PhysicsWorld simulate() {
        final world = PhysicsWorld(
            hole: hole, config: testPhysics, playerIds: const ['a', 'b']);
        world.applyShot('a', 0, 0.55);
        world.applyShot('b', 0.06, 0.5);
        for (var i = 0; i < 600; i++) {
          world.stepTick();
        }
        return world;
      }

      final first = simulate();
      final second = simulate();
      expect(second.toJson(), first.toJson());
      expect(first.allHoled, isFalse); // sane fixture: nobody lucked in
    });

    test('serialization restores a rolling world exactly', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13, 5), 0.8),
        boosts: [BoostStrip(const Vec2(9, 5), const Vec2(11, 5), speed: 14)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.7);
      for (var i = 0; i < 50; i++) {
        world.stepTick();
      }
      final restored = PhysicsWorld.restore(
          hole: hole, config: testPhysics, state: world.toJson());
      // Both continue; they must agree tick for tick.
      for (var i = 0; i < 300; i++) {
        world.stepTick();
        restored.stepTick();
      }
      expect(restored.toJson(), world.toJson());
    });
  });
}
