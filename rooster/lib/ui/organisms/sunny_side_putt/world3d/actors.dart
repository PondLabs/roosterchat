// The actors: the eggs (a true egg profile turned on a lathe, painted with
// an Easter band in the player's colour, rolling by their velocity and
// settling on their side when they stop, a soft contact shadow under them
// and, under the viewer's own, a marker ring and a bobbing arrow), the hen
// (legs that walk, a head that bobs), and the "?" crates floating over
// their glow.
part of '../putt_world3d.dart';

/// The egg's height over its radius: the long axis' half-length.
const double _eggAspect = 1.28;

/// The drawn egg runs a little bigger than the physics' disc, so it reads
/// from the camera's height; at a rail the overlap stays a sliver.
const double _eggVisualScale = 1.2;

/// An egg the nest just took: it slides to the cup's middle and sinks.
class _SinkingEgg {
  _SinkingEgg(this.view, this.nest);

  static const double life = 0.42;

  final _EggView3D view;
  final Vec2 nest;
  double age = 0;
}

/// One egg on the green. Its [group] carries the roll (position and
/// quaternion); [ground] stays level under it with the shadow and the
/// viewer's marker; [trail] holds the puffs a fast egg leaves behind.
class _EggView3D {
  _EggView3D(this._radius, ui.Color tint,
      {required int trailHex,
      required this.onBounce,
      _Ground? terrain,
      int glow = 0x2A2622})
      : terrain = terrain ?? _Ground(),
        _glow = glow {
    group = tjs.Group()..name = 'egg';
    _tintHex = _hexOf(tint);
    _texture = _eggTextureFor(_tintHex);
    body = tjs.Mesh(_eggGeometry(_radius), _shellMaterial(_texture, _glow))
      ..name = 'egg-shell'
      ..castShadow = true;
    group.add(body);
    // The egg's silhouette through whatever hides it (a rail, the silo, a
    // hay bale): drawn only where something nearer already stands.
    final xrayMaterial = tjs.MeshBasicMaterial({
      tjs.MaterialProperty.color: _lin(_mix(_tintHex, 0xFFFFFF, 0.25)),
      tjs.MaterialProperty.transparent: true,
      tjs.MaterialProperty.opacity: 0.5,
      tjs.MaterialProperty.depthWrite: false,
      tjs.MaterialProperty.fog: false,
    })
      ..depthFunc = tjs.GreaterDepth;
    _xray = tjs.Mesh(body.geometry, xrayMaterial)
      ..name = 'egg-xray'
      ..renderOrder = 20;
    body.add(_xray);
    // The ink outline (the shell's back faces, a size up): the eggs are the
    // characters, drawn with a line round them so they pop from the farm
    // at any distance. The world sets its weight from the camera's.
    _outline = tjs.Mesh(
      body.geometry,
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.ink)),
        tjs.MaterialProperty.side: tjs.BackSide,
        // Transparent from the start, like the shell: a Ghost Egg fades
        // them by their opacity alone, and no program ever recompiles.
        tjs.MaterialProperty.transparent: true,
      }),
    )..name = 'egg-outline';
    body.add(_outline);
    outlineFor(24);

    ground = tjs.Group()..name = 'egg-ground';
    _shadow = tjs.Mesh(
      tjg.CircleGeometry(radius: _radius * 1.15, segments: 24),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.map: _shadowTexture,
        tjs.MaterialProperty.color: _lin(0x1A140E),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.55,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'egg-shadow'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.02
      ..renderOrder = 2;
    // Every egg sits on a soft disc of its player's colour: who is who
    // reads from the ground even when the band faces away.
    _tintDisc = tjs.Mesh(
      tjg.RingGeometry(_radius * 0.95, _radius * 1.4, 32, 1),
      _unlit(_tintHex, opacity: _tintDiscOpacity, depthWrite: false),
    )
      ..name = 'egg-tint-disc'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.025
      ..renderOrder = 2;
    _marker = tjs.Mesh(
      tjg.RingGeometry(_radius * 1.55, _radius * 1.85, 36, 1),
      _unlit(_tintHex, opacity: 0.9, depthWrite: false),
    )
      ..name = 'egg-marker'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03
      ..renderOrder = 3
      ..visible = false;
    // The viewer's pin over the egg: a round yolk cone, tip down, inside an
    // ink outline (its back faces, a size up), so it reads from any angle.
    // Drawn last and over everything (the transparent pass, no depth
    // test): no egg in front ever hides where the viewer's egg is.
    _arrow = tjs.Mesh(
      tjg.ConeGeometry(_radius * 0.6, _radius * 1.3, 24),
      _matte(_hexOf(PuttPalette.yolk), roughness: 0.45)
        ..transparent = true
        ..depthTest = false,
    )
      ..name = 'egg-arrow'
      // Tip down, toward the egg.
      ..rotation.x = math.pi
      ..castShadow = false
      ..renderOrder = 22
      ..visible = false;
    _arrow.add(tjs.Mesh(
      tjg.ConeGeometry(_radius * 0.6, _radius * 1.3, 24),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.ink)),
        tjs.MaterialProperty.side: tjs.BackSide,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.depthTest: false,
      }),
    )
      ..name = 'egg-arrow-outline'
      ..renderOrder = 21
      ..scale.setValues(1.22, 1.14, 1.22));
    ground
      ..add(_shadow)
      ..add(_tintDisc)
      ..add(_marker)
      ..add(_arrow);
    trail = tjs.Group()..name = 'egg-trail';
    // Turf flecks kicked up behind it, darker than the grass.
    final trailColor = _lin(trailHex);
    for (var i = 0; i < _trailLength; i++) {
      final puff = _Billboard(map: _shadowTexture, color: trailColor)
        ..name = 'egg-trail-puff'
        ..visible = false
        ..renderOrder = 3;
      _puffs.add(puff);
      trail.add(puff);
    }
    // The Thick Shell's bubble, facing the camera round the egg (it rides
    // the unturned trail group, the shell's roll would turn it away).
    _bubble = _Billboard(map: _bubbleMap, color: _lin(_bubbleHexOf(_tintHex)))
      ..name = 'egg-bubble'
      ..visible = false
      ..renderOrder = 11;
    trail.add(_bubble);
  }

  /// The bubble's colour for an egg of [tint]: a pale sky with a touch of
  /// the player's own.
  static int _bubbleHexOf(int tint) => _mix(0xFFFFFF, tint, 0.18);

  /// The soap-film disc every egg's bubble wears (shared, like the
  /// shadow's disc).
  static final tjs.DataTexture _bubbleMap = _bubbleTexture();

  late final _Billboard _bubble;

  /// How long the bubble has been up (it blows up when the shell comes).
  double _bubbleAge = 0;

  /// The shell's opacity now: 1 solid, lower while a Ghost Egg lasts or
  /// while it stands aside for the viewer's egg.
  double _ghostOpacity = 1;

  /// Whether this egg stands in front of the viewer's resting egg on the
  /// screen (the world says, each frame): it fades to a ghost of itself,
  /// so the viewer's egg, its pin and the aim read through it.
  bool screening = false;

  /// How far it has faded for that, 0 to 1 (eased over a fifth of a
  /// second).
  double _screened = 0;

  static const int _trailLength = 18;

  /// Told when the egg slams into something (a rail, a bumper, another
  /// egg): where, how hard (0..1), and whether it is the viewer's.
  final void Function(Vec2 at, double strength, bool mine) onBounce;

  /// The ground the egg stands on (its hills).
  final _Ground terrain;

  /// Whether this egg has ever been the viewer's own (the frame marks it
  /// only while its shot is ready).
  bool everMine = false;

  late final tjs.Mesh _tintDisc;
  late final tjs.Mesh _xray;
  late final tjs.Mesh _outline;

  /// The outline's weight for a camera [distance] away: about the same
  /// width on screen near or far.
  void outlineFor(double distance) {
    final k = 1 + (0.03 + distance * 0.0026).clamp(0.05, 0.15);
    _outline.scale.setValues(k, k, k);
  }

  Vec2? _lastVelocity;
  double _squash = 0;

  late final tjs.Group trail;
  final List<_Billboard> _puffs = [];

  /// The trail's recent spots and their ages, newest last.
  final List<(Vec2, double)> _trailSpots = [];
  double _sinceSpot = 0;

  /// Where the egg stood last frame, and how high its centre rode at rest
  /// (the sink starts from both).
  Vec2 lastPosition = Vec2.zero;
  double get restHeight => _radius * _eggAspect;

  late final tjs.Group group;
  late final tjs.Group ground;
  late final tjs.Mesh body;
  late final tjs.Mesh _shadow;
  late final tjs.Mesh _marker;
  late final tjs.Mesh _arrow;
  late tjs.DataTexture _texture;
  late int _tintHex;

  final double _radius;

  /// Seconds the egg has been still, and whether it ever rolled (an egg
  /// fresh on the tee stands up; one that has rolled lies on its side).
  double _still = 0;
  bool _rolled = false;

  /// The ground the egg is drawn on and how fast that drawn ground sinks:
  /// it follows rising ground at once and sinking ground no faster than a
  /// fall, so off a ledge's lip the egg drops through the air (null until
  /// the first frame).
  double? _floor;
  double _sinkSpeed = 0;

  /// The fall's pull, units/s^2: a drop of one unit takes a third of a
  /// second, which reads as a fall at the egg's size.
  static const double _gravity = 18;

  /// The shadow's soft disc, shared by every egg of every world.
  static final tjs.DataTexture _shadowTexture = _discTexture(hardness: 1.4);

  void retint(ui.Color tint) {
    final hex = _hexOf(tint);
    if (hex == _tintHex) return;
    _tintHex = hex;
    // The shared texture for that colour, on a fresh material: no texture
    // is made or freed mid-play, and no compiled material has its map
    // swapped under it (the renderer once drew such an egg not at all).
    _texture = _eggTextureFor(hex);
    final old = body.material;
    body.material = _shellMaterial(_texture, _glow);
    old?.map = null;
    old?.emissiveMap = null;
    old?.dispose();
    _marker.material?.color = _lin(hex);
    _tintDisc.material?.color = _lin(hex);
    _xray.material?.color = _lin(_mix(hex, 0xFFFFFF, 0.25));
    _bubble.look.color = _lin(_bubbleHexOf(hex));
    _ghostOpacity = -1; // the fresh shell takes the fade on the next frame
  }

  /// The shell: the colour's paint, a soft sheen, and a whisper of light
  /// so eggs never sit muddy in the shade. The light takes the paint's
  /// colours: at dusk the shell stays white and the band glows in the
  /// player's colour.
  static tjs.MeshStandardMaterial _shellMaterial(
      tjs.DataTexture paint, int glow) {
    final material = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.map: paint,
      tjs.MaterialProperty.emissiveMap: paint,
      tjs.MaterialProperty.roughness: 0.36,
      tjs.MaterialProperty.metalness: 0.0,
      // Transparent from the start (opacity 1, depth still written): a
      // Ghost Egg only moves the opacity, so no program recompiles mid-play.
      tjs.MaterialProperty.transparent: true,
    });
    material.emissive = _lin(glow);
    return material;
  }

  /// The shell's own light (the theme's: warmer and stronger at dusk, so
  /// a white egg stays white in the blue hour).
  final int _glow;

  /// The stand (ground spot plus the hop's lift), then the roll: world
  /// axis from the horizontal velocity, omega = |v| / r, pre-multiplied so
  /// world space holds the accumulated spin - the egg tips exactly where it
  /// goes. Still, it eases onto its side, the way an egg rests.
  void sync(PuttWorldEgg egg, double dt, double time) {
    final speed = egg.speed;
    if (egg.mine) everMine = true;
    // The viewer's egg draws after the aim (which skips the depth test, so
    // no other egg hides it): the arrow comes out from under this one.
    final order = egg.mine ? 10 : 0;
    if (body.renderOrder != order) {
      body.renderOrder = order;
      _outline.renderOrder = order;
    }
    // A bounce: the heading swings hard in one frame while it is quick.
    final last = _lastVelocity;
    if (last != null && dt > 0) {
      final before = last.length;
      if (before > 2.2 && speed > 0.5) {
        final turn = last.dot(egg.velocity) / (before * speed);
        if (turn < 0.82) {
          final strength = ((before - 2.2) / 10).clamp(0.0, 1.0);
          _squash = 0.6 + strength * 0.4;
          onBounce(egg.position, strength, everMine);
        }
      } else if (before < 0.3 && speed > 4) {
        // The putt itself: a stretch as it leaves.
        _squash = 0.5;
      }
    }
    _lastVelocity = egg.velocity;
    if (_squash > 0) {
      _squash = math.max(0, _squash - dt / 0.16);
      final k = math.sin(_squash * math.pi) * 0.16;
      body.scale.setValues(1 + k, 1 - k, 1 + k);
    } else {
      body.scale.setValues(1, 1, 1);
    }
    if (speed > 1e-4 && dt > 0 && egg.radius > 0) {
      final axis = tjs.Vector3(egg.velocity.x, 0, egg.velocity.y);
      if (axis.length > 1e-6) {
        axis.normalize();
        // Rolling toward +x spins about -z: the wheel axis is up x velocity.
        final rollAxis = tjs.Vector3(0, 1, 0).cross(axis);
        if (rollAxis.length > 1e-6) {
          rollAxis.normalize();
          final delta =
              tjs.Quaternion().setFromAxisAngle(rollAxis, speed * dt / _radius);
          group.quaternion.premultiply(delta);
          _rolled = true;
        }
      }
      _still = 0;
    } else {
      _still += dt;
    }
    if (_rolled && _still > 0.05 && dt > 0) _settle(dt);

    // The lowest point of the (roughly ellipsoidal) shell under this
    // orientation: the world's up read in the egg's own frame.
    final up =
        tjs.Vector3(0, 1, 0).applyQuaternion(group.quaternion.clone().invert());
    final a = _radius;
    final h = _radius * _eggAspect;
    final support = math
        .sqrt(a * a * up.x * up.x + h * h * up.y * up.y + a * a * up.z * up.z);
    final floor = terrain.at(egg.position);
    final drawn = _fallTo(floor, egg.position, dt);
    group.position.setValues(
        egg.position.x, drawn + support + egg.height, egg.position.y);

    lastPosition = egg.position;
    _syncTrail(egg, dt);

    // The ground pieces: the shadow shrinks and fades as a hop or a fall
    // lifts the egg off it; on a slope they lie along it.
    ground.position.setValues(egg.position.x, floor, egg.position.y);
    if (!terrain.flat) ground.quaternion.setFrom(terrain.tiltAt(egg.position));
    final lift = ((egg.height + drawn - floor) / (_radius * 3)).clamp(0.0, 1.0);
    final shadowScale = 1 - lift * 0.45;
    _shadow.scale.setValues(shadowScale, shadowScale, 1);
    // A ghost's shadow thins with it.
    _shadow.material?.opacity =
        0.55 * (1 - lift * 0.6) * (0.35 + 0.65 * _ghostOpacity.clamp(0.0, 1.0));

    _syncBubble(egg, dt, time, drawn + support + egg.height);
    _syncGhost(egg, time, dt);

    final resting = speed < 0.05;
    final showMarker = egg.mine && resting;
    _marker.visible = showMarker;
    _arrow.visible = showMarker;
    if (showMarker) {
      final pulse = 0.5 + 0.5 * math.sin(time * 4);
      final s = 1 + pulse * 0.08;
      _marker.scale.setValues(s, s, 1);
      _marker.material?.opacity = 0.65 + 0.3 * pulse;
      _arrow.position.y = h * 2 + 0.6 + math.sin(time * 3.2).abs() * 0.35;
    }
  }

  /// The Thick Shell's bubble: blown up round the egg when the shield
  /// comes, wobbling like a soap film while it holds; gone the frame the
  /// shield is spent (the game pops it in shards).
  void _syncBubble(PuttWorldEgg egg, double dt, double time, double centre) {
    if (!egg.shielded) {
      _bubbleAge = 0;
      _bubble.visible = false;
      return;
    }
    _bubbleAge += dt;
    final blow = (_bubbleAge / 0.3).clamp(0.0, 1.0);
    // Out with a little overshoot, then the film's slow wobble.
    final grow = blow < 1 ? 1.15 * math.sin(blow * math.pi * 0.62) : 1.0;
    final wobble = math.sin(time * 3.4) * 0.035;
    final size = _radius * 4.4 * grow;
    _bubble
      ..visible = true
      ..position.setValues(egg.position.x, centre, egg.position.y)
      ..scale.setValues(size * (1 + wobble), size * (1 - wobble), 1);
    _bubble.look.opacity = 0.95;
  }

  /// A Ghost Egg: the shell and its ink go see-through and flicker while
  /// it lasts, blinking back toward solid as it runs out; its shadow
  /// thins. Opacity only - every material was made transparent at build.
  void _syncGhost(PuttWorldEgg egg, double time, double dt) {
    var target = 1.0;
    final left = egg.ghostSeconds;
    if (left > 0) {
      final wave = 0.5 + 0.5 * math.sin(time * 7.3) * math.sin(time * 2.9 + 1);
      target = 0.26 + 0.22 * wave;
      if (left < 0.9) {
        // The last beat: it blinks back toward solid.
        final blink = math.sin(time * 26) > 0 ? 1.0 : 0.0;
        target += (0.95 - target) * blink * (1 - left / 0.9);
      }
    }
    // Standing aside for the viewer's egg: a third of itself, still there.
    _screened = (_screened + (screening ? dt : -dt) * 5).clamp(0.0, 1.0);
    target *= 1 - 0.66 * _screened;
    if ((target - _ghostOpacity).abs() < 1e-3) return;
    _ghostOpacity = target;
    body.material?.opacity = target;
    _outline.material?.opacity = target >= 1 ? 1 : target * 0.7;
    _xray.material?.opacity = 0.5 * target;
    _tintDisc.material?.opacity = _tintDiscOpacity * (0.45 + 0.55 * target);
    body.castShadow = target > 0.9;
  }

  /// The colour disc's opacity under a solid egg.
  static const double _tintDiscOpacity = 0.78;

  /// Where the drawn egg stands, given the [ground] under it: on rising
  /// ground at once, on sinking ground as fast as it sinks - unless that is
  /// faster than a fall: then the egg is in the air, falling from where it
  /// was, and it lands with a squash and a puff of dust. A jump (a reset, a
  /// rabbit hole, a new hole) puts it down at once.
  double _fallTo(double ground, Vec2 position, double dt) {
    final floor = _floor;
    final last = _drawnAt;
    _drawnAt = position;
    final jumped = last == null || last.distanceTo(position) > 2.5;
    if (floor == null || dt <= 0 || jumped || ground >= floor) {
      _floor = ground;
      _sinkSpeed = 0;
      _inAir = false;
      return ground;
    }
    final speed = _sinkSpeed + _gravity * dt;
    final fallen = floor - speed * dt;
    if (fallen > ground) {
      _floor = fallen;
      _sinkSpeed = speed;
      if (fallen - ground > 0.02) _inAir = true;
      return fallen;
    }
    if (_inAir && speed > 2.5) {
      // Down off a drop: the shell squashes and the dust flies.
      final strength = ((speed - 2.5) / 5).clamp(0.0, 1.0);
      _squash = 0.6 + strength * 0.4;
      onBounce(position, strength, everMine);
    }
    _inAir = false;
    _sinkSpeed = math.min(speed, (floor - ground) / dt);
    _floor = ground;
    return ground;
  }

  Vec2? _drawnAt;
  bool _inAir = false;

  /// The trail: a fast egg drops a soft puff every few hundredths of a
  /// second; the puffs fade and shrink over half a second.
  void _syncTrail(PuttWorldEgg egg, double dt) {
    const life = 0.6;
    for (var i = 0; i < _trailSpots.length; i++) {
      final (at, age) = _trailSpots[i];
      _trailSpots[i] = (at, age + dt);
    }
    _trailSpots.removeWhere((spot) => spot.$2 >= life);
    _sinceSpot += dt;
    if (egg.speed > 2.6 && _sinceSpot > 0.03) {
      _sinceSpot = 0;
      _trailSpots.add((egg.position, 0));
      if (_trailSpots.length > _trailLength) _trailSpots.removeAt(0);
    }
    for (var i = 0; i < _puffs.length; i++) {
      final puff = _puffs[i];
      if (i >= _trailSpots.length) {
        puff.visible = false;
        continue;
      }
      final (at, age) = _trailSpots[i];
      final fade = 1 - age / life;
      puff.visible = true;
      puff.position.setValues(at.x, terrain.at(at) + _radius * 0.35, at.y);
      final size = _radius * (0.7 + 0.8 * fade);
      puff.scale.setValues(size, size, 1);
      puff.material?.opacity = 0.55 * fade;
    }
  }

  /// Eases the long axis down to the horizontal: an egg at rest lies on
  /// its side.
  void _settle(double dt) {
    final long =
        tjs.Vector3(0, 1, 0).applyQuaternion(group.quaternion).normalize();
    final flat = tjs.Vector3(long.x, 0, long.z);
    if (flat.length < 1e-3) flat.setValues(1, 0, 0);
    flat.normalize();
    final tip = tjs.Quaternion().setFromUnitVectors(long, flat);
    final target = tip.multiply(group.quaternion.clone());
    final k = 1 - math.exp(-2.6 * dt);
    group.quaternion.slerp(target, k);
  }

  void dispose() {
    body.geometry?.dispose();
    // The shell's paint is shared by colour and outlives the egg.
    body.material?.map = null;
    body.material?.emissiveMap = null;
    body.material?.dispose();
    group.dispose();
    _marker.geometry?.dispose();
    _marker.material?.dispose();
    _tintDisc.geometry?.dispose();
    _tintDisc.material?.dispose();
    for (final piece in [_arrow, ..._arrow.children.whereType<tjs.Mesh>()]) {
      piece.geometry?.dispose();
      piece.material?.dispose();
    }
    _shadow.geometry?.dispose();
    _shadow.material?.map = null;
    _shadow.material?.dispose();
    ground.dispose();
    for (final puff in [..._puffs, _bubble]) {
      puff.material?.map = null;
      puff.material?.dispose();
    }
    trail.dispose();
  }
}

