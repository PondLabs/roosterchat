// The real-3D world of Sunny Side Putt, on the `three_js` engine: a sunny
// farm diorama. The hole is a minigolf green on a raised wooden table in a
// meadow - mown turf, timber rails, a straw nest with its flag - under a
// sky dome, with trees, a barn, a turning windmill, flowers and drifting
// clouds around it, all lit by a warm sun with soft shadows.
//
// What lives here (the parts under `world3d/` carry the builders):
//   * [PuttWorld3D] - the scene graph, built headlessly from a
//     [`HoleDef`](../core/hole.dart): the course (`world3d/course.dart`:
//     turf, table, rails, bumpers, rocks, water, boosts, rabbit holes, the
//     silo, crates, the nest, the tee, the hen's coop decorations; the
//     kickers in `world3d/kicker.dart`), the scenery around it
//     (`world3d/scenery.dart`) and the actors (`world3d/actors.dart`:
//     eggs, hens; the birds' legs and feathers come from
//     `world3d/birds.dart`). Every frame, [PuttWorld3D.applySnapshot]
//     moves the meshes to the engine's truth (positions, roll quaternions,
//     the hop's lift, a flight's altitude, the collected crates),
//     breathes the time-driven bits (water, flag, windmill, crates,
//     portals, clouds), and eases the camera rig toward its follow point.
//     No physics and no engine state here: the world consumes a
//     [PuttWorldFrame], so its tests run on plain frames with no GPU.
//   * [PuttCameraRig] - the orbit camera (yaw free, pitch clamped, wheel and
//     pinch zoom) fitted to a hole, eased one frame at a time, with the
//     world<->screen ray the aim's pointer plumbing walks.
//   * [PuttThreeSurface] - the GPU glue: the `three_js` renderer's widget
//     ([ThreeJS]) bound to this world, sized to the space the game is given
//     (not the window), its render hook driving the snapshot. The surface
//     consults [PuttThreeSurface.gpuSupported] before starting anything:
//     the Flutter test runner has no GPU surface and no native plugins, so
//     tests boot the game and its HUD with the renderer never coming up.
//
// Colour: the renderer works in linear light and writes sRGB, so every
// colour written as a designer's hex goes through [_lin] first (three_js
// takes hex values as linear, which washes them out). The lights are tuned
// for the engine's legacy light units (intensities scaled by pi).
//
// On web the renderer needs a WebGL2 context helper: `gles_bindings.js`,
// vendored (no CDN) in `rooster/web/` and loaded by a `<script>` in
// `rooster/web/index.html` - the package's own requirement.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart'
    show
        BoxConstraints,
        BuildContext,
        ColoredBox,
        LayoutBuilder,
        SingleTickerProviderStateMixin,
        SizedBox,
        State,
        StatefulWidget,
        VoidCallback,
        Widget;
import 'package:flutter_angle/flutter_angle.dart' show AngleOptions;
import 'package:three_js_angle_renderer/three_js_angle_renderer.dart' as tjr;
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:three_js_geometry/three_js_geometry.dart' as tjg;
import 'package:three_js_math/three_js_math.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/look.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'flutter_env_io.dart'
    if (dart.library.js_interop) 'flutter_env_stub.dart' as flutter_env;
import 'putt_art.dart';
import 'putt_powerup_icons.dart' show paintPuttPowerUpIcon;

part 'world3d/kit.dart';
part 'world3d/course.dart';
part 'world3d/scenery.dart';
part 'world3d/plants.dart';
part 'world3d/actors.dart';
part 'world3d/birds.dart';
part 'world3d/aim_fx.dart';
part 'world3d/theme.dart';
part 'world3d/bursts.dart';
part 'world3d/hatch.dart';
part 'world3d/table_shape.dart';
part 'world3d/casts.dart';
part 'world3d/kicker.dart';

/// The void behind everything before the sky dome draws: the horizon's
/// warm haze, so a frame that misses the dome still reads as sky.
const int _clearHex = 0xF6E3C4;

// ---- the frame: what one rendered moment feeds the world ---------------------

/// One egg on the green, as the world needs it. The game builds these from
/// the engine's interpolated truth every rendered frame.
class PuttWorldEgg {
  final String playerId;
  final Vec2 position;

  /// Height above the green, 0 unless a hop is lifting the egg.
  final double height;

  /// While the egg flies off a kicker: the altitude of its lowest point
  /// over the green's base level (the engine's own, see `BallBody.air`),
  /// which the drawing stands it at; null while it rolls.
  final double? air;

  /// The egg's velocity, which hands the roll its axis.
  final Vec2 velocity;
  final ui.Color tint;

  /// The player's look: the band painted on the shell, the hat the chick
  /// wears when this egg hatches.
  final PuttLook look;
  final double radius;

  /// The viewer's own egg: it wears the marker ring on the turf.
  final bool mine;

  /// A Thick Shell holds round this egg: a bubble wraps it until a cast
  /// pops it.
  final bool shielded;

  /// Seconds of Ghost Egg left on this egg (0: solid): the shell goes
  /// see-through and flickers, faster as it runs out.
  final double ghostSeconds;

  /// A Nest Magnet waits on this egg's next shot or pulls it now: the nest
  /// shimmers in its colour.
  final bool magnet;

  /// Another player's egg that has not putted on this hole: a ghost to the
  /// others (they pass through it), so it is drawn as one - see-through,
  /// a dashed ink ring at its foot.
  final bool waiting;

  const PuttWorldEgg({
    required this.playerId,
    required this.position,
    required this.velocity,
    required this.tint,
    required this.radius,
    this.look = PuttLook.standard,
    this.height = 0,
    this.air,
    this.mine = false,
    this.shielded = false,
    this.ghostSeconds = 0,
    this.magnet = false,
    this.waiting = false,
  });

  double get speed => velocity.length;
}

/// The hen (or any moving obstacle) at a moment of its walk.
class PuttWorldHen {
  final Vec2 position;
  final double radius;

  /// The waddle clock (ticks plus alpha), for the bob.
  final double phase;

  /// Where she heads this frame; the mesh faces the last non-stop
  /// direction she had.
  final Vec2 heading;

  const PuttWorldHen({
    required this.position,
    required this.radius,
    required this.phase,
    required this.heading,
  });
}

/// The aim while a stroke is being dragged: the drawn angle arrives with
/// the visual wobble already added (the game does that per frame); the
/// pure angle never left `aim_controller.dart`.
class PuttWorldAim {
  final Vec2 origin;
  final double angle;
  final double power;
  final double dragLength;
  final double eggRadius;

  /// The first stretch of the egg's predicted roll (the engine's own
  /// physics, run ahead): drawn as the dotted guide. Empty draws none.
  final List<Vec2> preview;

  /// Where the egg comes to rest, when it stops inside the guide (a soft
  /// putt): marked on the turf, and the arrow ends there.
  final Vec2? rest;

  /// Beside [preview], point for point: the egg's altitude where it flies
  /// off a kicker (as [PuttWorldEgg.air]), null where it rolls. Empty when
  /// the guide never leaves the ground.
  final List<double?> previewAir;

  /// Where a flight in the guide comes down: the guide ends there, the
  /// spot marked on the turf.
  final Vec2? landing;

  /// The viewer's last roll on this hole, the stretches between jumps (a
  /// splash's return, a rabbit hole): drawn faint under the aim, in
  /// [traceTint], so the next putt can be judged against the last one.
  final List<List<Vec2>> trace;
  final ui.Color? traceTint;

  const PuttWorldAim({
    required this.origin,
    required this.angle,
    required this.power,
    required this.dragLength,
    required this.eggRadius,
    this.preview = const [],
    this.rest,
    this.previewAir = const [],
    this.landing,
    this.trace = const [],
    this.traceTint,
  });
}

/// One particle of the bursts. The power-ups' scenes add their own:
/// corn kernels that fall and bounce, wind streaks that run along the
/// green toward their [PuttWorldFx.toward], steam rising off a strong
/// coffee, a swap's swirl, a popped shell's shards, a hop's feathers, the
/// glints of a hawk's straight line.
enum PuttWorldFxKind {
  droplet,
  sparkle,
  suction,
  poof,
  confetti,
  dust,
  ring,
  kernel,
  streak,
  steam,
  swirl,
  shard,
  feather,
  glint,
}

class PuttWorldFx {
  final PuttWorldFxKind kind;
  final Vec2 at;

  /// Where a suction particle flies home to; where a streak runs.
  final Vec2? toward;

  /// Age over life, 0..1.
  final double progress;
  final double size;
  final ui.Color? color;

  /// Height above the green, for particles that fly (confetti); null keeps
  /// the kind's own arc.
  final double? height;

  /// A ring's widest radius in world units, whatever the camera's distance
  /// (a splash's rings keep to the water); null lets it spread.
  final double? reach;

  const PuttWorldFx({
    required this.kind,
    required this.at,
    required this.progress,
    required this.size,
    this.toward,
    this.color,
    this.height,
    this.reach,
  });
}

