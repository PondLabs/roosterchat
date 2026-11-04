// The hole model of Sunny Side Putt: everything a hole is made of, as plain
// data the physics can consume and content authors can build. A hole is a
// green bounded by [HoleDef.bounds], with walls (straight [WallSegment]s and
// curved [WallArc]s), sensors (water, boost strips, portals, gravity wells,
// "?" boxes), the nest to sink the egg into, optional moving obstacles (the
// hen) and decorations the physics ignores.
//
// Coordinates match the screen: x grows right, y grows down; angles are
// `atan2(y, x)`, so a positive angle turns clockwise as drawn. Units are
// abstract world units - an egg's radius is 0.45 units, holes are a few
// dozen units across (see the defaults in [PhysicsConfig]).
//
// Nothing here imports Flutter: the model, and the [ReferenceSolution]
// validator at the bottom, run headless in `unit_test/sunny_side_putt/`.
library;

import 'physics.dart';
import 'vec.dart';

/// One straight wall piece. Restitution null means the hole's default wall
/// bounce ([PhysicsConfig.wallRestitution]); a bumper sets its own high
/// restitution instead ([PhysicsConfig.bumperRestitution]).
class WallSegment {
  final Vec2 a;
  final Vec2 b;
  final double? restitution;
  final bool bumper;

  const WallSegment(this.a, this.b, {this.restitution, this.bumper = false});

  /// A bumper wall: bounces eggs away with extra energy.
  factory WallSegment.bumper(Vec2 a, Vec2 b) => WallSegment(a, b, bumper: true);

  double restitutionOr(double fallback) => restitution ?? fallback;
}

/// A curved wall: part of the circle at [center] with [radius], spanning
/// from [startAngle] going counterclockwise-in-math and clockwise-on-screen
/// by [sweep] radians ([sweep] is normalized into (0, 2pi], so a full ring
/// uses `sweep: 2 * pi`). Same restitution rules as [WallSegment].
class WallArc {
  final Vec2 center;
  final double radius;
  final double startAngle;
  final double sweep;
  final double? restitution;
  final bool bumper;

  const WallArc(this.center, this.radius,
      {required this.startAngle, required this.sweep})
      : restitution = null,
        bumper = false;

  const WallArc.custom(this.center, this.radius,
      {required this.startAngle,
      required this.sweep,
      this.restitution,
      this.bumper = false});

  double restitutionOr(double fallback) => restitution ?? fallback;
}

/// A stop on a moving obstacle's looping path: it sits at [at] for
/// [dwellSeconds], then travels to the next stop (wrapping around) in
/// [travelSecondsToNext]. Times are rounded to whole physics ticks once, at
/// construction, so obstacle motion is ended deterministically forever.
class ObstacleStop {
  final Vec2 at;
  final double dwellSeconds;
  final double travelSecondsToNext;

  const ObstacleStop(this.at,
      {this.dwellSeconds = 0, this.travelSecondsToNext = 1});
}

/// A kinematic moving obstacle - the hen: a circle that walks its path
/// forever and nudges eggs by contact. It ignores walls; authors keep the
/// path on the fairway. [restitution] null uses the hole's wall default.
class MovingObstacle {
  final String id;
  final double radius;
  final List<ObstacleStop> stops;
  final double? restitution;

  const MovingObstacle(
      {required this.id,
      required this.radius,
      required this.stops,
      this.restitution});

  double restitutionOr(double fallback) => restitution ?? fallback;
}

/// The nest (cup): an egg captured when its center gets within the capture
/// zone while slow enough - see [PhysicsConfig.captureSpeed].
class Nest {
  final Vec2 position;
  final double radius;

  const Nest(this.position, this.radius);
}

/// Water shapes; an egg whose CENTER falls inside is wet: it returns to its
/// position before the stroke, the stroke already counted.
sealed class WaterShape {
  const WaterShape();

  bool contains(Vec2 point);
}

class WaterCircle extends WaterShape {
  final Vec2 center;
  final double radius;

  const WaterCircle(this.center, this.radius);

  @override
  bool contains(Vec2 point) => point.distanceTo(center) <= radius;
}

class WaterRect extends WaterShape {
  final Rect rect;

  const WaterRect(this.rect);

  @override
  bool contains(Vec2 point) => rect.contains(point);
}

class WaterPolygon extends WaterShape {
  final List<Vec2> points;

  const WaterPolygon(this.points);

  @override
  bool contains(Vec2 point) {
    // Ray casting, consistent winding-agnostic.
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i];
      final b = points[j];
      final intersects = (a.y > point.y) != (b.y > point.y) &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
      if (intersects) inside = !inside;
    }
    return inside;
  }
}

/// A speed strip: while crossing, an egg's velocity along `to - from` is
/// raised to at least [speed], perpendicular motion kept.
class BoostStrip {
  final Vec2 from;
  final Vec2 to;
  final double width;
  final double speed;

  const BoostStrip(this.from, this.to, {this.width = 1.2, this.speed = 18});

  Vec2 get direction => (to - from).normalized(Vec2(1, 0));
}

