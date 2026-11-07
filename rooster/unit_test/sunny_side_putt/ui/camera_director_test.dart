// The camera's choreography: the whole hole while it opens, then one
// framing for the whole hole - the egg dead centre of the frame, as Putt
// Party has it - held while the camera only pans with the egg. No zoom, no
// turn and no re-framing per shot; the frame holds dead still under a drag;
// the hatch's close-up and the whole-hole view still work.
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
  ui.Offset pixelOf(Vec2 point, [double height = 0]) {
    final camera = tjs.PerspectiveCamera(PuttCameraRig.fovDeg, 1280 / 800);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
    final ndc = tjs.Vector3(point.x, height, point.y).project(camera);
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

  test('the hole opens with a sweep from low beside it to its play framing',
      () {
    // The host stands beyond the far rail, by the nest.
    const host = Vec2(44, -6);
    PuttCameraCue opening() => PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: hole.tee,
        myEggResting: true,
        host: host);
    director.update(1 / 60, opening());
    // The entrance starts low and turned, looking across the green at the
    // farm and the sky - the whole table, its tee and the host in the frame.
    expect(rig.pitchDeg, closeTo(15, 1));
    expectInFreeView(hole.tee);
    expectInFreeView(host);
    for (final corner in [
      hole.bounds.min,
      hole.bounds.max,
      Vec2(hole.bounds.min.x, hole.bounds.max.y),
      Vec2(hole.bounds.max.x, hole.bounds.min.y),
    ]) {
      expectInFreeView(corner);
    }
    run(PuttCameraDirector.openingSeconds - 0.2, opening());
    // It lands exactly on the hole's play framing: the egg where the hole
    // keeps it, the zoom the hole's own. Nothing glides afterwards.
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchDefault, 0.5));
    expect(rig.yaw, closeTo(PuttCameraRig.defaultYaw, 0.02));
    expect(rig.distance, closeTo(director.playDistance, 0.5));
    expect(
        rig.target.distanceTo(hole.tee + director.playOffset), lessThan(0.5));
  });

  test('with reduced motion there is no sweep and no shake', () {
    director.reduceMotion = true;
    rig.reduceMotion = true;
    const egg = Vec2(24, 12);
    director.update(1 / 60, resting(egg));
    expect(rig.pitchDeg, closeTo(PuttCameraRig.pitchDefault, 0.5));
    expect(director.opening, isFalse);
    run(1.2, resting(egg));
    expect(director.settledFor, greaterThan(0));
    expectInFreeView(egg);
    final at = pixelOf(egg);
    expect(at.dx, closeTo(640, 2), reason: 'the egg is the middle: $at');
    expect(at.dy, closeTo(400, 2), reason: 'the egg is the middle: $at');
    final before = rig.distanceTarget;
    rig.punch();
    expect(rig.distanceTarget, before);
  });

  test('the egg is the middle of the frame, at a size to aim at', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    final egg = pixelOf(hole.tee);
    expect(egg.dx, closeTo(640, 2), reason: '$egg');
    expect(egg.dy, closeTo(400, 2), reason: '$egg');
    // Big enough to read as an egg, not a dot: the framing never zooms out
    // past this to keep the nest in view.
    final eggPixels = pixelOf(hole.tee).dy - pixelOf(hole.tee, 1.4).dy;
    expect(eggPixels, greaterThan(30), reason: '$eggPixels px tall');
    expect(rig.distance, lessThanOrEqualTo(rig.overviewDistance + 1e-6));
  });

  test('a short hole keeps the nest in the frame too', () {
    // The nest a dozen units off the tee: the egg's size leaves room for
    // it, so the hole is played with both in view.
    final short = HoleDef(
      id: 'camera-short',
      par: 2,
      tee: const Vec2(4, 12),
      nest: const Nest(Vec2(16, 12), 1.7),
      bounds: Rect(Vec2.zero, Vec2(24, 26)),
    );
    rig.fitToHole(short.bounds);
    final cue =
        PuttCameraCue(hole: short, phase: PuttPhase.holePlay, myEgg: short.tee);
    run(PuttCameraDirector.openingSeconds + 3, cue);
    expectInFreeView(short.tee);
    expectInFreeView(short.nest.position);
    final egg = pixelOf(short.tee);
    expect(egg.dx, closeTo(640, 2), reason: '$egg');
    expect(egg.dy, closeTo(400, 2), reason: '$egg');
  });

  test('a long hole lets the nest leave the view, the egg staying put', () {
    // The nest 38 units off the tee: keeping it in the frame would shrink
    // the egg to a dot, so it goes and the HUD's marker points at it.
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    final nest = pixelOf(hole.nest.position);
    expect(nest.dx, greaterThan(1280),
        reason: 'the nest is off the right edge: $nest');
    final egg = pixelOf(hole.tee);
    expect(egg.dx, closeTo(640, 2), reason: '$egg');
  });

  test("the nest's flag stands clear of the HUD when the nest is in view", () {
    final short = HoleDef(
      id: 'camera-short',
      par: 2,
      tee: const Vec2(4, 12),
      nest: const Nest(Vec2(16, 12), 1.7),
      bounds: Rect(Vec2.zero, Vec2(24, 26)),
    );
    rig.fitToHole(short.bounds);
    run(
      PuttCameraDirector.openingSeconds + 3,
      PuttCameraCue(hole: short, phase: PuttPhase.holePlay, myEgg: short.tee),
    );
    final nest = short.nest.position;
    expect(pixelOf(nest, PuttCameraDirector.nestFlagHeight).dy,
        greaterThanOrEqualTo(120),
        reason: 'under the top strip, the chip and the corner buttons');
    final eggPixels = pixelOf(short.tee).dy - pixelOf(short.tee, 1.1).dy;
    expect(eggPixels, greaterThan(20), reason: 'still an egg to aim at');
  });

  test(
      'the hole keeps one framing: the egg holds its place in the frame '
      'from the tee to the nest', () {
    run(PuttCameraDirector.openingSeconds + 2, resting(hole.tee));
    final atTee = pixelOf(hole.tee);
    final yaw = rig.yaw;
    final pitch = rig.pitchDeg;
    final distance = rig.distance;
    // Four putts, each a roll and a rest, walking up to the nest.
    var from = hole.tee;
    for (final to in const [
      Vec2(14, 12),
      Vec2(24, 12),
      Vec2(34, 12),
      Vec2(40, 12),
    ]) {
      for (var i = 1; i <= 8; i++) {
        run(
          0.1,
          PuttCameraCue(
            hole: hole,
            phase: PuttPhase.holePlay,
            myEgg: from.lerp(to, i / 8),
            myEggResting: false,
          ),
        );
      }
      from = to;
      run(2.5, resting(to));
      // The egg is where the hole's framing put it, to the pixel.
      final at = pixelOf(to);
      expect(at.dx, closeTo(atTee.dx, 1.5), reason: 'shot to $to');
      expect(at.dy, closeTo(atTee.dy, 1.5), reason: 'shot to $to');
      // And the camera never turned nor zoomed to get there.
      expect(rig.yaw, closeTo(yaw, 1e-6), reason: 'shot to $to');
      expect(rig.pitchDeg, closeTo(pitch, 1e-6), reason: 'shot to $to');
      expect(rig.distance, closeTo(distance, 1e-6), reason: 'shot to $to');
    }
  });

  test('a drag during the opening holds the sweep where it is', () {
    PuttCameraCue opening({bool aiming = false}) => PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: hole.tee,
        myEggResting: true,
        aiming: aiming);
    run(0.8, opening());
    final yaw = rig.yaw;
    final pitch = rig.pitchDeg;
    final distance = rig.distance;
    final target = rig.target;
    run(1.5, opening(aiming: true));
    expect(rig.yaw, closeTo(yaw, 1e-6));
    expect(rig.pitchDeg, closeTo(pitch, 1e-6));
    expect(rig.distance, closeTo(distance, 1e-6));
    expect(rig.target.distanceTo(target), lessThan(1e-6));
    // Let go and the sweep carries on from where it stopped.
    run(PuttCameraDirector.openingSeconds, opening());
    expect(rig.distance, closeTo(director.playDistance, 0.5));
    expect(rig.yaw, closeTo(PuttCameraRig.defaultYaw, 0.02));
  });

  test('a drag holds the frame dead still', () {
    run(PuttCameraDirector.openingSeconds + 2, resting(hole.tee));
    final target = rig.target;
    final distance = rig.distance;
    // The egg is nudged (a stray frame) while the aim is held: the camera
    // does not follow it out from under the pointer.
    run(
      1,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: const Vec2(9, 13),
        myEggResting: true,
        aiming: true,
      ),
    );
    expect(rig.target.distanceTo(target), lessThan(1e-6));
    expect(rig.distance, closeTo(distance, 1e-6));
  });

  test('rolling, the camera pans with the egg, never ahead of it', () {
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
    expect(director.followPoint, rolling + director.playOffset);
  });

  test('a player who zoomed keeps their zoom at the next rest', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    rig.setDistance(rig.overviewDistance * 0.9);
    director.noteUserCamera();
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

  test('the whole-hole view centres the green and zooms out', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    director.toggleOverview();
    run(2, resting(hole.tee));
    expect(director.overview, isTrue);
    expect(rig.target.distanceTo(hole.bounds.center), lessThan(0.5));
    expect(rig.distance, closeTo(rig.overviewDistance, 0.5));
    director.toggleOverview();
    run(2, resting(hole.tee));
    expect(rig.distance, closeTo(director.playDistance, 0.5));
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
    // Down low on the nest, the chick in its hat whole in the lower middle
    // of the frame: from its feet on the lip (0.5 up) to its hat mid-hop
    // (3.9 up: the viewer's chick is drawn a size up), under the score's
    // banner at the top (to 175 px) and over the HUD at the bottom (650 px).
    expect(rig.pitchDeg, closeTo(PuttCameraDirector.celebratePitch, 3));
    final nest = hole.nest.position;
    expect(pixelOf(nest, 3.9).dy, greaterThan(175), reason: 'its hat mid-hop');
    expect(pixelOf(nest, 0.5).dy, lessThan(650), reason: 'its feet on the lip');
    expect(pixelOf(nest, 0.5).dy - pixelOf(nest, 2.85).dy, greaterThan(200),
        reason: 'big on the screen, standing');
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
