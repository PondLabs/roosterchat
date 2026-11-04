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
  _EggView3D(this._radius, ui.Color tint) {
    group = tjs.Group()..name = 'egg';
    _tintHex = _hexOf(tint);
    _texture = _eggTextureFor(_tintHex);
    final material = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.map: _texture,
      tjs.MaterialProperty.roughness: 0.36,
      tjs.MaterialProperty.metalness: 0.0,
    });
    // A whisper of light so eggs never sit muddy in the shade.
    material.emissive = _lin(0x2A2622);
    body = tjs.Mesh(_eggGeometry(_radius), material)
      ..name = 'egg-shell'
      ..castShadow = true;
    group.add(body);

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
    _marker = tjs.Mesh(
      tjg.RingGeometry(_radius * 1.55, _radius * 1.85, 36, 1),
      _unlit(_tintHex, opacity: 0.9, depthWrite: false),
    )
      ..name = 'egg-marker'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03
      ..renderOrder = 3
      ..visible = false;
    _arrow = tjs.Mesh(
      tjg.ConeGeometry(_radius * 0.62, _radius * 1.15, 4),
      _matte(_hexOf(PuttPalette.yolk), roughness: 0.45),
    )
      ..name = 'egg-arrow'
      // Tip down, toward the egg.
      ..rotation.x = math.pi
      ..castShadow = false
      ..visible = false;
    ground
      ..add(_shadow)
      ..add(_marker)
      ..add(_arrow);
    trail = tjs.Group()..name = 'egg-trail';
    final trailColor = _lin(_mix(_tintHex, 0xFFFFFF, 0.55));
    for (var i = 0; i < _trailLength; i++) {
      final puff = tjs.Sprite(
        tjs.SpriteMaterial({
          tjs.MaterialProperty.map: _shadowTexture,
          tjs.MaterialProperty.color: trailColor,
          tjs.MaterialProperty.transparent: true,
          tjs.MaterialProperty.opacity: 0.0,
          tjs.MaterialProperty.depthWrite: false,
        }),
      )
        ..name = 'egg-trail-puff'
        ..visible = false
        ..renderOrder = 3;
      _puffs.add(puff);
      trail.add(puff);
    }
  }

  static const int _trailLength = 12;

  late final tjs.Group trail;
  final List<tjs.Sprite> _puffs = [];

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

  /// The shadow's soft disc, shared by every egg of every world.
  static final tjs.DataTexture _shadowTexture = _discTexture(hardness: 1.4);

  void retint(ui.Color tint) {
    final hex = _hexOf(tint);
    if (hex == _tintHex) return;
    _tintHex = hex;
    // The shared texture for that colour: no texture is made or freed in
    // the middle of play (the renderer's texture cache has misbound a
    // freshly churned texture before).
    _texture = _eggTextureFor(hex);
    body.material?.map = _texture;
    body.material?.needsUpdate = true;
    _marker.material?.color = _lin(hex);
  }

  /// The stand (ground spot plus the hop's lift), then the roll: world
  /// axis from the horizontal velocity, omega = |v| / r, pre-multiplied so
  /// world space holds the accumulated spin - the egg tips exactly where it
  /// goes. Still, it eases onto its side, the way an egg rests.
  void sync(PuttWorldEgg egg, double dt, double time) {
    final speed = egg.speed;
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
    group.position
        .setValues(egg.position.x, support + egg.height, egg.position.y);

    lastPosition = egg.position;
    _syncTrail(egg, dt);

    // The ground pieces: the shadow shrinks and fades as a hop lifts.
    ground.position.setValues(egg.position.x, 0, egg.position.y);
    final lift = (egg.height / (_radius * 3)).clamp(0.0, 1.0);
    final shadowScale = 1 - lift * 0.45;
    _shadow.scale.setValues(shadowScale, shadowScale, 1);
    _shadow.material?.opacity = 0.55 * (1 - lift * 0.6);

    final resting = speed < 0.05;
    final showMarker = egg.mine && resting;
    _marker.visible = showMarker;
    _arrow.visible = showMarker;
    if (showMarker) {
      final pulse = 0.5 + 0.5 * math.sin(time * 4);
      final s = 1 + pulse * 0.08;
      _marker.scale.setValues(s, s, 1);
      _marker.material?.opacity = 0.65 + 0.3 * pulse;
      _arrow.position.y = h * 2 + 0.55 + math.sin(time * 3.2).abs() * 0.35;
      _arrow.rotation.y = time * 1.6;
    }
  }

  /// The trail: a fast egg drops a soft puff every few hundredths of a
  /// second; the puffs fade and shrink over half a second.
  void _syncTrail(PuttWorldEgg egg, double dt) {
    const life = 0.45;
    for (var i = 0; i < _trailSpots.length; i++) {
      final (at, age) = _trailSpots[i];
      _trailSpots[i] = (at, age + dt);
    }
    _trailSpots.removeWhere((spot) => spot.$2 >= life);
    _sinceSpot += dt;
    if (egg.speed > 3.2 && _sinceSpot > 0.035) {
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
      puff.position.setValues(at.x, _radius * 0.7, at.y);
      final size = _radius * (1.1 + 0.9 * fade);
      puff.scale.setValues(size, size, 1);
      puff.material?.opacity = 0.42 * fade;
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
    body.material?.dispose();
    group.dispose();
    _marker.geometry?.dispose();
    _marker.material?.dispose();
    _arrow.geometry?.dispose();
    _arrow.material?.dispose();
    _shadow.geometry?.dispose();
    _shadow.material?.map = null;
    _shadow.material?.dispose();
    ground.dispose();
    for (final puff in _puffs) {
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

/// The shell's paint: cream with fine speckles, a zig-zag band in the
/// player's colour round the waist and a ring of dots above and below.
/// u runs around the egg, v from the base (0) to the crown (1).
tjs.DataTexture _eggTexture(int tint) {
  const width = 256;
  const height = 128;
  final bitmap = _Bitmap(width, height);
  final rand = _Rand(tint);
  const shell = 0xFFF8EE;
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
class _HenView3D {
  _HenView3D(MovingObstacle obstacle) {
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
    _body.add(shape.mesh('hen-shape', flat: false, roughness: 0.8)!);
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
    _head.add(face.mesh('hen-face', flat: false, roughness: 0.7)!);
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
      object.castShadow = true;
    });
  }

  late final tjs.Group group;
  late final tjs.Group _body;
  late final tjs.Group _head;
  final List<tjs.Group> _legs = [];
  Vec2 _heading = const Vec2(0, 1);
  Vec2? _last;

  /// The stand and the facing (the last non-stop direction she had), the
  /// legs swinging while she walks and the head bobbing with her steps.
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
    group.position.setValues(hen.position.x, 0, hen.position.y);
  }
}

/// The "?" crate: a yolk carton floating over its glow, turning slowly,
/// until its id lands in the frame's collected set.
class _CrateView3D {
  _CrateView3D(this.box, tjs.DataTexture texture) {
    final size = box.radius * 1.35;
    group = tjs.Group()
      ..name = 'crate/${box.id}'
      ..position.setValues(box.position.x, 0, box.position.y);
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
