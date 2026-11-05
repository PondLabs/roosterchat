// The looks in the 3D world: an egg wears its player's pattern, painted
// once per colour and pattern and shared (eggs alike share one paint, a
// new pick swaps to its own, the old one comes back unchanged), and the
// chick that hatches wears its player's hat. No GPU: the world is pure
// Dart up to the surface widget.
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/look.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_art.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

const _nest = Nest(Vec2(14, 6), 0.9);

HoleDef _hole() => HoleDef(
      id: 'looks-hole',
      par: 2,
      tee: const Vec2(3, 6),
      nest: _nest,
      bounds: Rect(Vec2.zero, Vec2(18, 12)),
      walls: [
        WallSegment(Vec2.zero, Vec2(18, 0)),
        WallSegment(Vec2(18, 0), Vec2(18, 12)),
        WallSegment(Vec2(18, 12), Vec2(0, 12)),
        WallSegment(Vec2(0, 12), Vec2.zero),
      ],
    );

PuttWorldEgg _egg(String id, Vec2 at, PuttLook look, {int seat = 0}) =>
    PuttWorldEgg(
      playerId: id,
      position: at,
      velocity: Vec2.zero,
      tint: PuttPalette.tintForIndex(seat),
      radius: 0.45,
      look: look,
    );

/// The paint on [id]'s shell.
tjs.Texture? _paintOf(PuttWorld3D world, String id) {
  final shell = world
      .eggOf(id)!
      .children
      .firstWhere((child) => child.name == 'egg-shell');
  return shell.material?.map;
}

const _stripes = PuttLook(pattern: EggPattern.stripes);

void main() {
  group('the egg wears its pattern', () {
    test('one paint per colour and pattern, shared by every egg wearing it',
        () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(time: 0, eggs: [
        _egg('a', const Vec2(2, 2), _stripes),
        _egg('b', const Vec2(4, 2), _stripes),
        _egg('c', const Vec2(6, 2), PuttLook.standard),
        _egg('d', const Vec2(8, 2), _stripes, seat: 1),
      ]));
      final stripes = _paintOf(world, 'a');
      expect(stripes, isNotNull);
      expect(identical(_paintOf(world, 'b'), stripes), isTrue,
          reason: 'the same colour and pattern share one paint');
      final zigzag = _paintOf(world, 'c');
      expect(identical(zigzag, stripes), isFalse,
          reason: 'another pattern is another paint');
      expect(identical(_paintOf(world, 'd'), stripes), isFalse,
          reason: 'another colour is another paint');

      // 'c' picks stripes: its shell takes the shared paint; back to the
      // zig-zag, the first paint again, not a new one.
      world.applySnapshot(PuttWorldFrame(time: 0.016, eggs: [
        _egg('c', const Vec2(6, 2), _stripes),
      ]));
      expect(identical(_paintOf(world, 'c'), stripes), isTrue);
      world.applySnapshot(PuttWorldFrame(time: 0.032, eggs: [
        _egg('c', const Vec2(6, 2), PuttLook.standard),
      ]));
      expect(identical(_paintOf(world, 'c'), zigzag), isTrue,
          reason: 'the paints are cached, never remade');

      // And a second world draws the same paints.
      final other = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(other.dispose);
      other.applySnapshot(PuttWorldFrame(time: 0, eggs: [
        _egg('e', const Vec2(2, 2), _stripes),
      ]));
      expect(identical(_paintOf(other, 'e'), stripes), isTrue);
    });

    test('a new pattern puts a fresh shell material on, the paint shared', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(time: 0, eggs: [
        _egg('a', const Vec2(2, 2), PuttLook.standard),
      ]));
      final shell = world
          .eggOf('a')!
          .children
          .firstWhere((child) => child.name == 'egg-shell');
      final before = shell.material;
      world.applySnapshot(PuttWorldFrame(time: 0.016, eggs: [
        _egg('a', const Vec2(2, 2), const PuttLook(pattern: EggPattern.hearts)),
      ]));
      expect(identical(shell.material, before), isFalse,
          reason: 'no compiled material has its map swapped under it');
      expect(before?.map, isNull, reason: 'the old one let the paint go');
    });
  });

  group('the chick wears its hat', () {
    /// Sinks [look]'s egg at the nest and returns the chick that hatched.
    tjs.Object3D hatchOf(PuttWorld3D world, PuttLook look, double from) {
      final hatchlings =
          world.scene.children.firstWhere((c) => c.name == 'hatchlings');
      final before = {
        for (final c in hatchlings.children)
          if (c.visible) c,
      };
      world.applySnapshot(
          PuttWorldFrame(time: from, eggs: [_egg('me', _nest.position, look)]));
      var time = from + 0.016;
      while (time < from + 0.9) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 0.016;
      }
      return hatchlings.children
          .firstWhere((c) => c.visible && !before.contains(c));
    }

    List<String> hatsOn(tjs.Object3D chick) {
      final out = <String>[];
      chick.traverse((object) {
        if (object.name.startsWith('hatchling-hat-') && object.visible) {
          out.add(object.name);
        }
      });
      return out;
    }

    test('each chick carries every hat, and shows its own', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_hole(), eggRadius: 0.45);
      final crowned = hatchOf(
          world,
          const PuttLook(pattern: EggPattern.stars, hat: HatchlingHat.crown),
          0);
      expect(hatsOn(crowned), ['hatchling-hat-crown']);
      final every = <String>{};
      crowned.traverse((object) {
        if (object.name.startsWith('hatchling-hat-')) every.add(object.name);
      });
      expect(every, {
        for (final hat in HatchlingHat.values)
          if (hat != HatchlingHat.none) 'hatchling-hat-${hat.name}',
      });
    });

    test('a bare chick wears none, and a pooled chick changes hats', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(_hole(), eggRadius: 0.45);
      final bare = hatchOf(world, PuttLook.standard, 0);
      expect(hatsOn(bare), isEmpty);
      // Long after: the chicks are back in the nest, the pool comes round.
      var time = 0.9;
      while (time < 4) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 0.016;
      }
      final again =
          hatchOf(world, const PuttLook(hat: HatchlingHat.headphones), time);
      expect(hatsOn(again), ['hatchling-hat-headphones']);
    });
  });
}
