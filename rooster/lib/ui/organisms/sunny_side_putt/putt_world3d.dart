// The real-3D world of Sunny Side Putt, on the `three_js` engine: the flat
// diorama painter (the perspective-paint experiment of #233) replaced by an
// actual scene graph under a real perspective camera - lights with soft
// shadows, geometry for every obstacle, and eggs that ROLL, turning about
// the axis their velocity gives them.
//
// What lives here:
//   * [PuttWorld3D] - the scene graph, built headlessly from a
//     [`HoleDef`](../core/hole.dart): ground, walls, bumpers, water, portals,
//     wells, crates, decorations and the hen - geometry for everything the
//     physics already models, nothing drawn from data the engine does not
//     know. Every frame, [PuttWorld3D.applySnapshot] moves the meshes to the
//     engine's truth (positions, roll quaternions, the hop's lift, the
//     collected crates), breathes the time-driven bits (water's pulse, the
//     portals' glow, the crates' bob), and eases the camera rig toward its
//     follow point. No physics and no engine state here: the world consumes
//     a [PuttWorldFrame], so its tests run on plain frames with no GPU.
//   * [PuttCameraRig] - the orbit camera (yaw free, pitch clamped, wheel and
//     pinch zoom) fitted to a hole, eased one frame at a time, with the
//     world<->screen ray the aim's pointer plumbing walks. Same feel and
//     numbers the painted projection had (`PuttCamera`), expressed through
//     three_js's perspective camera (a 45-degree field of view).
//   * [PuttThreeSurface] - the GPU glue: the `three_js` renderer's widget
//     ([ThreeJS]) bound to this world, its render hook driving the snapshot.
//     The surface consults [PuttThreeSurface.gpuSupported] before starting
//     anything: the Flutter test runner has no GPU surface and no native
//     plugins, so tests boot the game and its HUD with the renderer never
//     coming up (a plain apron panel stands in its place).
//
// On web the renderer needs a WebGL2 context helper: `gles_bindings.js`,
// vendored (no CDN) in `rooster/web/` and loaded by a `<script>` in
// `rooster/web/index.html` - the package's own requirement, see the
// comment there.
//
// The eggs stay white ellipsoids with the player's tint as a band; the hen
// is a low-poly procedural chicken (body, head, beak, comb, eyes). Art
// values keep coming from the Rooster palette (`putt_art.dart`) plus the
// few shades the diorama derives - the same ones the flat painter used.
// Nothing here reads the clock or the network: the scene's time arrives
// with each frame.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Color, Offset, Size;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart'
    show BuildContext, ColoredBox, State, StatefulWidget, VoidCallback, Widget;
import 'package:three_js_angle_renderer/three_js_angle_renderer.dart' as tjr;
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:three_js_geometry/three_js_geometry.dart' as tjg;
import 'package:three_js_math/three_js_math.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'flutter_env_io.dart'
    if (dart.library.js_interop) 'flutter_env_stub.dart' as flutter_env;
import 'putt_art.dart';

// ---- shades derived from the Rooster palette (the flat painter's set) -------

/// The cream lawn's mown stripes alternate with this warmed stone tone.
const ui.Color _lawnDark = ui.Color(0xFFE9DDC9);

const ui.Color _spruceTop = ui.Color(0xFF3E5147); // spruce lit from above
const ui.Color _stoneDark = ui.Color(0xFF6E645B);
const ui.Color _hayBody = ui.Color(0xFFEDD9A3);
const ui.Color _hayTop = ui.Color(0xFFE3C98C);
const ui.Color _straw = ui.Color(0xFFD3831F);
const ui.Color _burrow = ui.Color(0xFF1D1512);
const ui.Color _nestCup = ui.Color(0xFF2A2118);

/// The world's sky and floor void: the apron, so the 3D view never fights
/// the widgets around it.
const int _apronHex = 0x26302A;

// ---- palette plumbing --------------------------------------------------------

/// three_js takes int hex without the alpha byte; the palette keeps ui.Color.
int _hexOf(ui.Color color) => color.toARGB32() & 0xFFFFFF;

tjs.Color _threeColor(ui.Color color) => tjs.Color.fromHex32(_hexOf(color));

int _redOf(ui.Color color) => (color.toARGB32() >> 16) & 0xFF;
int _greenOf(ui.Color color) => (color.toARGB32() >> 8) & 0xFF;
int _blueOf(ui.Color color) => color.toARGB32() & 0xFF;
int _alphaOf(ui.Color color) => (color.toARGB32() >> 24) & 0xFF;

// ---- the frame: what one rendered moment feeds the world ---------------------

/// One egg on the green, as the world needs it. The game builds these from
/// the engine's interpolated truth every rendered frame.
class PuttWorldEgg {
  final String playerId;
  final Vec2 position;

  /// Height above the green, 0 unless a hop is lifting the egg.
  final double height;

  /// The egg's velocity, which hands the roll its axis.
  final Vec2 velocity;
  final ui.Color tint;
  final double radius;

