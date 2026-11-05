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
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
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

    test("the aim traces the viewer's last roll, in their colour", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      List<tjs.Object3D> traced() => walk(world.scene)
          .where((o) => o.name == 'aim-trace' && o.visible)
          .toList();
      PuttWorldFrame frame(List<List<Vec2>> trace) => PuttWorldFrame(
            time: 0,
            eggs: [eggAt(const Vec2(10, 10), mine: true)],
            aim: PuttWorldAim(
              origin: const Vec2(10, 10),
              angle: 0,
              power: 0.5,
              dragLength: 3,
              eggRadius: 0.45,
              trace: trace,
              traceTint: PuttPalette.tintForIndex(2),
            ),
          );
      world.applySnapshot(frame(const []));
      expect(traced(), isEmpty);
      // From the tee at (4, 10) to here, and a stretch after a jump.
      world.applySnapshot(frame(const [
        [Vec2(4, 10), Vec2(10, 10)],
        [Vec2(20, 4), Vec2(22, 4)],
      ]));
      final dots = traced();
      expect(dots.length, greaterThan(15));
      // Laid along the stretches, relative to the aim's origin.
      for (final dot in dots) {
        final x = dot.position.x + 10;
        final z = dot.position.z + 10;
        final onFirst = (z - 10).abs() < 1e-6 && x >= 4 - 1e-6 && x <= 10;
        final onSecond = (z - 4).abs() < 1e-6 && x >= 20 - 1e-6 && x <= 22;
        expect(onFirst || onSecond, isTrue, reason: 'at ($x, $z)');
      }
      expect(dots.first.material!.opacity, lessThan(0.9),
          reason: "softer than the guide's dots");
    });

    test("only the viewer's egg shows through what hides it", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(time: 0, eggs: [
        eggAt(const Vec2(10, 10), mine: true),
        eggAt(const Vec2(14, 10), playerId: 'other'),
      ]));
      bool xray(String id) => walk(world.eggOf(id)!)
          .firstWhere((o) => o.name == 'egg-xray')
          .visible;
      expect(xray('me'), isTrue, reason: 'finding my own egg behind a silo');
      expect(xray('other'), isFalse,
          reason: "another's read as a stray translucent oval");
    });

    test('the aim draws over the other eggs, the pin over everything', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      world.applySnapshot(PuttWorldFrame(
        time: 0,
        eggs: [
          eggAt(const Vec2(10, 10), mine: true),
          eggAt(const Vec2(13, 10), playerId: 'other'),
        ],
        aim: const PuttWorldAim(
            origin: Vec2(10, 10),
            angle: 0,
            power: 0.6,
            dragLength: 3,
            eggRadius: 0.45,
            preview: [Vec2(11, 10), Vec2(13, 10), Vec2(15, 10)]),
      ));
      int orderOf(String playerId) => walk(world.eggOf(playerId)!)
          .firstWhere((o) => o.name == 'egg-shell')
          .renderOrder;
      final aim = walk(world.scene)
          .where((o) => o.name == 'aim-shaft' || o.name == 'aim-head')
          .toList();
      expect(aim, isNotEmpty);
      for (final piece in aim) {
        expect(piece.material!.depthTest, isFalse,
            reason: 'no egg in the way hides where the putt goes');
        expect(piece.renderOrder, greaterThan(orderOf('other')));
        expect(piece.renderOrder, lessThan(orderOf('me')),
            reason: 'the arrow comes out from under my own egg');
      }
      final pin = walk(world.eggOf('me')!)
          .followedBy(walk(world.scene))
          .firstWhere((o) => o.name == 'egg-arrow');
      expect(pin.material!.depthTest, isFalse);
      expect(pin.material!.transparent, isTrue,
          reason: 'in the pass drawn last, by its order');
      expect(pin.renderOrder, greaterThan(orderOf('me')));
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

  test("a traced pond's foam is one ribbon along its shore", () {
    final world = builtWorld();
    addTearDown(world.dispose);
    final foam =
        walk(world.scene).where((o) => o.name == 'water-foam').toList();
    expect(foam, hasLength(1),
        reason: 'the triangle pond; circles and rects paint their own');
    const corners = [Vec2(33, 3), Vec2(38, 3), Vec2(38, 7)];
    final centre = Vec2((33 + 38 + 38) / 3, (3 + 3 + 7) / 3);
    double toShore(Vec2 p) {
      var best = double.infinity;
      for (var i = 0; i < corners.length; i++) {
        final a = corners[i];
        final b = corners[(i + 1) % corners.length];
        final ab = b - a;
        final t = ((p - a).dot(ab) / ab.dot(ab)).clamp(0.0, 1.0);
        best = math.min(best, (a + ab * t - p).length);
      }
      return best;
    }

    final pond = dressing.water.whereType<WaterPolygon>().single;
    final geometry = foam.single.geometry!;
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final uv = geometry.attributes['uv'] as tjs.BufferAttribute;
    expect(position.count, greaterThan(20));
    var deep = 0;
    var inner = 0;
    for (var i = 0; i < position.count; i++) {
      final p = Vec2(centre.x + position.getX(i)!.toDouble(),
          centre.y - position.getY(i)!.toDouble());
      if (uv.getY(i)! < 0.5) {
        expect(toShore(p), lessThan(0.03), reason: 'its edge on the shore');
      } else {
        inner++;
        expect(pond.contains(p) || toShore(p) < 0.01, isTrue,
            reason: 'its inner side on the water');
        if (toShore(p) > 0.15) deep++;
      }
    }
    // A band's width in, but where a sharp corner narrows it.
    expect(deep / inner, greaterThan(0.85));
  });

  group('the birds', () {
    /// The vertices of [mesh] in its own frame.
    List<tjs.Vector3> pointsOf(tjs.Object3D mesh) {
      final position =
          mesh.geometry!.attributes['position'] as tjs.BufferAttribute;
      return [
        for (var i = 0; i < position.count; i++)
          tjs.Vector3(position.getX(i)!.toDouble(),
              position.getY(i)!.toDouble(), position.getZ(i)!.toDouble()),
      ];
    }

    /// A foot's vertices as (ahead, side) about its ankle: three toes reach
    /// out past [reach] (straight on and splayed either way) and a fourth
    /// past [back] behind.
    void expectToes(List<(double, double)> foot,
        {required double reach, required double back}) {
      final ahead = [
        for (final (a, s) in foot)
          if (math.sqrt(a * a + s * s) > reach) math.atan2(s, a),
      ];
      expect(ahead.any((angle) => angle.abs() < 0.2), isTrue,
          reason: 'the middle toe');
      expect(ahead.any((angle) => angle > 0.4 && angle < 0.8), isTrue,
          reason: 'a toe splayed one way');
      expect(ahead.any((angle) => angle < -0.4 && angle > -0.8), isTrue,
          reason: 'and one the other');
      expect(
          foot.any((p) =>
              math.sqrt(p.$1 * p.$1 + p.$2 * p.$2) > back &&
              math.atan2(p.$2, p.$1).abs() > 2.6),
          isTrue,
          reason: 'the short toe behind');
    }

    tjs.Object3D hostOf(PuttWorld3D world) =>
        walk(world.holeGroup('scenery')!).firstWhere((o) => o.name == 'host');

    test('the host stands on two scaly legs, three toes ahead and one behind',
        () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final body = walk(hostOf(world)).firstWhere((o) => o.name == 'host-body');
      // His own units: the ground at y = 0, forward +x, his sides along z.
      final points = pointsOf(body);
      final shanks = [
        for (final p in points)
          if (p.y > 0.8 && p.y < 1.2) p,
      ];
      expect(shanks, isNotEmpty);
      expect(shanks.where((p) => p.z.abs() < 0.5), isEmpty,
          reason: 'two legs, not one post');
      for (final side in [-1.0, 1.0]) {
        // The ankle: the shank's middle just over the foot.
        final low = [
          for (final p in points)
            if (p.y > 0.42 && p.y < 0.6 && p.z * side > 0) p,
        ];
        expect(low, isNotEmpty, reason: 'a leg on each side');
        final ankleX = low.map((p) => p.x).reduce((a, b) => a + b) / low.length;
        final ankleZ = low.map((p) => p.z).reduce((a, b) => a + b) / low.length;
        expectToes([
          for (final p in points)
            if (p.y < 0.32 && p.z * side > 0) (p.x - ankleX, p.z - ankleZ),
        ], reach: 0.65, back: 0.4);
      }
      // The scales: bands of two yellow-oranges down each shank (between
      // the spur and the drumstick nothing else stands there).
      final colors = body.geometry!.attributes['color'] as tjs.BufferAttribute;
      final ratios = <double>{};
      for (var i = 0; i < colors.count; i++) {
        if (points[i].y < 1.05 || points[i].y > 1.6) continue;
        final r = colors.getX(i)!.toDouble();
        final g = colors.getY(i)!.toDouble();
        final b = colors.getZ(i)!.toDouble();
        expect(g / r, lessThan(0.5), reason: 'yellow-orange');
        expect(b / r, lessThan(0.1), reason: 'yellow-orange');
        ratios.add((g / r * 100).roundToDouble());
      }
      expect(ratios.reduce(math.max) - ratios.reduce(math.min), greaterThan(5),
          reason: 'banded: two tones, not one');
    });

    test('the host breathes, and turns to the camera while the hole opens', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final host = hostOf(world);
      final head = walk(host).firstWhere((o) => o.name == 'host-head');
      final breath = walk(host).firstWhere((o) => o.name == 'host-breath');
      // The camera where the sweep sets off: low over the nest, turned off
      // to the side, well round from where he faces.
      world.rig.aimAt(
          yaw: math.pi + 0.55,
          pitchDeg: 15,
          distance: world.rig.overviewDistance * 0.92,
          target: dressing.nest.position);
      // My egg at rest out on the green, which he watches otherwise.
      final egg = eggAt(const Vec2(30, 13), mine: true);
      var time = 0.0;
      final swells = <double>[];
      void run(double seconds, {required bool opening}) {
        for (var t = 0.0; t < seconds; t += 1 / 60) {
          world.applySnapshot(
              PuttWorldFrame(time: time, eggs: [egg], opening: opening));
          swells.add(breath.scale.x);
          time += 1 / 60;
        }
        world.scene.updateMatrixWorld(true);
      }

      /// Where his beak points, from his head.
      (tjs.Vector3, tjs.Vector3) look() {
        final at = head.localToWorld(tjs.Vector3(0, 0, 0));
        final ahead = head.localToWorld(tjs.Vector3(1, 0, 0))..sub(at);
        return (at, ahead);
      }

      /// How far, on the ground, he looks off [target] (radians).
      double offFrom(tjs.Vector3 target) {
        final (at, ahead) = look();
        final to = target.clone()..sub(at);
        final turn =
            (math.atan2(ahead.z, ahead.x) - math.atan2(to.z, to.x)).abs() %
                (2 * math.pi);
        return math.min(turn, 2 * math.pi - turn);
      }

      run(2.5, opening: true);
      expect(offFrom(world.camera.position), lessThan(0.25),
          reason: 'he looks round at the camera, his body coming too');
      expect(look().$2.y, greaterThan(0), reason: 'up at it');
      run(2.5, opening: false);
      expect(offFrom(tjs.Vector3(30, 0, 13)), lessThan(0.5),
          reason: 'then back to the egg in play');
      expect(offFrom(world.camera.position), greaterThan(0.6));
      expect(look().$2.y, lessThan(0), reason: 'down at the green');
      // His breath: his body swells about two per cent, and back.
      final swell = swells.reduce(math.max) - swells.reduce(math.min);
      expect(swell, inInclusiveRange(0.015, 0.025));
    });

    test("the host pops out of the camera's face, every feather with him", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final host = hostOf(world);
      final meshes = walk(host).where((o) => o.material != null).toList();
      expect(
          meshes
              .where((o) => o.name.endsWith('-outline'))
              .map((o) => o.name)
              .toSet(),
          {
            'host-body-outline',
            'host-wing-feathers-outline',
            'host-face-outline'
          },
          reason: 'inked all over, wings too');
      for (final mesh in meshes) {
        expect(mesh.material!.transparent, isTrue,
            reason: '${mesh.name}: a fade only moves a uniform');
      }
      // The camera right over him.
      world.rig.aimAt(
          target: Vec2(host.position.x, host.position.z),
          pitchDeg: 72,
          distance: 12);
      var time = 0.0;
      for (var i = 0; i < 20; i++) {
        world.applySnapshot(PuttWorldFrame(time: time));
        time += 1 / 60;
      }
      expect(host.visible, isFalse);
      for (final mesh in meshes) {
        expect(mesh.material!.opacity, lessThan(0.05), reason: mesh.name);
      }
    });

    test('the host stays gone while the camera wavers at the line', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final host = hostOf(world);
      final spot = Vec2(host.position.x, host.position.z);
      var time = 0.0;
      // Looking down at him from [pitchDeg]: the camera stands cos(pitch)
      // of its distance off him, along the ground.
      void hold(double pitchDeg) {
        // Far enough back that his head stands well clear of the HUD.
        world.rig.aimAt(target: spot, pitchDeg: pitchDeg, distance: 30);
        for (var i = 0; i < 20; i++) {
          world.applySnapshot(PuttWorldFrame(time: time));
          time += 1 / 60;
        }
      }

      hold(72);
      expect(host.visible, isFalse, reason: 'right over him');
      hold(54.5);
      expect(host.visible, isFalse, reason: 'just past the line: still gone');
      hold(40);
      expect(host.visible, isTrue, reason: 'well clear: back');
    });

    test("the hen's legs step with her walk, the planted foot on the ground",
        () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final hen = world.holeGroup('hens')!.children.first;
      final legs = hen.children.where((o) => o.name == 'hen-leg').toList();
      expect(legs, hasLength(2));
      final feet = [
        for (final leg in legs)
          walk(leg).firstWhere((o) => o.name == 'hen-foot'),
      ];
      const r = 1.1;
      // Her own toes, like the host's: in her hip's frame forward is +z.
      for (final foot in feet) {
        final points = pointsOf(foot);
        final low = [
          for (final p in points)
            if (p.y < -r * 0.45 && p.y > -r * 0.55) p,
        ];
        final ankleZ = low.map((p) => p.z).reduce((a, b) => a + b) / low.length;
        final ankleX = low.map((p) => p.x).reduce((a, b) => a + b) / low.length;
        expectToes([
          for (final p in points)
            if (p.y < -r * 0.5) (p.z - ankleZ, p.x - ankleX),
        ], reach: r * 0.25, back: r * 0.14);
      }
      double lowest(tjs.Object3D foot) {
        var low = double.infinity;
        for (final p in pointsOf(foot)) {
          low = math.min(low, p.applyMatrix4(foot.matrixWorld).y);
        }
        return low;
      }

      var time = 0.0;
      var phase = 0.0;
      final lifted = [false, false];
      for (var i = 0; i < 90; i++) {
        // Walking east along her path, the waddle clock running as the
        // game's does (its ticks times 0.12, 120 a second).
        world.applySnapshot(PuttWorldFrame(time: time, hens: [
          PuttWorldHen(
              position: Vec2(20 + i * 0.03, 14),
              radius: r,
              phase: phase,
              heading: const Vec2(1, 0)),
        ]));
        world.scene.updateMatrixWorld(true);
        final lows = [for (final foot in feet) lowest(foot)];
        expect(math.min(lows[0], lows[1]), closeTo(0, r * 0.02),
            reason: 'a foot planted on the ground');
        if (i > 0) {
          expect(legs[0].rotation.x, closeTo(-legs[1].rotation.x, 1e-9),
              reason: 'the legs swing opposite');
          for (var k = 0; k < 2; k++) {
            if (lows[k] > r * 0.06) lifted[k] = true;
          }
        }
        time += 1 / 60;
        phase += 14.4 / 60;
      }
      expect(lifted, [true, true], reason: 'each foot lifts as it swings');
    });

    test('every part of the hen pops out of a close-up with her, legs too', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      final hen = world.holeGroup('hens')!.children.first;
      final meshes = walk(hen).where((o) => o.material != null).toList();
      expect(meshes.where((o) => o.name == 'hen-foot'), hasLength(2));
      expect(meshes.where((o) => o.name == 'hen-foot-outline'), hasLength(2),
          reason: 'her legs are inked too');
      for (final mesh in meshes) {
        expect(mesh.material!.transparent, isTrue,
            reason: '${mesh.name}: a fade only moves a uniform');
      }
      const walking = PuttWorldHen(
          position: Vec2(20, 14), radius: 1.1, phase: 0, heading: Vec2(1, 0));
      var time = 0.0;
      void frames(int count, {required bool closeUp}) {
        for (var i = 0; i < count; i++) {
          world.applySnapshot(PuttWorldFrame(
              time: time, hens: const [walking], closeUp: closeUp));
          time += 0.016;
        }
      }

      frames(14, closeUp: true);
      expect(hen.visible, isFalse);
      for (final mesh in meshes) {
        expect(mesh.material!.opacity, lessThan(0.05), reason: mesh.name);
      }
      expect(walk(hen).where((o) => o.castShadow), isEmpty,
          reason: 'no shadow of a hen who is not there');
      frames(14, closeUp: false);
      expect(hen.visible, isTrue);
      for (final mesh in meshes) {
        expect(mesh.material!.opacity, 1, reason: mesh.name);
      }
      expect(
          meshes.where((o) => o.name == 'hen-foot').every((o) => o.castShadow),
          isTrue,
          reason: 'her feet cast their shadows again');
    });
  });

  group("the courses' props and the tees' signs", () {
    // Every hole of every course, built once with its number, read and let
    // go: the props its farm stood, and the sign beside its tee.
    final built = <_BuiltHole>[];
    setUpAll(() {
      for (final course in sunnySidePuttCourses) {
        for (var i = 0; i < course.holes.length; i++) {
          final hole = course.holes[i].hole;
          final world = PuttWorld3D(viewport: const ui.Size(800, 600));
          world.buildHole(hole, eggRadius: 0.45, label: '${i + 1}');
          final farm = walk(world.holeGroup('scenery')!)
              .firstWhere((object) => object.name == 'farm');
          final signs = walk(world.holeGroup('tee')!)
              .where((object) => object.name == 'tee-sign')
              .toList();
          final sign = signs.isEmpty ? null : signs.single;
          final face = sign?.children
              .where((object) => object.name == 'tee-sign-face')
              .firstOrNull;
          built.add(_BuiltHole(
            course: course.id,
            hole: hole,
            number: '${i + 1}',
            props: (farm.userData['props'] as List)
                .cast<(String, Vec2, double)>()
                .toList(),
            signAt:
                sign == null ? null : Vec2(sign.position.x, sign.position.z),
            signNumber: sign?.userData['number'],
            signPainted: face?.material?.map != null,
          ));
          world.dispose();
        }
      }
    });

    const expected = {
      'the_coop': {'sunflower': 10, 'trough': 1, 'feed sacks': 1},
      'the_corn_maze': {'pumpkin': 8, 'corn crib': 1},
      'the_pond': {'rowboat': 1, 'lily pad': 6},
      'the_farm_road': {
        'egg crossing sign': 1,
        'chevron sign': 1,
        'milk stand': 1,
      },
      'the_barn': {'lantern post': 2, 'hay wagon': 1},
    };

    test('every course stands its own props, and none of another course', () {
      expect(built, hasLength(30));
      for (final entry in built) {
        final wanted = expected[entry.course]!;
        for (final MapEntry(key: name, value: least) in wanted.entries) {
          expect(entry.props.where((prop) => prop.$1 == name).length,
              greaterThanOrEqualTo(least),
              reason: '${entry.hole.id}: $name');
        }
        final others = {
          for (final other in expected.entries)
            if (other.key != entry.course) ...other.value.keys,
        };
        expect(entry.props.where((prop) => others.contains(prop.$1)), isEmpty,
            reason: entry.hole.id);
      }
    });

    test('the props stand off the table, never on the camera side', () {
      for (final entry in built) {
        final bounds = entry.hole.bounds;
        for (final (name, at, radius) in entry.props) {
          expect(at.y + radius, lessThanOrEqualTo(bounds.max.y + 1e-9),
              reason: '${entry.hole.id}: the $name on the camera side');
          final dx =
              math.max(math.max(bounds.min.x - at.x, at.x - bounds.max.x), 0.0);
          final dz =
              math.max(math.max(bounds.min.y - at.y, at.y - bounds.max.y), 0.0);
          expect(math.sqrt(dx * dx + dz * dz), greaterThan(radius + 1),
              reason: '${entry.hole.id}: the $name on the table');
        }
      }
    });

    test("every hole's tee sign shows that hole's number", () {
      // A tee with no spot off the table within a stroll has none (a sign
      // across the table reads as nobody's): a hole or two at most.
      expect(built.where((entry) => entry.signAt == null).length,
          lessThanOrEqualTo(2));
      for (final entry in built) {
        if (entry.signAt == null) continue;
        expect(entry.signNumber, entry.number, reason: entry.hole.id);
        expect(entry.signPainted, isTrue,
            reason: '${entry.hole.id}: the number is painted');
      }
    });

    test("the sign stands beside the tee, off the egg's path", () {
      for (final entry in built) {
        final hole = entry.hole;
        final at = entry.signAt;
        if (at == null) continue;
        expect(at.distanceTo(hole.tee), lessThan(15),
            reason: '${hole.id}: beside the tee');
        expect(at.y, lessThan(hole.bounds.max.y),
            reason: '${hole.id}: on the camera side');
        // Not where the close camera at the tee looks from.
        final yaw = PuttCameraRig.yawToward(hole.tee, hole.nest.position);
        final toCamera = Vec2(-math.sin(yaw), -math.cos(yaw));
        expect((at - hole.tee).normalized().dot(toCamera), lessThan(0.35),
            reason: '${hole.id}: between the camera and the egg');
        // Off the table: out past the border, or past a rail.
        expect(!hole.bounds.contains(at) || crossesRail(hole, hole.tee, at),
            isTrue,
            reason: '${hole.id}: on the green at $at');
      }
    });

    test("the Barn's bulbs glow by their own light, no lamp added", () {
      final hole = sunnySidePuttCourses
          .firstWhere((course) => course.id == 'the_barn')
          .holes
          .first
          .hole;
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      world.buildHole(hole, eggRadius: 0.45);
      final scenery = world.holeGroup('scenery')!;
      final bulbs = walk(scenery)
          .firstWhere((object) => object.name == 'festoon-bulbs') as tjs.Mesh;
      final material = bulbs.material as tjs.MeshStandardMaterial;
      expect(material.emissiveIntensity, greaterThan(1));
      expect(bulbs.castShadow, isFalse);
      expect(walk(scenery).where((object) => object.name == 'festoon-glow'),
          hasLength(1));
      // The corners' four lanterns light the yard, as before.
      expect(walk(scenery).whereType<tjs.PointLight>(), hasLength(4));
    });

    test('no number, no sign', () {
      final world = builtWorld();
      addTearDown(world.dispose);
      expect(
          walk(world.holeGroup('tee')!)
              .where((object) => object.name == 'tee-sign'),
          isEmpty);
    });

    test("the sign's paint goes with the hole", () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      world.buildHole(dressing, eggRadius: 0.45, label: '7');
      final face = walk(world.holeGroup('tee')!)
          .firstWhere((object) => object.name == 'tee-sign-face');
      var disposed = false;
      face.material!.map!.addEventListener('dispose', (tjs.Event event) {
        disposed = true;
      });
      world.dispose();
      expect(disposed, isTrue);
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

/// One catalog hole as the world built it: the props its farm stood and
/// the sign beside its tee.
class _BuiltHole {
  const _BuiltHole({
    required this.course,
    required this.hole,
    required this.number,
    required this.props,
    required this.signAt,
    required this.signNumber,
    required this.signPainted,
  });

  final String course;
  final HoleDef hole;

  /// The number the hole was built with (its place in the course).
  final String number;
  final List<(String, Vec2, double)> props;
  final Vec2? signAt;
  final Object? signNumber;
  final bool signPainted;
}

/// Whether the straight run from [from] to [to] crosses one of [hole]'s
/// rails (straight or arced).
bool crossesRail(HoleDef hole, Vec2 from, Vec2 to) {
  double side(Vec2 a, Vec2 b, Vec2 p) => (b - a).cross(p - a);
  bool crosses(Vec2 a, Vec2 b) =>
      (side(a, b, from) > 0) != (side(a, b, to) > 0) &&
      (side(from, to, a) > 0) != (side(from, to, b) > 0);
  for (final wall in hole.walls) {
    if (crosses(wall.a, wall.b)) return true;
  }
  for (final arc in hole.arcs) {
    Vec2 at(double t) {
      final angle = arc.startAngle + arc.sweep * t;
      return arc.center + Vec2(math.cos(angle), math.sin(angle)) * arc.radius;
    }

    for (var k = 0; k < 24; k++) {
      if (crosses(at(k / 24), at((k + 1) / 24))) return true;
    }
  }
  return false;
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
