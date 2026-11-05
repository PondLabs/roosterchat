// The payoff of a sink: the egg hatches in the nest. The shell's cap pops
// off and tumbles away, and a chick rises out of the cup standing in the
// bottom half of its shell (in the player's colour), turns to the camera,
// hops twice flapping its wings and drops back in. Three are pooled, built
// once; a hatch only moves them and recolours the shell (a colour, never
// a texture, so no material recompiles in play).
part of '../putt_world3d.dart';

class _Hatchling {
  _Hatchling() {
    group = tjs.Group()
      ..name = 'hatchling'
      ..visible = false;
    _rise = tjs.Group()..name = 'hatchling-rise';
    group.add(_rise);

    const yellow = 0xFFC61A;
    const light = 0xFFE066;
    const wing = 0xF2A90F;
    const beak = 0xF28C28;
    const blush = 0xFF9E9E;
    final ink = _hexOf(PuttPalette.ink);
    final chick = _Merged()
      ..add(tjs.SphereGeometry(1, 20, 14),
          _place(0, 0.52, 0, sx: 0.44, sy: 0.42, sz: 0.44), yellow,
          baseShade: 0.84)
      ..add(tjs.SphereGeometry(1, 18, 12),
          _place(0, 1.0, 0.05, sx: 0.33, sy: 0.32, sz: 0.33), yellow)
      ..add(tjg.ConeGeometry(0.09, 0.22, 8),
          _place(0, 0.95, 0.43, tilt: math.pi / 2), beak);
    for (final (x, y, z, s) in const [
      (0.0, 1.33, 0.04, 0.085),
      (-0.07, 1.3, -0.04, 0.065),
      (0.08, 1.29, -0.02, 0.06),
    ]) {
      chick.add(tjs.SphereGeometry(s, 10, 8), _place(x, y, z), light);
    }
    for (final side in [-1.0, 1.0]) {
      chick
        ..add(tjs.SphereGeometry(0.065, 10, 8),
            _place(side * 0.13, 1.05, 0.29, sz: 0.7), ink)
        ..add(tjs.SphereGeometry(0.022, 6, 6),
            _place(side * 0.13 + 0.02, 1.08, 0.335), 0xFFFFFF)
        ..add(tjs.SphereGeometry(0.06, 10, 8),
            _place(side * 0.21, 0.93, 0.26, sy: 0.6, sz: 0.4), blush)
        ..add(tjs.BoxGeometry(0.1, 0.04, 0.2), _place(side * 0.14, 0.04, 0.08),
            beak);
    }
    _rise.add(chick.mesh('hatchling-chick', flat: false, roughness: 0.78)!);
    for (final side in [-1.0, 1.0]) {
      final pivot = tjs.Group()
        ..name = 'hatchling-wing'
        ..position.setValues(side * 0.4, 0.66, -0.02);
      final feathers = _Merged()
        ..add(tjs.SphereGeometry(1, 12, 8),
            _place(side * 0.05, -0.14, 0, sx: 0.09, sy: 0.22, sz: 0.2), wing);
      pivot.add(feathers.mesh('hatchling-feathers', flat: false)!);
      _wings.add(pivot);
      _rise.add(pivot);
    }

    // The shell: the egg's own profile cut in two, the cut zig-zagged.
    _shellMaterial = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.color: _lin(0xFFF8EE),
      tjs.MaterialProperty.roughness: 0.55,
      tjs.MaterialProperty.metalness: 0.0,
      tjs.MaterialProperty.side: tjs.DoubleSide,
    });
    _bottom = tjs.Mesh(_shellPiece(0, 0.47, zigzagTop: true), _shellMaterial)
      ..name = 'hatchling-shell'
      ..position.y = _shellHeight;
    _rise.add(_bottom);
    _cap = tjs.Mesh(_shellPiece(0.6, 1, zigzagTop: false), _shellMaterial)
      ..name = 'hatchling-cap';
    group.add(_cap);
    group.traverse((object) {
      object.castShadow = true;
    });
  }

  static const double _shellRadius = 0.5;
  static const double _shellHeight = _shellRadius * _eggAspect;
  static const double life = 1.9;

  late final tjs.Group group;
  late final tjs.Group _rise;
  late final tjs.Mesh _bottom;
  late final tjs.Mesh _cap;
  late final tjs.MeshStandardMaterial _shellMaterial;
  final List<tjs.Group> _wings = [];

  double _age = life;
  double _scale = 1;
  double _rim = 1.2;
  Vec2 _at = Vec2.zero;
  double _capSpin = 0;
  Vec2 _capHeading = const Vec2(1, 0);

  bool get busy => _age < life;

  /// One band of the egg's profile, [from] to [to] of the way from the
  /// base to the crown, its rim (the top or the bottom one) cut in a
  /// zig-zag.
  static tjs.BufferGeometry _shellPiece(double from, double to,
      {required bool zigzagTop}) {
    const steps = 10;
    const segments = 24;
    final points = <tjs.Vector2>[];
    for (var i = 0; i <= steps; i++) {
      final theta = (from + (to - from) * i / steps) * math.pi;
      final y = -math.cos(theta) * _shellHeight;
      final r = math.max(
          _shellRadius * math.sin(theta) * (1 + 0.1 * math.cos(theta)), 0.0);
      points.add(tjs.Vector2(r, y));
    }
    final geometry = tjg.LatheGeometry(points, segments: segments);
    final position = geometry.attributes['position'];
    final rim = zigzagTop ? steps : 0;
    for (var i = 0; i <= segments; i++) {
      final index = i * points.length + rim;
      final jag = (i.isEven ? 0.07 : -0.05) * (zigzagTop ? 1 : -1);
      position.setY(index, position.getY(index)! + jag);
    }
    position.needsUpdate = true;
    return geometry;
  }

  /// Hatches at [at] (the nest), the shell in [tint]; [big] for the
  /// viewer's own egg.
  void hatch(Vec2 at, int tint,
      {double floor = 0, bool big = false, double rim = 1.2}) {
    _age = 0;
    _at = at;
    _scale = big ? 1.35 : 1.0;
    // Where the cap lands: on the straw, in the hatchling's own units.
    _rim = rim / _scale;
    _shellMaterial.color = _lin(_mix(tint, 0xFFF8EE, 0.3));
    _capSpin = 0;
    final angle = (at.x * 12.9898 + at.y * 78.233) % (math.pi * 2);
    _capHeading = Vec2(math.cos(angle), math.sin(angle));
    group
      ..visible = true
      ..position.setValues(at.x, floor, at.y)
      ..scale.setValues(_scale, _scale, _scale);
  }

  void hide() {
    _age = life;
    group.visible = false;
  }

  /// One frame: [camera] is where the chick turns to.
  void update(double dt, tjs.Vector3 camera) {
    if (!busy) return;
    _age += dt;
    if (_age >= life) {
      group.visible = false;
      return;
    }
    final t = _age;
    // Rise out of the cup with an overshoot, hop twice, drop back in.
    double y;
    double s;
    if (t < 0.42) {
      final k = t / 0.42;
      const c = 1.9;
      final back = 1 + (c + 1) * math.pow(k - 1, 3) + c * math.pow(k - 1, 2);
      y = -1.4 + 1.4 * back;
      s = 0.55 + 0.45 * k;
    } else if (t < 1.45) {
      final k = (t - 0.42) / 1.03;
      y = math.sin(k * math.pi * 2).abs() * 0.42;
      s = 1;
    } else {
      final k = (t - 1.45) / (life - 1.45);
      y = -1.5 * k * k;
      s = 1 - 0.35 * k;
    }
    _rise
      ..position.y = y
      ..scale.setValues(s, s, s);
    final hopping = t > 0.3 && t < 1.5;
    final flap = hopping ? math.sin(t * 34) * 0.85 + 0.45 : 0.1;
    _wings[0].rotation.z = -flap;
    _wings[1].rotation.z = flap;
    // Face the camera.
    final dx = camera.x - _at.x;
    final dz = camera.z - _at.y;
    _rise.rotation.y = math.atan2(dx, dz);

    // The cap: popped off the top, it tumbles in an arc and lands upside
    // down on the straw, where it rocks to rest until the chick goes.
    const flight = 0.55;
    _cap.visible = true;
    if (t < flight) {
      final k = t / flight;
      _cap.position.setValues(
        _capHeading.x * _rim * k,
        0.9 + 1.4 * math.sin(k * math.pi) - 0.75 * k,
        _capHeading.y * _rim * k,
      );
      _capSpin += dt * 11;
      _cap.rotation.set(_capSpin, 0, _capSpin * 0.6);
    } else {
      // Landed: upside down (a cup on the straw), a rock that settles.
      final since = t - flight;
      final rock = math.sin(since * 14) * 0.35 * math.exp(-since * 4);
      _cap.position.setValues(_capHeading.x * _rim, 0.15, _capHeading.y * _rim);
      _cap.rotation.set(math.pi + rock, 0, rock * 0.5);
    }
    final fade = t < life - 0.3 ? 1.0 : (life - t) / 0.3;
    _cap.scale.setValues(fade, fade, fade);
  }
}
