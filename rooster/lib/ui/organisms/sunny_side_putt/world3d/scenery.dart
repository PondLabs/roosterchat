// The farm around the course: the sky dome and its clouds (the world's
// own, kept across holes), and per hole the meadow rolling into hills,
// groves of oaks and pines, bushes, a scatter of wildflowers and tufts,
// stones, hay bales, a picket fence around the table, the red barn with
// its silo, a windmill turning on the hill, and the host himself - a big
// white rooster with his headphones on, bobbing his head by the green.
//
// Everything is placed by a random seeded from the hole's id: the same
// hole always stands in the same farm. Tall things keep off the camera's
// side of the table, so nothing ever stands between the player and the
// green.
part of '../putt_world3d.dart';

// ---- the sky -------------------------------------------------------------------------

/// The sky dome: a gradient from the warm horizon to deep blue overhead,
/// and the clouds drifting around it. It rides with the camera (only its
/// rotation is the world's), so its horizon never comes near.
class _SkyDome {
  _SkyDome() {
    group = tjs.Group()..name = 'sky';
    final dome = tjs.SphereGeometry(900, 40, 24);
    final position = dome.attributes['position'] as tjs.BufferAttribute;
    final colors = Float32List(position.count * 3);
    final horizon = _lin(_Farm.horizon);
    final mid = _lin(_Farm.skyMid);
    final top = _lin(_Farm.skyTop);
    for (var i = 0; i < position.count; i++) {
      final h = (position.getY(i)! / 900).toDouble();
      tjs.Color from;
      tjs.Color to;
      double t;
      if (h < 0.02) {
        from = horizon;
        to = horizon;
        t = 0;
      } else if (h < 0.22) {
        from = horizon;
        to = mid;
        t = (h - 0.02) / 0.2;
      } else {
        from = mid;
        to = top;
        t = ((h - 0.22) / 0.6).clamp(0.0, 1.0);
      }
      t = t * t * (3 - 2 * t);
      colors[i * 3] = from.red + (to.red - from.red) * t;
      colors[i * 3 + 1] = from.green + (to.green - from.green) * t;
      colors[i * 3 + 2] = from.blue + (to.blue - from.blue) * t;
    }
    dome.setAttributeFromString(
        'color', tjs.Float32BufferAttribute(colors, 3, false));
    final domeMesh = tjs.Mesh(
      dome,
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.side: tjs.BackSide,
        tjs.MaterialProperty.fog: false,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'sky-dome'
      ..renderOrder = -10
      ..frustumCulled = false;
    group.add(domeMesh);

    // Clouds: puffs of faceted spheres, white on top, a cool shade below.
    final rand = _Rand(4242);
    final clouds = _Merged();
    for (var c = 0; c < 14; c++) {
      final angle = c / 14 * math.pi * 2 + rand.range(-0.2, 0.2);
      final distance = rand.range(380, 560);
      final cx = math.cos(angle) * distance;
      final cz = math.sin(angle) * distance;
      final cy = rand.range(70, 150);
      final scale = rand.range(14, 26);
      final puffs = 4 + rand.below(4);
      for (var p = 0; p < puffs; p++) {
        final px = (p - puffs / 2) * scale * 0.55 + rand.range(-4, 4);
        final py = rand.range(0, scale * 0.35);
        final r = scale * rand.range(0.45, 0.8);
        clouds.add(
          tjg.IcosahedronGeometry(1, 1),
          _place(cx + px * math.cos(angle + math.pi / 2), cy + py,
              cz + px * math.sin(angle + math.pi / 2),
              sx: r, sy: r * 0.62, sz: r),
          _Farm.cloud,
          baseShade: 0.84,
        );
      }
    }
    final cloudGeometry = clouds.build()!;
    _clouds = tjs.Mesh(
      cloudGeometry,
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.fog: false,
      }),
    )
      ..name = 'sky-clouds'
      ..renderOrder = -9
      ..frustumCulled = false;
    group.add(_clouds);
  }

  late final tjs.Group group;
  late final tjs.Mesh _clouds;

  void tick(double time) {
    _clouds.rotation.y = time * 0.006;
  }
}

// ---- the farm -------------------------------------------------------------------------

/// Builds one hole's surroundings; the result is one group the world hangs
/// under the hole's 'scenery' kind.
class _Scenery {
  _Scenery(this.hole, {required this.animated})
      : _rand = _Rand(_seedOf('${hole.id}/farm'));

