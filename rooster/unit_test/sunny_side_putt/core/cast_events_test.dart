// What the engine tells the view about every cast, so everyone can see it:
// the cast with its target and the caster's spot, the eggs it hit, a
// crow's theft, a shell holding, and the next-shot power-ups riding a
// shot. Real effects, a real engine; the events change nothing in the
// game's state.
library;

import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

PuttEngine _engine({List<String> players = const ['p1', 'p2', 'p3']}) {
  final registry = PowerUpRegistry();
  registerBuiltinEffects(registry);
  final engine = PuttEngine(PuttConfig(
    mode: GameMode.casual,
    courses: [
      CourseDef(id: 'casts', holes: [
        boxHole(
            id: 'c0',
            par: 3,
            width: 30,
            height: 20,
            tee: const Vec2(6, 10),
            nest: const Nest(Vec2(26, 10), 0.8),
            friction: 4),
      ]),
    ],
    seed: 77,
    wobbleMaxRadians: 0,
    powerUps: registry,
  ));
  for (final id in players) {
    engine.join(id);
  }
  expect(engine.start(), isTrue);
  engine.drainEvents();
  return engine;
}

void main() {
  test('a shell stops a swap aimed at its egg, and is spent', () {
    final engine = _engine();
    engine.player('p2')!.inventory.add('thick_shell');
    expect(engine.usePowerUp('p2', 'thick_shell'), isTrue);
    engine.drainEvents();
    final p1At = engine.world!.ball('p1')!.position;
    final p2At = engine.world!.ball('p2')!.position;
    engine.player('p1')!.inventory.add('nest_swap');
    expect(
        engine.usePowerUp('p1', 'nest_swap', const PowerUpTarget.player('p2')),
        isTrue);
    final blocked = engine.drainEvents().whereType<ShieldBlocked>().single;
    expect(blocked.playerId, 'p2');
    expect(blocked.casterId, 'p1');
    expect(blocked.effectId, 'nest_swap');
    expect(engine.world!.ball('p1')!.position, p1At, reason: 'no swap');
    expect(engine.world!.ball('p2')!.position, p2At);
    expect(engine.player('p2')!.shields, 0);

    // Spent: the next swap goes through.
    engine.player('p1')!.inventory.add('nest_swap');
    engine.usePowerUp('p1', 'nest_swap', const PowerUpTarget.player('p2'));
    expect(engine.world!.ball('p1')!.position, p2At);
  });

  test('a cast says who, what, where it aimed and where the caster stood', () {
    final engine = _engine();
    engine.player('p1')!.inventory.add('gust');
    final spot = const Vec2(15, 3);
    expect(engine.usePowerUp('p1', 'gust', PowerUpTarget.point(spot)), isTrue);
    final events = engine.drainEvents();
    final used = events.whereType<PowerUpUsed>().single;
    expect(used.playerId, 'p1');
    expect(used.effectId, 'gust');
    expect(used.target!.point, spot);
    expect(used.at, engine.world!.ball('p1')!.position);
    // Its last word: the eggs the wind pushed, the caster's own spared.
    final hit = events.whereType<PowerUpHit>().single;
    expect(hit.casterId, 'p1');
    expect(hit.playerIds, ['p2', 'p3']);
    expect(events.last, same(hit));
  });

  test('a shell that holds is out of the hit list', () {
    final engine = _engine();
    engine.player('p2')!.inventory.add('thick_shell');
    engine.player('p3')!.inventory.add('corn_rain');
    expect(engine.usePowerUp('p2', 'thick_shell'), isTrue);
    engine.drainEvents();
    expect(engine.usePowerUp('p3', 'corn_rain'), isTrue);
    final events = engine.drainEvents();
    expect(events.map((e) => e.runtimeType),
        [PowerUpUsed, ShieldBlocked, PowerUpHit]);
    final blocked = events.whereType<ShieldBlocked>().single;
    expect(blocked.playerId, 'p2');
    expect(blocked.casterId, 'p3');
    expect(events.whereType<PowerUpHit>().single.playerIds, ['p1']);
  });

  group("a cast's shove does not get round a shell", () {
    // p1 rests just west of p2, p3 out of the way; all three have putted
    // (a waiting egg is a ghost anyway). p3's Gust blows p1 east into p2.
    PuttEngine blown({required bool shelled}) {
      final engine = _engine();
      final world = engine.world!;
      for (final (id, at) in const [
        ('p1', Vec2(12, 10)),
        ('p2', Vec2(14, 10)),
        ('p3', Vec2(6, 3)),
      ]) {
        world.ball(id)!
          ..position = at
          ..putted = true
          ..settle();
      }
      if (shelled) {
        engine.player('p2')!.inventory.add('thick_shell');
        expect(engine.usePowerUp('p2', 'thick_shell'), isTrue);
      }
      engine.player('p3')!.inventory.add('gust');
      expect(
          engine.usePowerUp(
              'p3', 'gust', const PowerUpTarget.point(Vec2(20, 10))),
          isTrue);
      return engine;
    }

    void settleAll(PuttEngine engine) {
      for (var i = 0; i < 720; i++) {
        engine.tickForward();
      }
    }

    test('unshelled, the shoved egg knocks it on', () {
      final engine = blown(shelled: false);
      settleAll(engine);
      expect(engine.world!.ball('p2')!.position.x, greaterThan(14.5));
    });

    test('shelled, it stays put and the shoved egg bounces off', () {
      final engine = blown(shelled: true);
      expect(engine.world!.isSheltered('p2'), isTrue);
      expect(engine.world!.isSheltered('p3'), isTrue, reason: 'the caster');
      settleAll(engine);
      final p2 = engine.world!.ball('p2')!;
      expect(p2.position, const Vec2(14, 10));
      expect(p2.asleep, isTrue);
      final p1 = engine.world!.ball('p1')!;
      expect(p1.position.x, lessThan(13.5), reason: 'off the shell, back west');
      expect(engine.world!.isSheltered('p2'), isFalse,
          reason: 'the shelter runs out');
    });

    test('a snapshot mid-shove keeps the shelter', () {
      final engine = blown(shelled: true);
      for (var i = 0; i < 20; i++) {
        engine.tickForward();
      }
      final copy = PuttEngine(engine.config)..restoreFrom(engine.toJson());
      expect(copy.world!.isSheltered('p2'), isTrue);
      settleAll(copy);
      expect(copy.world!.ball('p2')!.position, const Vec2(14, 10));
    });

    test("an egg's own putt meets a spared one as ever", () {
      final engine = blown(shelled: true);
      settleAll(engine);
      // The shelter ran out with the shove; a fresh one, then p1's own
      // putt east into p2 while it lasts.
      engine.world!.shelter(spared: ['p2'], pushed: ['p1'], ticks: 600);
      final p1 = engine.world!.ball('p1')!
        ..position = const Vec2(12, 10)
        ..settle();
      expect(p1.position, const Vec2(12, 10));
      engine.world!.applyShot('p1', 0, 0.35);
      settleAll(engine);
      expect(engine.world!.ball('p2')!.position.x, greaterThan(14.2),
          reason: 'a putt is its own, not the cast\'s shove');
    });
  });

  test("a crow's theft names the thief, the robbed and the loot", () {
    final engine = _engine();
    engine.player('p2')!.inventory
      ..add('gust')
      ..add('hawk_eye');
    engine.player('p1')!.inventory.add('thieving_crow');
    expect(
        engine.usePowerUp(
            'p1', 'thieving_crow', const PowerUpTarget.player('p2')),
        isTrue);
    final events = engine.drainEvents();
    final stolen = events.whereType<PowerUpStolen>().single;
    expect(stolen.thiefId, 'p1');
    expect(stolen.victimId, 'p2');
    expect(stolen.effectId, 'gust', reason: 'the crow takes the first slot');
    // The loot lands in the thief's hand; the crow touches no egg.
    expect(events.whereType<PowerUpPicked>().single.effectId, 'gust');
    expect(events.whereType<PowerUpHit>().single.playerIds, isEmpty);
    expect(engine.player('p1')!.inventory.toList(), ['gust']);
  });

  test('a swap hits both eggs, a rabbit hole and a ghost the caster', () {
    final engine = _engine();
    final player = engine.player('p1')!;
    player.inventory
      ..add('nest_swap')
      ..add('rabbit_hole')
      ..add('ghost_egg');
    engine.usePowerUp('p1', 'nest_swap', const PowerUpTarget.player('p3'));
    expect(engine.drainEvents().whereType<PowerUpHit>().single.playerIds,
        ['p1', 'p3']);
    engine.usePowerUp(
        'p1', 'rabbit_hole', const PowerUpTarget.point(Vec2(12, 10)));
    expect(
        engine.drainEvents().whereType<PowerUpHit>().single.playerIds, ['p1']);
    engine.usePowerUp('p1', 'ghost_egg');
    expect(
        engine.drainEvents().whereType<PowerUpHit>().single.playerIds, ['p1']);
  });

  test('a shot says which next-shot power-ups rode it', () {
    final engine = _engine(players: const ['p1']);
    engine.player('p1')!.inventory
      ..add('strong_coffee')
      ..add('hawk_eye')
      ..add('chicken_hop');
    for (final id in ['strong_coffee', 'hawk_eye', 'chicken_hop']) {
      expect(engine.usePowerUp('p1', id), isTrue);
    }
    engine.drainEvents();
    expect(engine.submitShot('p1', 0, 0.4), isTrue);
    final shot = engine.drainEvents().whereType<ShotApplied>().single;
    expect(shot.steady, isTrue);
    expect(shot.powerMultiplier, closeTo(1.3, 1e-9));
    expect(shot.hop, isTrue);
    expect(shot.magnet, isFalse);
    // Spent on it: the next one is plain.
    engine.advanceSeconds(8);
    engine.drainEvents();
    expect(engine.submitShot('p1', 0, 0.2), isTrue);
    final plain = engine.drainEvents().whereType<ShotApplied>().single;
    expect(plain.steady || plain.hop || plain.powerMultiplier != 1, isFalse);
  });
}