/// The egg's profile turned on a lathe: fuller at the base, narrower at the
/// crown, standing [_eggAspect] times its radius high either way.
tjs.BufferGeometry _eggGeometry(double radius) {
  const steps = 22;
  final h = radius * _eggAspect;
  final points = <tjs.Vector2>[];
  for (var i = 0; i <= steps; i++) {
    final theta = i / steps * math.pi;
    final y = -math.cos(theta) * h;
    final r =
        math.max(radius * math.sin(theta) * (1 + 0.1 * math.cos(theta)), 0.0);
    points.add(tjs.Vector2(r, y));
  }
  return tjg.LatheGeometry(points, segments: 28);
}

/// The shells' paints, one per player colour, made once and shared by
/// every egg of every world (eight at most).
final Map<int, tjs.DataTexture> _eggTextures = {};

tjs.DataTexture _eggTextureFor(int tint) =>
    _eggTextures.putIfAbsent(tint, () => _eggTexture(tint));

/// The shell's paint: a pastel of the player's colour with fine speckles
/// (so whose egg it is reads from the overview too), a zig-zag band in the
/// full colour round the waist and a ring of dots above and below. u runs
/// around the egg, v from the base (0) to the crown (1).
tjs.DataTexture _eggTexture(int tint) {
  const width = 256;
  const height = 128;
  final bitmap = _Bitmap(width, height);
  final rand = _Rand(tint);
  final shell = _mix(0xFFF8EE, tint, 0.25);
  final deep = _shade(tint, 0.78);
  for (var y = 0; y < height; y++) {
    final v = (y + 0.5) / height;
    for (var x = 0; x < width; x++) {
      final u = (x + 0.5) / width;
      var color = shell;
      // The band: a zig-zag-edged stripe in the player's colour.
      final zig = ((u * 9) % 1.0 - 0.5).abs() * 2; // 0..1 triangle
      final top = 0.6 + zig * 0.05;
      final bottom = 0.42 - zig * 0.05;
      if (v > bottom && v < top) {
        color = tint;
        if ((v - (bottom + top) / 2).abs() < 0.018) color = shell;
      } else if ((v - bottom).abs() < 0.025 || (v - top).abs() < 0.025) {
        color = deep;
      }
      // The face sits at u = 0 (the side that looks at the camera on the
      // tee): around it, no dots.
      final faceU = math.min(u, 1 - u); // distance round from the face
      // Dots above and below the band, a ring of seven each.
      for (final (row, size) in const [(0.75, 0.05), (0.27, 0.055)]) {
        if (row > 0.5 && faceU < 0.17) continue;
        const count = 7;
        final cell = ((u + 0.5 / count) * count) % 1.0 - 0.5;
        final du = cell / count * 3.2; // around the egg, in its height's units
        final dv = v - row;
        if (du * du + dv * dv < size * size) color = tint;
      }
      // The face: two ink eyes with a glint, and a little yolk beak. In
      // surface units u runs about 6.3 radii around, v about 3.6 up.
      final su = u < 0.5 ? u : u - 1; // signed, the face at 0
      for (final side in const [-1.0, 1.0]) {
        final ex = (su - side * 0.05) * 6.3;
        final ey = (v - 0.725) * 3.6;
        if (ex * ex + ey * ey < 0.125 * 0.125) {
          color = 0x211614;
          final gx = ex - 0.045;
          final gy = ey - 0.045;
          if (gx * gx + gy * gy < 0.045 * 0.045) color = 0xFFFFFF;
        }
      }
      final beak = (v - 0.632) / 0.05; // 0 at the tip, 1 at its top
      if (beak >= 0 && beak <= 1 && su.abs() * 6.3 < 0.11 * beak) {
        color = 0xF89B17;
      }
      bitmap.set(x, y, color);
    }
  }
  // Speckles on the shell.
  for (var i = 0; i < 260; i++) {
    final x = rand.below(width);
    final y = rand.below(height);
    bitmap.blend(x, y, 0xC9B79E, 0.35);
  }
  return bitmap.texture();
}

