// The 3D world's own checks, math-side like the painted projection's were:
// the scene graph built from a hole definition (counts, parents, material
// colours), the egg's roll direction following its velocity's sign, the
// camera holding the target centred under yaw changes, the hop lifting and
// settling, the aim's pixel ray landing back on the world it came from,
// and a clean disposal - every object, geometry, material and owned
// texture dead, no renderer leaks. All of this runs with no GPU: the
// world is pure Dart up to the surface widget.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:three_js_math/three_js_math.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_art.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

/// A hole carrying every element kind the world builds, all inside a
/// modest green.
HoleDef fullDressingHole() {
  return HoleDef(
    id: 'dressing',
    par: 3,
    tee: const Vec2(3, 13),
    nest: Nest(const Vec2(37, 13), 0.9),
    bounds: Rect(Vec2.zero, Vec2(40, 26)),
    walls: [
      // The border, plus a straight hedge crossing the middle.
      WallSegment(Vec2.zero, Vec2(40, 0)),
      WallSegment(Vec2(40, 0), Vec2(40, 26)),
      WallSegment(Vec2(40, 26), Vec2(0, 26)),
      WallSegment(Vec2(0, 26), Vec2.zero),
      WallSegment(Vec2(16, 8), Vec2(24, 8)),
      // A bumper line on the south lane.
      WallSegment.bumper(Vec2(18, 20), Vec2(24, 20)),
    ],
    arcs: [
      // A hedged hook around the tee.
      WallArc.custom(
        const Vec2(10, 9),
        4,
        startAngle: 0,
        sweep: math.pi / 2,
      ),
      // A standing rock ring (full circle).
      WallArc.custom(
        const Vec2(30, 10),
        2.5,
        startAngle: 0,
        sweep: 2 * math.pi,
      ),
      // A bumper arc out east.
      WallArc.custom(
        const Vec2(30, 20),
        2,
        startAngle: math.pi * 0.9,
        sweep: math.pi * 0.6,
        bumper: true,
      ),
    ],
    obstacles: [
      // The hen: two stops, so she walks.
      MovingObstacle(
        id: 'hen-1',
        radius: 1.1,
        stops: [
          ObstacleStop(const Vec2(20, 14), dwellSeconds: 1),
          ObstacleStop(const Vec2(26, 14),
              dwellSeconds: 1, travelSecondsToNext: 2),
        ],
      ),
    ],
    water: [
      WaterCircle(const Vec2(12, 20), 1.8),
      WaterRect(Rect(Vec2(4, 2), Vec2(9, 5))),
      WaterPolygon([const Vec2(33, 3), const Vec2(38, 3), const Vec2(38, 7)]),
    ],
    boosts: [
      BoostStrip(const Vec2(34, 16), const Vec2(38, 16)),
    ],
    portals: [
      PortalPair('tunnel', const Vec2(14, 4), const Vec2(28, 23), radius: 0.9),
    ],
    wells: [
      const GravityWell(Vec2(35, 13), radius: 3.2, strength: 12),
    ],
    boxes: [
      QuestionBox('carton-1', const Vec2(9, 16)),
    ],
    decorations: const [
      Decoration('hay_bale', Vec2(6, 23), numbers: {'size': 1.0}),
      Decoration('fence', Vec2(2, 24), numbers: {'posts': 4, 'length': 2.0}),
      Decoration('tee_marker', Vec2(3, 13)),
    ],
  );
}

