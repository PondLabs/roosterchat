// The kickers: a short launch ramp on the green in each course's build -
// timber planks on a dark frame at the Coop, a ramp of baled hay bound with
// twine at the Barn, packed earth with corn stalks laid across it and a
// shock of them at either corner of the lip in the maze, a pale stone slab
// on a dry-stone wedge at the Pond, a dirt ramp with a striped takeoff
// board along its lip on Farm Road. The deck curves up to the lip at the
// launch angle (the core's own profile, [Kicker.deckRise], the one the
// eggs ride), and painted chevrons on it point the way it throws.
part of '../putt_world3d.dart';

/// A solid's faces poured into one plain geometry (positions, normals,
/// UVs), each quad wound to face its own normal.
class _SolidSink {
  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _uvs = [];

  void quad(List<(double, double, double)> corners,
      (double, double, double) normal, List<(double, double)> uv) {
    final (nx, ny, nz) = normal;
    final (ax, ay, az) = corners[0];
    final (bx, by, bz) = corners[1];
    final (cx, cy, cz) = corners[2];
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final vx = cx - ax, vy = cy - ay, vz = cz - az;
    final facing = (uy * vz - uz * vy) * nx +
        (uz * vx - ux * vz) * ny +
        (ux * vy - uy * vx) * nz;
    final order =
        facing >= 0 ? const [0, 1, 2, 0, 2, 3] : const [0, 2, 1, 0, 3, 2];
    for (final k in order) {
      final (x, y, z) = corners[k];
      _positions.addAll([x, y, z]);
      _normals.addAll([nx, ny, nz]);
      _uvs.addAll([uv[k].$1, uv[k].$2]);
    }
  }

  tjs.BufferGeometry build() => tjs.BufferGeometry()
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(_positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(_normals, 3, false))
    ..setAttributeFromString(
        'uv', tjs.Float32BufferAttribute.fromList(_uvs, 2, false));
}

/// The steps a kicker's curve is drawn in, foot to lip.
const int _kickerSteps = 14;

extension _KickerKit on _CourseKit {
  /// [kicker] in the course's build, in its own frame (x up the deck from
  /// the foot, z across it, y up): the group stands on the ground at the
  /// foot, turned the way the kicker throws.
  tjs.Group kicker(Kicker kicker) {
    final way = kicker.direction;
    final group = tjs.Group()
      ..name = 'kicker'
      ..rotation.y = -math.atan2(way.y, way.x)
      ..position.setValues(
          kicker.from.x, hole.groundHeightAt(kicker.from), kicker.from.y);
    final rand =
        _Rand(_seedOf('${hole.id}/kicker/${kicker.from.x}/${kicker.from.y}'));
    switch (theme.kind) {
      case _ThemeKind.coop:
        _plankKicker(group, kicker, rand);
      case _ThemeKind.barn:
        _hayKicker(group, kicker, rand);
      case _ThemeKind.maze:
        _cornKicker(group, kicker, rand);
      case _ThemeKind.pond:
        _stoneKicker(group, kicker, rand);
      case _ThemeKind.road:
        _roadKicker(group, kicker, rand);
    }
    group.add(_kickerChevrons(kicker));
    group.add(_kickerPad(kicker));
    return group;
  }

