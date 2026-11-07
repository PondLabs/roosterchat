// Every speed strip the courses ship can be beaten head on: a full-power
// putt rolled straight against it, from just short of it, gets across,
// while a soft one is turned back.

import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import '../core/fixtures.dart';

void main() {
  test('a full-power putt gets across every strip head on, a soft one not', () {
    var strips = 0;
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        for (final strip in entry.hole.boosts) {
          strips++;
          final where = '${course.id}/${entry.hole.id} ${strip.from}';
          // The strip alone, in the middle of a big open box.
          final shift = const Vec2(40, 40) - (strip.from + strip.to) * 0.5;
          final alone = BoostStrip(strip.from + shift, strip.to + shift,
              width: strip.width, speed: strip.speed);
          final dir = alone.direction;
          final reach = alone.width / 2 + testPhysics.ballRadius * 0.5;
          final start = alone.to + dir * (reach + 1);
          final hole = boxHole(
            width: 80,
            height: 80,
            tee: start,
            nest: const Nest(Vec2(2, 2), 0.8),
            friction: entry.hole.friction,
            boosts: [alone],
          );

          /// How far past the strip's near end (against it) the egg got.
          double furthest(double power) {
            final world = PhysicsWorld(
                hole: hole, config: testPhysics, playerIds: const ['a']);
            world.applyShot('a', (dir * -1).angle, power);
            final ball = world.ball('a')!;
            var best = double.negativeInfinity;
            for (var i = 0; i < 7200 && !ball.asleep; i++) {
              world.stepTick();
              final past = (alone.from - ball.position).dot(dir) - reach;
              if (past > best) best = past;
            }
            return best;
          }

          expect(furthest(1), greaterThan(0), reason: '$where: full power');
          expect(furthest(0.25), lessThan(0), reason: '$where: soft');
        }
      }
    }
    expect(strips, greaterThan(0));
  });
}