  const PuttWorldEgg({
    required this.playerId,
    required this.position,
    required this.velocity,
    required this.tint,
    required this.radius,
    this.height = 0,
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

  const PuttWorldAim({
    required this.origin,
    required this.angle,
    required this.power,
    required this.dragLength,
    required this.eggRadius,
  });
}

/// One particle of the bursts: the four kinds the flat renderer knew.
enum PuttWorldFxKind { droplet, sparkle, suction, poof }

class PuttWorldFx {
  final PuttWorldFxKind kind;
  final Vec2 at;

  /// Where a suction particle flies home to.
  final Vec2? toward;

  /// Age over life, 0..1.
  final double progress;
  final double size;
  final ui.Color? color;

  const PuttWorldFx({
    required this.kind,
    required this.at,
    required this.progress,
    required this.size,
    this.toward,
    this.color,
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

  const PuttWorldFrame({
    required this.time,
    this.eggs = const [],
    this.hens = const [],
    this.aim,
    this.fxs = const [],
    this.followPoint,
    this.collectedBoxes = const {},
  });
}

// ---- the camera rig -----------------------------------------------------------

/// The orbit camera: state, easing, and how it lands on the three_js
/// camera. Gestures ([orbitBy], [zoomByWheel], [pinch]) write targets,
/// [update] eases the live state toward them, [fitToHole] frames a hole and
/// clamps the zoom range. The target point trails the player's egg when the
/// game asks, and recentres when the hole changes.
///
/// The feel (and the numbers) carry over from the painted projection's
/// `PuttCamera`: pitch in degrees clamped into [pitchMin, pitchMax], the
/// camera hanging behind the target (upwind of the away axis, which yaw
/// turns), a 45-degree vertical field of view (what the old focal factor
/// of 1.2 projected), and the same easing constants.
class PuttCameraRig {
  PuttCameraRig({this.viewport = const ui.Size(800, 600)});

  static const double pitchMin = 35;
  static const double pitchMax = 70;
  static const double pitchDefault = 55;

  /// Vertical fov in degrees: 45 keeps the painted projection's scale (its
  /// focal length was 1.2 x the viewport height).
  static const double fovDeg = 45;

  /// The pixels the rig projects into, logical (the same space pointer
  /// events report in). The game sets this on resize.
  ui.Size viewport;

  /// The orbit angle around the vertical, radians; unbounded, new drags
  /// add to it.
  double yaw = 0;

  /// The tilt from the ground plane, degrees, in [pitchMin, pitchMax].
  double pitchDeg = pitchDefault;

  /// The depth from the camera to the target along the look axis, in
  /// world units - the zoom handle.
  double distance = 30;

  /// The ground point under the middle of the screen (game coordinates).
  Vec2 target = Vec2.zero;

  double _yawTarget = 0;
  double _pitchTarget = pitchDefault;
  double _distanceTarget = 30;
  Vec2 _targetTarget = Vec2.zero;

  double _distanceMin = 8;
  double _distanceMax = 160;

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
    // Standing props and billboards add a fixed margin around the green;
    // a finger's width of the viewport stays free. The wanted distance is
    // the painted camera's: focal (1.2 x the viewport height) over the
    // tighter axis' pixels-per-unit.
    const margin = 5.0;
    final usableWidth = math.max(1.0, viewport.width - 24);
    final usableHeight = math.max(1.0, viewport.height - 24);
    final focal = viewport.height * 1.2;
    final wanted = math.max(
      focal * (spanRight + margin) / usableWidth,
      focal * (spanAway * sp + margin + 2.2) / usableHeight,
    );
    _distanceMin = 0.55 * maxSpan;
    _distanceMax = 2.8 * maxSpan;
    _distanceTarget = wanted.clamp(_distanceMin, _distanceMax).toDouble();
    _targetTarget = bounds.center;
    if (_snapNext) snap();
  }

  /// Orbit: [dxPixels] of horizontal drag turn the yaw, [dyPixels] tilt
  /// the pitch (clamped). Dragging down looks from higher above.
  void orbitBy(double dxPixels, double dyPixels) {
    _yawTarget += dxPixels * 0.006;
    _pitchTarget = (_pitchTarget + dyPixels * 0.11).clamp(pitchMin, pitchMax);
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

  /// The zoom clamp [fitToHole] last set (world units); tests read them.
  double get distanceMin => _distanceMin;
  double get distanceMax => _distanceMax;

  /// Ease one frame. [followPoint] glides the target toward the active
  /// egg; null holds the target where it is.
  void update(double dt, {Vec2? followPoint}) {
    if (followPoint != null) _targetTarget = followPoint;
    if (_snapNext) snap();
    const yawSpeed = 7.0;
    const pitchSpeed = 8.0;
    const distanceSpeed = 5.0;
    const targetSpeed = 6.0;
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

  /// Copy every target into the live state at once (also the boot snap).
  void snap() {
    yaw = _yawTarget;
    pitchDeg = _pitchTarget;
    distance = _distanceTarget.clamp(_distanceMin, _distanceMax).toDouble();
    target = _targetTarget;
    _snapNext = false;
  }

  /// Where the camera stands for the current rig state, in the world's
  /// ground frame: the game's x stays world x, the game's y (y down)
  /// becomes world z, and heights lift along world y. The camera hangs
  /// behind the target - opposite the away axis the yaw turns - at the
  /// drop the painted projection used.
  tjs.Vector3 cameraPositionOf(Vec2 targetPoint) {
    final pitch = pitchDeg * math.pi / 180;
    final cp = math.max(math.cos(pitch), 0.15);
    final sp = math.sin(pitch);
    final awayX = math.sin(yaw);
    final awayZ = math.cos(yaw);
    return tjs.Vector3(
      targetPoint.x - awayX * distance / cp,
      distance * sp,
      targetPoint.y - awayZ * distance / cp,
    );
  }

  /// Lands the rig on the three_js camera: position, then the look at the
  /// (ground-level) target.
  void applyTo(tjs.PerspectiveCamera camera) {
    camera.position.setFrom(cameraPositionOf(target));
    camera.lookAt(tjs.Vector3(target.x, 0, target.y));
  }
}

// ---- the world -----------------------------------------------------------------

/// The green as three_js geometry. Build one per game; build holes; feed
/// frames; dispose when done. Constructing, building holes and applying
/// snapshots are pure Dart - only [PuttThreeSurface] touches the GPU path.
class PuttWorld3D {
  PuttWorld3D({ui.Size viewport = const ui.Size(800, 600)})
      : rig = PuttCameraRig(viewport: viewport) {
    _setUpCamera();
    _setUpLights();
    scene
      ..add(_holeRoot = tjs.Group()..name = 'hole')
      ..add(_actorsRoot = tjs.Group()..name = 'actors')
      ..add(_aimRoot = tjs.Group()..name = 'aim')
      ..add(_fxRoot = tjs.Group()..name = 'fx');
    _aim = _PuttAimView3D(eggRadius: _eggRadius);
    _aimRoot.add(_aim.group);
    // The ground's fill: a hemisphere's sky over soil, no shadow work. The
    // sun comes with each hole (its shadow camera frames the green).
    _ambient = tjs.HemisphereLight(0xFFF3DF, _hexOf(PuttPalette.apron), 0.9);
    scene.add(_ambient);
  }

  final tjs.Scene scene = tjs.Scene();
  final tjs.PerspectiveCamera camera = tjs.PerspectiveCamera(
    PuttCameraRig.fovDeg,
    800 / 600,
    0.4,
    600,
  );
  final PuttCameraRig rig;

  late final tjs.Group _holeRoot;
  late final tjs.Group _actorsRoot;
  late final tjs.Group _aimRoot;
  late final tjs.Group _fxRoot;
  late final tjs.HemisphereLight _ambient;

  tjs.DirectionalLight? _sun;

  /// Textures the world itself owns (one lawn, one crate face, one fx
  /// disc): disposed with the world, never shared outside it.
  final List<tjs.DataTexture> _owned = [];

  /// The "?" crates' face texture, stamped on the first hole with boxes.
  tjs.DataTexture? _crateTexture;

  /// The per-kind groups the hole's geometry builds into; the tests walk
  /// these by name.
  final List<tjs.Group> _kindGroups = [];

  HoleDef? _hole;
  double _eggRadius = 0.45;

  late final _PuttAimView3D _aim;

  final Map<String, _EggView3D> _eggViews = {};
  final List<_HenView3D> _henViews = [];
  final List<_CrateView3D> _crateViews = [];
  final List<tjs.Mesh> _waterMeshes = [];
  final List<tjs.Mesh> _portalGlows = [];

  final _PuttFxPool _fx = _PuttFxPool();

  double _lastTime = 0;
  bool _firstFrame = true;
  bool _disposed = false;

  HoleDef? get hole => _hole;

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
    _aimPortalSun(hole);
  }

  // ---- lights and camera ------------------------------------------------------------

  void _setUpCamera() {
    camera.aspect = rig.aspect;
    camera.updateProjectionMatrix();
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
  }

  void _setUpLights() {
    // The warm sun, with its shadow work.
    final sun = tjs.DirectionalLight(0xFFF2DC, 2.2);
    sun.castShadow = true;
    final shadow = sun.shadow!;
    shadow.mapSize.setValues(1024, 1024);
    shadow.bias = -0.0008;
    shadow.normalBias = 0.03;
    shadow.radius = 4;
    scene.add(sun);
    scene.add(sun.target!);
    _sun = sun;
  }

  /// Plants the sun over the current hole so its shadow camera covers the
  /// green, and hangs the fog off the hole's span.
  void _aimPortalSun(HoleDef hole) {
    final sun = _sun;
    if (sun == null) return;
    final center = tjs.Vector3(hole.bounds.center.x, 0, hole.bounds.center.y);
    sun.target!.position.setFrom(center);
    sun.position.setFrom(center).add(tjs.Vector3(7, 15, -5));
    final span = math.max(hole.bounds.width, hole.bounds.height);
    final half = span * 0.62 + 6;
    final shadowCam = sun.shadow!.camera;
    if (shadowCam != null) {
      shadowCam
        ..left = -half
        ..right = half
        ..top = half
        ..bottom = -half
        ..near = 0.5
        ..far = 150;
      shadowCam.updateProjectionMatrix();
    }
    // Depth: the far end of the green dissolving gently into the void.
    scene.fog = tjs.Fog(_apronHex, span * 2.2, span * 7);
  }

  // ---- hole construction --------------------------------------------------------------

  /// Builds (or rebuilds) the hole's geometry. A hole whose id is already
  /// up keeps its meshes; a new one disposes the old subtree first.
  void buildHole(HoleDef hole, {required double eggRadius}) {
    if (_disposed) return;
    if (_hole?.id == hole.id) return;
    _clearHole();
    _hole = hole;
    _eggRadius = eggRadius;

    tjs.Group makeKind(String name) {
      final group = tjs.Group()..name = name;
      _kindGroups.add(group);
      _holeRoot.add(group);
      return group;
    }

    makeKind('ground').add(_groundMesh(hole));
    final walls = makeKind('walls');
    final bumpers = makeKind('bumpers');
    for (final wall in hole.walls) {
      if (wall.bumper) {
        _collectBumperWall(wall, bumpers);
      } else {
        walls.add(_wallBox(wall.a, wall.b));
      }
    }
    final arcs = makeKind('arcs');
    for (final arc in hole.arcs) {
      _buildArc(arc, bumpers, arcs);
    }
    final wells = makeKind('wells');
    for (final well in hole.wells) {
      wells.add(_wellGroup(well));
    }
    final water = makeKind('water');
    for (final shape in hole.water) {
      water.add(_waterMesh(shape));
    }
    final portals = makeKind('portals');
    for (final pair in hole.portals) {
      portals.add(_portal(pair.a, pair.radius, phaseSeconds: 0));
      portals.add(_portal(pair.b, pair.radius, phaseSeconds: 1.6));
    }
    final boxes = makeKind('boxes');
    for (final box in hole.boxes) {
      // The crate face texture is the world's own (stamped once, disposed
      // with the world); crates of every hole of the world share it.
      if (_crateTexture == null) {
        _crateTexture = _stampQuestion();
        _owned.add(_crateTexture!);
      }
      final crate = _CrateView3D(box, _crateTexture!);
      boxes.add(crate.group);
      _crateViews.add(crate);
    }
    final decorations = makeKind('decorations');
    for (final decoration in hole.decorations) {
      final built = _decoration(decoration);
      if (built != null) decorations.add(built);
    }
    final hens = makeKind('hens');
    for (final obstacle in hole.obstacles) {
      final hen = _HenView3D(obstacle);
      hens.add(hen.group);
      _henViews.add(hen);
    }

    _fx.reset(_fxRoot);
    _firstFrame = true;
    fitCamera();
  }

  /// Disposes the whole hole subtree and forgets every per-hole view.
  void _clearHole() {
    _disposeChildren(_holeRoot);
    _henViews.clear();
    _crateViews.clear();
    _waterMeshes.clear();
    _portalGlows.clear();
    _kindGroups.clear();
    _hole = null;
    _crateTexture?.dispose();
    _crateTexture = null;
    _fx.reset(_fxRoot);
  }

  /// The green: one plane carrying the procedural lawn texture (mown
  /// stripes, the walked line, the tee cup, the nest zone, the cut edge).
  tjs.Mesh _groundMesh(HoleDef hole) {
    final bounds = hole.bounds;
    final ground = tjs.Mesh(
      tjs.PlaneGeometry(bounds.width, bounds.height, 1, 1),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: _lawnTexture(hole),
        tjs.MaterialProperty.roughness: 1.0,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'lawn'
      // The plane's +z normal tips up to +y.
      ..rotation.x = -math.pi / 2
      ..position.setValues(bounds.center.x, 0, bounds.center.y)
      ..receiveShadow = true;
    return ground;
  }

  /// The two-tone lawn: mown stripes walked across the green, the walked
  /// line from tee to nest, the tee's cup, the nest's straw ring over its
  /// dark cup, and the green's ink cut edge - all stamped into one RGBA
  /// texture, sized to the hole. The tee and the nest zone are marked on
  /// the ground, as the flat painter did.
  tjs.DataTexture _lawnTexture(HoleDef hole) {
    final bounds = hole.bounds;
    final dx = math.max(bounds.width, 0.001);
    final dz = math.max(bounds.height, 0.001);
    const perUnit = 3.0;
    final width = (dx * perUnit).round().clamp(24, 128).toInt();
    final height = (dz * perUnit).round().clamp(24, 128).toInt();
    final data = Uint8List(width * height * 4);
    final teeRadius = math.max(_eggRadius * 1.5, 0.65);
    final nest = hole.nest;
    const stripe = 2.3;
    final toNest = nest.position - hole.tee;
    final nestDir = toNest.normalized(toNest);
    final toNestLength = toNest.length;

    for (var row = 0; row < height; row++) {
      // UV row 0 meets the green's south edge: PlaneGeometry maps its
      // local +y to world -z, so the texture walks rows the other way.
      final v = (row + 0.5) / height;
      final y = bounds.min.y + (1 - v) * dz;
      for (var col = 0; col < width; col++) {
        final u = (col + 0.5) / width;
        final point = Vec2(bounds.min.x + u * dx, y);
        var color = ((y - bounds.min.y) / stripe).floor() % 2 == 0
            ? PuttPalette.cream
            : _lawnDark;

        // The walked line from tee to nest, a soft band down the middle.
        if (toNestLength > 0.5) {
          final along =
              (point - hole.tee).dot(nestDir).clamp(0.0, toNestLength);
          final distance = point.distanceTo(hole.tee + nestDir * along);
          final mask = _softBand(distance, 0.55, 0.16);
          if (mask > 0) {
            color =
                _blend(color, _lawnDark.withValues(alpha: 0.75), mask * 0.6);
          }
        }

        // The tee cup: a cream disc ringed in ink.
        final teeDistance = point.distanceTo(hole.tee);
        final teeMask = _softBand(teeDistance, teeRadius, 0.12);
        if (teeMask > 0) color = _blend(color, PuttPalette.cream, teeMask);
        final teeEdge = _softBand(teeDistance, teeRadius + 0.1, 0.08) -
            _softBand(teeDistance, teeRadius - 0.08, 0.08);
        if (teeEdge > 0) color = _blend(color, PuttPalette.ink, teeEdge);

        // The nest zone: a straw ring over the dark want-in-there cup.
        final nestDistance = point.distanceTo(nest.position);
        final strawMask = _softBand(nestDistance, nest.radius * 1.25, 0.14) -
            _softBand(nestDistance, nest.radius * 0.6, 0.1);
        if (strawMask > 0) {
          final shade =
              (math.sin(point.x * 3.1 + point.y * 2.7) * 0.5 + 0.5) > 0.5
                  ? PuttPalette.yolk
                  : _straw;
          color = _blend(color, shade, strawMask * 0.9);
        }
        final cupMask = _softBand(nestDistance, nest.radius * 0.68, 0.1);
        if (cupMask > 0) color = _blend(color, _nestCup, cupMask);

        // The cut edge: the green's ink rim.
        final rim = math.min(
          math.min(point.x - bounds.min.x, bounds.max.x - point.x),
          math.min(point.y - bounds.min.y, bounds.max.y - point.y),
        );
        final rimMask = _softBand(rim, 0.28, 0.22);
        if (rimMask > 0) color = _blend(color, PuttPalette.ink, rimMask * 0.85);

        final index = (row * width + col) * 4;
        data[index] = _redOf(color);
        data[index + 1] = _greenOf(color);
        data[index + 2] = _blueOf(color);
        data[index + 3] = 255;
      }
    }
    final texture = tjs.DataTexture(data, width, height)
      ..needsUpdate = true
      ..magFilter = tjs.LinearFilter
      ..minFilter = tjs.LinearFilter
      ..colorSpace = tjs.SRGBColorSpace;
    _owned.add(texture);
    return texture;
  }

  /// A wall: the hedge box the physics sees, a bit above the green.
  tjs.Group _wallBox(Vec2 a, Vec2 b) {
    const height = 1.35;
    final dx = b.x - a.x;
    final dz = b.y - a.y;
    final length = math.sqrt(dx * dx + dz * dz);
    final group = tjs.Group()
      ..name = 'wall'
      // The wall runs a to b: long local x, so turn by the run's angle
      // (the game's y-down angle reads a negative world turn about y).
      ..rotation.y = -math.atan2(dz, dx)
      ..position.setValues((a.x + b.x) / 2, 0, (a.y + b.y) / 2);
    final body = tjs.Mesh(
      tjs.BoxGeometry(length, height, 0.5),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.spruce),
      }),
    )
      ..name = 'wall-body'
      ..position.y = height / 2
      ..castShadow = true
      ..receiveShadow = true;
    final cap = tjs.Mesh(
      tjs.BoxGeometry(length, 0.05, 0.54),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(_spruceTop),
      }),
    )
      ..name = 'wall-cap'
      ..position.y = height / 2 + 0.03
      ..receiveShadow = true;
    group.add(body);
    group.add(cap);
    return group;
  }