  /// The kicker's pad painted on the turf round its footprint: a frame in
  /// the course's accent, ink-edged - the kicker reads from across the
  /// green as the bold line it is (a small ramp in the lawn's own colours
  /// went unseen in stills).
  tjs.Mesh _kickerPad(Kicker kicker) {
    final fill = switch (theme.kind) {
      _ThemeKind.pond => 0xFFF6EA,
      _ => _hexOf(PuttPalette.yolk),
    };
    final half = kicker.width / 2;
    final foot = hole.groundHeightAt(kicker.from);
    final way = kicker.direction;
    final across = Vec2(-way.y, way.x);
    double groundAt(double x, double z) =>
        hole.groundHeightAt(kicker.from + way * x + across * z) - foot;
    final merged = _Merged();
    // The frame, its band [band] wide, [gap] out from the deck's edges.
    void frame(double gap, double band, double lift, int hex) {
      final x0 = -gap - 0.35, x1 = kicker.length + gap;
      final z1 = half + gap;
      final sink = _SolidSink();
      void bar(double ax, double az, double bx, double bz) {
        sink.quad([
          for (final (x, z) in [(ax, az), (bx, az), (bx, bz), (ax, bz)])
            (x, groundAt(x, z) + lift, z),
        ], (
          0,
          1,
          0
        ), const [
          (0, 0),
          (1, 0),
          (1, 1),
          (0, 1),
        ]);
      }

      bar(x0, -z1, x1, -z1 + band); // one side
      bar(x0, z1 - band, x1, z1); // the other
      bar(x0, -z1 + band, x0 + band, z1 - band); // behind the foot
      bar(x1 - band, -z1 + band, x1, z1 - band); // past the lip
      merged.add(sink.build(), tjs.Matrix4.identity(), hex);
    }

    frame(0.42, 0.34, 0.02, _hexOf(PuttPalette.ink));
    frame(0.36, 0.22, 0.03, fill);
    return merged.mesh('kicker-pad', castShadow: false, flat: true)!
      ..receiveShadow = true;
  }