  final HoleDef hole;
  final List<_Animated> animated;
  final _Rand _rand;

  Rect get _b => hole.bounds;
  double get _span => math.max(_b.width, _b.height);
  static const double _ground = -_tableHeight;

  /// How far [x], [z] stands from the table's edge (0 on or inside it).
  double _clearance(double x, double z) {
    const lip = _fenceThickness + 0.5;
    final dx = math.max(math.max(_b.min.x - lip - x, x - _b.max.x - lip), 0.0);
    final dz = math.max(math.max(_b.min.y - lip - z, z - _b.max.y - lip), 0.0);
    return math.sqrt(dx * dx + dz * dz);
  }

  /// Whether a tall thing at [z] would stand on the camera's side of the
  /// green (the camera hangs on the +z side, the game's south), between
  /// the player and the play.
  bool _cameraSide(double z, {double reach = 46}) =>
      z > _b.max.y && z < _b.max.y + reach;

  tjs.Group build() {
    final group = tjs.Group()..name = 'farm';
    group.add(_meadow());
    final props = _Merged();
    final small = _Merged();
    // The far side (the game's north, -z) carries the farm's landmarks.
    final barnAt = Vec2(_b.center.x + _span * 0.38, _b.min.y - 30);
    final millAt = Vec2(_b.min.x - 30, _b.min.y - 22);
    final hostAt = Vec2(_b.min.x - 7.5, _b.min.y - 3.5);
    final keepOut = [
      (barnAt, 14.0),
      (millAt, 7.0),
      (hostAt, 6.5),
      (Vec2(barnAt.x + 11, barnAt.y + 2), 5.0),
    ];
    bool blocked(double x, double z) {
      for (final (spot, radius) in keepOut) {
        if (Vec2(x, z).distanceTo(spot) < radius) return true;
      }
      return false;
    }

    _trees(props, blocked);
    _bushes(props, blocked);
    _stones(props, blocked);
    _fence(props);
    _hay(props, blocked);
    _flowers(small, blocked);
    _barn(props, barnAt);
    _path(small, from: Vec2(barnAt.x - 1, barnAt.y + 6), to: hostAt);

    final propsMesh = props.mesh('farm-props');
    if (propsMesh != null) group.add(propsMesh);
    final smallMesh = small.mesh('farm-small', castShadow: false);
    if (smallMesh != null) group.add(smallMesh);
    group.add(_windmill(millAt));
    group.add(_host(hostAt));
    return group;
  }

  // ---- the meadow ----------------------------------------------------------------------

