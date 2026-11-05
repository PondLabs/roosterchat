// The deterministic physics of Sunny Side Putt: a fixed-timestep world of
// eggs (circles) rolling among walls, arcs, bumpers, ledges, a walking hen,
// boost strips, portals, gravity wells, water, "?" boxes and the nest, over
// ground that pulls them down its slopes (hills, ramps), and kickers that
// throw a fast egg into the air.
//
// The world is planar: height exists only as the ground's gradient, which
// pulls, and as ledges, one-way edges an egg rolls off from above and
// bounces off from below. A terrace's level top rolls like the flat. The
// one egg with a height of its own is one in the air: off a kicker's lip
// it carries an altitude and a climb (see [BallBody.air]) and flies a
// ballistic arc over the ground until it comes down on it, passing over
// water, sensors, hens, other eggs and any step it clears, but never over
// a rail.
//
// Determinism contract:
//   * Time advances only in whole ticks of [PhysicsConfig.dt] (1/120 s) via
//     [PhysicsWorld.stepTick]; there is no wall-clock anywhere. The game
//     view interpolates between ticks for rendering.
//   * Every tick runs the same passes in the same order - forces, then
//     swept integration per egg in player-id order, then sensors, then
//     egg-vs-egg, then settling - so two simulations fed the same seed and
//     inputs agree bit for bit.
//   * Nothing random happens here: power-ups get randomness only through
//     the seeded [GameRng] the rules engine owns.
//
// Fast eggs never tunnel: movement is swept, with exact continuous
// collision against capsules (straight walls), against the radial band and
// end caps of arcs, and against the hen in relative motion - so a
// max-speed egg still bounces off a zero-thickness wall instead of
// crossing it.
//
// Pure Dart - no Flutter imports - so the whole world runs headless in
// `unit_test/sunny_side_putt/core/` and on every platform the app ships.
library;

import 'dart:math' as math;

import 'hole.dart';
import 'powerups.dart';
import 'rng.dart';
import 'vec.dart';

/// Tuning of the simulation. Lengths are world units (an egg's radius is
/// [ballRadius], holes are a few dozen units across), times are seconds.
class PhysicsConfig {
  /// Fixed tick length in seconds. Deterministic timestep; 1/120 s keeps
  /// 60 fps playback smooth with interpolation while sweeps stay cheap.
  final double dt;

  final double ballRadius;

  /// Hard speed cap (units/s), applied after forces and bounces.
  final double maxSpeed;

  /// Speed a full-power (1.0) shot launches at.
  final double maxShotSpeed;

  /// Default wall restitution (0.7-ish per the spec); per-wall overrides
  /// in [WallSegment.restitution] and [WallArc.restitution].
  final double wallRestitution;

  /// Bumper restitution: bounces give energy back with interest.
  final double bumperRestitution;

  /// Rolling deceleration (units/s^2), a constant opposing motion; also
  /// acts as static friction, so a resting egg under a pull weaker than
  /// this never creeps.
  final double frictionDeceleration;

  /// Restitution between two eggs.
  final double ballRestitution;

  /// An egg entering the nest's capture zone slower than this sinks; any
  /// faster rolls across the nest.
  final double captureSpeed;

  /// Below this speed an egg settles (velocity zeroed, asleep).
  final double sleepSpeed;

  /// Reflections one egg may chain within a single tick (tight corners).
  final int maxBouncesPerTick;

  /// Ticks an egg ignores portals after teleporting, counted once it is
  /// clear of every rabbit hole, so an exit that overlaps a trigger (or a
  /// slow egg still over the exit) cannot bounce it back and forth.
  final int portalCooldownTicks;

  /// The least speed an egg leaves a rabbit hole with: a slower one pops
  /// out at this pace (its heading kept), enough to roll clear of the
  /// hole instead of stopping in it.
  final double portalExitSpeed;

  /// Range (units) at which a magnetized egg feels the nest.
  final double magnetRange;

  /// Pull strength (units/s^2) of the magnet flag inside [magnetRange].
  final double magnetStrength;

  /// How hard a hill pulls (units/s^2 per unit of grade): an egg on a
  /// slope of grade g feels `slopeGravity * g` downhill. Over
  /// [frictionDeceleration] it rolls back down; under it, it can rest.
  final double slopeGravity;

  /// The least pace (units/s) an egg leaves a ledge's lip with, away from
  /// the face: one that rolls over slower is carried off at this pace (the
  /// rest of its motion kept), the fall taking it clear of the face so it
  /// never comes to rest inside the step. Enough to coast past an egg's
  /// radius against [frictionDeceleration].
  final double ledgeDropSpeed;

  /// The pull on an egg in the air (units/s^2): the view's own fall off a
  /// ledge, so a flight and a drop come down alike.
  final double airGravity;

  /// The fastest climb (units/s) a kicker throws an egg up with, however
  /// hard it comes: about 1.2 units over the lip at the top of its arc, so
  /// a flight stays near the rails it cannot cross. Past it a harder putt
  /// only flies farther.
  final double kickerMaxLift;

  /// The share of its pace an egg keeps rolling over a kicker's lip too
  /// slow to fly (or crossing it against the way it throws): a small bump.
  final double kickerBumpKeep;

  /// The share of its ground speed an egg keeps each time it comes down.
  final double landingKeep;

  /// The share of its fall's speed a landing gives back as a bounce.
  final double landingBounce;

  /// The least bounce (units/s up) that lifts a landing egg off again: a
  /// softer landing leaves it rolling.
  final double landingHopSpeed;

  const PhysicsConfig({
    this.dt = 1 / 120,
    this.ballRadius = 0.45,
    this.maxSpeed = 30,
    this.maxShotSpeed = 26,
    this.wallRestitution = 0.7,
    this.bumperRestitution = 1.6,
    this.frictionDeceleration = 7,
    this.ballRestitution = 0.8,
    this.captureSpeed = 3.0,
    this.sleepSpeed = 0.05,
    this.maxBouncesPerTick = 8,
    this.portalCooldownTicks = 24,
    this.portalExitSpeed = 3.8,
    this.magnetRange = 3.5,
    this.magnetStrength = 26,
    this.slopeGravity = 24,
    this.ledgeDropSpeed = 3.2,
    this.airGravity = 18,
    this.kickerMaxLift = 6.6,
    this.kickerBumpKeep = 0.88,
    this.landingKeep = 0.9,
    this.landingBounce = 0.3,
    this.landingHopSpeed = 1.2,
  });
}

/// One egg in play (a player's ball). Positions are world units.
class BallBody {
  final String playerId;

  Vec2 position;
  Vec2 velocity;
  Vec2 lastSafePosition;
  bool holed;
  bool asleep;

  /// Ticks left before this egg may enter a portal again.
  int portalCooldown;

  /// While the egg flies (off a kicker's lip): the altitude of its lowest
  /// point over the green's base level, the same measure as
  /// [HoleDef.groundHeightAt]. Null while it rolls on the ground.
  double? air;

  /// While the egg flies: its climb, units/s (negative once it falls).
  double airSpeed;

  /// Flags active until a world tick (timed effects, Ghost Egg).
  final Map<PowerUpFlag, int> timedUntil = {};

  /// Flags active until the egg settles (Chicken Hop, Nest Magnet).
  final Set<PowerUpFlag> untilRest = {};

