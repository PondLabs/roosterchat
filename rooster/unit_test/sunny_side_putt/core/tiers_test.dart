// Tiers: terraces raised flat, the ramps up to them and the ledges they
// drop off - an egg rolling off a lip falls clear of the face, one below
// bounces off it like a rail, a ramp pulls an egg back down that is too
// slow for the climb, and all of it rolls the same way every time.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Two levels and the way between them: the west terrace (x 0..10, a
/// ledge down its east side), the floor, and a ramp from the floor up to
/// the east terrace (x 24..30), railed along its sides, the east
/// terrace's ledges either side of the ramp's top.
HoleDef tiered({List<Hill> hills = const []}) => boxHole(
      width: 30,
      height: 12,
      tee: const Vec2(15, 6),
      nest: const Nest(Vec2(15, 10.5), 0.8),
      terraces: const [
        Terrace([Vec2(0, 0), Vec2(0, 12), Vec2(10, 12), Vec2(10, 0)],
            height: 1),
        Terrace([Vec2(24, 0), Vec2(24, 12), Vec2(30, 12), Vec2(30, 0)],
            height: 1),
      ],
      ramps: const [Ramp(Vec2(20, 6), Vec2(24, 6), width: 4, height: 1)],
      extraWalls: [
        WallSegment.ledge(const Vec2(10, 12), const Vec2(10, 0)),
        WallSegment.ledge(const Vec2(24, 0), const Vec2(24, 4)),
        WallSegment.ledge(const Vec2(24, 8), const Vec2(24, 12)),
        const WallSegment(Vec2(20, 4), Vec2(24, 4)),
        const WallSegment(Vec2(20, 8), Vec2(24, 8)),
      ],
      hills: hills,
    );

/// A square terrace standing free on the floor, a ledge down every side.
HoleDef island() => boxHole(
      width: 20,
      height: 12,
      tee: const Vec2(3, 6),
      nest: const Nest(Vec2(17, 10), 0.8),
      terraces: const [
        Terrace([Vec2(8, 4), Vec2(8, 8), Vec2(12, 8), Vec2(12, 4)], height: 1),
      ],
      extraWalls: [
        WallSegment.ledge(const Vec2(8, 4), const Vec2(8, 8)),
        WallSegment.ledge(const Vec2(8, 8), const Vec2(12, 8)),
        WallSegment.ledge(const Vec2(12, 8), const Vec2(12, 4)),
        WallSegment.ledge(const Vec2(12, 4), const Vec2(8, 4)),
      ],
    );

PhysicsWorld worldOn(HoleDef hole, [List<String> ids = const ['a']]) =>
    PhysicsWorld(hole: hole, config: testPhysics, playerIds: ids);

