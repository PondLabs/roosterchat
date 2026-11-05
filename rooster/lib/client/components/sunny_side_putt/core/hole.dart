// The hole model of Sunny Side Putt: everything a hole is made of, as plain
// data the physics can consume and content authors can build. A hole is a
// green bounded by [HoleDef.bounds], with walls (straight [WallSegment]s and
// curved [WallArc]s), sensors (water, boost strips, portals, gravity wells,
// "?" boxes), the nest to sink the egg into, optional moving obstacles (the
// hen), the ground's relief (hills, and tiers: [Terrace]s, the [Ramp]s up
// to them and the ledges they drop off), the [Kicker]s that throw an egg
// into the air, and decorations the physics ignores.
//
// Coordinates match the screen: x grows right, y grows down; angles are
// `atan2(y, x)`, so a positive angle turns clockwise as drawn. Units are
// abstract world units - an egg's radius is 0.45 units, holes are a few
// dozen units across (see the defaults in [PhysicsConfig]).
//
// Nothing here imports Flutter: the model, and the [ReferenceSolution]
// validator at the bottom, run headless in `unit_test/sunny_side_putt/`.
library;

import 'dart:math' as math;

import 'physics.dart';
import 'vec.dart';

/// One straight wall piece. Restitution null means the hole's default wall
/// bounce ([PhysicsConfig.wallRestitution]); a bumper sets its own high
/// restitution instead ([PhysicsConfig.bumperRestitution]).
///
/// A [ledge] is not a rail but the drop side of a tier (a [Terrace], or a
/// [Ramp]'s side): a one-way edge. Its high side is on the LEFT of a->b as
/// drawn - walking from [a] to [b] on the screen (x right, y down), the high
/// ground is on your left hand, the side `Vec2(d.y, -d.x)` points to for
/// `d = b - a` (see [highSide]). A terrace's outline runs counter-clockwise
/// as drawn, so a ledge along one of its edges runs the outline's way. An
/// egg crossing from the high side to the low side passes and falls (the
/// physics carries it clear of the face, see
/// [PhysicsConfig.ledgeDropSpeed]); an egg coming from the low side bounces
/// off the face like off a rail, with the wall's restitution.
class WallSegment {
  final Vec2 a;
  final Vec2 b;
  final double? restitution;
  final bool bumper;
  final bool ledge;

  const WallSegment(this.a, this.b,
      {this.restitution, this.bumper = false, this.ledge = false});

  /// A bumper wall: bounces eggs away with extra energy.
  factory WallSegment.bumper(Vec2 a, Vec2 b) => WallSegment(a, b, bumper: true);

  /// A ledge: the drop along a tier's edge, its high side on the left of
  /// [a]->[b] as drawn (see the class docs).
  factory WallSegment.ledge(Vec2 a, Vec2 b) => WallSegment(a, b, ledge: true);

  /// The unit normal pointing to the left of a->b as drawn: a ledge's high
  /// side.
  Vec2 get highSide => Vec2(b.y - a.y, a.x - b.x).normalized();

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

/// The nest (cup): over it an egg is pulled toward its center and slowed,
/// and drops when its center is over the cup slow enough for how centered
/// it is - see [PhysicsConfig.captureSpeed] and its neighbours.
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

/// A raised tier: the ground inside [points] stands flat at [height] over
/// the green's level - a hayloft, a raised yard, a road on its bank.
/// Heights run positive (the authoring range is 0.5 to 1.6); a dip below
/// the green is the green raised round it.
///
/// The outline is a simple polygon wound counter-clockwise as drawn (x
/// right, y down): walking it in order, the terrace lies on your left, so
/// a [WallSegment.ledge] along one of its edges runs the outline's way.
///
/// The physics knows no height: on a terrace an egg rolls as on the flat,
/// and what the step does comes from what covers its edges - a
/// [WallSegment.ledge] where it drops away (an egg rolls off it, one below
/// bounces off its face), an ordinary wall where it is railed, a [Ramp]'s
/// top where the way up arrives, the green's fence along its bounds. The
/// course test checks that every edge is covered.
class Terrace {
  final List<Vec2> points;
  final double height;