/// The hen: a plump white body, a cream-tipped tail, wings, a head with
/// the red comb and wattle, a yolk beak and legs that walk her path.
/// Something that walks (or swims) a moving obstacle's path.
abstract class _Walker {
  tjs.Group get group;
  void sync(PuttWorldHen hen, double time);
}

/// Fades a figure out of the way (a hen walking into the camera's face,
/// the host behind the HUD): its materials are made transparent once, at
/// build, so a fade only moves a uniform and never recompiles a program.
/// Faded all the way, the figure is not drawn at all (it would still hide
/// what stands behind it in the depth buffer).
mixin _Fadable {
  final List<tjs.Material> _fadeMaterials = [];

  /// The parts that cast a shadow when solid: a fading figure lets its
  /// shadow go (a faded rooster's full shadow on the meadow read as a
  /// glitch).
  final List<tjs.Object3D> _fadeCasters = [];
  double _fade = 1;
  tjs.Object3D? _fadeRoot;

  /// The root's own scale, which the pop shrinks from.
  tjs.Vector3? _fadeScale;

  /// How long a figure takes to go, or to come back: a pop, not a ghost
  /// lingering half-seen.
  static const double _fadeSeconds = 0.15;

  /// The figure's own height scale (not shrunk by the pop).
  double get fadeBaseScaleY => _fadeScale?.y ?? 1;

  void _prepareFade(tjs.Object3D root) {
    _fadeRoot = root;
    _fadeScale = root.scale.clone();
    root.traverse((object) {
      if (object.castShadow) _fadeCasters.add(object);
      final material = object.material;
      if (material == null || _fadeMaterials.contains(material)) return;
      material.transparent = true;
      _fadeMaterials.add(material);
    });
  }

  /// Goes toward [target] (1 solid, 0 gone) in [_fadeSeconds], shrinking
  /// a little toward its feet as it goes.
  void fadeToward(double target, double dt) {
    if (_fade == target) return;
    final step = dt / _fadeSeconds;
    _fade = target > _fade
        ? math.min(target, _fade + step)
        : math.max(target, _fade - step);
    for (final material in _fadeMaterials) {
      material.opacity = _fade;
    }
    final solid = _fade >= 0.9;
    for (final caster in _fadeCasters) {
      caster.castShadow = solid;
    }
    final root = _fadeRoot;
    if (root == null) return;
    root.visible = _fade > 0.02;
    final base = _fadeScale;
    if (base != null) {
      final k = 0.6 + 0.4 * _fade;
      root.scale.setValues(base.x * k, base.y * k, base.z * k);
    }
  }
}