/// A Thieving Crow on its way with its loot: from the robbed egg [from]
/// to the thief's [to], [progress] through the flight (0..1), carrying
/// [effectId]'s icon in its beak.
class PuttWorldCrow {
  final Vec2 from;
  final Vec2 to;
  final double progress;
  final String effectId;

  const PuttWorldCrow({
    required this.from,
    required this.to,
    required this.progress,
    required this.effectId,
  });
}

/// Everything one frame of the world knows. The hole stays out: the hole
/// is scene-graph work (built once), the frame only moves things.
class PuttWorldFrame {
  /// Seconds the game has been alive, for art that breathes.
  final double time;

  final List<PuttWorldEgg> eggs;
  final List<PuttWorldHen> hens;
  final PuttWorldAim? aim;
  final List<PuttWorldFx> fxs;

  /// The point (game coordinates) the camera's target glides toward, or
  /// null to hold where it is.
  final Vec2? followPoint;

  /// The "?" boxes already picked up this hole - read off the engine world
  /// every frame, so collected crates stand down and stay down through
  /// snapshots and mid-joins alike.
  final Set<String> collectedBoxes;

  /// The Thieving Crows in the air.
  final List<PuttWorldCrow> crows;

  /// The camera is in close on the nest for my egg's hatch: the hens step
  /// out of the shot.
  final bool closeUp;

  /// The camera's opening sweep of the hole is on: the host turns to the
  /// camera and looks at it.
  final bool opening;

  const PuttWorldFrame({
    required this.time,
    this.eggs = const [],
    this.hens = const [],
    this.aim,
    this.fxs = const [],
    this.followPoint,
    this.collectedBoxes = const {},
    this.crows = const [],
    this.closeUp = false,
    this.opening = false,
  });
}

// ---- the camera rig -----------------------------------------------------------

/// The orbit camera: state, easing, and how it lands on the three_js
/// camera. Gestures ([orbitBy], [zoomByWheel], [pinch]) write targets,
/// [update] eases the live state toward them, [fitToHole] frames a hole and
/// clamps the zoom range. The target point trails the player's egg when the
/// game asks, and recentres when the hole changes.
///
/// Pitch is in degrees clamped into [pitchMin, pitchMax], the camera hangs
/// behind the target (upwind of the away axis, which yaw turns), under a
/// 45-degree vertical field of view.
class PuttCameraRig {
  PuttCameraRig({this.viewport = const ui.Size(800, 600)});

  /// Scripted moves (the hole's opening sweep) may drop this low to show
  /// the horizon; the player's own orbit stops at [orbitPitchMin].
  static const double pitchMin = 14;
  static const double orbitPitchMin = 26;
  static const double pitchMax = 72;
  static const double pitchDefault = 42;

  /// Vertical fov in degrees.
  static const double fovDeg = 45;

  /// The pixels the rig projects into, logical (the same space pointer
  /// events report in). The game sets this on resize.
  ui.Size viewport;

  /// The orbit angle around the vertical, radians; unbounded, new drags
  /// add to it. Pi hangs the camera on the green's south (+z) side, so
  /// the hole reads the way it is drawn: x to the right, the game's y
  /// toward the player.
  double yaw = defaultYaw;

  static const double defaultYaw = math.pi;

  /// The orbit that turns the camera partway behind [from], looking down
  /// the line to [to]: half the turn from the hole's own view, never more
  /// than about 45 degrees, so the shot's direction reads while the hole
  /// keeps the orientation everyone shares. The close camera at the egg
  /// takes it; the tee's sign stands out of its way.
  static double yawToward(Vec2 from, Vec2 to) {
    final line = to - from;
    if (line.length < 1e-3) return defaultYaw;
    // The camera's away axis is (sin yaw, cos yaw) in x/z.
    final along = math.atan2(line.x, line.y);
    var turn = along - defaultYaw;
    turn = math.atan2(math.sin(turn), math.cos(turn)); // into (-pi, pi]
    return defaultYaw + (turn * 0.5).clamp(-0.8, 0.8);
  }

  /// The tilt from the ground plane, degrees, in [pitchMin, pitchMax].
  double pitchDeg = pitchDefault;

  /// The depth from the camera to the target along the look axis, in
  /// world units - the zoom handle.
  double distance = 30;

  /// The ground point under the middle of the screen (game coordinates).
  Vec2 target = Vec2.zero;

  double _yawTarget = defaultYaw;
  double _pitchTarget = pitchDefault;
  double _distanceTarget = 30;
  Vec2 _targetTarget = Vec2.zero;

  double _distanceMin = 8;
  double _distanceMax = 160;

  /// The distance that frames the whole hole, the overview's zoom.
  double _overviewDistance = 30;

  /// The first [fitToHole] snaps instead of easing: boot must not swoop.
  bool _snapNext = true;

  double get aspect => viewport.width <= 0 || viewport.height <= 0
      ? 1
      : viewport.width / viewport.height;

  void setViewport(ui.Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    viewport = size;
  }

  /// Frames [bounds]: distance so the green fits on screen (with the
  /// margin the standing props need), target at the green's centre, the
  /// zoom clamps off the hole's size. The first call snaps, later ones
  /// ease.
  void fitToHole(Rect bounds) {
    final c = math.cos(yaw).abs();
    final s = math.sin(yaw).abs();
    final pitchRad = pitchDeg * math.pi / 180;
    final sp = math.sin(pitchRad);
    final spanRight = bounds.width * c + bounds.height * s;
    final spanAway = bounds.width * s + bounds.height * c;
    final maxSpan = math.max(spanRight, spanAway);
    // The rails and the table's edge add a margin around the green; the
    // HUD's bars keep their strips at the top and the bottom free.
    const margin = 3.0;
    final usableWidth = math.max(1.0, viewport.width - 24);
    final usableHeight = math.max(1.0, viewport.height - 150);
    final focal = viewport.height * 1.2;
    final wanted = math.max(
      focal * (spanRight + margin) / usableWidth,
      focal * (spanAway * sp + margin + 1.5) / usableHeight,
    );
    _distanceMin = 0.3 * maxSpan;
    _distanceMax = 2.4 * maxSpan;
    _overviewDistance = wanted.clamp(_distanceMin, _distanceMax).toDouble();
    _distanceTarget = _overviewDistance;
    _targetTarget = bounds.center;
    if (_snapNext) snap();
  }

  /// The distance that frames the whole hole (the last fit's).
  double get overviewDistance => _overviewDistance;

  /// Glides to frame [a] and [b] together (the egg and the nest), or the
  /// box they span when [box]: the target and the distance that land every
  /// point inside the part of the screen the HUD leaves free (with room
  /// for an egg's tag and a flag), found by projecting the points through
  /// the camera the glide will end at. Never closer than [closest] of the
  /// overview's distance nor farther than the overview itself. [margin]
  /// (world units) widens the padding around the points.
  void glideToFrame(Vec2 a, Vec2 b,
      {double margin = 5,
      double closest = 0.42,
      double? yaw,
      bool box = false}) {
    glideToFramePoints(box ? [a, b, Vec2(a.x, b.y), Vec2(b.x, a.y)] : [a, b],
        margin: margin, closest: closest, yaw: yaw);
  }

  /// [glideToFrame] for any number of points (the eggs still out and the
  /// nest).
  /// [tall], beside the points, is how high something stands on each (the
  /// nest's flag): its top must clear the HUD's top band as well.
  void glideToFramePoints(List<Vec2> points,
      {double margin = 5,
      double closest = 0.42,
      double? yaw,
      List<double>? tall}) {
    if (points.isEmpty) return;
    _closeFloor = null;
    if (yaw != null) _yawTarget = yaw;
    final pad = 40 + margin * 6;
    final distance = _fitDistance(points, pad, closest, tall);
    _distanceTarget = distance;
    _targetTarget = _frameFits(points, distance, pad, tall).target;
  }

  /// The target and distance that land [points] inside the HUD-free part of
  /// the screen seen from [yaw] and [pitchDeg] - the nearest such distance
  /// up to [farthest] times the overview's - leaving the rig's own glide as
  /// it was (the opening's first pose, which the director drives itself).
  ({Vec2 target, double distance}) frameAt(List<Vec2> points,
      {required double yaw,
      required double pitchDeg,
      double margin = 2,
      double nearest = 0.5,
      double farthest = 1.6,
      List<double>? tall}) {
    final savedYaw = _yawTarget;
    final savedPitch = _pitchTarget;
    _yawTarget = yaw;
    _pitchTarget = pitchDeg.clamp(pitchMin, pitchMax);
    final pad = 40 + margin * 6;
    final distance = _nearestFitting(points, pad, _overviewDistance * nearest,
        _overviewDistance * farthest, tall);
    final target = _frameFits(points, distance, pad, tall).target;
    _yawTarget = savedYaw;
    _pitchTarget = savedPitch;
    return (target: target, distance: distance);
  }

  /// The distance [glideToFramePoints] would come to for [points] from
  /// [yaw] (the glide's own when left out), without moving the camera.
  double fitDistance(List<Vec2> points,
      {double margin = 5,
      double closest = 0.42,
      double? yaw,
      List<double>? tall}) {
    if (points.isEmpty) return _distanceTarget;
    final saved = _yawTarget;
    if (yaw != null) _yawTarget = yaw;
    final distance = _fitDistance(points, 40 + margin * 6, closest, tall);
    _yawTarget = saved;
    return distance;
  }

