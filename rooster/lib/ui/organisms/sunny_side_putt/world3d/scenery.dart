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
    _domeHeights = Float32List(position.count);
    for (var i = 0; i < position.count; i++) {
      _domeHeights[i] = (position.getY(i)! / 900).toDouble();
    }
    // The colours come with the theme ([recolor]).
    _domeColors =
        tjs.Float32BufferAttribute(Float32List(position.count * 3), 3, false);
    dome.setAttributeFromString('color', _domeColors);
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

    tjs.Sprite glow(String name, double size, double opacity) => tjs.Sprite(
          tjs.SpriteMaterial({
            tjs.MaterialProperty.map: _EggView3D._shadowTexture,
            tjs.MaterialProperty.color: 0xFFFFFF,
            tjs.MaterialProperty.transparent: true,
            tjs.MaterialProperty.opacity: opacity,
            tjs.MaterialProperty.depthWrite: false,
            tjs.MaterialProperty.blending: tjs.AdditiveBlending,
            tjs.MaterialProperty.fog: false,
          }),
        )
          ..name = name
          ..scale.setValues(size, size, 1)
          ..renderOrder = -8
          ..frustumCulled = false;
    _sunHalo = glow('sky-sun-halo', 520, 0.32);
    _sunDisc = glow('sky-sun', 120, 1.0);
    group
      ..add(_sunHalo)
      ..add(_sunDisc);
  }

  late final tjs.Group group;
  late final tjs.Mesh _clouds;

  /// The dome's colours per vertex height, kept for recolouring.
  late final tjs.BufferAttribute _domeColors;
  late final Float32List _domeHeights;

  void tick(double time) {
    _clouds.rotation.y = time * 0.006;
  }

  /// The sun's disc and its halo, hung on the dome toward the theme's sun.
  late final tjs.Sprite _sunDisc;
  late final tjs.Sprite _sunHalo;

  /// Paints the dome for [theme]'s hour: horizon, middle, top.
  void recolor(_Theme theme) {
    final (sx, sy, sz) = theme.sunFrom;
    final direction = tjs.Vector3(sx, sy, sz).normalize();
    _sunDisc.position.setFrom(direction.clone().scale(820));
    _sunHalo.position.setFrom(direction.clone().scale(830));
    _sunDisc.material?.color = _lin(_mix(theme.sun, 0xFFFFFF, 0.55));
    _sunHalo.material?.color = _lin(theme.sun);
    final horizon = _lin(theme.horizon);
    final mid = _lin(theme.skyMid);
    final top = _lin(theme.skyTop);
    for (var i = 0; i < _domeHeights.length; i++) {
      final (r, g, b) = _skyAt(_domeHeights[i], horizon, mid, top);
      _domeColors.setXYZ(i, r, g, b);
    }
    _domeColors.needsUpdate = true;
    _clouds.material?.color = _lin(theme.clouds);
  }
}

/// The sky's colour at height [h] (0 the horizon, 1 the zenith).
(double, double, double) _skyAt(
    double h, tjs.Color horizon, tjs.Color mid, tjs.Color top) {
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
  return (
    from.red + (to.red - from.red) * t,
    from.green + (to.green - from.green) * t,
    from.blue + (to.blue - from.blue) * t,
  );
}

// ---- the farm -------------------------------------------------------------------------

/// Builds one hole's surroundings; the result is one group the world hangs
/// under the hole's 'scenery' kind.
class _Scenery {
  _Scenery(this.hole,
      {required this.animated,
      required this.theme,
      required this.cheerUntil,
      required this.shape,
      Vec2? Function()? watch})
      : watch = watch ?? (() => null),
        _rand = _Rand(_seedOf('${hole.id}/farm'));

  /// The egg the host keeps his eye on (the one rolling, else the
  /// viewer's), or null.
  final Vec2? Function() watch;

  /// The table's shape: the meadow fills what the walls carved away.
  final _TableShape shape;

  /// Until when (the frame clock) the host is cheering: an egg just
  /// dropped into the nest.
  final double Function() cheerUntil;

  final HoleDef hole;
  final List<_Animated> animated;
  final _Theme theme;
  final _Rand _rand;

  Rect get _b => hole.bounds;
  double get _span => math.max(_b.width, _b.height);
  static const double _ground = -_tableHeight;

  /// Where the host stands: beyond the side rail on the nest's side, in
  /// the far half of the green - in the play view that is the upper half
  /// of the screen, clear of the HUD's top bar.
  Vec2 get _hostAt {
    final nest = hole.nest.position;
    final right = nest.x >= _b.center.x;
    return Vec2(
      right ? _b.max.x + 5.5 : _b.min.x - 5.5,
      nest.y.clamp(_b.min.y + 2.5, _b.center.y).toDouble(),
    );
  }

  /// His turn about the vertical: facing the green, a little toward the
  /// camera's side (local +x is where he looks).
  double get _hostTurn {
    final at = _hostAt;
    final toward = (_b.center - at).normalized(const Vec2(1, 0));
    final facing = Vec2(toward.x, toward.y + 0.75);
    return math.atan2(-facing.y, facing.x);
  }

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
    // What stands beyond the sun's shadow box casts no shadow (see
    // `_aimSun`: the box reaches span * 0.62 + 12 round the green).
    final props =
        _Merged(shadowCenter: _b.center, shadowReach: _span * 0.62 + 16);
    final small = _Merged();
    final kind = theme.kind;
    // The far side (the game's north, -z) carries the farm's landmarks;
    // where they stand depends on the course's corner of the farm.
    // The host watches from the far side, by the nest's end of the green,
    // where the close camera keeps him in frame.
    final hostAt = _hostAt;
    final barnAt = switch (kind) {
      _ThemeKind.barn => Vec2(_b.center.x + 4, _b.min.y - 19),
      _ThemeKind.maze => Vec2(_b.center.x + _span * 0.42, _b.min.y - 52),
      _ThemeKind.pond => Vec2(_b.max.x + 26, _b.min.y - 18),
      _ => Vec2(_b.center.x + _span * 0.38, _b.min.y - 30),
    };
    final barnScale = kind == _ThemeKind.barn ? 1.35 : 1.0;
    // Each corner of the farm has its own landmarks: the barn by the Coop
    // and as the Barn itself, a water tower over Farm Road, the windmill
    // by the Pond and the Road; the maze sees nothing but corn.
    final hasBarn = kind == _ThemeKind.coop || kind == _ThemeKind.barn;
    final hasMill = kind == _ThemeKind.pond || kind == _ThemeKind.road;
    final towerAt = Vec2(_b.center.x + _span * 0.38, _b.min.y - 30);
    final millAt = Vec2(_b.min.x - 30, _b.min.y - 22);
    final lakeAt = Vec2(_b.center.x - 2, _b.min.y - 30);
    const lakeRadius = 22.0;
    final henHouseAt = Vec2(_b.max.x + 10, _b.min.y - 7);
    final roadZ = _b.min.y - 13.0;
    final keepOut = <(Vec2, double)>[
      if (hasBarn) (barnAt, 14.0 * barnScale),
      if (hasBarn) (Vec2(barnAt.x + 11 * barnScale, barnAt.y - 2), 5.0),
      if (kind == _ThemeKind.road) (towerAt, 7.5),
      if (hasMill) (millAt, 7.0),
      (hostAt, 6.5),
      if (kind == _ThemeKind.pond) (lakeAt, lakeRadius + 3),
      if (kind == _ThemeKind.coop) (henHouseAt, 6.5),
    ];
    bool blocked(double x, double z) {
      if (kind == _ThemeKind.road && (z - roadZ).abs() < 4.5) return true;
      if (kind == _ThemeKind.maze && _inCornField(x, z)) return true;
      for (final (spot, radius) in keepOut) {
        if (Vec2(x, z).distanceTo(spot) < radius) return true;
      }
      return false;
    }