/// A figure of the scenery that can fade out of the way (the host, when
/// he would stand behind the HUD or in the camera's face).
class _FadingFigure with _Fadable {
  _FadingFigure(this.figure) {
    _prepareFade(figure);
  }

  final tjs.Object3D figure;
}

/// A duck where the obstacle paddles over water (the Pond's ducks): a
/// mallard sitting low in the water - brown body, green head over a white
/// collar, a yolk bill, a blue patch on the wing - bobbing as it goes, a
/// wake round it.
class _DuckView3D implements _Walker {
  _DuckView3D(MovingObstacle obstacle) {
    final r = obstacle.radius;
    group = tjs.Group()..name = 'duck/${obstacle.id}';
    _body = tjs.Group()..name = 'duck-body';
    final ink = _hexOf(PuttPalette.ink);
    final yolk = _hexOf(PuttPalette.yolk);
    final shape = _Merged()
      ..add(
          tjs.SphereGeometry(1, 20, 14),
          _place(0, r * 0.32, -r * 0.05,
              sx: r * 0.66, sy: r * 0.42, sz: r * 1.0),
          0x8A6A4A,
          baseShade: 0.7)
      ..add(
          tjs.SphereGeometry(1, 16, 12),
          _place(0, r * 0.3, r * 0.42, sx: r * 0.5, sy: r * 0.36, sz: r * 0.42),
          0xC9B79A)
      ..add(tjg.ConeGeometry(r * 0.3, r * 0.55, 8),
          _place(0, r * 0.42, -r * 1.0, tilt: -math.pi / 2 - 0.35), 0x5E4630);
    for (final side in [-1.0, 1.0]) {
      shape
        ..add(
            tjs.SphereGeometry(1, 12, 8),
            _place(side * r * 0.5, r * 0.42, -r * 0.12,
                sx: r * 0.2, sy: r * 0.24, sz: r * 0.7),
            0x6E5236)
        ..add(tjs.BoxGeometry(r * 0.05, r * 0.12, r * 0.3),
            _place(side * r * 0.69, r * 0.44, -r * 0.3), 0x3B5BDB);
    }
    shape
      ..add(tjg.TorusGeometry(r * 0.27, r * 0.05, 6, 20),
          _place(0, r * 0.72, r * 0.5, tilt: math.pi / 2 - 0.3), 0xFCF8F1)
      ..add(tjs.SphereGeometry(r * 0.34, 16, 12), _place(0, r * 0.98, r * 0.62),
          0x2E6B3C)
      ..add(tjs.BoxGeometry(r * 0.26, r * 0.08, r * 0.36),
          _place(0, r * 0.9, r * 1.02), yolk);
    for (final side in [-1.0, 1.0]) {
      shape.add(tjs.SphereGeometry(r * 0.055, 8, 6),
          _place(side * r * 0.24, r * 1.06, r * 0.82), ink);
    }
    final duckShape = shape.mesh('duck-shape', flat: false, roughness: 0.6)!;
    _inkOutline(duckShape, r * 0.05);
    _body.add(duckShape);
    group.add(_body);
    _wake = tjs.Mesh(
      tjg.RingGeometry(r * 1.05, r * 1.3, 32, 1),
      _unlit(0xFFFFFF, opacity: 0.35, depthWrite: false),
    )
      ..name = 'duck-wake'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.06
      ..renderOrder = 3;
    group.add(_wake);
    group.traverse((object) {
      if (object.name != 'duck-wake' && !object.name.endsWith('-outline')) {
        object.castShadow = true;
      }
    });
  }

