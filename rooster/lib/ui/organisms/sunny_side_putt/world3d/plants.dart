// The plants round each table. Every course grows its own where the
// meadow had the same round bushes everywhere: clipped boxwood balls,
// potted topiary and mophead hydrangeas in pink and blue by the Coop;
// rows of cabbages with curled outer leaves in the Corn Maze's beds and
// along its edges; clumps of reeds and brown-headed cattails at the Pond,
// on the lake's shore and round the table; a hawthorn hedgerow in white
// blossom along Farm Road, its field gates in the gaps; shrubs turned
// orange, rust and gold and plumes of fountain grass round the Barn.
//
// They pour into the farm's smooth-shaded mesh (`farm-soft`, with the
// meadow's stones), built of few-faced shapes whose normals round them
// off; the ones beyond the sun's shadow box pour into a second one
// (`farm-soft-far`), out of the shadow pass. They cost no more vertices
// than the bushes did. The farm group lists them in `userData['plants']`
// (kind, spot, footprint) and the garden beds' in
// `userData['bed plants']`.
part of '../putt_world3d.dart';

/// The plants' own colours (sRGB).
abstract final class _Flora {
  // The Coop.
  static const box = 0x3E7A39;
  static const boxLight = 0x4B8A3F;
  static const terracotta = 0xC4693D;
  static const terracottaRim = 0xD47F4E;
  static const hydrangeaLeaf = 0x4D9140;
  static const hydrangeaPink = [0xF4A3C4, 0xEC8DB6, 0xF8BFD6];
  static const hydrangeaBlue = [0x8DB2F2, 0x7C9BE9, 0xA9C5F7, 0xB3A3EA];

  // The Corn Maze.
  static const cabbageHeart = 0xD0E8A2;
  static const cabbageLeaf = 0x86B867;
  static const cabbageLeafBlue = 0x72A47A;
  static const bedSoil = 0x6A4A31;

  // The Pond.
  static const reeds = [0x6E9A3E, 0x86A94B, 0x5B8A39];
  static const cattailStem = 0x7A9A47;
  static const cattail = 0x6B4428;

  // Farm Road.
  static const hawthorn = 0x4F8E3E;
  static const hawthornLight = 0x5E9C46;
  static const blossom = 0xFFFBF2;
  static const blossomBlush = 0xF6E0E6;
  static const gate = 0xBDAD92;

  // The Barn.
  static const autumn = [0xE8822E, 0xC0562B, 0xEBB43A, 0xF0C64C];
  static const twig = 0x5A3A26;
  static const grass = 0xC9A04E;
  static const grassDark = 0xAD8A3E;
  static const plume = 0xF1DDA6;
}

extension _Plants on _Scenery {
  /// The table's bounds (kit's `_b` is a colour's blue).
  Rect get _table => hole.bounds;

  /// The course's plants round the table, where the meadow's bushes grew:
  /// off the table, the fence line, the landmarks and the props ([blocked])
  /// and one another.
  void _coursePlants(
      _Merged into, _Merged small, bool Function(double, double) blocked,
      {required double roadZ}) {
    final rand = _plantRand;
    switch (theme.kind) {
      case _ThemeKind.coop:
        _scatterPlants(30, blocked, () {
          final roll = rand.next();
          if (roll < 0.4) {
            return ('hydrangea', rand.range(0.62, 0.95));
          }
          return roll < 0.8
              ? ('boxwood', rand.range(0.45, 0.78))
              : ('topiary', 0.45);
        }, (kind, at, r, low) {
          switch (kind) {
            case 'hydrangea':
              _hydrangea(into, at, r, rand);
            case 'topiary':
              _topiary(into, at, rand, low: low);
            default:
              _boxwood(into, at, r, rand);
          }
        });
      case _ThemeKind.maze:
        _cabbageRows(into, small, blocked);
      case _ThemeKind.pond:
        _scatterPlants(
            26,
            blocked,
            () => rand.chance(0.6)
                ? ('cattails', rand.range(0.5, 0.7))
                : ('reeds', rand.range(0.45, 0.65)),
            (kind, at, r, low) => _reedClump(into, at, r, rand,
                cattails: kind == 'cattails', low: low));
      case _ThemeKind.road:
        _hedgerow(into, blocked, roadZ);
        _scatterPlants(3, blocked, () => ('hawthorn', rand.range(0.7, 0.95)),
            (kind, at, r, low) => _hawthorn(into, at, r, rand));
      case _ThemeKind.barn:
        _scatterPlants(
            31,
            blocked,
            () => rand.chance(0.68)
                ? ('autumn shrub', rand.range(0.75, 1.05))
                : ('fountain grass', rand.range(0.6, 0.75)),
            (kind, at, r, low) => kind == 'fountain grass'
                ? _fountainGrass(into, at, r, rand, low: low)
                : _autumnShrub(into, at, r, rand));
    }
  }

