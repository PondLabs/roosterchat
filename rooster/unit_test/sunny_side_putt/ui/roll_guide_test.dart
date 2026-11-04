// The roll guide: the first stretch of a shot's roll, predicted by running
// the engine's own physics ahead on a copy of the world. It must follow the
// shot's line, bend at the first rail and stop a little after it, end
// where a soft putt stops, and never touch the real world.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

HoleDef _box() => HoleDef(
      id: 'guide-box',
      par: 2,
      tee: const Vec2(5, 10),
      nest: Nest(const Vec2(36, 4), 0.9),
      bounds: Rect(Vec2.zero, Vec2(40, 20)),
      walls: [
        WallSegment(Vec2.zero, Vec2(40, 0)),
        WallSegment(Vec2(40, 0), Vec2(40, 20)),
        WallSegment(Vec2(40, 20), Vec2(0, 20)),
        WallSegment(Vec2(0, 20), Vec2.zero),
        // A rail across the line, a few units east of the tee.
        WallSegment(Vec2(10, 5), Vec2(10, 15)),
      ],
    );

void main() {
  const config = PhysicsConfig();

  PhysicsWorld world(HoleDef hole) =>
      PhysicsWorld(hole: hole, config: config, playerIds: const ['me']);

  test('follows the line and stops at its length on an open run', () {
    final hole = _box();
    final w = world(hole);
    // North-east-ish, away from the rail, hard enough to outrun the guide.
    const angle = -math.pi / 2;
    final points = predictRoll(
      world: w,
      hole: hole,
      config: config,
      playerId: 'me',
      angle: angle,
      power: 0.9,
      maxLength: 6,
    );
    expect(points.first, hole.tee);
    for (final p in points) {
      expect((p.x - hole.tee.x).abs(), lessThan(1e-6),
          reason: 'a straight shot north stays on its line');
    }
    final travelled = hole.tee.distanceTo(points.last);
    expect(travelled, closeTo(6, 0.6), reason: 'cut at the guide length');
  });

  test('bends at the first rail and runs a short tail after it', () {
    final hole = _box();
    final points = predictRoll(
      world: world(hole),
      hole: hole,
      config: config,
      playerId: 'me',
      angle: 0, // straight east into the rail at x = 10
      power: 0.7,
      maxLength: 40,
      tailAfterBounce: 2,
    );
    final furthest = points.map((p) => p.x).reduce(math.max);
    expect(furthest, lessThan(10), reason: 'never through the rail');
    expect(points.last.x, lessThan(furthest - 1),
        reason: 'the tail comes back off the rail');
    expect(furthest - points.last.x, lessThan(2.6),
        reason: 'only a short tail after the bounce');
  });

  test('a soft putt ends where the egg stops', () {
    final hole = _box();
    final points = predictRoll(
      world: world(hole),
      hole: hole,
      config: config,
      playerId: 'me',
      angle: math.pi / 2, // south, open turf
      power: 0.15,
      maxLength: 40,
    );
    // Replay the same putt for real and compare the resting spot.
    final real = world(hole);
    real.applyShot('me', math.pi / 2, 0.15);
    var guard = 0;
    while (!real.ball('me')!.asleep && guard++ < 5000) {
      real.stepTick();
    }
    expect(points.last.distanceTo(real.ball('me')!.position), lessThan(0.05));
  });

  test('the real world is left exactly as it was', () {
    final hole = _box();
    final w = world(hole);
    final before = w.toJson().toString();
    predictRoll(
      world: w,
      hole: hole,
      config: config,
      playerId: 'me',
      angle: 0.3,
      power: 0.8,
    );
    expect(w.toJson().toString(), before);
  });
}