  @override
  late final tjs.Group group;
  late final tjs.Group _body;
  late final tjs.Mesh _wake;
  Vec2 _heading = const Vec2(0, 1);

  @override
  void sync(PuttWorldHen hen, double time) {
    if (hen.heading.length > 1e-4) {
      _heading = hen.heading.normalized(_heading);
    }
    group.rotation.y = math.atan2(_heading.x, _heading.y);
    // Sitting low in the water, bobbing, rocking a little as it paddles.
    _body.position.y = -0.12 + math.sin(time * 2.2 + hen.position.x) * 0.05;
    _body.rotation.z = math.sin(time * 3.1) * 0.05;
    final swell = 1 + math.sin(time * 2.6) * 0.06;
    _wake.scale.setValues(swell, swell, 1);
    group.position.setValues(hen.position.x, 0, hen.position.y);
  }
}

class _HenView3D with _Fadable implements _Walker {
  _HenView3D(MovingObstacle obstacle, [_Ground? terrain])
      : _terrain = terrain ?? _Ground() {
    final r = obstacle.radius;
    group = tjs.Group()..name = 'hen/${obstacle.id}';
    const white = 0xFCF8F1;
    const cream = 0xEEDFC8;
    final comb = _hexOf(PuttPalette.comb);
    final yolk = _hexOf(PuttPalette.yolk);
    final ink = _hexOf(PuttPalette.ink);
    // The body rides the bob; forward is local +z.
    _body = tjs.Group()..name = 'hen-body';
    final shape = _Merged()
      ..add(
          tjs.SphereGeometry(1, 20, 14),
          _place(0, r * 1.05, 0, sx: r * 0.92, sy: r * 0.82, sz: r * 1.1),
          white,
          baseShade: 0.8)
      ..add(
          tjs.SphereGeometry(1, 16, 12),
          _place(0, r * 1.2, r * 0.55, sx: r * 0.62, sy: r * 0.68, sz: r * 0.6),
          white);
    for (final side in [-1.0, 1.0]) {
      shape.add(
          tjs.SphereGeometry(1, 14, 10),
          _place(side * r * 0.78, r * 1.08, -r * 0.08,
              sx: r * 0.22, sy: r * 0.5, sz: r * 0.78),
          cream);
    }
    for (var f = 0; f < 3; f++) {
      shape.add(
        tjg.ConeGeometry(r * 0.3, r * 0.9, 6),
        _place((f - 1) * r * 0.22, r * 1.55, -r * 0.85,
            tilt: -0.75 - f * 0.08, roll: (f - 1) * 0.25),
        f == 1 ? cream : white,
      );
    }
    final henShape = shape.mesh('hen-shape', flat: false, roughness: 0.8)!;
    _inkOutline(henShape, r * 0.05);
    _body.add(henShape);
    _head = tjs.Group()
      ..name = 'hen-head'
      ..position.setValues(0, r * 1.85, r * 0.85);
    final face = _Merged()
      ..add(tjs.SphereGeometry(r * 0.42, 16, 12), _place(0, 0, 0), white)
      ..add(tjg.ConeGeometry(r * 0.14, r * 0.38, 8),
          _place(0, -r * 0.04, r * 0.48, tilt: math.pi / 2), yolk)
      ..add(tjs.SphereGeometry(r * 0.12, 10, 8),
          _place(0, -r * 0.26, r * 0.32, sy: 1.5), comb);
    for (final (z, y, s) in const [
      (0.12, 0.4, 0.16),
      (-0.08, 0.46, 0.17),
      (-0.26, 0.38, 0.13)
    ]) {
      face.add(tjs.SphereGeometry(r * s, 10, 8),
          _place(0, r * y, r * z, sx: 0.55), comb);
    }
    for (final side in [-1.0, 1.0]) {
      face.add(tjs.SphereGeometry(r * 0.065, 8, 6),
          _place(side * r * 0.3, r * 0.08, r * 0.24), ink);
    }
    final henFace = face.mesh('hen-face', flat: false, roughness: 0.7)!;
    _inkOutline(henFace, r * 0.05);
    _head.add(henFace);
    _body.add(_head);
    group.add(_body);
    for (final side in [-1.0, 1.0]) {
      final hip = tjs.Group()
        ..name = 'hen-leg'
        ..position.setValues(side * r * 0.32, r * 0.55, 0);
      final leg = _Merged()
        ..add(tjg.CylinderGeometry(r * 0.06, r * 0.06, r * 0.55, 6),
            _place(0, -r * 0.27, 0), yolk)
        ..add(tjs.BoxGeometry(r * 0.12, r * 0.05, r * 0.36),
            _place(0, -r * 0.54, r * 0.1), yolk);
      hip.add(leg.mesh('hen-foot', flat: true)!..castShadow = true);
      _legs.add(hip);
      group.add(hip);
    }
    group.traverse((object) {
      if (!object.name.endsWith('-outline')) object.castShadow = true;
    });
    _prepareFade(group);
  }