  /// How often a garden bed's spot grows the course's plant (outside the
  /// maze, whose cabbages keep to rows): the dearer the plant, the fewer,
  /// so a bed costs what its old bushes did.
  double get _bedChance => switch (theme.kind) {
        _ThemeKind.road => 0.1,
        _ThemeKind.barn => 0.16,
        _ => 0.2,
      };

  /// One plant of the course's on the carved ground of a garden bed at [at]
  /// (the maze's cabbages stand in rows: see [_carvedMeadow]).
  void _bedPlant(_Merged into, Vec2 at, _Rand rand) {
    final (String kind, double r) = switch (theme.kind) {
      _ThemeKind.coop => ('boxwood', rand.range(0.38, 0.55)),
      _ThemeKind.maze => ('cabbage', rand.range(0.36, 0.44)),
      _ThemeKind.pond => ('reeds', rand.range(0.35, 0.5)),
      _ThemeKind.road => ('hawthorn', rand.range(0.45, 0.6)),
      _ThemeKind.barn => ('autumn shrub', rand.range(0.45, 0.6)),
    };
    _bedGrown.add((kind, at, r));
    switch (theme.kind) {
      case _ThemeKind.coop:
        _boxwood(into, at, r, rand, pair: false);
      case _ThemeKind.maze:
        _cabbage(into, at, r, rand);
      case _ThemeKind.pond:
        _reedClump(into, at, r, rand, cattails: false, low: true);
      case _ThemeKind.road:
        _hawthorn(into, at, r, rand, lumps: 1, blossoms: 7);
      case _ThemeKind.barn:
        _autumnShrub(into, at, r, rand, small: true);
    }
  }

  /// [tries] plants scattered round the table: [pick] names each one's
  /// kind and footprint, [grow] grows it at its spot ([low] on the
  /// camera's side, where it keeps under the view).
  void _scatterPlants(
    int tries,
    bool Function(double, double) blocked,
    (String, double) Function() pick,
    void Function(String kind, Vec2 at, double r, bool low) grow,
  ) {
    for (var i = 0; i < tries; i++) {
      final at = _spotAround(minClear: 1.6, maxClear: 22, rand: _plantRand);
      if (at == null) continue;
      final (kind, r) = pick();
      if (!_plantable(at, r, blocked)) continue;
      grow(kind, at, r, _cameraSide(at.y, reach: 16));
      _grown.add((kind, at, r));
    }
  }

  /// Whether a plant [r] across fits at [at]: off the table and its lip,
  /// clear of the picket fence's line, of what [blocked] keeps (the
  /// landmarks, the host, the course's props, the road, the corn) and of
  /// the plants grown before it.
  bool _plantable(Vec2 at, double r, bool Function(double, double) blocked) {
    if (_clearance(at.x, at.y) < r + 0.3) return false;
    if (_fromFence(at) < r + 0.3) return false;
    if (blocked(at.x, at.y)) return false;
    for (final (_, spot, radius) in _grown) {
      if (spot.distanceTo(at) < radius + r) return false;
    }
    return true;
  }