    _carvedMeadow(props, small);
    _trees(props, blocked);
    _bushes(props, blocked);
    _stones(props, blocked);
    _fence(props);
    _hay(props, blocked);
    _flowers(small, blocked);
    if (hasBarn) _barn(props, barnAt, scale: barnScale);
    switch (kind) {
      case _ThemeKind.coop:
        _henHouse(props, henHouseAt);
        _yardHens(props, henHouseAt);
        _path(small, from: Vec2(barnAt.x - 1, barnAt.y + 6), to: hostAt);
      case _ThemeKind.maze:
        _cornField(props);
        _scarecrow(props, Vec2(_b.center.x - 14, _b.min.y - 9));
      case _ThemeKind.pond:
        group.add(_lake(lakeAt, lakeRadius));
        _reeds(props, lakeAt, lakeRadius);
        _dock(props, lakeAt, lakeRadius);
        _ducks(group, lakeAt, lakeRadius);
      case _ThemeKind.road:
        _road(small, roadZ);
        _tractor(props, Vec2(_b.center.x + 9, roadZ - 0.2));
        _waterTower(props, towerAt);
        _poles(group, props, roadZ - 3.4);
        _fields(group, roadZ);
      case _ThemeKind.barn:
        _path(small,
            from: Vec2(barnAt.x, barnAt.y + 9),
            to: Vec2(_b.center.x, _b.min.y - 4));
        _haystacks(props, barnAt);
        _lanterns(group, props);
        _fireflies(group);
    }