  /// A bumper wall: short red drums riding the line the egg bounces off.
  void _collectBumperWall(WallSegment wall, tjs.Group bumpers) {
    final length = wall.a.distanceTo(wall.b);
    final count = math.max(1, (length / 1.7).floor());
    for (var i = 0; i < count; i++) {
      final at = wall.a + (wall.b - wall.a) * ((i + 0.5) / count);
      bumpers.add(_bumperPost(at, 0.5, 0.6));
    }
  }

  void _buildArc(WallArc arc, tjs.Group bumpers, tjs.Group arcs) {
    final fullCircle = arc.sweep >= 2 * math.pi - 0.01;
    if (arc.bumper) {
      // A ring of short red drums stepping the arc - the collider, in
      // posts.
      final steps = (arc.sweep * arc.radius / 1.7).ceil().clamp(2, 48).toInt();
      for (var i = 0; i < steps; i++) {
        final angle = arc.startAngle + (i + 0.5) / steps * arc.sweep;
        final at = Vec2(
          arc.center.x + math.cos(angle) * arc.radius,
          arc.center.y + math.sin(angle) * arc.radius,
        );
        bumpers.add(
          _bumperPost(at, arc.radius.clamp(0.28, 0.55).toDouble(), 0.6),
        );
      }
      return;
    }
    if (fullCircle) {
      arcs.add(_rock(arc.center, arc.radius));
      return;
    }
    // A hedge run bent along the arc: the same boxes, stepped around.
    final steps = (arc.sweep * arc.radius / 1.1).ceil().clamp(1, 48).toInt();
    for (var i = 0; i < steps; i++) {
      final a0 = arc.startAngle + i / steps * arc.sweep;
      final a1 = arc.startAngle + (i + 1) / steps * arc.sweep;
      final a = Vec2(
        arc.center.x + math.cos(a0) * arc.radius,
        arc.center.y + math.sin(a0) * arc.radius,
      );
      final b = Vec2(
        arc.center.x + math.cos(a1) * arc.radius,
        arc.center.y + math.sin(a1) * arc.radius,
      );
      arcs.add(_wallBox(a, b));
    }
  }

