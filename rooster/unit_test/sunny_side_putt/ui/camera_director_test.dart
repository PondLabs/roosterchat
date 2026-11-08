// The camera's choreography: the whole hole while it opens, then one
// framing per hole with the egg dead centre that only ever pans with it (as
// Putt Party has it), the nest kept once the egg is in (never another
// player's egg), a spectator's field watched, the whole green between holes
// - and a player who takes the camera keeps the zoom they chose.
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

  /// Where a ground point (or something [height] up on it) lands on the
  /// 1280x800 screen through the rig.
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
    // Right behind the egg on the tee, looking down the line to the nest.
    expect(rig.yaw,
        closeTo(PuttCameraRig.yawToward(hole.tee, hole.nest.position), 0.02));
    expect(rig.distance, closeTo(director.playDistance, 0.5));
    expect(
        rig.target.distanceTo(hole.tee + director.playOffset), lessThan(0.5));
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
    final eggPixels =
        pixelOf(hole.tee).dy - pixelOf(hole.tee, director.eggHeight).dy;
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
    expect(nest.dy, lessThan(96),
        reason: 'the nest is past the top of the free view: $nest');
    expect(nest.dx, closeTo(640, 2), reason: 'straight ahead: $nest');
    final egg = pixelOf(hole.tee);
    expect(egg.dx, closeTo(640, 2), reason: '$egg');
  });

  test('the camera stands behind my egg, the nest straight ahead', () {
    // A hole that runs down the screen from the green's own view (south):
    // the camera turns round to look along it, as Putt Party's tee shot.
    final turned = HoleDef(
      id: 'camera-turned',
      par: 2,
      tee: const Vec2(12, 4),
      nest: const Nest(Vec2(12, 16), 1.7),
      bounds: Rect(Vec2.zero, Vec2(24, 26)),
    );
    rig.fitToHole(turned.bounds);
    run(
      PuttCameraDirector.openingSeconds + 3,
      PuttCameraCue(hole: turned, phase: PuttPhase.holePlay, myEgg: turned.tee),
    );
    final egg = pixelOf(turned.tee);
    final nest = pixelOf(turned.nest.position);
    expect(egg.dx, closeTo(640, 2), reason: '$egg');
    expect(egg.dy, closeTo(400, 2), reason: '$egg');
    expect(nest.dx, closeTo(640, 2), reason: 'straight ahead: $nest');
    expect(nest.dy, lessThan(egg.dy), reason: 'up the screen: $nest');
    expectInFreeView(turned.nest.position);
    final eggPixels =
        pixelOf(turned.tee).dy - pixelOf(turned.tee, director.eggHeight).dy;
    expect(eggPixels, greaterThan(30), reason: 'an egg to aim at');
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
    expect(rig.yaw, closeTo(director.playYaw, 0.02));
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

  test('a splash puts the camera back on the egg where it comes back', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    // A roll toward the pond...
    run(
      0.5,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: const Vec2(30, 20),
        myEggResting: false,
      ),
    );
    // ...in: the egg is put back on the tee and settles in the same tick,
    // and the first frame draws it part way back from the water.
    const pond = Vec2(30, 20);
    director.update(1 / 60, resting(pond.lerp(hole.tee, 0.1)));
    run(3, resting(hole.tee));
    expectInFreeView(hole.tee);
    expect(rig.target.distanceTo(hole.tee),
        lessThan(pond.distanceTo(hole.tee) / 2),
        reason: 'the camera is on the egg, not the pond');
  });

  test('my next putt hands the camera back from the whole-hole view', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(hole.tee));
    director.toggleOverview();
    run(1, resting(hole.tee));
    expect(director.overview, isTrue);
    const rolling = Vec2(10, 12);
    // Another egg knocks mine rolling: no putt of mine, the view stays.
    director.update(
      1 / 60,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: rolling,
        myEggResting: false,
      ),
    );
    expect(director.overview, isTrue, reason: 'a knock is not my putt');
    run(1, resting(hole.tee));
    director.update(
      1 / 60,
      PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        myEgg: rolling,
        myEggResting: false,
        myStrokes: 1,
      ),
    );
    expect(director.overview, isFalse);
    expect(director.followPoint, rolling + director.playOffset);
  });

  test('once in the nest, the camera stays on it, not on the others', () {
    run(PuttCameraDirector.openingSeconds + 1, resting(hole.tee));
    // Past the close-up on the nest that celebrates the sink, with another
    // player's egg rolling across the green the whole time.
    const theirs = Vec2(10, 20);
    PuttCameraCue holed(Vec2 at, {bool rolling = false}) => PuttCameraCue(
          hole: hole,
          phase: PuttPhase.holePlay,
          myEgg: hole.nest.position,
          myEggHoled: true,
          otherEggs: [
            PuttCameraEgg('them', at,
                velocity: rolling ? const Vec2(6, 0) : Vec2.zero,
                resting: !rolling,
                strokes: rolling ? 1 : 0),
          ],
        );
    run(PuttCameraDirector.celebrateSeconds + 3, holed(theirs));
    expect(director.watching, isNull,
        reason: 'my egg is in: the camera is still mine');
    expect(rig.target.distanceTo(hole.nest.position), lessThan(3));
    expectInFreeView(hole.nest.position);
    // Their putt rolls on: the camera does not go with it.
    for (var x = 10.0; x < 34; x += 0.5) {
      run(0.1, holed(Vec2(x, 20), rolling: true));
      expect(director.watching, isNull);
      expect(rig.target.distanceTo(hole.nest.position), lessThan(3),
          reason: 'the camera stayed on the nest while they rolled');
    }
    expectInFreeView(hole.nest.position);
  });

  test('my own egg dropping in brings the camera in on the nest', () {
    run(PuttCameraDirector.openingSeconds + 2, resting(const Vec2(38, 12)));
    final holed = PuttCameraCue(
      hole: hole,
      phase: PuttPhase.holePlay,
      myEgg: hole.nest.position,
      myEggHoled: true,
      otherEggs: const [PuttCameraEgg('them', Vec2(10, 20))],
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
    // After it, the frame of the nest is back within the clamp.
    expect(rig.distanceTarget, greaterThanOrEqualTo(rig.distanceMin));
    expectInFreeView(hole.nest.position);
  });

  test('the close-up plays even after the player took the camera', () {
    // The same sink, three ways the player may have left the camera: as
    // the director had it, zoomed with the wheel, or the whole-hole view.
    // Each one comes in on the chick, low and close.
    final nest = hole.nest.position;
    final holed = PuttCameraCue(
      hole: hole,
      phase: PuttPhase.holePlay,
      myEgg: nest,
      myEggHoled: true,
      otherEggs: const [PuttCameraEgg('them', Vec2(10, 20))],
    );
    for (final take in ['none', 'zoom', 'overview']) {
      rig = PuttCameraRig(viewport: const ui.Size(1280, 800));
      rig.fitToHole(hole.bounds);
      director = PuttCameraDirector(rig);
      run(PuttCameraDirector.openingSeconds + 2, resting(const Vec2(38, 12)));
      if (take == 'zoom') {
        rig.setDistance(rig.overviewDistance * 0.9);
        director.noteUserCamera();
      } else if (take == 'overview') {
        director.toggleOverview();
      }
      run(1, resting(const Vec2(38, 12)));
      run(1.2, holed);
      expect(director.celebrating, isTrue, reason: take);
      expect(rig.target.distanceTo(nest), lessThan(4.5), reason: take);
      expect(rig.pitchDeg, closeTo(PuttCameraDirector.celebratePitch, 3),
          reason: take);
      expect(pixelOf(nest, 0.5).dy - pixelOf(nest, 2.85).dy, greaterThan(200),
          reason: '$take: the chick big on the screen');
      // And after the hatch the nest is still what the camera looks at.
      run(PuttCameraDirector.celebrateSeconds + 1.5, holed);
      expect(director.overview, isFalse, reason: take);
      expect(rig.target.distanceTo(nest), lessThan(3), reason: take);
    }
  });

  test('a hole that ends on my sink keeps the camera on the nest', () {
    // Alone, or the last one in: the hole ends the tick my egg drops.
    run(PuttCameraDirector.openingSeconds + 2, resting(const Vec2(38, 12)));
    final nest = hole.nest.position;
    final over = PuttCameraCue(
      hole: hole,
      phase: PuttPhase.holeScoreboard,
      myEgg: nest,
      myEggHoled: true,
    );
    run(1.2, over);
    expect(director.celebrating, isTrue, reason: 'the hatch plays');
    expect(rig.target.distanceTo(nest), lessThan(4.5));
    // Through the hatch and the whole results card: the nest, never the
    // middle of the green.
    for (var t = 0.0; t < PuttCameraDirector.celebrateSeconds + 6; t += 0.25) {
      run(0.25, over);
      // (In close the camera looks a little past the nest, at the chick's
      // middle: about 4 units.)
      expect(rig.target.distanceTo(nest), lessThan(4.5),
          reason: 'at ${t.toStringAsFixed(2)} s');
    }
    expect(director.followPoint, nest);
    expectInFreeView(nest);
  });

  /// A spectator's view: no egg of mine, [others] still out.
  PuttCameraCue holedWith(List<PuttCameraEgg> others) => PuttCameraCue(
        hole: hole,
        phase: PuttPhase.holePlay,
        otherEggs: others,
      );

  /// Runs the opening out, then the spectator's view of [others].
  void holeMine(List<PuttCameraEgg> others) {
    run(PuttCameraDirector.openingSeconds + 1, resting(const Vec2(38, 12)));
    run(PuttCameraDirector.celebrateSeconds + 0.5, holedWith(others));
  }

  test('a spectator rides with the egg still rolling', () {
    holeMine(const [PuttCameraEgg('them', Vec2(4, 12))]);
    expect(director.watching, 'them');
    // They putt: the camera follows the egg frame by frame, no stale shot.
    for (var x = 4.0; x < 30; x += 0.4) {
      final at = Vec2(x, 12 + (x - 4) * 0.3);
      director.update(
          1 / 60,
          holedWith([
            PuttCameraEgg('them', at,
                velocity: const Vec2(24, 7), resting: false)
          ]));
      rig.update(1 / 60, followPoint: director.followPoint);
      expect(director.followPoint!.distanceTo(at), lessThanOrEqualTo(4 + 1e-9));
    }
    expect(rig.target.distanceTo(const Vec2(30, 20)), lessThan(8));
    expectInFreeView(const Vec2(30, 19.8));
  });

  test("a spectator's splash reframes the watched egg where it comes back", () {
    holeMine(const [PuttCameraEgg('them', Vec2(4, 12))]);
    const pond = Vec2(30, 20);
    run(
        0.5,
        holedWith(const [
          PuttCameraEgg('them', pond, velocity: Vec2(10, 3), resting: false)
        ]));
    // Put back on the tee and settled in one tick: the first frame draws it
    // part way back from the water.
    director.update(
        1 / 60, holedWith([PuttCameraEgg('them', pond.lerp(hole.tee, 0.1))]));
    run(3, holedWith([PuttCameraEgg('them', hole.tee)]));
    expectInFreeView(hole.tee);
    expectInFreeView(hole.nest.position);
    expect(rig.target.distanceTo(hole.tee), lessThan(pond.distanceTo(hole.tee)),
        reason: 'the camera came back from the pond');
    final settled = rig.target;
    run(1, holedWith([PuttCameraEgg('them', hole.tee)]));
    expect(rig.target.distanceTo(settled), lessThan(0.05),
        reason: 'a resting egg is framed once, not pumped');
  });

  test('a spectator keeps the watched egg until it drops in or rests', () {
    holeMine(const []);
    const a = Vec2(30, 12), b = Vec2(8, 20);
    PuttCameraEgg egg(String id, Vec2 at,
            {bool rolling = false, int strokes = 0}) =>
        PuttCameraEgg(id, at,
            velocity: rolling ? const Vec2(5, 0) : Vec2.zero,
            resting: !rolling,
            strokes: strokes);
    // Both roll: the nearer is watched, and kept while b rolls on.
    run(0.5,
        holedWith([egg('a', a, rolling: true), egg('b', b, rolling: true)]));
    expect(director.watching, 'a');
    run(0.5, holedWith([egg('a', a), egg('b', b, rolling: true)]));
    expect(director.watching, 'a', reason: 'no hopping to an egg mid-roll');
    run(0.5, holedWith([egg('a', a), egg('b', b)]));
    expect(director.watching, 'a');
    // b putts while a rests: the camera moves on to it.
    run(0.6, holedWith([egg('a', a), egg('b', b, rolling: true, strokes: 1)]));
    expect(director.watching, 'b');
    run(0.5, holedWith([egg('a', a), egg('b', b, strokes: 1)]));
    // b drops in: back to a, the one still out.
    run(2, holedWith([egg('a', a)]));
    expect(director.watching, 'a');
    expectInFreeView(a);
    expectInFreeView(hole.nest.position);
    // Everyone in: the nest, until the scoreboard's whole green.
    run(2, holedWith(const []));
    expect(director.watching, isNull);
    expect(director.followPoint, hole.nest.position);
  });

  test('an egg a hen bumps never takes the camera; a putt waits a beat', () {
    holeMine(const []);
    const a = Vec2(30, 12), b = Vec2(8, 20);
    PuttCameraEgg egg(String id, Vec2 at,
            {bool rolling = false, int strokes = 0}) =>
        PuttCameraEgg(id, at,
            velocity: rolling ? const Vec2(2, 0) : Vec2.zero,
            resting: !rolling,
            strokes: strokes);
    run(1, holedWith([egg('a', a, rolling: true), egg('b', b)]));
    run(1, holedWith([egg('a', a), egg('b', b)]));
    expect(director.watching, 'a');
    // A hen nudges b again and again: no putt, the camera stays on a.
    for (var i = 0; i < 6; i++) {
      run(0.2, holedWith([egg('a', a), egg('b', b, rolling: true)]));
      run(0.2, holedWith([egg('a', a), egg('b', b)]));
      expect(director.watching, 'a');
    }
    // b putts: the camera moves on, and stays on b for a beat even when a
    // putts right after.
    run(0.1, holedWith([egg('a', a), egg('b', b, rolling: true, strokes: 1)]));
    expect(director.watching, 'b');
    run(0.5, holedWith([egg('a', a), egg('b', b, strokes: 1)]));
    run(
        0.5,
        holedWith([
          egg('a', a, rolling: true, strokes: 1),
          egg('b', b, strokes: 1),
        ]));
    expect(director.watching, 'b', reason: 'within the dwell');
    run(
        0.6,
        holedWith([
          egg('a', a, rolling: true, strokes: 1),
          egg('b', b, strokes: 1),
        ]));
    expect(director.watching, 'a', reason: 'past the dwell, still putting');
  });

  test('a spectator who zoomed keeps their zoom', () {
    holeMine(const [PuttCameraEgg('them', Vec2(4, 12))]);
    rig.setDistance(rig.overviewDistance * 0.9);
    director.noteUserCamera();
    final zoom = rig.distanceTarget;
    run(
        0.5,
        holedWith(const [
          PuttCameraEgg('them', Vec2(20, 12),
              velocity: Vec2(10, 0), resting: false)
        ]));
    run(2, holedWith(const [PuttCameraEgg('them', Vec2(30, 12))]));
    expect(rig.distanceTarget, closeTo(zoom, 1e-6));
    expect(rig.target.distanceTo(const Vec2(30, 12)), lessThan(12));
  });

  test('between holes the whole green shows again (my egg not in)', () {
    run(PuttCameraDirector.openingSeconds + 3, resting(const Vec2(38, 12)));
    run(3, PuttCameraCue(hole: hole, phase: PuttPhase.holeScoreboard));
    expect(director.followPoint, hole.bounds.center);
    expect(rig.distance, closeTo(rig.overviewDistance, 0.5));
  });
}