  /// The smallest distance (in range) whose centred frame fits.
  double _fitDistance(
      List<Vec2> points, double pad, double closest, List<double>? tall) {
    final low = math.max(_overviewDistance * closest, _distanceMin);
    final high = math.max(low, math.min(_overviewDistance, _distanceMax));
    return _nearestFitting(points, pad, low, high, tall);
  }

  /// The nearest distance in [low]..[high] from which [points] fit with
  /// every distance out to [high] fitting too, scanned in from [high]: up
  /// close the fit is not monotonic (a point near the lens throws the
  /// recentring off, and a pocket of false fits opens - with the host's
  /// height in the opening's frame, at half the distance it needs), so a
  /// bisection could land in one. [high] when even that does not fit.
  double _nearestFitting(List<Vec2> points, double pad, double low, double high,
      List<double>? tall) {
    if (high <= low || !_frameFits(points, high, pad, tall).fits) return high;
    const steps = 40;
    final step = (high - low) / steps;
    var good = high;
    var bad = low - 1;
    for (var i = 1; i <= steps; i++) {
      final d = high - step * i;
      if (!_frameFits(points, d, pad, tall).fits) {
        bad = d;
        break;
      }
      good = d;
    }
    if (bad < low) return good;
    // Between the last fit and the first miss, finer.
    var lo = bad, hi = good;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (_frameFits(points, mid, pad, tall).fits) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  /// The distance from which something standing [height] world units tall
  /// measures [pixels] in the middle of the screen, seen from the glide's
  /// pitch (looking down foreshortens it); infinite with no screen.
  double distanceForHeight(double height, double pixels) {
    if (viewport.height <= 0 || pixels <= 0) return double.infinity;
    final focal = viewport.height / 2 / math.tan(fovDeg * math.pi / 360);
    final upright = math.cos(_pitchTarget * math.pi / 180);
    return height * upright * focal / pixels;
  }

  /// The target that centres [points] in the HUD-free part of the screen
  /// from [distance] (at the glide's yaw and pitch), and whether they all
  /// fit there with [pad] pixels to spare.
  ({Vec2 target, bool fits}) _frameFits(
      List<Vec2> points, double distance, double pad,
      [List<double>? tall]) {
    final width = math.max(1.0, viewport.width);
    final height = math.max(1.0, viewport.height);
    final aspect = width / height;
    final t = math.tan(fovDeg * math.pi / 360);
    final pitch = _pitchTarget * math.pi / 180;
    final cp = math.max(math.cos(pitch), 0.15);
    final sp = math.sin(pitch);
    final away = Vec2(math.sin(_yawTarget), math.cos(_yawTarget));
    final right = Vec2(-away.y, away.x);
    // The free box in NDC: the HUD's bars at the top and the bottom.
    final left = -1 + 2 * pad / width;
    final rightEdge = 1 - 2 * pad / width;
    final top = 1 - 2 * (96 + pad) / height;
    final bottom = -1 + 2 * (150 + pad) / height;
    // The points' box on the screen from [target]: its extent, how far up
    // the tallest thing on them reaches (NDC), their mean depth, and
    // whether one stands behind the lens.
    ({
      double minX,
      double maxX,
      double minY,
      double maxY,
      double high,
      double depth,
      bool behind
    }) boxFrom(Vec2 target) {
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      var high = -double.infinity;
      var depth = 0.0;
      for (var i = 0; i < points.length; i++) {
        final d = points[i] - target;
        final f = d.dot(away);
        final zc = distance + f * cp;
        if (zc < 0.5) {
          return (
            minX: 0,
            maxX: 0,
            minY: 0,
            maxY: 0,
            high: 0,
            depth: 0,
            behind: true
          );
        }
        depth += zc;
        final x = d.dot(right) / (zc * t * aspect);
        final y = f * sp / (zc * t);
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        final lift = tall == null || i >= tall.length ? 0.0 : tall[i];
        high = math.max(high, y + lift * cp / (zc * t));
      }
      return (
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        high: high,
        depth: depth / points.length,
        behind: false
      );
    }

    // With tall things on the points (the nest's flag, the host), their
    // tops are what must clear the HUD's top band, by a small pad of their
    // own.
    final roof = tall == null ? top : 1 - 2 * (_hudTopFree + 36) / height;
    var target = Vec2.zero;
    for (final p in points) {
      target += p;
    }
    target = target / points.length.toDouble();
    // Move the target until the box sits in the middle of the free box,
    // in damped steps (screen offsets back to ground offsets, near enough;
    // low and from the side, a full step overshot and the frame swung back
    // and forth, never settling).
    for (var iteration = 0; iteration < 24; iteration++) {
      final box = boxFrom(target);
      if (box.behind) return (target: target, fits: false);
      final ex = (box.minX + box.maxX) / 2 - (left + rightEdge) / 2;
      final upper = tall == null ? box.maxY : math.max(box.maxY, box.high);
      final ey = (box.minY + upper) / 2 - (roof + bottom) / 2;
      if (ex.abs() < 1e-4 && ey.abs() < 1e-4) break;
      target += right * (ex * box.depth * t * aspect * 0.7) +
          away * (ey * box.depth * t / math.max(sp, 0.2) * 0.7);
    }
    // It fits when the box, where it settled, lies inside the free box.
    final box = boxFrom(target);
    if (box.behind) return (target: target, fits: false);
    const slack = 1e-3;
    final fits = box.minX >= left - slack &&
        box.maxX <= rightEdge + slack &&
        box.minY >= bottom - slack &&
        box.maxY <= top + slack &&
        (tall == null || box.high <= roof + slack);
    return (target: target, fits: fits);
  }

  /// How far down from the top the HUD reaches over the green, in pixels:
  /// the top strip, the course chip and the corner buttons.
  static const double _hudTopFree = 120;

  /// Orbit: [dxPixels] of horizontal drag turn the yaw, [dyPixels] tilt
  /// the pitch (clamped). Dragging down looks from higher above.
  void orbitBy(double dxPixels, double dyPixels) {
    _yawTarget += dxPixels * 0.006;
    _pitchTarget =
        (_pitchTarget + dyPixels * 0.11).clamp(orbitPitchMin, pitchMax);
  }

  /// Zoom by a mouse-wheel tick; positive scroll (down) moves out.
  void zoomByWheel(double delta) {
    _distanceTarget = (_distanceTarget * math.exp(delta * 0.0011))
        .clamp(_distanceMin, _distanceMax)
        .toDouble();
  }

  /// Pinch zoom: [scale] is the gesture's live scale against its start,
  /// [distanceAtGestureStart] the camera's distance when it began; fingers
  /// closing (scale under 1) move the camera in.
  void pinch(double scale, {required double distanceAtGestureStart}) {
    _distanceTarget = (distanceAtGestureStart / scale)
        .clamp(_distanceMin, _distanceMax)
        .toDouble();
  }

  /// Set the zoom distance directly (world units).
  void setDistance(double worldDistance) {
    _distanceTarget =
        worldDistance.clamp(_distanceMin, _distanceMax).toDouble();
  }

  /// The zoom the rig is easing toward.
  double get distanceTarget => _distanceTarget;

  /// The orbit angle the rig is easing toward.
  double get yawTarget => _yawTarget;

  /// Writes targets directly: the test seam (and any scripted camera
  /// move) for pointing the rig without gestures. [snap] (or an [update])
  /// lands the state.
  void aimAt({
    double? yaw,
    double? pitchDeg,
    double? distance,
    Vec2? target,
  }) {
    if (yaw != null) _yawTarget = yaw;
    if (pitchDeg != null) {
      _pitchTarget = pitchDeg.clamp(pitchMin, pitchMax);
    }
    if (distance != null) {
      _distanceTarget = distance.clamp(_distanceMin, _distanceMax).toDouble();
    }
    if (target != null) _targetTarget = target;
    _snapNext = true;
  }

  /// Eases toward the given targets without snapping: the scripted moves
  /// (the hole's intro sweep, the follow zoom) glide like gestures do.
  void glideTo(
      {double? yaw,
      double? pitchDeg,
      double? distance,
      Vec2? target,
      bool closeUp = false}) {
    // A close-up (the hatch) may come in nearer than the hole's zoom clamp;
    // any other glide with a distance ends it.
    if (closeUp) {
      _closeFloor = closeUpDistanceMin;
    } else if (distance != null) {
      _closeFloor = null;
    }
    if (yaw != null) _yawTarget = yaw;
    if (pitchDeg != null) {
      _pitchTarget = pitchDeg.clamp(pitchMin, pitchMax);
    }
    if (distance != null) {
      _distanceTarget = distance.clamp(_floor, _distanceMax).toDouble();
    }
    if (target != null) _targetTarget = target;
  }

  /// How near a close-up may come (world units).
  static const double closeUpDistanceMin = 3.5;

  /// The close-up's floor while one is on, below the hole's zoom clamp.
  double? _closeFloor;
  double get _floor => _closeFloor ?? _distanceMin;

  /// The zoom clamp [fitToHole] last set (world units); tests read them.
  double get distanceMin => _distanceMin;
  double get distanceMax => _distanceMax;

  /// Ease one frame. [followPoint] glides the target toward the active
  /// egg; null holds the target where it is.
  void update(double dt, {Vec2? followPoint}) {
    _clock += dt;
    _shake = math.max(0, _shake - dt * 1.4);
    if (followPoint != null) _targetTarget = followPoint;
    if (_snapNext) snap();
    const yawSpeed = 7.0;
    const pitchSpeed = 8.0;
    const distanceSpeed = 3.2;
    const targetSpeed = 4.0;
    final yawK = 1 - math.exp(-yawSpeed * dt);
    final pitchK = 1 - math.exp(-pitchSpeed * dt);
    final distanceK = 1 - math.exp(-distanceSpeed * dt);
    final targetK = 1 - math.exp(-targetSpeed * dt);
    yaw += (_yawTarget - yaw) * yawK;
    pitchDeg += (_pitchTarget - pitchDeg) * pitchK;
    distance += (_distanceTarget - distance) * distanceK;
    target = Vec2(
      target.x + (_targetTarget.x - target.x) * targetK,
      target.y + (_targetTarget.y - target.y) * targetK,
    );
  }

  /// Whether the player asked their system for reduced motion: the
  /// camera then never shakes nor punches in.
  bool reduceMotion = false;

  /// The camera's punch for the viewer's own sink: in a step, and a shake.
  void punch() {
    if (reduceMotion) return;
    _distanceTarget =
        (_distanceTarget * 0.9).clamp(_floor, _distanceMax).toDouble();
    shake(0.25);
  }

  /// A short shake of [strength] world units, fading over a fifth of a
  /// second.
  void shake(double strength) {
    if (reduceMotion) return;
    _shake = math.max(_shake, strength);
  }

  double _shake = 0;
  double _clock = 0;

  /// Copy every target into the live state at once (also the boot snap).
  void snap() {
    yaw = _yawTarget;
    pitchDeg = _pitchTarget;
    distance = _distanceTarget.clamp(_floor, _distanceMax).toDouble();
    target = _targetTarget;
    _snapNext = false;
  }

  /// Where the camera stands for the current rig state, in the world's
  /// ground frame: the game's x stays world x, the game's y (y down)
  /// becomes world z, and heights lift along world y. The camera hangs
  /// behind the target - opposite the away axis the yaw turns.
  tjs.Vector3 cameraPositionOf(Vec2 targetPoint) {
    final pitch = pitchDeg * math.pi / 180;
    final cp = math.max(math.cos(pitch), 0.15);
    final sp = math.sin(pitch);
    final awayX = math.sin(yaw);
    final awayZ = math.cos(yaw);
    return tjs.Vector3(
      targetPoint.x - awayX * distance * cp,
      distance * sp,
      targetPoint.y - awayZ * distance * cp,
    );
  }

  /// Lands the rig on the three_js camera: position, then the look at the
  /// (ground-level) target.
  void applyTo(tjs.PerspectiveCamera camera) {
    final at = cameraPositionOf(target);
    if (_shake > 0) {
      // A jitter that never repeats the same way: two detuned sines a
      // side.
      at.x += math.sin(_clock * 61) * _shake;
      at.y += math.sin(_clock * 47 + 1.3) * _shake * 0.6;
      at.z += math.sin(_clock * 53 + 2.1) * _shake;
    }
    camera.position.setFrom(at);
    camera.lookAt(tjs.Vector3(target.x, 0, target.y));
  }
}

// ---- the world -----------------------------------------------------------------

/// The farm as three_js geometry. Build one per game; build holes; feed
/// frames; dispose when done. Constructing, building holes and applying
/// snapshots are pure Dart - only [PuttThreeSurface] touches the GPU path.
class PuttWorld3D {
  PuttWorld3D({ui.Size viewport = const ui.Size(800, 600)})
      : rig = PuttCameraRig(viewport: viewport) {
    _setUpCamera();
    _setUpLights();
    _sky = _SkyDome();
    scene
      ..add(_sky.group)
      ..add(_holeRoot = tjs.Group()..name = 'hole')
      ..add(_actorsRoot = tjs.Group()..name = 'actors')
      ..add(_aimRoot = tjs.Group()..name = 'aim')
      ..add(_fxRoot = _ShownChildrenGroup()..name = 'fx')
      ..add(_bursts.group)
      ..add(_casts.group)
      ..add(_hatchRoot);
    for (var i = 0; i < 3; i++) {
      final hatchling = _Hatchling();
      _hatchlings.add(hatchling);
      _hatchRoot.add(hatchling.group);
    }
    _aim = _PuttAimView3D(eggRadius: _eggRadius);
    _aimRoot.add(_aim.group);
  }

