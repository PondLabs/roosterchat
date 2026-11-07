// Hills: the ground's relief (mounds, ridges, dips, plateaus) and the
// pull it puts on an egg - rolling back down a ridge it could not crest,
// running off a steep flank, gathering in a dip, resting against a rail
// it was pulled into.
library;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Hill', () {
    const mound = Hill.mound(Vec2(10, 5), height: 1.2, top: 0.5, skirt: 3);

    test('is flat on its plateau and off its reach, smooth between', () {
      expect(mound.heightAt(const Vec2(10, 5)), 1.2);
      expect(mound.heightAt(const Vec2(10.4, 5)), 1.2);
      expect(mound.heightAt(const Vec2(13.5, 5)), 0);
      expect(mound.heightAt(const Vec2(14, 5)), 0);
      expect(mound.gradientAt(const Vec2(10.2, 5)), Vec2.zero);
      expect(mound.gradientAt(const Vec2(14, 5)), Vec2.zero);
      expect(mound.heightAt(const Vec2(12, 5)), inExclusiveRange(0, 1.2));
      expect(mound.reach, 3.5);
    });

    test('its gradient is the slope of its height, pointing uphill', () {
      const e = 1e-5;
      for (final p in const [
        Vec2(11.3, 5.2),
        Vec2(8.1, 6.4),
        Vec2(10.5, 2.7)
      ]) {
        final dx = (mound.heightAt(p + const Vec2(e, 0)) -
                mound.heightAt(p - const Vec2(e, 0))) /
            (2 * e);
        final dy = (mound.heightAt(p + const Vec2(0, e)) -
                mound.heightAt(p - const Vec2(0, e))) /
            (2 * e);
        final gradient = mound.gradientAt(p);
        expect(gradient.x, closeTo(dx, 1e-5));
        expect(gradient.y, closeTo(dy, 1e-5));
        expect(gradient.dot(const Vec2(10, 5) - p), greaterThan(0));
      }
    });

    test('a ridge runs along its spine; a dip points its slope outward', () {
      const ridge = Hill(Vec2(4, 2), Vec2(4, 8), height: 0.8, skirt: 2);
      expect(ridge.heightAt(const Vec2(4, 5)), 0.8);
      expect(ridge.heightAt(const Vec2(4, 2)), 0.8);
      expect(ridge.heightAt(const Vec2(5, 5)),
          closeTo(ridge.heightAt(const Vec2(5, 3)), 1e-12));
      expect(ridge.gradientAt(const Vec2(5, 5)).y, closeTo(0, 1e-12));
      expect(ridge.gradientAt(const Vec2(5, 5)).x, lessThan(0));

      const dip = Hill.mound(Vec2(4, 4), height: -0.6, skirt: 2);
      expect(dip.heightAt(const Vec2(4, 4)), -0.6);
      // Uphill on a dip is away from its bottom.
      expect(dip.gradientAt(const Vec2(5, 4)).x, greaterThan(0));
    });

    test('a hole sums its hills', () {
      final hole = boxHole(hills: const [
        Hill.mound(Vec2(5, 5), height: 1, skirt: 2),
        Hill.mound(Vec2(6, 5), height: 0.5, skirt: 2),
      ]);
      const p = Vec2(5.5, 5.2);
      expect(
          hole.groundHeightAt(p),
          closeTo(
              hole.hills[0].heightAt(p) + hole.hills[1].heightAt(p), 1e-12));
      final gradient = hole.groundGradientAt(p);
      final sum = hole.hills[0].gradientAt(p) + hole.hills[1].gradientAt(p);
      expect(gradient.x, closeTo(sum.x, 1e-12));
      expect(gradient.y, closeTo(sum.y, 1e-12));
      expect(boxHole().groundHeightAt(p), 0);
    });
  });

  group('eggs on hills', () {
    HoleDef ridged() => boxHole(
          tee: const Vec2(2, 5),
          nest: const Nest(Vec2(14, 8.5), 0.8),
          hills: const [
            Hill(Vec2(8, 0.5), Vec2(8, 9.5), height: 1, skirt: 2.5),
          ],
        );

    test('an egg too slow to crest a ridge rolls back down', () {
      // Flat, this putt would stop near x = 10.5, past the crest at 8.
      final world = PhysicsWorld(
          hole: ridged(), config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.42);
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, lessThan(7));
    });

    test('an egg with the pace crests the ridge and runs on', () {
      final world = PhysicsWorld(
          hole: ridged(), config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, 0.62);
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, greaterThan(10.5));
    });

    test('an egg left on a steep flank runs off it', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        hills: const [Hill.mound(Vec2(8, 5), height: 1.2, skirt: 3)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.teleportBall('a', const Vec2(9.5, 5));
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.x, greaterThan(10));
      expect(ball.position.y, closeTo(5, 1e-9));
    });

    test('an egg left on a gentle flank slides off it, never parks there', () {
      // Steepest grade about 0.26: a pull of 6.2, under the rolling
      // friction everywhere on the flank.
      final hole = boxHole(
        width: 24,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        hills: const [Hill.mound(Vec2(10, 5), height: 1, skirt: 4.5)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.teleportBall('a', const Vec2(12, 5));
      final ticks = runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ticks, lessThan(2400));
      expect(ball.asleep, isTrue);
      expect(ball.position.x, greaterThanOrEqualTo(14.5));
      expect(hole.groundGradientAt(ball.position).length,
          lessThanOrEqualTo(testPhysics.flatGrade));
    });

    group('a gentle bank', () {
      // A long bank falling toward +y, grade about 0.11 where the putts
      // roll (y = 5): a pull of about 2.7, under the rolling friction.
      HoleDef bank(
              {List<Hill> hills = const [
                Hill(Vec2(-10, 1), Vec2(40, 1), height: 0.6, skirt: 8),
              ]}) =>
          boxHole(
            width: 30,
            height: 14,
            tee: const Vec2(4, 5),
            nest: const Nest(Vec2(28, 1.5), 0.6),
            hills: hills,
          );

      /// How far along x a soft putt rolls before it slows to a creep.
      double soft(HoleDef hole) {
        final world =
            PhysicsWorld(hole: hole, config: testPhysics, playerIds: ['a']);
        world.applyShot('a', 0, 0.2);
        final ball = world.ball('a')!;
        for (var i = 0; i < 1200 && ball.velocity.x.abs() > 1e-3; i++) {
          world.stepTick();
        }
        return ball.position.x - 4;
      }

      test('a soft putt across it rolls about as far as on the flat', () {
        final flat = soft(bank(hills: const []));
        expect(soft(bank()), closeTo(flat, flat * 0.2));
      });

      test('an egg released on it slides down and settles on the flat', () {
        final hole = bank();
        final world =
            PhysicsWorld(hole: hole, config: testPhysics, playerIds: ['a']);
        world.teleportBall('a', const Vec2(15, 5));
        expect(runUntilSettled(world), lessThan(2400));
        final ball = world.ball('a')!;
        expect(ball.asleep, isTrue);
        expect(ball.position.y, greaterThan(8.9));
        expect(hole.groundGradientAt(ball.position).length,
            lessThanOrEqualTo(testPhysics.flatGrade));
      });
    });

    test('a bowl with no flat bottom still settles an egg swinging in it', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        hills: const [Hill.mound(Vec2(8, 5), height: -1.2, skirt: 3.8)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      // Off the bottom and sideways: it orbits as much as it swings.
      world.teleportBall('a', const Vec2(10.5, 5));
      world.impulseBall('a', const Vec2(0, 3));
      final ticks = runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ticks, lessThan(3000));
      expect(ball.asleep, isTrue);
      expect(ball.position.distanceTo(const Vec2(8, 5)), lessThan(0.3));
      final at = ball.position;
      for (var i = 0; i < 240; i++) {
        world.stepTick();
      }
      expect(ball.asleep, isTrue);
      expect(ball.position, at);
    });

    test('a dip gathers an egg toward its bottom', () {
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(14, 8.5), 0.8),
        hills: const [Hill.mound(Vec2(9, 5), height: -1, top: 0.5, skirt: 3)],
      );
      // Flat, this putt stops at about x = 6.6, two and a half short.
      final power = puttStopPower(hole, hole.tee, const Vec2(6.6, 5));
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.applyShot('a', 0, power);
      runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ball.asleep, isTrue);
      expect(ball.position.distanceTo(const Vec2(9, 5)), lessThan(1.6));
    });

    test('an egg pulled into a rail comes to rest against it', () {
      // The mound's skirt runs under the right rail (x = 16): its pull
      // presses the egg into the rail, where it must settle, not rattle.
      final hole = boxHole(
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(2.5, 8.5), 0.8),
        hills: const [Hill.mound(Vec2(12, 5), height: 1.5, skirt: 5)],
      );
      final world =
          PhysicsWorld(hole: hole, config: testPhysics, playerIds: const ['a']);
      world.teleportBall('a', const Vec2(14.5, 5));
      final ticks = runUntilSettled(world);
      final ball = world.ball('a')!;
      expect(ticks, lessThan(600));
      expect(ball.asleep, isTrue);
      expect(ball.position.x, greaterThan(15.4));
      final at = ball.position;
      for (var i = 0; i < 240; i++) {
        world.stepTick();
      }
      expect(ball.asleep, isTrue);
      expect(ball.position, at);
    });

    test('rolls the same way every time', () {
      Vec2 roll() {
        final world = PhysicsWorld(
            hole: ridged(), config: testPhysics, playerIds: const ['a', 'b']);
        world.applyShot('a', 0.3, 0.7);
        world.applyShot('b', -0.2, 0.55);
        runUntilSettled(world);
        return world.ball('a')!.position + world.ball('b')!.position;
      }

      expect(roll(), roll());
    });
  });
}