  @override
  late final tjs.Group group;
  late final tjs.Group _body;
  late final tjs.Group _head;
  final List<tjs.Group> _legs = [];
  Vec2 _heading = const Vec2(0, 1);
  Vec2? _last;

  /// The stand and the facing (the last non-stop direction she had), the
  /// legs swinging while she walks and the head bobbing with her steps.
  @override
  void sync(PuttWorldHen hen, double time) {
    if (hen.heading.length > 1e-4) {
      _heading = hen.heading.normalized(_heading);
    }
    // Local +z turned onto the heading.
    group.rotation.y = math.atan2(_heading.x, _heading.y);
    final moved = _last == null ? 0.0 : _last!.distanceTo(hen.position);
    _last = hen.position;
    final walking = moved > 1e-4;
    final stride = walking ? math.sin(hen.phase * 0.9) : 0.0;
    _legs[0].rotation.x = stride * 0.6;
    _legs[1].rotation.x = -stride * 0.6;
    final bob = walking ? math.sin(hen.phase * 1.8).abs() * 0.08 : 0.0;
    _body.position.y = bob;
    // Pecking now and then while she stands.
    final peck = walking ? 0.0 : math.max(0.0, math.sin(time * 2.2)) * 0.5;
    _head.rotation.x = peck;
    group.position
        .setValues(hen.position.x, _terrain.at(hen.position), hen.position.y);
  }

