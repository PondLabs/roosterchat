// The camera's choreography: the whole hole while it opens, the egg and the
// nest framed together at rest, the egg followed while it rolls, the rest
// of the field framed once the egg is in, the whole green between holes -
// and a player who takes the camera keeps the zoom they chose.
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_camera_director.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

HoleDef _hole() => HoleDef(
      id: 'camera-check',
      par: 3,
      tee: const Vec2(4, 12),
      nest: Nest(const Vec2(42, 12), 1.7),
      bounds: Rect(Vec2.zero, Vec2(48, 26)),
    );

void main() {
  late PuttCameraRig rig;
  late PuttCameraDirector director;
  final hole = _hole();

  setUp(() {
    rig = PuttCameraRig(viewport: const ui.Size(1280, 800));
    rig.fitToHole(hole.bounds);
    director = PuttCameraDirector(rig);
  });

  /// Runs [seconds] of frames with [cue], easing the rig like the world
  /// does.
  void run(double seconds, PuttCameraCue cue) {
    const dt = 1 / 60;
    for (var t = 0.0; t < seconds; t += dt) {
      director.update(dt, cue);
      rig.update(dt, followPoint: director.followPoint);
    }
  }

  PuttCameraCue resting(Vec2 egg) => PuttCameraCue(
      hole: hole, phase: PuttPhase.holePlay, myEgg: egg, myEggResting: true);

  test('the hole opens with a sweep from over the nest to the whole green', () {
    director.update(1 / 60, resting(hole.tee));
    // The entrance starts high and turned, over the nest.
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchMax, 1));
    expect(rig.target.distanceTo(hole.nest.position), lessThan(1));
    run(PuttCameraDirector.openingSeconds - 0.2, resting(hole.tee));
    expect(director.followPoint, hole.bounds.center);
    expect(rig.target.distanceTo(hole.bounds.center), lessThan(0.5));
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchDefault, 0.5));
    expect(rig.yaw, closeTo(PuttCameraRig.defaultYaw, 0.02));
    expect(rig.distance, closeTo(rig.overviewDistance, 1.5));
  });

  test('at rest, the egg and the nest are framed together', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    final middle = hole.tee.lerp(hole.nest.position, 0.5);
    expect(rig.target.distanceTo(middle), lessThan(0.5));
    expect(rig.distance, lessThanOrEqualTo(rig.overviewDistance + 1e-6));
    expect(rig.distance, greaterThan(rig.overviewDistance * 0.42 - 1e-6));
  });

  test('a short putt left frames closer than the whole hole', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(const Vec2(38, 12)));
    expect(rig.distance, lessThan(rig.overviewDistance * 0.8));
  });

  test('rolling, the camera rides with the egg', () {
    run(PuttCameraDirector.openingSeconds + 1, resting(hole.tee));
    const rolling = Vec2(20, 14);
    director.update(
      1 / 60,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: rolling,
        myEggResting: false,
      ),
    );
    expect(director.followPoint, rolling);
  });

  test('a player who zoomed keeps their zoom at the next rest', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    rig.setDistance(rig.overviewDistance * 0.9);
    director.noteUserCamera();
    // A roll, then a new rest.
    run(
      0.5,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: const Vec2(20, 12),
        myEggResting: false,
      ),
    );
    final zoom = rig.distanceTarget;
    run(2, resting(const Vec2(30, 12)));
    expect(rig.distanceTarget, closeTo(zoom, 1e-6));
  });

  test('once in the nest, the eggs still out are framed with the nest', () {
    run(PuttCameraDirector.openingSeconds + 1, resting(hole.tee));
    run(
      3,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: hole.nest.position,
        myEggHoled: true,
        otherEggs: const [Vec2(10, 20)],
      ),
    );
    final middle = const Vec2(10, 20).lerp(hole.nest.position, 0.5);
    expect(rig.target.distanceTo(middle), lessThan(1.5));
  });

  test('between holes the whole green shows again', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(const Vec2(38, 12)));
    run(3, PuttCameraCue(hole: hole, phase: PuttPhase.holeScoreboard));
    expect(director.followPoint, hole.bounds.center);
    expect(rig.distance, closeTo(rig.overviewDistance, 0.5));
  });
}
