// Reference-solution sweep for Sunny Side Putt's launch content: every
// hole must sink its reference solution through the headless physics, so
// no hole ships unfinishable or soft-locked. Plus a simple geometry
// sanity pass: tee and nest live inside bounds, out of the water, and
// clear of wall ends, a full table's eggs spawn on open turf, and every
// hill stands clear of what the physics cannot tilt.

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

  test('every hill stands clear of what the physics cannot tilt', () {
    // The physics knows no height, only the pull: a rail, a pond, a speed
    // strip, a rabbit hole, a crate or a silo on a slope would sit level
    // while the turf rises through it, and an egg spawned on a slope rolls
    // off before its first putt. So a hill's reach (plateau and skirt
    // round its spine) keeps 0.3 units off all of them, off the tee and
    // off a full table's spawn ring. The nest clears the skirt by half a
    // unit past its rim, or sits on the plateau with 0.6 units of flat
    // round its rim. Hills keep apart, so a plateau stays flat, and keep
    // to the authoring ranges (heights 0.5 to 1.4, skirts 1.8 to 4).
    const clearance = 0.3;
    const slack = 1e-9; // a hill placed right at a limit passes
    const config = PhysicsConfig();
    final failures = <String>[];
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        final spawns = [
          for (final egg in PhysicsWorld(
              hole: hole,
              config: config,
              playerIds: [for (var i = 0; i < 8; i++) 'egg$i']).balls)
            egg.position,
        ];
        for (var i = 0; i < hole.hills.length; i++) {
          final hill = hole.hills[i];
          final where = '${course.id}/${hole.id} hill $i';
          void keepOff(String what, double distance) {
            final room = distance - hill.reach;
            if (room < clearance - slack) {
              failures.add('$where: ${room.toStringAsFixed(2)} off $what');
            }
          }

          double toSpine(Vec2 point) => _segmentDistance(point, hill.a, hill.b);

          if (hill.height.abs() < 0.5 || hill.height.abs() > 1.4) {
            failures.add('$where: height ${hill.height} outside 0.5..1.4');
          }
          if (hill.skirt < 1.8 || hill.skirt > 4) {
            failures.add('$where: skirt ${hill.skirt} outside 1.8..4');
          }
          for (final wall in hole.walls) {
            keepOff('the wall ${wall.a}-${wall.b}',
                _segmentsDistance(hill.a, hill.b, wall.a, wall.b));
          }
          for (final arc in hole.arcs) {
            keepOff('the arc round ${arc.center}', _spineToArc(hill, arc));
          }
          for (final shape in hole.water) {
            keepOff('the water', _spineToWater(hill, shape));
          }
          for (final strip in hole.boosts) {
            keepOff(
                'the speed strip ${strip.from}-${strip.to}',
                _segmentsDistance(hill.a, hill.b, strip.from, strip.to) -
                    strip.width / 2);
          }
          for (final pair in hole.portals) {
            keepOff('a rabbit hole of ${pair.id}',
                math.min(toSpine(pair.a), toSpine(pair.b)) - pair.radius);
          }
          for (final box in hole.boxes) {
            keepOff(
                'the "?" box ${box.id}', toSpine(box.position) - box.radius);
          }
          for (final well in hole.wells) {
            keepOff('the silo at ${well.position}',
                toSpine(well.position) - well.radius);
          }
          for (final spot in spawns) {
            keepOff('the spawn at $spot', toSpine(spot));
          }
          final nest = hole.nest;
          final toNest = toSpine(nest.position);
          final clearOfNest = toNest - hill.reach - nest.radius >= 0.5 - slack;
          final onPlateau = toNest + nest.radius + 0.6 <= hill.top + slack;
          if (!clearOfNest && !onPlateau) {
            failures.add('$where: the nest neither clears its skirt by 0.5 '
                'nor sits on its plateau with 0.6 of flat round the rim');
          }
          for (var j = i + 1; j < hole.hills.length; j++) {
            final other = hole.hills[j];
            if (_segmentsDistance(hill.a, hill.b, other.a, other.b) <
                hill.reach + other.reach - slack) {
              failures.add('$where overlaps hill $j');
            }
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
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

/// Distance between segments [a]-[b] and [c]-[d]: 0 when they cross.
double _segmentsDistance(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  double side(Vec2 p, Vec2 q, Vec2 r) => (q - p).cross(r - p);
  final crosses = (side(a, b, c) > 0) != (side(a, b, d) > 0) &&
      (side(c, d, a) > 0) != (side(c, d, b) > 0);
  if (crosses) return 0;
  return [
    _segmentDistance(a, c, d),
    _segmentDistance(b, c, d),
    _segmentDistance(c, a, b),
    _segmentDistance(d, a, b),
  ].reduce(math.min);
}

/// Distance from a hill's spine to an arc, walked in steps of 0.01 (a
/// rock counts as solid).
double _spineToArc(Hill hill, WallArc arc) {
  final steps = math.max(1, (hill.a.distanceTo(hill.b) / 0.01).ceil());
  var nearest = double.infinity;
  for (var i = 0; i <= steps; i++) {
    nearest =
        math.min(nearest, _arcDistance(hill.a.lerp(hill.b, i / steps), arc));
  }
  return nearest;
}

/// Distance from a hill's spine to a water shape: 0 when it reaches in.
double _spineToWater(Hill hill, WaterShape shape) {
  if (shape.contains(hill.a) || shape.contains(hill.b)) return 0;
  if (shape is WaterCircle) {
    return math.max(
        0, _segmentDistance(shape.center, hill.a, hill.b) - shape.radius);
  }
  final outline = switch (shape) {
    WaterRect(:final rect) => [
        rect.min,
        Vec2(rect.max.x, rect.min.y),
        rect.max,
        Vec2(rect.min.x, rect.max.y),
      ],
    WaterPolygon(:final points) => points,
    WaterCircle() => const <Vec2>[],
  };
  var nearest = double.infinity;
  for (var i = 0; i < outline.length; i++) {
    nearest = math.min(
        nearest,
        _segmentsDistance(
            hill.a, hill.b, outline[i], outline[(i + 1) % outline.length]));
  }
  return nearest;
}