/// A pair of rabbit holes (portals): an egg entering end [a] appears at [b]
/// (and the other way), keeping its velocity - same direction, same speed,
/// except that a slow egg pops out at [PhysicsConfig.portalExitSpeed] so it
/// rolls clear. A per-egg cooldown, counted only once the egg is clear of
/// every hole, prevents instant re-entry.
class PortalPair {
  final String id;
  final Vec2 a;
  final Vec2 b;
  final double radius;

  const PortalPair(this.id, this.a, this.b, {this.radius = 0.9});
}

/// A gravity well - the silo: pulls eggs that come within [radius], with
/// acceleration `strength / distance` (inverse-radius), capped so the
/// pull can never slingshot an egg past [maxAcceleration].
///
/// A well is also a hazard: an egg whose center comes within
/// [captureRadius] (a quarter of [radius] unless overridden) is swallowed
/// - it returns to its position before the stroke, the stroke already
/// counted, like water. Without the capture zone, an egg resting where the
/// pull beats rolling friction would creep toward the silo forever and
/// oscillate around the center, so holes would never settle; the capture
/// bounds every trajectory: the egg either escapes or falls in. Set 0 for
/// a pure attractor with no hazard.
class GravityWell {
  final Vec2 position;
  final double radius;
  final double strength;
  final double maxAcceleration;
  final double? captureRadius;

  const GravityWell(this.position,
      {required this.radius,
      required this.strength,
      this.maxAcceleration = 40,
      this.captureRadius});

  /// The swallow zone; a quarter of [radius] unless overridden.
  double get swallowRadius => captureRadius ?? radius * 0.25;

  /// Acceleration toward the well at [point], or null when outside.
  Vec2? pullOn(Vec2 point) {
    final offset = position - point;
    final distance = offset.length;
    if (distance >= radius || distance < Vec2.epsilon) return null;
    final magnitude =
        (strength / distance).clamp(0.0, maxAcceleration).toDouble();
    return offset.scaledTo(magnitude);
  }
}

/// A hill on the green: the ground rises (or, with a negative [height],
/// sinks) around the spine from [a] to [b] - one point for a mound or a
/// dip, a line for a ridge or a trough - and an egg on its slopes feels a
/// pull downhill ([PhysicsConfig.slopeGravity] times the grade).
///
/// The ground is flat at [height] for [top] units around the spine (a
/// plateau; 0 makes a rounded crest), then falls to the green's level over
/// [skirt] units along the profile `height * (1 - u^2)^2`, `u` running 0
/// to 1 across the skirt: level at both edges, so no kink anywhere, and
/// steepest at `u = 1/sqrt(3)`, where the grade is about
/// `1.54 * height / skirt`. Only + - * / and a square root go into the
/// pull, so every platform computes the same roll.
///
/// The physics knows no height, only the pull: a hill's reach must stay
/// clear of walls, water, the tee and the nest's rim, unless its plateau
/// carries the nest (the cup then sits on the flat top).
class Hill {
  final Vec2 a;
  final Vec2 b;
  final double height;
  final double top;
  final double skirt;

  const Hill(this.a, this.b,
      {required this.height, this.top = 0, required this.skirt});

  /// A round hill (or, with a negative [height], a dip) centered at [at].
  const Hill.mound(Vec2 at,
      {required double height, double top = 0, required double skirt})
      : this(at, at, height: height, top: top, skirt: skirt);

  /// How far from its spine the hill reaches.
  double get reach => top + skirt;

  Vec2 _spinePoint(Vec2 point) {
    final ab = b - a;
    final lengthSq = ab.dot(ab);
    if (lengthSq < Vec2.epsilon) return a;
    final t = ((point - a).dot(ab) / lengthSq).clamp(0.0, 1.0);
    return a + ab * t;
  }

  /// The ground's height at [point] (0 off the hill).
  double heightAt(Vec2 point) {
    final s = point.distanceTo(_spinePoint(point));
    if (s >= top + skirt) return 0;
    if (s <= top) return height;
    final u = (s - top) / skirt;
    final k = 1 - u * u;
    return height * k * k;
  }

  /// The ground's gradient at [point]: the rise per unit, pointing
  /// uphill (away from the spine on a dip). Zero on the plateau and off
  /// the hill.
  Vec2 gradientAt(Vec2 point) {
    final offset = point - _spinePoint(point);
    final s = offset.length;
    if (s <= top || s >= top + skirt || s < Vec2.epsilon) return Vec2.zero;
    final u = (s - top) / skirt;
    final rise = -4 * height * u * (1 - u * u) / skirt;
    return offset * (rise / s);
  }
}

/// A "?" egg-carton block: an egg reaching it picks up a power-up. The box
/// disappears for the rest of the hole once collected.
class QuestionBox {
  final String id;
  final Vec2 position;
  final double radius;

  const QuestionBox(this.id, this.position, {this.radius = 0.7});
}

/// Pure scenery: the physics skips it entirely. [kind] is a rendering tag
/// ("hay", "fence", "tee_marker", ...), [numbers] carries free parameters.
class Decoration {
  final String kind;
  final Vec2 at;
  final double rotation;
  final Map<String, double> numbers;