  /// A short red drum with the yolk ring on its top face.
  tjs.Group _bumperPost(Vec2 at, double radius, double height) {
    final group = tjs.Group()
      ..name = 'bumper'
      ..position.setValues(at.x, 0, at.y);
    final body = tjs.Mesh(
      tjg.CylinderGeometry(radius, radius, height, 14),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.comb),
      }),
    )
      ..name = 'bumper-body'
      ..position.y = height / 2
      ..castShadow = true
      ..receiveShadow = true;
    final ring = tjs.Mesh(
      tjg.TorusGeometry(radius * 0.62, 0.055, 6, 18),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.yolk),
      }),
    )
      ..name = 'bumper-ring'
      // Flat on the drum's top face.
      ..rotation.x = math.pi / 2
      ..position.y = height;
    group.add(body);
    group.add(ring);
    return group;
  }

  /// A stone dome: a squashed sphere sunk a touch into the green.
  tjs.Mesh _rock(Vec2 at, double radius) {
    final mesh = tjs.Mesh(
      tjs.SphereGeometry(radius, 18, 12),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(_stoneDark),
      }),
    )
      ..name = 'rock'
      ..scale.setValues(1, 0.6, 1)
      ..position.setValues(at.x, radius * 0.42, at.y)
      ..castShadow = true
      ..receiveShadow = true;
    return mesh;
  }

  /// The silo: the ground work of the pull (reach disc, swallow mouth)
  /// and the tank standing over it, band-ringed.
  tjs.Group _wellGroup(GravityWell well) {
    final group = tjs.Group()
      ..name = 'well'
      ..position.setValues(well.position.x, 0, well.position.y);

    final reach = tjs.Mesh(
      tjg.CircleGeometry(radius: well.radius, segments: 36),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.ink),
        tjs.MaterialProperty.opacity: 0.08,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'well-reach'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.02;
    final mouth = tjs.Mesh(
      tjg.CircleGeometry(radius: well.swallowRadius * 1.2, segments: 28),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(_burrow),
      }),
    )
      ..name = 'well-mouth'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03;

    final tankRadius = well.radius * 0.3 + 0.2;
    final tankHeight = well.radius * 0.45 + 1.2;
    final tank = tjs.Mesh(
      tjg.CylinderGeometry(tankRadius, tankRadius, tankHeight, 20),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.stone),
      }),
    )
      ..name = 'silo-tank'
      ..position.y = tankHeight / 2
      ..castShadow = true
      ..receiveShadow = true;
    final bands = tjs.Group()..name = 'silo-bands';
    for (final at in const [0.45, 0.7]) {
      final band = tjs.Mesh(
        tjg.TorusGeometry(tankRadius + 0.02, 0.04, 6, 24),
        tjs.MeshLambertMaterial({
          tjs.MaterialProperty.color: _hexOf(_stoneDark),
        }),
      )
        ..name = 'silo-band'
        ..rotation.x = math.pi / 2
        ..position.y = tankHeight * at;
      bands.add(band);
    }
    group.add(reach);
    group.add(mouth);
    group.add(tank);
    group.add(bands);
    return group;
  }

  /// Water: a slab sunk a touch below the green, its own blue that pulses
  /// gently (the emissive breathes from the snapshot's clock).
  tjs.Mesh _waterMesh(WaterShape shape) {
    final (geometry, center) = switch (shape) {
      WaterCircle(:final center, :final radius) => (
          tjg.CircleGeometry(radius: radius, segments: 36)
              as tjs.BufferGeometry,
          center,
        ),
      WaterRect(:final rect) => (
          tjs.PlaneGeometry(rect.width, rect.height, 1, 1)
              as tjs.BufferGeometry,
          rect.center,
        ),
      WaterPolygon(:final points) => (
          _polygonGeometry(points),
          _centroid(points),
        ),
    };
    final material = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.color: _hexOf(PuttPalette.water),
      tjs.MaterialProperty.roughness: 0.25,
      tjs.MaterialProperty.metalness: 0.0,
      tjs.MaterialProperty.transparent: true,
      tjs.MaterialProperty.opacity: 0.85,
      tjs.MaterialProperty.emissive: _hexOf(PuttPalette.waterDeep),
    });
    // The pulse (the emissive's breath) rides the snapshot's clock.
    material.emissiveIntensity = 0.15;
    final mesh = tjs.Mesh(geometry, material)
      ..name = 'water'
      ..rotation.x = -math.pi / 2
      ..position.setValues(center.x, -0.06, center.y);
    _waterMeshes.add(mesh);
    return mesh;
  }

  /// A portal pair's one end: the dark burrow disc plus the glowing torus
  /// rim; the rim's pulse carries [phaseSeconds]' offset so a pair
  /// breathes apart.
  tjs.Group _portal(
    Vec2 at,
    double radius, {
    required double phaseSeconds,
  }) {
    final group = tjs.Group()
      ..name = 'portal'
      ..position.setValues(at.x, 0, at.y)
      // The pulse phase rides userData: only applySnapshot reads it.
      ..userData['pulsePhase'] = phaseSeconds;
    final burrow = tjs.Mesh(
      tjg.CircleGeometry(radius: radius, segments: 28),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(_burrow),
      }),
    )
      ..name = 'portal-hole'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03;
    final glow = tjs.Mesh(
      tjg.TorusGeometry(radius * 1.06, 0.09, 8, 32),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.cream),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.8,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'portal-glow'
      ..position.y = 0.05;
    _portalGlows.add(glow);
    group.add(burrow);
    group.add(glow);
    return group;
  }

  tjs.Object3D? _decoration(Decoration decoration) {
    switch (decoration.kind) {
      case 'hay':
      case 'hay_bale':
        return _hayBale(decoration.at, decoration.numbers['size'] ?? 1.0);
      case 'fence':
        return _fence(decoration);
      default:
        // Unknown tags rest as a pebble, so nothing smuggles in unseen.
        return _rock(decoration.at, 0.25);
    }
  }

  /// A hay bale: a fat amber roll lying on the yard.
  tjs.Group _hayBale(Vec2 at, double scale) {
    final group = tjs.Group()
      ..name = 'hay-bale'
      ..position.setValues(at.x, 0, at.y);
    final roll = tjs.Mesh(
      tjg.CylinderGeometry(0.85 * scale, 0.85 * scale, 1.7 * scale, 18),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(_hayBody),
      }),
    )
      ..name = 'hay-roll'
      // Lying down: the cylinder's axis along the world's x.
      ..rotation.z = math.pi / 2
      ..position.y = 0.85 * scale
      ..castShadow = true
      ..receiveShadow = true;
    final face = tjs.Mesh(
      tjg.CircleGeometry(radius: 0.78 * scale, segments: 18),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(_hayTop),
      }),
    )
      ..name = 'hay-face'
      ..position.setValues(0.87 * scale, 0.85 * scale, 0)
      ..rotation.y = math.pi / 2;
    group.add(roll);
    group.add(face);
    return group;
  }

  /// A fence line: spruce posts with two rails, marching +x from the
  /// decoration's spot (the same `posts`/`length` numbers the painted
  /// fence read).
  tjs.Group _fence(Decoration decoration) {
    final posts = (decoration.numbers['posts'] ?? 5).round();
    final spacing = decoration.numbers['length'] ?? 1.4;
    final at = decoration.at;
    final group = tjs.Group()
      ..name = 'fence'
      ..position.setValues(at.x, 0, at.y);
    for (final railHeight in const [0.62, 0.28]) {
      final rail = tjs.Mesh(
        tjs.BoxGeometry((posts - 1) * spacing, 0.08, 0.07),
        tjs.MeshLambertMaterial({
          tjs.MaterialProperty.color: _hexOf(PuttPalette.spruce),
        }),
      )
        ..name = 'fence-rail'
        ..position.setValues((posts - 1) * spacing / 2, railHeight, 0)
        ..castShadow = true;
      group.add(rail);
    }
    for (var i = 0; i < posts; i++) {
      final post = tjs.Mesh(
        tjs.BoxGeometry(0.16, 0.85, 0.16),
        tjs.MeshLambertMaterial({
          tjs.MaterialProperty.color: _hexOf(PuttPalette.spruce),
        }),
      )
        ..name = 'fence-post'
        ..position.setValues(i * spacing, 0.85 / 2, 0)
        ..castShadow = true
        ..receiveShadow = true;
      group.add(post);
    }
    return group;
  }

  // ---- the snapshot -----------------------------------------------------------------

  /// Reads one frame: pools egg meshes by player id, rolls them by their
  /// velocity, lifts the hops, waddles the hens, stands collected crates
  /// down, breathes the water and the portals, and glides the camera.
  void applySnapshot(PuttWorldFrame frame) {
    if (_disposed) return;
    final dt = _firstFrame
        ? 0.0
        : (frame.time - _lastTime).clamp(0.0, 0.05).toDouble();
    _lastTime = frame.time;
    _firstFrame = false;

    _syncEggs(frame, dt);
    _syncHens(frame);
    _syncCrates(frame);
    _aim.sync(frame.aim);
    _fx.apply(frame);
    _syncScenery(frame);
    rig.update(math.max(dt, 1 / 240), followPoint: frame.followPoint);
    rig.applyTo(camera);
    camera.updateMatrixWorld(true);
  }

  void _syncEggs(PuttWorldFrame frame, double dt) {
    final seen = <String>{};
    for (final egg in frame.eggs) {
      seen.add(egg.playerId);
      final view = _eggViews.putIfAbsent(egg.playerId, () {
        final created = _EggView3D(egg.radius);
        _actorsRoot.add(created.group);
        return created;
      });
      view.retint(egg.tint);
      view.sync(egg, dt);
    }
    _eggViews.removeWhere((playerId, view) {
      if (seen.contains(playerId)) return false;
      _actorsRoot.remove(view.group);
      view.dispose();
      return true;
    });
  }

  void _syncHens(PuttWorldFrame frame) {
    for (var i = 0; i < _henViews.length && i < frame.hens.length; i++) {
      _henViews[i].sync(frame.hens[i]);
    }
  }

  void _syncCrates(PuttWorldFrame frame) {
    for (final crate in _crateViews) {
      crate.setVisible(!frame.collectedBoxes.contains(crate.id));
      // The carton's gentle breath (the painted lid's bob, on the box):
      // shows the crate from across the green.
      final breathe = math.sin(frame.time * 2.4 + crate.bobPhase);
      crate.group.position.y = (breathe * 0.5 + 0.5) * crate.box.radius * 0.12;
    }
  }

  /// The time-driven scenery: water's emissive breath, the portals' glow.
  void _syncScenery(PuttWorldFrame frame) {
    final time = frame.time;
    for (final mesh in _waterMeshes) {
      final material = mesh.material;
      if (material is tjs.MeshStandardMaterial) {
        material.emissiveIntensity =
            0.1 + 0.12 * (0.5 + 0.5 * math.sin(time * 2.1));
      }
    }
    for (final glow in _portalGlows) {
      final phase = glow.parent?.userData['pulsePhase'] as double? ?? 0;
      final material = glow.material;
      if (material != null) {
        material.opacity =
            0.55 + 0.32 * (0.5 + 0.5 * math.sin((time - phase) * 3.1));
      }
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
    dir.scale(t);
    final hit = camera.position.clone().add(dir);
    return Vec2(hit.x, hit.z);
  }

  /// The surface pixel a ground point projects to, through the same ray
  /// [screenToWorld] walks: the aim's pointer plumbing and the e2e's drag
  /// math both lean on the read. [height] lifts the point toward the
  /// camera (a hop's lift).
  ui.Offset projectToWorld(Vec2 world, {double height = 0}) {
    if (_disposed || rig.viewport.width <= 0 || rig.viewport.height <= 0) {
      return ui.Offset.zero;
    }
    camera.updateMatrixWorld(true);
    final point = tjs.Vector3(world.x, height, world.y).project(camera);
    return ui.Offset(
      (point.x + 1) / 2 * rig.viewport.width,
      (1 - point.y) / 2 * rig.viewport.height,
    );
  }

  /// Frees every geometry, material and owned texture in the world, the
  /// camera included. Safe to call twice; the GPU surface calls it after
  /// the renderer is down.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owned.add(_fx.texture); // the fx sprites' disc dies with the world
    scene.dispose(); // walks the children, then marks the scene itself
    camera.dispose();
    for (final texture in _owned) {
      texture.dispose();
    }
    _owned.clear();
    _eggViews.clear();
    _hole = null;
  }

  static void _disposeChildren(tjs.Object3D parent) {
    for (final child in [...parent.children]) {
      parent.remove(child);
      child.dispose();
    }
  }
}

