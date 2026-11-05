// The payoff of a sink: the egg hatches in the nest. The shell's cap pops
// off and tumbles away, and a chick rises out of the cup standing in the
// bottom half of its shell (in the player's colour) and wearing the hat its
// player picked, turns to the camera, hops three times on the lip flapping
// its wings and drops back in. Three are pooled, built once with every hat
// on hand; a hatch only moves them, recolours the shell (a colour, never a
// texture, so no material recompiles in play) and shows one hat.
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
    // The hats, one of each, on the head; a hatch shows its player's.
    for (final hat in HatchlingHat.values) {
      final mesh = _hatMesh(hat);
      if (mesh == null) continue;
      mesh.visible = false;
      _hats[hat] = mesh;
      _rise.add(mesh);
    }
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
  static const double life = 2.5;

  /// Where the chick stands while it hops: a touch above the nest's lip,
  /// so it reads over the dark cup, not down in it.
  static const double _stand = 0.3;

  /// When the hops end and it drops back in.
  static const double _hopsEnd = 2.0;

  late final tjs.Group group;
  late final tjs.Group _rise;
  late final tjs.Mesh _bottom;
  late final tjs.Mesh _cap;
  late final tjs.MeshStandardMaterial _shellMaterial;
  final List<tjs.Group> _wings = [];
  final Map<HatchlingHat, tjs.Mesh> _hats = {};

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

  /// Hatches at [at] (the nest), the shell in [tint], the chick in [hat];
  /// [big] for the viewer's own egg.
  void hatch(Vec2 at, int tint,
      {HatchlingHat hat = HatchlingHat.none,
      double floor = 0,
      bool big = false,
      double rim = 1.2}) {
    _age = 0;
    _at = at;
    _hats.forEach((kind, mesh) => mesh.visible = kind == hat);
    _scale = big ? 1.6 : 1.0;
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

  /// [hat] built for the chick's head (the head's middle at (0, 1, 0.05),
  /// about a third of a unit round, the face toward +z); null for none.
  static tjs.Mesh? _hatMesh(HatchlingHat hat) {
    final ink = _hexOf(PuttPalette.ink);
    final comb = _hexOf(PuttPalette.comb);
    final yolk = _hexOf(PuttPalette.yolk);
    final hatPieces = _Merged();
    switch (hat) {
      case HatchlingHat.none:
        return null;
      case HatchlingHat.strawHat:
        // Pushed back a little: every piece rides the tipped axis.
        const tip = -0.14;
        tjs.Matrix4 along(double rise, {double sy = 1}) =>
            _place(0, 1.25 + rise * math.cos(tip), 0.03 + rise * math.sin(tip),
                tilt: tip, sy: sy);
        hatPieces
          ..add(
              tjg.CylinderGeometry(0.5, 0.52, 0.04, 28), along(0), _Farm.straw)
          ..add(tjg.CylinderGeometry(0.21, 0.25, 0.2, 22), along(0.12),
              _Farm.strawLight)
          ..add(tjg.CylinderGeometry(0.258, 0.258, 0.06, 22), along(0.05), comb)
          ..add(tjs.SphereGeometry(0.21, 18, 8), along(0.22, sy: 0.3),
              _Farm.strawLight);
      case HatchlingHat.bow:
        // Two loops and the knot, perched on one side of the head.
        const knot = (0.16, 1.31, 0.09);
        for (final side in [-1.0, 1.0]) {
          hatPieces.add(
              tjs.SphereGeometry(1, 14, 10),
              _place(knot.$1 + side * 0.12, knot.$2 + 0.02, knot.$3,
                  roll: side * 0.35 - 0.2, sx: 0.13, sy: 0.085, sz: 0.06),
              comb);
        }
        hatPieces.add(tjs.SphereGeometry(0.055, 10, 8),
            _place(knot.$1, knot.$2, knot.$3 + 0.02), _shade(comb, 0.8));
      case HatchlingHat.crown:
        // A gold ring round the top of the head, five points with pearls,
        // a red jewel in front; set at a jaunty angle. A deep gold: the
        // yolk's would melt into the chick's yellow.
        const gold = 0xD98A14;
        const roll = 0.14;
        final ring = _place(0, 1.27, 0.04, roll: roll);
        hatPieces.add(
            tjg.TorusGeometry(0.2, 0.045, 8, 28),
            tjs.Matrix4().multiply2(ring, _place(0, 0, 0, tilt: math.pi / 2)),
            gold);
        for (var i = 0; i < 5; i++) {
          final angle = i * 2 * math.pi / 5;
          final x = math.sin(angle) * 0.2;
          final z = math.cos(angle) * 0.2;
          hatPieces
            ..add(tjg.ConeGeometry(0.055, 0.14, 8),
                tjs.Matrix4().multiply2(ring, _place(x, 0.1, z)), gold)
            ..add(tjs.SphereGeometry(0.03, 8, 6),
                tjs.Matrix4().multiply2(ring, _place(x, 0.18, z)), 0xFFF8EE);
        }
        hatPieces.add(tjs.SphereGeometry(0.04, 10, 8),
            tjs.Matrix4().multiply2(ring, _place(0, 0.01, 0.24)), comb);
      case HatchlingHat.headphones:
        // The host's: the band over the top, a cup on each side, red rims.
        hatPieces.add(tjg.TorusGeometry(0.37, 0.035, 8, 24, math.pi),
            _place(0, 1.0, 0.04), ink);
        for (final side in [-1.0, 1.0]) {
          hatPieces
            ..add(tjg.CylinderGeometry(0.12, 0.12, 0.08, 20),
                _place(side * 0.34, 1.0, 0.05, roll: math.pi / 2), ink)
            ..add(tjg.TorusGeometry(0.085, 0.022, 6, 18),
                _place(side * 0.385, 1.0, 0.05, yaw: math.pi / 2), comb);
        }
      case HatchlingHat.daisy:
        // White petals round a yolk heart, tucked over the left eye and
        // turned up toward the camera.
        final flower = _place(-0.16, 1.26, 0.2, tilt: 0.55, roll: 0.45);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          hatPieces.add(
              tjs.SphereGeometry(1, 10, 6),
              tjs.Matrix4().multiply2(
                  flower,
                  _place(math.cos(angle) * 0.075, 0, math.sin(angle) * 0.075,
                      yaw: -angle, sx: 0.07, sy: 0.022, sz: 0.036)),
              0xFFF8EE);
        }
        hatPieces.add(
            tjs.SphereGeometry(0.05, 10, 8),
            tjs.Matrix4().multiply2(flower, _place(0, 0.012, 0, sy: 0.6)),
            yolk);
    }
    return hatPieces.mesh('hatchling-hat-${hat.name}',
        flat: false, roughness: 0.6);
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
    // Rise out of the cup with an overshoot onto the lip, hop three times,
    // drop back in.
    double y;
    double s;
    if (t < 0.42) {
      final k = t / 0.42;
      const c = 1.9;
      final back = 1 + (c + 1) * math.pow(k - 1, 3) + c * math.pow(k - 1, 2);
      y = -1.4 + (1.4 + _stand) * back;
      s = 0.55 + 0.45 * k;
    } else if (t < _hopsEnd) {
      final k = (t - 0.42) / (_hopsEnd - 0.42);
      y = _stand + math.sin(k * math.pi * 3).abs() * 0.55;
      s = 1;
    } else {
      final k = (t - _hopsEnd) / (life - _hopsEnd);
      y = _stand - (_stand + 1.5) * k * k;
      s = 1 - 0.35 * k;
    }
    _rise
      ..position.y = y
      ..scale.setValues(s, s, s);
    final hopping = t > 0.3 && t < _hopsEnd + 0.05;
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
