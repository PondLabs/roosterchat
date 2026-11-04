// Reference-solution sweep for Sunny Side Putt's launch content: every
// hole must sink its reference solution through the headless physics, so
// no hole ships unfinishable or soft-locked. Plus a simple geometry
// sanity pass: tee and nest live inside bounds, out of the water, and
// clear of wall ends, and a full table's eggs spawn on open turf.

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

void main() {
  test('five launch courses ship six holes each', () {
    expect(sunnySidePuttCourses.length, 5);
    for (final course in sunnySidePuttCourses) {
      expect(course.holes.length, 6, reason: '${course.id} must have 6 holes');
    }
  });

  test('every launch hole completes its reference solution headless', () {
    final failures = <String>[];
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        final result = validateReferenceSolution(hole, entry.solution);
        if (!result.completed) {
          failures.add(
              '${course.id}/${hole.id}: did NOT finish the nest ($result)');
        } else if (result.strokes > hole.par) {
          failures.add(
              '${course.id}/${hole.id}: reference took ${result.strokes} strokes vs par ${hole.par}');
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('tee and nest sit inside bounds, dry, and clear of wall ends', () {
    const clearance = 1.2; // egg radius 0.45 plus authoring slack
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        for (final (label, point) in [
          ('tee', hole.tee),
          ('nest', hole.nest.position),
        ]) {
          expect(hole.bounds.contains(point), isTrue,
              reason: '${course.id}/${hole.id}: $label $point outside bounds');
          for (final shape in hole.water) {
            expect(shape.contains(point), isFalse,
                reason: '${course.id}/${hole.id}: $label $point submerged');
          }
          for (final wall in hole.walls) {
            final d = _segmentDistance(point, wall.a, wall.b);
            expect(d, greaterThan(clearance),
                reason:
                    '${course.id}/${hole.id}: $label ${d.toStringAsFixed(2)} from wall $wall');
          }
        }
      }
    }
  });

  test('a full table spawns on open, dry turf on the tee\'s side', () {
    // The world rings every egg after the first round the tee, up to four
    // units out: on a narrow fairway one could land in a rail, a rock or
    // the pond - or behind a rail, on turf it can never leave.
    const config = PhysicsConfig();
    final clearance = config.ballRadius + 0.05;
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        final where = '${course.id}/${hole.id}';
        final world = PhysicsWorld(
            hole: hole,
            config: config,
            playerIds: [for (var i = 0; i < 8; i++) 'egg$i']);
        for (final egg in world.balls) {
          final at = egg.position;
          expect(hole.bounds.contains(at), isTrue,
              reason: '$where: an egg spawns out of bounds at $at');
          for (final shape in hole.water) {
            expect(shape.contains(at), isFalse,
                reason: '$where: an egg spawns in the water at $at');
          }
          // The way out from the tee to the spot crosses no rail or rock.
          for (var step = 0; step <= 20; step++) {
            final point = hole.tee.lerp(at, step / 20);
            for (final wall in hole.walls) {
              expect(_segmentDistance(point, wall.a, wall.b),
                  greaterThan(clearance),
                  reason: '$where: the spawn at $at meets a wall');
            }
            for (final arc in hole.arcs) {
              expect(_arcDistance(point, arc), greaterThan(clearance),
                  reason: '$where: the spawn at $at meets an arc');
            }
          }
        }
      }
    }
  });

  test('no "?" box anchors on a tee or nest', () {
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final nest = entry.hole.nest.position;
        for (final box in entry.hole.boxes) {
          expect(box.position.distanceTo(entry.hole.tee), greaterThan(1.5),
              reason: '${course.id}/${entry.hole.id}: box sits on the tee');
          expect(box.position.distanceTo(nest), greaterThan(1.5),
              reason: '${course.id}/${entry.hole.id}: box sits on the nest');
        }
      }
    }
  });
}

/// Distance from [point] to an arc's curve, its end caps included; inside
/// a full ring (a rock) counts as touching it.
double _arcDistance(Vec2 point, WallArc arc) {
  final span = arcSpan(arc);
  final offset = point - arc.center;
  if (span.$2 >= 2 * math.pi - 1e-9) {
    return math.max(0, offset.length - arc.radius);
  }
  var turn = (math.atan2(offset.y, offset.x) - span.$1) % (2 * math.pi);
  if (turn < 0) turn += 2 * math.pi;
  if (turn <= span.$2) return (offset.length - arc.radius).abs();
  Vec2 end(double angle) =>
      arc.center + Vec2(math.cos(angle), math.sin(angle)) * arc.radius;
  return math.min(
      point.distanceTo(end(span.$1)), point.distanceTo(end(span.$1 + span.$2)));
}

double _segmentDistance(Vec2 point, Vec2 a, Vec2 b) {
  final ab = b - a;
  final l2 = ab.dot(ab);
  if (l2 < Vec2.epsilon) return point.distanceTo(a);
  final t = ((point - a).dot(ab) / l2).clamp(0.0, 1.0).toDouble();
  return point.distanceTo(a + ab * t);
}