// ---- geometry plating helpers --------------------------------------------------------------

/// A flat polygon on the ground plane standing in the world's z, built as
/// a triangle fan around [points]' centroid. Water polygons and the like
/// are simple; if an author sends a non-convex shape, the fan still shows
/// a reasonable body (the physics measures the same points).
tjs.BufferGeometry _polygonGeometry(List<Vec2> points) {
  if (points.length < 3) return tjs.BufferGeometry();
  final center = _centroid(points);
  final positions = <double>[];
  final normals = <double>[];
  for (var i = 0; i < points.length; i++) {
    final p0 = points[i];
    final p1 = points[(i + 1) % points.length];
    // The fan's triangles wound so the face points up (+y).
    positions.addAll([center.x, 0, center.y]);
    positions.addAll([p0.x, 0, p0.y]);
    positions.addAll([p1.x, 0, p1.y]);
    normals.addAll([0, 1, 0, 0, 1, 0, 0, 1, 0]);
  }
  return tjs.BufferGeometry()
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false));
}

Vec2 _centroid(List<Vec2> points) {
  if (points.isEmpty) return Vec2.zero;
  var x = 0.0;
  var y = 0.0;
  for (final point in points) {
    x += point.x;
    y += point.y;
  }
  return Vec2(x / points.length, y / points.length);
}