  BallBody(
      {required this.playerId,
      required this.position,
      this.velocity = Vec2.zero,
      this.holed = false,
      this.asleep = true,
      this.portalCooldown = 0,
      this.air,
      this.airSpeed = 0})
      : lastSafePosition = position;

  double get speed => velocity.length;

  /// Whether the egg is in the air.
  bool get airborne => air != null;

  /// Puts the egg back on the ground, its flight over.
  void ground() {
    air = null;
    airSpeed = 0;
  }

  bool flagActive(PowerUpFlag flag, int tick) =>
      untilRest.contains(flag) || (timedUntil[flag] ?? -1) > tick;

  void clearTransientFlags() {
    untilRest.clear();
    timedUntil.clear();
  }

  /// Stops and settles, ending until-rest flags. Wherever the egg came to
  /// rest IS its new safe spot: water and out-of-bounds returns land at the
  /// last place it settled (the callers of settle have already screened
  /// bounds and water).
  void settle() {
    velocity = Vec2.zero;
    asleep = true;
    untilRest.clear();
    lastSafePosition = position;
    ground();
  }

  Map<String, Object?> toJson() => {
        'id': playerId,
        'x': position.x,
        'y': position.y,
        'vx': velocity.x,
        'vy': velocity.y,
        'holed': holed,
        'asleep': asleep,
        'sx': lastSafePosition.x,
        'sy': lastSafePosition.y,
        'cd': portalCooldown,
        'air': air,
        'vz': airSpeed,
        'timed': {
          for (final entry in timedUntil.entries) entry.key.name: entry.value,
        },
        'rest': [
          for (final flag in PowerUpFlag.values)
            if (untilRest.contains(flag)) flag.name,
        ],
      };
}

/// What the world reports each tick, in fixed deterministic order (per egg
/// by player id, then by pass order). The rules engine turns these into
/// game events; the game view turns those into sounds and particles.
sealed class PhysicsEvent {
  const PhysicsEvent();
}

enum BounceKind { wall, arc, bumper, obstacle, ball }

/// An egg hit a wall, arc, bumper, the hen, or another egg.
class BallBounced extends PhysicsEvent {
  final String playerId;
  final BounceKind kind;
  final double impactSpeed;
  final Vec2 at;

  /// The other egg, for [BounceKind.ball].
  final String? otherPlayerId;

  const BallBounced({
    required this.playerId,
    required this.kind,
    required this.impactSpeed,
    required this.at,
    this.otherPlayerId,
  });
}

/// Wet: the egg returned to its pre-stroke position, stroke already counted.
class BallSplashed extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallSplashed({required this.playerId, required this.at});
}

/// Swallowed by a gravity well (the silo): same treatment as water - the
/// egg returns to its pre-stroke position, the stroke already counted.
class BallSwallowed extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallSwallowed({required this.playerId, required this.at});
}

/// Rolled off a ledge's lip: the egg drops to the tier below (the view
/// draws the fall).
class BallDropped extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallDropped({required this.playerId, required this.at});
}

/// Thrown into the air off a kicker's lip at [at]: the egg flies (the view
/// draws the arc from [BallBody.air]).
class BallLaunched extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  /// Its pace along the kicker as it left the lip.
  final double speed;

  const BallLaunched(
      {required this.playerId, required this.at, required this.speed});
}

/// Came down on the ground at [at] after a flight, falling at
/// [impactSpeed]; a hard landing bounces it up once more.
class BallLanded extends PhysicsEvent {
  final String playerId;
  final Vec2 at;
  final double impactSpeed;

  const BallLanded(
      {required this.playerId, required this.at, required this.impactSpeed});
}

/// Rolled over a kicker's lip at [at] without flying (too slow, or the
/// other way): a small bump.
class BallBumped extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallBumped({required this.playerId, required this.at});
}

/// Out of the hole's bounds: same treatment as water.
class BallOutOfBounds extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallOutOfBounds({required this.playerId, required this.at});
}

/// Sunk: the egg reached the nest slow enough.
class BallCaptured extends PhysicsEvent {
  final String playerId;

  const BallCaptured({required this.playerId});
}

/// Crossed a boost strip: velocity raised along the strip.
class BallBoosted extends PhysicsEvent {
  final String playerId;
  final Vec2 at;

  const BallBoosted({required this.playerId, required this.at});
}

/// Went through a rabbit hole (portal) - position swapped, speed kept.
class BallTeleported extends PhysicsEvent {
  final String playerId;
  final String portalId;

  const BallTeleported({required this.playerId, required this.portalId});
}

/// Reached a "?" box; the box is gone for the rest of the hole.
class BallPickedBox extends PhysicsEvent {
  final String playerId;
  final String boxId;

  const BallPickedBox({required this.playerId, required this.boxId});
}

/// The simulation for one hole: static geometry from a [HoleDef] plus the
/// eggs in play. The rules engine builds one per hole; state serializes
/// into snapshots (see [toJson] and [restore]).
class PhysicsWorld {
  final HoleDef hole;
  final PhysicsConfig config;

  final Map<String, BallBody> _balls = {};
  List<String> _order = []; // player ids, sorted

  int _tick = 0;
  final Set<String> _collectedBoxes = {};
  final List<PhysicsEvent> _events = [];

  /// The ids of this hole's "?" boxes already picked up. Rendering reads it
  /// to stand the collected crates down; the truth stays here (it rides the
  /// snapshots, so mid-joins see it too).
  Set<String> get collectedBoxes => _collectedBoxes;

  /// Per egg: boost strip indexes the egg was inside last tick (the edge
  /// trigger). Recomputed silently on restore and teleports.
  final Map<String, Set<int>> _insideBoosts = {};

  PhysicsWorld({
    required this.hole,
    required this.config,
    Iterable<String> playerIds = const [],
  }) {
    final ids = playerIds.toList()..sort();
    for (final id in ids) {
      addBall(id);
    }
  }

  int get tick => _tick;

  /// The eggs, in player-id order.
  List<BallBody> get balls => [for (final id in _order) _balls[id]!];

  BallBody? ball(String playerId) => _balls[playerId];

  bool get allSettled => _balls.values.every((b) => b.holed || b.asleep);

  bool get allHoled => _balls.isNotEmpty && _balls.values.every((b) => b.holed);

  double get frictionDeceleration =>
      hole.friction ?? config.frictionDeceleration;

  // ---- eggs in and out -----------------------------------------------------

  /// Spawns an egg at the tee (ringed around it when several share it), at
  /// rest. Used at hole start and on mid-hole joins. The ring steps start
  /// at 2 units and grow to 4, golden-angle spaced, so straight putts to a
  /// shared nest never clip a neighbor on the way out.
  BallBody addBall(String playerId) {
    final index = _balls.length;
    final offset = index == 0
        ? Vec2.zero
        : Vec2(math.cos(index * 2.39996), math.sin(index * 2.39996)) *
            (2.0 + index * 0.75).clamp(0.0, 4.0);
    final body = BallBody(playerId: playerId, position: hole.tee + offset);
    body.lastSafePosition = body.position;
    _balls[playerId] = body;
    _rebuildOrder();
    _insideBoosts[playerId] = _boostsInside(body.position).toSet();
    return body;
  }

