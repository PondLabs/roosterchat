// The kickers as everyone sees them: a launch ramp built in each course's
// own material with chevrons pointing the way it throws, an egg riding up
// its deck and flying the engine's arc with its shadow on the ground
// below, landing with a squash and a puff; the roll guide climbing through
// the flight to a mark where it comes down; and the match turning a flight
// into its sounds and its bursts, the altitude drawn between ticks.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:three_js_math/three_js_math.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_art.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

/// The kicker the tests throw from: foot at x 7, lip at x 9, throwing
/// east across the middle of a long field.
const Kicker _kicker = Kicker(Vec2(7, 6), Vec2(9, 6), width: 3);

/// A long field with the kicker, a moat past it, the hole id naming the
/// course whose look it takes.
HoleDef _field({String id = 'coop_kick', bool moat = false}) => HoleDef(
      id: id,
      par: 2,
      tee: const Vec2(3, 6),
      nest: Nest(const Vec2(37, 10.5), 0.9),
      bounds: Rect(Vec2.zero, const Vec2(40, 12)),
      walls: const [
        WallSegment(Vec2.zero, Vec2(40, 0)),
        WallSegment(Vec2(40, 0), Vec2(40, 12)),
        WallSegment(Vec2(40, 12), Vec2(0, 12)),
        WallSegment(Vec2(0, 12), Vec2.zero),
      ],
      water: [
        if (moat) const WaterRect(Rect(Vec2(10, 0), Vec2(14, 12))),
      ],
      kickers: const [_kicker],
    );

/// Depth-first walk of every object under [root].
List<tjs.Object3D> _walk(tjs.Object3D root) {
  final out = <tjs.Object3D>[];
  final queue = Queue<tjs.Object3D>()..add(root);
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    out.add(current);
    queue.addAll(current.children);
  }
  return out;
}

PuttWorldEgg _egg(Vec2 at, {double? air, Vec2 velocity = const Vec2(9, 0)}) =>
    PuttWorldEgg(
      playerId: 'me',
      position: at,
      velocity: velocity,
      tint: PuttPalette.tintForIndex(0),
      radius: 0.45,
      air: air,
    );

/// The highest point of [mesh]'s geometry in its group's frame (the
/// kicker's own: x up the deck, y up).
double _top(tjs.Mesh mesh, {double? nearX}) {
  final position = mesh.geometry!.attributes['position'];
  var top = -double.infinity;
  for (var i = 0; i < position.count; i++) {
    final x = position.getX(i)!.toDouble();
    if (nearX != null && (x - nearX).abs() > 0.02) continue;
    top = math.max(top, position.getY(i)!.toDouble());
  }
  return top;
}