/// A mask that is 1 inside [inner], 0 past [outer] ([inner] grown by
/// [softness]), soft between - the texture stamp's antialiasing.
double _softBand(double distance, double inner, double softness) {
  if (softness <= 0) return distance <= inner ? 1 : 0;
  if (distance <= inner - softness) return 1;
  if (distance >= inner + softness) return 0;
  final t = (inner + softness - distance) / (2 * softness);
  return t * t * (3 - 2 * t); // smoothstep
}

/// Blends [over] onto [base] by [t], channel-wise.
ui.Color _blend(ui.Color base, ui.Color over, double t) {
  return ui.Color.fromARGB(
    (_alphaOf(base) + (_alphaOf(over) - _alphaOf(base)) * t).round(),
    (_redOf(base) + (_redOf(over) - _redOf(base)) * t).round(),
    (_greenOf(base) + (_greenOf(over) - _greenOf(base)) * t).round(),
    (_blueOf(base) + (_blueOf(over) - _blueOf(base)) * t).round(),
  );
}

/// The "?" egg-carton face: cream carton with the comb question mark, the
/// dimples and the ink edge, drawn straight into RGBA bytes (no fonts,
/// nothing platform-bound). One texture per world, stamped by the caller.
tjs.DataTexture _stampQuestion() {
  const size = 64;
  final data = Uint8List(size * size * 4);
  // A cream carton with a comb-red "?" and the ink edge.
  for (var i = 0; i < size * size; i++) {
    final index = i * 4;
    data[index] = _redOf(PuttPalette.cream);
    data[index + 1] = _greenOf(PuttPalette.cream);
    data[index + 2] = _blueOf(PuttPalette.cream);
    data[index + 3] = 255;
  }
  const glyph = [
    '.####.',
    '##..##',
    '...##.',
    '..##..',
    '..##..',
    '......',
    '..##..',
    '..##..',
  ];
  const cell = 5.0;
  final left = (size - glyph[0].length * cell) / 2;
  final top = (size - glyph.length * cell) / 2;
  for (var row = 0; row < glyph.length; row++) {
    for (var col = 0; col < glyph[row].length; col++) {
      if (glyph[row][col] != '#') continue;
      _stampRect(data, size, left + col * cell, top + row * cell,
          cell: cell, color: PuttPalette.comb);
    }
  }
  // The ink edge, two texels wide, fading on the corners.
  for (var row = 0; row < size; row++) {
    for (var col = 0; col < size; col++) {
      final edge = math.min(
        math.min(col.toDouble(), (size - 1 - col).toDouble()),
        math.min(row.toDouble(), (size - 1 - row).toDouble()),
      );
      final mask = _softBand(edge, 1.2, 1.4);
      if (mask <= 0) continue;
      final index = (row * size + col) * 4;
      data[index] =
          (data[index] * (1 - mask) + _redOf(PuttPalette.ink) * mask).round();
      data[index + 1] =
          (data[index + 1] * (1 - mask) + _greenOf(PuttPalette.ink) * mask)
              .round();
      data[index + 2] =
          (data[index + 2] * (1 - mask) + _blueOf(PuttPalette.ink) * mask)
              .round();
    }
  }
  // Carton dimples: soft darker dots inside the face.
  for (final (px, py) in const [
    (10.0, 10.0),
    (54.0, 10.0),
    (10.0, 54.0),
    (54.0, 54.0),
    (32.0, 8.0),
  ]) {
    _stampDimple(data, size, px, py, 2.6);
  }
  final texture = tjs.DataTexture(data, size, size)
    ..needsUpdate = true
    ..magFilter = tjs.LinearFilter
    ..minFilter = tjs.LinearFilter
    ..colorSpace = tjs.SRGBColorSpace;
  return texture;
}

/// A soft rectangular stamp of [color] into an RGBA byte buffer.
void _stampRect(
  Uint8List data,
  int size,
  double x,
  double y, {
  required double cell,
  required ui.Color color,
}) {
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min((x + cell).ceil(), size);
  final y1 = math.min((y + cell).ceil(), size);
  for (var py = y0; py < y1; py++) {
    for (var px = x0; px < x1; px++) {
      final index = (py * size + px) * 4;
      data[index] = _redOf(color);
      data[index + 1] = _greenOf(color);
      data[index + 2] = _blueOf(color);
      data[index + 3] = 255;
    }
  }
}

/// A soft darker dot (the carton's dimple).
void _stampDimple(Uint8List data, int size, double x, double y, double r) {
  final x0 = math.max(0, (x - r).floor());
  final x1 = math.min(size - 1, (x + r).ceil());
  final y0 = math.max(0, (y - r).floor());
  final y1 = math.min(size - 1, (y + r).ceil());
  for (var py = y0; py <= y1; py++) {
    for (var px = x0; px <= x1; px++) {
      final d = math.sqrt((px - x) * (px - x) + (py - y) * (py - y));
      if (d > r) continue;
      final t = (1 - d / r).clamp(0.0, 1.0) * 0.35;
      final index = (py * size + px) * 4;
      data[index] = (data[index] * (1 - t)).round();
      data[index + 1] = (data[index + 1] * (1 - t)).round();
      data[index + 2] = (data[index + 2] * (1 - t)).round();
    }
  }
}

// ---- actors' views --------------------------------------------------------------------------

/// One egg on the green: the white ellipsoid (a scaled sphere) hanging in
/// a group the roll's quaternion turns, plus the player's tint ring. The
/// group sits at the egg's ground spot; the roll accumulates in world
/// space so the ellipsoid tips exactly where it goes.
class _EggView3D {
  factory _EggView3D(double radius) {
    final group = tjs.Group()..name = 'egg';
    final material = tjs.MeshLambertMaterial({
      tjs.MaterialProperty.color: _hexOf(PuttPalette.shell),
      tjs.MaterialProperty.emissive: _hexOf(PuttPalette.shell),
    });
    // A whisper of light so eggs never sit muddy in the shade.
    material.emissiveIntensity = 0.12;
    final body = tjs.Mesh(tjs.SphereGeometry(radius, 18, 12), material)
      ..name = 'egg-shell'
      // The ellipsoid: egg-taller than wide, standing on its short axis.
      ..scale.setValues(1, 1.28, 1)
      ..castShadow = true;
    final band = tjs.Mesh(
      tjg.TorusGeometry(radius * 0.94, radius * 0.09, 6, 20),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.yolk),
      }),
    )
      ..name = 'egg-band'
      // A band about the egg's waist, up a third of the ellipsoid.
      ..rotation.x = math.pi / 2
      ..position.y = radius * 1.28 * 0.35;
    group.add(body);
    group.add(band);
    return _EggView3D._(radius, group, body, band);
  }

  _EggView3D._(this._radius, this.group, this.body, this.band);

  /// The stand height: the ellipsoid's short axis rests on the green.
  double get standHeight => _radius * 1.28;

  final double _radius;
  final tjs.Group group;
  final tjs.Mesh body;
  final tjs.Mesh band;

  void retint(ui.Color tint) {
    final material = band.material;
    if (material is tjs.MeshBasicMaterial) {
      material.color.setFrom(_threeColor(tint));
    }
  }

  /// The stand (ground spot plus the hop's lift), then the roll: world
  /// axis from the horizontal velocity, omega = |v| / r, pre-multiplied
  /// so world space holds the accumulated spin - the egg tips exactly
  /// where it goes.
  void sync(PuttWorldEgg egg, double dt) {
    group.position.setValues(
      egg.position.x,
      standHeight + egg.height,
      egg.position.y,
    );
    final speed = egg.speed;
    if (speed < 1e-4 || dt <= 0 || egg.radius <= 0) return;
    final axis = tjs.Vector3(egg.velocity.x, 0, egg.velocity.y);
    if (axis.length < 1e-6) return;
    axis.normalize();
    // Rolling toward +x spins about -z: the wheel axis is up x velocity.
    final rollAxis = tjs.Vector3(0, 1, 0).cross(axis);
    if (rollAxis.length < 1e-6) return;
    rollAxis.normalize();
    final delta =
        tjs.Quaternion().setFromAxisAngle(rollAxis, speed * dt / egg.radius);
    group.quaternion.premultiply(delta);
  }

  void dispose() {
    body.geometry?.dispose();
    body.material?.dispose();
    band.geometry?.dispose();
    band.material?.dispose();
    group.dispose();
  }
}