  /// How far [at] stands from the picket fence's line (the rectangle its
  /// posts stand on), inside or out.
  double _fromFence(Vec2 at) {
    const out = _Scenery._fenceGap + _fenceThickness;
    final minX = _table.min.x - out;
    final maxX = _table.max.x + out;
    final minZ = _table.min.y - out;
    final maxZ = _table.max.y + out;
    final inside = at.x > minX && at.x < maxX && at.y > minZ && at.y < maxZ;
    if (inside) {
      return math.min(math.min(at.x - minX, maxX - at.x),
          math.min(at.y - minZ, maxZ - at.y));
    }
    final dx = math.max(math.max(minX - at.x, at.x - maxX), 0.0);
    final dz = math.max(math.max(minZ - at.y, at.y - maxZ), 0.0);
    return math.sqrt(dx * dx + dz * dz);
  }

  /// A piece leaning out from [base] on the ground toward [yaw] by [lean]:
  /// its own y axis tipped that way, its middle [along] up the lean.
  tjs.Matrix4 _leaning(Vec2 base, double yaw, double lean, double along,
          {double lift = 0, double sx = 1, double sy = 1, double sz = 1}) =>
      _inFrame(
          base, yaw, math.sin(lean) * along, lift + math.cos(lean) * along, 0,
          roll: -lean, sx: sx, sy: sy, sz: sz);

  // ---- the Coop -------------------------------------------------------------------------

