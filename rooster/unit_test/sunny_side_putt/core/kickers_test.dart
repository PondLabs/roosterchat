// Kickers: a launch ramp throws an egg that crosses its lip fast enough
// into the air - farther the faster it comes - and lets a slower one roll
// over it with a bump. In the air the egg flies a ballistic arc over the
// water, the sensors, the hens, the other eggs and any step whose top it
// clears, never over a rail, and lands with a bounce that keeps most of
// its pace; the flight rides the snapshot and the journal like everything
// else.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// The kicker every test throws from: its foot at x 7, its lip at x 9,
/// three units wide across the middle of the field, throwing east.
const Kicker kicker = Kicker(Vec2(7, 6), Vec2(9, 6), width: 3);

/// A long field (40 by 12) with the kicker, and whatever else is passed.
HoleDef field({
  List<WaterShape> water = const [],
  List<WallSegment> walls = const [],
  List<Terrace> terraces = const [],
  List<BoostStrip> boosts = const [],
  List<PortalPair> portals = const [],
  List<QuestionBox> boxes = const [],
  List<MovingObstacle> obstacles = const [],
}) =>
    boxHole(
      width: 40,
      height: 12,
      tee: const Vec2(3, 6),
      nest: const Nest(Vec2(37, 10.5), 0.8),
      kickers: const [kicker],
      water: water,
      extraWalls: walls,
      terraces: terraces,
      boosts: boosts,
      portals: portals,
      boxes: boxes,
      obstacles: obstacles,
    );

PhysicsWorld worldOn(HoleDef hole, [List<String> ids = const ['a']]) =>
    PhysicsWorld(hole: hole, config: testPhysics, playerIds: ids);

/// Sends egg [id] east along the middle of the field from just short of
/// the lip, so it crosses it at about [speed] units/s.
BallBody sendAtLip(PhysicsWorld world, double speed,
    {String id = 'a', double from = 8.8}) {
  final ball = world.ball(id)!;
  // The friction over the run-up to the lip, made good.
  final start = math
      .sqrt(speed * speed + 2 * testPhysics.frictionDeceleration * (9 - from));
  ball
    ..position = Vec2(from, 6)
    ..velocity = Vec2(start, 0)
    ..asleep = false;
  return ball;
}

/// Steps [world] until egg [id] rests (or [maxTicks] pass), gathering the
/// world's events.
List<PhysicsEvent> runOut(PhysicsWorld world,
    {String id = 'a', int maxTicks = 3000}) {
  final ball = world.ball(id)!;
  final events = <PhysicsEvent>[];
  for (var i = 0; i < maxTicks && !ball.asleep && !ball.holed; i++) {
    world.stepTick();
    events.addAll(world.drainEvents());
  }
  return events;
}

/// Where the egg first came down after leaving the lip at [speed].
double firstLanding(double speed) {
  final world = worldOn(field());
  sendAtLip(world, speed);
  final landing = runOut(world).whereType<BallLanded>().first;
  return landing.at.x;
}