/// The hen: the low-poly procedural chicken - body sphere, head sphere,
/// yolk beak cone, comb, eyes - driven by the same path the engine moves
/// her on (the snapshot carries the position; here only the mesh work:
/// facing the walk, the waddle's bob).
class _HenView3D {
  _HenView3D(MovingObstacle obstacle) {
    final radius = obstacle.radius;
    group = tjs.Group()..name = 'hen/${obstacle.id}';
    final body = tjs.Mesh(
      tjs.SphereGeometry(radius, 14, 10),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.shell),
      }),
    )
      ..name = 'hen-body'
      ..scale.setValues(radius, radius * 0.95, radius * 1.15)
      ..position.y = radius * 0.95
      ..castShadow = true;
    final head = tjs.Mesh(
      tjs.SphereGeometry(radius * 0.5, 12, 8),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.shell),
      }),
    )
      ..name = 'hen-head'
      ..position.setValues(0, radius * 1.6, radius * 1.05)
      ..castShadow = true;
    final beak = tjs.Mesh(
      tjg.ConeGeometry(radius * 0.2, radius * 0.45, 8),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.yolk),
      }),
    )
      ..name = 'hen-beak'
      // The cone's tip rests on its +y; tip it forward over the head.
      ..rotation.x = math.pi / 2
      ..position.setValues(0, radius * 1.55, radius * 1.05 + radius * 0.65);
    final comb = tjs.Mesh(
      tjs.BoxGeometry(radius * 0.42, radius * 0.3, radius * 0.18),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.comb),
      }),
    )
      ..name = 'hen-comb'
      ..position.setValues(0, radius * 2.05, radius * 1.0);
    group.add(body);
    group.add(head);
    group.add(beak);
    group.add(comb);
    for (final side in const [-1.0, 1.0]) {
      final eye = tjs.Mesh(
        tjs.SphereGeometry(radius * 0.08, 6, 6),
        tjs.MeshBasicMaterial({
          tjs.MaterialProperty.color: _hexOf(PuttPalette.ink),
        }),
      )
        ..name = 'hen-eye'
        ..position
            .setValues(side * radius * 0.34, radius * 1.68, radius * 1.42);
      group.add(eye);
    }
  }

  late final tjs.Group group;
  Vec2 _heading = const Vec2(0, 1);

  /// The stand (with the waddle's bob), and the facing: the last
  /// non-stop direction she had, as a turn about the world's y.
  void sync(PuttWorldHen hen) {
    if (hen.heading.length > 1e-4) {
      _heading = hen.heading;
      group.rotation.y = -math.atan2(_heading.y, _heading.x);
    }
    group.position.setValues(
      hen.position.x,
      math.sin(hen.phase * math.pi).abs() * 0.08,
      hen.position.y,
    );
  }
}

/// The "?" crate: a cream carton with the mark on its faces, bobbing with
/// the clock until its id lands in the frame's collected set.
class _CrateView3D {
  _CrateView3D(this.box, this.texture) {
    final half = box.radius * 0.7;
    final height = box.radius * 1.5;
    group = tjs.Group()
      ..name = 'crate/${box.id}'
      ..position.setValues(box.position.x, 0, box.position.y);
    final body = tjs.Mesh(
      tjs.BoxGeometry(half * 2, height, half * 2),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: texture,
        tjs.MaterialProperty.roughness: 0.9,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'crate-body'
      ..position.y = height / 2
      ..castShadow = true
      ..receiveShadow = true;
    group.add(body);
  }

  final QuestionBox box;
  final tjs.DataTexture texture;
  late final tjs.Group group;

  /// A per-crate offset so two cartons never breathe in sync (never
  /// changes for a crate's life, computed once).
  late final double bobPhase = () {
    var phase = 0.0;
    for (final code in box.id.codeUnits) {
      phase = (phase + code) % 17;
    }
    return phase;
  }();

  String get id => box.id;

  void setVisible(bool visible) {
    group.visible = visible;
  }
}

// ---- the aim, in 3D -------------------------------------------------------------------------

/// The aim's 3D read: the ghost of the pull behind the egg, the faint
/// power ring with its yolk arc filling from the north, the comb shaft
/// and the ink head - standing a hair above the green so they never sink
/// into it, turned to the (already wobbling) drawn angle.
class _PuttAimView3D {
  _PuttAimView3D({required double eggRadius}) : _eggRadius = eggRadius {
    group = tjs.Group()
      ..name = 'aim'
      ..visible = false;

    ghost = tjs.Mesh(
      tjs.BoxGeometry(1, 0.016, 0.1),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.water),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.35,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'aim-ghost'
      ..position.y = 0.02;
    group.add(ghost);

    ring = tjs.Mesh(
      tjg.TorusGeometry(eggRadius * 1.9, 0.035, 6, 40),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.ink),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.25,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'aim-ring'
      // Flat on the green.
      ..rotation.x = math.pi / 2
      ..position.y = 0.04;
    group.add(ring);

    shaft = tjs.Mesh(
      tjs.BoxGeometry(1, 0.05, 0.13),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.comb),
      }),
    )
      ..name = 'aim-shaft'
      ..position.y = 0.06;
    group.add(shaft);

    head = tjs.Mesh(
      tjg.ConeGeometry(0.3, 0.6, 10),
      tjs.MeshLambertMaterial({
        tjs.MaterialProperty.color: _hexOf(PuttPalette.ink),
      }),
    )
      ..name = 'aim-head'
      // The cone's +y tip turns to lie flat pointing +x.
      ..rotation.z = -math.pi / 2
      ..position.y = 0.06;
    group.add(head);
  }

  late final tjs.Group group;
  late final tjs.Mesh ghost;
  late final tjs.Mesh ring;
  late final tjs.Mesh shaft;
  late final tjs.Mesh head;

  tjs.Mesh? _fill;
  double _fillPower = -1;
  final double _eggRadius;

  /// Shows the aim for this frame, or hides the group. The fill arc's
  /// geometry rebuilds only when the power moved enough to see.
  void sync(PuttWorldAim? aim) {
    if (aim == null) {
      group.visible = false;
      return;
    }
    group.visible = true;
    // The game's y-down angle reads a negative world turn about y.
    group.rotation.y = -aim.angle;
    group.position.setValues(aim.origin.x, 0.01, aim.origin.y);

    final scale = aim.eggRadius / _eggRadius;
    final length = (1.5 + aim.power * 4.5) * scale;
    shaft.scale.x = length;
    shaft.position.x = length / 2;
    head.position.x = length + 0.3 * scale;

    final pull = math.min(aim.dragLength, length / scale) * scale;
    ghost.scale.x = math.max(pull, 0.001);
    ghost.position.x = -pull / 2;

    if ((aim.power - _fillPower).abs() > 0.015) {
      _fillPower = aim.power;
      final oldFill = _fill;
      if (oldFill != null) {
        group.remove(oldFill);
        oldFill.geometry?.dispose();
        oldFill.material?.dispose();
      }
      final fill = tjs.Mesh(
        tjg.TorusGeometry(
          aim.eggRadius * 1.9,
          0.05,
          6,
          (24 * math.max(aim.power, 0.05)).ceil().clamp(3, 48).toInt(),
          math.max(aim.power * 2 * math.pi, 0.05),
        ),
        tjs.MeshBasicMaterial({
          tjs.MaterialProperty.color: _hexOf(PuttPalette.yolk),
          tjs.MaterialProperty.transparent: true,
          tjs.MaterialProperty.opacity: 0.95,
          tjs.MaterialProperty.depthWrite: false,
        }),
      )
        ..name = 'aim-fill'
        // Flattened, then spun so the arc starts at the world's -z (the
        // game's north) and sweeps toward +x as power grows - the same
        // fill-from-the-top read the painted arrow had.
        ..rotation.set(math.pi / 2, 0, math.pi / 2)
        ..position.y = 0.05;
      group.add(fill);
      _fill = fill;
    }
  }

  /// Frees the fill's geometry (the shared material belongs to the world).
  void dispose() {
    _fill?.geometry?.dispose();
    _fill?.material?.dispose();
    group.dispose();
  }
}