  final tjs.Scene scene = tjs.Scene();
  final tjs.PerspectiveCamera camera = tjs.PerspectiveCamera(
    PuttCameraRig.fovDeg,
    800 / 600,
    0.3,
    1400,
  );
  final PuttCameraRig rig;

  late final tjs.Group _holeRoot;
  late final tjs.Group _actorsRoot;
  late final tjs.Group _aimRoot;
  late final tjs.Group _fxRoot;
  late final _SkyDome _sky;
  late final tjs.HemisphereLight _ambient;

  /// The theme's rim light (off by day): from behind the green, no shadow.
  late final tjs.DirectionalLight _rim;

  tjs.DirectionalLight? _sun;

  /// Textures the world itself owns across holes (the fx disc): disposed
  /// with the world, never shared outside it.
  final List<tjs.Texture> _owned = [];

  /// The per-kind groups the hole's geometry builds into; the tests walk
  /// these by name.
  final List<tjs.Group> _kindGroups = [];

  /// The hole's animated pieces (water, flag, windmill, crates, portals,
  /// boosts, clouds): each ticks with the frame's clock.
  final List<_Animated> _animated = [];

  HoleDef? _hole;
  double _eggRadius = 0.45;

  /// The course's corner of the farm and its hour: sky, sun, rails.
  _Theme _theme = _Theme.coop;

  /// The tone mapper's exposure for the current hole's light; the
  /// surface hands it to the renderer every frame.
  double get exposure => _theme.exposure;

  late final _PuttAimView3D _aim;

  final Map<String, _EggView3D> _eggViews = {};
  final List<_Walker> _henViews = [];
  final List<_CrateView3D> _crateViews = [];

  final _PuttFxPool _fx = _PuttFxPool();

  /// The bursts the world sees for itself (straw, the viewer's confetti
  /// column, rail puffs).
  final _Bursts _bursts = _Bursts();

  /// The power-ups' standing pieces: the crows and their loot, the nest's
  /// magnet shimmer (the casts' particles ride the fx pool).
  final _CastScenes _casts = _CastScenes();

  /// The current hole's relief, shared with everything standing on it.
  final _Ground _ground = _Ground();

  /// The chicks that hatch in the nest when an egg drops in.
  final tjs.Group _hatchRoot = tjs.Group()..name = 'hatchlings';
  final List<_Hatchling> _hatchlings = [];

  /// Hatches [view]'s egg in the nest at [nest]: a free chick, or the one
  /// furthest along when all three are out.
  void _hatch(_EggView3D view, Vec2 nest) {
    if (_hatchlings.isEmpty) return;
    var pick = _hatchlings.first;
    for (final hatchling in _hatchlings) {
      if (!hatchling.busy) {
        pick = hatchling;
        break;
      }
      if (hatchling._age > pick._age) pick = hatchling;
    }
    pick.hatch(nest, view._tintHex,
        hat: view.hat,
        floor: _ground.at(nest),
        big: view.everMine,
        rim: (_hole?.nest.radius ?? 1.2) * 0.85);
  }

  /// Until when (the frame clock) the flag shakes: an egg just dropped in.
  double _flagShakeUntil = 0;

  double _lastTime = 0;
  bool _firstFrame = true;
  bool _disposed = false;

  HoleDef? get hole => _hole;

  /// Where the host stands on the ground, when the hole built is
  /// [holeId] (null with no host, or another hole still built).
  Vec2? hostSpotOn(String holeId) {
    final figure = _hostFade?.figure;
    if (figure == null || _hole?.id != holeId) return null;
    return Vec2(figure.position.x, figure.position.z);
  }

  /// The named sub-group of the hole root holding everything of that kind
  /// ('ground', 'walls', 'bumpers', ...); null when the hole lacks it.
  tjs.Group? holeGroup(String kind) {
    for (final group in _kindGroups) {
      if (group.name == kind) return group;
    }
    return null;
  }

  /// One egg's group (its position, quaternion and children are this
  /// world's truth for that player); null before the first frame carrying
  /// them. The tests read the roll and the hop lift through it.
  tjs.Group? eggOf(String playerId) => _eggViews[playerId]?.group;

  void setViewport(ui.Size size) {
    if (_disposed) return;
    rig.setViewport(size);
    camera.aspect = rig.aspect;
    camera.updateProjectionMatrix();
  }