  const Terrace(this.points, {required this.height});

  /// Whether [point] is inside the outline (ray casting, so a point on an
  /// edge may fall either way; the ground agrees there wherever a ramp
  /// meets it, and a ledge or a rail stands everywhere else).
  bool contains(Vec2 point) {
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

  /// The ground's height at [point] from this terrace: [height] inside, 0
  /// off it.
  double heightAt(Vec2 point) => contains(point) ? height : 0;

  /// The edge from point [index] to the next one (round to the first).
  (Vec2, Vec2) edge(int index) =>
      (points[index], points[(index + 1) % points.length]);

  /// Twice the outline's signed area by the shoelace sum in the screen's
  /// coordinates: negative for the counter-clockwise (as drawn) outline a
  /// terrace takes.
  double get signedArea2 {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum;
  }
}

/// A ramp: the way up a tier. A rectangle [width] wide round the line from
/// [from], at the green's level, to [to], on a terrace's edge at [height]:
/// the ground rises along it on the smooth step `height * t^2 * (3 - 2t)`,
/// `t` running 0 at [from] to 1 at [to] - level at both ends, so there is
/// no kink where it leaves the green or meets the terrace, and steepest
/// halfway, where the grade is `1.5 * height / length`. Across it the
/// ground is level; off the rectangle it adds nothing.
///
/// An egg on it feels the pull downhill as on a hill's slope: one too slow
/// for the climb rolls back down. Its sides are a step, which the author
/// rails (or ledges, the ramp the high side); its foot and its top are
/// open. Only + - * / go into its pull, so every platform rolls alike.
class Ramp {
  final Vec2 from;
  final Vec2 to;
  final double width;
  final double height;

  const Ramp(this.from, this.to, {required this.width, required this.height});

  double get length => from.distanceTo(to);

  /// Where [point] sits along the ramp: 0 at [from], 1 at [to] (not
  /// clamped), or null when it is off the rectangle's width or the axis
  /// is degenerate.
  double? _along(Vec2 point) {
    final axis = to - from;
    final lengthSq = axis.dot(axis);
    if (lengthSq < Vec2.epsilon) return null;
    final offset = point - from;
    final across = offset.cross(axis);
    // |across| / |axis| is the distance off the axis.
    if (across * across > width * width * 0.25 * lengthSq) return null;
    return offset.dot(axis) / lengthSq;
  }

  /// Whether [point] is on the ramp's rectangle.
  bool covers(Vec2 point) {
    final t = _along(point);
    return t != null && t >= 0 && t <= 1;
  }

  /// The ground's height at [point] from this ramp (0 off it).
  double heightAt(Vec2 point) {
    final t = _along(point);
    if (t == null || t < 0 || t > 1) return 0;
    return height * t * t * (3 - 2 * t);
  }

  /// The ground's gradient at [point] from this ramp: the rise per unit,
  /// pointing up the ramp. Zero at both ends and off it.
  Vec2 gradientAt(Vec2 point) {
    final t = _along(point);
    if (t == null || t < 0 || t > 1) return Vec2.zero;
    final axis = to - from;
    return axis * (6 * height * t * (1 - t) / axis.dot(axis));
  }

  /// The height of the ramp's profile at [point]'s place along it, the
  /// width ignored and the ends held: the view lays the turf of a piece
  /// that is on the ramp by it, so the ramp's side stays a crisp step.
  double profileAt(Vec2 point) {
    final axis = to - from;
    final lengthSq = axis.dot(axis);
    if (lengthSq < Vec2.epsilon) return 0;
    final t = ((point - from).dot(axis) / lengthSq).clamp(0.0, 1.0);
    return height * t * t * (3 - 2 * t);
  }

  /// [profileAt]'s gradient: up the ramp, zero past its ends.
  Vec2 profileGradientAt(Vec2 point) {
    final axis = to - from;
    final lengthSq = axis.dot(axis);
    if (lengthSq < Vec2.epsilon) return Vec2.zero;
    final t = (point - from).dot(axis) / lengthSq;
    if (t <= 0 || t >= 1) return Vec2.zero;
    return axis * (6 * height * t * (1 - t) / lengthSq);
  }