/// The camera seam the e2e (and anything reading the aim's pixels) uses:
/// world points projected to surface pixels through the world's own
/// perspective - the read the painted `view3d` gave, on the real camera.
class PuttCameraSeam {
  final PuttWorld3D _world;

  const PuttCameraSeam(this._world);

  /// The surface pixel a world point (lifted by [height]) projects to.
  ui.Offset project(Vec2 world, {double height = 0}) =>
      _world.projectToWorld(world, height: height);
}

// ---- fx -------------------------------------------------------------------------------------

/// The bursts: splash droplets, suction rings, poofs, pickup sparkles - as
/// pooled sprites over a soft procedural disc, tinted and faded per frame.
class _PuttFxPool {
  static const int poolSize = 48;

  final List<tjs.Sprite> _sprites = [];
  tjs.DataTexture? _disc;

  /// The pool's one texture (world-owned): the world's dispose kills it
  /// via its owned list; a fresh pool stamps a new disc.
  tjs.DataTexture get texture => _disc ??= _stampDisc();

  void reset(tjs.Group parent) {
    for (final sprite in [..._sprites]) {
      parent.remove(sprite);
      sprite.material?.dispose();
      sprite.dispose();
    }
    _sprites.clear();
    final discTexture = texture;
    for (var i = 0; i < poolSize; i++) {
      final sprite = tjs.Sprite(
        tjs.SpriteMaterial({
          tjs.MaterialProperty.map: discTexture,
          tjs.MaterialProperty.color: 0xFFFFFF,
          tjs.MaterialProperty.transparent: true,
          tjs.MaterialProperty.opacity: 0.0,
          tjs.MaterialProperty.depthWrite: false,
        }),
      )
        ..name = 'fx'
        ..visible = false;
      parent.add(sprite);
      _sprites.add(sprite);
    }
  }

  /// Places this frame's fx onto the pooled sprites; the rest hide.
  void apply(PuttWorldFrame frame) {
    var active = 0;
    for (final fx in frame.fxs) {
      if (active >= poolSize) break;
      final progress = fx.progress.clamp(0.0, 1.0);
      final sprite = _sprites[active++];
      sprite.visible = true;

      // Where, and how high off the green.
      Vec2 at = fx.at;
      double lift;
      double diameter;
      final color = fx.color ?? PuttPalette.yolk;
      final opacity = (1 - progress) * 0.75;
      switch (fx.kind) {
        case PuttWorldFxKind.droplet:
          lift = 0.55 * math.sin(progress * math.pi);
          diameter = fx.size * (0.6 + 0.5 * progress);
        case PuttWorldFxKind.sparkle:
          lift = 0.35 + 0.45 * math.sin(progress * math.pi);
          diameter = fx.size * (0.5 + 1.1 * math.sin(progress * math.pi).abs());
        case PuttWorldFxKind.suction:
          final toward = fx.toward ?? fx.at;
          at = fx.at +
              (toward + const Vec2(0.2, 0.2) - fx.at) * (progress * progress);
          lift = 0.12;
          diameter = math.max(fx.size * (1 - progress), 0.02);
        case PuttWorldFxKind.poof:
          lift = 0.1;
          diameter = math.max(fx.size * (1 + progress), 0.02);
      }
      sprite.position.setValues(at.x, lift, at.y);
      sprite.scale.setValues(diameter, diameter, 1);
      final material = sprite.material;
      if (material is tjs.SpriteMaterial) {
        material.color.setFrom(_threeColor(color));
        material.opacity = opacity;
      }
    }
    for (var i = active; i < _sprites.length; i++) {
      _sprites[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
  }

  /// A soft round blob, white so tinting does the colour.
  static tjs.DataTexture _stampDisc() {
    const size = 32;
    final data = Uint8List(size * size * 4);
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final dx = col + 0.5 - size / 2;
        final dy = row + 0.5 - size / 2;
        final d = math.sqrt(dx * dx + dy * dy) / (size / 2);
        final core = (1 - d).clamp(0.0, 1.0);
        final alpha = (core * core * 255).round().clamp(0, 255);
        final index = (row * size + col) * 4;
        data[index] = 255;
        data[index + 1] = 255;
        data[index + 2] = 255;
        data[index + 3] = alpha;
      }
    }
    final texture = tjs.DataTexture(data, size, size)
      ..needsUpdate = true
      ..magFilter = tjs.LinearFilter
      ..minFilter = tjs.LinearFilter;
    return texture;
  }
}

// ---- the GPU surface ------------------------------------------------------------------------

/// The widget that hosts the three_js renderer bound to a [PuttWorld3D]:
/// the package's [ThreeJS] view running the world's scene and camera, its
/// render hook moving the world to each frame's truth before drawing.
///
/// Where no GPU surface can come up (the Flutter test runner), the widget
/// paints the apron plain and the game keeps ticking its match headlessly,
/// exactly as the widget tests expect.
class PuttThreeSurface extends StatefulWidget {
  final PuttWorld3D world;

  /// Builds the frame the world moves to, once per rendered frame (the
  /// game's read of the match's interpolated truth).
  final PuttWorldFrame Function() buildFrame;

  /// Setup-complete and failure taps for the hosting view.
  final VoidCallback? onReady;
  final VoidCallback? onFailed;

  const PuttThreeSurface({
    super.key,
    required this.world,
    required this.buildFrame,
    this.onReady,
    this.onFailed,
  });

  /// Whether the renderer can come up here. Web only needs WebGL2. On
  /// native, the ANGLE surface needs the platform's plugins - the Flutter
  /// test runner has neither (its process carries no GL symbols and the
  /// plugin channels stand empty), so it reports false: the view shows
  /// the apron panel and the tests run headless.
  static bool get gpuSupported =>
      kIsWeb || !flutter_env.runningUnderFlutterTest;

  @override
  State<PuttThreeSurface> createState() => _PuttThreeSurfaceState();
}

class _PuttThreeSurfaceState extends State<PuttThreeSurface> {
  tjr.ThreeJS? _three;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (PuttThreeSurface.gpuSupported) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final three = _three = tjr.ThreeJS(
        onSetupComplete: () {
          if (mounted) setState(() {});
          widget.onReady?.call();
        },
        settings: tjr.Settings(
          animate: true,
          enableShadowMap: true,
          shadowMapType: tjs.PCFSoftShadowMap,
          antialias: true,
          clearColor: _apronHex,
          clearAlpha: 1.0,
        ),
        // The setup closure runs only after this field is assigned (it is
        // called from the package's async boot), so reading `_three` here
        // is safe.
        setup: () async {
          final owner = _three!;
          owner.scene = widget.world.scene;
          owner.camera = widget.world.camera;
          // The renderer's own ticker: move the world to the frame's
          // truth, then the view draws it.
          owner.rendererUpdate =
              () => widget.world.applySnapshot(widget.buildFrame());
        },
      );
      // The engine resizes its own texture and camera on window metrics;
      // keep the rig's aspect (and the fit) honest alongside it.
      three.windowResizeUpdate = (size) {
        widget.world.setViewport(size);
        widget.world.fitCamera();
      };
      if (!mounted) {
        three.dispose();
        widget.world.dispose();
        return;
      }
      setState(() {});
    } on Object {
      // A missing ANGLE plugin (or a headless surprise): fall back to the
      // apron panel; the game itself keeps working.
      if (mounted) setState(() => _failed = true);
      widget.onFailed?.call();
    }
  }

  @override
  void dispose() {
    _three?.dispose();
    widget.world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final three = _three;
    if (three == null || _failed) {
      return const ColoredBox(color: ui.Color(_apronHex | 0xFF000000));
    }
    return three.build();
  }
}
