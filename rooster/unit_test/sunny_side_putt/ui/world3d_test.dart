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
  }) {
    return PuttWorldEgg(
      playerId: playerId,
      position: at,
      velocity: velocity,
      tint: PuttPalette.tintForIndex(0),
      radius: radius,
      height: height,
    );
  }

  group('the hole builds a scene graph', () {
    test('one group per kind, with the right counts inside', () {
      final world = builtWorld();
      addTearDown(world.dispose);

      int countUnder(String kind) => world.holeGroup(kind)!.children.length;

      // The border (4) plus the crossing hedge.
      expect(countUnder('walls'), 5, reason: 'walls minus bumpers');
      // A 6-long bumper line steps posts at 1.7 spacing.
      expect(countUnder('bumpers'), 6.floor() - 1 + (0.5 * 2 / 1.7).ceil(),
          reason: 'the bumper wall line rides its posts');
      // Hedge run + full-circle rock (in 'arcs' too).
      expect(countUnder('arcs'), greaterThan(0));
      expect(world.holeGroup('wells')!.children, isNotEmpty);
      expect(countUnder('water'), 3);
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
      expect(body.material!.color.getHex(), _hexOf(PuttPalette.comb));
      expect(ring.material!.color.getHex(), _hexOf(PuttPalette.yolk));
      expect(body.castShadow, isTrue);
    });

    test('the hedge box stands at its wall, turned along the run', () {
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
      expect(runOf(hedge), closeTo(8.0, 1e-9));
      final body = hedge.children.first as tjs.Mesh;
      // Standing on the green: the box's centre off the ground.
      expect(body.position.y, greaterThan(0));
      // The border walls fill out the rest of the group.
      final lengths = walls.map(runOf).toList()..sort();
      expect(lengths, containsAllInOrder([8.0, 26.0, 40.0]));
    });

    test("the hole's parent tree hangs under the world's hole group", () {
      final world = builtWorld();
      addTearDown(world.dispose);
      for (final kind in [
        'ground',
        'walls',
        'bumpers',
        'arcs',
        'wells',
        'water',
        'portals',
        'boxes',
        'decorations',
        'hens',
      ]) {
        final group = world.holeGroup(kind);
        expect(group, isNotNull, reason: kind);
        expect(group!.parent!.name, 'hole', reason: kind);
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
      expect(east.x, greaterThan(0.1), reason: 'top tips toward +x');
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
      expect(upPointsIn(westWorld).x, lessThan(-0.1),
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
      expect(upPointsIn(northWorld).z, greaterThan(0.1),
          reason: 'top tips toward +z (game south)');
    });

    test("the roll's angle carries omega = |v| / r over the frame", () {
      final world = PuttWorld3D(viewport: const ui.Size(800, 600));
      addTearDown(world.dispose);
      const dt = 0.02;
      const velocity = Vec2(4, 0);
      const radius = 0.45;
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
      const stand = 0.45 * 1.28;

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
      world.rig
        ..orbitBy(0, -100000)
        ..snap();
      expect(world.rig.pitchDeg, PuttCameraRig.pitchMin);
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

/// three_js wants raw hex (no alpha byte); the tests compare through the
/// same read the world uses.
int _hexOf(ui.Color color) => color.toARGB32() & 0xFFFFFF;