void main() {
  group('the tiers\' ground', () {
    test('a terrace stands flat at its height inside its outline', () {
      const terrace = Terrace([Vec2(0, 0), Vec2(0, 4), Vec2(6, 4), Vec2(6, 0)],
          height: 1.2);
      expect(terrace.contains(const Vec2(3, 2)), isTrue);
      expect(terrace.contains(const Vec2(7, 2)), isFalse);
      expect(terrace.heightAt(const Vec2(5.9, 0.1)), 1.2);
      expect(terrace.heightAt(const Vec2(-0.1, 2)), 0);
      // Counter-clockwise as drawn (y down): a negative shoelace sum.
      expect(terrace.signedArea2, lessThan(0));
      expect(terrace.edge(3), (const Vec2(6, 0), const Vec2(0, 0)));
    });

    test('a ramp rises smoothly from its foot to its top, level across', () {
      const ramp = Ramp(Vec2(2, 5), Vec2(6, 5), width: 3, height: 1);
      expect(ramp.heightAt(const Vec2(2, 5)), 0);
      expect(ramp.heightAt(const Vec2(6, 5)), closeTo(1, 1e-12));
      expect(ramp.heightAt(const Vec2(4, 5)), closeTo(0.5, 1e-12));
      expect(ramp.heightAt(const Vec2(4, 6.4)), closeTo(0.5, 1e-12));
      expect(ramp.heightAt(const Vec2(4, 6.6)), 0, reason: 'off its width');
      expect(ramp.heightAt(const Vec2(6.1, 5)), 0, reason: 'past its top');
      expect(ramp.gradientAt(const Vec2(2, 5)), Vec2.zero);
      expect(ramp.gradientAt(const Vec2(6, 5)).length, closeTo(0, 1e-12));
      // The steepest grade, halfway: 1.5 * height / length.
      expect(ramp.gradientAt(const Vec2(4, 5)).x, closeTo(1.5 / 4, 1e-12));
      expect(ramp.gradientAt(const Vec2(4, 5)).y, 0);
      expect(ramp.covers(const Vec2(5, 3.6)), isTrue);
      expect(ramp.covers(const Vec2(1.9, 5)), isFalse);
    });

    test('a ramp\'s gradient is the slope of its height, pointing up it', () {
      const ramp = Ramp(Vec2(3, 9), Vec2(7, 4), width: 4, height: 1.3);
      const e = 1e-6;
      for (final t in const [0.2, 0.45, 0.8]) {
        final p = ramp.from.lerp(ramp.to, t) + const Vec2(0.4, 0.3);
        final dx = (ramp.heightAt(p + const Vec2(e, 0)) -
                ramp.heightAt(p - const Vec2(e, 0))) /
            (2 * e);
        final dy = (ramp.heightAt(p + const Vec2(0, e)) -
                ramp.heightAt(p - const Vec2(0, e))) /
            (2 * e);
        final gradient = ramp.gradientAt(p);
        expect(gradient.x, closeTo(dx, 1e-5));
        expect(gradient.y, closeTo(dy, 1e-5));
        expect(gradient.dot(ramp.to - ramp.from), greaterThan(0));
      }
    });

    test('a ramp names its sides and its top, the ramp between', () {
      const ramp = Ramp(Vec2(20, 6), Vec2(24, 6), width: 4, height: 1);
      final (left, right) = ramp.sides;
      // Walking up the ramp (east), the left side is the north one.
      expect(left, (const Vec2(20, 4), const Vec2(24, 4)));
      expect(right, (const Vec2(20, 8), const Vec2(24, 8)));
      expect(ramp.top, (const Vec2(24, 4), const Vec2(24, 8)));
    });

    test('a hole stands on its tiers: the terrace, the ramp, the floor', () {
      final hole = tiered();
      expect(hole.hasRelief, isTrue);
      expect(hole.groundHeightAt(const Vec2(5, 6)), 1);
      expect(hole.groundHeightAt(const Vec2(15, 6)), 0);
      expect(hole.groundHeightAt(const Vec2(22, 6)), closeTo(0.5, 1e-12));
      expect(hole.groundHeightAt(const Vec2(23.999, 6)), closeTo(1, 1e-6));
      expect(hole.groundHeightAt(const Vec2(27, 6)), 1);
      expect(hole.groundGradientAt(const Vec2(5, 6)), Vec2.zero);
      expect(hole.groundGradientAt(const Vec2(22, 6)).x, greaterThan(0));
      expect(boxHole().hasRelief, isFalse);
    });

    test('a ledge\'s high side is the left of its run as drawn', () {
      final ledge = WallSegment.ledge(const Vec2(10, 12), const Vec2(10, 0));
      expect(ledge.ledge, isTrue);
      // Running north, the left as drawn is west.
      expect(ledge.highSide.x, closeTo(-1, 1e-12));
      expect(ledge.highSide.y, closeTo(0, 1e-12));
      expect(const WallSegment(Vec2.zero, Vec2(1, 0)).ledge, isFalse);
    });
  });

  group('a ledge', () {
    test('lets an egg roll off its lip and drop to the floor', () {
      final world = worldOn(tiered());
      world.teleportBall('a', const Vec2(5, 6));
      world.applyShot('a', 0, 0.45);
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, greaterThan(10.45));
      expect(world.drainEvents().whereType<BallDropped>(), hasLength(1));
    });

    test('carries a slow egg clear of its face as it falls', () {
      final world = worldOn(tiered());
      world.teleportBall('a', const Vec2(9.95, 6));
      world.impulseBall('a', const Vec2(1, 0.3));
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      // Off the lip and past an egg's radius from the face: never left
      // resting inside the step.
      expect(ball.position.x, greaterThan(10 + testPhysics.ballRadius));
      expect(ball.position.y, greaterThan(6));
    });

    test('bounces an egg off its face from below, like a rail', () {
      final world = worldOn(tiered());
      world.applyShot('a', math.pi, 0.5);
      final speedIn = world.ball('a')!.speed;
      var nearest = double.infinity;
      for (var i = 0; i < 2400 && !world.allSettled; i++) {
        world.stepTick();
        nearest = math.min(nearest, world.ball('a')!.position.x);
      }
      final ball = world.ball('a')!;
      // It came up to the face and no further.
      expect(nearest, greaterThan(10 + testPhysics.ballRadius - 1e-6));
      expect(nearest, lessThan(10.6));
      expect(ball.position.x, greaterThan(10.45));
      final bounces = world.drainEvents().whereType<BallBounced>().toList();
      expect(bounces.map((e) => e.kind), contains(BounceKind.wall));
      expect(bounces.first.impactSpeed, lessThan(speedIn));
    });

    test('holds an egg a slope presses into its face from below', () {
      // The mound's skirt reaches the ledge's foot from the floor: its
      // pull leans the egg on the face, where it must settle, not rattle.
      final world = worldOn(tiered(hills: const [
        Hill.mound(Vec2(13, 6), height: 1, skirt: 3),
      ]));
      world.teleportBall('a', const Vec2(11.6, 6));
      final ticks = runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ticks, lessThan(600));
      expect(ball.asleep, isTrue);
      expect(ball.position.x, closeTo(10.45, 0.01));
      final at = ball.position;
      for (var i = 0; i < 240; i++) {
        world.stepTick();
      }
      expect(ball.position, at);
    });

    test('never holds an egg from above: a slope rolls it over the lip', () {
      final world = worldOn(tiered(hills: const [
        Hill.mound(Vec2(7, 6), height: 1, skirt: 3),
      ]));
      world.teleportBall('a', const Vec2(8.73, 6));
      runUntilSettled(world);
      expect(world.ball('a')!.position.x, greaterThan(10.45));
    });

    test('leaves an egg resting over its lip where it is', () {
      final world = worldOn(tiered());
      world.teleportBall('a', const Vec2(9.8, 6));
      runUntilSettled(world);
      for (var i = 0; i < 120; i++) {
        world.stepTick();
      }
      expect(world.ball('a')!.position, const Vec2(9.8, 6));
    });

    test('a terrace standing free keeps eggs out from every side', () {
      // Shots at the square from all round, its corners included: none
      // ever gets its centre onto the terrace.
      for (var k = 0; k < 48; k++) {
        final angle = k / 48 * 2 * math.pi;
        final from =
            const Vec2(10, 6) + Vec2(math.cos(angle), math.sin(angle)) * 3.9;
        final world = worldOn(island());
        world.teleportBall('a', from);
        world.applyShot('a', (const Vec2(10, 6) - from).angle, 0.55);
        for (var i = 0; i < 1800 && !world.allSettled; i++) {
          world.stepTick();
          final p = world.ball('a')!.position;
          final inside = p.x > 8 && p.x < 12 && p.y > 4 && p.y < 8;
          expect(inside, isFalse, reason: 'from $from, tick $i at $p');
        }
      }
    });

    test('a terrace standing free drops eggs off every side', () {
      for (var k = 0; k < 48; k++) {
        final angle = k / 48 * 2 * math.pi;
        final world = worldOn(island());
        world.teleportBall('a', const Vec2(10, 6));
        world.applyShot('a', angle, 0.3);
        runUntilSettled(world);
        final p = world.ball('a')!.position;
        final dx = math.max(0.0, math.max(8 - p.x, p.x - 12));
        final dy = math.max(0.0, math.max(4 - p.y, p.y - 8));
        expect(
            math.sqrt(dx * dx + dy * dy), greaterThan(testPhysics.ballRadius),
            reason: 'angle $angle settled at $p');
      }
    });
  });

  test('eggs a step apart pass over and under each other', () {
    // One hangs over the lip, one rests at the face's foot right below
    // it: a step apart, they never touch.
    // (Both have putted: eggs still waiting to putt are ghosts anyway.)
    final world = worldOn(tiered(), const ['a', 'b']);
    for (final id in const ['a', 'b']) {
      world.ball(id)!.putted = true;
    }
    world.teleportBall('a', const Vec2(9.9, 6));
    world.teleportBall('b', const Vec2(10.46, 6));
    runUntilSettled(world);
    expect(world.ball('a')!.position, const Vec2(9.9, 6));
    expect(world.ball('b')!.position, const Vec2(10.46, 6));
    expect(world.drainEvents().whereType<BallBounced>(), isEmpty);
    // On one level, the same overlap pushes them apart.
    final flat = worldOn(boxHole(), const ['a', 'b']);
    for (final id in const ['a', 'b']) {
      flat.ball(id)!.putted = true;
    }
    flat.teleportBall('a', const Vec2(9.9, 6));
    flat.teleportBall('b', const Vec2(10.46, 6));
    runUntilSettled(flat);
    expect(flat.ball('a')!.position.distanceTo(flat.ball('b')!.position),
        greaterThan(0.899));
  });

  group('a ramp', () {
    test('pulls an egg left on its slope back down to its foot', () {
      // Its pull beats the rolling friction except near the ends (t under
      // about a quarter, or over three quarters), where an egg can rest.
      final world = worldOn(tiered());
      world.teleportBall('a', const Vec2(22, 6));
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, lessThan(21.1));
    });

    test('rolls an egg too slow for the climb back down', () {
      // Flat, this putt would stop past the ramp's top at x = 24.
      final world = worldOn(tiered());
      world.applyShot('a', 0,
          puttStopPower(tiered(), const Vec2(15, 6), const Vec2(24.6, 6)));
      var highest = 0.0;
      for (var i = 0; i < 4800 && !world.allSettled; i++) {
        world.stepTick();
        highest = math.max(highest, world.ball('a')!.position.x);
      }
      final ball = world.ball('a')!;
      expect(highest, greaterThan(22), reason: 'it went up the ramp');
      expect(ball.asleep, isTrue);
      expect(ball.position.x, lessThan(21.1));
    });

    test('carries an egg with the pace up onto the terrace', () {
      // The climb takes 2 * slopeGravity * height of v^2 on top of the
      // roll's friction.
      final v0 = math.sqrt(2 * testPhysics.frictionDeceleration * 10.5 +
          2 * testPhysics.slopeGravity * 1 +
          0.6 * 0.6);
      final world = worldOn(tiered());
      world.applyShot('a', 0, v0 / testPhysics.maxShotSpeed);
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, closeTo(25.5, 0.25));
    });

    test('its rails keep a climbing egg on it', () {
      final world = worldOn(tiered());
      world.teleportBall('a', const Vec2(19, 6));
      world.applyShot('a', -0.6, 0.7);
      var off = false;
      for (var i = 0; i < 2400 && !world.allSettled; i++) {
        world.stepTick();
        final p = world.ball('a')!.position;
        if (p.x > 20.2 && p.x < 23.8 && (p.y < 4 || p.y > 8)) off = true;
      }
      expect(off, isFalse);
    });
  });

  test('tiers roll the same way every time, and through a snapshot', () {
    Map<String, Object?> roll({int? snapshotAt}) {
      var world = worldOn(tiered(), const ['a', 'b']);
      world.teleportBall('a', const Vec2(4, 3));
      world.applyShot('a', 0.35, 0.8);
      world.applyShot('b', -0.05, 0.62);
      for (var i = 0; i < 2400; i++) {
        if (i == snapshotAt) {
          world = PhysicsWorld.restore(
              hole: tiered(), config: testPhysics, state: world.toJson());
        }
        world.stepTick();
      }
      return world.toJson();
    }

    final first = roll();
    expect(roll().toString(), first.toString());
    expect(roll(snapshotAt: 140).toString(), first.toString());
  });
}