  /// Refits the rig to the hole's bounds (after a resize, a hole change).
  void fitCamera() {
    final hole = _hole;
    if (hole == null) return;
    rig.fitToHole(hole.bounds);
    _aimSun(hole);
  }

  // ---- lights and camera ------------------------------------------------------------

  void _setUpCamera() {
    camera.aspect = rig.aspect;
    camera.updateProjectionMatrix();
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
  }

  void _setUpLights() {
    // The fill: a sky-blue dome over meadow-green bounce light.
    _ambient = tjs.HemisphereLight(0xFFFFFF, 0xFFFFFF, 0.62);
    _ambient.color = _lin(0xD6ECFF);
    _ambient.groundColor = _lin(0x9DB86A);
    scene.add(_ambient);
    // The warm morning sun, with its shadow work.
    final sun = tjs.DirectionalLight(0xFFFFFF, 1.32);
    sun.color = _lin(0xFFF0D8);
    sun.castShadow = true;
    final shadow = sun.shadow!;
    shadow.mapSize.setValues(2048, 2048);
    shadow.bias = -0.0006;
    shadow.normalBias = 0.04;
    shadow.radius = 3;
    scene.add(sun);
    scene.add(sun.target!);
    _sun = sun;
    _rim = tjs.DirectionalLight(0xFFFFFF, 0)..castShadow = false;
    scene.add(_rim);
    scene.add(_rim.target!);
  }

  /// Plants the sun over the current hole so its shadow camera covers the
  /// green and the scenery near it, and hangs the haze off the hole's span.
  void _aimSun(HoleDef hole) {
    final sun = _sun;
    if (sun == null) return;
    final center = tjs.Vector3(hole.bounds.center.x, 0, hole.bounds.center.y);
    sun.target!.position.setFrom(center);
    // The theme's sun: by default from the left and in front (the
    // camera's side), lit faces toward the player, shadows falling away.
    final (sx, sy, sz) = _theme.sunFrom;
    sun.position.setFrom(center).add(tjs.Vector3(sx, sy, sz));
    final (rx, ry, rz) = _theme.rimFrom;
    _rim.target!.position.setFrom(center);
    _rim.position.setFrom(center).add(tjs.Vector3(rx, ry, rz));
    final span = math.max(hole.bounds.width, hole.bounds.height);
    final half = span * 0.62 + 12;
    final shadowCam = sun.shadow!.camera;
    if (shadowCam != null) {
      shadowCam
        ..left = -half
        ..right = half
        ..top = half
        ..bottom = -half
        ..near = 1
        ..far = 140;
      shadowCam.updateProjectionMatrix();
    }
    // Depth: the far meadow dissolving gently into the warm horizon.
    final fog = tjs.Fog(0xFFFFFF, span * 1.5 + 30, span * 5 + 160);
    fog.color = _lin(_theme.horizon);
    scene.fog = fog;
  }

  // ---- hole construction --------------------------------------------------------------

  /// Builds (or rebuilds) the hole's geometry. A hole whose id is already
  /// up keeps its meshes; a new one disposes the old subtree first.
  /// [label] is the number the flag flies (the hole's place in its course).
  void buildHole(HoleDef hole, {required double eggRadius, String? label}) {
    if (_disposed) return;
    if (_hole?.id == hole.id) return;
    _clearHole();
    _hole = hole;
    _ground.hole = hole;
    _eggRadius = eggRadius;
    _theme = _Theme.of(hole.id);
    _applyTheme();

    tjs.Group makeKind(String name) {
      final group = tjs.Group()..name = name;
      _kindGroups.add(group);
      _holeRoot.add(group);
      return group;
    }

    final kit = _CourseKit(hole,
        eggRadius: eggRadius,
        animated: _animated,
        rig: rig,
        theme: _theme,
        flagShakeUntil: () => _flagShakeUntil);
    makeKind('ground').add(kit.lawn());
    makeKind('table').add(kit.table());
    final walls = makeKind('walls');
    final bumpers = makeKind('bumpers');
    for (final wall in hole.walls) {
      // A ledge is no rail: its face is the tiers' step (see 'cliffs').
      if (wall.ledge) continue;
      if (wall.bumper) {
        bumpers.add(kit.bumperRail(wall));
      } else {
        walls.add(kit.rail(wall.a, wall.b));
      }
    }
    final cliffs = kit.cliffs();
    if (cliffs != null) makeKind('cliffs').add(cliffs);
    // The kickers, each in the course's build, standing on the ground.
    if (hole.kickers.isNotEmpty) {
      final kickers = makeKind('kickers');
      for (final kicker in hole.kickers) {
        kickers.add(kit.kicker(kicker));
      }
    }
    // What stands free on the green stands on the tier under it (a
    // terrace's flat top lifts it whole).
    final arcs = makeKind('arcs');
    for (final arc in hole.arcs) {
      final built = kit.arc(arc);
      if (arc.sweep >= 2 * math.pi - 0.01) {
        built.position.y += _ground.at(arc.center);
      }
      (arc.bumper ? bumpers : arcs).add(built);
    }
    final wells = makeKind('wells');
    for (final well in hole.wells) {
      wells.add(kit.silo(well)..position.y += _ground.at(well.position));
    }
    final water = makeKind('water');
    for (final shape in hole.water) {
      water.add(kit.water(shape));
    }
    final boosts = makeKind('boosts');
    for (final strip in hole.boosts) {
      boosts.add(kit.boost(strip)
        ..position.y += _ground.at((strip.from + strip.to) * 0.5));
    }
    final portals = makeKind('portals');
    for (var i = 0; i < hole.portals.length; i++) {
      final pair = hole.portals[i];
      portals.add(kit.portal(pair.a, pair.radius, pairIndex: i, phase: 0)
        ..position.y += _ground.at(pair.a));
      portals.add(kit.portal(pair.b, pair.radius, pairIndex: i, phase: 1.6)
        ..position.y += _ground.at(pair.b));
    }
    final boxes = makeKind('boxes');
    for (final box in hole.boxes) {
      final crate = _CrateView3D(box, kit.crateTexture(),
          floor: _ground.at(box.position));
      boxes.add(crate.group);
      _crateViews.add(crate);
    }
    final garden = kit.garden();
    if (garden != null) makeKind('garden').add(garden);
    // The nest, the tee and the props stand on the ground (a plateau
    // lifts the nest with it).
    makeKind('nest').add(
        kit.nest(label: label)..position.y += _ground.at(hole.nest.position));
    final tee = makeKind('tee')
      ..add(kit.tee()..position.y += _ground.at(hole.tee));
    // The hole's number on a sign beside the tee (off the table: it stands
    // on the meadow, whatever the green's relief).
    final sign = kit.teeSign(label: label);
    if (sign != null) tee.add(sign);
    final decorations = makeKind('decorations');
    for (final decoration in hole.decorations) {
      final built = kit.decoration(decoration);
      if (built != null) {
        decorations.add(built..position.y += _ground.at(decoration.at));
      }
    }
    // Where the hens walk and wait, worn into the turf (on the green only).
    final paths = kit.henPaths(_ground.at);
    if (paths != null) makeKind('hen-paths').add(paths);
    final hens = makeKind('hens');
    for (final obstacle in hole.obstacles) {
      // Ducks paddle the Pond's water; hens walk everything else.
      final _Walker hen = _henSwims(hole, obstacle)
          ? _DuckView3D(obstacle)
          : _HenView3D(obstacle, _ground);
      hens.add(hen.group);
      _henViews.add(hen);
    }
    final scenery = _Scenery(hole,
            animated: _animated,
            theme: _theme,
            cheerUntil: () => _cheerUntil,
            watch: () => _watch,
            greet: () => _greeting ? _greetAt : null,
            shape: kit.shape,
            signAt: sign == null ? null : kit.teeSignSpot?.$1)
        .build();
    makeKind('scenery').add(scenery);
    final host = scenery.getObjectByName('host');
    _hostFade = host == null ? null : _FadingFigure(host);
    _hostDetail = host == null ? null : _HostDetail(host);

    _fx.reset(_fxRoot);
    _firstFrame = true;
    if (_lowTier) _shedOutlines(_holeRoot);
    fitCamera();
  }

  /// The low tier is on: what costs most for least is gone (a smaller
  /// shadow map, the walkers' and the scenery's ink outlines).
  bool get lowTier => _lowTier;
  bool _lowTier = false;

  /// Drops to the low tier, once: the sun's shadow map from 2048 to 1024
  /// pixels a side (rebuilt on the next frame), and the ink outlines on
  /// everything but the eggs, which keep theirs (they are the characters).
  /// The GPU surface calls it when frames run slow.
  void lowerQuality() {
    if (_lowTier || _disposed) return;
    _lowTier = true;
    final shadow = _sun?.shadow;
    if (shadow != null) {
      shadow.mapSize.setValues(1024, 1024);
      shadow.map?.dispose();
      shadow.map = null;
    }
    _shedOutlines(_holeRoot);
  }

  void _shedOutlines(tjs.Object3D root) {
    root.traverse((object) {
      final name = object.name;
      if (name.endsWith('-outline') && !name.startsWith('egg')) {
        object.visible = false;
      }
    });
  }