  const Decoration(this.kind, this.at,
      {this.rotation = 0, this.numbers = const {}});
}

/// The definition of one hole: everything static and scripted about it.
/// Runtime ball state lives in `physics.dart`; match state in `rules.dart`.
class HoleDef {
  final String id;
  final int par;
  final Vec2 tee;

  /// Where every egg in this hole spawns (tee markers for solo starts are
  /// the tee; multi-ball spawns ring around it).
  final Nest nest;

  /// The green's extent. An egg whose center leaves it is out of play: it
  /// returns to its position before the stroke, the stroke already counted.
  final Rect bounds;

  final List<WallSegment> walls;
  final List<WallArc> arcs;
  final List<MovingObstacle> obstacles;
  final List<WaterShape> water;
  final List<BoostStrip> boosts;
  final List<PortalPair> portals;
  final List<GravityWell> wells;
  final List<QuestionBox> boxes;
  final List<Decoration> decorations;

  /// The ground's relief: mounds, ridges, dips and plateaus. Empty is a
  /// dead-flat green.
  final List<Hill> hills;

  /// Rolling deceleration override for this hole's surface (units/s^2);
  /// null uses [PhysicsConfig.frictionDeceleration].
  final double? friction;

  const HoleDef({
    required this.id,
    required this.par,
    required this.tee,
    required this.nest,
    required this.bounds,
    this.walls = const [],
    this.arcs = const [],
    this.obstacles = const [],
    this.water = const [],
    this.boosts = const [],
    this.portals = const [],
    this.wells = const [],
    this.boxes = const [],
    this.decorations = const [],
    this.hills = const [],
    this.friction,
  });

  /// The ground's height at [point]: the hills summed (0 on flat green).
  double groundHeightAt(Vec2 point) {
    var height = 0.0;
    for (final hill in hills) {
      height += hill.heightAt(point);
    }
    return height;
  }

  /// The ground's gradient at [point] (rise per unit, pointing uphill):
  /// the hills summed. An egg feels the pull against it.
  Vec2 groundGradientAt(Vec2 point) {
    var gradient = Vec2.zero;
    for (final hill in hills) {
      gradient += hill.gradientAt(point);
    }
    return gradient;
  }
}

/// One planned stroke of a [ReferenceSolution]: aim [angle] (radians, the
/// core's screen-consistent convention), hit with [power] in 0..1, after
/// optionally [waitSeconds] - the wait lets moving obstacles line up.
class ReferenceShot {
  final double angle;
  final double power;
  final double waitSeconds;

  const ReferenceShot(this.angle, this.power, {this.waitSeconds = 0});
}

/// An ordered list of shots that finishes a hole. Every shipped hole gets
/// one; the validator replays it headless so an unfinishable or soft-locked
/// hole breaks the build.
class ReferenceSolution {
  final List<ReferenceShot> shots;

  const ReferenceSolution(this.shots);
}

/// The outcome of replaying a [ReferenceSolution] through the physics.
class ReferenceRunResult {
  /// Whether the egg reached the nest.
  final bool completed;

  /// How many of the solution's shots were taken before it finished.
  final int strokes;

  /// Physics ticks the run used, waits included.
  final int ticks;

  const ReferenceRunResult(
      {required this.completed, required this.strokes, required this.ticks});

  @override
  String toString() =>
      'ReferenceRunResult(completed: $completed, strokes: $strokes, ticks: $ticks)';
}

/// Replays [solution] against [hole] headless: one egg at the tee, each
/// shot waits [ReferenceShot.waitSeconds], fires, and the world runs until
/// the egg settles or sinks before the next shot. A safety cap (seen in
/// [maxSecondsPerShot]) keeps a pathological hole (a ball that never
/// settles - a forever-orbit in a well, say) from hanging the test.
ReferenceRunResult validateReferenceSolution(
  HoleDef hole,
  ReferenceSolution solution, {
  PhysicsConfig? config,
  double maxSecondsPerShot = 40,
}) {
  final cfg = config ?? const PhysicsConfig();
  final world =
      PhysicsWorld(hole: hole, config: cfg, playerIds: const ['reference']);
  final ball = world.balls.single;
  var strokes = 0;
  var completed = ball.holed;
  final maxTicksPerShot = (maxSecondsPerShot / cfg.dt).ceil();
  for (final shot in solution.shots) {
    if (completed) break;
    final waitTicks = (shot.waitSeconds / cfg.dt).round();
    for (var i = 0; i < waitTicks && !ball.holed; i++) {
      world.stepTick();
    }
    if (ball.holed) {
      completed = true;
      break;
    }
    world.applyShot('reference', shot.angle, shot.power);
    strokes++;
    var guard = 0;
    while (!ball.holed && !ball.asleep && guard < maxTicksPerShot) {
      world.stepTick();
      guard++;
    }
    if (ball.holed) completed = true;
  }
  return ReferenceRunResult(
      completed: completed, strokes: strokes, ticks: world.tick);
}
