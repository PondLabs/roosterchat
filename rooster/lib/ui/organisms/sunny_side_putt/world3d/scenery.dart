// The farm around the course: the sky dome and its clouds (the world's
// own, kept across holes), and per hole the meadow rolling into hills,
// groves of oaks and pines, the course's own plants (see plants.dart), a
// scatter of wildflowers and tufts, stones, hay bales, a picket fence
// around the table, the red barn with its silo, a windmill turning on
// the hill, and the host himself - a big white rooster with his
// headphones on, bobbing his head by the green.
// Each course has props of its own besides: sunflowers and a feeding
// trough by the Coop, pumpkins and a corn crib in the maze, a rowboat and
// lily pads on the Pond, road signs and milk churns along Farm Road,
// strings of bulbs and a hay wagon in the Barn's yard.
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

    _Billboard glow(String name, double size, double opacity) => _Billboard(
          map: _EggView3D._shadowTexture,
          opacity: opacity,
          blending: tjs.AdditiveBlending,
          fog: false,
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
  late final _Billboard _sunDisc;
  late final _Billboard _sunHalo;

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

/// Where the host stands: beyond the side rail on the nest's side, about
/// level with the green's middle - in the play view the side of the
/// screen, clear of the HUD's top bar and its corner buttons.
Vec2 _hostSpotOf(HoleDef hole) {
  final b = hole.bounds;
  final nest = hole.nest.position;
  final right = nest.x >= b.center.x;
  // Out past the picket fence (3.6 off the table) on the grass: at 4.0
  // he stood on the fence line, over it and the rail from most cameras.
  return Vec2(
    right ? b.max.x + 6.6 : b.min.x - 6.6,
    nest.y
        .clamp(b.center.y - b.height * 0.2, b.center.y + b.height * 0.05)
        .toDouble(),
  );
}

/// Settles a prop [radius] across at the free spot nearest [want] and
/// keeps the scatter off it (see [_Scenery._settle]); null when nothing
/// near is free. [cornOk] lets it stand in the corn's ground.
typedef _Settle = Vec2? Function(Vec2 want, double radius, {bool cornOk});

/// Builds one hole's surroundings; the result is one group the world hangs
/// under the hole's 'scenery' kind.
class _Scenery {
  _Scenery(this.hole,
      {required this.animated,
      required this.theme,
      required this.cheerUntil,
      required this.shape,
      this.signAt,
      Vec2? Function()? watch,
      tjs.Vector3? Function()? greet})
      : watch = watch ?? (() => null),
        greet = greet ?? (() => null),
        _rand = _Rand(_seedOf('${hole.id}/farm')),
        _propRand = _Rand(_seedOf('${hole.id}/props')),
        _plantRand = _Rand(_seedOf('${hole.id}/plants'));

  /// The egg the host keeps his eye on (the one rolling, else the
  /// viewer's), or null.
  final Vec2? Function() watch;

  /// The camera the host turns to and looks at while it sweeps in over
  /// the hole (where it stands, in the world), or null.
  final tjs.Vector3? Function() greet;

  /// The table's shape: the meadow fills what the walls carved away.
  final _TableShape shape;

  /// Where the tee's sign stands (the course kit builds it), so nothing
  /// grows through its post; null when the hole has none.
  final Vec2? signAt;

  /// Until when (the frame clock) the host is cheering: an egg just
  /// dropped into the nest.
  final double Function() cheerUntil;

  final HoleDef hole;
  final List<_Animated> animated;
  final _Theme theme;
  final _Rand _rand;

  /// The course's own props draw from their own random, so they never
  /// shift the scatter's.
  final _Rand _propRand;

  /// The course's plants draw from theirs.
  final _Rand _plantRand;

  /// The course's plants as they grew round the table, and in the garden
  /// beds: kind, spot, footprint (the farm group's `userData['plants']`
  /// and `userData['bed plants']`).
  final List<(String, Vec2, double)> _grown = [];
  final List<(String, Vec2, double)> _bedGrown = [];

  /// Ground the corn leaves clear: the scarecrow's, the crib's.
  final List<(Vec2, double)> _clearings = [];

  /// The course's own props as they stood: name, spot, footprint. The farm
  /// group carries them in its `userData['props']` (the tests read them).
  final List<(String, Vec2, double)> _stood = [];

  Rect get _b => hole.bounds;
  double get _span => math.max(_b.width, _b.height);
  static const double _ground = -_tableHeight;

  /// Where the host stands: on the grass beyond the picket fence on the
  /// nest's side, about level with the green's middle - in the play view
  /// the side of the screen, clear of the HUD's top bar and its buttons.
  /// The picket fence's distance out from the table's edge.
  static const double _fenceGap = 3.6;

  /// The fence line as [_clearance] measures it: the fence stands the gap
  /// and a rail's thickness out, the clearance counts from the rail and
  /// half a unit.
  static const double _fenceClearance = _fenceGap - 0.5;

  Vec2 get _hostAt => _hostSpotOf(hole);

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

  /// A piece of a prop standing at [at] on the meadow, turned [yaw]:
  /// placed at ([lx], [ly], [lz]) in the prop's own frame (x along it, y
  /// up from the meadow, z across it), then turned, tilted, rolled and
  /// scaled there.
  tjs.Matrix4 _inFrame(Vec2 at, double yaw, double lx, double ly, double lz,
      {double turn = 0,
      double tilt = 0,
      double roll = 0,
      double sx = 1,
      double sy = 1,
      double sz = 1}) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return _place(at.x + lx * c + lz * s, _ground + ly, at.y - lx * s + lz * c,
        yaw: yaw + turn, tilt: tilt, roll: roll, sx: sx, sy: sy, sz: sz);
  }

  /// The farm, all at once (the tests' way; the world builds it through
  /// [buildSteps], a step a frame).
  tjs.Group build() {
    final group = tjs.Group()..name = 'farm';
    for (final step in buildSteps(group)) {
      step();
    }
    return group;
  }

  /// The names of [buildSteps]' steps, in order (the world's timing log).
  static const stepNames = [
    'meadow',
    'props',
    'carved meadow',
    'trees',
    'plants',
    'stones',
    'fence',
    'hay',
    'flowers',
    'barn',
    'landmarks',
    'corn rows',
    'corn field',
    'merge',
    'figures',
  ];

  /// The farm's build into [group] as steps ([stepNames]), run in order
  /// (the seeded scatter draws in that order).
  List<void Function()> buildSteps(tjs.Group group) {
    late final int stoneVertices;
    int? cornPlanted;
    // What stands beyond the sun's shadow box casts no shadow (see
    // `_aimSun`: the box reaches span * 0.62 + 12 round the green).
    final props =
        _Merged(shadowCenter: _b.center, shadowReach: _span * 0.62 + 16);
    final small = _Merged();
    // The plants and the stones, smooth-shaded; their far ones in a mesh
    // of their own that casts no shadow.
    final soft =
        _Merged(shadowCenter: _b.center, shadowReach: _span * 0.62 + 16);
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
      (hostAt, 4.5),
      if (kind == _ThemeKind.pond) (lakeAt, lakeRadius + 3),
      if (kind == _ThemeKind.coop) (henHouseAt, 6.5),
      if (signAt case final sign?) (sign, 1.6),
    ];
    bool blocked(double x, double z) {
      if (kind == _ThemeKind.road && (z - roadZ).abs() < 4.5) return true;
      if (kind == _ThemeKind.maze && _inCornField(x, z)) return true;
      for (final (spot, radius) in keepOut) {
        if (Vec2(x, z).distanceTo(spot) < radius) return true;
      }
      return false;
    }

    // Each course's own props, at set spots round the table nudged clear
    // of the landmarks and of one another; the scatter below keeps off
    // them.
    Vec2? settle(Vec2 want, double radius, {bool cornOk = false}) {
      final spot = _settle(want, radius, keepOut,
          road: kind == _ThemeKind.road ? roadZ : null,
          corn: kind == _ThemeKind.maze && !cornOk);
      if (spot != null) keepOut.add((spot, radius));
      return spot;
    }

    return [
      () {
        group.add(_meadow());
      },
      () {
        switch (kind) {
          case _ThemeKind.coop:
            _coopProps(props, settle);
          case _ThemeKind.maze:
            _mazeProps(props, settle);
          case _ThemeKind.pond:
            _pondProps(props, small, lakeAt, lakeRadius);
          case _ThemeKind.road:
            _roadProps(props, settle, roadZ);
          case _ThemeKind.barn:
            _barnProps(group, props, small, settle, barnAt, barnScale);
        }
      },
      () {
        _carvedMeadow(soft, small);
      },
      () {
        _trees(props, blocked);
      },
      () {
        _coursePlants(soft, small, blocked, roadZ: roadZ);
      },
      () {
        final beforeStones = soft.vertexCount;
        _stones(soft, blocked);
        stoneVertices = soft.vertexCount - beforeStones;
      },
      () => _fence(props),
      () => _hay(props, blocked),
      () => _flowers(small, blocked),
      () {
        if (hasBarn) _barn(props, barnAt, scale: barnScale);
      },
      () {
        switch (kind) {
          case _ThemeKind.coop:
            _henHouse(props, henHouseAt);
            _yardHens(props, henHouseAt);
            _path(small, from: Vec2(barnAt.x - 1, barnAt.y + 6), to: hostAt);
          case _ThemeKind.maze:
            // The corn, the maze's whole landmark, steps of its own.
            cornPlanted = _cornRows(props, 0, near: true);
          case _ThemeKind.pond:
            group.add(_lake(lakeAt, lakeRadius));
            _reeds(soft, lakeAt, lakeRadius);
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
      },
      () {
        final planted = cornPlanted;
        if (kind == _ThemeKind.maze && planted != null) {
          cornPlanted = _cornRows(props, planted, near: false);
        }
      },
      () {
        if (kind != _ThemeKind.maze) return;
        final planted = cornPlanted;
        if (planted != null) _cornSides(props, planted);
        _scarecrow(props, _scarecrowAt);
      },
      () {
        group.userData['plant vertices'] = soft.vertexCount - stoneVertices;
        final softMesh = soft.mesh('farm-soft', flat: false);
        if (softMesh != null) group.add(softMesh);
        final softFar = soft.farMesh('farm-soft-far', flat: false);
        if (softFar != null) group.add(softFar);
        final propsMesh = props.mesh('farm-props');
        if (propsMesh != null) group.add(propsMesh);
        final farMesh = props.farMesh('farm-props-far');
        if (farMesh != null) group.add(farMesh);
        final smallMesh = small.mesh('farm-small', castShadow: false);
        if (smallMesh != null) group.add(smallMesh);
      },
      () {
        if (hasMill) group.add(_windmill(millAt));
        group.add(_host(hostAt));
        if (kind != _ThemeKind.barn) group.add(_butterflies());
        group.add(_birds());
        group.userData['props'] =
            List<(String, Vec2, double)>.unmodifiable(_stood);
        group.userData['plants'] =
            List<(String, Vec2, double)>.unmodifiable(_grown);
        group.userData['bed plants'] =
            List<(String, Vec2, double)>.unmodifiable(_bedGrown);
      },
    ];
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
  /// The meadow's sheet: [_meadowSegments] squares a side, centred on the
  /// green.
  static const double _meadowSize = 1300.0;
  static const int _meadowSegments = 120;

  /// The meadow's heights over the table's foot ([_ground]) at its grid's
  /// vertices, row by row along z (the order of its sheet's vertices).
  late final Float64List _meadowHeights = () {
    const n = _meadowSegments + 1;
    const cell = _meadowSize / _meadowSegments;
    final heights = Float64List(n * n);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        heights[row * n + col] = _meadowRelief(
            col * cell - _meadowSize / 2, row * cell - _meadowSize / 2);
      }
    }
    return heights;
  }();

  /// The meadow's height over [_ground] at ([lx], [lz]) from the green's
  /// centre: hills past the flat ring, a gentle roll nearer in. On Farm
  /// Road the road's strip stays level (a valley through the hills): the
  /// road, its poles and the tractor lie flat on it.
  double _meadowRelief(double lx, double lz) {
    final seed = _seedOf('${hole.id}/meadow');
    final x = lx + _b.center.x;
    final z = lz + _b.center.y;
    final d = math.sqrt(lx * lx + lz * lz);
    final angle = math.atan2(lz, lx);
    final flatReach = _span * 0.7 + 34;
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
    if (theme.kind != _ThemeKind.road) return y;
    // Level a cell of the meadow's grid either side of the road, so the
    // sheet's triangles over it are flat too.
    final off = (z - _roadZ).abs();
    final t = ((off - 12) / 18).clamp(0.0, 1.0);
    return y * t * t * (3 - 2 * t);
  }

  /// Farm Road's road: its middle line across the far side.
  double get _roadZ => _b.min.y - 13.0;

  /// The meadow's surface at ([x], [z]) in the world: its sheet's own
  /// triangles, interpolated as the GPU draws them, so what is laid on it
  /// ([_fields]) follows it exactly.
  double _meadowY(double x, double z) {
    const n = _meadowSegments + 1;
    const cell = _meadowSize / _meadowSegments;
    final gx = ((x - _b.center.x + _meadowSize / 2) / cell)
        .clamp(0.0, _meadowSegments - 1e-9);
    final gz = ((z - _b.center.y + _meadowSize / 2) / cell)
        .clamp(0.0, _meadowSegments - 1e-9);
    final col = gx.floor();
    final row = gz.floor();
    final u = gx - col;
    final v = gz - row;
    final h = _meadowHeights;
    final h00 = h[row * n + col];
    final h10 = h[row * n + col + 1];
    final h01 = h[(row + 1) * n + col];
    final h11 = h[(row + 1) * n + col + 1];
    // A PlaneGeometry cell splits along its (col, row + 1)-(col + 1, row)
    // diagonal.
    final y = u + v <= 1
        ? h00 + u * (h10 - h00) + v * (h01 - h00)
        : h11 + (1 - u) * (h01 - h11) + (1 - v) * (h10 - h11);
    return _ground + y;
  }

  tjs.Mesh _meadow() {
    final geometry = tjs.PlaneGeometry(
        _meadowSize, _meadowSize, _meadowSegments, _meadowSegments)
      ..rotateX(-math.pi / 2);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final colors = Float32List(position.count * 3);
    final seed = _seedOf('${hole.id}/meadow');
    final center = _b.center;
    final flatReach = _span * 0.7 + 34;
    const n = _meadowSegments + 1;
    const cell = _meadowSize / _meadowSegments;
    for (var i = 0; i < position.count; i++) {
      final lx = position.getX(i)!.toDouble();
      final lz = position.getZ(i)!.toDouble();
      final x = lx + center.x;
      final z = lz + center.y;
      final d = math.sqrt(lx * lx + lz * lz);
      final rise = ((d - flatReach) / 150).clamp(0.0, 1.0);
      final col = ((lx + _meadowSize / 2) / cell).round().clamp(0, n - 1);
      final row = ((lz + _meadowSize / 2) / cell).round().clamp(0, n - 1);
      final y = _meadowHeights[row * n + col];
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
  /// level: the course's plants, flowers and tufts grow there, clear of
  /// the skirt; in the maze, rows of cabbages.
  void _carvedMeadow(_Merged plants, _Merged small) {
    if (!shape.carved) return;
    final rand = _Rand(_seedOf('${hole.id}/carved'));
    const step = 1.4;
    var row = 0;
    for (var z = _b.min.y + 0.7; z < _b.max.y; z += step, row++) {
      for (var x = _b.min.x + 0.7; x < _b.max.x; x += step) {
        var p = Vec2(x + rand.range(-0.5, 0.5), z + rand.range(-0.5, 0.5));
        // The maze's beds are planted in rows, one row in two.
        final maze = theme.kind == _ThemeKind.maze;
        if (maze && row.isEven) p = Vec2(x + (p.x - x) * 0.25, z);
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
        if (signAt case final sign? when p.distanceTo(sign) < 1.6) continue;
        final roll = rand.next();
        if (maze ? row.isEven && roll < 0.5 : roll < _bedChance) {
          _bedPlant(plants, p, rand);
        } else if (roll >= 0.25 && roll < 0.7) {
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

  // ---- trees ------------------------------------------------------------------------

  void _trees(_Merged into, bool Function(double, double) blocked) {
    // Groves: a few clusters, and singles scattered between them.
    final spots = <Vec2>[];
    final groves = 6;
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
  /// Drawn from [rand], the scatter's own when null.
  Vec2? _spotAround(
      {required double minClear,
      required double maxClear,
      bool tall = false,
      _Rand? rand}) {
    final from = rand ?? _rand;
    for (var attempt = 0; attempt < 40; attempt++) {
      final x = from.range(_b.min.x - maxClear, _b.max.x + maxClear);
      final z = from.range(_b.min.y - maxClear, _b.max.y + maxClear);
      final clear = _clearance(x, z);
      if (clear < minClear || clear > maxClear) continue;
      if (tall && _cameraSide(z)) continue;
      return Vec2(x, z);
    }
    return null;
  }

  /// The free spot nearest [want] for a prop [radius] across: off the
  /// table and clear of the picket fence, never reaching the camera's side,
  /// clear of everything in [taken] (the landmarks, the host, the props
  /// placed before it), off the road along [road] and out of the corn
  /// when [corn]. Null when nothing near is free.
  Vec2? _settle(Vec2 want, double radius, List<(Vec2, double)> taken,
      {double? road, bool corn = false}) {
    for (var ring = 0; ring < 12; ring++) {
      final steps = ring == 0 ? 1 : 8 * ring;
      for (var k = 0; k < steps; k++) {
        final angle = k / steps * math.pi * 2;
        final p = want + Vec2(math.cos(angle), math.sin(angle)) * (ring * 0.9);
        final clear = _clearance(p.x, p.y);
        if (clear < radius + 0.5) continue;
        if ((clear - _fenceClearance).abs() < radius + 0.3) continue;
        if (p.y + radius > _b.max.y) continue;
        if (road != null && (p.y - road).abs() < 3.4 + radius) continue;
        if (corn && clear + radius > 7.5 && p.y - radius < _b.max.y - 2) {
          continue;
        }
        if (taken.any((t) => p.distanceTo(t.$1) < t.$2 + radius)) continue;
        return p;
      }
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

  void _stones(_Merged into, bool Function(double, double) blocked) {
    for (var i = 0; i < 18; i++) {
      final at = _spotAround(minClear: 2, maxClear: 40);
      if (at == null || blocked(at.x, at.y)) continue;
      final r = _rand.range(0.3, 0.9);
      into.add(
        _lumpyStone(_rand, detail: 1, lumps: 0.16),
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
    const gap = _fenceGap;
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
    // Trim: a board up each corner, standing proud of both walls it
    // meets. (A board as deep as the barn, a hair outside its side wall,
    // fought the red for every pixel of that wall: it flickered.)
    final front = z + depth / 2 + 0.06;
    const board = 0.42;
    const proud = 0.06;
    for (final sx in [-1.0, 1.0]) {
      for (final sz in [-1.0, 1.0]) {
        into.add(
            tjs.BoxGeometry(board, wallHeight, board),
            _place(
                x + sx * (width / 2 + proud - board / 2),
                base + wallHeight / 2,
                z + sz * (depth / 2 + proud - board / 2)),
            _Farm.trim);
      }
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
      // A little short of the leaves' top: level with it, the two tops
      // flickered through each other.
      into.add(tjs.BoxGeometry(0.22, doorHeight - 0.06, 0.1),
          _place(x, base + (doorHeight - 0.06) / 2, front + 0.1), _Farm.trim);
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

  /// The host's size against the build below (a rooster a few eggs tall
  /// beside the rail, not a giant over the green).
  static const double _hostScale = 0.65;

  /// The host: a big white rooster beside the green, comb like a crown,
  /// headphones on (he is always in the call). He stands on two scaly
  /// legs, his wings folded with their feathers cut along the edge and his
  /// sickles arched over his tail (`world3d/birds.dart` builds him). He
  /// breathes, looks about with quick turns and tilts of his head, follows
  /// the egg in play, bobs to the beat now and then, cheers every egg that
  /// drops in, and turns to the camera while it sweeps in over a new hole.
  tjs.Group _host(Vec2 at) {
    // He stands beyond the side rail by the nest, facing the green and a
    // little the camera, looking at the players.
    final turn = _hostTurn;
    final group = tjs.Group()
      ..name = 'host'
      ..position.setValues(at.x, _ground, at.y)
      ..rotation.y = turn
      ..scale.setValues(_hostScale, _hostScale, _hostScale);
    // All of him swells with his breath, from the ground up (the root's
    // own scale is the fade's to shrink).
    final breath = tjs.Group()..name = 'host-breath';
    group.add(breath);
    const white = _Bird.white;
    final comb = _hexOf(PuttPalette.comb);
    final yolk = _hexOf(PuttPalette.yolk);
    final ink = _hexOf(PuttPalette.ink);
    // Each part twice: in full for the close-ups, and light (fewer facets,
    // the same shapes) for while he stands small on the screen - the world
    // shows one or the other ([_HostDetail]); the light one waits hidden.
    tjs.Mesh built(String name, void Function(_Merged into) parts,
        {required bool light, required double ink}) {
      final merged = _Merged();
      parts(merged);
      final mesh = merged.mesh(light ? '$name-light' : name,
          flat: false, roughness: 0.75)!
        ..visible = !light;
      _inkOutline(mesh, ink);
      return mesh;
    }

    for (final light in [false, true]) {
      breath.add(built('host-body', (into) => _roosterBody(into, light: light),
          light: light, ink: 0.09));
    }
    // The wings hang from the shoulders on their own pivots: they flap
    // when he cheers.
    final wings = <(tjs.Group, double)>[];
    for (final side in [-1.0, 1.0]) {
      final shoulder = tjs.Group()
        ..name = 'host-wing'
        ..position.setValues(0.45, 5.3, side * 1.6);
      for (final light in [false, true]) {
        shoulder.add(built('host-wing-feathers',
            (into) => _roosterWing(into, side, light: light),
            light: light, ink: 0.07));
      }
      breath.add(shoulder);
      wings.add((shoulder, side));
    }

    // The head, which turns, tilts and nods: comb, beak, wattle, eyes and
    // the headphones.
    final head = tjs.Group()
      ..name = 'host-head'
      ..position.setValues(2.5, 7.4, 0);
    // Turned first, then nodded, then tilted about his own beak.
    head.rotation.order = tjs.RotationOrders.yzx;
    void faceParts(_Merged face, {required bool light}) {
      // Facets per part, in full and light.
      int n(int full, int few) => light ? few : full;
      face.add(tjs.SphereGeometry(1.25, n(22, 14), n(16, 10)),
          _place(0, 0, 0, sx: 1.08), white);
      final lobes = [
        (0.55, 1.25, 0.55),
        (-0.05, 1.45, 0.6),
        (-0.7, 1.35, 0.52),
        (-1.2, 1.0, 0.42),
      ];
      for (final (lx, ly, lr) in lobes) {
        face.add(tjs.SphereGeometry(lr, n(14, 8), n(10, 6)),
            _place(lx, ly, 0, sz: 0.62), comb);
      }
      face.add(tjg.ConeGeometry(0.42, 1.05, n(12, 8)),
          _place(1.45, -0.12, 0, roll: -math.pi / 2), yolk);
      face.add(tjs.SphereGeometry(0.42, n(12, 8), n(10, 6)),
          _place(1.0, -0.95, 0, sx: 0.8, sy: 1.25, sz: 0.6), comb);
      for (final side in [-1.0, 1.0]) {
        face.add(tjs.SphereGeometry(0.2, n(10, 6), n(8, 5)),
            _place(0.55, 0.28, side * 1.02), ink);
        face.add(tjs.SphereGeometry(0.07, n(8, 5), n(6, 4)),
            _place(0.62, 0.36, side * 1.17), white);
      }
      // Headphones: the band over the crown, a cup on each cheek.
      face.add(tjg.TorusGeometry(1.42, 0.15, n(8, 5), n(28, 16), math.pi),
          _place(-0.2, 0.05, 0, yaw: math.pi / 2), ink);
      for (final side in [-1.0, 1.0]) {
        face.add(tjg.CylinderGeometry(0.62, 0.62, 0.42, n(20, 12)),
            _place(-0.2, 0.02, side * 1.32, tilt: math.pi / 2), ink);
        face.add(tjg.TorusGeometry(0.42, 0.08, n(6, 4), n(20, 12)),
            _place(-0.2, 0.02, side * 1.55), comb);
      }
    }

    for (final light in [false, true]) {
      final face = _Merged();
      faceParts(face, light: light);
      final hostFace = face.mesh(light ? 'host-face-light' : 'host-face',
          flat: false, roughness: 0.7)!
        ..visible = !light;
      _inkOutline(hostFace, 0.07);
      head.add(hostFace);
    }
    breath.add(head);

    // Where his head turns (toward what he watches), how far his body
    // comes round with it (only for the camera), and the glance he holds
    // between a bird's quick turns and tilts.
    var headYaw = 0.0;
    var headPitch = 0.0;
    var bodyYaw = 0.0;
    var glances = 0;
    var nextGlance = 1.2;
    var glanceYaw = 0.0;
    var glanceTilt = 0.0;
    var glanceNow = 0.0;
    var tiltNow = 0.0;
    final headHeight = _ground + 7.4 * _hostScale;
    animated.add(_AnimatedBy((time, dt) {
      // He breathes: his body swells about two per cent, and back.
      final swell = 0.01 + 0.01 * math.sin(time * math.pi * 2 / 3.4);
      breath.scale.setValues(1 + swell, 1 + swell * 0.5, 1 + swell);
      // What he looks at: the camera while it sweeps in over the hole,
      // else the egg in play, as far as a rooster's neck turns - for the
      // camera his body comes round too.
      final camera = greet();
      final target = camera != null ? Vec2(camera.x, camera.z) : watch();
      var want = 0.0;
      var wantPitch = 0.0;
      if (target != null) {
        final hx = at.x + 2.5 * _hostScale * math.cos(turn);
        final hz = at.y - 2.5 * _hostScale * math.sin(turn);
        final wx = target.x - hx;
        final wz = target.y - hz;
        final lx = wx * math.cos(turn) - wz * math.sin(turn);
        final lz = wx * math.sin(turn) + wz * math.cos(turn);
        want = math.atan2(-lz, lx);
        // Up to the camera, down to the green.
        final rise = (camera?.y ?? 0.0) - headHeight;
        wantPitch = (math.atan2(rise, math.sqrt(wx * wx + wz * wz)) * 0.6)
            .clamp(-0.3, 0.35)
            .toDouble();
      }
      final bodyWant = camera == null
          ? 0.0
          : (want - want.clamp(-0.7, 0.7)).clamp(-0.9, 0.9).toDouble();
      bodyYaw += (bodyWant - bodyYaw) * math.min(1.0, dt * 3);
      group.rotation.y = turn + bodyYaw;
      final headWant = (want - bodyYaw).clamp(-0.85, 0.85).toDouble();
      headYaw += (headWant - headYaw) * math.min(1.0, dt * 5);
      headPitch += (wantPitch - headPitch) * math.min(1.0, dt * 4);
      // Now and then a glance: his head snaps to a small new turn and tilt
      // and holds it, the way a bird looks about (less of a turn while he
      // looks at the camera).
      if (time >= nextGlance) {
        glances++;
        nextGlance = time + 0.8 + _hash2(glances, 1, 71) * 2.2;
        glanceYaw = (_hash2(glances, 2, 71) * 2 - 1) * 0.3;
        glanceTilt = (_hash2(glances, 3, 71) * 2 - 1) * 0.26;
      }
      final cheering = time < cheerUntil();
      final snap = math.min(1.0, dt * 12);
      final glanceWant =
          cheering ? 0.0 : glanceYaw * (camera == null ? 1 : 0.3);
      glanceNow += (glanceWant - glanceNow) * snap;
      tiltNow += ((cheering ? 0.0 : glanceTilt) - tiltNow) * snap;
      head.rotation.y = (headYaw + glanceNow).clamp(-1.0, 1.0).toDouble();
      head.rotation.x = tiltNow;
      if (cheering) {
        // An egg in the nest: he hops, flaps his wings out and crows, beak
        // to the sky.
        final hop = math.sin(time * 9).abs();
        group.position.y = _ground + hop * 0.9 * _hostScale;
        for (final (shoulder, side) in wings) {
          shoulder.rotation.x =
              -side * (0.35 + 0.55 * math.sin(time * 18).abs());
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
      head.rotation.z = headPitch - nod * 0.16;
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

  /// A small hen, merged: the walking hens' own body, head and legs at
  /// her size, in fewer facets. Some peck at the grass, the others look
  /// about (each one's pose read off where she stands, so the farm's
  /// random draws stay as they were).
  void _henFigure(_Merged into, Vec2 at, double yaw, double r) {
    final frame = _place(at.x, _ground, at.y, yaw: yaw);
    _henBody(into, frame, r, small: true);
    final pose = _hash2((at.x * 13).floor(), (at.y * 13).floor(), 29);
    final head = pose < 0.45
        ? _place(0, r * (_henHeadY - 0.4), r * (_henHeadZ + 0.25), tilt: 0.85)
        : _place(0, r * _henHeadY, r * _henHeadZ, yaw: (pose - 0.72) * 1.6);
    _henHead(into, _within(frame, head), r, small: true);
    for (final side in [-1.0, 1.0]) {
      _henLeg(into, _within(frame, _place(side * r * 0.32, r * _henHip, 0)), r,
          side,
          small: true);
    }
  }

  /// The Coop's own corner: a patch of sunflowers beyond the far fence on
  /// the tee's half, their heads turned to the morning sun, and out west a
  /// feeding trough with the feed sacks stacked by it and hens at their
  /// breakfast.
  void _coopProps(_Merged into, _Settle settle) {
    final rand = _propRand;
    // To the sun, and enough to the camera's side that the faces read.
    final (sunX, _, sunZ) = theme.sunFrom;
    final facing =
        (Vec2(sunX, sunZ).normalized(const Vec2(0, 1)) + const Vec2(0, 0.9))
            .normalized(const Vec2(0, 1));
    const count = 17;
    for (var i = 0; i < count; i++) {
      final want = Vec2(
        _b.min.x + _b.width * (0.02 + 0.4 * i / (count - 1)),
        _b.min.y - 6.4 - (i % 3) * 1.25,
      );
      final at = settle(
          want + Vec2(rand.range(-0.3, 0.3), rand.range(-0.3, 0.3)), 0.6);
      if (at != null) _sunflower(into, at, rand.range(2.9, 4.0), facing, rand);
    }
    final troughAt =
        settle(Vec2(_b.min.x - 7.6, _b.min.y + _b.height * 0.32), 1.7);
    if (troughAt == null) return;
    // Along the table's side, so its length shows.
    const yaw = math.pi / 2 + 0.12;
    _trough(into, troughAt, yaw);
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    for (final (lx, side) in const [(-0.7, 1.0), (0.55, -1.0), (0.9, 1.0)]) {
      // A hen at each side, facing the feed.
      final lz = side * 0.95;
      final at = troughAt + Vec2(lx * c + lz * s, -lx * s + lz * c);
      _henFigure(into, at, yaw + (side > 0 ? math.pi : 0), 0.5);
    }
    final sacksAt = settle(troughAt + const Vec2(0.4, -2.9), 1.0);
    if (sacksAt != null) _feedSacks(into, sacksAt, rand.range(-0.5, 0.5));
  }

  /// A sunflower: a tall stem with broad leaves, and the big head - a
  /// brown disc in two rings of yellow petals, green behind - nodding
  /// toward [facing] (on the ground) and lifted to the sky.
  void _sunflower(
      _Merged into, Vec2 at, double height, Vec2 facing, _Rand rand) {
    _stood.add(('sunflower', at, 0.6));
    const stem = 0x4E8A2E;
    final f = facing.rotated(rand.range(-0.25, 0.25));
    final turn = math.atan2(f.x, f.y);
    final lift = rand.range(0.3, 0.5);
    into.add(tjg.CylinderGeometry(0.06, 0.09, height, 6),
        _place(at.x, _ground + height / 2, at.y), stem,
        baseShade: 0.7);
    for (var leaf = 0; leaf < 3; leaf++) {
      final a = rand.range(0, math.pi * 2);
      into.add(
        tjg.IcosahedronGeometry(1, 0),
        _place(at.x + math.cos(a) * 0.36,
            _ground + height * (0.28 + leaf * 0.18), at.y - math.sin(a) * 0.36,
            yaw: a, roll: -0.4, sx: 0.45, sy: 0.05, sz: 0.26),
        leaf.isEven ? _Farm.leafC : _Farm.leafA,
      );
    }
    // The neck bends over toward the sun; the head hangs off its end.
    into.add(
        tjg.CylinderGeometry(0.05, 0.06, 0.4, 5),
        _place(at.x + f.x * 0.12, _ground + height - 0.02, at.y + f.y * 0.12,
            yaw: turn, tilt: 0.85),
        stem);
    final head = at + f * 0.28;
    final headY = _ground + height + 0.1;
    // A piece in the head's own frame: its face looks down +z.
    tjs.Matrix4 onHead(double px, double py, double pz,
        {double tilt = 0, double roll = 0, double sy = 1, double sz = 1}) {
      final y1 = py * math.cos(lift) + pz * math.sin(lift);
      final z1 = -py * math.sin(lift) + pz * math.cos(lift);
      return _place(
        head.x + px * math.cos(turn) + z1 * math.sin(turn),
        headY + y1,
        head.y - px * math.sin(turn) + z1 * math.cos(turn),
        yaw: turn,
        tilt: tilt - lift,
        roll: roll,
        sy: sy,
        sz: sz,
      );
    }

    const disc = 0.36;
    into.add(tjg.ConeGeometry(disc + 0.16, 0.3, 10),
        onHead(0, 0, -0.13, tilt: -math.pi / 2), 0x5A8F32);
    for (var ring = 0; ring < 2; ring++) {
      const petals = 13;
      for (var i = 0; i < petals; i++) {
        final phi = (i + ring * 0.5) / petals * math.pi * 2;
        final reach = disc + 0.24 - ring * 0.04;
        into.add(
          tjg.ConeGeometry(0.12, 0.52, 4),
          onHead(
              math.cos(phi) * reach, math.sin(phi) * reach, -0.02 - ring * 0.03,
              roll: phi - math.pi / 2, sz: 0.28),
          ring == 0 ? 0xFFC928 : 0xF5A51C,
        );
      }
    }
    into.add(tjg.CylinderGeometry(disc, disc, 0.1, 14),
        onHead(0, 0, 0.01, tilt: math.pi / 2), 0x4A2C16);
    into.add(
        tjs.SphereGeometry(disc * 0.9, 12, 4, 0, math.pi * 2, 0, math.pi / 2),
        onHead(0, 0, 0.05, tilt: math.pi / 2, sy: 0.35),
        0x6B3E1E);
  }

  /// A feeding trough: a long V of boards on trestles, full of golden
  /// feed.
  void _trough(_Merged into, Vec2 at, double yaw) {
    _stood.add(('trough', at, 1.5));
    const length = 2.8;
    for (final end in [-1.0, 1.0]) {
      for (final lean in [-0.5, 0.5]) {
        into.add(
            tjs.BoxGeometry(0.1, 0.78, 0.1),
            _inFrame(at, yaw, end * (length / 2 - 0.25), 0.36, 0, tilt: lean),
            _Farm.trunk,
            baseShade: 0.7);
      }
    }
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjs.BoxGeometry(length, 0.07, 0.46),
          _inFrame(at, yaw, 0, 0.74, side * 0.19, tilt: -side * 0.62),
          _Farm.wood,
          baseShade: 0.85);
    }
    for (final end in [-1.0, 1.0]) {
      into.add(tjs.BoxGeometry(0.07, 0.36, 0.72),
          _inFrame(at, yaw, end * length / 2, 0.76, 0), _Farm.woodTop);
    }
    into.add(tjs.BoxGeometry(length - 0.12, 0.08, 0.5),
        _inFrame(at, yaw, 0, 0.82, 0), 0xE9C46A);
    // Feed spilt round its feet.
    for (var i = 0; i < 9; i++) {
      into.add(
          tjs.BoxGeometry(0.07, 0.03, 0.07),
          _inFrame(at, yaw, _propRand.range(-1.4, 1.4), 0.015,
              _propRand.range(-0.8, 0.8),
              turn: _propRand.range(0, 3)),
          0xE9C46A);
    }
  }

  /// Feed sacks in a little stack: burlap tied at the neck, a coloured
  /// band round each; two standing and one lying across their feet.
  void _feedSacks(_Merged into, Vec2 at, double yaw) {
    _stood.add(('feed sacks', at, 1.0));
    const burlap = 0xC9A46A;
    const twine = 0x8A6A40;
    // A sack's pieces at [u] along its own axis (up it when standing; a
    // lying sack lies along the stack's x, its neck to -x), squashed by
    // [squash] along it and turned end over end by [flip].
    void sack(double lx, double lz, double turn, int band,
        {bool lying = false}) {
      tjs.Matrix4 piece(double u, {double squash = 1, double flip = 0}) {
        if (!lying) {
          return _inFrame(at, yaw, lx, u, lz,
              turn: turn, tilt: flip, sy: squash, sz: 0.64);
        }
        final c = math.cos(turn);
        final s = math.sin(turn);
        return _inFrame(at, yaw, lx - u * c, 0.27, lz + u * s,
            turn: turn, roll: math.pi / 2 + flip, sx: 0.66, sy: squash);
      }

      final base = lying ? -0.36 : 0.0;
      into.add(
          tjg.CylinderGeometry(0.36, 0.4, 0.72, 10), piece(base + 0.36), burlap,
          baseShade: lying ? 0.85 : 0.7);
      into.add(
          tjg.CylinderGeometry(0.39, 0.41, 0.14, 10), piece(base + 0.4), band);
      into.add(tjs.SphereGeometry(0.36, 10, 5, 0, math.pi * 2, 0, math.pi / 2),
          piece(base + 0.72, squash: 0.6), burlap);
      into.add(
          tjg.CylinderGeometry(0.07, 0.1, 0.14, 7), piece(base + 0.98), twine);
      into.add(tjg.ConeGeometry(0.15, 0.2, 7), piece(base + 1.1, flip: math.pi),
          burlap);
    }

    sack(-0.42, 0, 0.15, 0xC63A2C);
    sack(0.44, -0.08, -0.2, 0x3E73B5);
    sack(0.1, 0.78, 1.45, 0x4F9A3A, lying: true);
  }

  // ---- the Corn Maze: the field and its scarecrow -------------------------------------

  /// Where the scarecrow keeps watch, in his clearing in the corn.
  Vec2 get _scarecrowAt => Vec2(_b.center.x - 14, _b.min.y - 9);

  /// The corn stands beyond the fence on three sides, leaving the camera's
  /// side open.
  bool _inCornField(double x, double z) {
    final clear = _clearance(x, z);
    if (clear < 7.5 || clear > 40) return false;
    return z < _b.max.y - 2;
  }

  /// The field's rows behind the green, the [near] half or the far one,
  /// after the [plants] already planted; the plants planted then, null when
  /// they reached the field's cap (then nothing more is planted).
  int? _cornRows(_Merged into, int plants, {required bool near}) {
    const spacing = _cornSpacing;
    final rows = <double>[];
    for (var z = _b.min.y - 8; z > _b.min.y - 40; z -= spacing * 1.25) {
      rows.add(z);
    }
    final half = rows.length ~/ 2;
    for (final z in near ? rows.take(half) : rows.skip(half)) {
      for (var x = _b.min.x - 34; x < _b.max.x + 34; x += spacing) {
        final px = x + _rand.range(-0.35, 0.35);
        final pz = z + _rand.range(-0.3, 0.3);
        if (!_inCornField(px, pz)) continue;
        // The scarecrow's clearing, the crib's.
        if (_clearings.any(
            (clearing) => Vec2(px, pz).distanceTo(clearing.$1) < clearing.$2)) {
          continue;
        }
        if (Vec2(px, pz).distanceTo(_hostAt) < 4.5) {
          continue; // the host's spot
        }
        _cornPlant(into, Vec2(px, pz), _rand.range(0.85, 1.2),
            far: _clearance(px, pz) > 18);
        plants++;
        if (plants > 520) return null;
      }
    }
    return plants;
  }

  static const double _cornSpacing = 1.9;

  /// The sides: a few rows running beside the course, after the [plants]
  /// the rows planted.
  void _cornSides(_Merged into, int plants) {
    const spacing = _cornSpacing;
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
  void _cornPlant(_Merged into, Vec2 at, double scale, {bool far = false}) {
    final height = 2.6 * scale;
    final base = _ground;
    final tone = _rand.range(0.86, 1.1);
    int green(int hex) => _shade(hex, tone);
    // Far off, a plant is a stalk, a few leaves and a tassel: the detail
    // would not show, and the field is the game's heaviest geometry.
    if (!far) {
      into.add(
          tjs.BoxGeometry(1.95, 0.05, 1.5),
          _place(at.x, base + 0.02, at.y, yaw: _rand.range(-0.05, 0.05)),
          _shade(0x6B5A34, _rand.range(0.9, 1.08)));
    }
    into.add(tjg.CylinderGeometry(0.06, 0.1, height, far ? 4 : 5),
        _place(at.x, base + height / 2, at.y), green(0x6E9F3A),
        baseShade: 0.62);
    final yaw0 = _rand.range(0, math.pi * 2);
    final leaves = far ? 4 : 7;
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
    if (!far && _rand.chance(0.75)) {
      into.add(
          tjg.CylinderGeometry(0.11, 0.14, 0.55, 6),
          _place(at.x + 0.13, base + height * 0.52, at.y, roll: 0.35),
          0xA9C25A);
      into.add(
          tjg.ConeGeometry(0.1, 0.22, 6),
          _place(at.x + 0.24, base + height * 0.52 + 0.32, at.y, roll: 0.35),
          0xE9C866);
    }
    for (var spike = far ? 1 : 0; spike < (far ? 2 : 3); spike++) {
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

  /// The Corn Maze's own: a pumpkin patch along the corn's edge on the far
  /// side and at the scarecrow's feet, and out west a corn crib on stilts,
  /// gold showing between its slats.
  void _mazeProps(_Merged into, _Settle settle) {
    final rand = _propRand;
    final scarecrow = _scarecrowAt;
    _clearings.add((scarecrow, 3.6));
    for (final (dx, dz, r) in const [
      (-1.5, 1.3, 0.55),
      (1.3, 1.6, 0.42),
      (1.9, 0.2, 0.32),
    ]) {
      _pumpkin(into, scarecrow + Vec2(dx, dz), r, rand);
    }
    for (var i = 0; i < 11; i++) {
      final r = rand.range(0.4, 0.78);
      final want = Vec2(
        _b.min.x + _b.width * (0.05 + 0.9 * i / 10) + rand.range(-1, 1),
        _b.min.y - 5.9 + rand.range(-0.5, 0.5),
      );
      final at = settle(want, r + 0.2);
      if (at != null) _pumpkin(into, at, r, rand);
    }
    final cribAt = settle(Vec2(_b.min.x - 8.4, _b.min.y + _b.height * 0.3), 2.3,
        cornOk: true);
    if (cribAt == null) return;
    _clearings.add((cribAt, 3.6));
    _cornCrib(into, cribAt, math.pi / 2 + rand.range(-0.12, 0.12));
    for (final (dx, dz, r) in const [(2.0, 2.4, 0.6), (2.6, 1.3, 0.4)]) {
      final at = settle(cribAt + Vec2(dx, dz), r + 0.1, cornOk: true);
      if (at != null) _pumpkin(into, at, r, rand);
    }
  }

  /// A pumpkin: a squat orange ball pressed into eight lobes, dimpled on
  /// top, a stub of stem and a curl of vine; [r] its radius.
  void _pumpkin(_Merged into, Vec2 at, double r, _Rand rand) {
    _stood.add(('pumpkin', at, r));
    final body = tjs.SphereGeometry(1, 16, 9);
    final position = body.attributes['position'] as tjs.BufferAttribute;
    for (var i = 0; i < position.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      final rib = 1 - 0.13 * (1 - math.cos(4 * math.atan2(z, x)).abs());
      final dimple = 1 - 0.25 * math.max(0.0, y.abs() - 0.85) / 0.15;
      position.setXYZ(i, x * rib, y * dimple, z * rib);
    }
    body.computeVertexNormals();
    into.add(
      body,
      _place(at.x, _ground + r * 0.68, at.y,
          yaw: rand.range(0, math.pi * 2), sx: r, sy: r * 0.72, sz: r),
      rand.chance(0.5) ? 0xF08A24 : 0xE7781C,
      baseShade: 0.62,
    );
    final lean = rand.range(-0.3, 0.3);
    into.add(tjg.CylinderGeometry(r * 0.07, r * 0.11, r * 0.42, 6),
        _place(at.x, _ground + r * 1.36, at.y, roll: lean), 0x6B7A2E);
    into.add(
        tjg.TorusGeometry(r * 0.15, r * 0.025, 4, 10, math.pi * 1.6),
        _place(at.x + r * 0.17, _ground + r * 1.32, at.y,
            yaw: rand.range(0, math.pi * 2), tilt: 0.4),
        0x5E8F2E);
    // A leaf of its vine on the ground.
    final a = rand.range(0, math.pi * 2);
    into.add(
        tjg.IcosahedronGeometry(1, 0),
        _place(at.x + math.cos(a) * r * 1.1, _ground + 0.05,
            at.y - math.sin(a) * r * 1.1,
            yaw: a, sx: r * 0.7, sy: 0.05, sz: r * 0.55),
        _Farm.leafC);
  }

  /// A corn crib: a narrow crib of slats on short stilts under a red tin
  /// roof, the cobs showing gold between the slats.
  void _cornCrib(_Merged into, Vec2 at, double yaw) {
    _stood.add(('corn crib', at, 2.2));
    const length = 3.6;
    const width = 1.6;
    const floor = 0.6;
    const wall = 2.5;
    const timber = 0x8A5A34;
    const slat = 0xC08A55;
    for (final lx in [-length / 2 + 0.15, 0.0, length / 2 - 0.15]) {
      for (final lz in [-width / 2 + 0.12, width / 2 - 0.12]) {
        into.add(tjs.BoxGeometry(0.2, floor, 0.2),
            _inFrame(at, yaw, lx, floor / 2, lz), timber,
            baseShade: 0.6);
      }
    }
    into.add(tjs.BoxGeometry(length + 0.24, 0.12, width + 0.24),
        _inFrame(at, yaw, 0, floor, 0), timber);
    // The corn: a crib full of cobs, gold behind the slats.
    into.add(tjs.BoxGeometry(length - 0.16, wall - 0.1, width - 0.16),
        _inFrame(at, yaw, 0, floor + wall / 2, 0), 0xF2BE3A,
        baseShade: 0.8);
    for (final lx in [-length / 2, length / 2]) {
      for (final lz in [-width / 2, width / 2]) {
        into.add(tjs.BoxGeometry(0.16, wall + 0.1, 0.16),
            _inFrame(at, yaw, lx, floor + wall / 2, lz), timber);
      }
    }
    const rows = 7;
    for (var row = 0; row < rows; row++) {
      final y = floor + 0.2 + row * (wall - 0.35) / (rows - 1);
      for (final side in [-1.0, 1.0]) {
        into.add(tjs.BoxGeometry(length + 0.04, 0.15, 0.05),
            _inFrame(at, yaw, 0, y, side * (width / 2 + 0.03)), slat);
        into.add(tjs.BoxGeometry(0.05, 0.15, width + 0.04),
            _inFrame(at, yaw, side * (length / 2 + 0.03), y, 0), slat);
      }
    }
    // The roof: a gable along the crib, red tin over the rafters.
    final top = floor + wall + 0.02;
    into.add(_prism(width + 0.4, 0.75, length + 0.3),
        _inFrame(at, yaw, 0, top, 0, turn: math.pi / 2), timber);
    final slope = math.atan2(0.75, width / 2 + 0.2);
    final slab = math.sqrt(math.pow(width / 2 + 0.2, 2) + 0.75 * 0.75) + 0.2;
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjs.BoxGeometry(length + 0.7, 0.08, slab),
          _inFrame(at, yaw, 0, top + 0.43, side * (width / 4 + 0.1),
              tilt: side * slope),
          0xA8432F);
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

  /// Clumps of reeds and cattails along the lake's shore.
  void _reeds(_Merged into, Vec2 at, double radius) {
    final rand = _plantRand;
    for (var cluster = 0; cluster < 22; cluster++) {
      final angle = rand.range(0, math.pi * 2);
      final r = radius + rand.range(-1.2, 1.4);
      final spot = at + Vec2(math.cos(angle), math.sin(angle)) * r;
      if (_clearance(spot.x, spot.y) < 2) continue;
      final cattails = rand.chance(0.6);
      final size = rand.range(0.5, 0.7);
      _reedClump(into, spot, size, rand, cattails: cattails);
      _grown.add((cattails ? 'cattails' : 'reeds', spot, size));
    }
  }

  /// Where the dock leaves the shore: the shore nearest the green.
  Vec2 _dockStart(Vec2 lake, double radius) =>
      Vec2(lake.x + radius * 0.35, lake.y + radius * 0.94);

  void _dock(_Merged into, Vec2 at, double radius) {
    // From the shore nearest the green out over the water.
    final start = _dockStart(at, radius);
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

  /// The Pond's own: a rowboat tied up beside the dock, and lily pads laid
  /// like stepping stones along the lake's shallow edge.
  void _pondProps(_Merged into, _Merged small, Vec2 lake, double radius) {
    final dock = _dockStart(lake, radius);
    // Moored off the dock's side, its line to the dock's third post.
    _rowboat(into, Vec2(dock.x + 2.05, dock.y - 5.4), math.pi / 2 + 0.06,
        tiedTo: Vec2(dock.x + 1.1, dock.y - 6));
    _lilyPads(small, lake, radius);
  }

  /// A rowboat: a cream hull with a red rim, flared sides closing to a
  /// pointed bow, a plank floor, two seats and the oars shipped inside;
  /// its line made fast to [tiedTo] (a post's top).
  void _rowboat(_Merged into, Vec2 at, double yaw, {Vec2? tiedTo}) {
    _stood.add(('rowboat', at, 2.0));
    const hull = 0xF4EEE3;
    const rim = 0xC63A2C;
    const depth = 0.5;
    // The floor, above the water so the lake never shows inside.
    into.add(tjs.BoxGeometry(2.5, 0.08, 0.98),
        _inFrame(at, yaw, -0.25, 0.16, 0), _Farm.wood);
    into.add(tjs.BoxGeometry(2.5, 0.12, 0.8), _inFrame(at, yaw, -0.25, 0.04, 0),
        hull);
    for (final side in [-1.0, 1.0]) {
      // The side, flared out, its rim on top.
      into.add(
          tjs.BoxGeometry(2.5, depth, 0.08),
          _inFrame(at, yaw, -0.25, depth / 2 + 0.02, side * 0.56,
              tilt: side * 0.26),
          hull,
          baseShade: 0.8);
      into.add(tjs.BoxGeometry(2.56, 0.07, 0.12),
          _inFrame(at, yaw, -0.25, depth + 0.04, side * 0.62), rim);
      // The bow's planks close in to the stem.
      into.add(
          tjs.BoxGeometry(1.2, depth, 0.08),
          _inFrame(at, yaw, 1.5, depth / 2 + 0.02, side * 0.3,
              turn: side * 0.48, tilt: side * 0.18),
          hull,
          baseShade: 0.8);
      into.add(
          tjs.BoxGeometry(1.22, 0.07, 0.12),
          _inFrame(at, yaw, 1.52, depth + 0.04, side * 0.33, turn: side * 0.48),
          rim);
    }
    // The transom across the stern, the floor at the bow.
    into.add(tjs.BoxGeometry(0.08, depth, 1.24),
        _inFrame(at, yaw, -1.5, depth / 2 + 0.02, 0), hull);
    into.add(tjs.BoxGeometry(0.7, 0.08, 0.5), _inFrame(at, yaw, 1.3, 0.16, 0),
        _Farm.wood);
    // Two seats and the oars along them.
    for (final lx in [-0.85, 0.45]) {
      into.add(tjs.BoxGeometry(0.28, 0.06, 1.1), _inFrame(at, yaw, lx, 0.38, 0),
          _Farm.woodTop);
    }
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjg.CylinderGeometry(0.035, 0.035, 2.3, 6),
          _inFrame(at, yaw, -0.2, 0.46, side * 0.28,
              turn: side * 0.08, roll: math.pi / 2),
          _Farm.woodTop);
      into.add(
          tjs.BoxGeometry(0.6, 0.03, 0.16),
          _inFrame(at, yaw, -1.2, 0.46, side * 0.33, turn: side * 0.08),
          _Farm.wood);
    }
    final post = tiedTo;
    if (post == null) return;
    // The line from the bow's ring to the post, sagging.
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final bow = Vec2(at.x + 1.9 * c, at.y - 1.9 * s);
    final from = tjs.Vector3(bow.x, _ground + depth + 0.05, bow.y);
    final to = tjs.Vector3(post.x, _ground + 0.95, post.y);
    final sag = tjs.Vector3(
        (from.x + to.x) / 2, (from.y + to.y) / 2 - 0.3, (from.z + to.z) / 2);
    _rope(into, from, sag, 0xD9C08A);
    _rope(into, sag, to, 0xD9C08A);
  }

  /// A straight run of rope (or wire) from [from] to [to].
  void _rope(_Merged into, tjs.Vector3 from, tjs.Vector3 to, int hex,
      {double thickness = 0.04}) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final dz = to.z - from.z;
    final run = math.sqrt(dx * dx + dz * dz);
    final length = math.sqrt(run * run + dy * dy);
    into.add(
      tjs.BoxGeometry(length + thickness, thickness, thickness),
      _place((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2,
          yaw: -math.atan2(dz, dx), roll: math.atan2(dy, run)),
      hex,
    );
  }

  /// Lily pads laid like stepping stones along the lake's shallow edge,
  /// west of the dock, from two flat stones on the shore: notched discs in
  /// two greens, a pink or white flower open on a few.
  void _lilyPads(_Merged into, Vec2 lake, double radius) {
    final rand = _propRand;
    for (final (degrees, out) in const [(98.0, 1.4), (100.0, 0.2)]) {
      final angle = degrees * math.pi / 180;
      final at = lake + Vec2(math.cos(angle), math.sin(angle)) * (radius + out);
      into.add(
          tjg.DodecahedronGeometry(1, 0),
          _place(at.x, _ground + 0.08, at.y,
              yaw: rand.range(0, 6.28), sx: 0.75, sy: 0.16, sz: 0.6),
          _Farm.rock,
          baseShade: 0.75);
    }
    const pads = 9;
    for (var i = 0; i < pads; i++) {
      final angle = (103 + i * 5.4) * math.pi / 180;
      final reach = radius - 1.8 - (i.isOdd ? 0.7 : 0) - i * 0.12;
      final at = lake + Vec2(math.cos(angle), math.sin(angle)) * reach;
      final r = rand.range(0.62, 0.88);
      _stood.add(('lily pad', at, r));
      const notch = 0.6;
      into.add(
          tjg.CylinderGeometry(r, r, 0.05, 16, 1, false,
              rand.range(0, math.pi * 2), math.pi * 2 - notch),
          _place(at.x, _ground + 0.13, at.y),
          i.isEven ? _Farm.lily : 0x6AAE45);
      if (i % 3 != 1) continue;
      // A flower open on the pad.
      final petal = i == 4 ? 0xFFF5F8 : 0xF6A9C4;
      final fx = at.x + r * 0.25;
      final fz = at.y - r * 0.2;
      for (var p = 0; p < 7; p++) {
        final a = p / 7 * math.pi * 2;
        into.add(
            tjg.ConeGeometry(0.07, 0.26, 4),
            _place(fx + math.cos(a) * 0.09, _ground + 0.24,
                fz - math.sin(a) * 0.09,
                yaw: a, roll: -1.0, sz: 0.5),
            petal);
      }
      into.add(tjs.SphereGeometry(0.06, 8, 6), _place(fx, _ground + 0.24, fz),
          _Farm.flowerYolk);
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
      // The hubs stand a few centimetres proud of the tyres: a centimetre
      // out, their faces flickered through the rubber's.
      into.add(
          tjg.CylinderGeometry(0.55, 0.55, 0.68, 12),
          _place(at.x - 1.3, base + 1.15, at.y + side * 1.15,
              tilt: math.pi / 2),
          _hexOf(PuttPalette.yolk));
      into.add(
          tjg.CylinderGeometry(0.62, 0.62, 0.45, 14),
          _place(at.x + 1.9, base + 0.62, at.y + side * 0.95,
              tilt: math.pi / 2),
          tyre);
      into.add(
          tjg.CylinderGeometry(0.28, 0.28, 0.52, 10),
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

  /// A field's sheet: cells at most this long a side (world units), fine
  /// enough to follow the meadow's own (about 11 wide) within
  /// [_fieldLift].
  static const double _fieldCell = 2.5;

  /// How far a field floats over the meadow.
  static const double _fieldLift = 0.12;

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
      // Laid over the meadow's roll, a hand's breadth above it: a flat
      // sheet crossed the rolling grass along its contours, and the two
      // fought for the same pixels there (they flickered as the camera
      // moved).
      // As many squares each way (three_js_core's PlaneGeometry indexes a
      // grid of unequal sides out of range).
      final cells = (math.max(width, depth) / _fieldCell).ceil();
      final geometry = tjs.PlaneGeometry(width, depth, cells, cells)
        ..rotateX(-math.pi / 2);
      final position = geometry.attributes['position'] as tjs.BufferAttribute;
      for (var i = 0; i < position.count; i++) {
        final lx = position.getX(i)!.toDouble();
        final lz = position.getZ(i)!.toDouble();
        position.setY(i, _meadowY(x + lx, z + lz) + _fieldLift);
      }
      geometry.computeVertexNormals();
      final mesh = tjs.Mesh(
        geometry,
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.map: texture,
          tjs.MaterialProperty.roughness: 1.0,
          tjs.MaterialProperty.metalness: 0.0,
          // Where a crease of the meadow comes closer than the lift, the
          // field still wins.
          tjs.MaterialProperty.polygonOffset: true,
          tjs.MaterialProperty.polygonOffsetFactor: -1.0,
          tjs.MaterialProperty.polygonOffsetUnits: -4.0,
        }),
      )
        ..name = 'field'
        ..position.setValues(x, 0, z)
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

  /// Farm Road's own, on the near verge: a warning sign for eggs crossing,
  /// a chevron sign, and the milk churns waiting on their stand for the
  /// morning's pick-up. Pictures only, never words.
  void _roadProps(_Merged into, _Settle settle, double roadZ) {
    final rand = _propRand;
    final verge = roadZ + 4.3;
    final standAt = settle(Vec2(_b.min.x + 1.2, verge + 1.0), 1.5);
    if (standAt != null) _milkStand(into, standAt, rand.range(-0.08, 0.08));
    // Turned a little toward the camera's side, where the views come from.
    final eggSignAt = settle(Vec2(_b.min.x + _b.width * 0.3, verge), 0.6);
    if (eggSignAt != null) _eggCrossingSign(into, eggSignAt, 0.25);
    final chevronAt = settle(Vec2(_b.min.x + _b.width * 0.8, verge), 1.0);
    if (chevronAt != null) _chevronSign(into, chevronAt, 0.2);
  }

  /// A road sign's black.
  static const int _signBlack = 0x1E1A18;

  /// How far in front of a sign's board (its yellow face is 0.045 out)
  /// the black drawn on it stands: a centimetre out, the two flickered
  /// through each other from across the green.
  static const double _signInk = 0.07;

  /// A road sign's yellow.
  static const int _signYellow = 0xF5C21B;

  /// The warning sign for eggs crossing: a yellow diamond edged in black on
  /// a grey post, a black egg striding across it on two little legs.
  void _eggCrossingSign(_Merged into, Vec2 at, double yaw) {
    _stood.add(('egg crossing sign', at, 0.6));
    into.add(tjg.CylinderGeometry(0.06, 0.06, 2.6, 8),
        _inFrame(at, yaw, 0, 1.3, -0.07), 0x8C8F94,
        baseShade: 0.7);
    const y = 2.6;
    into.add(tjs.BoxGeometry(1.3, 1.3, 0.05),
        _inFrame(at, yaw, 0, y, 0, roll: math.pi / 4), _signBlack);
    into.add(tjs.BoxGeometry(1.14, 1.14, 0.05),
        _inFrame(at, yaw, 0, y, 0.02, roll: math.pi / 4), _signYellow);
    into.add(
        tjs.SphereGeometry(1, 14, 10),
        _inFrame(at, yaw, 0.02, y + 0.08, _signInk,
            sx: 0.2, sy: 0.27, sz: 0.02),
        _signBlack);
    for (final (lx, lean) in const [(-0.07, 0.4), (0.08, -0.35)]) {
      into.add(tjs.BoxGeometry(0.045, 0.22, 0.02),
          _inFrame(at, yaw, lx, y - 0.26, _signInk, roll: lean), _signBlack);
      into.add(
          tjs.BoxGeometry(0.11, 0.04, 0.02),
          _inFrame(at, yaw, lx - lean * 0.12 + 0.03, y - 0.37, _signInk),
          _signBlack);
    }
  }

  /// A chevron sign: a yellow board edged in black on two posts, three
  /// black chevrons pointing along the road.
  void _chevronSign(_Merged into, Vec2 at, double yaw) {
    _stood.add(('chevron sign', at, 1.0));
    for (final lx in [-0.62, 0.62]) {
      into.add(tjg.CylinderGeometry(0.05, 0.05, 2.0, 8),
          _inFrame(at, yaw, lx, 1.0, -0.07), 0x8C8F94,
          baseShade: 0.7);
    }
    const y = 1.85;
    into.add(tjs.BoxGeometry(1.9, 0.9, 0.05), _inFrame(at, yaw, 0, y, 0),
        _signBlack);
    into.add(tjs.BoxGeometry(1.78, 0.78, 0.05), _inFrame(at, yaw, 0, y, 0.02),
        _signYellow);
    for (var chevron = 0; chevron < 3; chevron++) {
      final lx = -0.5 + chevron * 0.48;
      for (final side in [-1.0, 1.0]) {
        into.add(
            tjs.BoxGeometry(0.4, 0.12, 0.02),
            _inFrame(at, yaw, lx, y + side * 0.13, _signInk,
                roll: -side * 0.62),
            _signBlack);
      }
    }
  }

  /// A milk stand by the road: a plank platform at a truck bed's height on
  /// four legs, three churns on it and one waiting on the ground.
  void _milkStand(_Merged into, Vec2 at, double yaw) {
    _stood.add(('milk stand', at, 1.5));
    const width = 2.6;
    const depth = 1.1;
    const height = 1.0;
    for (final lx in [-width / 2 + 0.12, width / 2 - 0.12]) {
      for (final lz in [-depth / 2 + 0.1, depth / 2 - 0.1]) {
        // Up to the planks' underside: into them, their faces met the
        // planks' edges a hair apart and flickered.
        into.add(tjs.BoxGeometry(0.14, height - 0.05, 0.14),
            _inFrame(at, yaw, lx, (height - 0.05) / 2, lz), _Farm.trunk,
            baseShade: 0.65);
      }
    }
    for (final lz in [-depth / 2 + 0.1, depth / 2 - 0.1]) {
      into.add(tjs.BoxGeometry(width - 0.2, 0.08, 0.06),
          _inFrame(at, yaw, 0, 0.36, lz), _Farm.trunk);
    }
    for (var plank = 0; plank < 3; plank++) {
      into.add(
          tjs.BoxGeometry(width, 0.1, depth / 3 - 0.03),
          _inFrame(at, yaw, 0, height, (plank - 1) * depth / 3),
          plank.isEven ? _Farm.wood : _Farm.woodTop);
    }
    for (final lx in [-0.82, 0.0, 0.82]) {
      _churn(into, at, yaw, lx, height + 0.05, 0);
    }
    _churn(into, at, yaw, width / 2 + 0.5, 0, 0.25);
  }

  /// A milk churn: a steel can, banded, its shoulders narrowing to a lidded
  /// neck, a handle each side; at ([lx], [ly], [lz]) in its stand's frame.
  void _churn(
      _Merged into, Vec2 at, double yaw, double lx, double ly, double lz) {
    const steel = 0xCBD2D8;
    const band = 0x9AA3AB;
    tjs.Matrix4 piece(double y, {double roll = 0, double dx = 0}) =>
        _inFrame(at, yaw, lx + dx, ly + y, lz, roll: roll);
    into.add(tjg.CylinderGeometry(0.25, 0.27, 0.56, 14), piece(0.28), steel,
        baseShade: 0.75);
    // The bands stand a few centimetres proud of the can (it tapers from
    // 0.27 at the foot to 0.25 at the shoulder): a centimetre out, they
    // and the can flickered through each other from across the green.
    for (final (y, radius) in const [(0.08, 0.3), (0.5, 0.285)]) {
      into.add(tjg.CylinderGeometry(radius, radius, 0.05, 14), piece(y), band);
    }
    into.add(tjg.CylinderGeometry(0.14, 0.25, 0.2, 14), piece(0.66), steel);
    into.add(tjg.CylinderGeometry(0.13, 0.14, 0.12, 12), piece(0.82), steel);
    into.add(tjg.CylinderGeometry(0.16, 0.16, 0.06, 12), piece(0.9), band);
    into.add(tjs.SphereGeometry(0.05, 8, 6), piece(0.95), band);
    for (final side in [-1.0, 1.0]) {
      into.add(tjg.TorusGeometry(0.08, 0.022, 4, 8, math.pi),
          piece(0.6, roll: -side * math.pi / 2, dx: side * 0.22), band);
    }
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
      final light = tjs.PointLight(0xFFFFFF, 5.0, 30, 1.3)
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

  /// The Barn's own: strings of warm bulbs over the yard, and a hay wagon
  /// loaded high out west.
  void _barnProps(tjs.Group group, _Merged into, _Merged small, _Settle settle,
      Vec2 barnAt, double barnScale) {
    _festoon(group, into, small, settle, barnAt, barnScale);
    final wagonAt = settle(Vec2(_b.min.x + 1.5, _b.min.y - 9.5), 2.6);
    if (wagonAt != null) _hayWagon(into, wagonAt, 0.35);
  }

  /// Strings of warm bulbs over the yard: from a post on each side of it
  /// to the barn's eaves, along the eaves, and swooping across the yard
  /// between the posts. The bulbs glow by their own light (one emissive
  /// mesh for them all, a soft halo on each), no lamps of their own.
  void _festoon(tjs.Group group, _Merged into, _Merged small, _Settle settle,
      Vec2 barnAt, double barnScale) {
    const postHeight = 5.2;
    const wire = 0x2A2228;
    final posts = [
      settle(Vec2(barnAt.x - 14.5, _b.min.y - 5.5), 0.5),
      settle(Vec2(barnAt.x + 14.2, _b.min.y - 5.5), 0.5),
    ];
    final left = posts[0];
    final right = posts[1];
    if (left == null || right == null) return;
    for (final post in [left, right]) {
      _stood.add(('lantern post', post, 0.5));
      into.add(tjg.CylinderGeometry(0.12, 0.17, postHeight, 7),
          _place(post.x, _ground + postHeight / 2, post.y), 0x3A2E28,
          baseShade: 0.7);
      into.add(tjs.BoxGeometry(0.9, 0.12, 0.12),
          _place(post.x, _ground + postHeight - 0.2, post.y), 0x3A2E28);
    }
    // The barn's front corners under the eaves.
    final halfWidth = 13.0 * barnScale / 2;
    final front = barnAt.y + 10.0 * barnScale / 2 + 0.25;
    final eave = _ground + 6.4 * barnScale - 0.35;
    tjs.Vector3 top(Vec2 post) =>
        tjs.Vector3(post.x, _ground + postHeight - 0.15, post.y);
    final eaveLeft = tjs.Vector3(barnAt.x - halfWidth + 0.3, eave, front);
    final eaveRight = tjs.Vector3(barnAt.x + halfWidth - 0.3, eave, front);
    final strings = [
      (top(left), eaveLeft, 0.9),
      (eaveLeft, eaveRight, 0.7),
      (eaveRight, top(right), 0.9),
      (top(left), top(right), 2.0),
    ];
    final bulbs = _Merged();
    final glows = <double>[];
    for (final (from, to, sag) in strings) {
      tjs.Vector3 along(double t) => tjs.Vector3(
            from.x + (to.x - from.x) * t,
            from.y + (to.y - from.y) * t - 4 * sag * t * (1 - t),
            from.z + (to.z - from.z) * t,
          );
      final length = from.distanceTo(to);
      final count = math.max(4, (length / 0.95).round());
      for (var i = 0; i < count; i++) {
        _rope(small, along(i / count), along((i + 1) / count), wire,
            thickness: 0.05);
        final at = along((i + 0.5) / count);
        small.add(tjg.CylinderGeometry(0.05, 0.05, 0.12, 6),
            _place(at.x, at.y - 0.06, at.z), wire);
        bulbs.add(
            tjg.IcosahedronGeometry(0.13, 1),
            _place(at.x, at.y - 0.2, at.z, sy: 1.2),
            i.isEven ? 0xFFE9B8 : 0xFFC978);
        glows.addAll([at.x, at.y - 0.2, at.z]);
      }
    }
    group.add(tjs.Mesh(
      bulbs.build(),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.emissive: _lin(0xFFB451),
        tjs.MaterialProperty.roughness: 0.4,
        tjs.MaterialProperty.metalness: 0.0,
      })
        ..emissiveIntensity = 1.6,
    )..name = 'festoon-bulbs');
    group.add(tjs.Points(
      tjs.BufferGeometry()
        ..setAttributeFromString(
            'position', tjs.Float32BufferAttribute.fromList(glows, 3, false)),
      tjs.PointsMaterial({
        tjs.MaterialProperty.color: _lin(0xFFC46B),
        tjs.MaterialProperty.map: _EggView3D._shadowTexture,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.55,
        tjs.MaterialProperty.depthWrite: false,
        tjs.MaterialProperty.blending: tjs.AdditiveBlending,
      })
        ..size = 1.2
        ..sizeAttenuation = true,
    )..name = 'festoon-glow');
  }

  /// A hay wagon: a plank bed with red sides on four spoked wheels (the
  /// back pair the bigger), its tongue down on the grass, loaded high with
  /// hay.
  void _hayWagon(_Merged into, Vec2 at, double yaw) {
    _stood.add(('hay wagon', at, 2.6));
    const length = 4.2;
    const width = 1.9;
    const bed = 1.05;
    const iron = 0x4A3426;
    into.add(tjs.BoxGeometry(length, 0.14, width), _inFrame(at, yaw, 0, bed, 0),
        _Farm.wood,
        baseShade: 0.8);
    for (final lz in [-0.6, 0.6]) {
      into.add(tjs.BoxGeometry(length - 0.3, 0.16, 0.14),
          _inFrame(at, yaw, 0, bed - 0.15, lz), _Farm.trunk);
    }
    for (final side in [-1.0, 1.0]) {
      into.add(
          tjs.BoxGeometry(length, 0.36, 0.08),
          _inFrame(at, yaw, 0, bed + 0.25, side * (width / 2 - 0.02)),
          _Farm.barnRedDark);
      for (final lx in [-length / 2 + 0.1, 0.0, length / 2 - 0.1]) {
        into.add(
            tjs.BoxGeometry(0.1, 0.62, 0.1),
            _inFrame(at, yaw, lx, bed + 0.32, side * (width / 2 + 0.03)),
            _Farm.trunk);
      }
    }
    for (final end in [-1.0, 1.0]) {
      into.add(
          tjs.BoxGeometry(0.08, 0.36, width),
          _inFrame(at, yaw, end * (length / 2 - 0.02), bed + 0.25, 0),
          _Farm.barnRedDark);
    }
    for (final (lx, r) in const [(-1.35, 0.78), (1.4, 0.62)]) {
      into.add(tjg.CylinderGeometry(0.06, 0.06, width + 0.5, 6),
          _inFrame(at, yaw, lx, r, 0, tilt: math.pi / 2), iron);
      for (final side in [-1.0, 1.0]) {
        final lz = side * (width / 2 + 0.2);
        into.add(tjg.TorusGeometry(r, 0.07, 5, 20),
            _inFrame(at, yaw, lx, r, lz), iron);
        for (var spoke = 0; spoke < 6; spoke++) {
          into.add(
              tjs.BoxGeometry(0.06, r * 2 - 0.1, 0.05),
              _inFrame(at, yaw, lx, r, lz, roll: spoke * math.pi / 6),
              _Farm.woodTop);
        }
        into.add(tjg.CylinderGeometry(0.13, 0.13, 0.2, 8),
            _inFrame(at, yaw, lx, r, lz, tilt: math.pi / 2), iron);
      }
    }
    // The tongue, down on the grass in front.
    into.add(tjs.BoxGeometry(2.0, 0.09, 0.09),
        _inFrame(at, yaw, length / 2 + 0.8, 0.45, 0, roll: -0.36), _Farm.trunk);
    into.add(tjs.BoxGeometry(0.09, 0.09, 0.8),
        _inFrame(at, yaw, length / 2 + 1.72, 0.1, 0), _Farm.trunk);
    // The load, heaped over the sides, straws poking out.
    for (final (lx, ly, lz, sx, sy, sz, hex) in const [
      (0.0, 1.8, 0.0, 2.2, 0.7, 1.14, _Farm.hay),
      (-0.85, 2.3, 0.2, 1.25, 0.58, 0.86, _Farm.strawLight),
      (0.8, 2.25, -0.18, 1.2, 0.55, 0.82, _Farm.straw),
      (-0.1, 2.65, 0.0, 1.05, 0.48, 0.72, _Farm.hay),
      (1.45, 1.95, 0.32, 0.85, 0.48, 0.7, _Farm.strawLight),
    ]) {
      into.add(tjg.IcosahedronGeometry(1, 1),
          _inFrame(at, yaw, lx, ly, lz, sx: sx, sy: sy, sz: sz), hex,
          baseShade: 0.72, rand: _propRand, variation: 0.06);
    }
    for (var i = 0; i < 14; i++) {
      final a = _propRand.range(0, math.pi * 2);
      into.add(
          tjs.BoxGeometry(0.5, 0.03, 0.05),
          _inFrame(at, yaw, math.cos(a) * 1.9, 1.6 + _propRand.range(0, 0.5),
              -math.sin(a) * 1.0,
              turn: a, roll: _propRand.range(-0.5, 0.5)),
          i.isEven ? _Farm.strawLight : _Farm.hayDark);
    }
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