void main() {
  final dressing = fullDressingHole();
  PuttWorld3D builtWorld() {
    final world = PuttWorld3D(viewport: const ui.Size(800, 600));
    world.buildHole(dressing, eggRadius: 0.45);
    return world;
  }

  /// Depth-first walk of every object under [root].
  List<tjs.Object3D> walk(tjs.Object3D root) {
    final out = <tjs.Object3D>[];
    final queue = Queue<tjs.Object3D>()..add(root);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      out.add(current);
      queue.addAll(current.children);
    }
    return out;
  }

  PuttWorldEgg eggAt(
    Vec2 at, {
    Vec2 velocity = Vec2.zero,
    double height = 0,
    String playerId = 'me',
    double radius = 0.45,
    bool shielded = false,
    double ghostSeconds = 0,
    bool magnet = false,
    bool mine = false,
  }) {
    return PuttWorldEgg(
      playerId: playerId,
      position: at,
      velocity: velocity,
      tint: PuttPalette.tintForIndex(0),
      radius: radius,
      height: height,
      shielded: shielded,
      ghostSeconds: ghostSeconds,
      magnet: magnet,
      mine: mine,
    );
  }

  group('the hole builds a scene graph', () {
    test('one group per kind, with the right counts inside', () {
      final world = builtWorld();
      addTearDown(world.dispose);

      int countUnder(String kind) => world.holeGroup(kind)!.children.length;

      // The border (4) plus the crossing hedge.
      expect(countUnder('walls'), 5, reason: 'walls minus bumpers');
      // One rubber rail per bumper wall, one per bumper arc.
      expect(countUnder('bumpers'), 2,
          reason: 'the bumper wall and the bumper arc');
      // Hedge run + full-circle rock (in 'arcs' too).
      expect(countUnder('arcs'), greaterThan(0));
      expect(world.holeGroup('wells')!.children, isNotEmpty);
      expect(countUnder('water'), 3);
      expect(countUnder('boosts'), 1);
      expect(countUnder('portals'), 2);
      expect(countUnder('boxes'), 1);
      expect(countUnder('hens'), 1);
      // Two hay bales would be two; this hole carries one hay.
      expect(
        walk(world.holeGroup('decorations')!)
            .where((object) => object.name == 'hay-bale')
            .length,
        1,
      );
    });

    test('the green carries the lawn, lit and shadowed, under the ground group',
        () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final ground = world.holeGroup('ground')!.children.single;
      expect(ground.name, 'lawn');
      expect(ground.receiveShadow, isTrue);
      final material = (ground as tjs.Mesh).material!;
      expect(material.map, isNotNull, reason: 'the lawn is textured');
      expect(material.map!.colorSpace, tjs.SRGBColorSpace);
    });

    test('the bumper drum wears the brand palette, the ring the yolk', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final post = world.holeGroup('bumpers')!.children.first;
      final body = (post.children.firstWhere((c) => c.name == 'bumper-body')
          as tjs.Mesh);
      final ring = (post.children.firstWhere((c) => c.name == 'bumper-ring')
          as tjs.Mesh);
      // In linear light: the renderer's working space.
      expectHexClose(
          body.material!.color.getHex(), _linearHexOf(PuttPalette.comb));
      expectHexClose(
          ring.material!.color.getHex(), _linearHexOf(PuttPalette.yolk));
      expect(body.castShadow, isTrue);
    });

    test('the rail stands at its wall, turned along the run', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      // The straight hedge crossing the middle: run 8, no turn, standing
      // on the green. The border walls run 40 and 26 - find the short one.
      final walls = world
          .holeGroup('walls')!
          .children
          .where((child) => child.name == 'wall');
      double runOf(tjs.Object3D child) =>
          (child.children.first as tjs.Mesh).geometry!.parameters!['width']
              as double;
      final hedge = walls.firstWhere((child) => (runOf(child) - 8).abs() < 1);
      expect(hedge.rotation.y, closeTo(0, 1e-9),
          reason: 'the run is straight along +x');
      // The timber runs its wall's length plus its own thickness, so two
      // rails meeting at a corner close it.
      expect(runOf(hedge), closeTo(8.34, 1e-9));
      expect(hedge.position.x, closeTo(20, 1e-9));
      expect(hedge.position.z, closeTo(8, 1e-9),
          reason: 'an inner rail stands centred on its line');
      final body = hedge.children.first as tjs.Mesh;
      // Standing on the green: the box's centre off the ground.
      expect(body.position.y, greaterThan(0));
      // The border's rails stop at the green's corners (their colliders
      // overrun them), plus the fence's thickness.
      final lengths = walls.map(runOf).toList()..sort();
      expect(lengths, containsAllInOrder([8.34, 26.62, 40.62]));
      // The fence stands outside the green: its inner face on the line.
      final north = walls.firstWhere((child) =>
          (runOf(child) - 40.62).abs() < 1e-6 && child.position.z < 13);
      expect(north.position.z, closeTo(-0.31, 1e-6));
    });

    test("the hole's parent tree hangs under the world's hole group", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      for (final kind in [
        'ground',
        'table',
        'walls',
        'bumpers',
        'arcs',
        'wells',
        'water',
        'boosts',
        'portals',
        'boxes',
        'nest',
        'tee',
        'decorations',
        'hens',
        'scenery',
      ]) {
        final group = world.holeGroup(kind);
        expect(group, isNotNull, reason: kind);
        expect(group!.parent!.name, 'hole', reason: kind);
      }
    });
  });

  group('the garden', () {
    test('a corner the walls close off is carved away from the table', () {
      // A box of walls in the north-east corner: the egg can never get in,
      // and it reaches the table's edge, so the table takes it off.
      final hole = HoleDef(
        id: 'garden-check',
        par: 2,
        tee: const Vec2(3, 13),
        nest: Nest(const Vec2(20, 18), 0.9),
        bounds: Rect(Vec2.zero, Vec2(40, 26)),
        walls: [
          WallSegment(Vec2.zero, Vec2(40, 0)),
          WallSegment(Vec2(40, 0), Vec2(40, 26)),
          WallSegment(Vec2(40, 26), Vec2(0, 26)),
          WallSegment(Vec2(0, 26), Vec2.zero),
          WallSegment(Vec2(28, -1), Vec2(28, 10.2)),
          WallSegment(Vec2(27.8, 10), Vec2(41, 10)),
        ],
      );
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hole, eggRadius: 0.45);
      expect(world.holeGroup('garden'), isNull,
          reason: 'carved, not planted on the table');
      // No turf over the carved corner, but for the ledge under its rails.
      final lawn = world.holeGroup('ground')!.children.single as tjs.Mesh;
      final position = lawn.geometry!.attributes['position'] as dynamic;
      var inCorner = 0;
      for (var i = 0; i < position.count; i++) {
        final x = (position.getX(i) as num).toDouble();
        final z = (position.getZ(i) as num).toDouble();
        if (x > 29.5 && z < 8.5) inCorner++;
      }
      expect(inCorner, 0);
      // The fences split where they pass over the carved corner.
      final pieces = walk(world.holeGroup('walls')!)
          .where((object) => object.name == 'wall-piece');
      expect(pieces, isNotEmpty, reason: 'fences stop at the carved corner');
    });

    test('ground walled off in the middle of the green is a garden bed', () {
      final hole = HoleDef(
        id: 'island-check',
        par: 2,
        tee: const Vec2(3, 13),
        nest: Nest(const Vec2(37, 13), 0.9),
        bounds: Rect(Vec2.zero, Vec2(40, 26)),
        walls: [
          WallSegment(Vec2.zero, Vec2(40, 0)),
          WallSegment(Vec2(40, 0), Vec2(40, 26)),
          WallSegment(Vec2(40, 26), Vec2(0, 26)),
          WallSegment(Vec2(0, 26), Vec2.zero),
          // A closed box in the middle: the henhouse.
          WallSegment(Vec2(16, 9), Vec2(24, 9)),
          WallSegment(Vec2(24, 9), Vec2(24, 17)),
          WallSegment(Vec2(24, 17), Vec2(16, 17)),
          WallSegment(Vec2(16, 17), Vec2(16, 9)),
        ],
      );
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hole, eggRadius: 0.45);
      final garden = world.holeGroup('garden');
      expect(garden, isNotNull, reason: 'the island gets beds');
      expect(walk(garden!).where((o) => o.name == 'garden-plants'), isNotEmpty);
    });

    test('an open green has no garden', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      expect(world.holeGroup('garden'), isNull,
          reason: 'every corner of the dressing hole is in play');
    });
  });

  group('the low tier', () {
    test('a smaller shadow map, and outlines only on the eggs', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(3, 13))],
      ));
      bool shown(tjs.Object3D o) {
        for (tjs.Object3D? at = o; at != null; at = at.parent) {
          if (!at.visible) return false;
        }
        return true;
      }

      List<tjs.Object3D> outlines() => [
            for (final o in walk(world.scene))
              if (o.name.endsWith('-outline')) o,
          ];
      expect(
          outlines().where((o) => !o.name.startsWith('egg')).any(shown), isTrue,
          reason: 'the walkers and the host wear outlines by default');

      world.lowerQuality();
      expect(world.lowTier, isTrue);
      final sun = walk(world.scene)
          .whereType<tjs.DirectionalLight>()
          .firstWhere((light) => light.castShadow);
      expect(sun.shadow!.mapSize.x, 1024);
      // The eggs, the aim's arrow and the casts' characters (a crow) keep
      // theirs: the hole's walkers, host and scenery lose them.
      bool kept(String name) =>
          name.startsWith('egg') ||
          name.startsWith('aim') ||
          name.startsWith('crow');
      for (final o in outlines()) {
        expect(o.visible, kept(o.name), reason: o.name);
      }
    });
  });

  group('eggs roll and lift', () {
    test("the roll's axis follows the velocity's sign", () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      tjs.Vector3 upPointsIn(PuttWorld3D world) {
        final egg = world.eggOf('me')!;
        return tjs.Vector3(0, 1, 0).applyQuaternion(egg.quaternion);
      }

      // Rolling east: the top tips east.
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(3, 0))],
      ));
      world.applySnapshot(PuttWorldFrame(
        time: 0.016,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(3, 0))],
      ));
      final east = upPointsIn(world);
      expect(east.x, greaterThan(0.05), reason: 'top tips toward +x');
      expect(east.z, closeTo(0.0, 0.06));

      // Rolling west on a fresh world: the top tips west.
      final westWorld = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(westWorld.dispose);
      westWorld.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(-3, 0))],
      ));
      westWorld.applySnapshot(PuttWorldFrame(
        time: 0.016,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(-3, 0))],
      ));
      expect(upPointsIn(westWorld).x, lessThan(-0.05),
          reason: 'top tips toward -x');

      // And a north roll (game +y = world +z) leans toward +z.
      final northWorld = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(northWorld.dispose);
      northWorld.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(0, 3))],
      ));
      northWorld.applySnapshot(PuttWorldFrame(
        time: 0.016,
        eggs: [eggAt(const Vec2(2, 2), velocity: const Vec2(0, 3))],
      ));
      expect(upPointsIn(northWorld).z, greaterThan(0.05),
          reason: 'top tips toward +z (game south)');
    });

    test("the roll's angle carries omega = |v| / r over the frame", () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      const dt = 0.02;
      const velocity = Vec2(4, 0);
      // The drawn egg runs 1.2 times the physics' radius; it rolls on its
      // own shell.
      const radius = 0.45 * 1.2;
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(0, 0), velocity: velocity)],
      ));
      world.applySnapshot(PuttWorldFrame(
        time: dt,
        eggs: [eggAt(const Vec2(0, 0), velocity: velocity)],
      ));
      final up =
          tjs.Vector3(0, 1, 0).applyQuaternion(world.eggOf('me')!.quaternion);
      final turned = math.acos(clampDouble(up.y, -1, 1));
      expect(turned, closeTo(velocity.length * dt / radius, 1e-5),
          reason: 'distance rolled over radius, in radians');
    });

    test('the hop lifts the mesh and settles back to zero', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      // Standing on its tip: the drawn shell's half-height.
      const stand = 0.45 * 1.2 * 1.28;

      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(3, 3))],
      ));
      expect(world.eggOf('me')!.position.y, closeTo(stand, 1e-6));

      world.applySnapshot(PuttWorldFrame(
        time: 0.016,
        eggs: [eggAt(const Vec2(3, 3), height: 1.4)],
      ));
      expect(world.eggOf('me')!.position.y, closeTo(stand + 1.4, 1e-6));

      world.applySnapshot(PuttWorldFrame(
        time: 0.032,
        eggs: [eggAt(const Vec2(3, 3))],
      ));
      expect(world.eggOf('me')!.position.y, closeTo(stand, 1e-6),
          reason: "the hop's cosmetic arc comes back down");
    });

    test('an egg that drops into the nest hatches a chick', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final hatchlings =
          world.scene.children.firstWhere((c) => c.name == 'hatchlings');
      List<tjs.Object3D> out() =>
          hatchlings.children.where((c) => c.visible).toList();
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(dressing.nest.position)],
      ));
      expect(out(), isEmpty);
      // Gone at the nest: it sinks for a moment, then hatches.
      var time = 0.016;
      while (time < 0.9) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 0.016;
      }
      expect(out(), hasLength(1));
      expect(out().single.position.x, closeTo(dressing.nest.position.x, 1e-9));
      // Up on the nest's lip for its hops, over the dark cup.
      while (time < 1.6) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 0.016;
      }
      final rise =
          walk(out().single).firstWhere((o) => o.name == 'hatchling-rise');
      expect(rise.position.y, greaterThan(0.25));
      while (time < 3.8) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 0.016;
      }
      expect(out(), isEmpty, reason: 'the chick drops back into the nest');
    });

    test('the collected crates stand down and stay down', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final crate =
          world.holeGroup('boxes')!.children.firstWhere((c) => c.visible);
      expect(crate.visible, isTrue);
      world.applySnapshot(PuttWorldFrame(
        time: 1,
        collectedBoxes: {'carton-1'},
      ));
      // Taken: the carton pops (a swell over a quarter second), then goes.
      world.applySnapshot(PuttWorldFrame(
        time: 1.4,
        collectedBoxes: {'carton-1'},
      ));
      expect(crate.visible, isFalse);
      // The client's frames always carry the engine's collected set (the
      // crates stay hidden); the same hole WITHOUT the id - a fresh
      // engine world, mid-join into a new hole - finds cartons standing.
      world
          .applySnapshot(PuttWorldFrame(time: 2, collectedBoxes: {'carton-1'}));
      expect(crate.visible, isFalse, reason: 'the box is gone for the hole');
      world.applySnapshot(PuttWorldFrame(time: 3));
      expect(crate.visible, isTrue,
          reason: 'a frame without the id re-shows it (new hole, same id)');
    });
  });

  group('hills', () {
    HoleDef hilly() => HoleDef(
          id: 'hilly',
          par: 3,
          tee: const Vec2(3, 10),
          nest: Nest(const Vec2(26, 10), 0.9),
          bounds: Rect(Vec2.zero, Vec2(30, 20)),
          walls: [
            WallSegment(Vec2.zero, Vec2(30, 0)),
            WallSegment(Vec2(30, 0), Vec2(30, 20)),
            WallSegment(Vec2(30, 20), Vec2(0, 20)),
            WallSegment(Vec2(0, 20), Vec2.zero),
          ],
          hills: const [
            Hill.mound(Vec2(14, 10), height: 1.2, top: 0.6, skirt: 3),
            // The nest's plateau.
            Hill.mound(Vec2(26, 10), height: 0.8, top: 2, skirt: 1.5),
          ],
        );

    test('the turf rises over them, lit along its slopes', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hilly(), eggRadius: 0.45);
      final lawn = world.holeGroup('ground')!.children.single as tjs.Mesh;
      final position = lawn.geometry!.attributes['position'];
      final normal = lawn.geometry!.attributes['normal'];
      var highest = 0.0;
      var tilted = 0;
      for (var i = 0; i < position.count; i++) {
        highest = math.max(highest, position.getY(i)!.toDouble());
        if (normal.getY(i)! < 0.98) tilted++;
      }
      expect(highest, closeTo(1.2, 1e-6));
      expect(tilted, greaterThan(100));
      // The nest stands on its plateau.
      final nest = world.holeGroup('nest')!.children.single;
      expect(nest.position.y, closeTo(0.8, 1e-6));
    });

    test('an egg stands on the ground under it', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hilly(), eggRadius: 0.45);
      const stand = 0.45 * 1.2 * 1.28;
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [eggAt(const Vec2(14, 10))],
      ));
      expect(world.eggOf('me')!.position.y, closeTo(1.2 + stand, 1e-6));
      world.applySnapshot(PuttWorldFrame(
        time: 0.016,
        eggs: [eggAt(const Vec2(5, 10))],
      ));
      expect(world.eggOf('me')!.position.y, closeTo(stand, 1e-6));
    });

    test('a pixel over a slope lands back on the slope', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      final hole = hilly();
      world.buildHole(hole, eggRadius: 0.45);
      world.applySnapshot(PuttWorldFrame(time: 0));
      for (final point in const [
        Vec2(14, 10),
        Vec2(12.2, 9.1),
        Vec2(15.5, 11.8),
        Vec2(26, 10),
      ]) {
        final pixel = world.projectToWorld(point);
        final back = world.screenToWorld(pixel);
        expect(back, isNotNull);
        expect(back!.distanceTo(point), lessThan(0.02), reason: '$point');
      }
    });
  });

  group('tiers', () {
    // A terrace down the west side (its east edge a ledge), the floor, and
    // a railed ramp up to a higher terrace in the east (ledged either side
    // of the ramp's top) with the nest on it.
    HoleDef tiered() => HoleDef(
          id: 'tiered',
          par: 3,
          tee: const Vec2(4, 10),
          nest: Nest(const Vec2(26, 10), 0.9),
          bounds: Rect(Vec2.zero, Vec2(30, 20)),
          walls: [
            WallSegment(Vec2.zero, Vec2(30, 0)),
            WallSegment(Vec2(30, 0), Vec2(30, 20)),
            WallSegment(Vec2(30, 20), Vec2(0, 20)),
            WallSegment(Vec2(0, 20), Vec2.zero),
            WallSegment.ledge(const Vec2(10, 20), const Vec2(10, 0)),
            WallSegment(Vec2(16, 8), Vec2(20, 8)),
            WallSegment(Vec2(16, 12), Vec2(20, 12)),
            WallSegment.ledge(const Vec2(20, 0), const Vec2(20, 8)),
            WallSegment.ledge(const Vec2(20, 12), const Vec2(20, 20)),
          ],
          terraces: const [
            Terrace([Vec2(0, 0), Vec2(0, 20), Vec2(10, 20), Vec2(10, 0)],
                height: 1),
            Terrace([Vec2(20, 0), Vec2(20, 20), Vec2(30, 20), Vec2(30, 0)],
                height: 1.2),
          ],
          ramps: const [
            Ramp(Vec2(16, 10), Vec2(20, 10), width: 4, height: 1.2),
          ],
        );
    const stand = 0.45 * 1.2 * 1.28;

    test('a corn hedge too short for a tassel still builds', () {
      // A maze hole (the corn hedge's style) where a hedge ends a third of
      // a unit past a terrace's edge: the sliver carries no tassels and the
      // hole builds rather than throwing.
      final base = tiered();
      final hole = HoleDef(
        id: 'maze_sliver',
        par: base.par,
        tee: base.tee,
        nest: base.nest,
        bounds: base.bounds,
        walls: [...base.walls, WallSegment(Vec2(5, 4), Vec2(5.3, 4))],
        terraces: base.terraces,
        ramps: base.ramps,
      );
      final world = PuttWorld3D();
      addTearDown(world.dispose);
      expect(() => world.buildHole(hole, eggRadius: 0.45), returnsNormally);
    });

    test('the turf stands on the terraces and steps off them crisply', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(tiered(), eggRadius: 0.45);
      final lawn = world.holeGroup('ground')!.children.single as tjs.Mesh;
      final position = lawn.geometry!.attributes['position'];
      var onTheLip = 0;
      var atTheFoot = 0;
      for (var i = 0; i < position.count; i++) {
        final x = position.getX(i)!.toDouble();
        final y = position.getY(i)!.toDouble();
        final z = position.getZ(i)!.toDouble();
        if (z < 1 || z > 19) continue;
        if (x < 9.9) expect(y, closeTo(1, 1e-6), reason: 'on the terrace');
        if (x > 10.1 && x < 15.9) expect(y, closeTo(0, 1e-6));
        if (x > 20.1) expect(y, closeTo(1.2, 1e-6));
        // On the ledge's line the turf parts: both levels, nothing between.
        if ((x - 10).abs() < 1e-4) {
          expect(y.abs() < 1e-6 || (y - 1).abs() < 1e-6, isTrue,
              reason: 'a step, not a slope, at $x, $z');
          if (y > 0.5) {
            onTheLip++;
          } else {
            atTheFoot++;
          }
        }
        // Up the ramp: its smooth step along its axis.
        if (x > 16 && x < 20 && (z - 10).abs() < 1.9) {
          final t = (x - 16) / 4;
          expect(y, closeTo(1.2 * t * t * (3 - 2 * t), 1e-4));
        }
      }
      expect(onTheLip, greaterThan(20));
      expect(atTheFoot, greaterThan(20));
      // The nest stands on its terrace.
      expect(world.holeGroup('nest')!.children.single.position.y,
          closeTo(1.2, 1e-6));
    });

    test('a drop wears a face; the ramp\'s rails stand on its slope', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(tiered(), eggRadius: 0.45);
      final faces = walk(world.holeGroup('cliffs')!)
          .whereType<tjs.Mesh>()
          .where((mesh) => mesh.name == 'cliff-face')
          .single;
      final position = faces.geometry!.attributes['position'];
      var top = 0.0;
      var west = 0;
      for (var i = 0; i < position.count; i++) {
        top = math.max(top, position.getY(i)!.toDouble());
        if ((position.getX(i)! - 10).abs() < 1e-6) west++;
      }
      expect(top, closeTo(1.2, 1e-6));
      expect(west, greaterThan(0), reason: 'the west terrace\'s drop');
      // The ramp's rails climb with it, a step's face under them; the
      // fence round the terraces stands on them.
      final walls = walk(world.holeGroup('walls')!);
      expect(walls.where((o) => o.name == 'wall-step'), isNotEmpty);
      // A ledge is no rail.
      expect(world.holeGroup('walls')!.children, hasLength(6));
    });

    test('an egg rolled off a ledge falls through the air and lands', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(tiered(), eggRadius: 0.45);
      var time = 0.0;
      void frame(Vec2 at) {
        world.applySnapshot(PuttWorldFrame(time: time, eggs: [eggAt(at)]));
        time += 1 / 60;
      }

      tjs.Object3D shadowGroup() =>
          walk(world.scene).firstWhere((object) => object.name == 'egg-ground');
      int puffs() => walk(world.scene)
          .where((object) => object.name == 'burst-puff' && object.visible)
          .length;

      frame(const Vec2(9.4, 10));
      frame(const Vec2(9.7, 10));
      expect(world.eggOf('me')!.position.y, closeTo(1 + stand, 1e-6));
      // Past the lip: the shadow is on the floor at once, the egg still up
      // in the air, falling.
      var x = 10.05;
      frame(Vec2(x, 10));
      final first = world.eggOf('me')!.position.y;
      expect(first, lessThan(1 + stand));
      expect(first, greaterThan(stand + 0.9));
      expect(shadowGroup().position.y, closeTo(0, 1e-9));
      var landedAfter = -1;
      var previous = first;
      for (var i = 1; i < 40; i++) {
        x += 0.05;
        frame(Vec2(x, 10));
        final y = world.eggOf('me')!.position.y;
        expect(y, lessThanOrEqualTo(previous + 1e-9), reason: 'it only falls');
        previous = y;
        if (landedAfter < 0 && (y - stand).abs() < 1e-6) landedAfter = i;
      }
      // A fall from one unit at 18 units/s^2: a third of a second.
      expect(landedAfter, inInclusiveRange(17, 23));
      expect(puffs(), greaterThan(0), reason: 'the dust flies where it lands');
    });

    test('an egg rides a ramp down and up, never in the air', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(tiered(), eggRadius: 0.45);
      final ramp = tiered().ramps.single;
      var time = 0.0;
      for (final step in [
        for (var i = 0; i <= 40; i++) 19.9 - i * 0.1,
        for (var i = 0; i <= 40; i++) 15.9 + i * 0.1,
      ]) {
        final at = Vec2(step, 10);
        world.applySnapshot(PuttWorldFrame(time: time, eggs: [eggAt(at)]));
        time += 1 / 60;
        expect(world.eggOf('me')!.position.y,
            closeTo(ramp.heightAt(at) + stand, 0.02),
            reason: 'at $at');
      }
      expect(
          walk(world.scene)
              .where((object) => object.name == 'burst-puff' && object.visible),
          isEmpty);
    });
  });

  group('the camera rig', () {
    test('the target sits dead-centre under any yaw', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        followPoint: world.hole!.bounds.center,
      ));
      for (var i = 0; i < 12; i++) {
        final yaw = i / 12 * 2 * math.pi;
        world.rig
          ..aimAt(yaw: yaw)
          ..snap();
        world.applySnapshot(PuttWorldFrame(
          time: 0.016 * (i + 1),
          followPoint: world.hole!.bounds.center,
        ));
        final target = world.rig.target;
        final ndc = tjs.Vector3(target.x, 0, target.y).project(world.camera);
        expect(ndc.x.abs(), lessThan(1e-4), reason: 'yaw $yaw');
        expect(ndc.y.abs(), lessThan(1e-4), reason: 'yaw $yaw');
      }
    });

    test('a ground grid unprojects back onto itself through pixels', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(time: 0));
      final viewport = const ui.Size(800, 600);
      ndcToPixels(tjs.Vector3 ndc) => ui.Offset(
            (ndc.x + 1) / 2 * viewport.width,
            (1 - ndc.y) / 2 * viewport.height,
          );
      for (final x in [-14.0, -3.0, 0.0, 5.5, 17.0]) {
        for (final y in [-9.0, 0.0, 8.0]) {
          final world3 = tjs.Vector3(x, 0, y).project(world.camera);
          if (world3.z < -1 || world3.z > 1) continue; // off-frustum point
          final back = world.screenToWorld(ndcToPixels(world3));
          expect(back, isNotNull, reason: 'at ($x, $y)');
          expect(back!.x, closeTo(x, 1e-3), reason: 'at ($x, $y)');
          expect(back.y, closeTo(y, 1e-3), reason: 'at ($x, $y)');

          // The e2e's seam: world -> pixels lands the same world back.
          final pixel = world.projectToWorld(Vec2(x, y));
          expect(pixel.dx, closeTo((world3.x + 1) / 2 * viewport.width, 1e-6));
          expect(pixel.dy, closeTo((1 - world3.y) / 2 * viewport.height, 1e-6));
        }
      }
    });

    test('zoom and orbit gestures land clamped', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final min = world.rig.distanceMin;
      world.rig
        ..zoomByWheel(-100000)
        ..snap();
      expect(world.rig.distance, closeTo(min, 1e-6));
      world.rig
        ..orbitBy(0, 100000)
        ..snap();
      expect(world.rig.pitchDeg, PuttCameraRig.pitchMax);
      // The player's orbit stops at its own floor; only scripted moves go
      // lower, to show the horizon.
      world.rig
        ..orbitBy(0, -100000)
        ..snap();
      expect(world.rig.pitchDeg, PuttCameraRig.orbitPitchMin);
    });

    test('the follow point glides the target toward it', () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      var t = 0.0;
      for (var i = 0; i < 12; i++) {
        t += 1 / 60;
        world.applySnapshot(PuttWorldFrame(
          time: t,
          followPoint: const Vec2(10, 10),
        ));
      }
      expect(world.rig.target.x, greaterThan(5));
      expect(world.rig.target.y, greaterThan(5));
      final x = world.rig.target.x;
      final y = world.rig.target.y;
      world.applySnapshot(PuttWorldFrame(time: t + 1 / 60, followPoint: null));
      expect(world.rig.target.x, closeTo(x, 1e-9),
          reason: 'no follow point holds the target');
      expect(world.rig.target.y, closeTo(y, 1e-9),
          reason: 'no follow point holds the target');
    });
  });

  group("the casts' scenes", () {
    /// A plain second hole, to move the world on to.
    final otherHole = HoleDef(
      id: 'other',
      par: 2,
      tee: const Vec2(3, 5),
      nest: Nest(const Vec2(17, 5), 0.9),
      bounds: Rect(Vec2.zero, Vec2(20, 10)),
      walls: [
        WallSegment(Vec2.zero, Vec2(20, 0)),
        WallSegment(Vec2(20, 0), Vec2(20, 10)),
        WallSegment(Vec2(20, 10), Vec2(0, 10)),
        WallSegment(Vec2(0, 10), Vec2.zero),
      ],
    );

    test('a crow flies its arc with its loot; a new hole grounds it', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final casts = world.scene.children.firstWhere((c) => c.name == 'casts');
      List<tjs.Object3D> crows() =>
          casts.children.where((c) => c.name == 'cast-crow').toList();
      final loot = walk(casts)
          .where((o) => o.name.startsWith('crow-loot/'))
          .toList(growable: false);
      expect(crows(), hasLength(2), reason: 'two pooled, built once');
      expect(loot, hasLength(24), reason: "every power-up's icon, per crow");
      expect(crows().every((c) => !c.visible), isTrue);

      const from = Vec2(6, 13);
      const to = Vec2(20, 13);
      void fly(double progress, double time) =>
          world.applySnapshot(PuttWorldFrame(time: time, crows: [
            PuttWorldCrow(
                from: from, to: to, progress: progress, effectId: 'gust'),
          ]));
      fly(0.5, 0);
      final crow = crows().firstWhere((c) => c.visible);
      expect(crow.position.x, inExclusiveRange(from.x, to.x));
      expect(crow.position.y, greaterThan(3), reason: 'high on its arc');
      // Facing its way: its forward (+z) turned onto the flight (+x).
      expect(crow.rotation.y, closeTo(math.pi / 2, 1e-6));
      final carried = loot.where((o) => o.visible).toList();
      expect(carried.map((o) => o.name), ['crow-loot/gust']);
      expect(carried.single.position.distanceTo(crow.position), lessThan(3));
      // Its outline: inked like the other characters.
      expect(walk(crow).where((o) => o.name.endsWith('-outline')), hasLength(3),
          reason: 'the body and both wings');

      final along = crow.position.x;
      fly(0.7, 0.016);
      expect(crow.position.x, greaterThan(along));
      world.applySnapshot(PuttWorldFrame(time: 0.032));
      expect(crows().every((c) => !c.visible), isTrue);
      expect(loot.every((o) => !o.visible), isTrue);

      fly(0.4, 0.048);
      expect(crows().where((c) => c.visible), hasLength(1));
      world.buildHole(otherHole, eggRadius: 0.45);
      expect(crows().every((c) => !c.visible), isTrue,
          reason: 'a new hole starts clear of the last one\'s casts');
      expect(loot.every((o) => !o.visible), isTrue);
    });

    test('a shielded egg wears a bubble until the shield is spent', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      var time = 0.0;
      void frame({required bool shielded}) {
        world.applySnapshot(PuttWorldFrame(
            time: time, eggs: [eggAt(const Vec2(5, 9), shielded: shielded)]));
        time += 0.016;
      }

      frame(shielded: false);
      final bubble =
          walk(world.scene).firstWhere((o) => o.name == 'egg-bubble');
      expect(bubble.visible, isFalse);
      for (var i = 0; i < 30; i++) {
        frame(shielded: true);
      }
      expect(bubble.visible, isTrue);
      expect(bubble.position.x, closeTo(5, 1e-9));
      expect(bubble.position.z, closeTo(9, 1e-9));
      expect(bubble.position.y, greaterThan(0.3),
          reason: "round the egg's middle");
      expect(bubble.scale.x, greaterThan(0.45 * 1.2 * 3),
          reason: 'blown up round the whole egg');
      expect(bubble.material!.map, isNotNull);
      frame(shielded: false);
      expect(bubble.visible, isFalse, reason: 'popped: the shield is spent');
    });

    test('a ghost egg fades by its opacity alone, then comes back solid', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      var time = 0.0;
      void frame(double ghostSeconds) {
        world.applySnapshot(PuttWorldFrame(
            time: time,
            eggs: [eggAt(const Vec2(5, 9), ghostSeconds: ghostSeconds)]));
        time += 0.016;
      }

      frame(0);
      final egg = world.eggOf('me')!;
      final shell = walk(egg).firstWhere((o) => o.name == 'egg-shell');
      final outline = walk(egg).firstWhere((o) => o.name == 'egg-outline');
      final shellMaterial = shell.material!;
      final outlineMaterial = outline.material!;
      // Transparent from the start: a fade moves a uniform, no program
      // recompiles.
      expect(shellMaterial.transparent, isTrue);
      expect(outlineMaterial.transparent, isTrue);
      expect(shellMaterial.opacity, closeTo(1, 1e-9));

      final seen = <double>{};
      for (var i = 0; i < 40; i++) {
        frame(2.5);
        seen.add(shellMaterial.opacity);
      }
      expect(identical(shell.material, shellMaterial), isTrue,
          reason: 'never a material swapped in play');
      expect(seen.every((opacity) => opacity < 0.6), isTrue,
          reason: 'see-through the whole time');
      expect(seen.length, greaterThan(10), reason: 'and flickering');
      expect(outlineMaterial.opacity, lessThan(0.6));

      frame(0);
      expect(shellMaterial.opacity, closeTo(1, 1e-9));
      expect(outlineMaterial.opacity, closeTo(1, 1e-9));
    });

    test('a hen pops out of the close-up quickly, and back after', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final hen = world.holeGroup('hens')!.children.first;
      const walking = PuttWorldHen(
          position: Vec2(20, 14), radius: 1.1, phase: 0, heading: Vec2(1, 0));
      var time = 0.0;
      void frame({required bool closeUp}) {
        world.applySnapshot(PuttWorldFrame(
            time: time, hens: const [walking], closeUp: closeUp));
        time += 0.016;
      }

      frame(closeUp: false);
      expect(hen.visible, isTrue);
      final opacities = <double>[];
      for (var i = 0; i < 12; i++) {
        frame(closeUp: true);
        opacities.add(
            walk(hen).firstWhere((o) => o.material != null).material!.opacity);
      }
      expect(hen.visible, isFalse, reason: 'gone within 0.2 s');
      expect(opacities.where((o) => o > 0.02 && o < 0.98).length,
          lessThanOrEqualTo(10),
          reason: 'never long half-seen');
      for (var i = 0; i < 12; i++) {
        frame(closeUp: false);
      }
      expect(hen.visible, isTrue);
      expect(
          walk(hen).firstWhere((o) => o.material != null).material!.opacity, 1);
    });

    test("an egg in front of the viewer's resting egg fades aside", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      const mineAt = Vec2(10, 10);
      world.applySnapshot(
          PuttWorldFrame(time: 0, eggs: [eggAt(mineAt, mine: true)]));
      // On the ground line from mine toward the camera, close in front.
      final eye = world.camera.position;
      final toward = Vec2(eye.x - mineAt.x, eye.z - mineAt.y);
      final front = mineAt + toward * (1.3 / toward.length);
      const aside = Vec2(16, 4);
      var time = 0.016;
      void frame({Vec2 velocity = Vec2.zero}) {
        world.applySnapshot(PuttWorldFrame(time: time, eggs: [
          eggAt(mineAt, mine: true, velocity: velocity),
          eggAt(front, playerId: 'front'),
          eggAt(aside, playerId: 'aside'),
        ]));
        time += 0.016;
      }

      double opacityOf(String playerId) => walk(world.eggOf(playerId)!)
          .firstWhere((o) => o.name == 'egg-shell')
          .material!
          .opacity;
      for (var i = 0; i < 30; i++) {
        frame();
      }
      expect(opacityOf('front'), lessThan(0.5),
          reason: 'mine, its pin and the aim read through it');
      expect(opacityOf('front'), greaterThan(0.2), reason: 'still there');
      expect(opacityOf('aside'), closeTo(1, 1e-9),
          reason: 'an egg elsewhere stays solid');
      expect(opacityOf('me'), closeTo(1, 1e-9));

      // Mine on the move: nothing to read through any more.
      for (var i = 0; i < 30; i++) {
        frame(velocity: const Vec2(3, 0));
      }
      expect(opacityOf('front'), closeTo(1, 1e-9));
    });

    test('the nest shimmers while an egg carries a magnet', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final shimmer =
          walk(world.scene).firstWhere((o) => o.name == 'cast-magnet');
      var time = 0.0;
      void frame({required bool magnet}) {
        world.applySnapshot(PuttWorldFrame(
            time: time, eggs: [eggAt(const Vec2(5, 9), magnet: magnet)]));
        time += 0.016;
      }

      frame(magnet: false);
      expect(shimmer.visible, isFalse);
      for (var i = 0; i < 20; i++) {
        frame(magnet: true);
      }
      expect(shimmer.visible, isTrue);
      expect(shimmer.position.x, closeTo(dressing.nest.position.x, 1e-9));
      expect(shimmer.position.z, closeTo(dressing.nest.position.y, 1e-9));
      final ring = shimmer.children.firstWhere((c) => c.name == 'magnet-ring');
      expect(ring.material!.opacity, greaterThan(0.3));
      for (var i = 0; i < 80; i++) {
        frame(magnet: false);
      }
      expect(shimmer.visible, isFalse,
          reason: 'it fades once the pull is over');
    });

    test('a ring with a reach spreads no further, near or far', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final root = world.scene.children.firstWhere((c) => c.name == 'fx');
      world.applySnapshot(const PuttWorldFrame(time: 0, fxs: [
        PuttWorldFx(
            kind: PuttWorldFxKind.ring,
            at: Vec2(10, 10),
            progress: 0.95,
            size: 2.4,
            reach: 0.8),
        PuttWorldFx(
            kind: PuttWorldFxKind.ring,
            at: Vec2(14, 10),
            progress: 0.95,
            size: 2.4),
      ]));
      final shown =
          root.children.where((c) => c.name == 'fx-ring' && c.visible).toList();
      expect(shown, hasLength(2));
      final radii = shown.map((ring) => ring.scale.x).toList()..sort();
      expect(radii.first, closeTo(0.8, 1e-6), reason: 'held to its reach');
      expect(radii.last, greaterThan(3), reason: 'the other spreads');
    });

    test("the casts' particles draw from their own pools", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final root = world.scene.children.firstWhere((c) => c.name == 'fx');
      int shown(String name) =>
          root.children.where((c) => c.name == name && c.visible).length;
      const at = Vec2(10, 10);
      world.applySnapshot(const PuttWorldFrame(time: 0, fxs: [
        PuttWorldFx(
            kind: PuttWorldFxKind.kernel,
            at: at,
            progress: 0.3,
            size: 0.5,
            height: 2),
        PuttWorldFx(
            kind: PuttWorldFxKind.streak,
            at: at,
            toward: Vec2(10, 12),
            progress: 0.5,
            size: 0.6),
        PuttWorldFx(
            kind: PuttWorldFxKind.steam, at: at, progress: 0.4, size: 0.4),
        PuttWorldFx(
            kind: PuttWorldFxKind.swirl, at: at, progress: 0.2, size: 0.3),
        PuttWorldFx(
            kind: PuttWorldFxKind.glint, at: at, progress: 0.5, size: 0.4),
        PuttWorldFx(
            kind: PuttWorldFxKind.shard,
            at: at,
            progress: 0.2,
            size: 0.25,
            height: 0.8),
        PuttWorldFx(
            kind: PuttWorldFxKind.feather,
            at: at,
            progress: 0.3,
            size: 0.45,
            height: 1.2),
      ]));
      expect(shown('fx-kernel'), 1, reason: 'kernels: their own drawing');
      expect(shown('fx-paper'), 2, reason: 'shards and feathers: paper');
      expect(shown('fx-streak'), 1, reason: 'the wind: its own line');
      expect(shown('fx'), 3, reason: 'steam, swirl, glint: soft');
      final kernel =
          root.children.firstWhere((c) => c.name == 'fx-kernel' && c.visible);
      expect(kernel.position.y, closeTo(2, 1e-9), reason: 'up in the air');
      final soft = root.children.firstWhere((c) => c.name == 'fx');
      expect(kernel.material!.map, isNotNull);
      expect(kernel.material!.map, isNot(same(soft.material!.map)),
          reason: 'no sprite ever changes its map: each pool keeps its own');
      final streak =
          root.children.firstWhere((c) => c.name == 'fx-streak' && c.visible);
      expect(streak.scale.x, greaterThan(streak.scale.y * 6),
          reason: 'the wind: long and thin');
      // The pools skip the matrix work while hidden: a shown sprite is
      // still drawn where it stands.
      world.scene.updateMatrixWorld();
      for (final sprite in [kernel, streak]) {
        final drawn = tjs.Vector3().setFromMatrixPosition(sprite.matrixWorld);
        expect(drawn.x, closeTo(sprite.position.x, 1e-6));
        expect(drawn.y, closeTo(sprite.position.y, 1e-6));
        expect(drawn.z, closeTo(sprite.position.z, 1e-6));
      }

      world.applySnapshot(const PuttWorldFrame(time: 0.016));
      expect(
          shown('fx-kernel') +
              shown('fx-paper') +
              shown('fx-streak') +
              shown('fx'),
          0);
    });
  });

  group('the world disposes cleanly', () {
    test('every object and geometry is dead; the gpu resources fire dispose',
        () {
      final world = builtWorld();
      final objects = walk(world.scene);
      final geometries = <tjs.BufferGeometry>[];
      // Materials and textures carry no disposed flag, only the event:
      // listen, then count who said goodbye.
      final deadMaterials = <int>{};
      final deadTextures = <int>{};
      final materials = <tjs.Material>[];
      final textures = <tjs.Texture>[];
      for (final object in objects) {
        final geometry = object.geometry;
        if (geometry != null) geometries.add(geometry);
        final material = object.material;
        if (material != null) {
          material.addEventListener('dispose', (tjs.Event event) {
            final target = event.target;
            if (target is tjs.Material) deadMaterials.add(target.id);
          });
          materials.add(material);
          final map = material.map;
          if (map is tjs.Texture && !textures.contains(map)) {
            map.addEventListener('dispose', (tjs.Event event) {
              final target = event.target;
              if (target is tjs.Texture) deadTextures.add(target.id);
            });
            textures.add(map);
          }
        }
      }

      world.dispose();
      expect(world.scene.disposed, isTrue);
      expect(world.camera.disposed, isTrue);
      for (final object in objects) {
        expect(object.disposed, isTrue, reason: '${object.name} alive');
      }
      for (final geometry in geometries) {
        expect(geometry.disposed, isTrue);
      }
      for (final material in materials) {
        expect(deadMaterials.contains(material.id), isTrue,
            reason: 'material ${material.name} never disposed');
      }
      for (final texture in textures) {
        expect(deadTextures.contains(texture.id), isTrue,
            reason: 'a lawn/crate texture leaked');
      }
      expect(textures, isNotEmpty,
          reason: 'the hole under test carries textures');
    });

    test('dispose is idempotent, and a disposed world ignores frames', () {
      final world = builtWorld();
      world.dispose();
      world.dispose();
      world.applySnapshot(PuttWorldFrame(time: 1, eggs: [eggAt(Vec2.zero)]));
      expect(world.eggOf('me'), isNull);
    });
  });
}

/// Two packed colours alike channel by channel, give or take the one step
/// the engine's float-to-byte read may floor away.
void expectHexClose(int actual, int expected) {
  for (final shift in const [16, 8, 0]) {
    expect(((actual >> shift) & 0xFF) - ((expected >> shift) & 0xFF),
        inInclusiveRange(-1, 1),
        reason: 'channel at bit $shift of ${actual.toRadixString(16)} vs '
            '${expected.toRadixString(16)}');
  }
}

/// A palette colour as the world hands it to three_js: each channel taken
/// from sRGB into linear light, then packed as hex.
int _linearHexOf(ui.Color color) {
  final hex = color.toARGB32() & 0xFFFFFF;
  int channel(int shift) {
    final c = ((hex >> shift) & 0xFF) / 255;
    final linear = c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return (linear * 255).round();
  }

  return (channel(16) << 16) | (channel(8) << 8) | channel(0);
}
