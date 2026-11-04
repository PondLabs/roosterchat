// Shared authoring helpers for the launch courses: exact shot math over
// waypoint chains, fence/rock builders, and the per-hole record the
// registry consumes. Nothing renders here - all pure data for the core.

import 'dart:math' as math;

import '../core/hole.dart';
import '../core/physics.dart';
import '../core/vec.dart';

const PhysicsConfig _kitConfig = PhysicsConfig();

/// One authored hole and the reference solution that must sink it headless.
class SunnySidePuttHole {
  final HoleDef hole;
  final ReferenceSolution solution;

  const SunnySidePuttHole({required this.hole, required this.solution});
}

/// The baseline hit: launches from [from] toward [to] and arrives at `to`
/// moving [arrival] units/s (under [PhysicsConfig.captureSpeed] this gets
/// captured by a nest centered on `to`).
ReferenceShot putt(Vec2 from, Vec2 to, {double arrival = 0.6}) {
  final distance = from.distanceTo(to);
  final v0 = math
      .sqrt(arrival * arrival + 2 * _kitConfig.frictionDeceleration * distance);
  return ReferenceShot(
    (to - from).angle,
    (v0 / _kitConfig.maxShotSpeed).clamp(0.05, 1.0).toDouble(),
  );
}

/// Resting point after a [putt] with the same parameters: `to` plus the
/// leftover coast. Next legs start from it, which keeps chained putts
/// exact without hand-computing friction twice.
Vec2 landAt(Vec2 from, Vec2 to, {double arrival = 0.6}) {
  final dir = (to - from).normalized(Vec2(1, 0));
  final coast = arrival * arrival / (2 * _kitConfig.frictionDeceleration);
  return to + dir * coast;
}

/// Speed needed at a point that sits [gap] roll-units before the finish
/// so the egg keeps coasting through the gap and arrives at [arrivalEnd].
/// Portal exits keep their speed, so a portal leg into the nest uses this
/// as the leg's `arrival`.
double entrySpeedFor(double gap, {double arrivalEnd = 2.4}) {
  return math.sqrt(
      arrivalEnd * arrivalEnd + 2 * _kitConfig.frictionDeceleration * gap);
}

/// Settle point after taking a portal: the putt aimed at the trigger's
/// center arrives there at [arrival], so the crossing speed at the disc
/// edge is a touch higher; the exit spawns at [exitsAt] keeping that
/// speed and direction, coasts, settles. The next putt starts here.
Vec2 portalLandAim({
  required Vec2 entryFrom,
  required Vec2 triggerAt,
  required Vec2 exitsAt,
  required double arrival,
  double triggerRadius = 0.9,
}) {
  final vCross = math.sqrt(
      arrival * arrival + 2 * _kitConfig.frictionDeceleration * triggerRadius);
  final dir = (triggerAt - entryFrom).normalized(Vec2(1, 0));
  final coast = vCross * vCross / (2 * _kitConfig.frictionDeceleration);
  return exitsAt + dir * coast;
}

/// One putt along [path] (tee or waypoint first, last point is where the
/// leg ends): aims at the last point, powers for a slow arrival there.
List<ReferenceShot> puttPath(List<Vec2> path, {double arrival = 0.6}) {
  return [
    for (var i = 0; i < path.length - 1; i++)
      putt(path[i], path[i + 1], arrival: arrival),
  ];
}

/// The rectangular green's perimeter fence with corners overlapped so the
/// swept egg can never slip past a corner rounding.
List<WallSegment> fenceAround(Rect bounds) {
  final low = bounds.min;
  final high = bounds.max;
  return [
    WallSegment(Vec2(low.x - 2, low.y), Vec2(high.x + 2, low.y)),
    WallSegment(Vec2(high.x, low.y - 2), Vec2(high.x, high.y + 2)),
    WallSegment(Vec2(high.x + 2, high.y), Vec2(low.x - 2, high.y)),
    WallSegment(Vec2(low.x, high.y + 2), Vec2(low.x, low.y - 2)),
  ];
}

/// A round rock the egg bounces off (full-circle arc); [bumper] gives it
/// pinball energy instead of the plain wall bounce.
WallArc rock(Vec2 center, double radius, {bool bumper = false}) => bumper
    ? WallArc.custom(center, radius,
        startAngle: 0, sweep: math.pi * 2, bumper: true)
    : WallArc(center, radius, startAngle: 0, sweep: math.pi * 2);
