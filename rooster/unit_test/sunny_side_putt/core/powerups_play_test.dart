// The power-ups as a player meets them: the real twelve, on a real engine,
// played the way a match plays them (cast, aim for as long as it takes,
// putt, wait). Each group is one of the reports it holds fixed:
//
//   "the ghost isn't moving through walls", "the corn falling doesn't do
//   anything", "the wind is way too short and weak", "the shield stays on
//   forever", and what a power-up turned on and never putted becomes of
//   from hole to hole and from course to course.
library;

import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/reach.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _tee = Vec2(6, 10);
const _nest = Nest(Vec2(46, 16), 0.95);

/// A long green, the tee at its west end and the nest out of the way in a
/// far corner.
HoleDef _green(
        {String id = 'green',
        List<WallSegment> walls = const [],
        List<WallArc> arcs = const [],
        List<WaterShape> water = const [],
        List<MovingObstacle> hens = const []}) =>
    boxHole(
        id: id,
        par: 3,
        width: 50,
        height: 20,
        tee: _tee,
        nest: _nest,
        extraWalls: walls,
        arcs: arcs,
        water: water,
        obstacles: hens);

/// A rail across the green at x = 16, open at both ends (the far side is
/// still turf an egg can roll to).
final _rail = WallSegment(const Vec2(16, 2), const Vec2(16, 18));

PuttEngine _match(
    {List<HoleDef>? holes,
    List<String> players = const ['p1', 'p2', 'p3'],
    GameMode mode = GameMode.casual,
    List<CourseDef>? courses,
    int seed = 77}) {
  final registry = PowerUpRegistry();
  registerBuiltinEffects(registry);
  final played = courses ??
      [
        CourseDef(id: 'course', holes: holes ?? [_green()])
      ];
  final engine = PuttEngine(PuttConfig(
    mode: mode,
    courses: played,
    catalog: {for (final course in played) course.id: course},
    seed: seed,
    wobbleMaxRadians: 0,
    powerUps: registry,
  ));
  for (final id in players) {
    engine.join(id);
  }
  expect(engine.start(), isTrue);
  engine.drainEvents();
  engine.drainWorldEvents();
  return engine;
}

/// Hands [playerId] the power-up and casts it.
void _cast(PuttEngine engine, String playerId, String effectId,
    [PowerUpTarget? target]) {
  engine.player(playerId)!.inventory.add(effectId);
  expect(engine.usePowerUp(playerId, effectId, target), isTrue,
      reason: '$playerId casts $effectId');
}

BallBody _egg(PuttEngine engine, String playerId) =>
    engine.world!.ball(playerId)!;

/// Plays on until every egg rests (ten seconds at most).
void _rest(PuttEngine engine) {
  engine.tickForward();
  for (var tick = 0; tick < 1200 && !engine.world!.allSettled; tick++) {
    engine.tickForward();
  }
  expect(engine.world!.allSettled, isTrue, reason: 'an egg never rested');
}

/// Puts every egg in the nest, so the hole ends, and moves the match on to
/// the next hole (past the results).
void _finishHole(PuttEngine engine) {
  final world = engine.world!;
  for (final ball in world.balls) {
    if (ball.holed) continue;
    ball.position = world.hole.nest.position;
    ball.asleep = false;
  }
  for (var tick = 0; tick < 240 && engine.phase == PuttPhase.holePlay; tick++) {
    engine.tickForward();
  }
  expect(engine.phase, PuttPhase.holeScoreboard);
}