  /// The unit vector across the ramp, to the left of [from]->[to] as
  /// drawn.
  Vec2 get _leftward {
    final axis = (to - from).normalized(const Vec2(1, 0));
    return Vec2(axis.y, -axis.x);
  }

  /// The ramp's two sides, each from the foot to the top: the left one
  /// (as drawn, walking up the ramp) first. The ramp is on the right of
  /// the left side and on the left of the right side.
  ((Vec2, Vec2), (Vec2, Vec2)) get sides {
    final half = _leftward * (width / 2);
    return ((from + half, to + half), (from - half, to - half));
  }

  /// The ramp's top end, on the terrace's edge: from its left corner to
  /// its right one.
  (Vec2, Vec2) get top {
    final half = _leftward * (width / 2);
    return (to + half, to - half);
  }
}

/// A kicker: a short launch ramp standing on the green, its deck rising
/// from its foot at [from] to its lip at [to] over a rectangle [width]
/// wide. It throws the way from [from] to [to].
///
/// An egg whose centre crosses the lip the way the kicker throws, at
/// [threshold] units/s or more along it, leaves the ground: it flies off
/// the lip [height] over the ground with its ground speed kept, climbing
/// at that pace along the kicker times [pitch] (capped at
/// [PhysicsConfig.kickerMaxLift]) under [PhysicsConfig.airGravity], so
/// the faster it comes, the higher and farther it flies. A slower egg rolls
/// over the lip, a small bump that keeps [PhysicsConfig.kickerBumpKeep]
/// of its pace, and so does one crossing the lip the other way. Off the
/// lip's width (past the deck's sides) nothing happens.
///
/// [pitch] is the launch angle as rise over run (0.5 is about 27 degrees,
/// see [launchAngleDegrees]): only + - * / go into the flight, so every
/// platform flies the same arc. The physics reads only the lip; the deck
/// under it is the view's to draw ([deckHeightAt]), curving up from the
/// green to meet the lip at the launch angle.
class Kicker {
  final Vec2 from;
  final Vec2 to;
  final double width;
  final double height;
  final double pitch;
  final double threshold;

  const Kicker(this.from, this.to,
      {this.width = 3,
      this.height = 0.45,
      this.pitch = 0.5,
      this.threshold = 7});

  double get length => from.distanceTo(to);

  /// The way the kicker throws, a unit vector from its foot to its lip.
  Vec2 get direction => (to - from).normalized(const Vec2(1, 0));

  /// The launch angle over the horizontal, in degrees (for people: the
  /// physics flies [pitch]).
  double get launchAngleDegrees => math.atan(pitch) * 180 / math.pi;

  /// The unit vector across the kicker, to the left of [direction] as
  /// drawn.
  Vec2 get _leftward {
    final d = direction;
    return Vec2(d.y, -d.x);
  }

  /// The lip, from its left end to its right one (walking up the deck).
  (Vec2, Vec2) get lip {
    final half = _leftward * (width / 2);
    return (to + half, to - half);
  }

  /// The deck's outline: the foot's left corner, the lip's left end, the
  /// lip's right end, the foot's right corner.
  List<Vec2> get corners {
    final half = _leftward * (width / 2);
    return [from + half, to + half, to - half, from - half];
  }

  /// Where [point] sits along the deck: 0 at the foot, 1 at the lip (not
  /// clamped), or null when it is off the deck's width.
  double? _along(Vec2 point) {
    final axis = to - from;
    final lengthSq = axis.dot(axis);
    if (lengthSq < Vec2.epsilon) return null;
    final offset = point - from;
    final across = offset.cross(axis);
    if (across * across > width * width * 0.25 * lengthSq) return null;
    return offset.dot(axis) / lengthSq;
  }

  /// Whether [point] is on the deck.
  bool covers(Vec2 point) {
    final t = _along(point);
    return t != null && t >= 0 && t <= 1;
  }

  /// How the deck curves up to its lip: `height * t^p`, `t` running from
  /// 0 at the foot to 1 at the lip, with `p` set so the deck's last slope
  /// is [pitch] (never under 1, so the deck never bulges).
  double get _profilePower => math.max(1.0, pitch * length / height);

