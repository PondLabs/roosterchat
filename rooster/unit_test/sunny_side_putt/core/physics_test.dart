// Headless physics scenarios: bounce with restitution, tunnel-proof fast
// shots, water return, the nest cup (drops, skips, lip-outs), boost strips, portal
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
    test('two bumpers facing each other cannot keep an egg for ever', () {
      final hole = boxHole(
        tee: const Vec2(8, 5),
        nest: const Nest(Vec2(14.5, 8.8), 0.8),
        extraWalls: [
          WallSegment.bumper(const Vec2(2, 2), const Vec2(14, 2)),
          WallSegment.bumper(const Vec2(2, 8), const Vec2(14, 8)),
        ],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', -math.pi / 2, 1);
      var bumps = 0;
      var ticks = 0;
      while (!world.allSettled && ticks < 2400) {
        world.stepTick();
        ticks++;
        bumps += world
            .drainEvents()
            .whereType<BallBounced>()
            .where((e) => e.kind == BounceKind.bumper)
            .length;
      }
      expect(world.allSettled, isTrue);
      expect(ticks, lessThan(1200));
      expect(bumps, greaterThan(testPhysics.livelyBounces),
          reason: 'it ping-pongs a while, then the bounces go dead');
      expect(world.ball('a')!.bumps, 0, reason: 'reset once it rests');
    });

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

    group('the nest is a cup', () {
      // A launch-size nest (radius 1.7) on a long flat green. The egg rolls
      // along +x, [offset] off the cup's center line, and reaches the cup's
      // near edge (x = 12.3) at [arrival] units/s.
      PhysicsWorld rollAt(double arrival,
          {double offset = 0, PhysicsConfig config = testPhysics}) {
        final hole = boxHole(
            tee: Vec2(2, 10 + offset),
            nest: const Nest(Vec2(14, 10), 1.7),
            width: 40,
            height: 20);
        final world =
            PhysicsWorld(hole: hole, config: config, playerIds: const ['a']);
        final v0 = math.sqrt(
            arrival * arrival + 2 * config.frictionDeceleration * (12.3 - 2));
        world.applyShot('a', 0, v0 / config.maxShotSpeed);
        return world;
      }

      test('a firm putt through the middle drops', () {
        final world = rollAt(8);
        runUntilSettled(world);
        expect(world.drainEvents().whereType<BallCaptured>(), isNotEmpty);
        expect(world.ball('a')!.holed, isTrue);
        expect(world.ball('a')!.position, const Vec2(14, 10));
      });

      test('a very fast putt skips across', () {
        final world = rollAt(17);
        runUntilSettled(world);
        expect(world.drainEvents().whereType<BallCaptured>(), isEmpty);
        expect(world.ball('a')!.holed, isFalse);
        expect(world.ball('a')!.position.x, greaterThan(20));
      });

      test('a lip hit at pace curls round the rim and spins out, bent', () {
        final world = rollAt(12, offset: 1.5);
        runUntilSettled(world);
        expect(world.drainEvents().whereType<BallCaptured>(), isEmpty);
        final ball = world.ball('a')!;
        expect(ball.holed, isFalse);
        expect(ball.position.x, greaterThan(17));
        // Pulled toward the center: it left well inside the line it came in
        // on (y 11.5).
        expect(ball.position.y, lessThan(11.0));
      });

      test('a medium lip hit curls in and drops', () {
        final world = rollAt(6, offset: 1.5);
        runUntilSettled(world);
        expect(world.ball('a')!.holed, isTrue);
      });

      test('a slow roll that only reaches the edge drops', () {
        // Dies just over the near rim: the funnel takes it, no parking.
        final world = rollAt(1.2, offset: 0.3);
        runUntilSettled(world);
        expect(world.ball('a')!.holed, isTrue);
      });

      test('a firm putt through the middle drops, not skips', () {
        // 12 u/s at the near rim is a firm putt, not a smash: it used to
        // cross the cup dead center and roll straight out the far side.
        final world = rollAt(12);
        runUntilSettled(world);
        expect(world.drainEvents().whereType<BallCaptured>(), isNotEmpty);
        expect(world.ball('a')!.holed, isTrue);
      });

      test('an egg that dies on the lip is drawn in, not parked there', () {
        // Its center stops a hair outside the rim, its body half over the
        // hole: the lip's bevel takes it. It used to rest there for good.
        final world = rollAt(2, offset: 0.9);
        runUntilSettled(world);
        expect(world.ball('a')!.holed, isTrue);
      });

      test('the lip bevel reaches past the rim, and no further', () {
        expect(testPhysics.cupLipReach, greaterThan(1));
        // A putt that dies a whole egg's width outside the rim stays out:
        // the bevel is a lip, not a magnet.
        final world = rollAt(2, offset: 1.5);
        runUntilSettled(world);
        expect(world.ball('a')!.holed, isFalse);
      });

      test('the dead-center speed limit is higher than the lip one', () {
        expect(testPhysics.captureSpeedCentered,
            greaterThan(testPhysics.captureSpeed * 2));
        expect(
            testPhysics.cupPull, greaterThan(testPhysics.frictionDeceleration));
      });

      test('the nest magnet drops a lip hit that would spin out', () {
        final world = rollAt(12, offset: 1.5);
        world.setBallFlagUntilRest('a', PowerUpFlag.magnet);
        runUntilSettled(world);
        expect(world.ball('a')!.holed, isTrue);
      });
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

    group('a boost strip', () {
      // A strip east along y = 5, from x = 10 to 18, in a long box.
      HoleDef stripHole({Vec2 tee = const Vec2(2, 5)}) => boxHole(
            width: 60,
            height: 20,
            tee: tee,
            nest: const Nest(Vec2(58, 18), 0.8),
            boosts: [
              BoostStrip(const Vec2(10, 5), const Vec2(18, 5), speed: 18),
            ],
          );

      /// Rolls the egg until it is clear of the strip (either way) and
      /// returns its velocity then.
      Vec2 throughStrip(PhysicsWorld world, double angle, double power) {
        if (power > 0) world.applyShot('a', angle, power);
        final ball = world.ball('a')!;
        var on = false;
        for (var i = 0; i < 2400 && !ball.asleep; i++) {
          world.stepTick();
          final inside = (ball.position.y - 5).abs() < 1.2 &&
              ball.position.x > 9 &&
              ball.position.x < 19;
          if (inside) on = true;
          if (on && !inside) return ball.velocity;
        }
        return ball.velocity;
      }

      test('speeds an egg already faster than its pace', () {
        final world = PhysicsWorld(
            hole: stripHole(), config: testPhysics, playerIds: const ['a']);
        // Full power: about 25.7 u/s at the strip, well over its 18.
        final out = throughStrip(world, 0, 1);
        final arriving = math.sqrt(26 * 26 - 2 * 7 * 7.1);
        expect(out.x, greaterThan(arriving + 1.5));
        expect(world.drainEvents().whereType<BallBoosted>(), hasLength(1));
      });

      test('raises the cap: a fast egg leaves over maxSpeed, then slows', () {
        final world = PhysicsWorld(
            hole: stripHole(), config: testPhysics, playerIds: const ['a']);
        world.ball('a')!.position = const Vec2(9, 5);
        world.impulseBall('a', const Vec2(29, 0));
        final out = throughStrip(world, 0, 0);
        expect(out.length, greaterThan(testPhysics.maxSpeed));
        expect(out.length, lessThanOrEqualTo(testPhysics.boostMaxSpeed));
        runUntilSettled(world);
        expect(world.ball('a')!.boostCap, 0);
      });

      test('a firm putt gets across against it, a soft one is turned back', () {
        PhysicsWorld from(Vec2 tee) => PhysicsWorld(
            hole: stripHole(tee: tee),
            config: testPhysics,
            playerIds: const ['a']);
        final firm = from(const Vec2(20, 5));
        expect(throughStrip(firm, math.pi, 1).x, lessThan(0));
        expect(firm.ball('a')!.position.x, lessThan(9));
        final soft = from(const Vec2(20, 5));
        expect(throughStrip(soft, math.pi, 0.5).x, greaterThan(0),
            reason: 'pushed back');
        runUntilSettled(soft);
        expect(soft.ball('a')!.position.x, greaterThan(18));
      });

      test('bends an egg crossing it only a little', () {
        final world = PhysicsWorld(
            hole: stripHole(tee: const Vec2(14, 1)),
            config: testPhysics,
            playerIds: const ['a']);
        final out = throughStrip(world, math.pi / 2, 0.6);
        expect(out.y, greaterThan(0));
        expect(math.atan2(out.x, out.y), lessThan(0.35), reason: '< 20 deg');
      });

      test('never lets an egg rest on it', () {
        final world = PhysicsWorld(
            hole: stripHole(tee: const Vec2(12, 5)),
            config: testPhysics,
            playerIds: const ['a']);
        world.ball('a')!.asleep = false;
        runUntilSettled(world);
        expect(world.ball('a')!.position.x, greaterThan(18));
      });

      test('an egg turned back by it never dozes off on it', () {
        // The strip points at the east rail, which bounces the egg back
        // against it again and again; the only rest is past its end.
        final hole = boxHole(
          width: 16,
          tee: const Vec2(2, 5),
          nest: const Nest(Vec2(2, 9), 0.6),
          boosts: [
            BoostStrip(const Vec2(4, 5), const Vec2(13, 5),
                width: 1.2, speed: 14),
          ],
        );
        final world =
            PhysicsWorld(hole: hole, config: testPhysics, playerIds: ['a']);
        world.applyShot('a', 0, 0.4);
        final ball = world.ball('a')!;
        var naps = 0;
        var wasAsleep = false;
        for (var i = 0; i < 7200; i++) {
          world.stepTick();
          if (ball.asleep && !wasAsleep) naps++;
          wasAsleep = ball.asleep;
        }
        expect(naps, 1, reason: 'one rest, at the end');
        expect(ball.asleep, isTrue);
        expect(ball.position.x, greaterThan(13 + 0.6 + 0.225));
      });
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
      // b has putted already (a waiting egg would be a ghost) and rests
      // down the fairway.
      world.ball('b')!
        ..putted = true
        ..position = const Vec2(10, 8);
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

      test('every egg spawns on the tee point, and the stack holds', () {
        final hole = boxHole(
            width: 24,
            height: 16,
            tee: const Vec2(4, 8),
            nest: const Nest(Vec2(20, 8), 0.8));
        final world = PhysicsWorld(
            hole: hole,
            config: testPhysics,
            playerIds: [for (var i = 0; i < 8; i++) 'egg$i']);
        for (var i = 0; i < 240; i++) {
          world.stepTick();
        }
        for (final egg in world.balls) {
          expect(egg.position, hole.tee);
          expect(egg.asleep, isTrue);
        }
        // Every egg putts off the stack at once: none springs off another.
        for (final egg in world.balls) {
          world.applyShot(egg.playerId, 0, 0.4);
        }
        runUntilSettled(world);
        expect(
            world
                .drainEvents()
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isEmpty);
        // A late joiner lands on the tee and goes through the stack too.
        world.addBall('late');
        expect(world.ball('late')!.position, hole.tee);
      });

      test('a joiner onto a putted egg on the tee passes through it', () {
        final world = pair();
        final a = world.ball('a')!..putted = true;
        world.removeBall('b');
        world.addBall('c');
        world.applyShot('c', 0, 0.02);
        a.putted = true;
        world.applyShot('a', math.pi, 0.02);
        runUntilSettled(world);
        expect(
            world
                .drainEvents()
                .whereType<BallBounced>()
                .where((e) => e.kind == BounceKind.ball),
            isEmpty,
            reason: 'both putted before a tick: still no spring apart');
      });

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

      test('a pair drifts apart only a few times a hole', () {
        // Wedged in a corner, two could push, bounce back and push again
        // for ever: set back inside each other after every drift, they
        // stop drifting after the fourth.
        final world = pair();
        final a = world.ball('a')!;
        final b = world.ball('b')!;
        var drifted = 0;
        for (var round = 0; round < 6; round++) {
          a
            ..position = const Vec2(10, 8)
            ..velocity = Vec2.zero
            ..asleep = true;
          b
            ..position = const Vec2(10.3, 8)
            ..velocity = Vec2.zero
            ..asleep = true;
          world.stepTick();
          if (!a.asleep || !b.asleep) drifted++;
          runUntilSettled(world);
        }
        expect(drifted, 4);
        expect(world.toJson()['drifts'], {'a|b': 4});
        final restored = PhysicsWorld.restore(
            hole: world.hole, config: testPhysics, state: world.toJson());
        expect(restored.toJson(), world.toJson());
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
        world.ball('b')!
          ..putted = true
          ..position = const Vec2(10, 8);
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