void main() {
  group('Ghost Egg', () {
    test('the putt goes through the rail, however long the aim took', () {
      final engine = _match(holes: [
        _green(walls: [_rail])
      ]);
      _cast(engine, 'p1', 'ghost_egg');
      // Half a minute lining it up: it used to run out three seconds after
      // the cast, before most putts were struck.
      engine.advanceSeconds(30);
      expect(engine.submitShot('p1', 0, 0.75), isTrue);
      _rest(engine);
      expect(engine.drainWorldEvents().whereType<BallBounced>(), isEmpty);
      expect(_egg(engine, 'p1').position.x, greaterThan(17),
          reason: 'it rolled through the rail at x = 16');

      // Without it the same putt comes back off the rail.
      expect(engine.submitShot('p2', 0, 0.75), isTrue);
      _rest(engine);
      expect(_egg(engine, 'p2').position.x, lessThan(16));
    });

    test('it is one putt: the next one meets the rail again', () {
      final engine = _match(holes: [
        _green(walls: [_rail])
      ]);
      _cast(engine, 'p1', 'ghost_egg');
      expect(engine.submitShot('p1', 0, 0.2), isTrue); // stops short of it
      _rest(engine);
      expect(_egg(engine, 'p1').position.x, lessThan(16));
      expect(engine.submitShot('p1', 0, 0.75), isTrue);
      _rest(engine);
      expect(_egg(engine, 'p1').position.x, lessThan(16));
    });

    test('it goes through a hen and a rock too', () {
      final rock = WallArc(const Vec2(20, 10), 1.5, startAngle: 0, sweep: 0);
      final engine = _match(holes: [
        _green(arcs: [
          rock
        ], hens: [
          MovingObstacle(
              id: 'hen',
              radius: 1.2,
              stops: [ObstacleStop(const Vec2(13, 10), dwellSeconds: 60)]),
        ])
      ]);
      _cast(engine, 'p1', 'ghost_egg');
      expect(engine.submitShot('p1', 0, 0.9), isTrue);
      _rest(engine);
      expect(engine.drainWorldEvents().whereType<BallBounced>(), isEmpty);
      expect(_egg(engine, 'p1').position.x, greaterThan(22));
    });

    test('an egg that stops inside a rock comes out on the turf beside it', () {
      const center = Vec2(20, 10);
      final hole = _green(arcs: [WallArc(center, 2, startAngle: 0, sweep: 0)]);
      final engine = _match(holes: [hole]);
      _cast(engine, 'p1', 'ghost_egg');
      // Just enough to die at the rock's middle.
      final power = puttStopPower(hole, _tee, center, arrivalSpeed: 0.1);
      expect(engine.submitShot('p1', 0, power), isTrue);
      _rest(engine);
      final surfaced = engine.drainWorldEvents().whereType<BallSurfaced>();
      expect(surfaced, hasLength(1));
      expect(surfaced.single.from.distanceTo(center), lessThan(1));
      final at = _egg(engine, 'p1').position;
      expect(at.distanceTo(center), greaterThan(2 + 0.4),
          reason: 'clear of the rock');
      expect(at.distanceTo(center), lessThan(3.5), reason: 'right beside it');
      expect(HoleReach.of(hole, testPhysics).at(at), isTrue);
      expect(engine.strokesInHole('p1'), 1, reason: 'no penalty for it');
    });

    test('a ghost never leaves the table', () {
      final engine = _match();
      _cast(engine, 'p1', 'ghost_egg');
      // Flat out at the fence 6 units behind the tee.
      expect(engine.submitShot('p1', 3.14159265, 1), isTrue);
      _rest(engine);
      final events = engine.drainWorldEvents();
      expect(events.whereType<BallOutOfBounds>(), isEmpty);
      final at = _egg(engine, 'p1').position;
      expect(engine.world!.hole.bounds.contains(at), isTrue);
      expect(at.x, lessThan(1.5), reason: 'it ends at the fence it reached');
    });
  });

  group('Chicken Hop', () {
    test('the putt flies over a rail, a hen and the pond', () {
      final hole = _green(walls: [
        _rail
      ], water: [
        WaterRect(Rect(const Vec2(18, 2), const Vec2(21, 18))),
      ], hens: [
        MovingObstacle(
            id: 'hen',
            radius: 1.2,
            stops: [ObstacleStop(const Vec2(12, 10), dwellSeconds: 60)]),
      ]);
      final engine = _match(holes: [hole]);
      _cast(engine, 'p1', 'chicken_hop');
      engine.advanceSeconds(20); // armed until the putt, like the others
      expect(engine.submitShot('p1', 0, 0.9), isTrue);
      expect(_egg(engine, 'p1').airborne, isTrue);
      var highest = 0.0;
      while (_egg(engine, 'p1').airborne) {
        engine.tickForward();
        final air = _egg(engine, 'p1').air;
        if (air != null && air > highest) highest = air;
      }
      expect(highest, greaterThan(1), reason: 'a real flight, not a drawing');
      expect(_egg(engine, 'p1').position.x, greaterThan(21),
          reason: 'it came down past the rail (16) and the pond (18-21)');
      _rest(engine);
      final events = engine.drainWorldEvents();
      expect(events.whereType<BallSplashed>(), isEmpty);
      expect(
          events.whereType<BallBounced>().where((bounce) => bounce.at.x < 22),
          isEmpty);

      // The same putt without the hop meets the hen or the rail.
      expect(engine.submitShot('p2', 0, 0.9), isTrue);
      _rest(engine);
      expect(_egg(engine, 'p2').position.x, lessThan(16));
    });

    test('how far it flies is its pace: a soft hop is a short one', () {
      // To where it first comes down.
      double carry(double power) {
        final engine = _match();
        _cast(engine, 'p1', 'chicken_hop');
        engine.submitShot('p1', 0, power);
        for (var tick = 0; tick < 240; tick++) {
          engine.tickForward();
          final landed = engine.drainWorldEvents().whereType<BallLanded>();
          if (landed.isNotEmpty) return landed.first.at.x - _tee.x;
        }
        fail('it never came down');
      }

      final soft = carry(0.3);
      final firm = carry(0.6);
      expect(soft, inInclusiveRange(4.5, 7.5));
      expect(firm, inInclusiveRange(9.5, 14));
    });

    test('a hop that comes down on a rock lands beside it', () {
      const center = Vec2(15.5, 10);
      final hole = _green(arcs: [WallArc(center, 2, startAngle: 0, sweep: 0)]);
      final engine = _match(holes: [hole]);
      _cast(engine, 'p1', 'chicken_hop');
      // 0.73 s in the air at 13 units/s: down about 9.5 units out.
      expect(engine.submitShot('p1', 0, 0.5), isTrue);
      _rest(engine);
      expect(engine.drainWorldEvents().whereType<BallSurfaced>(), isNotEmpty);
      expect(HoleReach.of(hole, testPhysics).at(_egg(engine, 'p1').position),
          isTrue);
    });
  });

  group('Gust', () {
    test('carries an egg at rest a long way, for a while', () {
      final engine = _match();
      _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 10)));
      final blown = _egg(engine, 'p2');
      expect(engine.world!.windSecondsLeft('p2'), closeTo(kGustSeconds, 0.02));
      // Two seconds in it is still blowing, and the egg still gaining.
      engine.advanceSeconds(1);
      final early = blown.velocity.x;
      engine.advanceSeconds(1);
      expect(engine.world!.windSecondsLeft('p2'), greaterThan(0.4));
      expect(blown.velocity.x, greaterThan(early));
      expect(blown.velocity.x, greaterThan(4));
      _rest(engine);
      // One shove of 6 units/s used to be spent within 2.6 units.
      final carried = blown.position.x - _tee.x;
      expect(carried, inInclusiveRange(8, 14));
      expect(blown.position.y, closeTo(_tee.y, 0.01), reason: 'along its line');
      expect(engine.world!.windSecondsLeft('p2'), 0);
      expect(_egg(engine, 'p1').position, _tee, reason: 'never the caster');
      expect(_egg(engine, 'p3').position.x, closeTo(blown.position.x, 0.01));
    });

    test('an egg it blows into the pond is back where it stood, once', () {
      final engine = _match(holes: [
        _green(water: [
          WaterRect(Rect(const Vec2(10, 2), const Vec2(13, 18))),
        ])
      ]);
      _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 10)));
      engine.advanceSeconds(kGustSeconds + 2);
      final splashes = engine
          .drainWorldEvents()
          .whereType<BallSplashed>()
          .where((splash) => splash.playerId == 'p2');
      // Not carried in again and again for as long as the wind lasts.
      expect(splashes, hasLength(1));
      expect(_egg(engine, 'p2').position, _tee);
      expect(engine.world!.windSecondsLeft('p2'), 0);
    });

    test('the egg cannot be putted out of it', () {
      final engine = _match();
      _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 10)));
      engine.advanceSeconds(1);
      expect(engine.submitShot('p2', 0, 0.5), isFalse);
      expect(engine.submitShot('p1', 0, 0.5), isTrue);
    });
  });

  group('Sprinkler', () {
    test('drives the eggs in it out of it, and keeps at it', () {
      final engine = _match();
      const mark = Vec2(20, 10);
      _egg(engine, 'p2').position = const Vec2(21, 10); // well inside
      _egg(engine, 'p3').position = const Vec2(30, 10); // well outside
      _cast(engine, 'p1', 'sprinkler', const PowerUpTarget.point(mark));
      expect(engine.world!.sprays.single.secondsLeft,
          closeTo(kSprinklerSeconds, 0.02));
      _rest(engine);
      // One shove of 5.7 units/s used to move it 2.3 units.
      expect(_egg(engine, 'p2').position.x - mark.x,
          greaterThan(kSprinklerRadius + 1));
      expect(_egg(engine, 'p3').position, const Vec2(30, 10));
      expect(_egg(engine, 'p1').position, _tee);
      engine.advanceSeconds(kSprinklerSeconds);
      expect(engine.world!.sprays, isEmpty);
    });

    test('an egg that rolls into it later is pushed back out', () {
      final engine = _match();
      const mark = Vec2(20, 10);
      _cast(engine, 'p1', 'sprinkler', const PowerUpTarget.point(mark));
      // p2 putts straight at the mark, with the pace to die on it.
      final power =
          puttStopPower(engine.world!.hole, _tee, mark, arrivalSpeed: 0.1);
      expect(engine.submitShot('p2', 0, power), isTrue);
      _rest(engine);
      expect(_egg(engine, 'p2').position.distanceTo(mark),
          greaterThan(kSprinklerRadius));
      // The caster's own egg rolls into one and stops in it, untouched.
      const other = Vec2(20, 3);
      _cast(engine, 'p1', 'sprinkler', const PowerUpTarget.point(other));
      expect(
          engine.submitShot(
              'p1',
              (other - _tee).angle,
              puttStopPower(engine.world!.hole, _tee, other,
                  arrivalSpeed: 0.1)),
          isTrue);
      _rest(engine);
      expect(_egg(engine, 'p1').position.distanceTo(other), lessThan(0.5));
    });
  });

  group('Corn Rain', () {
    test('pelts every other egg about for as long as it falls', () {
      final engine = _match();
      _cast(engine, 'p1', 'corn_rain');
      final pelted = _egg(engine, 'p2');
      var path = 0.0;
      var last = pelted.position;
      var awakeLate = false;
      for (var tick = 0; tick < 6 * 120; tick++) {
        engine.tickForward();
        path += pelted.position.distanceTo(last);
        last = pelted.position;
        final seconds = tick / 120;
        if (seconds > 2 && seconds < kCornRainSeconds && !pelted.asleep) {
          awakeLate = true;
        }
      }
      expect(engine.world!.allSettled, isTrue);
      // One kick of at most 4 units/s used to roll it 0.3 units on average.
      expect(path, greaterThan(4), reason: 'rolled $path units in all');
      expect(awakeLate, isTrue, reason: 'still being hit two seconds in');
      expect(_egg(engine, 'p1').position, _tee, reason: 'never the caster');
      expect(_egg(engine, 'p3').position, isNot(_tee));
      expect(_egg(engine, 'p3').position, isNot(pelted.position),
          reason: 'each egg its own kernels');
    });

    test('the same match pelts the same way', () {
      Vec2 after() {
        final engine = _match(seed: 5);
        _cast(engine, 'p1', 'corn_rain');
        engine.advanceSeconds(6);
        return _egg(engine, 'p2').position;
      }

      expect(after(), after());
    });
  });

  group('Thick Shell', () {
    test('does not stay on for ever', () {
      final engine = _match();
      _cast(engine, 'p2', 'thick_shell');
      expect(engine.isShielded('p2'), isTrue);
      expect(engine.shieldSecondsLeft('p2'), closeTo(kThickShellSeconds, 0.02));
      engine.advanceSeconds(kThickShellSeconds - 1);
      expect(engine.isShielded('p2'), isTrue);
      engine.advanceSeconds(1.5);
      expect(engine.isShielded('p2'), isFalse);
      // Gone: the next wind takes its egg.
      engine.drainEvents();
      _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 10)));
      expect(engine.drainEvents().whereType<ShieldBlocked>(), isEmpty);
      _rest(engine);
      expect(_egg(engine, 'p2').position.x, greaterThan(_tee.x + 5));
    });

    test('stops one cast while it holds, and is spent on it', () {
      final engine = _match();
      _cast(engine, 'p2', 'thick_shell');
      engine.advanceSeconds(10);
      engine.drainEvents();
      _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 10)));
      expect(engine.drainEvents().whereType<ShieldBlocked>().single.playerId,
          'p2');
      expect(engine.isShielded('p2'), isFalse);
      _rest(engine);
      expect(_egg(engine, 'p2').position, _tee);
      expect(_egg(engine, 'p3').position.x, greaterThan(_tee.x + 5));
    });

    test('never outlasts its hole', () {
      final engine = _match(holes: [_green(id: 'h1'), _green(id: 'h2')]);
      _cast(engine, 'p2', 'thick_shell');
      _finishHole(engine);
      expect(engine.isShielded('p2'), isFalse);
      expect(engine.advance(), isTrue);
      expect(engine.currentHole!.id, 'h2');
      expect(engine.isShielded('p2'), isFalse,
          reason: 'a second into the new hole');
      engine.advanceSeconds(1);
      expect(engine.isShielded('p2'), isFalse);
    });

    test('a snapshot keeps the time it has left', () {
      final engine = _match();
      _cast(engine, 'p2', 'thick_shell');
      engine.advanceSeconds(12);
      final copy = PuttEngine(engine.config)..restoreFrom(engine.toJson());
      expect(copy.shieldSecondsLeft('p2'),
          closeTo(engine.shieldSecondsLeft('p2'), 1e-9));
      expect(copy.shieldSecondsLeft('p2'), closeTo(18, 0.02));
    });
  });

  group('Strong Coffee', () {
    test('a full putt leaves harder with it', () {
      final engine = _match();
      expect(engine.submitShot('p2', 0, 1), isTrue);
      final plain = _egg(engine, 'p2').velocity.length;
      _cast(engine, 'p1', 'strong_coffee');
      expect(engine.submitShot('p1', 0, 1), isTrue);
      final strong = _egg(engine, 'p1').velocity.length;
      // It used to be capped at a full putt's pace: nothing gained.
      expect(strong, closeTo(plain * 1.3, 1e-6));
      engine.advanceSeconds(0.5);
      expect(_egg(engine, 'p1').position.x,
          greaterThan(_egg(engine, 'p2').position.x + 2));
    });
  });

  group('Rabbit Hole', () {
    test('a hop into a rock comes up on the turf beside it', () {
      const center = Vec2(11, 10);
      final hole = _green(arcs: [WallArc(center, 2, startAngle: 0, sweep: 0)]);
      final engine = _match(holes: [hole]);
      _cast(engine, 'p1', 'rabbit_hole', const PowerUpTarget.point(center));
      final at = _egg(engine, 'p1').position;
      expect(at.distanceTo(center), greaterThan(2 + 0.4));
      expect(HoleReach.of(hole, testPhysics).at(at), isTrue);
    });
  });

  group('from hole to hole, from course to course', () {
    final courses = [
      CourseDef(id: 'first', holes: [_green(id: 'a1'), _green(id: 'a2')]),
      CourseDef(id: 'second', holes: [_green(id: 'b1')]),
    ];

    for (final (name, effect, armed)
        in <(String, String, bool Function(NextShotModifiers))>[
      ('Hawk Eye', 'hawk_eye', (mods) => mods.noWobble),
      ('Ghost Egg', 'ghost_egg', (mods) => mods.ghost),
      ('Chicken Hop', 'chicken_hop', (mods) => mods.hop),
      ('Nest Magnet', 'nest_magnet', (mods) => mods.magnet),
      ('Strong Coffee', 'strong_coffee', (mods) => mods.powerMultiplier > 1),
    ]) {
      test('$name turned on and never putted goes on to the next hole', () {
        final engine = _match(courses: courses, mode: GameMode.tournament);
        // My egg is already rolling to the nest when I turn it on.
        expect(engine.submitShot('p1', 0, 0.3), isTrue);
        _cast(engine, 'p1', effect);
        expect(armed(engine.player('p1')!.nextShot), isTrue);
        _finishHole(engine);
        expect(engine.advance(), isTrue);
        expect(engine.currentHole!.id, 'a2');
        expect(armed(engine.player('p1')!.nextShot), isTrue,
            reason: 'still armed on the next hole');
        // And it rides the first putt there.
        engine.drainEvents();
        expect(engine.submitShot('p1', 0, 0.3), isTrue);
        final shot = engine.drainEvents().whereType<ShotApplied>().single;
        expect(
            shot.steady ||
                shot.ghost ||
                shot.hop ||
                shot.magnet ||
                shot.powerMultiplier > 1,
            isTrue);
        expect(engine.player('p1')!.nextShot.isEmpty, isTrue);
      });
    }

    test('a new course starts everyone clean, the power-ups in hand kept', () {
      final engine = _match(courses: courses, mode: GameMode.tournament);
      engine.player('p1')!.inventory.add('gust');
      _finishHole(engine);
      engine.advance();
      expect(engine.currentHole!.id, 'a2');
      _cast(engine, 'p1', 'hawk_eye');
      _cast(engine, 'p1', 'strong_coffee');
      _cast(engine, 'p2', 'thick_shell');
      _finishHole(engine);
      expect(engine.advance(), isTrue); // the course's awards
      expect(engine.advance(), isTrue); // the next course
      expect(engine.currentHole!.id, 'b1');
      expect(engine.player('p1')!.nextShot.isEmpty, isTrue);
      expect(engine.isShielded('p2'), isFalse);
      expect(engine.player('p1')!.inventory.toList(), ['gust']);
    });

    test('a course the group votes next starts clean too', () {
      final engine = _match(courses: [courses.first], mode: GameMode.casual);
      _finishHole(engine);
      engine.advance();
      _cast(engine, 'p1', 'ghost_egg');
      _finishHole(engine);
      engine.advance(); // awards
      engine.advance(); // the vote
      expect(engine.phase, PuttPhase.awaitingNextCourse);
      expect(engine.startCourse('first'), isTrue);
      expect(engine.player('p1')!.nextShot.isEmpty, isTrue);
    });
  });

  group('where an egg can stand', () {
    test('a step is turf on both levels; a rock, a pond and a bed are not', () {
      final hole = boxHole(
        width: 30,
        height: 20,
        tee: const Vec2(4, 10),
        nest: const Nest(Vec2(26, 10), 0.95),
        // A ledge across the green (no ramp: only a flight gets up it), a
        // rock, a pond, and a bed walled off in a corner.
        extraWalls: [
          WallSegment.ledge(const Vec2(15, 0), const Vec2(15, 20)),
          WallSegment(const Vec2(0, 16), const Vec2(4, 16)),
          WallSegment(const Vec2(4, 16), const Vec2(4, 20)),
        ],
        arcs: [WallArc(const Vec2(9, 5), 1.5, startAngle: 0, sweep: 0)],
        water: [WaterCircle(const Vec2(9, 15), 1.5)],
      );
      final reach = HoleReach.of(hole, testPhysics);
      expect(reach.at(hole.tee), isTrue);
      expect(reach.at(hole.nest.position), isTrue, reason: 'past the ledge');
      expect(reach.at(const Vec2(9, 5)), isFalse, reason: 'in the rock');
      expect(reach.at(const Vec2(9, 15)), isFalse, reason: 'in the pond');
      expect(reach.at(const Vec2(2, 18)), isFalse, reason: 'in the bed');
      // The nearest turf to each is right beside it.
      for (final spot in const [Vec2(9, 5), Vec2(9, 15), Vec2(2, 18)]) {
        final turf = reach.nearest(spot);
        expect(reach.at(turf), isTrue);
        expect(turf.distanceTo(spot), lessThan(3.2));
      }
      expect(reach.nearest(hole.tee), hole.tee, reason: 'turf stays put');
    });
  });

  group('a snapshot mid-cast', () {
    for (final (name, cast) in <(String, void Function(PuttEngine))>[
      (
        'a gust',
        (engine) =>
            _cast(engine, 'p1', 'gust', const PowerUpTarget.point(Vec2(40, 4)))
      ),
      (
        'a sprinkler',
        (engine) => _cast(
            engine, 'p1', 'sprinkler', const PowerUpTarget.point(Vec2(7, 10)))
      ),
      ('corn rain', (engine) => _cast(engine, 'p1', 'corn_rain')),
    ]) {
      test('$name plays on the same from a snapshot', () {
        final engine = _match();
        cast(engine);
        engine.advanceSeconds(0.7);
        final copy = PuttEngine(engine.config)..restoreFrom(engine.toJson());
        engine.advanceSeconds(8);
        copy.advanceSeconds(8);
        for (final id in ['p1', 'p2', 'p3']) {
          expect(_egg(copy, id).position, _egg(engine, id).position,
              reason: id);
        }
        expect(_egg(engine, 'p2').position, isNot(_tee));
      });
    }
  });
}
