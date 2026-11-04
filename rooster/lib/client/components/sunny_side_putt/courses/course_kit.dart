// Shared authoring helpers for the launch courses: exact shot math over
// waypoint chains, fences, rocks and rails (straight chains, bends built
// from straight pieces, walls traced from character plans), lakes cut
// round causeways and jetties, and the per-hole record the registry
// consumes. Nothing renders here - all pure data for the core.

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

/// Walls along a chain of [points], joined in order (and back to the first
/// when [closed]). The pieces share their ends, so no egg slips through a
/// joint.
List<WallSegment> polyline(List<Vec2> points,
    {bool closed = false, bool bumper = false}) {
  return [
    for (var i = 0; i < points.length - (closed ? 0 : 1); i++)
      WallSegment(points[i], points[(i + 1) % points.length], bumper: bumper),
  ];
}

/// The points of a bend: the circle at [center] with [radius] from
/// [startAngle] to [endAngle] (radians, the core's screen convention), in
/// [pieces] equal steps, both ends included. Feed them to [polyline] for a
/// curved rail eggs roll along the inside of: built from straight pieces,
/// it rebounds them from either face like any rail.
List<Vec2> bendPoints(Vec2 center, double radius,
    {required double startAngle,
    required double endAngle,
    required int pieces}) {
  return [
    for (var i = 0; i <= pieces; i++)
      center +
          Vec2(math.cos(startAngle + (endAngle - startAngle) * i / pieces),
                  math.sin(startAngle + (endAngle - startAngle) * i / pieces)) *
              radius,
  ];
}

/// Walls tracing a plan drawn in characters, one per [cell]-unit square
/// with the first row's first square's top-left corner at [origin]: '#'
/// squares are closed (corn, hay, scenery), anything else is open. A wall
/// runs along every edge between an open and a closed square, straight
/// runs merged into one piece. Edges on the plan's outer border are left
/// to [fenceAround], so draw the plan to fill the hole's bounds.
List<WallSegment> plannedWalls(List<String> plan,
    {required double cell, Vec2 origin = Vec2.zero}) {
  final rows = plan.length;
  final columns = plan.first.length;
  for (final row in plan) {
    if (row.length != columns) {
      throw ArgumentError('every plan row needs $columns squares: "$row"');
    }
  }
  bool closed(int column, int row) => plan[row][column] == '#';
  Vec2 corner(int column, int row) =>
      Vec2(origin.x + column * cell, origin.y + row * cell);
  final walls = <WallSegment>[];
  // Edges between row - 1 and row, merged along the row.
  for (var row = 1; row < rows; row++) {
    int? start;
    for (var column = 0; column <= columns; column++) {
      final edge =
          column < columns && closed(column, row - 1) != closed(column, row);
      if (edge) {
        start ??= column;
      } else if (start != null) {
        walls.add(WallSegment(corner(start, row), corner(column, row)));
        start = null;
      }
    }
  }
  // Edges between column - 1 and column, merged down the column.
  for (var column = 1; column < columns; column++) {
    int? start;
    for (var row = 0; row <= rows; row++) {
      final edge = row < rows && closed(column - 1, row) != closed(column, row);
      if (edge) {
        start ??= row;
      } else if (start != null) {
        walls.add(WallSegment(corner(column, start), corner(column, row)));
        start = null;
      }
    }
  }
  return walls;
}

/// The two banks of a strip [width] wide along [path]: the left and the
/// right edge as seen walking from the first point to the last, corners
/// mitred so the strip keeps its width round every bend.
(List<Vec2>, List<Vec2>) stripEdges(List<Vec2> path, double width) {
  final half = width / 2;
  List<Vec2> edge(double side) {
    final points = <Vec2>[];
    for (var i = 0; i < path.length; i++) {
      final before = i == 0 ? null : (path[i] - path[i - 1]).normalized();
      final after =
          i == path.length - 1 ? null : (path[i + 1] - path[i]).normalized();
      if (before == null || after == null) {
        final along = (before ?? after)!;
        points.add(path[i] + Vec2(along.y, -along.x) * (half * side));
        continue;
      }
      final normalBefore = Vec2(before.y, -before.x);
      final normalAfter = Vec2(after.y, -after.x);
      final miter = (normalBefore + normalAfter).normalized(normalBefore);
      final stretch = 1 / miter.dot(normalBefore);
      points.add(path[i] + miter * (half * side * stretch));
    }
    return points;
  }

  return (edge(1), edge(-1));
}

