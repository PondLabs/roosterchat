// The camera's choreography: the whole hole while it opens, the egg and the
// nest framed together at rest, the egg followed while it rolls, the rest
// of the field framed once the egg is in, the whole green between holes -
// and a player who takes the camera keeps the zoom they chose.
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:three_js_math/three_js_math.dart' as tjs;
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

  /// Where a ground point lands on the 1280x800 screen through the rig.
  ui.Offset pixelOf(Vec2 point) {
    final camera = tjs.PerspectiveCamera(PuttCameraRig.fovDeg, 1280 / 800);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
    final ndc = tjs.Vector3(point.x, 0, point.y).project(camera);
    return ui.Offset((ndc.x + 1) / 2 * 1280, (1 - ndc.y) / 2 * 800);
  }

  /// Whether a ground point shows in the part of the screen the HUD's
  /// bars leave free.
  void expectInFreeView(Vec2 point) {
    final pixel = pixelOf(point);
    expect(pixel.dx, inInclusiveRange(20, 1260), reason: '$point at $pixel');
    expect(pixel.dy, inInclusiveRange(96, 800 - 150),
        reason: '$point at $pixel');
  }

  test('the hole opens with a sweep from over the nest to the whole green', () {
    director.update(1 / 60, resting(hole.tee));
    // The entrance starts low and turned, looking across the nest at the
    // farm and the sky.
    expect(rig.pitchDeg, closeTo(15, 1));
    expect(rig.target.distanceTo(hole.nest.position), lessThan(1));
    run(PuttCameraDirector.openingSeconds - 0.2, resting(hole.tee));
    expect(rig.target.distanceTo(hole.bounds.center), lessThan(0.5));
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchDefault, 0.5));
    expect(rig.yaw, closeTo(PuttCameraRig.defaultYaw, 0.02));
    expect(rig.distance, closeTo(rig.overviewDistance, 1.5));
  });

  test('with reduced motion there is no sweep and no shake', () {
    director.reduceMotion = true;
    rig.reduceMotion = true;
    // An egg near enough the nest to frame both at an aimable size.
    const egg = Vec2(24, 12);
    director.update(1 / 60, resting(egg));
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchDefault, 0.5));
    expect(director.opening, isFalse);
    run(1.2, resting(egg));
    expect(director.settledFor, greaterThan(0));
    expectInFreeView(egg);
    expectInFreeView(hole.nest.position);
    final before = rig.distanceTarget;
    rig.punch();
    expect(rig.distanceTarget, before);
  });

  test('at rest, the egg and the nest are framed together', () {
    const egg = Vec2(24, 12);
    run(PuttCameraDirector.openingSeconds + 3, resting(egg));
    expectInFreeView(egg);
    expectInFreeView(hole.nest.position);
    expect(rig.distance, lessThanOrEqualTo(rig.overviewDistance + 1e-6));
  });

  test("at rest, the nest's flag stands clear of the HUD, the egg aimable", () {
    const egg = Vec2(24, 12);
    run(PuttCameraDirector.openingSeconds + 3, resting(egg));
    final camera = tjs.PerspectiveCamera(PuttCameraRig.fovDeg, 1280 / 800);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
    double pixelY(Vec2 at, double height) =>
        (1 - tjs.Vector3(at.x, height, at.y).project(camera).y) / 2 * 800;
    final nest = hole.nest.position;
    expect(pixelY(nest, PuttCameraDirector.nestFlagHeight),
        greaterThanOrEqualTo(120),
        reason: 'under the top strip, the chip and the corner buttons');
    final eggPixels = pixelY(egg, 0) - pixelY(egg, director.eggHeight);
    expect(eggPixels, greaterThan(PuttCameraDirector.aimEggPixels * 0.85),
        reason: 'still an egg to aim at');
  });

  test('a nest too far to frame with an aimable egg gives way to the egg', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    // The egg in view, low, and the stretch toward the nest above it; the
    // nest itself is the HUD's to point at.
    expectInFreeView(hole.tee);
    expect(pixelOf(hole.tee).dy, greaterThan(400));
    expect(
        rig.distance,
        lessThanOrEqualTo(
            rig.distanceForHeight(director.eggHeight, 30) + 1e-6));
  });

  test('on a long hole the resting egg stays big enough to aim at', () {
    // A nest 80 units away: framing it with the egg would shrink the egg
    // to a speck, so the camera frames the egg and the way toward the
    // nest instead.
    final long = HoleDef(
      id: 'camera-long',
      par: 4,
      tee: const Vec2(6, 15),
      nest: Nest(const Vec2(86, 15), 1.7),
      bounds: Rect(Vec2.zero, Vec2(92, 30)),
    );
    rig.fitToHole(long.bounds);
    director = PuttCameraDirector(rig);
    final cue = PuttCameraCue(
        hole: long,
        phase: PuttPhase.holePlay,
        myEgg: long.tee,
        myEggResting: true);
    run(PuttCameraDirector.openingSeconds + 3, cue);
    expectInFreeView(long.tee);
    final camera = tjs.PerspectiveCamera(PuttCameraRig.fovDeg, 1280 / 800);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
    double pixelY(double height) =>
        (1 - tjs.Vector3(long.tee.x, height, long.tee.y).project(camera).y) /
        2 *
        800;
    final eggPixels = pixelY(0) - pixelY(director.eggHeight);
    expect(
        eggPixels, greaterThanOrEqualTo(PuttCameraDirector.aimEggPixels * 0.9));
    expect(rig.distance, lessThan(rig.overviewDistance * 0.8));
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

  test('rolling fast, the camera looks ahead of the egg', () {
    run(PuttCameraDirector.openingSeconds + 1, resting(hole.tee));
    const rolling = Vec2(20, 14);
    director.update(
      1 / 60,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: rolling,
        myEggResting: false,
        myEggVelocity: const Vec2(20, 0),
      ),
    );
    final follow = director.followPoint!;
    expect(follow.x, greaterThan(rolling.x + 3));
    expect(follow.distanceTo(rolling), lessThanOrEqualTo(4 + 1e-9));
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
    // Past the close-up on the nest that celebrates the sink.
    run(
      PuttCameraDirector.celebrateSeconds + 3,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: hole.nest.position,
        myEggHoled: true,
        otherEggs: const [Vec2(10, 20)],
      ),
    );
    expectInFreeView(const Vec2(10, 20));
    expectInFreeView(hole.nest.position);
  });

  test('my own egg dropping in brings the camera in on the nest', () {
    run(PuttCameraDirector.openingSeconds + 2, resting(const Vec2(38, 12)));
    final holed = PuttCameraCue(
      hole: hole,
      phase: PuttPhase.holePlay,
      myEgg: hole.nest.position,
      myEggHoled: true,
      otherEggs: const [Vec2(10, 20)],
    );
    run(1.2, holed);
    // Down low and close on the nest (the chick in its hat in the middle of
    // the frame), nearer than the hole's own zoom clamp lets a player come.
    expect(rig.target.distanceTo(hole.nest.position), lessThan(0.5));
    expect(rig.distanceTarget,
        closeTo(PuttCameraDirector.celebrateDistance, 1e-6));
    expect(rig.distanceTarget, lessThan(rig.distanceMin));
    expect(rig.pitchDeg, closeTo(PuttCameraDirector.celebratePitch, 3));
    run(PuttCameraDirector.celebrateSeconds + 1.5, holed);
    // After it, the frame of the eggs still out is back within the clamp.
    expect(rig.distanceTarget, greaterThanOrEqualTo(rig.distanceMin));
    expectInFreeView(const Vec2(10, 20));
    expectInFreeView(hole.nest.position);
  });

  test('between holes the whole green shows again', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(const Vec2(38, 12)));
    run(3, PuttCameraCue(hole: hole, phase: PuttPhase.holeScoreboard));
    expect(director.followPoint, hole.bounds.center);
    expect(rig.distance, closeTo(rig.overviewDistance, 0.5));
  });
}