  /// A clipped boxwood ball, deep glossy green, sat a little into the
  /// grass; now and then a smaller one beside it ([pair]).
  void _boxwood(_Merged into, Vec2 at, double r, _Rand rand,
      {bool pair = true}) {
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x, _Scenery._ground + r * 0.8, at.y,
          yaw: rand.range(0, 6.28), sx: r, sy: r * 0.92, sz: r),
      rand.chance(0.5) ? _Flora.box : _Flora.boxLight,
      baseShade: 0.5,
      rand: rand,
      variation: 0.05,
    );
    if (!pair || !rand.chance(0.45)) return;
    final small = r * rand.range(0.5, 0.65);
    final a = rand.range(0, math.pi * 2);
    final reach = r * 0.9 + small * 0.55;
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x + math.cos(a) * reach, _Scenery._ground + small * 0.78,
          at.y + math.sin(a) * reach,
          sx: small, sy: small * 0.92, sz: small),
      _Flora.boxLight,
      baseShade: 0.5,
      rand: rand,
      variation: 0.05,
    );
  }

  /// Boxwood clipped into a topiary in a terracotta pot: a ball on a bare
  /// stem, often a smaller ball above it (one ball only when [low]).
  void _topiary(_Merged into, Vec2 at, _Rand rand, {bool low = false}) {
    const potHeight = 0.46;
    into.add(tjg.CylinderGeometry(0.3, 0.22, potHeight, 10),
        _place(at.x, _Scenery._ground + potHeight / 2, at.y), _Flora.terracotta,
        baseShade: 0.7);
    into.add(tjg.CylinderGeometry(0.35, 0.35, 0.1, 10),
        _place(at.x, _Scenery._ground + potHeight, at.y), _Flora.terracottaRim);
    const stem = 0.42;
    into.add(
        tjg.CylinderGeometry(0.035, 0.045, stem + 0.2, 5, 1, true),
        _place(at.x, _Scenery._ground + potHeight + stem / 2, at.y),
        _Farm.trunk);
    const ball = 0.42;
    final ballY = _Scenery._ground + potHeight + stem + ball * 0.8;
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x, ballY, at.y, sx: ball, sy: ball * 0.94, sz: ball),
      _Flora.box,
      baseShade: 0.62,
      rand: rand,
      variation: 0.05,
    );
    if (low || rand.chance(0.35)) return;
    const top = 0.26;
    into.add(tjg.CylinderGeometry(0.03, 0.035, 0.3, 5, 1, true),
        _place(at.x, ballY + ball * 0.9, at.y), _Farm.trunk);
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x, ballY + ball + 0.12 + top * 0.8, at.y,
          sx: top, sy: top * 0.94, sz: top),
      _Flora.boxLight,
      baseShade: 0.7,
      rand: rand,
      variation: 0.05,
    );
  }

  /// A mophead hydrangea: a low mound of leaves, a few broad leaves
  /// splayed at its foot, and round heads of bloom all over its top, pink
  /// or blue.
  void _hydrangea(_Merged into, Vec2 at, double r, _Rand rand) {
    final mound = _Scenery._ground + r * 0.42;
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x, mound, at.y,
          yaw: rand.range(0, 6.28), sx: r, sy: r * 0.72, sz: r),
      _Flora.hydrangeaLeaf,
      baseShade: 0.45,
      rand: rand,
      variation: 0.06,
    );
    for (var leaf = 0; leaf < 5; leaf++) {
      final a = leaf / 5 * math.pi * 2 + rand.range(-0.3, 0.3);
      into.add(
          _softLeaf(),
          _inFrame(at, a, r * 0.86, r * 0.2, 0,
              roll: 0.3, sx: r * 0.42, sy: 0.05, sz: r * 0.26),
          _Farm.leafC,
          rand: rand,
          variation: 0.08);
    }
    final colors =
        rand.chance(0.5) ? _Flora.hydrangeaPink : _Flora.hydrangeaBlue;
    final heads = 5 + rand.below(3);
    for (var h = 0; h < heads; h++) {
      final a = h / heads * math.pi * 2 + rand.range(-0.3, 0.3);
      // Up over the mound: one head on its crown, the rest round its sides.
      final rise = h == 0 ? 0.0 : rand.range(0.55, 1.05);
      final size = r * rand.range(0.3, 0.38);
      into.add(
        _softBall(),
        _place(
            at.x + math.cos(a) * math.sin(rise) * r * 0.86,
            mound + math.cos(rise) * r * 0.68,
            at.y + math.sin(a) * math.sin(rise) * r * 0.86,
            yaw: rand.range(0, 6.28),
            sx: size,
            sy: size * 0.86,
            sz: size),
        colors[rand.below(colors.length)],
        baseShade: 0.8,
        rand: rand,
        variation: 0.06,
      );
    }
  }

  // ---- the Corn Maze --------------------------------------------------------------------

  /// A cabbage: a pale round heart, and outer leaves cupped round it, their
  /// edges curled up and out.
  void _cabbage(_Merged into, Vec2 at, double r, _Rand rand) {
    into.add(
      _softBall(),
      _place(at.x, _Scenery._ground + r * 0.55, at.y,
          yaw: rand.range(0, 6.28), sx: r * 0.62, sy: r * 0.58, sz: r * 0.62),
      _Flora.cabbageHeart,
      baseShade: 0.7,
      rand: rand,
      variation: 0.05,
    );
    final turn = rand.range(0, math.pi * 2);
    for (var leaf = 0; leaf < 4; leaf++) {
      final a = turn + leaf / 4 * math.pi * 2 + rand.range(-0.2, 0.2);
      into.add(
        _softLeaf(),
        _inFrame(at, a, r * 0.5, r * 0.24, 0,
            roll: rand.range(0.5, 0.75),
            sx: r * 0.64,
            sy: r * 0.1,
            sz: r * 0.52),
        leaf.isEven ? _Flora.cabbageLeaf : _Flora.cabbageLeafBlue,
        baseShade: 0.8,
        rand: rand,
        variation: 0.06,
      );
    }
  }

  /// Cabbage rows on beds of dark soil along the table's sides, between
  /// the fence and the corn: a few rows to a side, broken where a pumpkin,
  /// the host or a landmark stands.
  void _cabbageRows(
      _Merged into, _Merged small, bool Function(double, double) blocked) {
    final rand = _plantRand;
    const lip = _fenceThickness + 0.5;
    // Out from the lip: past the fence (3.1), short of the corn (7.5).
    const out = 5.3;
    const spacing = 0.95;
    final west = _table.min.x - lip - out;
    final east = _table.max.x + lip + out;
    final north = _table.min.y - lip - out;
    final south = _table.max.y + lip + out;
    // The four sides, each from one corner to the next; the third is the
    // camera's.
    final sides = [
      (Vec2(west, north), Vec2(east, north), false),
      (Vec2(east, north), Vec2(east, south), false),
      (Vec2(east, south), Vec2(west, south), true),
      (Vec2(west, south), Vec2(west, north), false),
    ];
    for (final (from, to, cameraSide) in sides) {
      final length = from.distanceTo(to);
      final along = (to - from).normalized(const Vec2(1, 0));
      var s = rand.range(1.5, 5.0);
      while (s < length - 1.5) {
        final count = 3 + rand.below(2);
        final row = <Vec2>[];
        for (var c = 0; c < count && s < length - 1.5; c++, s += spacing) {
          final at = from + along * s;
          // The gate in the camera's side stays open.
          if (cameraSide && (at.x - _table.center.x).abs() < 6) continue;
          const r = 0.42;
          if (!_plantable(at, r, blocked)) continue;
          row.add(at);
        }
        if (row.length >= 2) {
          // The bed under the row, a little longer than it.
          final first = row.first;
          final last = row.last;
          final middle = (first + last) * 0.5;
          small.add(
              tjs.BoxGeometry(first.distanceTo(last) + 1.0, 0.06, 1.0),
              _place(middle.x, _Scenery._ground + 0.02, middle.y,
                  yaw: -math.atan2(along.y, along.x)),
              _Flora.bedSoil,
              rand: rand,
              variation: 0.06);
          for (final at in row) {
            final r = rand.range(0.36, 0.44);
            _cabbage(into, at, r, rand);
            _grown.add(('cabbage', at, r));
          }
        }
        s += rand.range(5.0, 9.0);
      }
    }
  }

  // ---- the Pond -------------------------------------------------------------------------

  /// A clump of reeds: slim blades fanning out from one spot, and with
  /// [cattails] a few stiff stems carrying the brown velvet heads, a spike
  /// on each. [low] keeps it short (the camera's side).
  void _reedClump(_Merged into, Vec2 at, double r, _Rand rand,
      {required bool cattails, bool low = false}) {
    final tall = low ? 0.6 : 1.0;
    final blades = 10 + rand.below(4);
    for (var b = 0; b < blades; b++) {
      final a = rand.range(0, math.pi * 2);
      final from =
          at + Vec2(math.cos(a), -math.sin(a)) * (r * rand.range(0.0, 0.55));
      final h = rand.range(0.8, 1.5) * tall;
      into.add(
        tjg.ConeGeometry(0.065, h, 3, 1, true),
        _leaning(from, a, rand.range(0.06, 0.32), h / 2),
        _Flora.reeds[rand.below(_Flora.reeds.length)],
        baseShade: 0.6,
      );
    }
    if (!cattails) return;
    final heads = 2 + rand.below(3);
    for (var c = 0; c < heads; c++) {
      final a = rand.range(0, math.pi * 2);
      final from =
          at + Vec2(math.cos(a), -math.sin(a)) * (r * rand.range(0.1, 0.45));
      final h = rand.range(1.15, 1.65) * tall;
      final lean = rand.range(0.0, 0.1);
      into.add(tjg.CylinderGeometry(0.018, 0.026, h, 4, 1, true),
          _leaning(from, a, lean, h / 2), _Flora.cattailStem,
          baseShade: 0.7);
      into.add(
          _softBall(),
          _leaning(from, a, lean, h - 0.14, sx: 0.085, sy: 0.24, sz: 0.085),
          _Flora.cattail,
          baseShade: 0.75,
          rand: rand,
          variation: 0.08);
      into.add(tjg.ConeGeometry(0.012, 0.18, 3, 1, true),
          _leaning(from, a, lean, h + 0.16), _Flora.cattailStem);
    }
  }

  // ---- Farm Road ------------------------------------------------------------------------

  /// A hawthorn hedgerow along the road's far verge, between the poles and
  /// the fields: one long row of dark rounded lumps, a crown poking up
  /// here and there, all in white blossom; a field gate in each gap.
  void _hedgerow(
      _Merged into, bool Function(double, double) blocked, double roadZ) {
    final rand = _plantRand;
    final z = roadZ - 5.6;
    final from = _table.min.x - 16;
    final to = _table.max.x + 16;
    // A gate every 26 or so, off the table's middle.
    final gates = <double>[
      for (var x = _table.center.x + 9 - 26 * 4; x < to; x += 26)
        if (x > from + 3 && x < to - 3) x,
    ];
    for (final x in gates) {
      if (blocked(x, z)) continue;
      _fieldGate(into, Vec2(x, z));
    }
    var x = from;
    while (x < to) {
      final at = Vec2(x + rand.range(-0.3, 0.3), z + rand.range(-0.25, 0.25));
      x += rand.range(2.2, 2.7);
      if (gates.any((gate) => (gate - at.x).abs() < 2.9)) continue;
      if (blocked(at.x, at.y)) continue;
      final sx = rand.range(1.45, 1.75);
      final sy = rand.range(0.85, 1.2);
      final sz = rand.range(0.75, 0.9);
      _hawthornLump(into, at, sx, sy, sz, rand, blossoms: 9);
      if (rand.chance(0.15)) {
        _hawthornLump(into, at + Vec2(rand.range(-0.4, 0.4), 0), sx * 0.62,
            sy * 0.7, sz * 0.7, rand,
            lift: sy * 1.05, blossoms: 3);
      }
      _grown.add(('hawthorn hedge', at, sx));
    }
  }

  /// A hawthorn shrub on the meadow: one or two lumps, [blossoms] clusters
  /// of bloom on the first.
  void _hawthorn(_Merged into, Vec2 at, double r, _Rand rand,
      {int lumps = 2, int blossoms = 8}) {
    for (var l = 0; l < lumps; l++) {
      final a = rand.range(0, math.pi * 2);
      final reach = l == 0 ? 0.0 : r * 0.45;
      final size = l == 0 ? r : r * 0.7;
      _hawthornLump(into, at + Vec2(math.cos(a), math.sin(a)) * reach, size,
          size * rand.range(0.85, 1.05), size * 0.9, rand,
          blossoms: l == 0 ? blossoms : 4);
    }
  }

  /// One lump of hawthorn [sx] by [sy] by [sz] (half-sizes) on the ground
  /// at [at], [lift] above it, and [blossoms] clusters of white bloom
  /// over its top and sides.
  void _hawthornLump(
      _Merged into, Vec2 at, double sx, double sy, double sz, _Rand rand,
      {double lift = 0, int blossoms = 6}) {
    final y = _Scenery._ground + lift + sy * 0.78;
    into.add(
      tjg.IcosahedronGeometry(1, 1),
      _place(at.x, y, at.y, yaw: rand.range(-0.2, 0.2), sx: sx, sy: sy, sz: sz),
      rand.chance(0.5) ? _Flora.hawthorn : _Flora.hawthornLight,
      baseShade: 0.5,
      rand: rand,
      variation: 0.07,
    );
    for (var b = 0; b < blossoms; b++) {
      final a = rand.range(0, math.pi * 2);
      final rise = rand.range(0.1, 1.05);
      final size = rand.range(0.2, 0.28);
      into.add(
        _softLeaf(),
        _place(
            at.x + math.cos(a) * math.sin(rise) * sx * 0.96,
            y + math.cos(rise) * sy * 0.96,
            at.y + math.sin(a) * math.sin(rise) * sz * 0.96,
            yaw: a,
            tilt: rand.range(-0.4, 0.4),
            sx: size,
            sy: size * 0.6,
            sz: size),
        rand.chance(0.75) ? _Flora.blossom : _Flora.blossomBlush,
      );
    }
  }

  /// A weathered five-bar field gate in a gap of the hedgerow, along x.
  void _fieldGate(_Merged into, Vec2 at) {
    const half = 1.9;
    for (final side in const [-1.0, 1.0]) {
      into.add(tjs.BoxGeometry(0.2, 1.4, 0.2),
          _place(at.x + side * half, _Scenery._ground + 0.7, at.y), _Flora.gate,
          baseShade: 0.7);
    }
    for (var bar = 0; bar < 5; bar++) {
      into.add(tjs.BoxGeometry(half * 2, 0.1, 0.06),
          _place(at.x, _Scenery._ground + 0.3 + bar * 0.22, at.y), _Flora.gate);
    }
    into.add(
        tjs.BoxGeometry(half * 2.05, 0.1, 0.06),
        _place(at.x, _Scenery._ground + 0.74, at.y + 0.04,
            roll: math.atan2(0.88, half * 2)),
        _Flora.gate);
  }

  // ---- the Barn -------------------------------------------------------------------------

  /// A shrub turned for autumn: a few twiggy stems fanning up out of the
  /// grass, clusters of leaves in orange, rust or gold at their tips and
  /// in the middle, a scatter of fallen leaves round its foot. [small]
  /// for a garden bed's.
  void _autumnShrub(_Merged into, Vec2 at, double r, _Rand rand,
      {bool small = false}) {
    final main = _Flora.autumn[rand.below(_Flora.autumn.length)];
    final accent = _Flora.autumn[rand.below(_Flora.autumn.length)];
    final stems = small ? 2 : 3;
    final turn = rand.range(0, math.pi * 2);
    for (var s = 0; s < stems; s++) {
      final a = turn + s / stems * math.pi * 2 + rand.range(-0.3, 0.3);
      final h = r * rand.range(1.0, 1.25);
      final lean = rand.range(0.3, 0.5);
      into.add(tjg.CylinderGeometry(0.025, 0.045, h, 4, 1, true),
          _leaning(at, a, lean, h / 2), _Flora.twig,
          baseShade: 0.7);
      final size = r * rand.range(0.42, 0.52);
      into.add(
        _softBall(),
        _leaning(at, a, lean, h + size * 0.2,
            sx: size, sy: size * 0.8, sz: size),
        s.isEven ? main : accent,
        baseShade: 0.75,
        rand: rand,
        variation: 0.1,
      );
    }
    // The middle, fuller.
    into.add(
      small ? _softBall() : tjg.IcosahedronGeometry(1, 1),
      _place(at.x, _Scenery._ground + r * 0.62, at.y,
          yaw: rand.range(0, 6.28), sx: r * 0.62, sy: r * 0.6, sz: r * 0.62),
      main,
      baseShade: 0.55,
      rand: rand,
      variation: 0.08,
    );
    final fallen = small ? 3 : 5;
    for (var f = 0; f < fallen; f++) {
      final a = rand.range(0, math.pi * 2);
      final out = r * rand.range(0.7, 1.3);
      into.add(
          _softLeaf(),
          _place(at.x + math.cos(a) * out, _Scenery._ground + 0.03,
              at.y + math.sin(a) * out,
              yaw: rand.range(0, 6.28), sx: 0.13, sy: 0.02, sz: 0.09),
          rand.chance(0.5) ? main : accent,
          rand: rand,
          variation: 0.12);
    }
  }

  /// A clump of fountain grass gone gold: blades arching out all round,
  /// and soft cream plumes nodding over them ([low]: shorter).
  void _fountainGrass(_Merged into, Vec2 at, double r, _Rand rand,
      {bool low = false}) {
    final tall = low ? 0.65 : 1.0;
    for (var b = 0; b < 11; b++) {
      final a = b / 11 * math.pi * 2 + rand.range(-0.25, 0.25);
      final h = rand.range(0.85, 1.3) * tall;
      into.add(
        tjg.ConeGeometry(0.06, h, 3, 1, true),
        _leaning(at, a, rand.range(0.3, 0.75), h / 2),
        rand.chance(0.5) ? _Flora.grass : _Flora.grassDark,
        baseShade: 0.6,
      );
    }
    for (var p = 0; p < 4; p++) {
      final a = rand.range(0, math.pi * 2);
      final h = rand.range(1.05, 1.45) * tall;
      final lean = rand.range(0.15, 0.4);
      into.add(tjg.CylinderGeometry(0.012, 0.016, h, 3, 1, true),
          _leaning(at, a, lean, h / 2), _Flora.grass);
      into.add(
          _softBall(),
          _leaning(at, a, lean + 0.12, h + 0.12, sx: 0.07, sy: 0.22, sz: 0.07),
          _Flora.plume,
          baseShade: 0.85,
          rand: rand,
          variation: 0.05);
    }
  }
}