  /// The theme's light and sky: the dome's colours, the sun's colour and
  /// strength, the fill's (the sun's place and the haze follow in
  /// [_aimSun], with the hole's span).
  void _applyTheme() {
    _sky.recolor(_theme);
    _ambient
      ..color = _lin(_theme.hemiSky)
      ..groundColor = _lin(_theme.hemiGround)
      ..intensity = _theme.hemiIntensity;
    final sun = _sun;
    if (sun != null) {
      sun
        ..color = _lin(_theme.sun)
        ..intensity = _theme.sunIntensity;
    }
    // Always in the scene (by day at nothing): a light that came and went
    // would change every material's program on a course change.
    _rim
      ..color = _lin(_theme.rim)
      ..intensity = _theme.rimIntensity;
  }

  /// Disposes the whole hole subtree and forgets every per-hole view.
  void _clearHole() {
    _bursts.clear();
    _casts.clear();
    for (final hatchling in _hatchlings) {
      hatchling.hide();
    }
    for (final sinking in _sinking) {
      _dropEgg(sinking.view);
    }
    _sinking.clear();
    _disposeChildren(_holeRoot);
    _ground.hole = null;
    _watch = null;
    _greeting = false;
    _hostFade = null;
    _hostDetail = null;
    _henViews.clear();
    _crateViews.clear();
    _animated.clear();
    _kindGroups.clear();
    _hole = null;
    _fx.reset(_fxRoot);
  }

  // ---- the snapshot -----------------------------------------------------------------

  /// Reads one frame: pools egg meshes by player id, rolls them by their
  /// velocity, lifts the hops and flies the kickers' flights, waddles the
  /// hens, stands collected crates down, breathes the scenery, and glides
  /// the camera.
  void applySnapshot(PuttWorldFrame frame) {
    if (_disposed) return;
    final dt = _firstFrame
        ? 0.0
        : (frame.time - _lastTime).clamp(0.0, 0.05).toDouble();
    _lastTime = frame.time;
    _firstFrame = false;

    _syncEggs(frame, dt);
    // While the hole opens, the host looks at the camera (where it stood
    // last frame: the sweep moves it a little at a time).
    _greeting = frame.opening;
    if (_greeting) _greetAt.setFrom(camera.position);
    _syncHens(frame, dt);
    _syncCrates(frame);
    _aim.sync(frame.aim, frame.time, _ground);
    // Confetti and sparkles grow with the camera's distance, so the party
    // reads from the overview too.
    final grow = math.max(1.0, rig.distance / 24);
    _fx.apply(frame, scale: grow, ground: _ground, camera: camera);
    _bursts.update(dt, frame.time);
    // The casts' figures (the crow, the bubbles) grow a little faster
    // than the particles' square root, so they read from the overview.
    _casts.sync(frame,
        hole: _hole,
        ground: _ground,
        grow: math.pow(grow, 0.75).toDouble(),
        dt: dt);
    for (final hatchling in _hatchlings) {
      hatchling.update(dt, camera.position);
    }
    for (final piece in _animated) {
      piece.tick(frame.time, dt);
    }
    _sky.tick(frame.time);
    rig.update(math.max(dt, 1 / 240), followPoint: frame.followPoint);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
    _faceCamera();
    _syncHost(dt);
    // The dome rides with the camera, so its horizon never comes near.
    _sky.group.position.setValues(camera.position.x, 0, camera.position.z);
  }

  final tjs.Quaternion _roll = tjs.Quaternion();
  final tjs.Vector3 _viewAxis = tjs.Vector3(0, 0, 1);

  /// Turns every billboard (trails, bursts, effects, glints, the sun) to
  /// face the camera, each spun by its own roll.
  void _faceCamera() {
    final facing = camera.quaternion;
    scene.traverse((object) {
      if (object is! _Billboard || !object.visible) return;
      object.quaternion.setFrom(facing);
      if (object.roll != 0) {
        object.quaternion
            .multiply(_roll.setFromAxisAngle(_viewAxis, object.roll));
      }
      // The effects' pooled sprites skip the per-frame matrix work while
      // hidden (hundreds of them): one shown gets its matrix here.
      if (!object.matrixAutoUpdate) object.updateMatrix();
    });
  }

  final tjs.Vector3 _mineInView = tjs.Vector3();
  final tjs.Vector3 _otherInView = tjs.Vector3();

  /// Marks the eggs that stand in front of the viewer's resting egg on the
  /// screen (by last frame's camera and places), so they fade aside: the
  /// close camera behind a fresh egg looks along the tee's ring of eggs,
  /// and the nearest one hid the viewer's egg, its pin and the aim's base.
  void _screenEggs(PuttWorldFrame frame) {
    PuttWorldEgg? mine;
    for (final egg in frame.eggs) {
      if (egg.mine) mine = egg;
    }
    final mineView = mine == null ? null : _eggViews[mine.playerId];
    final resting = mineView != null && mine!.speed < 0.05;
    if (resting) {
      _mineInView
        ..setFrom(mineView.group.position)
        ..applyMatrix4(camera.matrixWorldInverse);
    }
    for (final egg in frame.eggs) {
      if (egg.mine) continue;
      final view = _eggViews[egg.playerId];
      if (view == null) continue;
      // In front of mine on the screen, or passing through mine on the
      // ground (an egg that has not putted is a ghost to the others): the
      // latter at once, the frame it is in.
      final inside = resting &&
          egg.position.distanceTo(mine.position) <
              (egg.radius + mine.radius) * 1.1;
      view.screening = inside || (resting && _covers(view, mineView));
      if (inside) view.screenAtOnce();
    }
  }

  /// Whether [other] stands nearer the camera than [mine] and overlaps it
  /// on the screen: boxes in the view's slope (x/z, y/z), the viewer's
  /// reaching up over its pin.
  bool _covers(_EggView3D other, _EggView3D mine) {
    _otherInView
      ..setFrom(other.group.position)
      ..applyMatrix4(camera.matrixWorldInverse);
    // The camera looks down its -z.
    final zMine = -_mineInView.z;
    final zOther = -_otherInView.z;
    if (zMine <= 0.1 || zOther <= 0.1 || zOther >= zMine) return false;
    final rMine = mine._radius / zMine;
    final rOther = other._radius / zOther;
    final dx = (_otherInView.x / zOther - _mineInView.x / zMine).abs();
    if (dx > (rMine + rOther) * 1.05) return false;
    final yMine = _mineInView.y / zMine;
    final yOther = _otherInView.y / zOther;
    final tall = rOther * _eggAspect;
    // Mine from under its shell to the top of its pin.
    return yOther + tall > yMine - rMine * _eggAspect &&
        yOther - tall < yMine + rMine * 4.4;
  }

  void _syncEggs(PuttWorldFrame frame, double dt) {
    // What the host watches: the quickest egg on the move, else mine.
    Vec2? quickest;
    var pace = 0.8;
    for (final egg in frame.eggs) {
      if (egg.speed > pace) {
        pace = egg.speed;
        quickest = egg.position;
      } else if (quickest == null && egg.mine) {
        _watch = egg.position;
      }
    }
    if (quickest != null) _watch = quickest;
    _screenEggs(frame);
    final seen = <String>{};
    for (final egg in frame.eggs) {
      seen.add(egg.playerId);
      final view = _eggViews.putIfAbsent(egg.playerId, () {
        final created = _EggView3D(
          egg.radius * _eggVisualScale,
          egg.tint,
          pattern: egg.look.pattern,
          trailHex: _mix(_theme.turfFringe, 0x4A3A22, 0.4),
          terrain: _ground,
          glow: _theme.eggGlow,
          onBounce: (at, strength, mine) {
            _bursts.puff(at, strength, floor: _ground.at(at));
            if (mine && strength > 0.45) rig.shake(0.08 + strength * 0.12);
          },
        );
        _actorsRoot.add(created.group);
        _actorsRoot.add(created.ground);
        _actorsRoot.add(created.trail);
        return created;
      });
      view
        ..restyle(egg.tint, egg.look.pattern)
        ..hat = egg.look.hat;
      view.sync(egg, dt, frame.time);
      view.outlineFor(rig.distance);
    }
    _eggViews.removeWhere((playerId, view) {
      if (seen.contains(playerId)) return false;
      // Gone at the nest: it drops in (a short sink and shrink); gone
      // anywhere else (a player leaving): it just goes.
      final nest = _hole?.nest;
      if (nest != null &&
          view.lastPosition.distanceTo(nest.position) < nest.radius * 1.8) {
        _sinking.add(_SinkingEgg(view, nest.position));
        // The host celebrates every egg that drops in, the straw flies and
        // the flag shakes; the viewer's own sink gets the confetti column
        // and the camera's punch.
        _cheerUntil = frame.time + 2.2;
        _flagShakeUntil = frame.time + 1.4;
        final floor = _ground.at(nest.position);
        // For the viewer's own: none of it between the camera and the chick
        // hatching there.
        final toCamera = Vec2(camera.position.x - nest.position.x,
            camera.position.z - nest.position.y);
        final clear = view.everMine && toCamera.length > 1e-6 ? toCamera : null;
        _bursts.straw(nest.position, nest.radius,
            floor: floor, clearToward: clear);
        if (view.everMine) {
          _bursts.confettiColumn(nest.position,
              floor: floor, radius: nest.radius, clearToward: clear);
          rig.punch();
        }
      } else {
        _dropEgg(view);
      }
      return true;
    });
    _sinking.removeWhere((sinking) {
      sinking.age += dt;
      final t = (sinking.age / _SinkingEgg.life).clamp(0.0, 1.0);
      final eased = t * t;
      final view = sinking.view;
      final from = view.lastPosition;
      final at = Vec2(
        from.x + (sinking.nest.x - from.x) * math.min(1, t * 2.2),
        from.y + (sinking.nest.y - from.y) * math.min(1, t * 2.2),
      );
      final scale = 1 - eased * 0.75;
      view.group
        ..position.setValues(
            at.x,
            _ground.at(sinking.nest) + view.restHeight * scale - eased * 0.9,
            at.y)
        ..scale.setValues(scale, scale, scale);
      view.ground.visible = false;
      if (t >= 1) {
        // In: the egg hatches.
        _hatch(view, sinking.nest);
        _dropEgg(view);
        return true;
      }
      return false;
    });
  }