void main() {
  group('a kicker\'s shape', () {
    test('its deck curves up from the foot to meet the lip at its pitch', () {
      expect(kicker.length, 2);
      expect(kicker.direction, const Vec2(1, 0));
      expect(kicker.launchAngleDegrees, closeTo(26.565, 1e-3));
      expect(kicker.deckHeightAt(const Vec2(7, 6)), 0);
      expect(kicker.deckHeightAt(const Vec2(9, 6)), closeTo(0.45, 1e-12));
      expect(kicker.deckHeightAt(const Vec2(8, 7.4)), greaterThan(0),
          reason: 'level across its width');
      expect(kicker.deckHeightAt(const Vec2(8, 7.6)), 0, reason: 'off it');
      expect(kicker.deckHeightAt(const Vec2(9.1, 6)), 0, reason: 'past it');
      // Rising all the way, and leaving the lip at the launch's pitch.
      var last = 0.0;
      for (var x = 7.1; x < 9; x += 0.1) {
        final h = kicker.deckHeightAt(Vec2(x, 6));
        expect(h, greaterThan(last));
        last = h;
      }
      expect(kicker.deckGradientAt(const Vec2(8.9999, 6)).x,
          closeTo(kicker.pitch, 1e-3));
      expect(kicker.deckGradientAt(const Vec2(8, 6)).y, 0);
      // Its lip and its outline, walking up the deck (east).
      expect(kicker.lip, (const Vec2(9, 4.5), const Vec2(9, 7.5)));
      expect(kicker.corners, const [
        Vec2(7, 4.5),
        Vec2(9, 4.5),
        Vec2(9, 7.5),
        Vec2(7, 7.5),
      ]);
      expect(kicker.covers(const Vec2(8, 6)), isTrue);
      expect(kicker.covers(const Vec2(9.2, 6)), isFalse);
    });

    test('a hole reads the deck under a point, the physics never does', () {
      final hole = field();
      expect(hole.kickerDeckHeightAt(const Vec2(9, 6)), closeTo(0.45, 1e-12));
      expect(hole.kickerDeckHeightAt(const Vec2(20, 6)), 0);
      expect(hole.kickerDeckGradientAt(const Vec2(8, 6)).x, greaterThan(0));
      expect(hole.groundHeightAt(const Vec2(8.5, 6)), 0,
          reason: 'the ground under the deck stays the green');
      expect(hole.hasRelief, isFalse);
    });
  });

  group('the lip', () {
    test('throws an egg into the air at its threshold or faster', () {
      final world = worldOn(field());
      final ball = sendAtLip(world, 9);
      final events = <PhysicsEvent>[];
      while (!ball.airborne) {
        world.stepTick();
        events.addAll(world.drainEvents());
      }
      final launch = events.whereType<BallLaunched>().single;
      expect(launch.playerId, 'a');
      expect(launch.at.x, closeTo(9, 1e-5));
      expect(launch.speed, closeTo(9, 0.1));
      // Off the lip's height, climbing at its pace along it times the pitch.
      expect(ball.air, greaterThan(kicker.height));
      expect(ball.air, lessThan(kicker.height + 0.05));
      expect(ball.airSpeed, closeTo(9 * kicker.pitch, 0.15));
      expect(ball.asleep, isFalse);
    });

    test('lets a slower egg roll over it, a little pace lost', () {
      final world = worldOn(field());
      final ball = sendAtLip(world, 6.5);
      final events = <PhysicsEvent>[];
      var speedBefore = ball.speed;
      while (events.whereType<BallBumped>().isEmpty) {
        speedBefore = ball.speed;
        world.stepTick();
        events.addAll(world.drainEvents());
        expect(ball.airborne, isFalse);
      }
      final crossing = events.whereType<BallBumped>().single;
      expect(crossing.at.x, closeTo(9, 1e-5));
      expect(events.whereType<BallLaunched>(), isEmpty);
      // Over the lip it keeps the bump's share (less a tick's friction).
      final tickFriction = testPhysics.frictionDeceleration * testPhysics.dt;
      expect(
          ball.speed,
          closeTo(
              (speedBefore - tickFriction) * testPhysics.kickerBumpKeep, 1e-9));
      expect(ball.speed, closeTo(6.5 * testPhysics.kickerBumpKeep, 0.15));
      // And it rolls on, on the ground.
      final rest = runOut(world);
      expect(rest.whereType<BallBumped>(), isEmpty);
      expect(ball.airborne, isFalse);
      expect(ball.position.x, greaterThan(10));
    });

    test('crossed against the way it throws, it is only a bump', () {
      final world = worldOn(field());
      final ball = world.ball('a')!
        ..position = const Vec2(9.6, 6)
        ..velocity = const Vec2(-14, 0)
        ..asleep = false;
      final events = runOut(world);
      expect(events.whereType<BallLaunched>(), isEmpty);
      expect(events.whereType<BallBumped>(), hasLength(1));
      expect(ball.airborne, isFalse);
    });

    test('off its width, past the deck\'s side, nothing happens', () {
      final world = worldOn(field());
      final ball = world.ball('a')!
        ..position = const Vec2(8, 8.2)
        ..velocity = const Vec2(14, 0)
        ..asleep = false;
      final events = runOut(world);
      expect(events.whereType<BallLaunched>(), isEmpty);
      expect(events.whereType<BallBumped>(), isEmpty);
      expect(ball.position.x, greaterThan(15));
    });
  });

  group('the flight', () {
    test('flies farther the faster the egg comes', () {
      final landings = [
        for (final speed in [8.0, 10.0, 12.0]) firstLanding(speed)
      ];
      expect(landings[0], greaterThan(10));
      expect(landings[1], greaterThan(landings[0] + 1));
      expect(landings[2], greaterThan(landings[1] + 1));
    });

    test('is the arc gravity draws, and lands with a bounce', () {
      const speed = 10.0;
      final world = worldOn(field());
      final ball = sendAtLip(world, speed);
      while (!ball.airborne) {
        world.stepTick();
      }
      world.drainEvents();
      var apex = ball.air!;
      final heading = ball.velocity;
      while (ball.airborne) {
        apex = math.max(apex, ball.air!);
        expect(ball.velocity.x, closeTo(heading.x, 1e-9),
            reason: 'nothing rubs it in the air');
        world.stepTick();
        if (world.pendingEventCount > 0) break;
      }
      // Up off the lip at the pitch, down under the air's gravity.
      final lift = speed * kicker.pitch;
      expect(
          apex,
          closeTo(kicker.height + lift * lift / (2 * testPhysics.airGravity),
              0.08));
      final landed = world.drainEvents().whereType<BallLanded>().single;
      expect(landed.impactSpeed, greaterThan(lift));
      // Most of its pace kept, and a hard landing hops it up once more.
      expect(ball.speed, closeTo(heading.x * testPhysics.landingKeep, 0.01));
      expect(ball.airborne, isTrue);
      expect(ball.airSpeed,
          closeTo(landed.impactSpeed * testPhysics.landingBounce, 1e-9));
      final rest = runOut(world);
      expect(rest.whereType<BallLanded>(), hasLength(1),
          reason: 'the hop comes down soft and rolls');
      expect(ball.airborne, isFalse);
      expect(ball.asleep, isTrue);
    });

    test('a hard putt flies no higher than the lift allows, only farther', () {
      double apexAt(double speed) {
        final world = worldOn(field());
        final ball = sendAtLip(world, speed);
        var apex = 0.0;
        for (var i = 0; i < 600; i++) {
          world.stepTick();
          if (ball.airborne) apex = math.max(apex, ball.air!);
        }
        return apex;
      }

      final cap = testPhysics.kickerMaxLift;
      final top = kicker.height + cap * cap / (2 * testPhysics.airGravity);
      expect(apexAt(20), closeTo(top, 0.02));
      expect(apexAt(24), closeTo(top, 0.02));
      expect(firstLanding(24), greaterThan(firstLanding(20)));
    });

    test('passes over the water, and an egg that only rolls over swims', () {
      final moat = [const WaterRect(Rect(Vec2(10, 0), Vec2(15, 12)))];
      final flying = worldOn(field(water: moat));
      final flyer = sendAtLip(flying, 11);
      final flight = runOut(flying);
      expect(flight.whereType<BallSplashed>(), isEmpty);
      expect(flight.whereType<BallLanded>().first.at.x, greaterThan(15));
      expect(flyer.position.x, greaterThan(15));

      final rolling = worldOn(field(water: moat));
      sendAtLip(rolling, 6.5);
      expect(runOut(rolling).whereType<BallSplashed>(), hasLength(1));
    });

    test('a touchdown in the water swims, bounce or not', () {
      // The moat's far bank just past where the first landing falls.
      final landing = firstLanding(11);
      final world = worldOn(field(water: [
        WaterRect(Rect(const Vec2(10, 0), Vec2(landing + 0.5, 12))),
      ]));
      sendAtLip(world, 11);
      final events = runOut(world);
      expect(events.whereType<BallLanded>(), hasLength(1));
      expect(events.whereType<BallSplashed>(), hasLength(1));
    });

    test('clears a step up onto its terrace, and one too low meets its face',
        () {
      final hole = field(
        terraces: const [
          Terrace([Vec2(13, 0), Vec2(13, 12), Vec2(30, 12), Vec2(30, 0)],
              height: 0.8),
        ],
        walls: [
          WallSegment.ledge(const Vec2(13, 0), const Vec2(13, 12)),
          WallSegment.ledge(const Vec2(30, 12), const Vec2(30, 0)),
        ],
      );
      final up = worldOn(hole);
      final climber = sendAtLip(up, 12);
      final events = runOut(up);
      expect(events.whereType<BallBounced>(), isEmpty);
      final landing = events.whereType<BallLanded>().first;
      expect(landing.at.x, greaterThan(13));
      expect(hole.tierHeightAt(landing.at), 0.8);
      expect(hole.tierHeightAt(climber.position), 0.8,
          reason: 'it rolls on along the terrace');

      final low = worldOn(hole);
      final short = sendAtLip(low, 8);
      final knocked = runOut(low);
      final face = knocked.whereType<BallBounced>().first;
      expect(face.kind, BounceKind.wall);
      expect(face.at.x, closeTo(13 - testPhysics.ballRadius, 0.01));
      expect(short.position.x, lessThan(13));
      expect(hole.tierHeightAt(short.position), 0);
    });

    test('never flies over a rail, however high it goes', () {
      final world =
          worldOn(field(walls: const [WallSegment(Vec2(12, 0), Vec2(12, 12))]));
      final ball = sendAtLip(world, 16);
      final events = <PhysicsEvent>[];
      double? heightAtTheRail;
      for (var i = 0; i < 3000 && !ball.asleep; i++) {
        world.stepTick();
        final now = world.drainEvents();
        if (now.whereType<BallBounced>().isNotEmpty && ball.airborne) {
          heightAtTheRail ??= ball.air;
        }
        events.addAll(now);
      }
      final knock = events.whereType<BallBounced>().first;
      expect(knock.kind, BounceKind.wall);
      expect(knock.at.x, closeTo(12 - testPhysics.ballRadius, 0.01));
      expect(heightAtTheRail, greaterThan(1),
          reason: 'well over a rail\'s height when it met it');
      expect(ball.position.x, lessThan(12));
    });

    test(
        'passes over the hens, the other eggs, the strips, the rabbit holes '
        'and the crates', () {
      final world = worldOn(
        field(
          boosts: [BoostStrip(const Vec2(10, 6), const Vec2(11, 6), speed: 25)],
          portals: [const PortalPair('burrow', Vec2(12.6, 6), Vec2(36, 2))],
          obstacles: const [
            MovingObstacle(
                id: 'hen', radius: 0.6, stops: [ObstacleStop(Vec2(14.2, 6))]),
          ],
          boxes: [QuestionBox('crate', const Vec2(15.6, 6))],
        ),
        const ['a', 'b'],
      );
      final other = world.ball('b')!;
      world.teleportBall('b', const Vec2(17, 6));
      for (var i = 0; i < 400 && !other.asleep; i++) {
        world.stepTick();
      }
      world.drainEvents();
      final flyer = sendAtLip(world, 13);
      final events = <PhysicsEvent>[];
      while (!flyer.airborne) {
        world.stepTick();
        events.addAll(world.drainEvents());
      }
      while (flyer.airborne && flyer.position.x < 18) {
        world.stepTick();
        events.addAll(world.drainEvents());
      }
      expect(flyer.position.x, greaterThanOrEqualTo(18),
          reason: 'still in the air past them all');
      expect(events.whereType<BallBoosted>(), isEmpty);
      expect(events.whereType<BallTeleported>(), isEmpty);
      expect(events.whereType<BallPickedBox>(), isEmpty);
      expect(events.whereType<BallBounced>(), isEmpty);
      expect(world.collectedBoxes, isEmpty);
      expect(other.position, const Vec2(17, 6));
      expect(other.asleep, isTrue);
    });

    test('a rabbit hole or a swap puts a flying egg on the ground', () {
      final world = worldOn(field(), const ['a', 'b']);
      final ball = sendAtLip(world, 12);
      while (!ball.airborne) {
        world.stepTick();
      }
      world.teleportBall('a', const Vec2(30, 6));
      expect(ball.airborne, isFalse);
      sendAtLip(world, 12);
      while (!ball.airborne) {
        world.stepTick();
      }
      world.swapBalls('a', 'b');
      expect(ball.airborne, isFalse);
      expect(world.ball('b')!.airborne, isFalse);
    });

    test('a cast that moves it in the air does not drown it over the pond', () {
      final world = worldOn(
          field(water: [const WaterRect(Rect(Vec2(10, 0), Vec2(15, 12)))]));
      final ball = sendAtLip(world, 12);
      while (ball.position.x < 11) {
        world.stepTick();
      }
      expect(ball.airborne, isTrue);
      world.impulseBall('a', const Vec2(0, 1));
      world.evaluatePlacement('a');
      expect(ball.airborne, isTrue, reason: 'over the water, not in it');
      expect(world.drainEvents().whereType<BallSplashed>(), isEmpty);
    });
  });

  group('the flight in the record', () {
    test('flies the same arc every time, and through a snapshot mid-air', () {
      HoleDef hole() => field(
            water: const [WaterRect(Rect(Vec2(10, 0), Vec2(14, 12)))],
            terraces: const [
              Terrace([Vec2(20, 0), Vec2(20, 12), Vec2(30, 12), Vec2(30, 0)],
                  height: 0.6),
            ],
            walls: [
              WallSegment.ledge(const Vec2(20, 0), const Vec2(20, 12)),
              WallSegment.ledge(const Vec2(30, 12), const Vec2(30, 0)),
            ],
          );
      Map<String, Object?> fly({int? snapshotAt}) {
        var world = worldOn(hole(), const ['a', 'b']);
        world.teleportBall('a', const Vec2(4, 6.2));
        world.applyShot('a', 0.004, 0.62);
        world.applyShot('b', 0.3, 0.5);
        for (var i = 0; i < 1800; i++) {
          if (i == snapshotAt) {
            final json = jsonDecode(jsonEncode(world.toJson()));
            expect(world.ball('a')!.airborne, isTrue,
                reason: 'the snapshot catches it in the air');
            world = PhysicsWorld.restore(
                hole: hole(),
                config: testPhysics,
                state: (json as Map).cast<String, Object?>());
          }
          world.stepTick();
        }
        return world.toJson();
      }

      // Find a tick when the egg is in the air.
      final probe = worldOn(hole(), const ['a', 'b']);
      probe.teleportBall('a', const Vec2(4, 6.2));
      probe.applyShot('a', 0.004, 0.62);
      probe.applyShot('b', 0.3, 0.5);
      var inAir = -1;
      for (var i = 0; i < 600 && inAir < 0; i++) {
        probe.stepTick();
        if (probe.ball('a')!.airborne) inAir = i + 8;
      }
      expect(inAir, greaterThan(0), reason: 'the putt flies the kicker');

      final first = fly();
      expect(fly().toString(), first.toString());
      expect(fly(snapshotAt: inAir).toString(), first.toString());
    });

    test('an egg in the air rides the engine\'s snapshot and journal', () {
      final config = PuttConfig(
        mode: GameMode.casual,
        seed: 77,
        courses: [
          CourseDef(id: 'kicks', holes: [
            field(water: const [WaterRect(Rect(Vec2(10, 0), Vec2(14, 12)))])
          ]),
        ],
      );
      final engine = PuttEngine(config)
        ..join('p1')
        ..join('p2')
        ..start();
      final tee = engine.world!.ball('p1')!.position;
      expect(engine.submitShot('p1', (const Vec2(9, 6) - tee).angle, 0.62),
          isTrue);
      var guard = 0;
      while (!engine.world!.ball('p1')!.airborne && guard++ < 600) {
        engine.tickForward();
      }
      expect(engine.world!.ball('p1')!.airborne, isTrue);
      final snapshotSeq = engine.lastSeq;
      final snapshot =
          jsonDecode(jsonEncode(engine.toJson())) as Map<String, Object?>;
      expect(
          PuttEngine.fromJson(snapshot, config: config).world!.ball('p1')!.air,
          engine.world!.ball('p1')!.air);
      // A second putt joins the journal while the first egg is still up.
      expect(engine.submitShot('p2', 0.2, 0.4), isTrue);
      for (var i = 0; i < 200; i++) {
        engine.tickForward();
      }
      final journal =
          engine.journalSince(snapshotSeq).map((e) => e.toJson()).toList();
      final handoff = PuttEngine.replay(snapshot, journal,
          config: config, untilTick: engine.tick);
      expect(jsonEncode(handoff.toJson()), jsonEncode(engine.toJson()));
    });
  });
}