  final _Ground _terrain;
}

/// The "?" crate: a yolk carton floating over its glow, turning slowly,
/// until its id lands in the frame's collected set.
class _CrateView3D {
  _CrateView3D(this.box, tjs.DataTexture texture, {double floor = 0}) {
    final size = box.radius * 1.35;
    group = tjs.Group()
      ..name = 'crate/${box.id}'
      ..position.setValues(box.position.x, floor, box.position.y);
    _spin = tjs.Group()..name = 'crate-spin';
    final body = tjs.Mesh(
      tjs.BoxGeometry(size, size, size),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: texture,
        tjs.MaterialProperty.roughness: 0.5,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.emissive: _lin(0x3C2400),
      }),
    )
      ..name = 'crate-body'
      ..castShadow = true;
    _spin.add(body);
    _hover = size * 0.5 + 0.45;
    _spin.position.y = _hover;
    _glow = tjs.Mesh(
      tjg.CircleGeometry(radius: box.radius * 1.35, segments: 28),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.map: _EggView3D._shadowTexture,
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.yolk)),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.6,
        tjs.MaterialProperty.depthWrite: false,
        tjs.MaterialProperty.blending: tjs.AdditiveBlending,
      }),
    )
      ..name = 'crate-glow'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.04
      ..renderOrder = 2;
    group
      ..add(_spin)
      ..add(_glow);
  }

  final QuestionBox box;
  late final tjs.Group group;
  late final tjs.Group _spin;
  late final tjs.Mesh _glow;
  late final double _hover;

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

  /// Seconds since the crate was taken (the pop plays), or null while it
  /// stands.
  double? _poppedAt;

  void sync({required bool visible, required double time}) {
    if (!visible) {
      // Taken: a quick swell and spin, then gone.
      final start = _poppedAt ??= time;
      final t = ((time - start) / 0.28).clamp(0.0, 1.0);
      group.visible = t < 1;
      if (t < 1) {
        final swell = 1 + t * 0.7;
        _spin
          ..scale.setValues(
              swell * (1 - t), swell * (1 - t) + 0.001, swell * (1 - t))
          ..rotation.y += 0.35
          ..position.y = _hover + t * 1.2;
        _glow.material?.opacity = 0.6 * (1 - t);
      }
      return;
    }
    if (_poppedAt != null) {
      _poppedAt = null;
      _spin.scale.setValues(1, 1, 1);
    }
    group.visible = true;
    final breathe = math.sin(time * 2.4 + bobPhase);
    _spin.position.y = _hover + breathe * 0.14;
    _spin.rotation.y = time * 0.9 + bobPhase;
    _spin.rotation.x = math.sin(time * 1.3 + bobPhase) * 0.08;
    _glow.material?.opacity = 0.42 + 0.22 * (0.5 + 0.5 * breathe);
  }
}