/// A lake filling [lake], crossed from its west side to its east side by a
/// causeway [width] wide along [path] (west end first, both ends on or
/// past the lake's sides): the water north of the causeway and the water
/// south of it.
List<WaterShape> lakeCrossedBy(Rect lake, List<Vec2> path, double width) {
  final (north, south) = stripEdges(path, width);
  return [
    WaterPolygon([
      lake.min,
      Vec2(lake.max.x, lake.min.y),
      ...north.reversed,
    ]),
    WaterPolygon([
      ...south,
      lake.max,
      Vec2(lake.min.x, lake.max.y),
    ]),
  ];
}

/// A lake filling [lake] with a jetty run out into it from its west side:
/// a strip [width] wide along [path] (first point on the west side), and
/// past its end the [tip] - the outline of whatever land it leads to (an
/// island, a landing), from the strip's south edge round to its north
/// edge. One water polygon, the land cut out of it like a keyhole.
WaterPolygon lakeWithJetty(Rect lake, List<Vec2> path, double width,
    {List<Vec2> tip = const []}) {
  final (north, south) = stripEdges(path, width);
  return WaterPolygon([
    lake.min,
    Vec2(lake.max.x, lake.min.y),
    lake.max,
    Vec2(lake.min.x, lake.max.y),
    ...south,
    ...tip,
    ...north.reversed,
  ]);
}

/// The far side of a round island at [center] with [radius] that a jetty
/// [width] wide reaches heading [heading] (radians; 0 comes from the
/// west): the [lakeWithJetty] tip from the jetty's right edge round the
/// far side to its left edge, in [pieces]. End the jetty's path on the
/// rim, where its edges meet it: `sqrt(radius² - (width / 2)²)` short of
/// the center.
List<Vec2> islandTip(Vec2 center, double radius, double width,
    {double heading = 0, int pieces = 12}) {
  final edge = math.asin((width / 2) / radius);
  final from = heading + math.pi - edge;
  final to = heading - math.pi + edge;
  return [
    for (var i = 0; i <= pieces; i++)
      center +
          Vec2(math.cos(from + (to - from) * i / pieces),
                  math.sin(from + (to - from) * i / pieces)) *
              radius,
  ];
}

/// Where [mark] sits on a [plannedWalls] plan: the middle of every square
/// carrying that character, so a two-by-two mark names the corner between
/// its squares. Lets a plan place its own tee, nest and rabbit holes.
Vec2 planSpot(List<String> plan, String mark,
    {required double cell, Vec2 origin = Vec2.zero}) {
  var sum = Vec2.zero;
  var count = 0;
  for (var row = 0; row < plan.length; row++) {
    for (var column = 0; column < plan[row].length; column++) {
      if (plan[row][column] != mark) continue;
      sum +=
          Vec2(origin.x + (column + 0.5) * cell, origin.y + (row + 0.5) * cell);
      count++;
    }
  }
  if (count == 0) throw ArgumentError('no "$mark" on the plan');
  return sum / count.toDouble();
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

/// Boards across the green's four corners, [cut] units along each side
/// from the corner, so the rectangle reads as an octagonal yard; [bumper]
/// makes them kickers.
List<WallSegment> cornerBoards(Rect bounds, double cut, {bool bumper = false}) {
  final low = bounds.min;
  final high = bounds.max;
  return [
    WallSegment(Vec2(low.x, low.y + cut), Vec2(low.x + cut, low.y),
        bumper: bumper),
    WallSegment(Vec2(high.x - cut, low.y), Vec2(high.x, low.y + cut),
        bumper: bumper),
    WallSegment(Vec2(high.x, high.y - cut), Vec2(high.x - cut, high.y),
        bumper: bumper),
    WallSegment(Vec2(low.x + cut, high.y), Vec2(low.x, high.y - cut),
        bumper: bumper),
  ];
}

/// A round rock the egg bounces off (full-circle arc); [bumper] gives it
/// pinball energy instead of the plain wall bounce.
WallArc rock(Vec2 center, double radius, {bool bumper = false}) => bumper
    ? WallArc.custom(center, radius,
        startAngle: 0, sweep: math.pi * 2, bumper: true)
    : WallArc(center, radius, startAngle: 0, sweep: math.pi * 2);