  /// The meadow: a wide field of patchy grass rolling up into hills toward
  /// the horizon, the near ring kept flat around the table.
  tjs.Mesh _meadow() {
    const size = 1300.0;
    const segments = 120;
    final geometry = tjs.PlaneGeometry(size, size, segments, segments)
      ..rotateX(-math.pi / 2);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final colors = Float32List(position.count * 3);
    final seed = _seedOf('${hole.id}/meadow');
    final center = _b.center;
    final flatReach = _span * 0.7 + 34;
    for (var i = 0; i < position.count; i++) {
      final lx = position.getX(i)!.toDouble();
      final lz = position.getZ(i)!.toDouble();
      final x = lx + center.x;
      final z = lz + center.y;
      final d = math.sqrt(lx * lx + lz * lz);
      final angle = math.atan2(lz, lx);
      // Hills: rising past the flat ring, their crests from noise around
      // the compass.
      final rise = ((d - flatReach) / 150).clamp(0.0, 1.0);
      final crest = 14 +
          46 * _fbm(angle * 1.6 + 3, d * 0.004, seed) +
          18 * _noise2(angle * 5, 1.5, seed + 3);
      final roll = (_fbm(x * 0.03, z * 0.03, seed + 11) - 0.5) *
          2.4 *
          ((d - _span * 0.6 - 12) / 30).clamp(0.0, 1.0);
      final y = rise * rise * (3 - 2 * rise) * crest + roll;
      position.setXYZ(i, lx, y, lz);
      // Patches of deep and dry grass; the far hills paler.
      final patch = _fbm(x * 0.018, z * 0.018, seed + 5);
      var hex = patch < 0.42
          ? _mix(_Farm.meadowDeep, _Farm.meadow, patch / 0.42)
          : _mix(_Farm.meadow, _Farm.meadowDry, ((patch - 0.42) / 0.58) * 0.8);
      hex = _mix(hex, _Farm.hillFar, (rise * 0.7).clamp(0.0, 1.0));
      final c = _lin(hex);
      colors[i * 3] = c.red;
      colors[i * 3 + 1] = c.green;
      colors[i * 3 + 2] = c.blue;
    }
    geometry
      ..setAttributeFromString(
          'color', tjs.Float32BufferAttribute(colors, 3, false))
      ..computeVertexNormals();
    return tjs.Mesh(
      geometry,
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.roughness: 1.0,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'meadow'
      ..position.setValues(center.x, _ground, center.y)
      ..receiveShadow = true;
  }

  // ---- trees and bushes ----------------------------------------------------------------

  void _trees(_Merged into, bool Function(double, double) blocked) {
    // Groves: a few clusters, and singles scattered between them.
    final spots = <Vec2>[];
    final groves = 7;
    for (var g = 0; g < groves; g++) {
      final center = _spotAround(minClear: 14, maxClear: 70, tall: true);
      if (center == null) continue;
      final count = 4 + _rand.below(6);
      for (var t = 0; t < count; t++) {
        final at = center + Vec2(_rand.range(-9, 9), _rand.range(-9, 9));
        if (_clearance(at.x, at.y) < 9 || _cameraSide(at.y)) continue;
        spots.add(at);
      }
    }
    for (var s = 0; s < 26; s++) {
      final at = _spotAround(minClear: 10, maxClear: 110, tall: true);
      if (at != null) spots.add(at);
    }
    for (final at in spots) {
      if (blocked(at.x, at.y)) continue;
      final scale = _rand.range(0.85, 1.55) *
          (1 + (_clearance(at.x, at.y) / 120).clamp(0.0, 0.5));
      if (_rand.chance(0.32)) {
        _pine(into, at, scale);
      } else {
        _oak(into, at, scale);
      }
    }
  }

  /// A random spot whose clearance from the table lies in the range; tall
  /// things never stand on the camera's side. Null after too many tries.
  Vec2? _spotAround(
      {required double minClear, required double maxClear, bool tall = false}) {
    for (var attempt = 0; attempt < 40; attempt++) {
      final x = _rand.range(_b.min.x - maxClear, _b.max.x + maxClear);
      final z = _rand.range(_b.min.y - maxClear, _b.max.y + maxClear);
      final clear = _clearance(x, z);
      if (clear < minClear || clear > maxClear) continue;
      if (tall && _cameraSide(z)) continue;
      return Vec2(x, z);
    }
    return null;
  }

  void _oak(_Merged into, Vec2 at, double scale) {
    final trunkHeight = 2.4 * scale;
    into.add(
      tjg.CylinderGeometry(0.28 * scale, 0.42 * scale, trunkHeight, 7),
      _place(at.x, _ground + trunkHeight / 2, at.y),
      _Farm.trunk,
      baseShade: 0.7,
    );
    final autumn = _rand.chance(0.12);
    final leaves = [_Farm.leafA, _Farm.leafB, _Farm.leafC];
    final puffs = 3 + _rand.below(3);
    for (var p = 0; p < puffs; p++) {
      final angle = p / puffs * math.pi * 2 + _rand.range(0, 1);
      final reach = p == 0 ? 0.0 : _rand.range(0.8, 1.4) * scale;
      final r = _rand.range(1.3, 1.9) * scale;
      into.add(
        tjg.IcosahedronGeometry(1, 1),
        _place(
          at.x + math.cos(angle) * reach,
          _ground + trunkHeight + r * 0.75 + (p == 0 ? r * 0.35 : 0),
          at.y + math.sin(angle) * reach,
          yaw: _rand.range(0, 6.28),
          sx: r,
          sy: r * 0.9,
          sz: r,
        ),
        autumn && p.isOdd ? _Farm.leafAutumn : leaves[_rand.below(3)],
        baseShade: 0.62,
        rand: _rand,
        variation: 0.08,
      );
    }
  }

  void _pine(_Merged into, Vec2 at, double scale) {
    final trunkHeight = 1.6 * scale;
    into.add(
      tjg.CylinderGeometry(0.22 * scale, 0.32 * scale, trunkHeight, 6),
      _place(at.x, _ground + trunkHeight / 2, at.y),
      _Farm.trunk,
      baseShade: 0.7,
    );
    var y = _ground + trunkHeight;
    for (var tier = 0; tier < 3; tier++) {
      final r = (2.1 - tier * 0.5) * scale;
      final h = (2.4 - tier * 0.3) * scale;
      into.add(
        tjg.ConeGeometry(r, h, 7),
        _place(at.x, y + h / 2, at.y, yaw: _rand.range(0, 6.28)),
        _Farm.leafC,
        baseShade: 0.55,
        rand: _rand,
        variation: 0.1,
      );
      y += h * 0.55;
    }
  }

  void _bushes(_Merged into, bool Function(double, double) blocked) {
    for (var i = 0; i < 46; i++) {
      final at = _spotAround(minClear: 1.6, maxClear: 22);
      if (at == null || blocked(at.x, at.y)) continue;
      final r = _rand.range(0.55, 1.05);
      final lumps = 2 + _rand.below(2);
      for (var l = 0; l < lumps; l++) {
        into.add(
          tjg.IcosahedronGeometry(1, 1),
          _place(at.x + _rand.range(-0.6, 0.6), _ground + r * 0.7,
              at.y + _rand.range(-0.6, 0.6),
              sx: r, sy: r * 0.82, sz: r),
          _rand.chance(0.5) ? _Farm.leafB : _Farm.leafA,
          baseShade: 0.6,
          rand: _rand,
          variation: 0.1,
        );
      }
      if (_rand.chance(0.35)) {
        for (var berry = 0; berry < 5; berry++) {
          into.add(
            tjg.IcosahedronGeometry(0.09, 0),
            _place(
                at.x + _rand.range(-0.8, 0.8),
                _ground + r * _rand.range(0.9, 1.4),
                at.y + _rand.range(-0.8, 0.8)),
            _Farm.flowerRed,
          );
        }
      }
    }
  }

  void _stones(_Merged into, bool Function(double, double) blocked) {
    for (var i = 0; i < 18; i++) {
      final at = _spotAround(minClear: 2, maxClear: 40);
      if (at == null || blocked(at.x, at.y)) continue;
      final r = _rand.range(0.3, 0.9);
      into.add(
        tjg.DodecahedronGeometry(1, 0),
        _place(at.x, _ground + r * 0.3, at.y,
            yaw: _rand.range(0, 6.28),
            tilt: _rand.range(-0.3, 0.3),
            sx: r * 1.2,
            sy: r * 0.7,
            sz: r),
        _rand.chance(0.5) ? _Farm.rock : _Farm.rockDark,
        baseShade: 0.7,
      );
    }
  }

  // ---- the fence around the table --------------------------------------------------------

  /// A white picket fence around the table at a stroll's distance, open on
  /// the camera's side where the path comes in.
  void _fence(_Merged into) {
    const gap = 3.6;
    final minX = _b.min.x - gap - _fenceThickness;
    final maxX = _b.max.x + gap + _fenceThickness;
    final minZ = _b.min.y - gap - _fenceThickness;
    final maxZ = _b.max.y + gap + _fenceThickness;
    final corners = [
      Vec2(minX, minZ),
      Vec2(maxX, minZ),
      Vec2(maxX, maxZ),
      Vec2(minX, maxZ),
    ];
    const spacing = 1.7;
    for (var side = 0; side < 4; side++) {
      final a = corners[side];
      final b = corners[(side + 1) % 4];
      final length = a.distanceTo(b);
      final steps = (length / spacing).floor();
      final direction = (b - a).normalized(const Vec2(1, 0));
      final yaw = -math.atan2(direction.y, direction.x);
      for (var s = 0; s <= steps; s++) {
        final at = a + direction * (s * spacing);
        // The gate: the middle of the camera's side stays open.
        if (side == 2 && (at.x - _b.center.x).abs() < 5) continue;
        into.add(
          tjs.BoxGeometry(0.16, 1.05, 0.12),
          _place(at.x, _ground + 0.52, at.y, yaw: yaw),
          _Farm.trim,
          baseShade: 0.78,
        );
        into.add(
          tjg.ConeGeometry(0.12, 0.2, 4),
          _place(at.x, _ground + 1.15, at.y, yaw: yaw + math.pi / 4),
          _Farm.trim,
        );
        if (s < steps) {
          final next = a + direction * ((s + 1) * spacing);
          if (side == 2 && (next.x - _b.center.x).abs() < 5) continue;
          final mid = (at + next) * 0.5;
          for (final h in const [0.38, 0.8]) {
            into.add(
              tjs.BoxGeometry(spacing, 0.09, 0.06),
              _place(mid.x, _ground + h, mid.y, yaw: yaw),
              _Farm.trim,
            );
          }
        }
      }
    }
  }

  void _hay(_Merged into, bool Function(double, double) blocked) {
    for (var i = 0; i < 6; i++) {
      final at = _spotAround(minClear: 5, maxClear: 26);
      if (at == null || blocked(at.x, at.y)) continue;
      final r = _rand.range(0.8, 1.05);
      final yaw = _rand.range(0, 6.28);
      into.add(
        tjg.CylinderGeometry(r, r, r * 1.7, 18, 2),
        _place(at.x, _ground + r, at.y, yaw: yaw, roll: math.pi / 2),
        _Farm.hay,
        baseShade: 0.72,
      );
      for (final side in [-1.0, 1.0]) {
        final ox = math.cos(-yaw) * side * (r * 0.86);
        final oz = math.sin(-yaw) * side * (r * 0.86);
        into.add(
          tjg.CylinderGeometry(r * 0.9, r * 0.9, 0.04, 18),
          _place(at.x + ox, _ground + r, at.y + oz,
              yaw: yaw, roll: math.pi / 2),
          _Farm.hayDark,
        );
      }
    }
  }

  // ---- flowers and tufts -------------------------------------------------------------------

  void _flowers(_Merged into, bool Function(double, double) blocked) {
    const heads = [
      _Farm.flowerRed,
      _Farm.flowerYolk,
      _Farm.flowerCream,
      _Farm.flowerPink,
      _Farm.flowerYolk,
    ];
    // Patches: flowers come in drifts, not evenly.
    for (var patch = 0; patch < 26; patch++) {
      final center = _spotAround(minClear: 1.2, maxClear: 38);
      if (center == null) continue;
      final head = heads[_rand.below(heads.length)];
      final count = 8 + _rand.below(14);
      for (var f = 0; f < count; f++) {
        final x = center.x + _rand.range(-3.2, 3.2);
        final z = center.y + _rand.range(-3.2, 3.2);
        if (_clearance(x, z) < 1.0 || blocked(x, z)) continue;
        final h = _rand.range(0.28, 0.5);
        into.add(tjs.BoxGeometry(0.04, h, 0.04), _place(x, _ground + h / 2, z),
            _Farm.leafC);
        into.add(
          tjg.IcosahedronGeometry(_rand.range(0.1, 0.16), 0),
          _place(x, _ground + h, z, sy: 0.6),
          head,
        );
      }
    }
    // Tufts: three blades each, darker than the meadow.
    for (var t = 0; t < 320; t++) {
      final at = _spotAround(minClear: 0.8, maxClear: 30);
      if (at == null || blocked(at.x, at.y)) continue;
      final hex = _rand.chance(0.5) ? _Farm.leafB : _Farm.leafA;
      for (var blade = 0; blade < 3; blade++) {
        final h = _rand.range(0.35, 0.7);
        into.add(
          tjg.ConeGeometry(0.07, h, 3),
          _place(at.x + _rand.range(-0.12, 0.12), _ground + h / 2,
              at.y + _rand.range(-0.12, 0.12),
              tilt: _rand.range(-0.35, 0.35), roll: _rand.range(-0.35, 0.35)),
          hex,
          baseShade: 0.7,
        );
      }
    }
  }

  /// A dirt path from [from] winding to [to]: a sandy ribbon on the grass.
  void _path(_Merged into, {required Vec2 from, required Vec2 to}) {
    const steps = 28;
    final bend = Vec2(-(to.y - from.y), to.x - from.x).normalized(Vec2.zero) *
        (from.distanceTo(to) * 0.18);
    for (var i = 0; i < steps; i++) {
      final t0 = i / steps;
      final t1 = (i + 1) / steps;
      Vec2 at(double t) =>
          from + (to - from) * t + bend * math.sin(t * math.pi);
      final a = at(t0);
      final b = at(t1);
      final run = b - a;
      final mid = (a + b) * 0.5;
      into.add(
        tjs.BoxGeometry(run.length + 0.4, 0.04, 1.9),
        _place(mid.x, _ground + 0.02, mid.y, yaw: -math.atan2(run.y, run.x)),
        _Farm.path,
      );
    }
  }

  // ---- the barn ------------------------------------------------------------------------

  /// The red barn with cream trim, its X-braced doors facing the green, a
  /// hay loft and the silo beside it.
  void _barn(_Merged into, Vec2 at) {
    const width = 13.0;
    const depth = 10.0;
    const wallHeight = 6.4;
    const roofHeight = 4.6;
    final x = at.x;
    final z = at.y;
    final base = _ground;
    into.add(tjs.BoxGeometry(width, wallHeight, depth),
        _place(x, base + wallHeight / 2, z), _Farm.barnRed,
        baseShade: 0.8);
    // The gable: a prism under the roof slabs.
    into.add(_prism(width, roofHeight, depth), _place(x, base + wallHeight, z),
        _Farm.barnRed);
    // Roof slabs, overhanging.
    final half = width / 2 + 0.5;
    final slope = math.atan2(roofHeight, width / 2);
    final slabLength = math.sqrt(half * half + roofHeight * roofHeight) + 0.2;
    for (final side in [-1.0, 1.0]) {
      into.add(
        tjs.BoxGeometry(slabLength, 0.32, depth + 1.2),
        _place(
          x + side * half / 2,
          base + wallHeight + roofHeight / 2 + 0.2,
          z,
          roll: -side * slope,
        ),
        _Farm.roof,
      );
    }
    // Ridge cap.
    into.add(tjs.BoxGeometry(0.5, 0.3, depth + 1.3),
        _place(x, base + wallHeight + roofHeight + 0.25, z), _Farm.roofDark);
    // Trim: corner boards and the eave line, on the face toward the green.
    final front = z + depth / 2 + 0.06;
    for (final cx in [x - width / 2 + 0.2, x + width / 2 - 0.2]) {
      into.add(tjs.BoxGeometry(0.42, wallHeight, depth + 0.12),
          _place(cx, base + wallHeight / 2, z), _Farm.trim);
    }
    // The doors: dark red leaves in a cream frame, the X braces.
    const doorWidth = 4.6;
    const doorHeight = 4.6;
    into.add(tjs.BoxGeometry(doorWidth + 0.5, doorHeight + 0.4, 0.12),
        _place(x, base + doorHeight / 2 + 0.1, front), _Farm.trim);
    into.add(tjs.BoxGeometry(doorWidth, doorHeight, 0.16),
        _place(x, base + doorHeight / 2, front + 0.02), _Farm.barnRedDark);
    final braceLength =
        math.sqrt(doorWidth * doorWidth / 4 + doorHeight * doorHeight);
    final braceAngle = math.atan2(doorHeight, doorWidth / 2);
    for (final leaf in [-1.0, 1.0]) {
      final cx = x + leaf * doorWidth / 4;
      for (final dir in [-1.0, 1.0]) {
        into.add(
          tjs.BoxGeometry(braceLength, 0.28, 0.1),
          _place(cx, base + doorHeight / 2, front + 0.1,
              roll: dir * braceAngle),
          _Farm.trim,
        );
      }
      into.add(tjs.BoxGeometry(0.22, doorHeight, 0.1),
          _place(x, base + doorHeight / 2, front + 0.1), _Farm.trim);
    }
    // The hay loft door, bales peeking out.
    into.add(tjs.BoxGeometry(2.6, 2.2, 0.12),
        _place(x, base + wallHeight + 1.4, front), _Farm.trim);
    into.add(tjs.BoxGeometry(2.1, 1.7, 0.14),
        _place(x, base + wallHeight + 1.35, front + 0.02), 0x3A2418);
    into.add(tjs.BoxGeometry(1.6, 0.7, 0.6),
        _place(x, base + wallHeight + 0.85, front + 0.15), _Farm.hay);
    // The silo beside it.
    final sx = x + width / 2 + 4.2;
    final sz = z - 1.5;
    into.add(tjg.CylinderGeometry(2.4, 2.4, 13, 20), _place(sx, base + 6.5, sz),
        _Farm.silo,
        baseShade: 0.82);
    into.add(tjs.SphereGeometry(2.5, 20, 10, 0, math.pi * 2, 0, math.pi / 2),
        _place(sx, base + 13, sz, sy: 0.7), _Farm.siloRoof);
    for (final h in const [3.0, 6.5, 10.0]) {
      into.add(tjg.TorusGeometry(2.45, 0.08, 5, 28),
          _place(sx, base + h, sz, tilt: math.pi / 2), _Farm.metalDark);
    }
  }

  /// A triangular prism: the gable's triangle in x/y (apex up), extruded
  /// along z.
  tjs.BufferGeometry _prism(double width, double height, double depth) {
    final w = width / 2;
    final d = depth / 2;
    final positions = <double>[
      // front triangle (z = -d), facing -z
      -w, 0, -d, 0, height, -d, w, 0, -d,
      // back triangle (z = +d), facing +z
      -w, 0, d, w, 0, d, 0, height, d,
      // left slope
      -w, 0, -d, -w, 0, d, 0, height, d,
      -w, 0, -d, 0, height, d, 0, height, -d,
      // right slope
      w, 0, -d, 0, height, -d, 0, height, d,
      w, 0, -d, 0, height, d, w, 0, d,
    ];
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
      ..computeVertexNormals();
  }

  // ---- the windmill ----------------------------------------------------------------------

  /// A windmill on the hillside: a cream tower, a red cap, four sails
  /// turning in the breeze.
  tjs.Group _windmill(Vec2 at) {
    final group = tjs.Group()
      ..name = 'windmill'
      ..position.setValues(at.x, _ground, at.y);
    final tower = _Merged()
      ..add(
          tjg.CylinderGeometry(1.5, 2.4, 11, 8), _place(0, 5.5, 0), _Farm.trim,
          baseShade: 0.8)
      ..add(tjg.ConeGeometry(2.2, 2.6, 8), _place(0, 12.3, 0), _Farm.barnRed)
      ..add(tjs.BoxGeometry(1.2, 2.0, 0.2), _place(0, 1.0, 2.1), _Farm.roofDark)
      ..add(tjs.BoxGeometry(0.9, 0.9, 0.2), _place(0, 6.5, 1.75), 0x5B87A8)
      ..add(tjs.BoxGeometry(0.9, 0.9, 0.2), _place(0, 9.0, 1.55), 0x5B87A8);
    group.add(tower.mesh('windmill-tower')!);
    final hub = tjs.Group()
      ..name = 'windmill-sails'
      ..position.setValues(0, 10.6, 2.1);
    final sails = _Merged()
      ..add(tjg.CylinderGeometry(0.45, 0.45, 0.6, 10),
          _place(0, 0, 0, tilt: math.pi / 2), _Farm.roofDark);
    for (var blade = 0; blade < 4; blade++) {
      final angle = blade * math.pi / 2;
      final reach = 3.4;
      sails.add(
        tjs.BoxGeometry(0.22, 6.2, 0.12),
        _place(0, 0, 0, roll: angle)
          ..multiply(tjs.Matrix4().makeTranslation(0, reach, 0)),
        _Farm.roofDark,
      );
      sails.add(
        tjs.BoxGeometry(1.5, 5.0, 0.06),
        _place(0, 0, 0.02, roll: angle)
          ..multiply(tjs.Matrix4().makeTranslation(0.8, reach + 0.4, 0)),
        _Farm.trim,
      );
    }
    hub.add(sails.mesh('windmill-sail', flat: true)!);
    group.add(hub);
    animated.add(_AnimatedBy((time, dt) {
      hub.rotation.z = time * 0.7;
    }));
    return group;
  }

  // ---- the host -------------------------------------------------------------------------

  /// The host: a big white rooster in profile beside the green, comb like a
  /// crown, headphones on (he is always in the call), bobbing his head
  /// once in a while to the beat.
  tjs.Group _host(Vec2 at) {
    // He stands on the green's far left looking across it, turned a touch
    // toward the camera: on screen his beak points right, the way the
    // mark faces.
    final group = tjs.Group()
      ..name = 'host'
      ..position.setValues(at.x, _ground, at.y)
      ..rotation.y = -0.45;
    const white = 0xFCF8F1;
    const shade = 0xEDE3D3;
    final comb = _hexOf(PuttPalette.comb);
    final yolk = _hexOf(PuttPalette.yolk);
    final ink = _hexOf(PuttPalette.ink);
    const spruce = 0x2E3B33;
    final body = _Merged();
    // Legs and feet.
    for (final side in [-0.75, 0.75]) {
      body.add(tjg.CylinderGeometry(0.22, 0.26, 2.4, 8), _place(0.1, 1.2, side),
          yolk);
      for (final toe in [-0.5, 0.0, 0.5]) {
        body.add(tjs.BoxGeometry(1.0, 0.22, 0.24),
            _place(0.55, 0.11, side + toe * 0.6, yaw: -toe * 0.7), yolk);
      }
    }
    // Body, breast and wing.
    body.add(tjs.SphereGeometry(1, 24, 16),
        _place(0, 4.3, 0, sx: 2.6, sy: 2.2, sz: 2.0), white,
        baseShade: 0.82);
    body.add(tjs.SphereGeometry(1, 20, 14),
        _place(1.5, 4.7, 0, sx: 1.7, sy: 1.8, sz: 1.6), white);
    for (final side in [-1.0, 1.0]) {
      body.add(
          tjs.SphereGeometry(1, 18, 12),
          _place(-0.3, 4.5, side * 1.75,
              tilt: side * 0.2, sx: 1.9, sy: 1.2, sz: 0.45),
          shade);
    }
    // The tail: dark sickle feathers with a spruce sheen.
    for (var f = 0; f < 5; f++) {
      final lift = 0.5 + f * 0.22;
      body.add(
        tjg.ConeGeometry(0.42, 3.4 - f * 0.25, 8),
        _place(-2.4 - f * 0.12, 5.6 + f * 0.25, (f - 2) * 0.28,
            roll: lift, yaw: (f - 2) * 0.12),
        f.isEven ? ink : spruce,
      );
    }
    // The neck.
    body.add(tjg.CylinderGeometry(0.85, 1.25, 2.4, 14),
        _place(1.9, 6.3, 0, roll: -0.35), white);
    group.add(body.mesh('host-body', flat: false, roughness: 0.75)!);

    // The head, which bobs: comb, beak, wattle, eyes and the headphones.
    final head = tjs.Group()
      ..name = 'host-head'
      ..position.setValues(2.5, 7.4, 0);
    final face = _Merged();
    face.add(
        tjs.SphereGeometry(1.25, 22, 16), _place(0, 0, 0, sx: 1.08), white);
    final lobes = [
      (0.55, 1.25, 0.55),
      (-0.05, 1.45, 0.6),
      (-0.7, 1.35, 0.52),
      (-1.2, 1.0, 0.42),
    ];
    for (final (lx, ly, lr) in lobes) {
      face.add(
          tjs.SphereGeometry(lr, 14, 10), _place(lx, ly, 0, sz: 0.62), comb);
    }
    face.add(tjg.ConeGeometry(0.42, 1.05, 12),
        _place(1.45, -0.12, 0, roll: -math.pi / 2), yolk);
    face.add(tjs.SphereGeometry(0.42, 12, 10),
        _place(1.0, -0.95, 0, sx: 0.8, sy: 1.25, sz: 0.6), comb);
    for (final side in [-1.0, 1.0]) {
      face.add(
          tjs.SphereGeometry(0.2, 10, 8), _place(0.55, 0.28, side * 1.02), ink);
      face.add(tjs.SphereGeometry(0.07, 8, 6), _place(0.62, 0.36, side * 1.17),
          white);
    }
    // Headphones: the band over the crown, a cup on each cheek.
    face.add(tjg.TorusGeometry(1.42, 0.15, 8, 28, math.pi),
        _place(-0.2, 0.05, 0, yaw: math.pi / 2), ink);
    for (final side in [-1.0, 1.0]) {
      face.add(tjg.CylinderGeometry(0.62, 0.62, 0.42, 20),
          _place(-0.2, 0.02, side * 1.32, tilt: math.pi / 2), ink);
      face.add(tjg.TorusGeometry(0.42, 0.08, 6, 20),
          _place(-0.2, 0.02, side * 1.55), comb);
    }
    head.add(face.mesh('host-face', flat: false, roughness: 0.7)!);
    group.add(head);
    animated.add(_AnimatedBy((time, dt) {
      // A bar of nodding every few seconds, still in between.
      final phase = time % 6.0;
      final nod = phase < 2.4 ? math.sin(phase * math.pi * 2.5).abs() : 0.0;
      head.rotation.z = -nod * 0.16;
      head.position.y = 7.4 - nod * 0.12;
    }));
    return group;
  }
}