  /// Eggs dropping into the nest, finishing their sink.
  final List<_SinkingEgg> _sinking = [];

  /// Until when (the frame clock) the host cheers.
  double _cheerUntil = 0;

  /// The egg the host's head follows.
  Vec2? _watch;

  /// Whether the host looks at the camera (the hole is opening), and
  /// where it stands.
  bool _greeting = false;
  final tjs.Vector3 _greetAt = tjs.Vector3();

  void _dropEgg(_EggView3D view) {
    _actorsRoot.remove(view.group);
    _actorsRoot.remove(view.ground);
    _actorsRoot.remove(view.trail);
    view.dispose();
  }

  void _syncHens(PuttWorldFrame frame, double dt) {
    for (var i = 0; i < _henViews.length && i < frame.hens.length; i++) {
      final view = _henViews[i];
      view.sync(frame.hens[i], frame.time);
      if (view is _HenView3D) {
        // A hen right in front of the camera (a close-up's foreground), or
        // any hen while the camera is in on my egg's hatch, pops out of the
        // way: all or nothing (a ghost of her read as a glitch), with a
        // little slack so she does not flicker at the line.
        final at = frame.hens[i].position;
        final dx = camera.position.x - at.x;
        final dy = camera.position.y - _ground.at(at);
        final dz = camera.position.z - at.y;
        final near = math.sqrt(dx * dx + dy * dy + dz * dz) /
            math.max(rig.distance, 1e-6);
        final gone = view._fade < 0.5;
        final tooNear = near < (gone ? 0.68 : 0.58);
        view.fadeToward(frame.closeUp || tooNear ? 0.0 : 1.0, dt);
      }
    }
  }

  /// The host fades away while his head would stand under the HUD's top
  /// bar or its corner buttons, or right in front of the camera.
  void _syncHost(double dt) {
    final fade = _hostFade;
    final size = rig.viewport;
    if (fade == null || size.width <= 0 || size.height <= 0) return;
    final at = fade.figure.position;
    // His own height, not the pop's shrink (that would bring his head out
    // from under the HUD and back, over and over).
    final head = tjs.Vector3(at.x, at.y + 8.2 * fade.fadeBaseScaleY, at.z)
        .project(camera);
    final headY = (1 - head.y) / 2 * size.height;
    final headX = (head.x + 1) / 2 * size.width;
    if (head.z < 1) {
      // In full while he stands tall on the screen, light while small.
      final foot = tjs.Vector3(at.x, at.y, at.z).project(camera);
      _hostDetail?.standing((1 - foot.y) / 2 * size.height - headY);
    }
    final dx = camera.position.x - at.x;
    final dz = camera.position.z - at.z;
    // Some slack once he is gone, as with the hens: a camera on the move
    // crossing the line back and forth left him half there, a ghost.
    final gone = fade._fade < 0.5;
    final near = math.sqrt(dx * dx + dz * dz) / math.max(rig.distance, 1e-6) <
        (gone ? 0.62 : 0.55);
    final underHud = head.z < 1 &&
        headY < _hudTopBand + (gone ? 28 : 0) &&
        headX > -40 &&
        headX < size.width + 40;
    fade.fadeToward(underHud || near ? 0.0 : 1.0, dt);
  }

  /// How far down the HUD's top bar and corner buttons reach, in pixels.
  static const double _hudTopBand = 118;

  _FadingFigure? _hostFade;
  _HostDetail? _hostDetail;

  void _syncCrates(PuttWorldFrame frame) {
    for (final crate in _crateViews) {
      crate.sync(
        visible: !frame.collectedBoxes.contains(crate.id),
        time: frame.time,
      );
    }
  }

  // ---- the aim's ray ---------------------------------------------------------------------

  /// The ground point under a screen pixel: the pointer's ray (through
  /// the three_js camera) onto the green. Null when the pixel looks at
  /// the sky above the horizon - the aim does nothing.
  Vec2? screenToWorld(ui.Offset screen) {
    if (_disposed || rig.viewport.width <= 0 || rig.viewport.height <= 0) {
      return null;
    }
    camera.updateMatrixWorld(true);
    final nx = screen.dx / rig.viewport.width * 2 - 1;
    final ny = 1 - screen.dy / rig.viewport.height * 2;
    final through = tjs.Vector3(nx, ny, -1).unproject(camera);
    final dir = through.sub(camera.position);
    if (dir.y.abs() < 1e-9) return null; // parallel to the green
    final t = -camera.position.y / dir.y;
    if (t <= 0) return null; // the ray rises: sky, not ground
    var hit =
        Vec2(camera.position.x + dir.x * t, camera.position.z + dir.z * t);
    // Over hills: walk the ray onto the ground's own height (a few steps
    // converge for any slope the green allows).
    if (!_ground.flat) {
      for (var i = 0; i < 6; i++) {
        final s = (_ground.at(hit) - camera.position.y) / dir.y;
        if (s <= 0) break;
        hit =
            Vec2(camera.position.x + dir.x * s, camera.position.z + dir.z * s);
      }
    }
    return hit;
  }

  /// The surface pixel a ground point projects to, through the same ray
  /// [screenToWorld] walks: the aim's pointer plumbing, the name tags and
  /// the e2e's drag math all lean on the read. [height] lifts the point
  /// toward the camera (a hop's lift, a tag over an egg).
  ui.Offset projectToWorld(Vec2 world, {double height = 0}) {
    if (_disposed || rig.viewport.width <= 0 || rig.viewport.height <= 0) {
      return ui.Offset.zero;
    }
    camera.updateMatrixWorld(true);
    final point = tjs.Vector3(world.x, height + _ground.at(world), world.y)
        .project(camera);
    return ui.Offset(
      (point.x + 1) / 2 * rig.viewport.width,
      (1 - point.y) / 2 * rig.viewport.height,
    );
  }

  /// Whether a ground point (lifted by [height]) sits in front of the
  /// camera - the name tags hide when their egg is behind the lens.
  bool inFrontOfCamera(Vec2 world, {double height = 0}) {
    if (_disposed) return false;
    final point = tjs.Vector3(world.x, height + _ground.at(world), world.y)
        .project(camera);
    return point.z < 1 && point.z > -1;
  }

  /// Frees every geometry, material and owned texture in the world, the
  /// camera included. Safe to call twice; the GPU surface calls it after
  /// the renderer is down.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // The fx sprites' discs, the drops' and the kernel die with the world.
    _owned
      ..add(_fx.texture)
      ..add(_fx.dropTexture)
      ..add(_fx.kernelTexture)
      ..add(_fx.streakTexture);
    scene.dispose(); // walks the children, then marks the scene itself
    camera.dispose();
    for (final texture in _owned) {
      texture.dispose();
    }
    _owned.clear();
    _eggViews.clear();
    _animated.clear();
    _hole = null;
  }

  static void _disposeChildren(tjs.Object3D parent) {
    // Removed before disposed: three_js disposes a child's parent too.
    for (final child in [...parent.children]) {
      parent.remove(child);
      _keepSharedTextures(child);
      child.dispose();
    }
  }

  /// The textures every hole shares (the soft disc of shadows, glows and
  /// glints, the eggs' paints) live as long as the program: a hole that
  /// goes takes its materials, not those.
  static void _keepSharedTextures(tjs.Object3D root) {
    root.traverse((object) {
      final material = object.material;
      if (material == null) return;
      final map = material.map;
      if (map != null &&
          (identical(map, _EggView3D._shadowTexture) ||
              identical(map, _paperTexture) ||
              _eggTextures.containsValue(map))) {
        material.map = null;
      }
    });
  }
}

/// The camera seam the e2e (and anything reading the aim's pixels) uses:
/// world points projected to surface pixels through the world's own
/// perspective.
class PuttCameraSeam {
  final PuttWorld3D _world;

  const PuttCameraSeam(this._world);

