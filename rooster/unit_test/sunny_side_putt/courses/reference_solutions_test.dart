// Reference-solution sweep for Sunny Side Putt's launch content: every
// hole must sink its reference solution through the headless physics, so
// no hole ships unfinishable or soft-locked. Plus a simple geometry
// sanity pass: tee and nest live inside bounds, out of the water, and
// clear of wall ends, a full table's eggs spawn on open turf, every hill
// stands clear of what the physics cannot tilt, and every tier is closed
// at its edges and clear of what a step would break.

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

  test('every tier is closed at its edges and clear of what a step breaks', () {
    // The physics knows no height: a terrace's step is only what covers
    // its edges. Every edge of a terrace carries a ledge with the terrace
    // on its high side, a rail, the top of a ramp as high as the terrace,
    // or the green's fence; a ramp's sides carry rails or ledges (the ramp
    // on their high side), its foot stands on the green's level and its top
    // on a terrace's edge. A ledge runs along a tier's edge, high side up.
    // Terraces run counter-clockwise as drawn, simple, inside the bounds
    // and apart; a ramp meets no terrace but at its top. Heights 0.5 to
    // 1.6, a ramp at most 0.6 at its steepest, 2.5 to 10 wide.
    //
    // A pond, a rabbit hole or a silo on a step would sit level while the
    // ground steps under it, so each keeps 0.3 units off every tier; a
    // speed strip or a "?" box may stand on a terrace's flat with 0.3 of
    // room round it, else keeps off too; a hill's reach keeps 0.3 off; a
    // rock or a bumper drum stands wholly on one level, off the tiers or on
    // a terrace's flat, though it may stand against a step's face. The tee
    // and a full table's spawn ring stand on one level, an egg's radius and
    // 0.3 clear of every tier's outline, and so does every hen's walk. The
    // nest sits on a terrace with 0.6 of flat round its rim, or half a unit
    // clear of every tier.
    const clearance = 0.3;
    const slack = 1e-9;
    const config = PhysicsConfig();
    final failures = <String>[];
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        final here = '${course.id}/${hole.id}';
        final shapes = <(String, List<Vec2>)>[
          for (var i = 0; i < hole.terraces.length; i++)
            ('terrace $i', hole.terraces[i].points),
          for (var i = 0; i < hole.ramps.length; i++)
            ('ramp $i', _rampCorners(hole.ramps[i])),
        ];
        if (shapes.isEmpty) continue;
        final rails = [
          for (final wall in hole.walls)
            if (!wall.ledge) wall,
        ];
        final drops = [
          for (final wall in hole.walls)
            if (wall.ledge) wall,
        ];
        // Whether a rail, or a ledge whose high side is [inward], runs
        // along the line through [p] heading [direction].
        bool railed(Vec2 p, Vec2 direction) => rails.any((wall) =>
            _parallel(wall.b - wall.a, direction) &&
            _segmentDistance(p, wall.a, wall.b) < 1e-6);
        bool ledged(Vec2 p, Vec2 direction, Vec2 inward) => drops.any((wall) =>
            _parallel(wall.b - wall.a, direction) &&
            _segmentDistance(p, wall.a, wall.b) < 1e-6 &&
            wall.highSide.dot(inward) > 0.99);

        for (var i = 0; i < hole.terraces.length; i++) {
          final terrace = hole.terraces[i];
          final where = '$here terrace $i';
          final points = terrace.points;
          if (points.length < 3) {
            failures.add('$where: fewer than three corners');
            continue;
          }
          if (terrace.signedArea2 >= 0) {
            failures.add('$where: runs clockwise as drawn');
          }
          if (terrace.height < 0.5 || terrace.height > 1.6) {
            failures.add('$where: height ${terrace.height} outside 0.5..1.6');
          }
          for (final p in points) {
            if (!hole.bounds.contains(p))
              failures.add('$where: $p off the green');
          }
          for (var e = 0; e < points.length; e++) {
            for (var f = e + 2; f < points.length; f++) {
              if (e == 0 && f == points.length - 1) continue;
              final (a, b) = terrace.edge(e);
              final (c, d) = terrace.edge(f);
              if (_segmentsDistance(a, b, c, d) < 1e-9) {
                failures.add('$where: edges $e and $f cross');
              }
            }
          }
          for (var e = 0; e < points.length; e++) {
            final (a, b) = terrace.edge(e);
            final run = b - a;
            final direction = run.normalized();
            final inward = Vec2(direction.y, -direction.x);
            final steps = math.max(2, (run.length / 0.05).ceil());
            for (var s = 0; s <= steps; s++) {
              final t = (0.02 + (run.length - 0.04) * s / steps) / run.length;
              final p = a + run * t;
              final topped = hole.ramps.any((ramp) =>
                  (ramp.height - terrace.height).abs() < 1e-9 &&
                  _parallel(ramp.top.$2 - ramp.top.$1, direction) &&
                  _segmentDistance(p, ramp.top.$1, ramp.top.$2) < 1e-6 &&
                  (ramp.to - ramp.from).dot(inward) > 0);
              if (!railed(p, direction) &&
                  !ledged(p, direction, inward) &&
                  !topped) {
                failures.add('$where: edge $e lies open at $p');
                break;
              }
            }
          }
          for (var j = i + 1; j < hole.terraces.length; j++) {
            if (_outlinesMeet(points, hole.terraces[j].points)) {
              failures.add('$where meets terrace $j');
            }
          }
        }

        for (var i = 0; i < hole.ramps.length; i++) {
          final ramp = hole.ramps[i];
          final where = '$here ramp $i';
          final axis = (ramp.to - ramp.from).normalized();
          if (ramp.height < 0.5 || ramp.height > 1.6) {
            failures.add('$where: height ${ramp.height} outside 0.5..1.6');
          }
          if (ramp.width < 2.5 || ramp.width > 10) {
            failures.add('$where: width ${ramp.width} outside 2.5..10');
          }
          if (1.5 * ramp.height / ramp.length > 0.6 + slack) {
            failures.add('$where: steeper than 0.6');
          }
          final top = hole.terraces.where((terrace) {
            if ((terrace.height - ramp.height).abs() > 1e-9) return false;
            for (var e = 0; e < terrace.points.length; e++) {
              final (a, b) = terrace.edge(e);
              if (_segmentDistance(ramp.top.$1, a, b) < 1e-6 &&
                  _segmentDistance(ramp.top.$2, a, b) < 1e-6) {
                return terrace.contains(ramp.to + axis * 0.1);
              }
            }
            return false;
          });
          if (top.isEmpty) {
            failures.add('$where: its top meets no terrace of its height');
          }
          if (hole.tierHeightAt(ramp.from - axis * 0.3) != 0) {
            failures.add('$where: its foot is not on the green\'s level');
          }
          final (left, right) = ramp.sides;
          for (final (label, side, inward) in [
            ('left', left, Vec2(axis.y, -axis.x) * -1),
            ('right', right, Vec2(axis.y, -axis.x)),
          ]) {
            final run = side.$2 - side.$1;
            final steps = math.max(2, (run.length / 0.05).ceil());
            for (var s = 0; s <= steps; s++) {
              final p = side.$1 + run * (0.01 + 0.98 * s / steps);
              if (!railed(p, axis) && !ledged(p, axis, inward)) {
                failures.add('$where: its $label side lies open at $p');
                break;
              }
            }
          }
          for (var a = 1; a < 50; a++) {
            for (var b = -9; b <= 9; b++) {
              final p = ramp.from.lerp(ramp.to, a / 50) +
                  Vec2(axis.y, -axis.x) * (ramp.width / 2 * b / 10);
              for (var t = 0; t < hole.terraces.length; t++) {
                if (hole.terraces[t].contains(p)) {
                  failures.add('$where runs into terrace $t at $p');
                }
              }
              for (var r = i + 1; r < hole.ramps.length; r++) {
                if (hole.ramps[r].covers(p)) {
                  failures.add('$where runs into ramp $r at $p');
                }
              }
            }
          }
        }

        for (final ledge in drops) {
          final where = '$here: the ledge ${ledge.a}-${ledge.b}';
          final direction = ledge.b - ledge.a;
          final along = [
            for (final terrace in hole.terraces)
              for (var e = 0; e < terrace.points.length; e++) terrace.edge(e),
            for (final ramp in hole.ramps) ...[ramp.sides.$1, ramp.sides.$2],
          ].any((edge) =>
              _parallel(edge.$2 - edge.$1, direction) &&
              _segmentDistance(ledge.a, edge.$1, edge.$2) < 1e-6 &&
              _segmentDistance(ledge.b, edge.$1, edge.$2) < 1e-6);
          if (!along) failures.add('$where runs along no tier\'s edge');
          // High side up all along it (bar the first rise of a ramp's
          // side, where the step is still a sliver).
          final run = ledge.b - ledge.a;
          final steps = math.max(2, (run.length / 0.05).ceil());
          for (var s = 0; s <= steps; s++) {
            final p = ledge.a + run * (0.01 + 0.98 * s / steps);
            final high = hole.groundHeightAt(p + ledge.highSide * 0.05);
            final low = hole.groundHeightAt(p - ledge.highSide * 0.05);
            if (high >= 0.25 && high - low < 0.2) {
              failures.add('$where drops ${(high - low).toStringAsFixed(2)} '
                  'off its high side at $p');
              break;
            }
          }
        }

        // What a step would break stays off the tiers.
        double off(Vec2 p) => shapes
            .map((shape) => _toShape(p, shape.$2))
            .fold(double.infinity, math.min);
        double toOutlines(Vec2 p) => shapes
            .map((shape) => _toOutline(p, shape.$2))
            .fold(double.infinity, math.min);
        (int, double)? onTerrace(Vec2 p) {
          for (var t = 0; t < hole.terraces.length; t++) {
            if (hole.terraces[t].contains(p)) {
              return (t, _toOutline(p, hole.terraces[t].points));
            }
          }
          return null;
        }

        for (var h = 0; h < hole.hills.length; h++) {
          final hill = hole.hills[h];
          for (final (label, outline) in shapes) {
            final room = _spineToShape(hill.a, hill.b, outline) - hill.reach;
            if (room < clearance - slack) {
              failures.add('$here hill $h: ${room.toStringAsFixed(2)} off the '
                  '$label');
            }
          }
        }
        for (final shape in hole.water) {
          for (final (label, outline) in shapes) {
            if (_waterToShape(shape, outline) < clearance - slack) {
              failures.add('$here: a pond sits on the $label');
            }
          }
        }
        for (final pair in hole.portals) {
          for (final end in [pair.a, pair.b]) {
            if (off(end) - pair.radius < clearance - slack) {
              failures.add('$here: the rabbit hole at $end sits on a tier');
            }
          }
        }
        for (final well in hole.wells) {
          if (off(well.position) - well.radius < clearance - slack) {
            failures.add('$here: the silo at ${well.position} reaches a tier');
          }
        }
        for (final strip in hole.boosts) {
          final half = strip.width / 2;
          final on = onTerrace(strip.from);
          final flat = on != null &&
              hole.terraces[on.$1].contains(strip.to) &&
              _spineToOutline(
                          strip.from, strip.to, hole.terraces[on.$1].points) -
                      half >=
                  clearance - slack;
          final clear = shapes.every((shape) =>
              _spineToShape(strip.from, strip.to, shape.$2) - half >=
              clearance - slack);
          if (!flat && !clear) {
            failures.add('$here: the speed strip ${strip.from}-${strip.to} '
                'straddles a step');
          }
        }
        for (final box in hole.boxes) {
          final on = onTerrace(box.position);
          final flat = on != null && on.$2 - box.radius >= clearance - slack;
          final clear = off(box.position) - box.radius >= clearance - slack;
          if (!flat && !clear) {
            failures.add('$here: the "?" box ${box.id} straddles a step');
          }
        }
        for (final arc in hole.arcs) {
          if (arcSpan(arc).$2 < 2 * math.pi - 1e-9) continue;
          final on = onTerrace(arc.center);
          final flat = on != null && on.$2 - arc.radius >= -slack;
          final clear = off(arc.center) - arc.radius >= -slack;
          if (!flat && !clear) {
            failures.add('$here: the rock at ${arc.center} straddles a step');
          }
        }
        final spawns = [
          for (final egg in PhysicsWorld(
              hole: hole,
              config: config,
              playerIds: [for (var i = 0; i < 8; i++) 'egg$i']).balls)
            egg.position,
        ];
        final teeLevel = hole.tierHeightAt(hole.tee);
        for (final spot in spawns) {
          if (hole.tierHeightAt(spot) != teeLevel) {
            failures.add('$here: the spawn at $spot is off the tee\'s level');
          }
          if (toOutlines(spot) - config.ballRadius < clearance - slack) {
            failures.add('$here: the spawn at $spot stands on a step');
          }
          if (hole.ramps.any((ramp) => ramp.covers(spot))) {
            failures.add('$here: the spawn at $spot stands on a ramp');
          }
        }
        for (final hen in hole.obstacles) {
          final stops = [for (final stop in hen.stops) stop.at];
          final walk = <Vec2>[
            for (var s = 0; s < stops.length; s++)
              for (var k = 0; k < 20; k++)
                stops[s].lerp(stops[(s + 1) % stops.length], k / 20),
          ];
          final level = hole.tierHeightAt(stops.first);
          for (final p in walk) {
            if (hole.tierHeightAt(p) != level ||
                toOutlines(p) - hen.radius < clearance - slack) {
              failures
                  .add('$here: the hen ${hen.id} walks off its level at $p');
              break;
            }
          }
        }
        final nest = hole.nest;
        final nestOn = onTerrace(nest.position);
        final seated = nestOn != null &&
            nestOn.$2 - nest.radius >= 0.6 - slack &&
            !hole.ramps.any((ramp) => ramp.covers(nest.position));
        final apart = off(nest.position) - nest.radius >= 0.5 - slack;
        if (!seated && !apart) {
          failures.add('$here: the nest neither sits on a terrace with 0.6 '
              'of flat round its rim nor stands half a unit clear of the '
              'tiers');
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
      'every kicker stands on open, level, dry turf, clear of what it '
      'would break', () {
    // The physics reads only a kicker's lip; the deck is drawn on the
    // ground under it. So the deck keeps to one level (no hill, ramp or
    // step under it), on dry turf inside the bounds, 0.3 off every rail,
    // rock, pond, speed strip, rabbit hole, "?" box and silo's reach, off
    // the nest's rim, the tee's spawn ring and the hens' walks; and its
    // shape keeps to the authoring ranges, its curve never bulging.
    const clearance = 0.3;
    const slack = 1e-9;
    const config = PhysicsConfig();
    final failures = <String>[];
    var kickers = 0;
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
        for (var k = 0; k < hole.kickers.length; k++) {
          kickers++;
          final kicker = hole.kickers[k];
          final where = '${course.id}/${hole.id} kicker $k';
          if (kicker.height < 0.3 || kicker.height > 0.6) {
            failures.add('$where: height ${kicker.height} outside 0.3..0.6');
          }
          if (kicker.pitch < 0.3 || kicker.pitch > 0.8) {
            failures.add('$where: pitch ${kicker.pitch} outside 0.3..0.8');
          }
          if (kicker.threshold < 5 || kicker.threshold > 12) {
            failures.add('$where: threshold ${kicker.threshold} outside 5..12');
          }
          if (kicker.width < 2 || kicker.width > 4) {
            failures.add('$where: width ${kicker.width} outside 2..4');
          }
          if (kicker.length < 1.5 || kicker.length > 3) {
            failures.add('$where: length ${kicker.length} outside 1.5..3');
          }
          if (kicker.pitch * kicker.length < kicker.height - slack) {
            failures.add('$where: its deck would bulge (pitch times length '
                'under its height)');
          }
          final corners = kicker.corners;
          final deck = _deckSamples(kicker);
          for (final p in deck) {
            if (!hole.bounds.contains(p)) {
              failures.add('$where: its deck leaves the green at $p');
              break;
            }
          }
          if (deck.any((p) => hole.water.any((w) => w.contains(p)))) {
            failures.add('$where: its deck stands in the water');
          }
          final level = hole.groundHeightAt(kicker.from);
          if (deck.any((p) =>
              (hole.groundHeightAt(p) - level).abs() > 1e-9 ||
              hole.groundGradientAt(p) != Vec2.zero)) {
            failures.add('$where: its deck stands across a slope or a step');
          }
          // How far a shape is from the deck: 0 when it reaches in.
          double fromDeck(double Function(Vec2) distance) =>
              deck.map(distance).fold(double.infinity, math.min);
          void keepOff(String what, double room) {
            if (room < clearance - slack) {
              failures.add('$where: ${room.toStringAsFixed(2)} off $what');
            }
          }

          for (final wall in hole.walls) {
            keepOff('the wall ${wall.a}-${wall.b}',
                _spineToShape(wall.a, wall.b, corners));
          }
          for (final arc in hole.arcs) {
            keepOff('the arc round ${arc.center}',
                fromDeck((p) => _arcDistance(p, arc)));
          }
          for (final shape in hole.water) {
            keepOff('the water', _waterToShape(shape, corners));
          }
          for (final hill in hole.hills) {
            keepOff(
                'a hill', _spineToShape(hill.a, hill.b, corners) - hill.reach);
          }
          for (final terrace in hole.terraces) {
            if (!terrace.contains(kicker.from) ||
                !terrace.contains(kicker.to)) {
              keepOff('a terrace', _outlineGap(terrace.points, corners));
            } else {
              keepOff('its terrace\'s edge',
                  fromDeck((p) => _toOutline(p, terrace.points)));
            }
          }
          for (final ramp in hole.ramps) {
            keepOff('a ramp', _outlineGap(_rampCorners(ramp), corners));
          }
          for (final strip in hole.boosts) {
            keepOff('the speed strip ${strip.from}-${strip.to}',
                _spineToShape(strip.from, strip.to, corners) - strip.width / 2);
          }
          for (final pair in hole.portals) {
            for (final end in [pair.a, pair.b]) {
              keepOff('a rabbit hole of ${pair.id}',
                  _toShape(end, corners) - pair.radius);
            }
          }
          for (final box in hole.boxes) {
            keepOff('the "?" box ${box.id}',
                _toShape(box.position, corners) - box.radius);
          }
          for (final well in hole.wells) {
            keepOff('the silo at ${well.position}',
                _toShape(well.position, corners) - well.radius);
          }
          keepOff('the nest',
              _toShape(hole.nest.position, corners) - hole.nest.radius);
          for (final spot in spawns) {
            keepOff('the spawn at $spot',
                _toShape(spot, corners) - config.ballRadius);
          }
          for (final hen in hole.obstacles) {
            final stops = [for (final stop in hen.stops) stop.at];
            for (var s = 0; s < stops.length; s++) {
              final next = stops[(s + 1) % stops.length];
              keepOff('the hen ${hen.id}\'s walk',
                  _spineToShape(stops[s], next, corners) - hen.radius);
            }
          }
          for (var j = k + 1; j < hole.kickers.length; j++) {
            keepOff('kicker $j', _outlineGap(hole.kickers[j].corners, corners));
          }
        }
      }
    }
    expect(kickers, greaterThanOrEqualTo(sunnySidePuttCourses.length),
        reason: 'every course has a hole built round a kicker');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
      'every kicker has a launch an egg can reach and a landing zone on '
      'open, dry turf clear of walls', () {
    // A launch reachable: the run-up two units before the foot is turf an
    // egg can roll to from the tee (stopped by rails and water, carried
    // through rabbit holes, down a ledge but never up one), and from there
    // a straight run up the deck to the lip touches no rail.
    //
    // A landing zone: thrown off the lip straight along the kicker at
    // every speed from its threshold up to a full putt's, an egg first
    // comes down somewhere; over a span of at least 3 units/s of those
    // speeds it comes down on open, dry turf clear of walls - in bounds,
    // out of the water, an egg's radius and 0.3 off every rail and rock,
    // off the steps, the ramps and the silos' reach - and meets no rail
    // in the air on the way. (Slower or harder throws may land in the
    // pond or off the far rail: that is the kicker's risk.)
    const config = PhysicsConfig();
    final clearance = config.ballRadius + 0.3;
    final failures = <String>[];
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        if (hole.kickers.isEmpty) continue;
        final reach = _rollReach(hole, config);
        for (var k = 0; k < hole.kickers.length; k++) {
          final kicker = hole.kickers[k];
          final where = '${course.id}/${hole.id} kicker $k';
          final runUp = kicker.from - kicker.direction * 2;
          if (!reach(runUp)) {
            failures.add('$where: no egg can roll to its run-up at $runUp');
          }
          for (var s = 0; s <= 40; s++) {
            final p = runUp.lerp(kicker.to, s / 40);
            for (final wall in hole.walls) {
              if (_segmentDistance(p, wall.a, wall.b) <
                  config.ballRadius + 0.05) {
                failures.add('$where: the run up its deck meets a wall at $p');
              }
            }
          }

          bool good(Vec2 p) {
            if (!hole.bounds.contains(p)) return false;
            if (hole.water.any((w) => w.contains(p))) return false;
            for (final wall in hole.walls) {
              if (_segmentDistance(p, wall.a, wall.b) < clearance) {
                return false;
              }
            }
            for (final arc in hole.arcs) {
              if (_arcDistance(p, arc) < clearance) return false;
            }
            for (final ramp in hole.ramps) {
              if (_toShape(p, _rampCorners(ramp)) < 0.3) return false;
            }
            for (final terrace in hole.terraces) {
              if (_toOutline(p, terrace.points) < 0.3) return false;
            }
            for (final well in hole.wells) {
              if (p.distanceTo(well.position) < well.radius) return false;
            }
            return true;
          }

          var run = 0.0;
          var best = 0.0;
          var start = kicker.threshold;
          for (var speed = kicker.threshold;
              speed <= config.maxShotSpeed + 1e-9;
              speed += 0.25) {
            final landing = _flightOff(hole, kicker, speed, config);
            if (landing != null && good(landing)) {
              if (run == 0) start = speed;
              run = speed - start + 0.25;
              best = math.max(best, run);
            } else {
              run = 0;
            }
          }
          if (best < 3) {
            failures.add('$where: its throws land on open, dry turf over '
                'only ${best.toStringAsFixed(2)} units/s of speed');
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

/// Whether two directions run the same line (either way).
bool _parallel(Vec2 u, Vec2 v) {
  final lu = u.length, lv = v.length;
  if (lu < 1e-12 || lv < 1e-12) return false;
  return (u.cross(v) / (lu * lv)).abs() < 1e-6;
}

/// A ramp's rectangle: foot left, top left, top right, foot right.
List<Vec2> _rampCorners(Ramp ramp) {
  final (left, right) = ramp.sides;
  return [left.$1, left.$2, right.$2, right.$1];
}

bool _inside(Vec2 p, List<Vec2> outline) =>
    Terrace(outline, height: 1).contains(p);

/// Distance from [p] to an outline's edges.
double _toOutline(Vec2 p, List<Vec2> outline) {
  var nearest = double.infinity;
  for (var i = 0; i < outline.length; i++) {
    nearest = math.min(nearest,
        _segmentDistance(p, outline[i], outline[(i + 1) % outline.length]));
  }
  return nearest;
}

/// Distance from [p] to the shape an outline closes: 0 inside it.
double _toShape(Vec2 p, List<Vec2> outline) =>
    _inside(p, outline) ? 0 : _toOutline(p, outline);

/// Distance from the segment [a]-[b] to an outline's edges.
double _spineToOutline(Vec2 a, Vec2 b, List<Vec2> outline) {
  var nearest = double.infinity;
  for (var i = 0; i < outline.length; i++) {
    nearest = math.min(nearest,
        _segmentsDistance(a, b, outline[i], outline[(i + 1) % outline.length]));
  }
  return nearest;
}

/// Distance from the segment [a]-[b] to the shape an outline closes: 0
/// when it reaches in.
double _spineToShape(Vec2 a, Vec2 b, List<Vec2> outline) =>
    _inside(a, outline) || _inside(b, outline)
        ? 0
        : _spineToOutline(a, b, outline);

/// Whether two outlines touch or overlap.
bool _outlinesMeet(List<Vec2> one, List<Vec2> other) {
  if (one.any((p) => _inside(p, other)) || other.any((p) => _inside(p, one))) {
    return true;
  }
  for (var i = 0; i < one.length; i++) {
    if (_spineToOutline(one[i], one[(i + 1) % one.length], other) < 1e-9) {
      return true;
    }
  }
  return false;
}

/// Distance from a water shape to the shape an outline closes: 0 when they
/// meet.
double _waterToShape(WaterShape water, List<Vec2> outline) {
  if (outline.any(water.contains)) return 0;
  switch (water) {
    case WaterCircle(:final center, :final radius):
      return math.max(0, _toShape(center, outline) - radius);
    case WaterRect(:final rect):
      final corners = [
        rect.min,
        Vec2(rect.max.x, rect.min.y),
        rect.max,
        Vec2(rect.min.x, rect.max.y),
      ];
      return _outlineGap(corners, outline);
    case WaterPolygon(:final points):
      return _outlineGap(points, outline);
  }
}

double _outlineGap(List<Vec2> one, List<Vec2> other) {
  if (_outlinesMeet(one, other)) return 0;
  var nearest = double.infinity;
  for (var i = 0; i < one.length; i++) {
    nearest = math.min(
        nearest, _spineToOutline(one[i], one[(i + 1) % one.length], other));
  }
  return nearest;
}

/// Points over a kicker's deck, its outline and inside it, for the lint's
/// level and clearance checks.
List<Vec2> _deckSamples(Kicker kicker) {
  final (left, right) = (kicker.corners[0], kicker.corners[3]);
  final run = kicker.to - kicker.from;
  return [
    for (var a = 0; a <= 12; a++)
      for (var b = 0; b <= 8; b++) left.lerp(right, b / 8) + run * (a / 12),
  ];
}

/// Where an egg thrown off [kicker]'s lip at [speed] along it first comes
/// down; null when it meets a rail in the air first, never lands, or never
/// leaves the ground.
Vec2? _flightOff(
    HoleDef hole, Kicker kicker, double speed, PhysicsConfig config) {
  final world =
      PhysicsWorld(hole: hole, config: config, playerIds: const ['kick']);
  final ball = world.ball('kick')!;
  // Just short of the lip, with the friction to it made good.
  final start = kicker.to - kicker.direction * 0.3;
  ball
    ..position = start
    ..lastSafePosition = start
    ..velocity = kicker.direction *
        math.sqrt(speed * speed + 2 * config.frictionDeceleration * 0.3)
    ..asleep = false;
  var flew = false;
  for (var i = 0; i < 600; i++) {
    world.stepTick();
    for (final event in world.drainEvents()) {
      if (event is BallLaunched) flew = true;
      if (event is BallBounced && flew) return null;
      if (event is BallLanded) return event.at;
    }
    if (!flew && i > 30) return null;
  }
  return null;
}

/// Where an egg can roll from [hole]'s tee: a flood fill over a half-unit
/// grid, stopped by rails, rocks and water, carried through the rabbit
/// holes, and down a ledge but never up one.
bool Function(Vec2) _rollReach(HoleDef hole, PhysicsConfig config) {
  const cell = 0.5;
  final bounds = hole.bounds;
  final cols = (bounds.width / cell).ceil();
  final rows = (bounds.height / cell).ceil();
  Vec2 center(int c, int r) =>
      Vec2(bounds.min.x + (c + 0.5) * cell, bounds.min.y + (r + 0.5) * cell);
  int? cellOf(Vec2 p) {
    final c = ((p.x - bounds.min.x) / cell).floor();
    final r = ((p.y - bounds.min.y) / cell).floor();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return null;
    return r * cols + c;
  }

  bool open(Vec2 p) {
    if (hole.water.any((w) => w.contains(p))) return false;
    for (final wall in hole.walls) {
      if (wall.ledge) continue;
      if (_segmentDistance(p, wall.a, wall.b) < config.ballRadius * 0.9) {
        return false;
      }
    }
    for (final arc in hole.arcs) {
      if (_arcDistance(p, arc) < config.ballRadius * 0.9) return false;
    }
    return true;
  }

  bool crosses(Vec2 a, Vec2 b, Vec2 p, Vec2 q) {
    double side(Vec2 o, Vec2 u, Vec2 v) => (u - o).cross(v - o);
    return (side(p, q, a) > 0) != (side(p, q, b) > 0) &&
        (side(a, b, p) > 0) != (side(a, b, q) > 0);
  }

  bool step(Vec2 from, Vec2 to) {
    for (final wall in hole.walls) {
      if (!crosses(from, to, wall.a, wall.b)) continue;
      if (!wall.ledge) return false;
      if ((from - wall.a).dot(wall.highSide) <= 0) return false;
    }
    return true;
  }

  final reached = List<bool>.filled(cols * rows, false);
  final queue = <int>[];
  void seed(Vec2 p) {
    final index = cellOf(p);
    if (index == null || reached[index]) return;
    reached[index] = true;
    queue.add(index);
  }

  seed(hole.tee);
  for (var head = 0; head < queue.length; head++) {
    final index = queue[head];
    final c = index % cols;
    final r = index ~/ cols;
    final here = center(c, r);
    for (final pair in hole.portals) {
      if (here.distanceTo(pair.a) <= pair.radius) seed(pair.b);
      if (here.distanceTo(pair.b) <= pair.radius) seed(pair.a);
    }
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nc = c + dc;
      final nr = r + dr;
      if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
      final next = nr * cols + nc;
      if (reached[next]) continue;
      final there = center(nc, nr);
      if (!open(there) || !step(here, there)) continue;
      reached[next] = true;
      queue.add(next);
    }
  }
  return (p) {
    final index = cellOf(p);
    return index != null && reached[index];
  };
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