void main() {
  // Standing on its tip: the drawn shell's half-height.
  const stand = 0.45 * 1.2 * 1.28;

  group('the kicker on the green', () {
    const looks = {
      'coop_kick': 'kicker-planks',
      'barn_kick': 'kicker-straw',
      'maze_kick': 'kicker-corn',
      'pond_kick': 'kicker-slab',
      'road_kick': 'kicker-board',
    };
    for (final MapEntry(key: id, value: signature) in looks.entries) {
      test('builds in its course\'s look: $id wears $signature', () {
        final world = PuttWorld3D(viewport: const ui.Size(800, 600));
        addTearDown(world.dispose);
        world.buildHole(_field(id: id), eggRadius: 0.45);
        final kickers = world.holeGroup('kickers')!;
        final kicker = kickers.children.single;
        expect(kicker.name, 'kicker');
        final parts = {for (final o in _walk(kicker)) o.name};
        expect(
            parts, containsAll(['kicker-body', 'kicker-chevrons', signature]));
        // At its foot, turned the way it throws (east: no turn).
        expect(kicker.position.x, closeTo(7, 1e-9));
        expect(kicker.position.z, closeTo(6, 1e-9));
        expect(kicker.rotation.y, closeTo(0, 1e-9));
        // The deck meets the lip at the kicker's height, from the turf.
        final meshes = _walk(kicker).whereType<tjs.Mesh>();
        final body = meshes.firstWhere((m) => m.name == 'kicker-body');
        expect(_top(body, nearX: 0), closeTo(0, 0.07),
            reason: 'its foot is flush with the turf');
        final deck = id == 'coop_kick'
            ? meshes.firstWhere((m) => m.name == 'kicker-planks')
            : id == 'pond_kick'
                ? meshes.firstWhere((m) => m.name == 'kicker-slab')
                : body;
        expect(_top(deck), closeTo(_kicker.height, 0.06));
      });
    }

    test('its chevrons point up the deck, the way it throws', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_field(), eggRadius: 0.45);
      final chevrons = _walk(world.holeGroup('kickers')!)
          .whereType<tjs.Mesh>()
          .firstWhere((m) => m.name == 'kicker-chevrons');
      final position = chevrons.geometry!.attributes['position'];
      // Each arm's tip lies on the deck's middle line, ahead of its ends.
      var tipX = -double.infinity;
      var endX = double.infinity;
      for (var i = 0; i < position.count; i++) {
        final x = position.getX(i)!.toDouble();
        final z = position.getZ(i)!.toDouble();
        if (z.abs() < 1e-6) tipX = math.max(tipX, x);
        if (z.abs() > 0.5) endX = math.min(endX, x);
        // Laid on the deck's curve, a hair over it.
        final rise = _kicker.deckRise(x / _kicker.length);
        expect(position.getY(i)!.toDouble(), greaterThan(rise));
        expect(position.getY(i)!.toDouble(), lessThan(rise + 0.05));
      }
      expect(tipX, greaterThan(endX));
      expect(tipX, lessThanOrEqualTo(_kicker.length));
    });

    test('a kicker turned another way turns its whole build with it', () {
      const turned = Kicker(Vec2(20, 4), Vec2(20, 6.5), width: 2.5);
      final hole = HoleDef(
        id: 'road_turned',
        par: 2,
        tee: const Vec2(3, 6),
        nest: Nest(const Vec2(37, 10.5), 0.9),
        bounds: Rect(Vec2.zero, const Vec2(40, 12)),
        kickers: const [turned],
      );
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hole, eggRadius: 0.45);
      final kicker = world.holeGroup('kickers')!.children.single;
      // Local x (up the deck) onto the game's +y: world +z.
      final up = tjs.Vector3(1, 0, 0)..applyEuler(kicker.rotation);
      expect(up.x, closeTo(0, 1e-6));
      expect(up.z, closeTo(1, 1e-6));
    });
  });

  group('an egg over a kicker', () {
    test('rides up the deck, flies its arc over its shadow, and lands', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_field(), eggRadius: 0.45);
      var time = 0.0;
      // Unrolled (no velocity), so the shell stands on its tip throughout.
      void frame(Vec2 at, {double? air}) {
        world.applySnapshot(PuttWorldFrame(
            time: time, eggs: [_egg(at, air: air, velocity: Vec2.zero)]));
        time += 1 / 60;
      }

      tjs.Object3D shadowGroup() => _walk(world.scene)
          .firstWhere((object) => object.name == 'egg-ground');
      tjs.Object3D shadow() => _walk(world.scene)
          .firstWhere((object) => object.name == 'egg-shadow');
      int puffs() => _walk(world.scene)
          .where((object) => object.name == 'burst-puff' && object.visible)
          .length;

      // Up the deck: the egg stands on it, rising toward the lip.
      for (final x in [6.5, 7.6, 8.4, 8.95]) {
        frame(Vec2(x, 6));
        expect(world.eggOf('me')!.position.y,
            closeTo(_kicker.deckHeightAt(Vec2(x, 6)) + stand, 1e-6),
            reason: 'on the deck at $x');
      }
      // Off the lip: the engine's arc, the shadow left on the turf below.
      const lift = 4.5;
      var landedAt = 0.0;
      for (var i = 1; i < 60; i++) {
        final t = i / 60;
        final air = _kicker.height + lift * t - 9 * t * t;
        if (air <= 0) break;
        final at = Vec2(9 + 9 * t, 6);
        frame(at, air: air);
        expect(world.eggOf('me')!.position.y, closeTo(air + stand, 1e-6),
            reason: 'flying at $air');
        expect(shadowGroup().position.y, closeTo(0, 1e-9),
            reason: 'the shadow stays on the turf');
        expect(shadowGroup().position.x, closeTo(at.x, 1e-5));
        if (air > 0.9) {
          expect(shadow().scale.x, lessThan(0.85),
              reason: 'high up, its shadow shrinks');
        }
        landedAt = at.x;
      }
      expect(puffs(), 0, reason: 'no dust in the air');
      // Down: the engine has it rolling again; the drawing finishes the
      // fall, squashes the shell and puffs the dust.
      var x = landedAt;
      for (var i = 0; i < 6; i++) {
        x += 0.12;
        frame(Vec2(x, 6));
      }
      expect(world.eggOf('me')!.position.y, closeTo(stand, 0.02));
      expect(puffs(), greaterThan(0), reason: 'the dust flies where it lands');
    });

    test('a landing the engine bounces back up squashes the shell too', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_field(), eggRadius: 0.45);
      var time = 0.0;
      void frame(double x, double air) {
        world.applySnapshot(
            PuttWorldFrame(time: time, eggs: [_egg(Vec2(x, 6), air: air)]));
        time += 1 / 60;
      }

      // Coming down fast, touching the turf, and up again in a hop.
      for (final (x, air) in [
        (14.0, 0.6),
        (14.2, 0.42),
        (14.4, 0.22),
        (14.6, 0.04),
        (14.8, 0.06),
        (15.0, 0.1),
      ]) {
        frame(x, air);
      }
      final squashed = world
          .eggOf('me')!
          .children
          .firstWhere((object) => object.name == 'egg-shell');
      expect(squashed.scale.y, lessThan(1), reason: 'the shell squashes');
      expect(
          _walk(world.scene)
              .where((object) => object.name == 'burst-puff' && object.visible),
          isNotEmpty);
    });

    test('the roll guide climbs through the flight to a mark at its landing',
        () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_field(), eggRadius: 0.45);
      final preview = [
        for (var x = 3.0; x <= 9.0; x += 0.5) Vec2(x, 6),
        for (var i = 1; i <= 10; i++) Vec2(9 + i * 0.6, 6),
      ];
      final airs = <double?>[
        for (var x = 3.0; x <= 9.0; x += 0.5) null,
        for (var i = 1; i <= 10; i++)
          math.max(
              0.0,
              _kicker.height +
                  0.9 * i / 10 * 4 -
                  4 * (i / 10) * (i / 10) * 2.4),
      ];
      airs[airs.length - 1] = null;
      final landing = preview.last;
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [_egg(const Vec2(3, 6), velocity: Vec2.zero)],
        aim: PuttWorldAim(
          origin: const Vec2(3, 6),
          angle: 0,
          power: 0.6,
          dragLength: 3,
          eggRadius: 0.45,
          preview: preview,
          previewAir: airs,
          landing: landing,
        ),
      ));
      final dots = _walk(world.scene)
          .where((object) => object.name == 'aim-dot' && object.visible)
          .toList();
      expect(dots, isNotEmpty);
      // Past the lip the dots rise off the turf (the aim group sits on the
      // turf at the egg).
      final aloft = dots
          .where((dot) => dot.position.x > 9.5 - 3 && dot.position.x < 14 - 3);
      expect(aloft.map((dot) => dot.position.y).reduce(math.max),
          greaterThan(0.5));
      final mark = _walk(world.scene)
          .firstWhere((object) => object.name == 'aim-landing');
      expect(mark.visible, isTrue);
      expect(mark.position.x, closeTo(landing.x - 3, 1e-9));
      expect(mark.position.z, closeTo(0, 1e-9));
    });
  });

  group('the guide through a jump', () {
    const config = PhysicsConfig();
    test('runs the engine\'s flight to where it comes down, and no further',
        () {
      final hole = _field(moat: true);
      final world =
          PhysicsWorld(hole: hole, config: config, playerIds: const ['me']);
      final roll = previewRoll(
        world: world,
        hole: hole,
        config: config,
        playerId: 'me',
        angle: 0,
        power: 0.6,
        maxLength: 6,
      );
      expect(roll.landing, isNotNull);
      expect(roll.points.last, roll.landing);
      expect(roll.airs, hasLength(roll.points.length));
      // Up off the lip and back down again.
      final flying = [
        for (final air in roll.airs)
          if (air != null) air,
      ];
      expect(flying, isNotEmpty);
      final peak = flying.reduce(math.max);
      expect(peak, greaterThan(_kicker.height + 0.3));
      expect(flying.first, lessThan(peak));
      expect(flying.last, lessThan(peak));
      // Far past the guide's usual length: the flight is shown whole.
      expect(roll.landing!.x - hole.tee.x, greaterThan(6));
      expect(roll.landing!.x, greaterThan(14), reason: 'over the moat');
      // The engine's own first landing.
      final real =
          PhysicsWorld(hole: hole, config: config, playerIds: const ['me']);
      real.applyShot('me', 0, 0.6);
      BallLanded? first;
      for (var i = 0; i < 600 && first == null; i++) {
        real.stepTick();
        first = real.drainEvents().whereType<BallLanded>().firstOrNull;
      }
      expect(roll.landing, first!.at);
    });

    test('runs on to a kicker its length ends on, and shows the flight', () {
      // From the tee (x 3) the kicker's foot is four units off, its lip
      // six: a guide four long ends on the deck, and runs on to the flight.
      final hole = _field(moat: true);
      ({List<Vec2> points, List<double?> airs, Vec2? landing}) guide(
              double length) =>
          previewRoll(
            world: PhysicsWorld(
                hole: hole, config: config, playerIds: const ['me']),
            hole: hole,
            config: config,
            playerId: 'me',
            angle: 0,
            power: 0.72,
            maxLength: length,
          );
      final onTheDeck = guide(4);
      expect(onTheDeck.landing, isNotNull);
      expect(onTheDeck.airs.whereType<double>(), isNotEmpty);
      expect(onTheDeck.landing!.x, greaterThan(14), reason: 'over the moat');
      // One that ends well short of the kicker stops where it ends.
      final short = guide(1.5);
      expect(short.landing, isNull);
      expect(short.airs, isEmpty);
      expect(short.points.last.x, lessThan(6));
    });

    test('a roll that never leaves the ground has no altitudes', () {
      final hole = _field();
      final world =
          PhysicsWorld(hole: hole, config: config, playerIds: const ['me']);
      final roll = previewRoll(
        world: world,
        hole: hole,
        config: config,
        playerId: 'me',
        angle: math.pi / 2,
        power: 0.4,
      );
      expect(roll.airs, isEmpty);
      expect(roll.landing, isNull);
    });
  });

  group('the match over a jump', () {
    PuttMatch kickMatch() {
      final course =
          CourseDef(id: 'kicks', holes: [_field(id: 'barn_kick', moat: true)]);
      return PuttMatch(
        config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 9),
      )..boot();
    }

    test('draws the flight between ticks, sounds it and bursts at both ends',
        () {
      final match = kickMatch();
      match.notices.clear();
      match.fxSpots.clear();
      expect(match.submitShot(0, 0.6), isTrue);
      var flying = false;
      final heard = <PuttSfx>[];
      final spots = <PuttFxSpotKind>[];
      for (var i = 0; i < 240; i++) {
        match.update(1 / 60);
        heard.addAll(match.notices.map((notice) => notice.sfx));
        spots.addAll(match.fxSpots.map((spot) => spot.kind));
        match.notices.clear();
        match.fxSpots.clear();
        final air = match.renderAirOf('me');
        final ball = match.myBall!;
        if (ball.airborne) {
          flying = true;
          expect(air, isNotNull);
          // Between the last two ticks' altitudes.
          final previous = match.previousAirs['me'];
          final current = match.currentAirs['me']!;
          final low = math.min(previous ?? current, current);
          final high = math.max(previous ?? current, current);
          expect(air!, inInclusiveRange(low - 1e-9, high + 1e-9));
        }
      }
      expect(flying, isTrue);
      expect(heard, contains(PuttSfx.kick));
      expect(heard, contains(PuttSfx.land));
      expect(spots, contains(PuttFxSpotKind.launch));
      expect(spots, contains(PuttFxSpotKind.land));
      expect(match.renderAirOf('me'), isNull, reason: 'down again');
    });

    test('each course throws up its own puff', () {
      expect(kickerPuffOf('coop_3').straw, isTrue);
      expect(kickerPuffOf('barn_5').straw, isTrue);
      expect(kickerPuffOf('maze_3').straw, isFalse);
      expect(kickerPuffOf('road_4').straw, isFalse);
      expect(kickerPuffOf('pond_1').straw, isFalse);
      expect(kickerPuffOf('pond_1').dust, isNot(kickerPuffOf('maze_3').dust));
    });
  });
}