  /// The surface pixel a world point (lifted by [height]) projects to.
  ui.Offset project(Vec2 world, {double height = 0}) =>
      _world.projectToWorld(world, height: height);
}

// ---- the drawing resolution -----------------------------------------------------------------

/// Steps the drawing resolution down while frames run slow - a laptop's
/// integrated GPU on a high-density screen - so the game keeps its pace:
/// after [window] seconds averaging under [targetFps], one step of
/// [step]; then it lets the surface settle before judging again. Never
/// below [floor], and never back up (a step up and down again would
/// show as a flicker of sharpness).
class PuttResolutionGovernor {
  PuttResolutionGovernor(this.start)
      : ratio = start,
        floor = math.min(start, math.max(0.75, start * 0.5));

  /// The device's pixel ratio the surface came up at.
  final double start;

  /// The lowest ratio it steps down to.
  final double floor;

  /// The ratio the surface draws at now.
  double ratio;

  static const double targetFps = 42;
  static const double window = 3;
  static const double step = 0.8;

  /// Seconds not judged after boot (shaders compile) and after a step.
  static const double settle = 2.5;

  double _quiet = settle;
  double _measured = 0;
  int _frames = 0;

  /// Feeds one frame's interval (seconds); returns the ratio to draw at
  /// when it is time for a step down, else null.
  double? frame(double seconds) {
    if (ratio <= floor) return null;
    // A pause (a hidden tab, a debugger) says nothing about the GPU.
    if (seconds <= 0 || seconds > 0.5) return null;
    if (_quiet > 0) {
      _quiet -= seconds;
      return null;
    }
    _measured += seconds;
    _frames++;
    if (_measured < window) return null;
    final fps = _frames / _measured;
    _measured = 0;
    _frames = 0;
    if (fps >= targetFps) return null;
    ratio = math.max(floor, ratio * step);
    _quiet = settle;
    return ratio;
  }
}

// ---- the GPU surface ------------------------------------------------------------------------

/// The widget that hosts the three_js renderer bound to a [PuttWorld3D]:
/// the package's [ThreeJS] view running the world's scene and camera, its
/// render hook moving the world to each frame's truth before drawing. It
/// takes the size its parent gives it (the call's stage, not the window)
/// and resizes the GL surface with it.
///
/// Where no GPU surface can come up (the Flutter test runner), the widget
/// paints the horizon plain and the game keeps ticking its match
/// headlessly, exactly as the widget tests expect.
class PuttThreeSurface extends StatefulWidget {
  final PuttWorld3D world;

  /// Builds the frame the world moves to, once per rendered frame (the
  /// game's read of the match's interpolated truth).
  final PuttWorldFrame Function() buildFrame;

  /// Setup-complete and failure taps for the hosting view.
  final VoidCallback? onReady;
  final VoidCallback? onFailed;

  /// Called after every rendered frame (the name tags follow it).
  final VoidCallback? onFrame;

  const PuttThreeSurface({
    super.key,
    required this.world,
    required this.buildFrame,
    this.onReady,
    this.onFailed,
    this.onFrame,
  });

  /// Whether the renderer can come up here. Web only needs WebGL2. On
  /// native, the ANGLE surface needs the platform's plugins - the Flutter
  /// test runner has neither (its process carries no GL symbols and the
  /// plugin channels stand empty), so it reports false: the view shows
  /// the plain panel and the tests run headless.
  static bool get gpuSupported =>
      debugGpuSupported ?? (kIsWeb || !flutter_env.runningUnderFlutterTest);

  /// Tests: try the GL surface anyway (under the test runner its plugin is
  /// missing, so the start fails as on a machine without GL).
  static bool? debugGpuSupported;

  @override
  State<PuttThreeSurface> createState() => _PuttThreeSurfaceState();
}

class _PuttThreeSurfaceState extends State<PuttThreeSurface>
    with SingleTickerProviderStateMixin {
  tjr.ThreeJS? _three;
  bool _failed = false;

  /// With no GL to draw with, the world still moves every frame (the
  /// camera's choreography, the eggs, the tags and the coach riding it,
  /// the aim's ray through the camera): only the drawing is gone.
  Ticker? _headless;

  void _failOver(ui.Size size) {
    if (_headless != null) return;
    widget.world.setViewport(size);
    widget.world.fitCamera();
    _headless = createTicker((_) {
      if (!mounted) return;
      final now = _size;
      if (now != null) widget.world.setViewport(now);
      widget.world.applySnapshot(widget.buildFrame());
      widget.onFrame?.call();
    })
      ..start();
  }

  bool _ready = false;
  ui.Size? _size;
  ui.Size? _pendingSize;
  bool _resizing = false;
  PuttResolutionGovernor? _governor;
  final Stopwatch _frameClock = Stopwatch();

  void _start(ui.Size size) {
    try {
      final three = _three = tjr.ThreeJS(
        size: size,
        // Until the GL surface is up: the horizon's haze, not a white flash.
        loadingWidget:
            const ColoredBox(color: ui.Color(_clearHex | 0xFF000000)),
        onSetupComplete: () {
          _ready = true;
          if (mounted) setState(() {});
          widget.onReady?.call();
        },
        // The GL context would not start (a machine without the GL it
        // needs): the plain panel, as for a missing plugin; the game itself
        // keeps working.
        onStartFailed: (_) {
          if (_failed || !mounted) return;
          _failed = true;
          setState(() {});
          _failOver(size);
          widget.onFailed?.call();
        },
        settings: tjr.Settings(
          animate: true,
          enableShadowMap: true,
          shadowMapType: tjs.PCFSoftShadowMap,
          antialias: true,
          clearColor: _clearHex,
          clearAlpha: 1.0,
          toneMapping: tjs.ACESFilmicToneMapping,
          toneMappingExposure: 1.08,
        ),
        // The setup closure runs only after this field is assigned (it is
        // called from the package's async boot), so reading `_three` here
        // is safe.
        setup: () async {
          final owner = _three!;
          owner.scene = widget.world.scene;
          owner.camera = widget.world.camera;
          widget.world.setViewport(size);
          widget.world.fitCamera();
          // The renderer's own ticker: move the world to the frame's
          // truth, then the view draws it.
          owner.rendererUpdate = () {
            widget.world.applySnapshot(widget.buildFrame());
            owner.renderer?.toneMappingExposure = widget.world.exposure;
            widget.onFrame?.call();
            _pace(owner);
          };
        },
      );
      if (!mounted) {
        three.dispose();
        return;
      }
    } on Object {
      // A missing ANGLE plugin (or a headless surprise): fall back to the
      // plain panel; the game itself keeps working.
      _failed = true;
      _failOver(size);
      widget.onFailed?.call();
    }
  }

  /// Times the frames; when they run slow, draws fewer pixels.
  void _pace(tjr.ThreeJS three) {
    final seconds = _frameClock.elapsedMicroseconds / 1e6;
    _frameClock
      ..reset()
      ..start();
    final governor = _governor ??= PuttResolutionGovernor(three.dpr);
    final next = governor.frame(seconds);
    final size = _size;
    if (next == null || size == null) return;
    // The first slow stretch also drops the world to its low tier.
    widget.world.lowerQuality();
    three.setResolution(next);
    // After this frame: the surface resizes outside the render.
    Timer.run(() {
      if (mounted) unawaited(_resize(size));
    });
  }

  /// The parent's size changed: the GL surface, the renderer and the
  /// camera follow (one resize at a time; the latest size wins).
  Future<void> _resize(ui.Size size) async {
    _pendingSize = size;
    if (_resizing) return;
    _resizing = true;
    try {
      while (_pendingSize != null) {
        final next = _pendingSize!;
        _pendingSize = null;
        final three = _three;
        final texture = three?.texture;
        final renderer = three?.renderer;
        if (three == null || texture == null || renderer == null) break;
        three.screenSize = next;
        await three.angle?.resize(
          texture,
          AngleOptions(
            width: next.width.toInt(),
            height: next.height.toInt(),
            dpr: three.dpr,
          ),
        );
        renderer
          ..setPixelRatio(three.dpr)
          ..setSize(next.width, next.height);
        widget.world.setViewport(next);
        widget.world.fitCamera();
        if (mounted) setState(() {});
      }
    } on Object {
      // A surface that cannot resize keeps its old size; the game plays on.
    } finally {
      _resizing = false;
    }
  }

  @override
  void dispose() {
    _headless?.dispose();
    _three?.dispose();
    widget.world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, BoxConstraints constraints) {
      final size = constraints.biggest;
      if (!size.width.isFinite ||
          !size.height.isFinite ||
          size.width < 1 ||
          size.height < 1) {
        return const SizedBox.shrink();
      }
      if (PuttThreeSurface.gpuSupported && !_failed) {
        if (_three == null) {
          _size = size;
          _start(size);
        } else if (_size != size) {
          _size = size;
          if (_ready) unawaited(_resize(size));
        }
      }
      final three = _three;
      if (three == null || _failed) {
        return const ColoredBox(color: ui.Color(_clearHex | 0xFF000000));
      }
      return SizedBox(
        width: size.width,
        height: size.height,
        child: three.build(),
      );
    });
  }
}