  /// Removes an egg (a player leaving mid-hole). Its score stays with the
  /// rules engine; the world just stops simulating it.
  void removeBall(String playerId) {
    _balls.remove(playerId);
    _insideBoosts.remove(playerId);
    _rebuildOrder();
  }

  void _rebuildOrder() {
    _order = _balls.keys.toList()..sort();
  }

  // ---- inputs --------------------------------------------------------------

  /// Launches an egg: [angle] in radians, [power] 0..1 scaled by
  /// [PhysicsConfig.maxShotSpeed]. The wobble is the rules engine's
  /// business; it passes the final, wobbled angle here.
  void applyShot(String playerId, double angle, double power) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    final speed = power.clamp(0.0, 1.0) * config.maxShotSpeed;
    ball.velocity = Vec2(math.cos(angle), math.sin(angle)) * speed;
    ball.asleep = false;
  }

  void impulseBall(String playerId, Vec2 deltaVelocity) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    ball.velocity += deltaVelocity;
    ball.asleep = false;
  }

  /// Random kick of at most [maxSpeed], drawn from [rng] (Corn Rain).
  void nudgeBall(String playerId, double maxSpeed, GameRng rng) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    final angle = rng.nextAngle();
    final speed = rng.nextDouble() * maxSpeed;
    impulseBall(playerId, Vec2(math.cos(angle), math.sin(angle)) * speed);
  }

  /// Moves an egg to [to] at once, speed kept (Rabbit Hole): it comes up
  /// out of the ground there, so one in the air lands.
  void teleportBall(String playerId, Vec2 to) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    ball.position = to;
    ball.asleep = false;
    ball.ground();
    _insideBoosts[playerId] = _boostsInside(to).toSet();
  }

  /// Swaps two eggs' positions and safe positions, speeds preserved
  /// (Nest Swap); both stand on the ground after it, even one that was in
  /// the air.
  void swapBalls(String playerIdA, String playerIdB) {
    final a = _balls[playerIdA];
    final b = _balls[playerIdB];
    if (a == null || b == null || a.holed || b.holed) return;
    final positionA = a.position;
    a.position = b.position;
    b.position = positionA;
    final safeA = a.lastSafePosition;
    a.lastSafePosition = b.lastSafePosition;
    b.lastSafePosition = safeA;
    a.asleep = false;
    b.asleep = false;
    a.ground();
    b.ground();
    _insideBoosts[playerIdA] = _boostsInside(a.position).toSet();
    _insideBoosts[playerIdB] = _boostsInside(b.position).toSet();
  }

  void setBallFlagFor(String playerId, PowerUpFlag flag, int durationTicks) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    ball.timedUntil[flag] = _tick + durationTicks;
  }

  void setBallFlagUntilRest(String playerId, PowerUpFlag flag) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    ball.untilRest.add(flag);
  }

  /// Immediate placement checks for an egg that was moved somewhere
  /// without rolling there (power-ups): bounds, water, capture. One still
  /// in the air (a gust caught it in flight) only answers to the bounds:
  /// it is over the water, not in it.
  void evaluatePlacement(String playerId) {
    final ball = _balls[playerId];
    if (ball == null || ball.holed) return;
    if (_handleBounds(ball)) return;
    if (ball.airborne) return;
    if (_handleWater(ball)) return;
    _handleNest(ball);
  }

  // ---- simulation ----------------------------------------------------------

  /// Advances exactly one [PhysicsConfig.dt].
  void stepTick() {
    _tick++;
    final hens = [
      for (final obstacle in hole.obstacles)
        _ObstacleSweep(obstacle, _tick, config.dt),
    ];

    for (final id in _order) {
      final ball = _balls[id]!;
      if (ball.holed) continue;
      // The cooldown only runs once the egg is clear of every rabbit
      // hole: a slow egg still over the exit cannot drop straight back in.
      if (ball.portalCooldown > 0 && !_overAnyPortal(ball.position)) {
        ball.portalCooldown--;
      }

      if (ball.asleep) {
        // Static friction: a pull the surface (or a rail the egg leans
        // on) can hold never wakes the egg.
        if (_restingPull(ball).length > frictionDeceleration) {
          ball.asleep = false;
        }
      }
      if (!ball.asleep && ball.airborne) {
        // In the air nothing on the ground pulls or rubs: it keeps its
        // pace until it comes down.
        ball.velocity = _clamped(ball.velocity);
      } else if (!ball.asleep) {
        var velocity = ball.velocity + _accelOn(ball) * config.dt;
        final speed = velocity.length;
        if (speed > 0) {
          final dropped = frictionDeceleration * config.dt;
          velocity = speed > dropped
              ? velocity * ((speed - dropped) / speed)
              : Vec2.zero;
        }
        ball.velocity = _clamped(velocity);
      }
      // Awake eggs sweep their own motion; sleeping eggs still get swept
      // against the hen walking its path (relative motion), which is how
      // it nudges them awake.
      _integrate(ball, hens);
      if (!ball.holed && !ball.asleep) {
        final touched = ball.airborne && _touchdown(ball);
        if (!ball.airborne) {
          _sensors(ball);
        } else if (!_handleBounds(ball) && touched) {
          // Bounced back up off the ground it met: wet all the same when
          // that ground was the pond.
          _handleWater(ball);
        }
      }
    }

    _ballVsBalls();

    for (final id in _order) {
      final ball = _balls[id]!;
      if (ball.holed) continue;
      if (ball.asleep) {
        // Screening: nothing may STAY out of bounds or inside water, even
        // a resting egg that another body pushed there this tick.
        if (!_handleBounds(ball)) _handleWater(ball);
      } else if (!ball.airborne &&
          ball.velocity.length < config.sleepSpeed &&
          _restingPull(ball).length <= frictionDeceleration) {
        // True static equilibrium: slow AND nothing pushing it onward.
        // A ball on a gravity well's or a hill's slope (pull > friction)
        // keeps creeping instead of settling, exactly like physics says;
        // one pressed against a rail by the pull settles there.
        if (!_handleBounds(ball) && !_handleWater(ball)) ball.settle();
      }
    }
  }

  List<PhysicsEvent> drainEvents() {
    final drained = List.of(_events);
    _events.clear();
    return drained;
  }

  int get pendingEventCount => _events.length;

  // ---- internals -----------------------------------------------------------

  Vec2 _clamped(Vec2 v) {
    final speed = v.length;
    if (speed <= config.maxSpeed || speed == 0) return v;
    return v * (config.maxSpeed / speed);
  }

  /// Acceleration from gravity wells, hills, ramps and the magnet flag.
  Vec2 _accelOn(BallBody ball) {
    var accel = Vec2.zero;
    for (final well in hole.wells) {
      final pull = well.pullOn(ball.position);
      if (pull != null) accel += pull;
    }
    if (hole.hasRelief) {
      accel -= hole.groundGradientAt(ball.position) * config.slopeGravity;
    }
    if (ball.flagActive(PowerUpFlag.magnet, _tick)) {
      final offset = hole.nest.position - ball.position;
      final distance = offset.length;
      if (distance < config.magnetRange && distance > Vec2.epsilon) {
        accel += offset.scaledTo(config.magnetStrength);
        if (distance < hole.nest.radius) {
          // Magnetized over the nest ring: never too fast to be caught.
          final speed = ball.velocity.length;
          if (speed > config.captureSpeed) {
            ball.velocity = ball.velocity * (config.captureSpeed / speed);
          }
        }
      }
    }
    return accel;
  }

  /// The pull an egg at rest would have to resist: [_accelOn] minus the
  /// part a wall or rock it touches pushes back (an egg rolled down a
  /// slope into a rail rests against it instead of rattling there). A
  /// ledge holds an egg only from below: from above it is the drop.
  Vec2 _restingPull(BallBody ball) {
    var accel = _accelOn(ball);
    if (accel == Vec2.zero) return accel;
    if (ball.flagActive(PowerUpFlag.ghost, _tick)) return accel;
    final reach = config.ballRadius + 0.02;
    void lean(Vec2 normal) {
      final into = accel.dot(normal);
      if (into < 0) accel -= normal * into;
    }

    for (final wall in hole.walls) {
      if (wall.ledge && _ledgeSide(ball.position, wall.a, wall.b) <= 0) {
        continue;
      }
      final closest = _closestPointOnSegment(ball.position, wall.a, wall.b);
      final offset = ball.position - closest;
      final distance = offset.length;
      if (distance < reach && distance > Vec2.epsilon) {
        lean(offset * (1 / distance));
      }
    }
    for (final arc in hole.arcs) {
      final offset = ball.position - arc.center;
      final distance = offset.length;
      if (distance < Vec2.epsilon) continue;
      if ((distance - arc.radius).abs() >= reach) continue;
      final span = arcSpan(arc);
      if (!_angleInSpan(math.atan2(offset.y, offset.x), span.$1, span.$2)) {
        continue;
      }
      final outward = offset * (1 / distance);
      lean(distance >= arc.radius ? outward : outward * -1);
    }
    return accel;
  }

  /// Moves an egg through the rest of its tick with swept collisions
  /// against walls, arcs and the hen; reflects at each hit. A ledge
  /// stops an egg only from below; rolled over from above, it drops the
  /// egg to the tier below. A kicker's lip, rolled over, throws the egg
  /// into the air or bumps it. In the air the egg passes over the hens and
  /// over every step whose top it clears, and its flight carries on to the
  /// tick's end.
  void _integrate(BallBody ball, List<_ObstacleSweep> hens) {
    final radius = config.ballRadius;
    final ghost = ball.flagActive(PowerUpFlag.ghost, _tick);
    final hop = ball.flagActive(PowerUpFlag.hop, _tick);

    _depenetrate(ball, hens, ghost, hop);

    // The share of the tick at which the egg's flight state (its altitude
    // and climb) holds: the tick's start, or where it left a lip.
    var airFrom = 0.0;
    var fraction = 0.0;
    var bounces = 0;
    while (fraction < 1 - 1e-12 && bounces <= config.maxBouncesPerTick) {
      final remainingFraction = 1 - fraction;
      final velocity = ball.velocity;
      final delta = velocity * (config.dt * remainingFraction);
      final moving = velocity.lengthSquared > 1e-18;
      final flying = ball.airborne;

      _SweepHit? best;
      if (!ghost) {
        for (final wall in hole.walls) {
          if (!moving) break;
          final hit = wall.ledge
              ? _sweepLedge(ball.position, delta, radius, wall.a, wall.b)
              : _sweepCapsule(ball.position, delta, radius, wall.a, wall.b);
          if (hit == null) continue;
          if (best == null || hit.$1 < best.t) {
            // A step's face stops an egg in the air only below its top.
            if (flying &&
                wall.ledge &&
                _altitudeAt(
                        ball, airFrom, fraction + hit.$1 * remainingFraction) >=
                    _ledgeTop(wall, ball.position + delta * hit.$1)) {
              continue;
            }
            best = _SweepHit(
              t: hit.$1,
              normal: hit.$2,
              restitution: wall.restitutionOr(wall.bumper
                  ? config.bumperRestitution
                  : config.wallRestitution),
              kind: wall.bumper ? BounceKind.bumper : BounceKind.wall,
            );
          }
        }
        for (final arc in hole.arcs) {
          if (!moving) break;
          final hit = _sweepArc(ball.position, delta, radius, arc);
          if (hit == null) continue;
          if (best == null || hit.$1 < best.t) {
            best = _SweepHit(
              t: hit.$1,
              normal: hit.$2,
              restitution: arc.restitutionOr(arc.bumper
                  ? config.bumperRestitution
                  : config.wallRestitution),
              kind: arc.bumper ? BounceKind.bumper : BounceKind.arc,
            );
          }
        }
      }
      // In the air (or hopping) the egg passes over the hens.
      if (!ghost && !hop && !flying) {
        for (final hen in hens) {
          final hit = hen.sweep(ball.position, radius, delta, fraction);
          if (hit == null) continue;
          if (best == null || hit.$1 < best.t) {
            best = _SweepHit(
              t: hit.$1,
              normal: hit.$2,
              restitution: hen.obstacle.restitutionOr(config.wallRestitution),
              kind: BounceKind.obstacle,
              surfaceVelocity: hen.velocity,
            );
          }
        }
      }
      // On the ground: the first lip the egg's centre rolls over, a ledge's
      // from its high side or a kicker's either way, if that comes before
      // anything it would hit. A fall is gravity, so a ghost egg drops too
      // (and a ghost flies off a kicker like any egg). In the air the egg
      // is over them all.
      if (!flying) {
        for (final wall in hole.walls) {
          if (!moving) break;
          if (!wall.ledge) continue;
          final t = _ledgeCrossing(ball.position, delta, wall.a, wall.b);
          if (t == null || (best != null && best.t <= t)) continue;
          best = _SweepHit(
            t: t,
            normal: _lowSideOf(wall.a, wall.b),
            restitution: 0,
            kind: BounceKind.wall,
            drop: true,
          );
        }
        for (var i = 0; i < hole.kickers.length; i++) {
          if (!moving) break;
          final crossing = _lipCrossing(ball.position, delta, hole.kickers[i]);
          if (crossing == null || (best != null && best.t <= crossing.$1)) {
            continue;
          }
          best = _SweepHit(
            t: crossing.$1,
            normal: crossing.$2,
            restitution: 0,
            kind: BounceKind.wall,
            kicker: i,
          );
        }
      }

      if (best == null) {
        ball.position = ball.position + delta;
        break;
      }

      ball.position = ball.position + delta * best.t;
      ball.position = ball.position + best.normal * 1e-6;
      ball.asleep = false;
      final kicker = best.kicker;
      if (kicker != null) {
        if (_overLip(ball, hole.kickers[kicker])) {
          airFrom = fraction + best.t * remainingFraction;
        }
      } else if (best.drop) {
        _dropOff(ball, best.normal);
      } else {
        _reflectAtSurface(ball, best);
      }
      fraction = (fraction + best.t * remainingFraction + 1e-9).clamp(0.0, 1.0);
      bounces++;
    }
    if (ball.airborne) _fly(ball, (1 - airFrom) * config.dt);
  }

  /// An egg rolling over [kicker]'s lip: off the ground when it goes the
  /// kicker's way at its threshold or faster, off the lip's height with
  /// its ground speed kept and a climb of its pace along the kicker times
  /// the pitch (capped); else a bump that costs it a little pace. Whether
  /// it flew.
  bool _overLip(BallBody ball, Kicker kicker) {
    final along = ball.velocity.dot(kicker.direction);
    if (along >= kicker.threshold) {
      ball.air = hole.groundHeightAt(ball.position) + kicker.height;
      ball.airSpeed = math.min(along * kicker.pitch, config.kickerMaxLift);
      _events.add(BallLaunched(
          playerId: ball.playerId, at: ball.position, speed: along));
      return true;
    }
    ball.velocity = ball.velocity * config.kickerBumpKeep;
    _events.add(BallBumped(playerId: ball.playerId, at: ball.position));
    return false;
  }

  /// Carries an egg's flight [seconds] on: its climb slows under
  /// [PhysicsConfig.airGravity], then turns into a fall.
  void _fly(BallBody ball, double seconds) {
    ball.air = ball.air! +
        ball.airSpeed * seconds -
        0.5 * config.airGravity * seconds * seconds;
    ball.airSpeed -= config.airGravity * seconds;
  }

  /// A flying egg's altitude at [at] of the tick, its flight state holding
  /// from [from] of it.
  double _altitudeAt(BallBody ball, double from, double at) {
    final t = (at - from) * config.dt;
    return ball.air! + ball.airSpeed * t - 0.5 * config.airGravity * t * t;
  }

  /// The top an egg in the air must clear to pass over [ledge] by [near]:
  /// the ground just up on its high side, by the point of it nearest
  /// [near] (a terrace's height, or a ramp's along its side).
  double _ledgeTop(WallSegment ledge, Vec2 near) {
    final closest = _closestPointOnSegment(near, ledge.a, ledge.b);
    return hole.groundHeightAt(closest + ledge.highSide * 0.05);
  }

  /// A flying egg that has come down to the ground under it lands, keeping
  /// [PhysicsConfig.landingKeep] of its ground speed; a hard landing gives
  /// [PhysicsConfig.landingBounce] of its fall's speed back as a bounce up,
  /// when that beats [PhysicsConfig.landingHopSpeed], and the egg flies a
  /// little hop more. Otherwise it rolls on. Whether it touched down.
  bool _touchdown(BallBody ball) {
    final ground = hole.groundHeightAt(ball.position);
    if (ball.air! > ground) return false;
    final falling = math.max(0.0, -ball.airSpeed);
    ball.velocity = ball.velocity * config.landingKeep;
    _events.add(BallLanded(
        playerId: ball.playerId, at: ball.position, impactSpeed: falling));
    final bounce = falling * config.landingBounce;
    if (bounce > config.landingHopSpeed) {
      ball.air = ground;
      ball.airSpeed = bounce;
    } else {
      ball.ground();
    }
    return true;
  }

  /// An egg rolling over a ledge's lip falls to the low side, carried
  /// clear of the face: its pace away from the ledge ([lowSide]) is raised
  /// to at least [PhysicsConfig.ledgeDropSpeed], the rest of its motion
  /// kept.
  void _dropOff(BallBody ball, Vec2 lowSide) {
    final away = ball.velocity.dot(lowSide);
    if (away < config.ledgeDropSpeed) {
      ball.velocity =
          _clamped(ball.velocity + lowSide * (config.ledgeDropSpeed - away));
    }
    _events.add(BallDropped(playerId: ball.playerId, at: ball.position));
  }

  /// Bounces an egg off the surface [hit]: in a moving surface's frame,
  /// reflect the approach speed with the surface's restitution.
  void _reflectAtSurface(BallBody ball, _SweepHit hit) {
    final approach = hit.surfaceVelocity == Vec2.zero
        ? ball.velocity
        : ball.velocity - hit.surfaceVelocity;
    final into = approach.dot(hit.normal);
    if (into >= 0) return;
    final reflected = approach - hit.normal * ((1 + hit.restitution) * into);
    ball.velocity = hit.surfaceVelocity == Vec2.zero
        ? reflected
        : reflected + hit.surfaceVelocity;
    _events.add(BallBounced(
      playerId: ball.playerId,
      kind: hit.kind,
      impactSpeed: -into,
      at: ball.position,
    ));
  }

  /// Pushes an overlapping egg out of static geometry before sweeping, so
  /// the sweep never starts inside a wall. An egg in the air over a step
  /// it clears is no step's business, and it is over the hens.
  void _depenetrate(
      BallBody ball, List<_ObstacleSweep> hens, bool ghost, bool hop) {
    final radius = config.ballRadius;
    for (var i = 0; i < 3; i++) {
      var moved = false;
      if (!ghost) {
        for (final wall in hole.walls) {
          if (wall.ledge &&
              ball.airborne &&
              ball.air! >= _ledgeTop(wall, ball.position)) {
            continue;
          }
          moved |= wall.ledge
              ? _pushFromLedge(ball, wall.a, wall.b, radius)
              : _pushFromCapsule(ball, wall.a, wall.b, radius);
        }
        for (final arc in hole.arcs) {
          moved |= _pushFromArc(ball, arc, radius);
        }
        if (!hop && !ball.airborne) {
          for (final hen in hens) {
            // The hen at its tick-start position; its motion is swept.
            final offset = ball.position - hen.start;
            final distance = offset.length;
            final min = hen.obstacle.radius + radius;
            if (distance < min && distance > Vec2.epsilon) {
              ball.position = hen.start + offset * (min / distance);
              moved = true;
            }
          }
        }
      }
      if (!moved) break;
    }
  }

  bool _pushFromCapsule(BallBody ball, Vec2 a, Vec2 b, double radius) {
    final closest = _closestPointOnSegment(ball.position, a, b);
    final offset = ball.position - closest;
    final distance = offset.length;
    if (distance >= radius || distance < Vec2.epsilon) return false;
    ball.position = closest + offset * (radius / distance);
    return true;
  }

  /// A ledge's face pushes out only an egg below it that is not on its way
  /// out: one on the high side hangs over the lip, one that has just
  /// dropped is leaving the face.
  bool _pushFromLedge(BallBody ball, Vec2 a, Vec2 b, double radius) {
    if (_ledgeSide(ball.position, a, b) <= 0) return false;
    if (ball.velocity.dot(_lowSideOf(a, b)) > 0) return false;
    return _pushFromCapsule(ball, a, b, radius);
  }

  bool _pushFromArc(BallBody ball, WallArc arc, double radius) {
    final offset = ball.position - arc.center;
    final distance = offset.length;
    if (distance < Vec2.epsilon) return false;
    if ((distance - arc.radius).abs() >= radius) return false;
    final span = arcSpan(arc);
    if (!_angleInSpan(math.atan2(offset.y, offset.x), span.$1, span.$2)) {
      return false;
    }
    final signed = distance - arc.radius;
    final target = arc.radius + (signed >= 0 ? radius : -radius);
    ball.position = arc.center + offset * (target / distance);
    return true;
  }

  // ---- sensors (order: bounds, water, wells, boosts, portals, boxes, nest) --

  void _sensors(BallBody ball) {
    if (_handleBounds(ball)) return;
    if (_handleWater(ball)) return;
    if (_handleWells(ball)) return;
    _handleBoosts(ball);
    _handlePortals(ball);
    _handleBoxes(ball);
    _handleNest(ball);
  }

  bool _handleBounds(BallBody ball) {
    if (!hole.bounds.contains(ball.position)) {
      final at = ball.position;
      ball.position = _homeFor(ball);
      ball.settle();
      _events.add(BallOutOfBounds(playerId: ball.playerId, at: at));
      return true;
    }
    return false;
  }

  bool _handleWater(BallBody ball) {
    for (final shape in hole.water) {
      if (shape.contains(ball.position)) {
        final at = ball.position;
        ball.position = _homeFor(ball);
        ball.settle();
        _events.add(BallSplashed(playerId: ball.playerId, at: at));
        return true;
      }
    }
    return false;
  }

  bool _handleWells(BallBody ball) {
    for (final well in hole.wells) {
      final swallow = well.swallowRadius;
      if (swallow <= 0) continue;
      if (ball.position.distanceTo(well.position) <= swallow) {
        final at = ball.position;
        ball.position = _homeFor(ball);
        ball.settle();
        _events.add(BallSwallowed(playerId: ball.playerId, at: at));
        return true;
      }
    }
    return false;
  }

  /// Where a bounced-out egg goes back to: its pre-stroke position, unless
  /// that would immediately put it right back into a hazard (in bounds,
  /// dry, out of every well's reach) - then the tee. Authors get a safety
  /// net, never a loop.
  Vec2 _homeFor(BallBody ball) {
    for (final candidate in [ball.lastSafePosition, hole.tee]) {
      if (!hole.bounds.contains(candidate)) continue;
      var safe = true;
      for (final shape in hole.water) {
        if (shape.contains(candidate)) safe = false;
      }
      for (final well in hole.wells) {
        final distance = candidate.distanceTo(well.position);
        if (distance < well.radius &&
            well.strength / distance > frictionDeceleration) {
          safe = false; // resting there creeps straight back in
        }
        if (well.swallowRadius > 0 && distance <= well.swallowRadius) {
          safe = false;
        }
      }
      if (safe) return candidate;
    }
    return ball.lastSafePosition;
  }

  void _handleBoosts(BallBody ball) {
    final inside = _boostsInside(ball.position);
    final previous = _insideBoosts[ball.playerId]!;
    for (var i = 0; i < hole.boosts.length; i++) {
      if (!inside.contains(i) || previous.contains(i)) continue;
      final strip = hole.boosts[i];
      final dir = strip.direction;
      final along = ball.velocity.dot(dir);
      if (along < strip.speed) {
        ball.velocity += dir * (strip.speed - along);
        ball.velocity = _clamped(ball.velocity);
      }
      _events.add(BallBoosted(playerId: ball.playerId, at: ball.position));
    }
    previous
      ..clear()
      ..addAll(inside);
  }

  Set<int> _boostsInside(Vec2 point) {
    final result = <int>{};
    for (var i = 0; i < hole.boosts.length; i++) {
      final strip = hole.boosts[i];
      final closest = _closestPointOnSegment(point, strip.from, strip.to);
      if (point.distanceTo(closest) <=
          strip.width / 2 + config.ballRadius * 0.5) {
        result.add(i);
      }
    }
    return result;
  }

  void _handlePortals(BallBody ball) {
    if (ball.portalCooldown > 0) return;
    for (final pair in hole.portals) {
      final atA = ball.position.distanceTo(pair.a) <= pair.radius;
      final atB = ball.position.distanceTo(pair.b) <= pair.radius;
      if (!atA && !atB) continue;
      final exit = atA ? pair.b : pair.a;
      ball.position = exit;
      ball.portalCooldown = config.portalCooldownTicks;
      // A slow egg pops out with pace enough to roll clear of the hole.
      final speed = ball.velocity.length;
      if (speed > Vec2.epsilon && speed < config.portalExitSpeed) {
        ball.velocity = ball.velocity * (config.portalExitSpeed / speed);
      }
      ball.asleep = false;
      _insideBoosts[ball.playerId] = _boostsInside(exit).toSet();
      _events.add(BallTeleported(playerId: ball.playerId, portalId: pair.id));
      return;
    }
  }

  bool _overAnyPortal(Vec2 point) {
    for (final pair in hole.portals) {
      if (point.distanceTo(pair.a) <= pair.radius ||
          point.distanceTo(pair.b) <= pair.radius) {
        return true;
      }
    }
    return false;
  }

  void _handleBoxes(BallBody ball) {
    for (final box in hole.boxes) {
      if (_collectedBoxes.contains(box.id)) continue;
      if (ball.position.distanceTo(box.position) <=
          box.radius + config.ballRadius * 0.5) {
        _collectedBoxes.add(box.id);
        _events.add(BallPickedBox(playerId: ball.playerId, boxId: box.id));
      }
    }
  }

  void _handleNest(BallBody ball) {
    if (ball.holed) return;
    final distance = ball.position.distanceTo(hole.nest.position);
    if (distance > hole.nest.radius - config.ballRadius * 0.5) return;
    if (ball.velocity.length > config.captureSpeed) return;
    ball.position = hole.nest.position;
    ball.velocity = Vec2.zero;
    ball.holed = true;
    ball.asleep = true;
    ball.clearTransientFlags();
    _events.add(BallCaptured(playerId: ball.playerId));
  }

  void _ballVsBalls() {
    final list = balls;
    final tiered = hole.terraces.isNotEmpty || hole.ramps.isNotEmpty;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i];
        final b = list[j];
        if (a.holed || b.holed) continue;
        // An egg in the air passes over the others.
        if (a.airborne || b.airborne) continue;
        final offset = b.position - a.position;
        final distance = offset.length;
        final min = config.ballRadius * 2;
        if (distance >= min) continue;
        // Eggs a step apart (one on a lip, one at the face's foot below)
        // pass over and under each other.
        if (tiered &&
            (hole.tierHeightAt(a.position) - hole.tierHeightAt(b.position))
                    .abs() >
                config.ballRadius) {
          continue;
        }
        final normal = distance < Vec2.epsilon
            ? const Vec2(0, -1)
            : offset * (1 / distance);
        final overlap = min - distance;
        a.position -= normal * (overlap / 2);
        b.position += normal * (overlap / 2);
        final closing = (b.velocity - a.velocity).dot(normal);
        if (closing < 0) {
          final impulse = (1 + config.ballRestitution) * closing / 2;
          a.velocity += normal * impulse;
          b.velocity -= normal * impulse;
          a.asleep = false;
          b.asleep = false;
          _events.add(BallBounced(
            playerId: a.playerId,
            kind: BounceKind.ball,
            impactSpeed: -closing,
            at: a.position,
            otherPlayerId: b.playerId,
          ));
          _events.add(BallBounced(
            playerId: b.playerId,
            kind: BounceKind.ball,
            impactSpeed: -closing,
            at: b.position,
            otherPlayerId: a.playerId,
          ));
        }
      }
    }
  }

  // ---- serialization -------------------------------------------------------

  Map<String, Object?> toJson() => {
        'tick': _tick,
        'boxes': _collectedBoxes.toList()..sort(),
        'balls': [for (final id in _order) _balls[id]!.toJson()],
      };

  /// Rebuilds a world mid-hole from [state] (as [toJson] produced), against
  /// the same [hole] and [config] the original ran with.
  factory PhysicsWorld.restore({
    required HoleDef hole,
    required PhysicsConfig config,
    required Map<String, Object?> state,
  }) {
    final world = PhysicsWorld(hole: hole, config: config);
    world._tick = (state['tick'] as num).toInt();
    world._collectedBoxes
      ..clear()
      ..addAll((state['boxes'] as List).cast<String>());
    for (final raw in state['balls'] as List) {
      final json = raw as Map<String, Object?>;
      final id = json['id'] as String;
      world._balls[id] = BallBody(
        playerId: id,
        position:
            Vec2((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
        velocity: Vec2(
            (json['vx'] as num).toDouble(), (json['vy'] as num).toDouble()),
        holed: json['holed'] == true,
        asleep: json['asleep'] == true,
        portalCooldown: (json['cd'] as num).toInt(),
        air: (json['air'] as num?)?.toDouble(),
        airSpeed: (json['vz'] as num?)?.toDouble() ?? 0,
      )..lastSafePosition =
          Vec2((json['sx'] as num).toDouble(), (json['sy'] as num).toDouble());
      final timed = json['timed'] as Map;
      for (final entry in timed.entries) {
        world._balls[id]!
                .timedUntil[PowerUpFlag.values.byName(entry.key as String)] =
            (entry.value as num).toInt();
      }
      for (final name in (json['rest'] as List).cast<String>()) {
        world._balls[id]!.untilRest.add(PowerUpFlag.values.byName(name));
      }
    }
    world._rebuildOrder();
    for (final id in world._order) {
      world._insideBoosts[id] =
          world._boostsInside(world._balls[id]!.position).toSet();
    }
    return world;
  }
}

// ---- sweeps ------------------------------------------------------------------

class _SweepHit {
  /// Fraction within the swept window [0, 1].
  final double t;

  /// Against the motion, pointing back at the egg.
  final Vec2 normal;
  final double restitution;
  final BounceKind kind;

  /// The surface's own velocity (the hen); zero for static geometry.
  final Vec2 surfaceVelocity;

  /// Not a hit but a fall: the egg's centre rolls over a ledge's lip
  /// here, [normal] pointing to the low side.
  final bool drop;

  /// Not a hit but a kicker's lip, by its index in the hole: the egg's
  /// centre crosses it here, [normal] pointing the way it crosses.
  final int? kicker;

  const _SweepHit({
    required this.t,
    required this.normal,
    required this.restitution,
    required this.kind,
    this.surfaceVelocity = Vec2.zero,
    this.drop = false,
    this.kicker,
  });
}

/// A kinematic obstacle over one tick: positions at both ends (linear in
/// between - stop durations are whole ticks), plus the relative sweep.
class _ObstacleSweep {
  final MovingObstacle obstacle;
  final double tickSeconds;
  late final Vec2 start;
  late final Vec2 end;

  _ObstacleSweep(this.obstacle, int tick, this.tickSeconds) {
    start = positionAt(obstacle, tick - 1, tickSeconds);
    end = positionAt(obstacle, tick, tickSeconds);
  }

  Vec2 get velocity => (end - start) * (1 / tickSeconds);

  /// Position at [fraction] of the ongoing tick.
  Vec2 at(double fraction) => start.lerp(end, fraction.clamp(0.0, 1.0));

  /// Swept egg (radius [eggRadius], displaced [delta] over the remaining
  /// [remainingFraction] of the tick, currently at global [fraction]) vs
  /// this obstacle. Returns (t within the window, normal toward the egg).
  (double, Vec2)? sweep(
      Vec2 eggPos, double eggRadius, Vec2 delta, double fraction) {
    final obstacleNow = at(fraction);
    final obstacleDelta = end - obstacleNow;
    final relative = delta - obstacleDelta;
    return sweepSphere(
        eggPos - obstacleNow, relative, obstacle.radius + eggRadius);
  }

  /// The obstacle's position at [tick]: walk the looping stop path. Times
  /// are rounded to whole ticks, so positions repeat exactly forever.
  static Vec2 positionAt(
      MovingObstacle obstacle, int tick, double tickSeconds) {
    final stops = obstacle.stops;
    if (stops.isEmpty) return Vec2.zero;
    if (stops.length == 1) return stops.first.at;
    final n = stops.length;
    final travel = [
      for (final s in stops) (s.travelSecondsToNext / tickSeconds).round(),
    ];
    final dwell = [
      for (final s in stops) (s.dwellSeconds / tickSeconds).round(),
    ];
    var period = 0;
    for (var i = 0; i < n; i++) {
      period += dwell[i] + travel[i];
    }
    if (period <= 0) return stops.first.at;
    var phase = tick % period;
    if (phase < 0) phase += period;
    var index = 0;
    var guard = 0;
    while (guard++ <= n * 2) {
      if (phase < dwell[index]) return stops[index].at;
      phase -= dwell[index];
      if (phase < travel[index]) {
        final next = (index + 1) % n;
        return stops[index].at.lerp(stops[next].at, phase / travel[index]);
      }
      phase -= travel[index];
      index = (index + 1) % n;
    }
    return stops.first.at;
  }
}

/// Normalized (start, sweep) of an arc, sweep in (0, 2pi].
(double, double) arcSpan(WallArc arc) {
  final twoPi = 2 * math.pi;
  var start = arc.startAngle % twoPi;
  if (start < 0) start += twoPi;
  var sweep = arc.sweep % twoPi;
  if (sweep <= 1e-9) sweep = twoPi;
  return (start, sweep);
}

bool _angleInSpan(double theta, double start, double sweep) {
  final twoPi = 2 * math.pi;
  var diff = (theta - start) % twoPi;
  if (diff < 0) diff += twoPi;
  return diff <= sweep + 1e-9;
}

/// Closest point to [p] on segment [a, b].
Vec2 _closestPointOnSegment(Vec2 p, Vec2 a, Vec2 b) {
  final u = b - a;
  final l2 = u.dot(u);
  if (l2 < Vec2.epsilon * Vec2.epsilon) return a;
  final t = ((p - a).dot(u) / l2).clamp(0.0, 1.0).toDouble();
  return a + u * t;
}

/// Swept sphere (start [p], displacement [d], radius [radius]) against a
/// POINT center: returns (t in (0, 1], normal pointing from the point to
/// the sphere at contact), or null. A start already inside returns an
/// immediate push back against the motion.
(double, Vec2)? sweepSphere(Vec2 p, Vec2 d, double radius) {
  final a = d.dot(d);
  if (a < 1e-18) return null;
  final b = 2 * p.dot(d);
  final c = p.dot(p) - radius * radius;
  if (c <= 0) {
    // Already touching: push back against the motion; the positional fix
    // happens in the caller.
    return (0.0, d * (-1 / math.sqrt(a)));
  }
  final disc = b * b - 4 * a * c;
  if (disc < 0) return null;
  final t = (-b - math.sqrt(disc)) / (2 * a);
  if (t <= 1e-9 || t > 1) return null;
  final contact = p + d * t;
  final distance = contact.length;
  if (distance < 1e-12) return null;
  return (t, contact * (1 / distance));
}

/// Swept circle (start [p], displacement [d], radius [radius]) against the
/// capsule around segment [a, b]: exact earliest (t, normal), no
/// tunneling at any speed.
(double, Vec2)? _sweepCapsule(Vec2 p, Vec2 d, double radius, Vec2 a, Vec2 b) {
  (double, Vec2)? best;

  void consider((double, Vec2)? hit) {
    if (hit == null || hit.$1 <= 1e-9 || hit.$1 > 1) return;
    if (best == null || hit.$1 < best!.$1) best = hit;
  }

  consider(sweepSphere(p - a, d, radius));
  consider(sweepSphere(p - b, d, radius));

  final u = b - a;
  final l2 = u.dot(u);
  if (l2 > 1e-12) {
    final n = Vec2(-u.y, u.x) * (1 / math.sqrt(l2));
    final dist0 = (p - a).dot(n);
    final dn = d.dot(n);
    if (dn.abs() > 1e-12) {
      for (final side in [1.0, -1.0]) {
        final surface = side * radius;
        final t = (surface - dist0) / dn;
        // Approaching that side only when the distance to it is closing.
        if (t > 1e-9 && t <= 1 && (dist0 - surface) * dn < 0) {
          final q = p + d * t;
          final s = (q - a).dot(u) / l2;
          if (s >= -1e-9 && s <= 1 + 1e-9) {
            consider((t, n * side));
          }
        }
      }
    }
  }
  return best;
}

/// The unit normal of the ledge [a]-[b] pointing to its low side: the
/// right of a->b as drawn (its high side is the left).
Vec2 _lowSideOf(Vec2 a, Vec2 b) {
  final u = b - a;
  return Vec2(-u.y, u.x).normalized();
}

/// The signed distance from the ledge [a]-[b]'s line to [p]: positive on
/// its low side, negative on its high side.
double _ledgeSide(Vec2 p, Vec2 a, Vec2 b) => (p - a).dot(_lowSideOf(a, b));

/// Swept circle (start [p], displacement [d], radius [radius]) against a
/// ledge: only the face on its low side stops an egg, met heading up into
/// it, and the ledge's two ends for an egg below it - from the high side
/// it is a lip to roll over (see [_ledgeCrossing]). Same returns as
/// [_sweepCapsule].
(double, Vec2)? _sweepLedge(Vec2 p, Vec2 d, double radius, Vec2 a, Vec2 b) {
  final u = b - a;
  final l2 = u.dot(u);
  if (l2 < 1e-12) return null;
  final n = Vec2(-u.y, u.x) * (1 / math.sqrt(l2)); // to the low side
  (double, Vec2)? best;

  void consider((double, Vec2)? hit) {
    if (hit == null || hit.$1 <= 1e-9 || hit.$1 > 1) return;
    if (best == null || hit.$1 < best!.$1) best = hit;
  }

  // The face, [radius] off the line on the low side.
  final dist0 = (p - a).dot(n);
  final dn = d.dot(n);
  if (dist0 > radius && dn < -1e-12) {
    final t = (radius - dist0) / dn;
    if (t > 1e-9 && t <= 1) {
      final s = (p + d * t - a).dot(u) / l2;
      if (s >= -1e-9 && s <= 1 + 1e-9) consider((t, n));
    }
  }
  // The ends, met from below.
  for (final end in [a, b]) {
    final hit = sweepSphere(p - end, d, radius);
    if (hit == null) continue;
    if ((p + d * hit.$1 - a).dot(n) <= 0) continue;
    consider(hit);
  }
  return best;
}

/// Where the centre of an egg moving from [p] by [d] rolls over the
/// ledge [a]-[b] from its high side to its low side, as a fraction of
/// [d] in (0, 1], or null when it does not.
double? _ledgeCrossing(Vec2 p, Vec2 d, Vec2 a, Vec2 b) {
  final u = b - a;
  final l2 = u.dot(u);
  if (l2 < 1e-12) return null;
  final n = Vec2(-u.y, u.x) * (1 / math.sqrt(l2)); // to the low side
  final dist0 = (p - a).dot(n);
  final dn = d.dot(n);
  if (dist0 >= 0 || dn <= 1e-12) return null;
  final t = -dist0 / dn;
  if (t <= 1e-9 || t > 1) return null;
  final s = (p + d * t - a).dot(u) / l2;
  if (s < 0 || s > 1) return null;
  return t;
}

/// Where the centre of an egg moving from [p] by [d] crosses [kicker]'s
/// lip within its width, as a fraction of [d] in [0, 1], and the way it
/// crosses: the kicker's direction, or back against it. Null when it does
/// not cross.
(double, Vec2)? _lipCrossing(Vec2 p, Vec2 d, Kicker kicker) {
  final way = kicker.direction;
  final dist0 = (p - kicker.to).dot(way);
  final dn = d.dot(way);
  if (dn.abs() <= 1e-12) return null;
  final t = -dist0 / dn;
  if (t < 0 || t > 1) return null;
  final across = (p + d * t - kicker.to).dot(Vec2(way.y, -way.x));
  if (across.abs() > kicker.width / 2) return null;
  return (t, dn > 0 ? way : way * -1);
}

/// Swept circle vs a [WallArc] (a zero-thickness curve the egg can touch
/// from either side): radial band entries within the arc's angular span,
/// plus its two end caps.
(double, Vec2)? _sweepArc(Vec2 p, Vec2 d, double radius, WallArc arc) {
  final c = arc.center;
  final e = p - c;
  final a = d.dot(d);
  if (a < 1e-18) return null;
  final span = arcSpan(arc);

  (double, Vec2)? best;

  void consider((double, Vec2)? hit) {
    if (hit == null || hit.$1 <= 1e-9 || hit.$1 > 1) return;
    if (best == null || hit.$1 < best!.$1) best = hit;
  }

  // Radial contacts: the egg's center reaching distance R + r (outside
  // face) or R - r (inside face).
  final targets = <double>[arc.radius + radius];
  if (arc.radius - radius > 1e-6) targets.add(arc.radius - radius);
  for (final target in targets) {
    final b = 2 * e.dot(d);
    final c0 = e.dot(e) - target * target;
    final disc = b * b - 4 * a * c0;
    if (disc < 0) continue;
    final double t;
    if (c0 > 0) {
      // Outside the ring, closing in: the first crossing.
      t = (-b - math.sqrt(disc)) / (2 * a);
    } else if (target < arc.radius) {
      // Inside the inner ring, heading out: the inside face, met where
      // the egg would leave that ring.
      t = (-b + math.sqrt(disc)) / (2 * a);
    } else {
      continue; // inside the outer ring: the inner one decides
    }
    if (t <= 1e-9 || t > 1) continue;
    final q = p + d * t;
    final offset = q - c;
    final rho = offset.length;
    if (rho < 1e-12) continue;
    if (!_angleInSpan(math.atan2(offset.y, offset.x), span.$1, span.$2)) {
      continue;
    }
    // Normal points back at the egg's side of the wall face.
    final side = e.length > arc.radius ? 1.0 : -1.0;
    consider((t, offset * (side / rho)));
  }

  // The arc's two end caps act as points.
  for (final angle in [span.$1, span.$1 + span.$2]) {
    final cap = c + Vec2(math.cos(angle), math.sin(angle)) * arc.radius;
    consider(sweepSphere(p - cap, d, radius));
  }

  return best;
}