  /// The deck's height over the green [t] of the way from the foot (0) to
  /// the lip (1), clamped there: its profile, the same at every point
  /// across it.
  double deckRise(double t) =>
      height * math.pow(t.clamp(0.0, 1.0), _profilePower).toDouble();

  /// The deck's height over the green at [point] (0 off it): what the view
  /// stands an egg on as it rides up to the lip. The physics never reads
  /// it.
  double deckHeightAt(Vec2 point) {
    final t = _along(point);
    if (t == null || t < 0 || t > 1) return 0;
    return deckRise(t);
  }

  /// The deck's gradient at [point]: its rise per unit, pointing up the
  /// deck (zero off it).
  Vec2 deckGradientAt(Vec2 point) {
    final t = _along(point);
    if (t == null || t <= 0 || t > 1) return Vec2.zero;
    final p = _profilePower;
    return direction * (height * p * math.pow(t, p - 1).toDouble() / length);
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

  /// The raised tiers and the ramps up to them (their drops are the
  /// [WallSegment.ledge]s among [walls]). Empty keeps the green on one
  /// level.
  final List<Terrace> terraces;
  final List<Ramp> ramps;

  /// The launch ramps that throw a fast egg into the air. Empty keeps every
  /// egg on the ground.
  final List<Kicker> kickers;

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
    this.terraces = const [],
    this.ramps = const [],
    this.kickers = const [],
    this.friction,
  });

  /// Whether the ground leaves the flat anywhere (hills or tiers).
  bool get hasRelief =>
      hills.isNotEmpty || terraces.isNotEmpty || ramps.isNotEmpty;

  /// The ground's height at [point]: the hills summed, on the tier under
  /// it (0 on flat green).
  double groundHeightAt(Vec2 point) {
    var height = 0.0;
    for (final hill in hills) {
      height += hill.heightAt(point);
    }
    return height + tierHeightAt(point);
  }

  /// The ground's gradient at [point] (rise per unit, pointing uphill):
  /// the hills summed, plus the ramp under it. An egg feels the pull
  /// against it.
  Vec2 groundGradientAt(Vec2 point) {
    var gradient = Vec2.zero;
    for (final hill in hills) {
      gradient += hill.gradientAt(point);
    }
    return gradient + _tierAt(point).$2;
  }

  /// The tiers' height at [point]: the highest terrace or ramp holding it,
  /// 0 off them all. Tiers never overlap - a ramp meets its terrace along
  /// its top, where the two agree - so the highest is the one underfoot.
  double tierHeightAt(Vec2 point) => _tierAt(point).$1;

  /// The height of the kicker deck under [point] over the ground (0 off
  /// every deck): the view stands an egg on it, the physics never reads
  /// it.
  double kickerDeckHeightAt(Vec2 point) {
    var height = 0.0;
    for (final kicker in kickers) {
      final deck = kicker.deckHeightAt(point);
      if (deck > height) height = deck;
    }
    return height;
  }

  /// [kickerDeckHeightAt]'s gradient: up the deck under [point].
  Vec2 kickerDeckGradientAt(Vec2 point) {
    var height = 0.0;
    var gradient = Vec2.zero;
    for (final kicker in kickers) {
      final deck = kicker.deckHeightAt(point);
      if (deck > height) {
        height = deck;
        gradient = kicker.deckGradientAt(point);
      }
    }
    return gradient;
  }

  /// The tier under [point]: its height and its gradient (a terrace is
  /// level, a ramp slopes up its axis).
  (double, Vec2) _tierAt(Vec2 point) {
    var height = 0.0;
    var gradient = Vec2.zero;
    for (final terrace in terraces) {
      if (terrace.height > height && terrace.contains(point)) {
        height = terrace.height;
        gradient = Vec2.zero;
      }
    }
    for (final ramp in ramps) {
      final rise = ramp.heightAt(point);
      if (rise > height) {
        height = rise;
        gradient = ramp.gradientAt(point);
      }
    }
    return (height, gradient);
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