  /// The Coop's: timber planks laid across a dark frame, a sliver of the
  /// dark showing between them.
  void _plankKicker(tjs.Group group, Kicker kicker, _Rand rand) {
    const thickness = 0.06;
    group.add(_kickerMesh(
      'kicker-body',
      _kickerWedge(kicker, inset: thickness),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0x5E3A22),
        tjs.MaterialProperty.map: _woodGrainTexture(),
        tjs.MaterialProperty.roughness: 0.86,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final length = kicker.length;
    final planks = _Merged();
    const plank = 0.3;
    const gap = 0.035;
    final count = math.max(1, ((length - 0.04) / (plank + gap)).floor());
    final step = (length - 0.04) / count;
    for (var i = 0; i < count; i++) {
      final x0 = 0.02 + i * step;
      final x1 = x0 + step - gap;
      final y0 = kicker.deckRise(x0 / length);
      final y1 = kicker.deckRise(x1 / length);
      final run = x1 - x0;
      final slope = math.atan2(y1 - y0, run);
      final across = kicker.width + 0.08;
      planks.add(
        tjs.BoxGeometry(
            math.sqrt(run * run + (y1 - y0) * (y1 - y0)), thickness, across),
        _place((x0 + x1) / 2, (y0 + y1) / 2 - thickness / 2, 0, roll: slope),
        i.isEven ? _Farm.woodTop : _mix(_Farm.woodTop, _Farm.wood, 0.5),
        baseShade: 0.85,
        rand: rand,
        variation: 0.06,
      );
      // Two nails at either end of each plank.
      for (final side in [-1.0, 1.0]) {
        planks.add(
          tjs.BoxGeometry(0.05, 0.012, 0.05),
          _place((x0 + x1) / 2, (y0 + y1) / 2 + 0.004,
              side * (kicker.width / 2 - 0.12),
              roll: slope),
          0x4A3A2C,
        );
      }
    }
    group.add(planks.mesh('kicker-planks', flat: true, roughness: 0.78)!);
  }

  /// The Barn's: a wedge of baled hay, two twine bands up the deck, loose
  /// straw round its foot and tufts sticking out of its lip.
  void _hayKicker(tjs.Group group, Kicker kicker, _Rand rand) {
    group.add(_kickerMesh(
      'kicker-body',
      _kickerWedge(kicker, tile: 1.6),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(_Farm.hay),
        tjs.MaterialProperty.map: _baleStackTexture(),
        tjs.MaterialProperty.roughness: 0.97,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final length = kicker.length;
    final half = kicker.width / 2;
    final straw = _Merged();
    // The twine up the deck, following its curve.
    for (final z in [-half * 0.55, half * 0.55]) {
      for (var i = 0; i < _kickerSteps; i++) {
        final x0 = length * i / _kickerSteps;
        final x1 = length * (i + 1) / _kickerSteps;
        final y0 = kicker.deckRise(x0 / length);
        final y1 = kicker.deckRise(x1 / length);
        final run = x1 - x0;
        straw.add(
          tjs.BoxGeometry(
              math.sqrt(run * run + (y1 - y0) * (y1 - y0)) + 0.01, 0.025, 0.07),
          _place((x0 + x1) / 2, (y0 + y1) / 2 + 0.008, z,
              roll: math.atan2(y1 - y0, run)),
          _Farm.strawDark,
        );
      }
    }
    // Loose straw round its foot and along its sides.
    for (var i = 0; i < 18; i++) {
      final onSide = rand.chance(0.55);
      final x = onSide ? rand.range(0, length) : rand.range(-0.5, 0.1);
      final z = onSide
          ? (rand.chance(0.5) ? -1 : 1) * (half + rand.range(0.05, 0.4))
          : rand.range(-half, half);
      straw.add(
        tjs.BoxGeometry(rand.range(0.3, 0.55), 0.025, 0.045),
        // Over the pad painted round the kicker (its frame lies 0.02 and
        // 0.03 up), each a little higher than the last: tops that met the
        // paint or a crossing straw's flickered.
        _place(x, 0.035 + i * 0.003, z, yaw: rand.range(0, math.pi)),
        rand.chance(0.5) ? _Farm.straw : _Farm.strawLight,
      );
    }
    // Tufts poking out of the lip's top edge.
    final lip = kicker.height;
    for (var i = 0; i < 9; i++) {
      final z = -half + kicker.width * (i + 0.5) / 9 + rand.range(-0.08, 0.08);
      straw.add(
        tjs.BoxGeometry(0.03, rand.range(0.16, 0.28), 0.03),
        _place(length + 0.02, lip - 0.02, z,
            roll: -rand.range(0.4, 0.9), tilt: rand.range(-0.3, 0.3)),
        rand.chance(0.5) ? _Farm.strawLight : _Farm.straw,
      );
    }
    group.add(straw.mesh('kicker-straw', flat: true, roughness: 0.95)!);
  }

  /// The maze's: packed earth with dry corn stalks laid across the deck,
  /// and a shock of stalks tied up at either corner of the lip.
  void _cornKicker(tjs.Group group, Kicker kicker, _Rand rand) {
    group.add(_kickerMesh(
      'kicker-body',
      _kickerWedge(kicker, tile: 1.8),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0x8C6440),
        tjs.MaterialProperty.map: _dirtTexture(),
        tjs.MaterialProperty.roughness: 0.98,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final length = kicker.length;
    final half = kicker.width / 2;
    final corn = _Merged();
    const dry = [0xD8BE6A, 0xC9A85A, 0xB89A50];
    final rows = math.max(3, (length / 0.36).round());
    for (var i = 0; i < rows; i++) {
      final x = length * (i + 0.5) / rows;
      corn.add(
        tjg.CylinderGeometry(0.04, 0.045, kicker.width + 0.1, 6),
        _place(x, kicker.deckRise(x / length) + 0.025, rand.range(-0.06, 0.06),
            tilt: math.pi / 2),
        dry[i % dry.length],
        rand: rand,
        variation: 0.07,
      );
    }
    // The shocks: stalks leaning together, a band round their waist, the
    // dry leaves fanning out of the top.
    for (final side in [-1.0, 1.0]) {
      final cx = length - 0.2;
      final cz = side * (half + 0.42);
      for (var s = 0; s < 8; s++) {
        final angle = s / 8 * math.pi * 2 + rand.range(-0.2, 0.2);
        final tall = rand.range(1.15, 1.5);
        final lean = 0.2;
        corn.add(
          tjg.CylinderGeometry(0.028, 0.04, tall, 5),
          // Leaning in to the shock's middle: the roll tips the top to
          // local -x, the yaw turns local -x inward.
          _place(
              cx + math.cos(angle) * 0.2, tall / 2, cz + math.sin(angle) * 0.2,
              yaw: -angle, roll: lean),
          dry[s % dry.length],
          rand: rand,
          variation: 0.08,
        );
      }
      corn.add(tjg.TorusGeometry(0.16, 0.03, 5, 14),
          _place(cx, 0.72, cz, tilt: math.pi / 2), _Farm.strawDark);
      for (var l = 0; l < 6; l++) {
        final angle = l / 6 * math.pi * 2;
        corn.add(
          tjs.BoxGeometry(0.06, 0.42, 0.012),
          _place(cx + math.cos(angle) * 0.08, 1.38, cz + math.sin(angle) * 0.08,
              yaw: -angle, roll: -0.6),
          0xE0C878,
        );
      }
    }
    group.add(corn.mesh('kicker-corn', flat: true, roughness: 0.9)!);
  }

  /// The Pond's: a pale stone slab capping a dry-stone wedge, pebbles and
  /// a little moss round its foot.
  void _stoneKicker(tjs.Group group, Kicker kicker, _Rand rand) {
    const slab = 0.09;
    // One drawing of the stones for the wedge and its slab.
    final stones = _stoneTexture();
    group.add(_kickerMesh(
      'kicker-body',
      _kickerWedge(kicker, inset: slab, tile: 1.4),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0xA79F94),
        tjs.MaterialProperty.map: stones,
        tjs.MaterialProperty.roughness: 0.94,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    group.add(_kickerMesh(
      'kicker-slab',
      _kickerPlate(kicker, thickness: slab, overhang: 0.05, tile: 3.2),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0xD3CCC0),
        tjs.MaterialProperty.map: stones,
        tjs.MaterialProperty.roughness: 0.82,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final length = kicker.length;
    final half = kicker.width / 2;
    final trim = _Merged();
    for (var i = 0; i < 12; i++) {
      final onSide = rand.chance(0.6);
      final x = onSide ? rand.range(0.1, length) : rand.range(-0.35, 0);
      final z = onSide
          ? (rand.chance(0.5) ? -1 : 1) * (half + rand.range(0.08, 0.3))
          : rand.range(-half, half);
      final r = rand.range(0.07, 0.15);
      trim.add(tjg.IcosahedronGeometry(r, 0), _place(x, r * 0.5, z, sy: 0.6),
          rand.chance(0.5) ? _Farm.rock : _Farm.rockDark,
          rand: rand, variation: 0.08);
    }
    for (var i = 0; i < 5; i++) {
      final x = rand.range(0.2, length * 0.8);
      final z = (rand.chance(0.5) ? -1 : 1) * (half + rand.range(0.0, 0.12));
      trim.add(tjs.SphereGeometry(rand.range(0.08, 0.14), 6, 4),
          _place(x, 0.04, z, sy: 0.45), _Farm.moss);
    }
    group.add(trim.mesh('kicker-stones', flat: true)!);
  }

  /// Farm Road's: a ramp of road dirt, a striped takeoff board along its
  /// lip, a few stones kicked up round its foot.
  void _roadKicker(tjs.Group group, Kicker kicker, _Rand rand) {
    group.add(_kickerMesh(
      'kicker-body',
      _kickerWedge(kicker, tile: 1.8),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0xB48F62),
        tjs.MaterialProperty.map: _dirtTexture(),
        tjs.MaterialProperty.roughness: 0.97,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final length = kicker.length;
    final board = math.min(0.5, length * 0.3);
    group.add(_kickerMesh(
      'kicker-board',
      _kickerPlate(kicker,
          from: (length - board) / length,
          thickness: 0.07,
          lift: 0.02,
          overhang: 0.06,
          tile: 0.9),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: _barrierTexture(),
        tjs.MaterialProperty.roughness: 0.55,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    ));
    final half = kicker.width / 2;
    final trim = _Merged();
    for (var i = 0; i < 9; i++) {
      final r = rand.range(0.05, 0.11);
      trim.add(
        tjg.IcosahedronGeometry(r, 0),
        _place(rand.range(-0.4, length * 0.6), r * 0.5,
            rand.range(-half - 0.3, half + 0.3),
            sy: 0.7),
        rand.chance(0.5) ? 0x8E7354 : 0xA58A66,
        rand: rand,
        variation: 0.08,
      );
    }
    group.add(trim.mesh('kicker-stones', flat: true)!);
  }

  /// Two chevrons painted up the deck, pointing at the lip: a bright
  /// fill in an ink rim, so the way it throws reads on any build.
  tjs.Mesh _kickerChevrons(Kicker kicker) {
    final fill = switch (theme.kind) {
      _ThemeKind.coop => 0xFFF6EA,
      _ThemeKind.barn => _hexOf(PuttPalette.comb),
      _ThemeKind.maze => 0xFFF6EA,
      _ThemeKind.pond => _hexOf(PuttPalette.yolk),
      _ThemeKind.road => 0xFFF6EA,
    };
    final length = kicker.length;
    final half = kicker.width / 2;
    // Bold: most of the deck's width, read from across the green.
    final size = math.min(half * 0.78, length * 0.36);
    final merged = _Merged();
    for (final at in [0.42, 0.82]) {
      final tip = length * at;
      merged.add(
          _chevron(kicker, tip + 0.06, size + 0.08, size * 0.36 + 0.12, 0.014),
          tjs.Matrix4.identity(),
          _hexOf(PuttPalette.ink));
      merged.add(_chevron(kicker, tip, size, size * 0.36, 0.024),
          tjs.Matrix4.identity(), fill);
    }
    return merged.mesh('kicker-chevrons', castShadow: false, flat: true)!;
  }

  /// One chevron on the deck, its tip at [tip] along it pointing at the
  /// lip, its arms [size] out to either side and [thickness] thick, laid
  /// [lift] over the deck's curve.
  tjs.BufferGeometry _chevron(
      Kicker kicker, double tip, double size, double thickness, double lift) {
    final length = kicker.length;
    double y(double x) => kicker.deckRise(x / length) + lift;
    final back = size * 0.7;
    final sink = _SolidSink();
    for (final side in [-1.0, 1.0]) {
      final corners = [
        (tip, 0.0),
        (tip - back, side * size),
        (tip - back - thickness, side * size),
        (tip - thickness, 0.0),
      ];
      sink.quad([
        for (final (x, z) in corners) (x, y(x), z),
      ], (
        0,
        1,
        0
      ), const [
        (0, 0),
        (1, 0),
        (1, 1),
        (0, 1),
      ]);
    }
    return sink.build();
  }

  tjs.Mesh _kickerMesh(String name, tjs.BufferGeometry geometry,
          tjs.MeshStandardMaterial material) =>
      tjs.Mesh(geometry, material)
        ..name = name
        ..castShadow = true
        ..receiveShadow = true;

  /// The kicker's wedge in its own frame: the deck curving up from the
  /// foot (x 0) to the lip (x its length) [inset] under the profile, both
  /// sides down to the turf and the lip's face; UVs in units over [tile].
  tjs.BufferGeometry _kickerWedge(Kicker kicker,
      {double inset = 0, double tile = 1.2}) {
    final length = kicker.length;
    final half = kicker.width / 2;
    double top(double x) => math.max(0.0, kicker.deckRise(x / length) - inset);
    final sink = _SolidSink();
    for (var i = 0; i < _kickerSteps; i++) {
      final x0 = length * i / _kickerSteps;
      final x1 = length * (i + 1) / _kickerSteps;
      final y0 = top(x0);
      final y1 = top(x1);
      final dx = x1 - x0;
      final dy = y1 - y0;
      final n = math.sqrt(dx * dx + dy * dy);
      sink.quad([
        (x0, y0, -half),
        (x1, y1, -half),
        (x1, y1, half),
        (x0, y0, half),
      ], (
        -dy / n,
        dx / n,
        0
      ), [
        (x0 / tile, 0),
        (x1 / tile, 0),
        (x1 / tile, kicker.width / tile),
        (x0 / tile, kicker.width / tile),
      ]);
      if (y1 <= 1e-6) continue;
      for (final side in [-1.0, 1.0]) {
        sink.quad([
          (x0, 0, side * half),
          (x1, 0, side * half),
          (x1, y1, side * half),
          (x0, y0, side * half),
        ], (
          0,
          0,
          side
        ), [
          (x0 / tile, 0),
          (x1 / tile, 0),
          (x1 / tile, y1 / tile),
          (x0 / tile, y0 / tile),
        ]);
      }
    }
    final lip = top(length);
    sink.quad([
      (length, 0, -half),
      (length, 0, half),
      (length, lip, half),
      (length, lip, -half),
    ], (
      1,
      0,
      0
    ), [
      (0, 0),
      (kicker.width / tile, 0),
      (kicker.width / tile, lip / tile),
      (0, lip / tile),
    ]);
    return sink.build();
  }

  /// A plate laid on the deck's curve from [from] of the way up it to the
  /// lip: its top [lift] over the profile, [thickness] deep, [overhang]
  /// past the deck's sides, its edges closed; UVs in units over [tile].
  tjs.BufferGeometry _kickerPlate(Kicker kicker,
      {double from = 0,
      double thickness = 0.08,
      double lift = 0,
      double overhang = 0,
      double tile = 1.2}) {
    final length = kicker.length;
    final half = kicker.width / 2 + overhang;
    final start = length * from;
    double top(double x) => kicker.deckRise(x / length) + lift;
    final steps =
        (_kickerSteps * (1 - from)).ceil().clamp(2, _kickerSteps).toInt();
    final sink = _SolidSink();
    for (var i = 0; i < steps; i++) {
      final x0 = start + (length - start) * i / steps;
      final x1 = start + (length - start) * (i + 1) / steps;
      final y0 = top(x0);
      final y1 = top(x1);
      final dx = x1 - x0;
      final dy = y1 - y0;
      final n = math.sqrt(dx * dx + dy * dy);
      sink.quad([
        (x0, y0, -half),
        (x1, y1, -half),
        (x1, y1, half),
        (x0, y0, half),
      ], (
        -dy / n,
        dx / n,
        0
      ), [
        (x0 / tile, 0),
        (x1 / tile, 0),
        (x1 / tile, half * 2 / tile),
        (x0 / tile, half * 2 / tile),
      ]);
      for (final side in [-1.0, 1.0]) {
        sink.quad([
          (x0, y0 - thickness, side * half),
          (x1, y1 - thickness, side * half),
          (x1, y1, side * half),
          (x0, y0, side * half),
        ], (
          0,
          0,
          side
        ), [
          (x0 / tile, 0),
          (x1 / tile, 0),
          (x1 / tile, thickness / tile),
          (x0 / tile, thickness / tile),
        ]);
      }
    }
    for (final (x, out) in [(length, 1.0), (start, -1.0)]) {
      final y = top(x);
      sink.quad([
        (x, y - thickness, -half),
        (x, y - thickness, half),
        (x, y, half),
        (x, y, -half),
      ], (
        out,
        0,
        0
      ), [
        (0, 0),
        (half * 2 / tile, 0),
        (half * 2 / tile, thickness / tile),
        (0, thickness / tile),
      ]);
    }
    return sink.build();
  }
}

/// Packed earth: soft blotches and fine grit, grey for tinting.
tjs.DataTexture _dirtTexture() {
  final bitmap = _Bitmap(64, 64);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      final n = _fbm(x / 7, y / 7, 47);
      final grit = _hash2(x, y, 53);
      var v = 0.74 + n * 0.3 + (grit - 0.5) * 0.14;
      if (grit > 0.95) v -= 0.2;
      if (grit < 0.03) v += 0.12;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}
