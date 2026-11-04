// Shared fixtures for Sunny Side Putt's core tests: a rectangular hole
// builder, shot-power tuning, and the fake power-up effects the contract
// tests register (the twelve real ones are another ticket's files).
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

const testPhysics = PhysicsConfig();

/// A rectangular hole: walls exactly on the bounds edges, all sensors empty
/// unless passed in.
HoleDef boxHole({
  String id = 'test-hole',
  int par = 2,
  Vec2 tee = const Vec2(2, 5),
  Nest nest = const Nest(Vec2(6, 5), 0.8),
  double width = 16,
  double height = 10,
  double? friction,
  List<WallSegment> extraWalls = const [],
  List<WallArc> arcs = const [],
  List<WaterShape> water = const [],
  List<BoostStrip> boosts = const [],
  List<PortalPair> portals = const [],
  List<GravityWell> wells = const [],
  List<QuestionBox> boxes = const [],
  List<MovingObstacle> obstacles = const [],
}) {
  return HoleDef(
    id: id,
    par: par,
    tee: tee,
    nest: nest,
    bounds: Rect(Vec2.zero, Vec2(width, height)),
    walls: [
      WallSegment(Vec2.zero, Vec2(width, 0)),
      WallSegment(Vec2(width, 0), Vec2(width, height)),
      WallSegment(Vec2(width, height), Vec2(0, height)),
      WallSegment(Vec2(0, height), Vec2.zero),
      ...extraWalls,
    ],
    arcs: arcs,
    obstacles: obstacles,
    water: water,
    boosts: boosts,
    portals: portals,
    wells: wells,
    boxes: boxes,
    friction: friction,
  );
}

/// The power (0..1) that rolls an egg from [from] to just inside the nest's
/// capture zone arriving at [arrivalSpeed] (under the capture gate), for
/// whatever friction the hole's surface uses.
(double angle, double power) puttFor(
  HoleDef hole,
  Vec2 from, {
  PhysicsConfig config = testPhysics,
  double arrivalSpeed = 2.4,
}) =>
    puttToSpeed(
      hole,
      from,
      hole.nest.position,
      arrivalSpeed: arrivalSpeed,
      config: config,
    );

/// The power that rolls an egg from [from] until it nearly stops at [stop].
double puttStopPower(
  HoleDef hole,
  Vec2 from,
  Vec2 stop, {
  PhysicsConfig config = testPhysics,
  double arrivalSpeed = 0.4,
}) {
  final (_, power) =
      puttToSpeed(hole, from, stop, arrivalSpeed: arrivalSpeed, config: config);
  return power;
}

/// The power that arrives at [to] at [arrivalSpeed], along the straight
/// line from [from].
(double angle, double power) puttToSpeed(
  HoleDef hole,
  Vec2 from,
  Vec2 to, {
  PhysicsConfig config = testPhysics,
  double arrivalSpeed = 2.4,
}) {
  final friction = hole.friction ?? config.frictionDeceleration;
  final v0 = math
      .sqrt(arrivalSpeed * arrivalSpeed + 2 * friction * from.distanceTo(to));
  return (
    (to - from).angle,
    (v0 / config.maxShotSpeed).clamp(0.02, 1.0),
  );
}

/// Runs the world until every egg settles (or the cap, so a broken hole
/// can't hang the test), returning the ticks used.
int runUntilSettled(PhysicsWorld world, {int maxTicks = 7200}) {
  var ticks = 0;
  while (!world.allSettled && ticks < maxTicks) {
    world.stepTick();
    ticks++;
  }
  return ticks;
}

// ---- fake power-up effects (contract tests; the real twelve are #227's) ----

/// Harmful area effect: shoves every other egg along +x.
class StormEffect extends PowerUpEffect {
  @override
  String get id => 'test/storm';

  @override
  PowerUpTiming get timing => PowerUpTiming.area;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    for (final ball in context.targetBalls) {
      context.impulseBall(ball.playerId, const Vec2(6, 0));
    }
  }
}

/// Next-shot effect: the caster's next shot is stronger (Strong Coffee).
class CoffeeEffect extends PowerUpEffect {
  @override
  String get id => 'test/coffee';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).powerMultiplier = 1.3;
  }
}

/// Instant effect: grants the caster a shield (Thick Shell).
class ShellEffect extends PowerUpEffect {
  @override
  String get id => 'test/shell';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.addShield(context.casterId);
  }
}

/// Timed effect: the caster's egg ghosts through walls (Ghost Egg).
class GhostEffect extends PowerUpEffect {
  @override
  String get id => 'test/ghost';

  @override
  PowerUpTiming get timing => PowerUpTiming.timed;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.setBallFlagFor(
        context.casterId, PowerUpFlag.ghost, (2 / context.tickSeconds).round());
  }
}

/// Registry with one of each fake, all grantable.
PowerUpRegistry testRegistry() {
  final registry = PowerUpRegistry();
  registry.register(StormEffect());
  registry.register(CoffeeEffect());
  registry.register(ShellEffect());
  registry.register(GhostEffect());
  return registry;
}
