// Tests for the hole model and the reference-solution validator: a solvable
// hole completes headless, a sealed-off nest never does, and waits land
// where they are asked before shots.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('ReferenceSolution validation', () {
    test('a two-putt green completes', () {
      // Tee (2,5) to nest (13,5), friction 4: a drive that stops ~1 unit
      // short of the capture zone, then a tap-in.
      final hole = boxHole(
        id: 'green',
        par: 2,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13, 5), 0.8),
        friction: 4,
      );
      final stop = Vec2(hole.nest.position.x - 1.55, 5);
      final drivePower = puttStopPower(hole, hole.tee, stop, arrivalSpeed: 0.3);
      final tap = puttFor(hole, stop);
      final result = validateReferenceSolution(
        hole,
        ReferenceSolution([
          ReferenceShot(0, drivePower),
          ReferenceShot(tap.$1, tap.$2),
        ]),
      );
      expect(result.completed, isTrue);
      expect(result.strokes, 2);
    });

    test('a firm one-putt that crosses the cup completes', () {
      // No need to die on the nest: arriving at 7 units/s through the
      // middle it drops.
      final hole = boxHole(
        id: 'firm',
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13, 5), 0.8),
        width: 30,
      );
      final (angle, power) = puttFor(hole, hole.tee, arrivalSpeed: 7);
      final result = validateReferenceSolution(
          hole, ReferenceSolution([ReferenceShot(angle, power)]));
      expect(result.completed, isTrue);
      expect(result.strokes, 1);
    });

    test('a straight shot past a round pillar completes', () {
      // The pillar sits on the tee-nest line's flank; the fairway shot
      // from the raised tee misses it and rolls to the nest.
      final hole = boxHole(
        id: 'pillar',
        par: 2,
        tee: const Vec2(2, 8),
        nest: const Nest(Vec2(13, 5), 0.8),
        friction: 4,
        arcs: [
          WallArc.custom(const Vec2(5, 5), 0.8,
              startAngle: 0, sweep: 2 * math.pi),
        ],
      );
      final putt = puttFor(hole, hole.tee);
      final result = validateReferenceSolution(
        hole,
        ReferenceSolution([ReferenceShot(putt.$1, putt.$2)]),
      );
      expect(result.completed, isTrue);
      expect(result.strokes, 1);
    });

    test('a sealed-off nest cannot be reached', () {
      final hole = boxHole(
        id: 'sealed',
        par: 2,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13, 5), 0.8),
        extraWalls: [
          WallSegment(const Vec2(10, 1), const Vec2(14, 1)),
          WallSegment(const Vec2(14, 1), const Vec2(14, 9)),
          WallSegment(const Vec2(14, 9), const Vec2(10, 9)),
          WallSegment(const Vec2(10, 9), const Vec2(10, 1)),
        ],
      );
      final result = validateReferenceSolution(
        hole,
        ReferenceSolution([
          ReferenceShot(0, 0.5),
          ReferenceShot(0.2, 0.5),
          ReferenceShot(-0.15, 0.5),
        ]),
      );
      expect(result.completed, isFalse);
    });

    test('waits pause before the shot so the hen can clear the path', () {
      // The hen patrols a vertical crossing; the solution waits 0.2 s
      // before the drive, long enough that the timing is honored (the
      // validator steps the world during the wait; the hen has moved by
      // the time the egg arrives).
      final hole = boxHole(
        id: 'guarded',
        par: 3,
        tee: const Vec2(2, 5),
        nest: const Nest(Vec2(13.8, 5), 0.8),
        friction: 4,
        obstacles: [
          MovingObstacle(
            id: 'hen',
            radius: 0.9,
            stops: [
              ObstacleStop(const Vec2(9, 2),
                  dwellSeconds: 1, travelSecondsToNext: 1),
              ObstacleStop(const Vec2(9, 8),
                  dwellSeconds: 1, travelSecondsToNext: 1),
            ],
          ),
        ],
      );
      final putt = puttFor(hole, hole.tee);
      final waited = validateReferenceSolution(
        hole,
        ReferenceSolution([ReferenceShot(putt.$1, putt.$2, waitSeconds: 0.25)]),
      );
      expect(waited.completed, isTrue);
    });
  });
}