    final propsMesh = props.mesh('farm-props');
    if (propsMesh != null) group.add(propsMesh);
    final farMesh = props.farMesh('farm-props-far');
    if (farMesh != null) group.add(farMesh);
    final smallMesh = small.mesh('farm-small', castShadow: false);
    if (smallMesh != null) group.add(smallMesh);
    if (hasMill) group.add(_windmill(millAt));
    group.add(_host(hostAt));
    if (kind != _ThemeKind.barn) group.add(_butterflies());
    group.add(_birds());
    return group;
  }

  /// Butterflies fluttering over the meadow by the table (the dusk keeps
  /// fireflies instead).
  tjs.Group _butterflies() {
    final group = tjs.Group()..name = 'butterflies';
    const colors = [
      _Farm.flowerYolk,
      _Farm.flowerCream,
      _Farm.flowerPink,
      0x7FC6F2,
      _Farm.flowerYolk,
      0xFFFFFF,
    ];
    final flyers = <(tjs.Group, tjs.Mesh, tjs.Mesh, Vec2, double, double)>[];
    for (var i = 0; i < 9; i++) {
      final home = _spotAround(minClear: 0.6, maxClear: 9) ?? _b.center;
      final hex = colors[i % colors.length];
      final butterfly = tjs.Group()..name = 'butterfly';
      tjs.Mesh wing(double side) {
        // Built flat (in x/z), off to its side of the body.
        final mesh = tjs.Mesh(
          tjg.CircleGeometry(radius: 0.18, segments: 8)
            ..rotateX(-math.pi / 2)
            ..translate(side * 0.16, 0, 0),
          tjs.MeshStandardMaterial({
            tjs.MaterialProperty.color: _lin(hex),
            tjs.MaterialProperty.roughness: 0.7,
            tjs.MaterialProperty.metalness: 0.0,
            tjs.MaterialProperty.side: tjs.DoubleSide,
          }),
        )..name = 'butterfly-wing';
        return mesh;
      }

      final left = wing(-1);
      final right = wing(1);
      butterfly
        ..add(left)
        ..add(right)
        ..add(tjs.Mesh(
          tjg.CylinderGeometry(0.025, 0.025, 0.22, 5),
          _matte(0x3A2A20),
        )..rotation.x = math.pi / 2);
      group.add(butterfly);
      flyers.add((
        butterfly,
        left,
        right,
        home,
        _rand.range(0, 6.28),
        _rand.range(0.7, 1.3)
      ));
    }
    animated.add(_AnimatedBy((time, dt) {
      for (final (body, left, right, home, phase, speed) in flyers) {
        final t = time * speed + phase;
        final x = home.x + math.sin(t * 0.7) * 2.6 + math.sin(t * 1.9) * 0.6;
        final z = home.y + math.cos(t * 0.53) * 2.2;
        final y = _ground + 1.1 + math.sin(t * 2.3).abs() * 0.7 + 0.3;
        body.position.setValues(x, y, z);
        body.rotation.y = -t * 0.7;
        // The wings fold up about the body's long axis.
        final flap = math.sin(time * 18 + phase) * 1.1;
        left.rotation.z = -flap;
        right.rotation.z = flap;
      }
    }));
    return group;
  }

  /// Birds gliding in wide circles high over the farm, a lazy flap now
  /// and then.
  tjs.Group _birds() {
    final group = tjs.Group()..name = 'birds';
    final birds = <(tjs.Group, tjs.Mesh, tjs.Mesh, double, double, double)>[];
    final dark = theme.kind == _ThemeKind.barn ? 0x2A2228 : 0x3A3A44;
    for (var i = 0; i < 5; i++) {
      final bird = tjs.Group()..name = 'bird';
      final body = tjs.Mesh(
        tjg.ConeGeometry(0.22, 1.0, 5)..rotateX(math.pi / 2),
        _matte(dark),
      );
      tjs.Mesh wing(double side) => tjs.Mesh(
            tjs.BoxGeometry(1.5, 0.04, 0.45)..translate(side * 0.75, 0, 0),
            _matte(dark),
          );
      final left = wing(-1);
      final right = wing(1);
      bird
        ..add(body)
        ..add(left)
        ..add(right);
      group.add(bird);
      birds.add((
        bird,
        left,
        right,
        _rand.range(0, 6.28),
        _rand.range(18, 34),
        _rand.range(16, 26)
      ));
    }
    final center = _b.center;
    animated.add(_AnimatedBy((time, dt) {
      for (final (bird, left, right, phase, radius, height) in birds) {
        final angle = phase + time * 0.11;
        bird.position.setValues(
          center.x + math.cos(angle) * radius,
          height + math.sin(time * 0.4 + phase) * 1.5,
          center.y - 18 + math.sin(angle) * radius * 0.6,
        );
        // Facing along the circle (counter-clockwise seen from above).
        bird.rotation.y = -angle;
        final beat = math.sin(time * 6 + phase);
        final flap = (math.sin(time * 0.7 + phase) > 0.3 ? beat * 0.5 : 0.08);
        left.rotation.z = flap;
        right.rotation.z = -flap;
      }
    }));
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
          ? _mix(theme.meadowDeep, theme.meadow, patch / 0.42)
          : _mix(theme.meadow, theme.meadowDry, ((patch - 0.42) / 0.58) * 0.8);
      hex = _mix(hex, theme.hillFar, (rise * 0.7).clamp(0.0, 1.0));
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

  /// The ground the walls carved off the table, down at the meadow's
  /// level: bushes, flowers and tufts grow there, clear of the skirt.
  void _carvedMeadow(_Merged props, _Merged small) {
    if (!shape.carved) return;
    final rand = _Rand(_seedOf('${hole.id}/carved'));
    const step = 1.4;
    for (var z = _b.min.y + 0.7; z < _b.max.y; z += step) {
      for (var x = _b.min.x + 0.7; x < _b.max.x; x += step) {
        final p = Vec2(x + rand.range(-0.5, 0.5), z + rand.range(-0.5, 0.5));
        if (!shape.carvedAt(p)) continue;
        // Clear of the table's skirt all round.
        var clear = true;
        for (final (dx, dz) in const [
          (1.0, 0.0),
          (-1.0, 0.0),
          (0.0, 1.0),
          (0.0, -1.0),
        ]) {
          if (shape.keptAt(p + Vec2(dx, dz))) clear = false;
        }
        if (!clear) continue;
        final roll = rand.next();
        if (roll < 0.25) {
          final r = rand.range(0.5, 0.9);
          props.add(
            tjg.IcosahedronGeometry(1, 1),
            _place(p.x, _ground + r * 0.7, p.y, sx: r, sy: r * 0.82, sz: r),
            rand.chance(0.5) ? _Farm.leafB : _Farm.leafA,
            baseShade: 0.6,
            rand: rand,
            variation: 0.1,
          );
        } else if (roll < 0.7) {
          const heads = [
            _Farm.flowerRed,
            _Farm.flowerYolk,
            _Farm.flowerCream,
            _Farm.flowerPink,
          ];
          final head = heads[rand.below(heads.length)];
          for (var f = 0; f < 5; f++) {
            final fx = p.x + rand.range(-0.5, 0.5);
            final fz = p.y + rand.range(-0.5, 0.5);
            final h = rand.range(0.28, 0.48);
            small.add(tjs.BoxGeometry(0.04, h, 0.04),
                _place(fx, _ground + h / 2, fz), _Farm.leafC);
            small.add(tjg.IcosahedronGeometry(rand.range(0.1, 0.15), 0),
                _place(fx, _ground + h, fz, sy: 0.6), head);
          }
        } else {
          for (var blade = 0; blade < 3; blade++) {
            final h = rand.range(0.35, 0.65);
            small.add(
              tjg.ConeGeometry(0.07, h, 3),
              _place(p.x + rand.range(-0.15, 0.15), _ground + h / 2,
                  p.y + rand.range(-0.15, 0.15),
                  tilt: rand.range(-0.3, 0.3)),
              _Farm.leafA,
              baseShade: 0.7,
            );
          }
        }
      }
    }
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
  void _barn(_Merged into, Vec2 at, {double scale = 1}) {
    final width = 13.0 * scale;
    final depth = 10.0 * scale;
    final wallHeight = 6.4 * scale;
    final roofHeight = 4.6 * scale;
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
    final doorWidth = 4.6 * scale;
    final doorHeight = 4.6 * scale;
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
    // He stands beyond the side rail by the nest, facing the green and a
    // little the camera, looking at the players.
    final turn = _hostTurn;
    final group = tjs.Group()
      ..name = 'host'
      ..position.setValues(at.x, _ground, at.y)
      ..rotation.y = turn;
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
    // The wings hang from the shoulders on their own pivots: they flap
    // when he cheers.
    final wings = <(tjs.Group, double)>[];
    for (final side in [-1.0, 1.0]) {
      final shoulder = tjs.Group()
        ..name = 'host-wing'
        ..position.setValues(0.4, 5.25, side * 1.55);
      final wing = _Merged()
        ..add(
            tjs.SphereGeometry(1, 18, 12),
            _place(-0.7, -0.75, side * 0.2,
                tilt: side * 0.2, sx: 1.9, sy: 1.2, sz: 0.45),
            shade);
      shoulder
          .add(wing.mesh('host-wing-feathers', flat: false, roughness: 0.75)!);
      group.add(shoulder);
      wings.add((shoulder, side));
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
    var headYaw = 0.0;
    animated.add(_AnimatedBy((time, dt) {
      // He follows the egg in play with his head (as far as a rooster's
      // neck turns).
      final watched = watch();
      var wantYaw = 0.0;
      if (watched != null) {
        final hx = at.x + 2.5 * math.cos(turn);
        final hz = at.y - 2.5 * math.sin(turn);
        final wx = watched.x - hx;
        final wz = watched.y - hz;
        final lx = wx * math.cos(turn) - wz * math.sin(turn);
        final lz = wx * math.sin(turn) + wz * math.cos(turn);
        wantYaw = math.atan2(-lz, lx).clamp(-0.85, 0.85).toDouble();
      }
      headYaw += (wantYaw - headYaw) * math.min(1.0, dt * 5);
      head.rotation.y = headYaw;
      final cheering = time < cheerUntil();
      if (cheering) {
        // An egg in the nest: he hops, flaps and crows, beak to the sky.
        final hop = math.sin(time * 9).abs();
        group.position.y = _ground + hop * 0.9;
        for (final (shoulder, side) in wings) {
          shoulder.rotation.x =
              side * (0.35 + 0.55 * math.sin(time * 18).abs());
        }
        head.rotation.z = 0.32 + math.sin(time * 6) * 0.06;
        head.position.y = 7.55;
        return;
      }
      group.position.y = _ground;
      for (final (shoulder, _) in wings) {
        shoulder.rotation.x = 0;
      }
      // A bar of nodding every few seconds, still in between.
      final phase = time % 6.0;
      final nod = phase < 2.4 ? math.sin(phase * math.pi * 2.5).abs() : 0.0;
      head.rotation.z = -nod * 0.16;
      head.position.y = 7.4 - nod * 0.12;
    }));
    return group;
  }

  // ---- the Coop: the hen house and its hens ----------------------------------------

  /// Farm Road's landmark: a water tower on four splayed legs, braced
  /// twice, its tank banded in red under a cone roof, a catwalk round it
  /// and a ladder up one leg.
  void _waterTower(_Merged into, Vec2 at) {
    final base = _ground;
    const legHeight = 14.0;
    const tankRadius = 3.6;
    const tankHeight = 5.0;
    for (final (sx, sz) in const [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0)
    ]) {
      into.add(
          tjg.CylinderGeometry(0.22, 0.3, legHeight + 0.6, 6),
          _place(at.x + sx * 2.5, base + legHeight / 2, at.y + sz * 2.5,
              tilt: -sz * 0.07, roll: sx * 0.07),
          0x8C8F94,
          baseShade: 0.7);
    }
    for (final y in const [4.8, 9.6]) {
      final half = 2.5 - y * 0.07 * 0.5;
      for (final (dx, dz, yaw) in [
        (0.0, half, 0.0),
        (0.0, -half, 0.0),
        (half, 0.0, math.pi / 2),
        (-half, 0.0, math.pi / 2),
      ]) {
        into.add(tjs.BoxGeometry(half * 2 + 0.3, 0.18, 0.18),
            _place(at.x + dx, base + y, at.y + dz, yaw: yaw), 0x7D8086);
      }
    }
    final tankBase = base + legHeight;
    into
      ..add(
          tjg.CylinderGeometry(tankRadius * 1.06, tankRadius * 1.06, 0.25, 28),
          _place(at.x, tankBase + 0.1, at.y),
          0x6E7176)
      ..add(tjg.CylinderGeometry(tankRadius, tankRadius, tankHeight, 28),
          _place(at.x, tankBase + tankHeight / 2 + 0.2, at.y), 0xDCE2E6,
          baseShade: 0.82)
      ..add(tjg.CylinderGeometry(tankRadius + 0.04, tankRadius + 0.04, 0.9, 28),
          _place(at.x, tankBase + tankHeight * 0.55 + 0.2, at.y), 0xC8453A)
      ..add(tjg.ConeGeometry(tankRadius + 0.35, 2.2, 28),
          _place(at.x, tankBase + tankHeight + 1.3, at.y), 0x9AA4AC)
      ..add(tjs.SphereGeometry(0.3, 10, 8),
          _place(at.x, tankBase + tankHeight + 2.5, at.y), 0x9AA4AC)
      ..add(tjg.TorusGeometry(tankRadius + 0.55, 0.07, 4, 32),
          _place(at.x, tankBase + 1.1, at.y, tilt: math.pi / 2), 0x7D8086);
    // The ladder up the camera-side leg.
    for (final side in const [-0.25, 0.25]) {
      into.add(
          tjs.BoxGeometry(0.06, legHeight, 0.06),
          _place(at.x + 2.5 + side, base + legHeight / 2, at.y + 2.75),
          0x6E7176);
    }
    for (var rung = 1.0; rung < legHeight; rung += 0.7) {
      into.add(tjs.BoxGeometry(0.5, 0.05, 0.05),
          _place(at.x + 2.5, base + rung, at.y + 2.75), 0x6E7176);
    }
  }

  /// The hen house: cream boards under a red roof, a little door with its
  /// ramp, the nesting boxes along one side.
  void _henHouse(_Merged into, Vec2 at) {
    final x = at.x;
    final z = at.y;
    final base = _ground;
    into.add(tjs.BoxGeometry(5.2, 3.2, 4.0), _place(x, base + 1.9, z), 0xF3E5CC,
        baseShade: 0.78);
    // Stilts lift it off the grass.
    for (final (sx, sz) in const [
      (-2.3, -1.7),
      (2.3, -1.7),
      (-2.3, 1.7),
      (2.3, 1.7)
    ]) {
      into.add(tjs.BoxGeometry(0.3, 0.6, 0.3),
          _place(x + sx, base + 0.3, z + sz), _Farm.trunk);
    }
    into.add(_prism(5.8, 2.0, 4.6), _place(x, base + 3.5, z), _Farm.barnRed);
    final slope = math.atan2(2.0, 2.9);
    final slab = math.sqrt(2.9 * 2.9 + 4.0) + 0.2;
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjs.BoxGeometry(slab, 0.22, 4.9),
          _place(x + side * 1.45, base + 4.55, z, roll: -side * slope),
          _Farm.barnRedDark);
    }
    // The door toward the green, its ramp down to the yard.
    final front = z + 2.02;
    into.add(tjs.BoxGeometry(1.2, 1.4, 0.08),
        _place(x - 0.8, base + 1.55, front), 0x3A2418);
    into.add(tjs.BoxGeometry(1.5, 1.7, 0.06),
        _place(x - 0.8, base + 1.6, front - 0.02), _Farm.trim);
    into.add(tjs.BoxGeometry(1.0, 0.1, 2.6),
        _place(x - 0.8, base + 0.55, front + 1.1, tilt: 0.38), _Farm.wood);
    for (var rung = 0; rung < 4; rung++) {
      into.add(
          tjs.BoxGeometry(1.0, 0.07, 0.07),
          _place(x - 0.8, base + 0.25 + rung * 0.22, front + 2.1 - rung * 0.55),
          _Farm.woodTop);
    }
    // A round window with a hen's view of the course.
    into.add(tjg.CylinderGeometry(0.42, 0.42, 0.1, 16),
        _place(x + 1.3, base + 2.4, front, tilt: math.pi / 2), 0x3A2418);
    into.add(tjg.TorusGeometry(0.45, 0.07, 6, 18),
        _place(x + 1.3, base + 2.4, front + 0.04), _Farm.trim);
    // Nesting boxes on the east wall.
    into.add(tjs.BoxGeometry(1.0, 1.0, 3.0), _place(x + 3.1, base + 1.5, z),
        _Farm.wood,
        baseShade: 0.8);
    into.add(tjs.BoxGeometry(1.2, 0.12, 3.2),
        _place(x + 3.2, base + 2.05, z, roll: -0.35), _Farm.barnRedDark);
  }

  /// A few hens out in the yard, pecking about the hen house.
  void _yardHens(_Merged into, Vec2 near) {
    for (var i = 0; i < 5; i++) {
      final at =
          Vec2(near.x + _rand.range(-7, 6), near.y + _rand.range(2.5, 7));
      if (_clearance(at.x, at.y) < 2.5) continue;
      _henFigure(into, at, _rand.range(0, math.pi * 2), _rand.range(0.45, 0.6));
    }
  }

  /// A small hen, merged: plump body, head, comb, beak, tail.
  void _henFigure(_Merged into, Vec2 at, double yaw, double r) {
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    tjs.Matrix4 local(double lx, double ly, double lz,
        {double sx = 1, double sy = 1, double sz = 1, double tilt = 0}) {
      return _place(at.x + lx * cosY + lz * sinY, _ground + ly,
          at.y - lx * sinY + lz * cosY,
          yaw: yaw, tilt: tilt, sx: sx, sy: sy, sz: sz);
    }

    const white = 0xFCF8F1;
    into.add(tjs.SphereGeometry(1, 12, 8),
        local(0, r * 1.0, 0, sx: r * 0.85, sy: r * 0.75, sz: r * 1.05), white,
        baseShade: 0.78);
    into.add(tjs.SphereGeometry(r * 0.42, 10, 8), local(0, r * 1.6, r * 0.75),
        white);
    into.add(
        tjs.SphereGeometry(r * 0.16, 8, 6),
        local(0, r * 2.02, r * 0.75, sx: 0.6, sy: 1.2),
        _hexOf(PuttPalette.comb));
    into.add(
        tjg.ConeGeometry(r * 0.12, r * 0.32, 6),
        local(0, r * 1.56, r * 1.18, tilt: math.pi / 2),
        _hexOf(PuttPalette.yolk));
    into.add(tjg.ConeGeometry(r * 0.32, r * 0.8, 6),
        local(0, r * 1.45, -r * 0.8, tilt: -0.7), 0xEEDFC8);
    for (final side in [-0.25, 0.25]) {
      into.add(tjg.CylinderGeometry(r * 0.05, r * 0.05, r * 0.5, 5),
          local(side * r, r * 0.25, 0), _hexOf(PuttPalette.yolk));
    }
  }

  // ---- the Corn Maze: the field and its scarecrow -------------------------------------

  /// The corn stands beyond the fence on three sides, leaving the camera's
  /// side open.
  bool _inCornField(double x, double z) {
    final clear = _clearance(x, z);
    if (clear < 7.5 || clear > 40) return false;
    return z < _b.max.y - 2;
  }

  void _cornField(_Merged into) {
    const spacing = 1.9;
    final rows = <double>[];
    for (var z = _b.min.y - 8; z > _b.min.y - 40; z -= spacing * 1.25) {
      rows.add(z);
    }
    var plants = 0;
    for (final z in rows) {
      for (var x = _b.min.x - 34; x < _b.max.x + 34; x += spacing) {
        final px = x + _rand.range(-0.35, 0.35);
        final pz = z + _rand.range(-0.3, 0.3);
        if (!_inCornField(px, pz)) continue;
        if (Vec2(px, pz).distanceTo(Vec2(_b.center.x - 14, _b.min.y - 9)) <
            3.2) {
          continue; // the scarecrow's clearing
        }
        if (Vec2(px, pz).distanceTo(_hostAt) < 6.5) {
          continue; // the host's spot
        }
        _cornPlant(into, Vec2(px, pz), _rand.range(0.85, 1.2));
        plants++;
        if (plants > 520) return;
      }
    }
    // The sides: a few rows running beside the course.
    for (final side in [-1.0, 1.0]) {
      final x0 = side < 0 ? _b.min.x - 9 : _b.max.x + 9;
      for (var row = 0; row < 4; row++) {
        final x = x0 + side * row * spacing * 1.25;
        for (var z = _b.min.y - 6; z < _b.max.y; z += spacing) {
          if (plants > 680) return;
          _cornPlant(
              into,
              Vec2(x + _rand.range(-0.3, 0.3), z + _rand.range(-0.3, 0.3)),
              _rand.range(0.85, 1.15));
          plants++;
        }
      }
    }
  }

  /// One corn plant on its strip of ploughed soil: a stalk, broad leaves
  /// arching out and drooping all the way up (each a quarter turn round
  /// from the last, the way corn grows), a cob in its husk, and the
  /// tassel's spikes on top. Each plant gets its own green.
  void _cornPlant(_Merged into, Vec2 at, double scale) {
    final height = 2.6 * scale;
    final base = _ground;
    final tone = _rand.range(0.86, 1.1);
    int green(int hex) => _shade(hex, tone);
    into.add(
        tjs.BoxGeometry(1.95, 0.05, 1.5),
        _place(at.x, base + 0.02, at.y, yaw: _rand.range(-0.05, 0.05)),
        _shade(0x6B5A34, _rand.range(0.9, 1.08)));
    into.add(tjg.CylinderGeometry(0.06, 0.1, height, 5),
        _place(at.x, base + height / 2, at.y), green(0x6E9F3A),
        baseShade: 0.62);
    final yaw0 = _rand.range(0, math.pi * 2);
    const leaves = 7;
    for (var leaf = 0; leaf < leaves; leaf++) {
      final yaw = yaw0 + leaf * 2.2 + _rand.range(-0.25, 0.25);
      final k = leaf / (leaves - 1);
      final h = base + height * (0.16 + k * 0.72);
      final length = (1.35 - k * 0.55) * scale;
      into.add(
        tjs.BoxGeometry(length, 0.03, 0.26 - k * 0.08),
        _place(at.x + math.cos(yaw) * length * 0.42, h,
            at.y - math.sin(yaw) * length * 0.42,
            yaw: yaw, roll: -0.35 - (1 - k) * 0.45),
        green(leaf.isEven ? 0x4F8F2E : 0x6FAE3E),
      );
    }
    if (_rand.chance(0.75)) {
      into.add(
          tjg.CylinderGeometry(0.11, 0.14, 0.55, 6),
          _place(at.x + 0.13, base + height * 0.52, at.y, roll: 0.35),
          0xA9C25A);
      into.add(
          tjg.ConeGeometry(0.1, 0.22, 6),
          _place(at.x + 0.24, base + height * 0.52 + 0.32, at.y, roll: 0.35),
          0xE9C866);
    }
    for (var spike = 0; spike < 3; spike++) {
      final lean = (spike - 1) * 0.35;
      into.add(
          tjg.ConeGeometry(0.05, 0.55, 4),
          _place(at.x + lean * 0.25, base + height + 0.22, at.y,
              roll: lean, yaw: yaw0),
          spike == 1 ? 0xE2C27A : 0xC9A45C);
    }
  }

  /// The scarecrow: a cross of poles, a plaid shirt, a straw hat, a sack
  /// head with a stitched smile.
  void _scarecrow(_Merged into, Vec2 at) {
    final base = _ground;
    into.add(tjg.CylinderGeometry(0.1, 0.12, 4.2, 6),
        _place(at.x, base + 2.1, at.y), _Farm.trunk);
    into.add(tjg.CylinderGeometry(0.08, 0.08, 3.0, 6),
        _place(at.x, base + 3.0, at.y, roll: math.pi / 2), _Farm.trunk);
    into.add(tjs.BoxGeometry(1.2, 1.4, 0.6), _place(at.x, base + 2.55, at.y),
        0x3E73B5,
        baseShade: 0.8);
    for (final side in [-1.0, 1.0]) {
      into.add(tjs.BoxGeometry(0.95, 0.4, 0.42),
          _place(at.x + side * 1.0, base + 3.0, at.y), 0xC4453A);
      into.add(
          tjg.ConeGeometry(0.16, 0.4, 5),
          _place(at.x + side * 1.62, base + 3.0, at.y,
              roll: side * math.pi / 2),
          _Farm.straw);
    }
    into.add(tjs.SphereGeometry(0.48, 12, 10), _place(at.x, base + 3.7, at.y),
        0xD9C08A);
    into.add(tjg.CylinderGeometry(0.95, 0.95, 0.08, 18),
        _place(at.x, base + 4.08, at.y), _Farm.straw);
    into.add(tjg.CylinderGeometry(0.46, 0.5, 0.5, 14),
        _place(at.x, base + 4.32, at.y), _Farm.strawDark);
    for (final side in [-0.17, 0.17]) {
      into.add(
          tjs.SphereGeometry(0.07, 6, 5),
          _place(at.x + side, base + 3.8, at.y + 0.44),
          _hexOf(PuttPalette.ink));
    }
  }

  // ---- the Pond: the lake, its reeds, the dock, the ducks -----------------------------

  tjs.Group _lake(Vec2 at, double radius) {
    final group = tjs.Group()
      ..name = 'lake'
      ..position.setValues(at.x, _ground, at.y);
    final shore = tjs.Mesh(
      tjg.RingGeometry(radius * 0.96, radius + 2.2, 64, 1),
      _matte(_Farm.shore, roughness: 1),
    )
      ..name = 'lake-shore'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03
      ..receiveShadow = true;
    final geometry = tjg.RingGeometry(0.001, radius, 64, 8);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final colors = Float32List(position.count * 3);
    final deep = _lin(_Farm.waterDeep);
    final shallow = _lin(_Farm.water);
    for (var i = 0; i < position.count; i++) {
      final d = math.sqrt(
          math.pow(position.getX(i)!, 2) + math.pow(position.getY(i)!, 2));
      final k = (1 - d / radius).clamp(0.0, 1.0);
      colors[i * 3] = shallow.red + (deep.red - shallow.red) * k;
      colors[i * 3 + 1] = shallow.green + (deep.green - shallow.green) * k;
      colors[i * 3 + 2] = shallow.blue + (deep.blue - shallow.blue) * k;
    }
    geometry.setAttributeFromString(
        'color', tjs.Float32BufferAttribute(colors, 3, false));
    final water = tjs.Mesh(
      geometry,
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.roughness: 0.08,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'lake-water'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.08
      ..receiveShadow = true;
    group
      ..add(shore)
      ..add(water);
    animated.add(_AnimatedBy((time, dt) {
      water.position.y = 0.08 + math.sin(time * 0.8) * 0.02;
    }));
    return group;
  }

  void _reeds(_Merged into, Vec2 at, double radius) {
    for (var cluster = 0; cluster < 22; cluster++) {
      final angle = _rand.range(0, math.pi * 2);
      final r = radius + _rand.range(-1.2, 1.4);
      final cx = at.x + math.cos(angle) * r;
      final cz = at.y + math.sin(angle) * r;
      if (_clearance(cx, cz) < 2) continue;
      for (var reed = 0; reed < 6; reed++) {
        final x = cx + _rand.range(-0.6, 0.6);
        final z = cz + _rand.range(-0.6, 0.6);
        final h = _rand.range(1.2, 2.3);
        into.add(
            tjg.CylinderGeometry(0.03, 0.05, h, 4),
            _place(x, _ground + h / 2, z, tilt: _rand.range(-0.12, 0.12)),
            0x4F8A33);
        if (_rand.chance(0.45)) {
          into.add(tjg.CylinderGeometry(0.09, 0.09, 0.42, 6),
              _place(x, _ground + h - 0.1, z), 0x6B4428);
        }
      }
    }
  }

  void _dock(_Merged into, Vec2 at, double radius) {
    // From the shore nearest the green out over the water.
    final start = Vec2(at.x + radius * 0.35, at.y + radius * 0.94);
    const length = 9.0;
    for (var plank = 0; plank < 14; plank++) {
      final z = start.y - plank * (length / 14);
      into.add(
          tjs.BoxGeometry(2.4, 0.12, 0.56),
          _place(start.x, _ground + 0.55, z),
          plank.isEven ? _Farm.wood : _Farm.woodTop);
    }
    for (var post = 0; post < 4; post++) {
      for (final side in [-1.1, 1.1]) {
        into.add(
            tjg.CylinderGeometry(0.12, 0.12, 1.4, 6),
            _place(start.x + side, _ground + 0.3, start.y - post * 3),
            _Farm.trunk);
      }
    }
  }

  void _ducks(tjs.Group group, Vec2 at, double radius) {
    final ducks = <tjs.Group>[];
    for (var i = 0; i < 4; i++) {
      final duck = tjs.Group()..name = 'duck';
      final body = _Merged()
        ..add(tjs.SphereGeometry(0.5, 12, 8),
            _place(0, 0.25, 0, sx: 1.4, sy: 0.8), i == 0 ? 0xFCF8F1 : 0x8A6A4A)
        ..add(tjs.SphereGeometry(0.28, 10, 8), _place(0.55, 0.75, 0),
            i == 0 ? 0xFCF8F1 : 0x2E6B3C)
        ..add(tjg.ConeGeometry(0.1, 0.32, 6),
            _place(0.85, 0.72, 0, roll: -math.pi / 2), _hexOf(PuttPalette.yolk))
        ..add(tjg.ConeGeometry(0.16, 0.42, 5), _place(-0.7, 0.45, 0, roll: 1.1),
            i == 0 ? 0xFCF8F1 : 0x6B5038);
      duck.add(body.mesh('duck-body', flat: false, roughness: 0.6)!);
      ducks.add(duck);
      group.add(duck);
    }
    final phases = [
      for (var i = 0; i < ducks.length; i++) _rand.range(0, 6.28)
    ];
    final rings = [
      for (var i = 0; i < ducks.length; i++) _rand.range(0.35, 0.75)
    ];
    animated.add(_AnimatedBy((time, dt) {
      for (var i = 0; i < ducks.length; i++) {
        final angle = phases[i] + time * 0.05 * (i.isEven ? 1 : -1);
        final r = radius * rings[i];
        final x = at.x + math.cos(angle) * r;
        final z = at.y + math.sin(angle) * r;
        ducks[i]
            .position
            .setValues(x, _ground + 0.08 + math.sin(time * 1.7 + i) * 0.04, z);
        // Facing along the circle.
        ducks[i].rotation.y = -angle - (i.isEven ? math.pi / 2 : -math.pi / 2);
      }
    }));
  }

  // ---- Farm Road: the road, the tractor, the poles, the fields ------------------------

  void _road(_Merged into, double z) {
    final from = _b.min.x - 160.0;
    final to = _b.max.x + 160.0;
    const step = 6.0;
    for (var x = from; x < to; x += step) {
      into.add(tjs.BoxGeometry(step + 0.1, 0.05, 6.4),
          _place(x + step / 2, _ground + 0.02, z), 0xC9A06A);
      // The tyre tracks.
      for (final track in [-1.4, 1.4]) {
        into.add(tjs.BoxGeometry(step + 0.1, 0.06, 0.7),
            _place(x + step / 2, _ground + 0.03, z + track), 0xB28A58);
      }
    }
  }

  /// A red tractor parked on the road: hood, cab, big rear wheels.
  void _tractor(_Merged into, Vec2 at) {
    final base = _ground;
    final red = _hexOf(PuttPalette.comb);
    const tyre = 0x2B2522;
    into.add(tjs.BoxGeometry(3.4, 1.2, 1.5),
        _place(at.x + 0.6, base + 1.5, at.y), red,
        baseShade: 0.8);
    into.add(tjs.BoxGeometry(1.6, 1.8, 1.7),
        _place(at.x - 1.2, base + 1.9, at.y), red);
    into.add(tjs.BoxGeometry(1.7, 0.12, 1.9),
        _place(at.x - 1.2, base + 3.55, at.y), _Farm.trim);
    for (final (cx, cz) in const [
      (-1.95, -0.85),
      (-0.45, -0.85),
      (-1.95, 0.85),
      (-0.45, 0.85)
    ]) {
      into.add(tjg.CylinderGeometry(0.06, 0.06, 1.7, 5),
          _place(at.x + cx * 0.85 - 0.2, base + 2.7, at.y + cz), 0x2E2A28);
    }
    into.add(tjs.BoxGeometry(1.3, 1.0, 1.75),
        _place(at.x - 1.2, base + 2.6, at.y), 0x9CC9E8);
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjg.CylinderGeometry(1.15, 1.15, 0.6, 18),
          _place(at.x - 1.3, base + 1.15, at.y + side * 1.15,
              tilt: math.pi / 2),
          tyre);
      into.add(
          tjg.CylinderGeometry(0.55, 0.55, 0.62, 12),
          _place(at.x - 1.3, base + 1.15, at.y + side * 1.15,
              tilt: math.pi / 2),
          _hexOf(PuttPalette.yolk));
      into.add(
          tjg.CylinderGeometry(0.62, 0.62, 0.45, 14),
          _place(at.x + 1.9, base + 0.62, at.y + side * 0.95,
              tilt: math.pi / 2),
          tyre);
      into.add(
          tjg.CylinderGeometry(0.28, 0.28, 0.47, 10),
          _place(at.x + 1.9, base + 0.62, at.y + side * 0.95,
              tilt: math.pi / 2),
          _hexOf(PuttPalette.yolk));
    }
    into.add(tjg.CylinderGeometry(0.1, 0.1, 1.2, 6),
        _place(at.x + 1.6, base + 2.6, at.y - 0.4), 0x3A3532);
    into.add(tjs.SphereGeometry(0.16, 8, 6),
        _place(at.x + 2.32, base + 1.7, at.y - 0.45), 0xFFF4C8);
    into.add(tjs.SphereGeometry(0.16, 8, 6),
        _place(at.x + 2.32, base + 1.7, at.y + 0.45), 0xFFF4C8);
  }

  /// Telephone poles along the road, wires slung between them.
  void _poles(tjs.Group group, _Merged into, double z) {
    final tops = <double>[];
    for (var x = _b.min.x - 90; x < _b.max.x + 90; x += 22) {
      into.add(tjg.CylinderGeometry(0.16, 0.2, 9, 7),
          _place(x, _ground + 4.5, z), 0x6B4A32,
          baseShade: 0.75);
      into.add(tjs.BoxGeometry(0.16, 0.18, 2.6), _place(x, _ground + 8.4, z),
          0x6B4A32);
      tops.add(x);
    }
    final points = <double>[];
    for (var i = 0; i + 1 < tops.length; i++) {
      for (final offset in [-1.1, 1.1]) {
        // A sagging wire in a few straight pieces.
        const pieces = 6;
        for (var p = 0; p < pieces; p++) {
          double xAt(int k) => tops[i] + (tops[i + 1] - tops[i]) * k / pieces;
          double yAt(int k) {
            final t = k / pieces;
            return _ground + 8.5 - 4 * t * (1 - t) * 1.1;
          }

          points.addAll(
              [xAt(p), yAt(p), z + offset, xAt(p + 1), yAt(p + 1), z + offset]);
        }
      }
    }
    final wires = tjs.LineSegments(
      tjs.BufferGeometry()
        ..setAttributeFromString(
            'position', tjs.Float32BufferAttribute.fromList(points, 3, false)),
      tjs.LineBasicMaterial({tjs.MaterialProperty.color: _lin(0x2A2420)}),
    )..name = 'road-wires';
    group.add(wires);
  }

  /// Fields beyond the road: golden wheat and fresh-ploughed rows.
  void _fields(tjs.Group group, double roadZ) {
    final rand = _Rand(_seedOf('${hole.id}/fields'));
    for (var f = 0; f < 6; f++) {
      final width = rand.range(40, 70);
      final depth = rand.range(30, 50);
      final x = _b.center.x + (f - 2.5) * 62 + rand.range(-8, 8);
      final z = roadZ - 8 - depth / 2 - (f.isEven ? 0 : rand.range(4, 20));
      final golden = f % 3 != 1;
      final texture = _fieldTexture(golden: golden);
      texture.repeat.setValues(width / 4, 1);
      final mesh = tjs.Mesh(
        tjs.PlaneGeometry(width, depth, 1, 1),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.map: texture,
          tjs.MaterialProperty.roughness: 1.0,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      )
        ..name = 'field'
        ..rotation.x = -math.pi / 2
        ..position.setValues(x, _ground + 0.06, z)
        ..receiveShadow = true;
      group.add(mesh);
    }
  }

  /// Crop rows: golden wheat or green shoots on brown earth, along u.
  tjs.DataTexture _fieldTexture({required bool golden}) {
    final bitmap = _Bitmap(32, 32);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        final inRow = (x % 16) < 11;
        final noise = (_hash2(x, y, golden ? 3 : 4) - 0.5) * 0.1;
        final hex = golden
            ? (inRow ? 0xE7C35A : 0xC99B45)
            : (inRow ? 0x7FB04A : 0x8A6240);
        bitmap.set(x, y, _shade(hex, 1 + noise));
      }
    }
    return bitmap.texture(repeat: true);
  }

  // ---- the Barn at dusk: haystacks, lanterns, fireflies -------------------------------

  void _haystacks(_Merged into, Vec2 barnAt) {
    for (final (dx, dz, s) in const [
      (-14.0, 4.0, 1.2),
      (-17.5, 1.0, 1.0),
      (16.0, 6.0, 1.1)
    ]) {
      final x = barnAt.x + dx;
      final z = barnAt.y + dz;
      // A stack: square bales in a stepped pyramid.
      for (var level = 0; level < 3; level++) {
        final count = 3 - level;
        for (var i = 0; i < count; i++) {
          into.add(
            tjs.BoxGeometry(1.6 * s, 0.9 * s, 1.0 * s),
            _place(x + (i - (count - 1) / 2) * 1.65 * s,
                _ground + 0.45 * s + level * 0.9 * s, z,
                yaw: _rand.range(-0.06, 0.06)),
            level.isEven ? _Farm.hay : _shade(_Farm.hay, 0.92),
            baseShade: 0.75,
          );
        }
      }
    }
  }

  /// Lanterns on posts at the course's corners: warm glass, a pool of
  /// light on the turf (a point light each, no shadows).
  void _lanterns(tjs.Group group, _Merged into) {
    const lip = _fenceThickness + 1.8;
    final spots = [
      Vec2(_b.min.x - lip, _b.min.y - lip),
      Vec2(_b.max.x + lip, _b.min.y - lip),
      Vec2(_b.min.x - lip, _b.max.y + lip),
      Vec2(_b.max.x + lip, _b.max.y + lip),
    ];
    final glow = <tjs.Mesh>[];
    for (final spot in spots) {
      into.add(tjg.CylinderGeometry(0.12, 0.16, 4.2, 6),
          _place(spot.x, _ground + 2.1, spot.y), 0x3A2E28);
      into.add(tjs.BoxGeometry(0.8, 0.12, 0.12),
          _place(spot.x, _ground + 4.0, spot.y), 0x3A2E28);
      final bulb = tjs.Mesh(
        tjs.BoxGeometry(0.42, 0.55, 0.42),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0xFFE2A0),
          tjs.MaterialProperty.emissive: _lin(0xFFB451),
          tjs.MaterialProperty.roughness: 0.4,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      )
        ..name = 'lantern-glass'
        ..position.setValues(spot.x, _ground + 3.55, spot.y);
      group.add(bulb);
      glow.add(bulb);
      final light = tjs.PointLight(0xFFFFFF, 3.2, 26, 1.4)
        ..name = 'lantern-light'
        ..position.setValues(spot.x, _ground + 3.4, spot.y);
      light.color = _lin(0xFFB766);
      group.add(light);
    }
    animated.add(_AnimatedBy((time, dt) {
      for (var i = 0; i < glow.length; i++) {
        final flicker = 0.88 +
            0.12 * math.sin(time * 7.3 + i * 1.7) * math.sin(time * 3.1 + i);
        final material = glow[i].material;
        if (material is tjs.MeshStandardMaterial) {
          material.emissiveIntensity = flicker * 2.6;
        }
      }
    }));
  }

  /// Fireflies drifting over the meadow at dusk.
  void _fireflies(tjs.Group group) {
    const count = 60;
    final rand = _Rand(_seedOf('${hole.id}/fireflies'));
    final homes = <(double, double, double, double)>[];
    for (var i = 0; i < count; i++) {
      final at = _spotAround(minClear: 1.5, maxClear: 26) ?? _b.center;
      homes.add((at.x, at.y, rand.range(0.6, 3.2), rand.range(0, 6.28)));
    }
    final positions = Float32List(count * 3);
    final geometry = tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute(positions, 3, false));
    final material = tjs.PointsMaterial({
      tjs.MaterialProperty.color: _lin(0xFFE48A),
      tjs.MaterialProperty.map: _EggView3D._shadowTexture,
      tjs.MaterialProperty.transparent: true,
      tjs.MaterialProperty.depthWrite: false,
      tjs.MaterialProperty.blending: tjs.AdditiveBlending,
    })
      ..size = 0.55
      ..sizeAttenuation = true;
    final points = tjs.Points(geometry, material)
      ..name = 'fireflies'
      ..frustumCulled = false;
    group.add(points);
    final attribute = geometry.attributes['position'] as tjs.BufferAttribute;
    animated.add(_AnimatedBy((time, dt) {
      for (var i = 0; i < count; i++) {
        final (x, z, h, phase) = homes[i];
        attribute.setXYZ(
          i,
          x + math.sin(time * 0.37 + phase) * 1.4,
          _ground + h + math.sin(time * 0.9 + phase * 2) * 0.5,
          z + math.cos(time * 0.31 + phase) * 1.4,
        );
      }
      attribute.needsUpdate = true;
      material.opacity = 0.6 + 0.4 * math.sin(time * 2.2).abs();
    }));
  }
}
