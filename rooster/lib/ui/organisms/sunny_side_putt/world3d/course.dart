// The course itself: the mown turf (one texture carrying stripes, the
// rails' contact shadows, the shores, the silo's spiral and the nest's
// shade), the wooden table it sits on, timber rails (the outer fence set
// outside the green so its face is where the physics' line is), rubber
// bumpers, boulders, ponds that ripple, speed belts whose chevrons run,
// rabbit holes, the silo, the "?" crates' face, the straw nest with its
// flag, and the tee mat.
part of '../putt_world3d.dart';

/// How high the table stands over the meadow: the green is a raised
/// diorama, its wooden skirt showing on the near side.
const double _tableHeight = 1.4;

/// The rails: the outer fence's thickness (set outside the green) and the
/// inner walls' (centred on the physics' line, slim so an egg touching it
/// barely overlaps the timber).
const double _fenceThickness = 0.62;
const double _innerThickness = 0.34;
const double _railHeight = 0.78;

/// Builds one hole's course pieces. Every piece is a fresh subtree the
/// world parents under its kind group; the hole's animated pieces register
/// with [animated].
class _CourseKit {
  _CourseKit(this.hole,
      {required this.eggRadius,
      required this.animated,
      required this.rig,
      required this.theme})
      : _rand = _Rand(_seedOf(hole.id));

  /// The course's look: the rails' style, the turf's greens.
  final _Theme theme;

  final HoleDef hole;
  final double eggRadius;
  final List<_Animated> animated;

  /// The camera rig: the flag turns its face to it.
  final PuttCameraRig rig;
  final _Rand _rand;

  /// One material for every rail body of the hole and one for the caps,
  /// in the theme's style (timber, corn hedge, stone, barrier, boards).
  late final (tjs.MeshStandardMaterial, tjs.MeshStandardMaterial) _rails =
      _railMaterials(theme.rails);
  tjs.MeshStandardMaterial get _railMaterial => _rails.$1;
  tjs.MeshStandardMaterial get _capMaterial => _rails.$2;

  /// The belt frames keep timber whatever the rails are.
  late final tjs.MeshStandardMaterial _timber = tjs.MeshStandardMaterial({
    tjs.MaterialProperty.color: _lin(_Farm.wood),
    tjs.MaterialProperty.map: _woodGrainTexture(),
    tjs.MaterialProperty.roughness: 0.78,
    tjs.MaterialProperty.metalness: 0.0,
  });

  tjs.DataTexture? _crateFace;

  /// Where the egg can roll from the tee; the rest of the bounds (corners
  /// the walls close off) is garden, not turf.
  late final _ReachGrid _reach = _ReachGrid.of(hole);

  /// The garden beds' ground per theme: mulch, dark earth, moss, gravel,
  /// straw.
  int get _gardenGround => switch (theme.kind) {
        _ThemeKind.coop => 0x7A5233,
        _ThemeKind.maze => 0x6A4A2C,
        _ThemeKind.pond => 0x5C8A3C,
        _ThemeKind.road => 0xB9A27E,
        _ThemeKind.barn => 0xC9A55A,
      };

  // ---- the turf ---------------------------------------------------------------------

  /// The green: one plane carrying the procedural lawn.
  tjs.Mesh lawn() {
    final bounds = hole.bounds;
    return tjs.Mesh(
      tjs.PlaneGeometry(bounds.width, bounds.height, 1, 1),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: _lawnTexture(),
        tjs.MaterialProperty.roughness: 0.96,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'lawn'
      // The plane's +z normal tips up to +y.
      ..rotation.x = -math.pi / 2
      ..position.setValues(bounds.center.x, 0, bounds.center.y)
      ..receiveShadow = true;
  }

  /// The lawn's texture: mown stripes across the tee-to-nest line, a
  /// darker fringe at the edge, contact shade along every rail, rock and
  /// bumper, sandy shores around the ponds (their beds darker), the
  /// silo's spiral pull, the rabbit holes' dug earth and the nest's ring
  /// of shade.
  tjs.DataTexture _lawnTexture() {
    final bounds = hole.bounds;
    final dx = math.max(bounds.width, 0.001);
    final dz = math.max(bounds.height, 0.001);
    final perUnit = math.min(10.0, 560 / math.max(dx, dz));
    final width = (dx * perUnit).round().clamp(32, 640).toInt();
    final height = (dz * perUnit).round().clamp(32, 640).toInt();
    final texelX = dx / width;
    final texelZ = dz / height;
    final bitmap = _Bitmap(width, height);
    final seed = _seedOf(hole.id);

    // Texel centre -> world point. Row 0 meets the green's far (+z) edge
    // reversed: PlaneGeometry maps its local +y to world -z, and the
    // texture's first row is v = 0, the plane's bottom (world +z).
    Vec2 worldAt(int col, int row) => Vec2(
          bounds.min.x + (col + 0.5) * texelX,
          bounds.max.y - (row + 0.5) * texelZ,
        );
    int colOf(double x) => ((x - bounds.min.x) / texelX).floor();
    int rowOf(double y) => ((bounds.max.y - y) / texelZ).floor();

    // The contact shade: the nearest rail-ish edge per texel, walked only
    // inside each piece's own neighbourhood.
    final shadeReach = 1.1;
    final nearest = Float32List(width * height)
      ..fillRange(0, width * height, 99);
    void stampDistance(Rect box, double Function(Vec2 point) distanceOf) {
      final c0 = colOf(box.min.x - shadeReach).clamp(0, width - 1);
      final c1 = colOf(box.max.x + shadeReach).clamp(0, width - 1);
      final r0 = rowOf(box.max.y + shadeReach).clamp(0, height - 1);
      final r1 = rowOf(box.min.y - shadeReach).clamp(0, height - 1);
      for (var row = r0; row <= r1; row++) {
        for (var col = c0; col <= c1; col++) {
          final d = distanceOf(worldAt(col, row));
          final i = row * width + col;
          if (d < nearest[i]) nearest[i] = d;
        }
      }
    }

    for (final wall in hole.walls) {
      final half = (_isPerimeter(wall) ? 0 : _innerThickness / 2) +
          (wall.bumper ? 0.06 : 0);
      stampDistance(
        Rect(
          Vec2(math.min(wall.a.x, wall.b.x), math.min(wall.a.y, wall.b.y)),
          Vec2(math.max(wall.a.x, wall.b.x), math.max(wall.a.y, wall.b.y)),
        ),
        (p) => math.max(0, _segmentDistance(p, wall.a, wall.b) - half),
      );
    }
    for (final arc in hole.arcs) {
      final full = arc.sweep >= 2 * math.pi - 0.01;
      final reach = arc.radius + 0.5;
      stampDistance(
        Rect(arc.center - Vec2(reach, reach), arc.center + Vec2(reach, reach)),
        (p) => full
            ? math.max(0, p.distanceTo(arc.center) - arc.radius * 0.96)
            : math.max(0, _arcDistance(p, arc) - _innerThickness / 2),
      );
    }

    final toNest = hole.nest.position - hole.tee;
    final axis = toNest.normalized(const Vec2(1, 0));
    const stripe = 2.6;

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final point = worldAt(col, row);
        // Mown stripes across the line of play.
        final along = (point - hole.tee).dot(axis);
        final band = (along / stripe).floor().isEven;
        var color = band ? theme.turfLight : theme.turfDark;
        // The turf's grain: patches and blades.
        final patch = _fbm(point.x * 0.35, point.y * 0.35, seed);
        final blade = _hash2(col, row, seed);
        color = _shade(color, 0.94 + patch * 0.1 + (blade - 0.5) * 0.05);

        // Garden: ground the egg can never reach (walled-off corners).
        if (!_reach.reachableAt(point)) {
          final soil = _shade(_gardenGround,
              0.86 + _fbm(point.x * 0.9, point.y * 0.9, seed + 2) * 0.24);
          bitmap.set(col, row, soil);
          continue;
        }

        // The fringe at the green's edge.
        final edge = math.min(
          math.min(point.x - bounds.min.x, bounds.max.x - point.x),
          math.min(point.y - bounds.min.y, bounds.max.y - point.y),
        );
        final fringe = _softBand(edge, 0.55, 0.3);
        if (fringe > 0) color = _mix(color, theme.turfFringe, fringe * 0.7);

        // Contact shade along rails and rocks.
        final contact = nearest[row * width + col];
        if (contact < shadeReach) {
          final k = math.pow(1 - contact / shadeReach, 1.6).toDouble();
          color = _mix(color, _Farm.turfShade, k * 0.55);
        }
        bitmap.set(col, row, color);
      }
    }

    // Ponds: the shore's sand and the bed's depth under the water.
    for (final shape in hole.water) {
      final box = _waterBox(shape);
      final c0 = colOf(box.min.x - 0.9).clamp(0, width - 1);
      final c1 = colOf(box.max.x + 0.9).clamp(0, width - 1);
      final r0 = rowOf(box.max.y + 0.9).clamp(0, height - 1);
      final r1 = rowOf(box.min.y - 0.9).clamp(0, height - 1);
      for (var row = r0; row <= r1; row++) {
        for (var col = c0; col <= c1; col++) {
          final point = worldAt(col, row);
          final signed = _waterSignedDistance(shape, point);
          if (signed < 0) {
            final depth = (-signed / 2.2).clamp(0.0, 1.0);
            bitmap.blend(col, row,
                _mix(_Farm.shore, _Farm.waterDeep, 0.35 + depth * 0.6), 1);
          } else if (signed < 0.75) {
            final k = _softBand(signed, 0.45, 0.3);
            bitmap.blend(col, row, _Farm.shore, k * 0.9);
          }
        }
      }
    }

    // The silo's pull: a spiral of darker turf curling toward the mouth.
    for (final well in hole.wells) {
      final reach = well.radius;
      final c0 = colOf(well.position.x - reach).clamp(0, width - 1);
      final c1 = colOf(well.position.x + reach).clamp(0, width - 1);
      final r0 = rowOf(well.position.y + reach).clamp(0, height - 1);
      final r1 = rowOf(well.position.y - reach).clamp(0, height - 1);
      for (var row = r0; row <= r1; row++) {
        for (var col = c0; col <= c1; col++) {
          final point = worldAt(col, row);
          final offset = point - well.position;
          final d = offset.length;
          if (d > reach) continue;
          final theta = math.atan2(offset.y, offset.x);
          final arm = math.sin(theta * 3 + d * 1.6);
          final fade = (1 - d / reach).clamp(0.0, 1.0);
          final k = (arm > 0.55 ? 0.3 : 0.0) * fade +
              _softBand(reach - d, 0.12, 0.1) * 0.25;
          if (k > 0) bitmap.blend(col, row, _Farm.turfShade, k);
        }
      }
    }

    // Rabbit holes: a ring of dug earth.
    for (final pair in hole.portals) {
      for (final end in [pair.a, pair.b]) {
        final reach = pair.radius * 1.6;
        final c0 = colOf(end.x - reach).clamp(0, width - 1);
        final c1 = colOf(end.x + reach).clamp(0, width - 1);
        final r0 = rowOf(end.y + reach).clamp(0, height - 1);
        final r1 = rowOf(end.y - reach).clamp(0, height - 1);
        for (var row = r0; row <= r1; row++) {
          for (var col = c0; col <= c1; col++) {
            final d = worldAt(col, row).distanceTo(end);
            final k = _softBand(d, pair.radius * 1.35, 0.18);
            if (k > 0) bitmap.blend(col, row, 0x8A6239, k * 0.85);
          }
        }
      }
    }

    // The nest: a soft ring of shade around the straw.
    final nest = hole.nest;
    final reach = nest.radius * 1.9;
    final c0 = colOf(nest.position.x - reach).clamp(0, width - 1);
    final c1 = colOf(nest.position.x + reach).clamp(0, width - 1);
    final r0 = rowOf(nest.position.y + reach).clamp(0, height - 1);
    final r1 = rowOf(nest.position.y - reach).clamp(0, height - 1);
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        final d = worldAt(col, row).distanceTo(nest.position);
        final k = _softBand(d, nest.radius * 1.35, nest.radius * 0.45);
        if (k > 0) bitmap.blend(col, row, _Farm.turfShade, k * 0.4);
      }
    }

    return bitmap.texture();
  }

  // ---- the table ----------------------------------------------------------------------

  /// The wooden table the green sits on: a timber rim around the turf and
  /// a planked skirt down to the meadow.
  tjs.Group table() {
    final bounds = hole.bounds;
    final group = tjs.Group()..name = 'table';
    const lip = _fenceThickness + 0.5;
    final w = bounds.width + lip * 2;
    final d = bounds.height + lip * 2;
    final skirtGrain = _woodGrainTexture()..repeat.setValues((w + d) / 6, 1);
    final skirt = tjs.Mesh(
      tjs.BoxGeometry(w, _tableHeight, d),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(_Farm.tableSide),
        tjs.MaterialProperty.map: skirtGrain,
        tjs.MaterialProperty.roughness: 0.85,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'table-skirt'
      ..position
          .setValues(bounds.center.x, -_tableHeight / 2 - 0.01, bounds.center.y)
      ..castShadow = true
      ..receiveShadow = true;
    final base = tjs.Mesh(
      tjs.BoxGeometry(w + 0.5, 0.35, d + 0.5),
      _matte(_Farm.tableBase, roughness: 0.9),
    )
      ..name = 'table-base'
      ..position
          .setValues(bounds.center.x, -_tableHeight + 0.17, bounds.center.y)
      ..castShadow = true
      ..receiveShadow = true;
    group
      ..add(skirt)
      ..add(base);
    // White posts at the corners and along the long sides: the course's
    // fence line, painted.
    final posts = _Merged();
    final corners = [
      Vec2(bounds.min.x, bounds.min.y),
      Vec2(bounds.max.x, bounds.min.y),
      Vec2(bounds.max.x, bounds.max.y),
      Vec2(bounds.min.x, bounds.max.y),
    ];
    final outward = _fenceThickness / 2;
    final spots = <Vec2>[];
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final length = a.distanceTo(b);
      final count = math.max(1, (length / 11).round());
      for (var k = 0; k < count; k++) {
        spots.add(a + (b - a) * (k / count));
      }
    }
    final center = bounds.center;
    for (final spot in spots) {
      final away = (spot - center);
      final push = Vec2(
        away.x.sign *
            (spot.x == bounds.min.x || spot.x == bounds.max.x ? outward : 0),
        away.y.sign *
            (spot.y == bounds.min.y || spot.y == bounds.max.y ? outward : 0),
      );
      final at = spot + push;
      posts.add(
        tjs.BoxGeometry(0.82, _railHeight + 0.42, 0.82),
        _place(at.x, (_railHeight + 0.42) / 2, at.y),
        _Farm.post,
        baseShade: 0.82,
      );
      posts.add(
        tjg.ConeGeometry(0.62, 0.42, 4),
        _place(at.x, _railHeight + 0.42 + 0.21, at.y, yaw: math.pi / 4),
        _Farm.barnRed,
      );
    }
    final postMesh = posts.mesh('table-posts');
    if (postMesh != null) group.add(postMesh);
    return group;
  }

  // ---- the rails ------------------------------------------------------------------------

  /// Whether [wall] runs along the green's edge (the outer fence).
  bool _isPerimeter(WallSegment wall) {
    final b = hole.bounds;
    bool onX(double x) =>
        (wall.a.x - x).abs() < 0.01 && (wall.b.x - x).abs() < 0.01;
    bool onY(double y) =>
        (wall.a.y - y).abs() < 0.01 && (wall.b.y - y).abs() < 0.01;
    return onX(b.min.x) || onX(b.max.x) || onY(b.min.y) || onY(b.max.y);
  }

  /// A timber rail along [a]-[b]: the outer fence stands just outside the
  /// green (its inner face on the physics' line), an inner wall stands
  /// centred and slim. Rails run long by their own thickness so corners
  /// close.
  tjs.Group rail(Vec2 a, Vec2 b) {
    final wall = WallSegment(a, b);
    final perimeter = _isPerimeter(wall);
    final thickness = perimeter ? _fenceThickness : _innerThickness;
    if (perimeter) {
      // The fence's colliders overrun the corners (so no egg slips past a
      // rounding); the timber stops at the green's edge.
      final bounds = hole.bounds;
      Vec2 clip(Vec2 p) => Vec2(p.x.clamp(bounds.min.x, bounds.max.x),
          p.y.clamp(bounds.min.y, bounds.max.y));
      a = clip(a);
      b = clip(b);
    }
    final run = b - a;
    final length = run.length;
    final direction = run.normalized(const Vec2(1, 0));
    var mid = (a + b) * 0.5;
    if (perimeter) {
      // Outward: away from the green's centre, across the run.
      final normal = Vec2(-direction.y, direction.x);
      final toCenter = hole.bounds.center - mid;
      final sign = normal.dot(toCenter) > 0 ? -1.0 : 1.0;
      mid = mid + normal * (sign * thickness / 2);
    }
    final group = tjs.Group()
      ..name = 'wall'
      // The rail runs a to b: long local x, turned by the run's angle (the
      // game's y-down angle reads a negative world turn about y).
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, 0, mid.y);
    final long = length + thickness;
    final body = tjs.Mesh(
      _woodBox(long, _railHeight, thickness),
      _railMaterial,
    )
      ..name = 'wall-body'
      ..position.y = _railHeight / 2
      ..castShadow = true
      ..receiveShadow = true;
    final cap = tjs.Mesh(
      _woodBox(long + 0.08, 0.1, thickness + 0.12),
      _capMaterial,
    )
      ..name = 'wall-cap'
      ..position.y = _railHeight + 0.05
      ..castShadow = true
      ..receiveShadow = true;
    group
      ..add(body)
      ..add(cap);
    return group;
  }

  /// A box whose UVs follow the timber: grain along its length at a fixed
  /// scale whatever the rail's size.
  tjs.BufferGeometry _woodBox(double length, double height, double depth) {
    final geometry = tjs.BoxGeometry(length, height, depth);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final normal = geometry.attributes['normal'] as tjs.BufferAttribute;
    final uv = geometry.attributes['uv'] as tjs.BufferAttribute;
    for (var i = 0; i < uv.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      final nx = normal.getX(i)!.toDouble().abs();
      final ny = normal.getY(i)!.toDouble().abs();
      double u;
      double v;
      if (nx > 0.5) {
        u = z / 2.4;
        v = y / 0.62;
      } else if (ny > 0.5) {
        u = x / 2.4;
        v = z / 0.62;
      } else {
        u = x / 2.4;
        v = y / 0.62;
      }
      uv.setXY(i, u, v);
    }
    uv.needsUpdate = true;
    return geometry;
  }

  /// A partial hedge arc as stepped rails; a full ring as a boulder; a
  /// bumper arc as a red rubber rail (or a pinball mushroom when full).
  tjs.Object3D arc(WallArc arc) {
    final full = arc.sweep >= 2 * math.pi - 0.01;
    if (arc.bumper) {
      return full ? _mushroomBumper(arc.center, arc.radius) : _bumperArc(arc);
    }
    if (full) return _boulder(arc.center, arc.radius);
    final group = tjs.Group()..name = 'arc';
    final steps = (arc.sweep * arc.radius / 1.0).ceil().clamp(2, 64).toInt();
    for (var i = 0; i < steps; i++) {
      final a0 = arc.startAngle + i / steps * arc.sweep;
      final a1 = arc.startAngle + (i + 1) / steps * arc.sweep;
      final a = Vec2(arc.center.x + math.cos(a0) * arc.radius,
          arc.center.y + math.sin(a0) * arc.radius);
      final b = Vec2(arc.center.x + math.cos(a1) * arc.radius,
          arc.center.y + math.sin(a1) * arc.radius);
      group.add(_innerRail(a, b));
    }
    return group;
  }

  /// A slim inner rail (no perimeter test: arcs never ride the edge).
  tjs.Group _innerRail(Vec2 a, Vec2 b) {
    final run = b - a;
    final length = run.length;
    final mid = (a + b) * 0.5;
    final group = tjs.Group()
      ..name = 'wall'
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, 0, mid.y);
    group
      ..add(tjs.Mesh(
          _woodBox(
              length + _innerThickness * 0.9, _railHeight, _innerThickness),
          _railMaterial)
        ..name = 'wall-body'
        ..position.y = _railHeight / 2
        ..castShadow = true
        ..receiveShadow = true)
      ..add(tjs.Mesh(
          _woodBox(length + _innerThickness, 0.1, _innerThickness + 0.12),
          _capMaterial)
        ..name = 'wall-cap'
        ..position.y = _railHeight + 0.05
        ..castShadow = true);
    return group;
  }

  // ---- bumpers ----------------------------------------------------------------------------

  /// A straight bumper: a red rubber rail with yolk-capped ends and a
  /// cream band - the pinball rail the egg bounces off.
  tjs.Group bumperRail(WallSegment wall) {
    final run = wall.b - wall.a;
    final length = run.length;
    final mid = (wall.a + wall.b) * 0.5;
    const height = 0.62;
    const thickness = 0.44;
    final group = tjs.Group()
      ..name = 'bumper'
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, 0, mid.y);
    final rubber =
        _matte(PuttPalette.comb.toARGB32() & 0xFFFFFF, roughness: 0.42);
    final body = tjs.Mesh(tjs.BoxGeometry(length, height, thickness), rubber)
      ..name = 'bumper-body'
      ..position.y = height / 2
      ..castShadow = true
      ..receiveShadow = true;
    final band = tjs.Mesh(
      tjs.BoxGeometry(length + 0.02, 0.14, thickness + 0.04),
      _matte(_Farm.trim, roughness: 0.5),
    )
      ..name = 'bumper-band'
      ..position.y = height * 0.55;
    group
      ..add(body)
      ..add(band);
    final yolk = _matte(_hexOf(PuttPalette.yolk), roughness: 0.4);
    for (final end in [-length / 2, length / 2]) {
      final cap = tjs.Mesh(
        tjg.CylinderGeometry(
            thickness * 0.62, thickness * 0.62, height + 0.12, 18),
        yolk,
      )
        ..name = 'bumper-ring'
        ..position.setValues(end, (height + 0.12) / 2, 0)
        ..castShadow = true;
      group.add(cap);
    }
    return group;
  }

  /// A bumper arc: stepped red rubber with yolk caps at its ends.
  tjs.Group _bumperArc(WallArc arc) {
    final group = tjs.Group()..name = 'bumper';
    final rubber = _matte(_hexOf(PuttPalette.comb), roughness: 0.42);
    const height = 0.62;
    final steps = (arc.sweep * arc.radius / 0.6).ceil().clamp(2, 64).toInt();
    for (var i = 0; i < steps; i++) {
      final a0 = arc.startAngle + i / steps * arc.sweep;
      final a1 = arc.startAngle + (i + 1) / steps * arc.sweep;
      final a = Vec2(arc.center.x + math.cos(a0) * arc.radius,
          arc.center.y + math.sin(a0) * arc.radius);
      final b = Vec2(arc.center.x + math.cos(a1) * arc.radius,
          arc.center.y + math.sin(a1) * arc.radius);
      final run = b - a;
      final mid = (a + b) * 0.5;
      group
          .add(tjs.Mesh(tjs.BoxGeometry(run.length + 0.2, height, 0.44), rubber)
            ..name = 'bumper-body'
            ..rotation.y = -math.atan2(run.y, run.x)
            ..position.setValues(mid.x, height / 2, mid.y)
            ..castShadow = true
            ..receiveShadow = true);
    }
    final yolk = _matte(_hexOf(PuttPalette.yolk), roughness: 0.4);
    for (final angle in [arc.startAngle, arc.startAngle + arc.sweep]) {
      final at = Vec2(arc.center.x + math.cos(angle) * arc.radius,
          arc.center.y + math.sin(angle) * arc.radius);
      group
          .add(tjs.Mesh(tjg.CylinderGeometry(0.3, 0.3, height + 0.12, 16), yolk)
            ..name = 'bumper-ring'
            ..position.setValues(at.x, (height + 0.12) / 2, at.y)
            ..castShadow = true);
    }
    return group;
  }

  /// A round pinball bumper: red rubber skirt, cream cap, a yolk ring.
  tjs.Group _mushroomBumper(Vec2 at, double radius) {
    final group = tjs.Group()
      ..name = 'bumper'
      ..position.setValues(at.x, 0, at.y);
    const height = 0.7;
    final body = tjs.Mesh(
      tjg.CylinderGeometry(radius * 0.98, radius, height, 32),
      _matte(_hexOf(PuttPalette.comb), roughness: 0.42),
    )
      ..name = 'bumper-body'
      ..position.y = height / 2
      ..castShadow = true
      ..receiveShadow = true;
    final cap = tjs.Mesh(
      tjg.CylinderGeometry(radius * 0.86, radius * 0.98, 0.22, 32),
      _matte(_Farm.trim, roughness: 0.5),
    )
      ..name = 'bumper-cap'
      ..position.y = height + 0.11
      ..castShadow = true;
    final ring = tjs.Mesh(
      tjg.TorusGeometry(radius * 0.55, 0.09, 8, 32),
      _matte(_hexOf(PuttPalette.yolk), roughness: 0.4),
    )
      ..name = 'bumper-ring'
      ..rotation.x = math.pi / 2
      ..position.y = height + 0.23;
    group
      ..add(body)
      ..add(cap)
      ..add(ring);
    return group;
  }

  // ---- boulders ---------------------------------------------------------------------------

  /// A boulder: a faceted stone sunk into the turf, moss on its crown.
  tjs.Mesh _boulder(Vec2 at, double radius) {
    final rand = _Rand(_seedOf('${hole.id}/${at.x}/${at.y}'));
    final geometry = tjg.IcosahedronGeometry(1, 1);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    // Jitter shared vertices identically: key them by their rounded spot.
    final offsets = <String, double>{};
    for (var i = 0; i < position.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      final key =
          '${(x * 1000).round()},${(y * 1000).round()},${(z * 1000).round()}';
      final k = offsets.putIfAbsent(key, () => rand.range(0.86, 1.1));
      position.setXYZ(i, x * k, y * k, z * k);
    }
    final merged = _Merged()
      ..add(
        geometry,
        _place(0, 0, 0,
            sx: radius * 1.02, sy: radius * 0.72, sz: radius * 1.02),
        _Farm.rock,
        baseShade: 0.62,
      );
    final mesh = merged.mesh('rock', flat: true)!;
    // Moss on the crown: lift the upward-facing faces toward green.
    final colors = mesh.geometry!.attributes['color'] as tjs.BufferAttribute;
    final normals = mesh.geometry!.attributes['normal'] as tjs.BufferAttribute;
    final moss = _lin(_Farm.moss);
    for (var i = 0; i < colors.count; i++) {
      final up = normals.getY(i)!.toDouble();
      if (up > 0.72) {
        final k = ((up - 0.72) / 0.28).clamp(0.0, 1.0) * 0.75;
        colors.setXYZ(
          i,
          colors.getX(i)! + (moss.red - colors.getX(i)!) * k,
          colors.getY(i)! + (moss.green - colors.getY(i)!) * k,
          colors.getZ(i)! + (moss.blue - colors.getZ(i)!) * k,
        );
      }
    }
    mesh.position.setValues(at.x, radius * 0.32, at.y);
    return mesh;
  }

  // ---- the silo ---------------------------------------------------------------------------

  /// The silo: a corrugated tank with a dome roof standing on the swallow
  /// zone, its dark intake ring at the turf, the reach drawn as a ring.
  tjs.Group silo(GravityWell well) {
    final group = tjs.Group()
      ..name = 'well'
      ..position.setValues(well.position.x, 0, well.position.y);
    final swallow = math.max(well.swallowRadius, 0.6);
    final tankRadius = math.max(swallow * 0.92, 0.55);
    final tankHeight = 3.2 + tankRadius * 1.1;

    final reach = tjs.Mesh(
      tjg.RingGeometry(well.radius - 0.12, well.radius, 72, 1),
      _unlit(_Farm.trim, opacity: 0.45, depthWrite: false),
    )
      ..name = 'well-reach'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.025;
    group.add(reach);

    final intake = tjs.Mesh(
      tjg.CylinderGeometry(tankRadius + 0.18, tankRadius + 0.26, 0.34, 40),
      _matte(0x2A221C, roughness: 0.9),
    )
      ..name = 'well-mouth'
      ..position.y = 0.17
      ..receiveShadow = true;
    group.add(intake);

    // The corrugated skin: alternating light and shade down the staves.
    final staves = 28;
    final tankGeometry = tjg.CylinderGeometry(
        tankRadius, tankRadius, tankHeight, staves, 6, false);
    final tank = _Merged()
      ..add(tankGeometry, _place(0, 0.34 + tankHeight / 2, 0), _Farm.silo,
          baseShade: 0.8);
    final tankMesh = tank.mesh('silo-tank', flat: true, roughness: 0.55)!;
    final colors =
        tankMesh.geometry!.attributes['color'] as tjs.BufferAttribute;
    final positions =
        tankMesh.geometry!.attributes['position'] as tjs.BufferAttribute;
    for (var i = 0; i < colors.count; i += 3) {
      // Per triangle: which stave it faces.
      final x = (positions.getX(i)! +
              positions.getX(i + 1)! +
              positions.getX(i + 2)!) /
          3;
      final z = (positions.getZ(i)! +
              positions.getZ(i + 1)! +
              positions.getZ(i + 2)!) /
          3;
      final stave =
          ((math.atan2(z, x) + math.pi) / (2 * math.pi) * staves).floor();
      if (stave.isOdd) {
        for (var k = 0; k < 3; k++) {
          colors.setXYZ(i + k, colors.getX(i + k)! * 0.86,
              colors.getY(i + k)! * 0.86, colors.getZ(i + k)! * 0.86);
        }
      }
    }
    group.add(tankMesh);

    final roof = tjs.Mesh(
      tjs.SphereGeometry(
          tankRadius * 1.04, 28, 12, 0, math.pi * 2, 0, math.pi / 2),
      _matte(_Farm.siloRoof, roughness: 0.4, metalness: 0.25),
    )
      ..name = 'silo-roof'
      ..scale.setValues(1, 0.62, 1)
      ..position.y = 0.34 + tankHeight
      ..castShadow = true;
    group.add(roof);
    final bands = tjs.Group()..name = 'silo-bands';
    for (final at in const [0.3, 0.62, 0.94]) {
      bands.add(tjs.Mesh(
        tjg.TorusGeometry(tankRadius + 0.03, 0.06, 6, 40),
        _matte(_Farm.metalDark, roughness: 0.5, metalness: 0.3),
      )
        ..name = 'silo-band'
        ..rotation.x = math.pi / 2
        ..position.y = 0.34 + tankHeight * at);
    }
    group.add(bands);
    // A comb-red cap on the roof's crown.
    group.add(tjs.Mesh(
      tjg.ConeGeometry(0.22, 0.4, 12),
      _matte(_Farm.barnRed),
    )
      ..name = 'silo-vent'
      ..position.y = 0.34 + tankHeight + tankRadius * 0.62 + 0.15);
    return group;
  }

  // ---- water --------------------------------------------------------------------------------

  /// A pond: a rippling sheet a hair over the turf (whose texture paints
  /// the shore and the bed), foam at its rim, lily pads on the big ones.
  tjs.Group water(WaterShape shape) {
    final group = tjs.Group()..name = 'water';
    final tjs.BufferGeometry geometry;
    final Vec2 center;
    switch (shape) {
      case WaterCircle(center: final c, :final radius):
        geometry = tjg.RingGeometry(0.0001, radius, 48, 10);
        center = c;
      case WaterRect(:final rect):
        geometry = _gridPlane(
            rect.width,
            rect.height,
            (rect.width / 0.8).ceil().clamp(2, 80).toInt(),
            (rect.height / 0.8).ceil().clamp(2, 80).toInt());
        center = rect.center;
      case WaterPolygon(:final points):
        geometry = _polygonGeometry(points, flatOnXY: true);
        center = _centroid(points);
    }
    // Per-vertex colour: foam at the rim, deeper toward the middle.
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final count = position.count;
    final colors = Float32List(count * 3);
    final rest = Float32List(count * 2);
    final deep = _lin(_Farm.waterDeep);
    final mid = _lin(_Farm.water);
    final foam = _lin(_Farm.waterFoam);
    for (var i = 0; i < count; i++) {
      final lx = position.getX(i)!.toDouble();
      final ly = position.getY(i)!.toDouble();
      rest[i * 2] = lx;
      rest[i * 2 + 1] = ly;
      // Local plane coords: +y is world -z.
      final world = Vec2(center.x + lx, center.y - ly);
      final inside = -_waterSignedDistance(shape, world);
      final depth = (inside / 2.4).clamp(0.0, 1.0);
      final foamK = _softBand(inside, 0.18, 0.16);
      var r = mid.red + (deep.red - mid.red) * depth;
      var g = mid.green + (deep.green - mid.green) * depth;
      var b = mid.blue + (deep.blue - mid.blue) * depth;
      r += (foam.red - r) * foamK;
      g += (foam.green - g) * foamK;
      b += (foam.blue - b) * foamK;
      colors[i * 3] = r;
      colors[i * 3 + 1] = g;
      colors[i * 3 + 2] = b;
    }
    geometry.setAttributeFromString(
        'color', tjs.Float32BufferAttribute(colors, 3, false));
    final material = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.vertexColors: true,
      tjs.MaterialProperty.roughness: 0.12,
      tjs.MaterialProperty.metalness: 0.0,
      tjs.MaterialProperty.transparent: true,
      tjs.MaterialProperty.opacity: 0.9,
    });
    final sheet = tjs.Mesh(geometry, material)
      ..name = 'water-sheet'
      ..rotation.x = -math.pi / 2
      ..position.setValues(center.x, 0.03, center.y)
      ..receiveShadow = true;
    group.add(sheet);

    // The ripple: gentle crossing waves, normals refreshed so the sun's
    // glints dance.
    final phase = _rand.range(0, 6.28);
    var lastUpdate = -1.0;
    animated.add(_AnimatedBy((time, dt) {
      // Thirty updates a second is plenty for water.
      if ((time - lastUpdate).abs() < 1 / 30) return;
      lastUpdate = time;
      for (var i = 0; i < count; i++) {
        final x = rest[i * 2];
        final y = rest[i * 2 + 1];
        final rim =
            (-_waterSignedDistance(shape, Vec2(center.x + x, center.y - y)))
                .clamp(0.0, 1.0);
        final wave = (math.sin(x * 1.3 + time * 1.7 + phase) +
                math.sin(y * 1.7 - time * 1.3 + phase * 0.7) * 0.8 +
                math.sin((x + y) * 2.9 + time * 2.6) * 0.35) *
            0.035 *
            rim;
        position.setXYZ(i, x, y, wave);
      }
      position.needsUpdate = true;
      geometry.computeVertexNormals();
    }));

    // Lily pads on the bigger ponds.
    final box = _waterBox(shape);
    final area = box.width * box.height;
    final pads = (area / 22).floor().clamp(0, 6).toInt();
    if (pads > 0) {
      final lilies = _Merged();
      var placed = 0;
      for (var attempt = 0; attempt < 40 && placed < pads; attempt++) {
        final spot = Vec2(_rand.range(box.min.x, box.max.x),
            _rand.range(box.min.y, box.max.y));
        if (-_waterSignedDistance(shape, spot) < 0.9) continue;
        final size = _rand.range(0.35, 0.6);
        lilies.add(
          tjg.CircleGeometry(
              radius: 1,
              segments: 14,
              thetaStart: 0.4,
              thetaLength: math.pi * 2 - 0.8),
          _place(spot.x, 0.07, spot.y,
              yaw: _rand.range(0, 6.28),
              tilt: -math.pi / 2,
              sx: size,
              sy: size,
              sz: size),
          _Farm.lily,
          rand: _rand,
          variation: 0.12,
        );
        if (_rand.chance(0.45)) {
          lilies.add(
            tjg.IcosahedronGeometry(0.14, 0),
            _place(spot.x + 0.1, 0.16, spot.y, sy: 0.6),
            _Farm.flowerPink,
          );
        }
        placed++;
      }
      final lilyMesh = lilies.mesh('water-lilies', castShadow: false);
      if (lilyMesh != null) group.add(lilyMesh);
    }
    return group;
  }

  // ---- speed belts --------------------------------------------------------------------------

  /// A boost strip: a dark belt in a timber frame, yolk chevrons running
  /// along it the way it throws.
  tjs.Group boost(BoostStrip strip) {
    final run = strip.to - strip.from;
    final length = run.length;
    final mid = (strip.from + strip.to) * 0.5;
    final group = tjs.Group()
      ..name = 'boost'
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, 0, mid.y);
    final frame = tjs.Mesh(
      tjs.BoxGeometry(length + 0.3, 0.06, strip.width + 0.3),
      _timber,
    )
      ..name = 'boost-frame'
      ..position.y = 0.03
      ..receiveShadow = true;
    final chevrons = _chevronTexture()
      ..repeat
          .setValues(math.max(1, (length / strip.width).roundToDouble()), 1);
    final belt = tjs.Mesh(
      tjs.PlaneGeometry(length, strip.width),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: chevrons,
        tjs.MaterialProperty.roughness: 0.6,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.emissive: _lin(0x3A2A06),
      }),
    )
      ..name = 'boost-belt'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.065
      ..receiveShadow = true;
    group
      ..add(frame)
      ..add(belt);
    animated.add(_AnimatedBy((time, dt) {
      chevrons.offset.x = -(time * 1.6) % 1.0;
    }));
    return group;
  }

  /// Yolk chevrons on a dark belt, pointing +u.
  tjs.DataTexture _chevronTexture() {
    final bitmap = _Bitmap(64, 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final v = (y - 31.5).abs() / 32; // 0 at the middle line
        final u = x / 64;
        // A chevron pointing +u: its arms trail back as |v| grows.
        final shape = ((u + v * 0.45) % 1.0 + 1) % 1.0;
        final inside = shape > 0.22 && shape < 0.52;
        final edge = (shape - 0.22).abs() < 0.03 || (shape - 0.52).abs() < 0.03;
        var color = 0x3B3530;
        if (inside) color = edge ? 0xE88A10 : 0xF8B23A;
        if (y < 3 || y > 60) color = 0xF0D9A8;
        bitmap.set(x, y, color);
      }
    }
    return bitmap.texture(repeat: true);
  }

  // ---- rabbit holes ---------------------------------------------------------------------------

  /// A rabbit hole: the burrow's dark mouth in a ring of dug earth, its
  /// rim glowing the pair's colour (both ends of a pair share it).
  tjs.Group portal(Vec2 at, double radius,
      {required int pairIndex, required double phase}) {
    const pairColors = [0xF89B17, 0x52C7E8, 0xF07AA0, 0xFFF4DE];
    final tint = pairColors[pairIndex % pairColors.length];
    final group = tjs.Group()
      ..name = 'portal'
      ..position.setValues(at.x, 0, at.y);
    final mound = tjs.Mesh(
      tjg.TorusGeometry(radius * 1.08, radius * 0.22, 8, 28),
      _matte(0x7A532E, roughness: 0.95, flat: true),
    )
      ..name = 'portal-mound'
      ..rotation.x = math.pi / 2
      ..scale.setValues(1, 1, 0.55)
      ..castShadow = true
      ..receiveShadow = true;
    final burrow = tjs.Mesh(
      tjg.CircleGeometry(radius: radius, segments: 32),
      _unlit(0x120C08),
    )
      ..name = 'portal-hole'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03;
    final glow = tjs.Mesh(
      tjg.TorusGeometry(radius * 0.92, 0.07, 8, 40),
      _unlit(tint, opacity: 0.85, depthWrite: false),
    )
      ..name = 'portal-glow'
      ..rotation.x = math.pi / 2
      ..position.y = 0.09;
    final swirl = tjs.Mesh(
      tjg.RingGeometry(radius * 0.3, radius * 0.62, 24, 1, 0, math.pi * 1.2),
      _unlit(tint, opacity: 0.35, depthWrite: false),
    )
      ..name = 'portal-swirl'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.04;
    group
      ..add(mound)
      ..add(burrow)
      ..add(swirl)
      ..add(glow);
    animated.add(_AnimatedBy((time, dt) {
      final pulse = 0.5 + 0.5 * math.sin((time - phase) * 3.1);
      glow.material?.opacity = 0.55 + 0.4 * pulse;
      glow.scale.setValues(1 + pulse * 0.06, 1 + pulse * 0.06, 1);
      swirl.rotation.z = time * 2.2 + phase;
    }));
    return group;
  }

  // ---- crates ---------------------------------------------------------------------------------

  /// The "?" crates' face: a yolk carton side with a cream question mark
  /// in the brand's display face, ink-edged. One per hole, shared.
  tjs.DataTexture crateTexture() {
    return _crateFace ??=
        _paintedTexture(128, 128, _hexOf(PuttPalette.yolk), (canvas, size) {
      final edge = ui.Paint()
        ..color = const ui.Color(0xFFD9780C)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 10;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(5, 5, size.width - 10, size.height - 10),
          const ui.Radius.circular(18),
        ),
        edge,
      );
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontFamily: 'Sora',
        fontSize: 92,
        fontWeight: ui.FontWeight.w800,
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFF8EE),
          fontFamily: 'Sora',
          fontWeight: ui.FontWeight.w800,
          shadows: const [
            ui.Shadow(color: ui.Color(0xFF8C4A06), offset: ui.Offset(0, 5)),
          ],
        ))
        // Not translated: the crate's glyph is a symbol, not a word.
        ..addText('?');
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(
          paragraph, ui.Offset(0, (size.height - paragraph.height) / 2 - 4));
    });
  }

  // ---- the nest and its flag --------------------------------------------------------------------

  /// The nest: a woven straw ring around a dark cup, and the flag on its
  /// far rim flying the hole's number.
  tjs.Group nest({String? label}) {
    final nest = hole.nest;
    final group = tjs.Group()
      ..name = 'nest'
      ..position.setValues(nest.position.x, 0, nest.position.y);
    final r = nest.radius;
    final cup = tjs.Mesh(
      tjg.CircleGeometry(radius: r * 0.8, segments: 40),
      _unlit(_Farm.cup),
    )
      ..name = 'nest-cup'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.012;
    final rim = tjs.Mesh(
      tjg.RingGeometry(r * 0.5, r * 0.8, 40, 1),
      _unlit(0x3A2A1C),
    )
      ..name = 'nest-rim'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.016;
    group
      ..add(cup)
      ..add(rim);

    // The straw: a lumpy torus in mixed straw tones, and strands poking
    // out of it every which way.
    final straw = _Merged();
    final torus = tjg.TorusGeometry(r * 1.0, r * 0.24, 10, 44);
    final position = torus.attributes['position'] as tjs.BufferAttribute;
    for (var i = 0; i < position.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      final k =
          1 + (_hash2((x * 40).round(), (y * 40).round(), 5) - 0.5) * 0.16;
      position.setXYZ(i, x * k, y * k, z * k);
    }
    straw.add(
        torus, _place(0, r * 0.12, 0, tilt: math.pi / 2, sz: 0.55), _Farm.straw,
        baseShade: 0.7);
    for (var i = 0; i < 34; i++) {
      final angle = i / 34 * math.pi * 2 + _rand.range(-0.1, 0.1);
      final radial = r * _rand.range(0.88, 1.18);
      final length = _rand.range(0.45, 0.85) * r;
      straw.add(
        tjs.BoxGeometry(length, 0.035, 0.07),
        _place(
          math.cos(angle) * radial,
          r * 0.16 + _rand.range(0, 0.12),
          math.sin(angle) * radial,
          yaw: -angle + _rand.range(0.5, 1.2) * (i.isEven ? 1 : -1),
          tilt: _rand.range(-0.3, 0.3),
          roll: _rand.range(-0.35, 0.35),
        ),
        i % 3 == 0
            ? _Farm.strawDark
            : (i % 3 == 1 ? _Farm.strawLight : _Farm.straw),
      );
    }
    group.add(straw.mesh('nest-straw', flat: true)!);

    // The flag on the far rim (away from the tee), facing the camera.
    final away = (nest.position - hole.tee).normalized(const Vec2(1, 0));
    final poleAt = away * (r * 1.02);
    const poleHeight = 3.6;
    final pole = tjs.Group()
      ..name = 'nest-flag'
      ..position.setValues(poleAt.x, 0, poleAt.y);
    final poleMerged = _Merged();
    for (var i = 0; i < 6; i++) {
      poleMerged.add(
        tjg.CylinderGeometry(0.07, 0.07, poleHeight / 6, 10),
        _place(0, poleHeight / 6 * (i + 0.5), 0),
        i.isEven ? _Farm.trim : _Farm.barnRed,
      );
    }
    poleMerged.add(tjs.SphereGeometry(0.13, 12, 8),
        _place(0, poleHeight + 0.06, 0), _hexOf(PuttPalette.yolk));
    pole.add(poleMerged.mesh('flag-pole', flat: false, roughness: 0.5)!);

    final flagTexture =
        _paintedTexture(160, 112, _Farm.barnRed, (canvas, size) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontFamily: 'Sora',
        fontSize: 78,
        fontWeight: ui.FontWeight.w800,
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFF4E4),
          fontFamily: 'Sora',
          fontWeight: ui.FontWeight.w800,
        ))
        // Not translated: the hole's number, digits only.
        ..addText(label ?? '');
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: size.width - 20));
      canvas.drawParagraph(
          paragraph, ui.Offset(4, (size.height - paragraph.height) / 2));
    });
    const flagWidth = 1.5;
    const flagHeight = 1.05;
    final cloth = _gridPlane(flagWidth, flagHeight, 12, 4)
      ..translate(flagWidth / 2 + 0.06, poleHeight - flagHeight / 2 - 0.08, 0);
    final flag = tjs.Mesh(
      cloth,
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: flagTexture,
        tjs.MaterialProperty.roughness: 0.85,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.side: tjs.DoubleSide,
      }),
    )
      ..name = 'flag-cloth'
      ..castShadow = true;
    pole.add(flag);
    group.add(pole);

    final clothPosition = cloth.attributes['position'] as tjs.BufferAttribute;
    final rest = Float32List(clothPosition.count * 3);
    for (var i = 0; i < clothPosition.count; i++) {
      rest[i * 3] = clothPosition.getX(i)!.toDouble();
      rest[i * 3 + 1] = clothPosition.getY(i)!.toDouble();
      rest[i * 3 + 2] = clothPosition.getZ(i)!.toDouble();
    }
    animated.add(_AnimatedBy((time, dt) {
      // The number always reads: the flag swings its face to the camera.
      pole.rotation.y = rig.yaw + math.pi;
      for (var i = 0; i < clothPosition.count; i++) {
        final x = rest[i * 3];
        final y = rest[i * 3 + 1];
        final reach = ((x - 0.06) / flagWidth).clamp(0.0, 1.0);
        final wave = math.sin(x * 3.2 - time * 5.2 + y * 0.6) * 0.16 * reach;
        clothPosition.setXYZ(
            i, x - reach * reach * 0.05, y - reach * 0.06, wave);
      }
      clothPosition.needsUpdate = true;
      cloth.computeVertexNormals();
    }));
    return group;
  }

  // ---- the tee ----------------------------------------------------------------------------------

  /// The tee: a rubber mat with a cream dashed ring where the eggs start.
  tjs.Group tee() {
    final at = hole.tee;
    final group = tjs.Group()
      ..name = 'tee'
      ..position.setValues(at.x, 0, at.y);
    final mat = tjs.Mesh(
      tjg.CylinderGeometry(1.25, 1.3, 0.06, 40),
      _matte(0x2E6B3C, roughness: 0.9),
    )
      ..name = 'tee-mat'
      ..position.y = 0.03
      ..receiveShadow = true;
    group.add(mat);
    final dashes = _Merged();
    for (var i = 0; i < 14; i++) {
      final angle = i / 14 * math.pi * 2;
      dashes.add(
        tjs.BoxGeometry(0.34, 0.02, 0.1),
        _place(math.cos(angle) * 1.0, 0.07, math.sin(angle) * 1.0,
            yaw: -angle + math.pi / 2),
        _Farm.trim,
      );
    }
    dashes.add(tjg.CylinderGeometry(0.16, 0.16, 0.02, 16), _place(0, 0.07, 0),
        _Farm.trim);
    group.add(dashes.mesh('tee-dashes', castShadow: false, flat: false)!);
    return group;
  }

  // ---- garden beds -------------------------------------------------------------------------------

  /// The walled-off ground planted in the theme's way: flower beds by the
  /// coop, corn in the maze, reeds by the pond, wheat along the road,
  /// straw at the barn. Plants keep clear of the rails. Null when the whole
  /// green is in play.
  tjs.Object3D? garden() {
    if (_reach.unreachableCount == 0) return null;
    final merged = _Merged();
    final rand = _Rand(_seedOf('${hole.id}/garden'));
    final walls = [
      for (final wall in hole.walls) (wall.a, wall.b),
    ];
    bool nearRail(Vec2 p) {
      for (final (a, b) in walls) {
        if (_segmentDistance(p, a, b) < 0.75) return true;
      }
      for (final arc in hole.arcs) {
        if (_arcDistance(p, arc) < 0.75) return true;
      }
      return false;
    }

    final bounds = hole.bounds;
    const step = 1.15;
    for (var y = bounds.min.y + 0.6; y < bounds.max.y - 0.4; y += step) {
      for (var x = bounds.min.x + 0.6; x < bounds.max.x - 0.4; x += step) {
        final p = Vec2(x + rand.range(-0.4, 0.4), y + rand.range(-0.4, 0.4));
        if (_reach.reachableAt(p) || nearRail(p)) continue;
        _gardenPlant(merged, p, rand);
      }
    }
    final mesh = merged.mesh('garden-plants', flat: true);
    if (mesh == null) return null;
    return tjs.Group()
      ..name = 'garden'
      ..add(mesh);
  }

  void _gardenPlant(_Merged into, Vec2 p, _Rand rand) {
    switch (theme.kind) {
      case _ThemeKind.maze:
        final h = rand.range(1.0, 1.5);
        into.add(tjg.CylinderGeometry(0.04, 0.06, h, 5),
            _place(p.x, h / 2, p.y), 0x6E9F3A,
            baseShade: 0.7);
        for (var leaf = 0; leaf < 3; leaf++) {
          final yaw = rand.range(0, math.pi * 2);
          into.add(
              tjs.BoxGeometry(0.7, 0.03, 0.13),
              _place(p.x + math.cos(yaw) * 0.3, h * (0.35 + leaf * 0.2),
                  p.y - math.sin(yaw) * 0.3,
                  yaw: yaw, roll: -0.5),
              leaf.isEven ? 0x5E9A35 : 0x79B145);
        }
        if (rand.chance(0.6)) {
          into.add(tjg.CylinderGeometry(0.08, 0.1, 0.36, 6),
              _place(p.x + 0.1, h * 0.6, p.y, roll: 0.35), 0xF2C845);
        }
        into.add(tjg.ConeGeometry(0.12, 0.36, 4), _place(p.x, h + 0.15, p.y),
            0xD9B76A);
      case _ThemeKind.pond:
        if (rand.chance(0.55)) {
          for (var reed = 0; reed < 4; reed++) {
            final h = rand.range(0.7, 1.3);
            final x = p.x + rand.range(-0.3, 0.3);
            final z = p.y + rand.range(-0.3, 0.3);
            into.add(tjg.CylinderGeometry(0.03, 0.045, h, 4),
                _place(x, h / 2, z, tilt: rand.range(-0.15, 0.15)), 0x4F8A33);
            if (rand.chance(0.4)) {
              into.add(tjg.CylinderGeometry(0.07, 0.07, 0.3, 6),
                  _place(x, h - 0.05, z), 0x6B4428);
            }
          }
        } else {
          into.add(tjg.IcosahedronGeometry(1, 1),
              _place(p.x, 0.3, p.y, sx: 0.55, sy: 0.42, sz: 0.55), 0x4E9C3A,
              baseShade: 0.6, rand: rand, variation: 0.1);
        }
      case _ThemeKind.road:
        for (var tuft = 0; tuft < 5; tuft++) {
          final h = rand.range(0.5, 0.85);
          into.add(
              tjg.ConeGeometry(0.07, h, 3),
              _place(p.x + rand.range(-0.35, 0.35), h / 2,
                  p.y + rand.range(-0.35, 0.35),
                  tilt: rand.range(-0.25, 0.25)),
              rand.chance(0.6) ? 0xE2BE5A : 0xC99B45,
              baseShade: 0.75);
        }
      case _ThemeKind.barn:
        if (rand.chance(0.3)) {
          into.add(tjs.BoxGeometry(0.9, 0.5, 0.6),
              _place(p.x, 0.25, p.y, yaw: rand.range(0, math.pi)), _Farm.hay,
              baseShade: 0.75);
        } else {
          for (var tuft = 0; tuft < 4; tuft++) {
            into.add(
                tjs.BoxGeometry(0.5, 0.03, 0.06),
                _place(p.x + rand.range(-0.4, 0.4), 0.05,
                    p.y + rand.range(-0.4, 0.4),
                    yaw: rand.range(0, math.pi * 2)),
                rand.chance(0.5) ? _Farm.strawLight : _Farm.straw);
          }
        }
      case _ThemeKind.coop:
        if (rand.chance(0.45)) {
          into.add(
              tjg.IcosahedronGeometry(1, 1),
              _place(p.x, 0.32, p.y, sx: 0.5, sy: 0.42, sz: 0.5),
              rand.chance(0.5) ? _Farm.leafB : _Farm.leafA,
              baseShade: 0.6,
              rand: rand,
              variation: 0.1);
        } else {
          const heads = [
            _Farm.flowerRed,
            _Farm.flowerYolk,
            _Farm.flowerCream,
            _Farm.flowerPink,
          ];
          final head = heads[rand.below(heads.length)];
          for (var f = 0; f < 4; f++) {
            final x = p.x + rand.range(-0.35, 0.35);
            final z = p.y + rand.range(-0.35, 0.35);
            final h = rand.range(0.25, 0.42);
            into.add(tjs.BoxGeometry(0.035, h, 0.035), _place(x, h / 2, z),
                _Farm.leafC);
            into.add(tjg.IcosahedronGeometry(rand.range(0.09, 0.13), 0),
                _place(x, h, z, sy: 0.6), head);
          }
        }
    }
  }

  // ---- decorations -------------------------------------------------------------------------------

  tjs.Object3D? decoration(Decoration decoration) {
    switch (decoration.kind) {
      case 'hay':
      case 'hay_bale':
        return _hayBale(decoration.at, decoration.numbers['size'] ?? 1.0);
      case 'fence':
        return _fence(decoration);
      case 'tee_marker':
        // The tee mat already marks the start.
        return null;
      default:
        // Unknown tags rest as a pebble, so nothing smuggles in unseen.
        return _boulder(decoration.at, 0.25);
    }
  }

  /// A round hay bale lying on the turf, twine bands around it.
  tjs.Group _hayBale(Vec2 at, double scale) {
    final group = tjs.Group()
      ..name = 'hay-bale'
      ..position.setValues(at.x, 0, at.y);
    final merged = _Merged();
    final radius = 0.85 * scale;
    final length = 1.5 * scale;
    merged.add(tjg.CylinderGeometry(radius, radius, length, 20, 3),
        _place(0, radius, 0, roll: math.pi / 2), _Farm.hay,
        baseShade: 0.75);
    for (final side in [-1.0, 1.0]) {
      merged.add(
          tjg.CircleGeometry(radius: radius * 0.92, segments: 20),
          _place(side * (length / 2 + 0.005), radius, 0,
              yaw: side * math.pi / 2),
          _Farm.hayDark);
    }
    for (final band in [-0.28, 0.28]) {
      merged.add(tjg.TorusGeometry(radius + 0.01, 0.035, 5, 24),
          _place(band * length, radius, 0, yaw: math.pi / 2), _Farm.strawDark);
    }
    group.add(merged.mesh('hay-roll', flat: false)!);
    return group;
  }

  /// A white picket fence line marching +x from the decoration's spot.
  tjs.Group _fence(Decoration decoration) {
    final posts = (decoration.numbers['posts'] ?? 5).round();
    final spacing = decoration.numbers['length'] ?? 1.4;
    final at = decoration.at;
    final group = tjs.Group()
      ..name = 'fence'
      ..position.setValues(at.x, 0, at.y);
    final merged = _Merged();
    for (final railHeight in const [0.62, 0.3]) {
      merged.add(
        tjs.BoxGeometry((posts - 1) * spacing, 0.08, 0.06),
        _place((posts - 1) * spacing / 2, railHeight, 0),
        _Farm.trim,
      );
    }
    for (var i = 0; i < posts; i++) {
      merged.add(tjs.BoxGeometry(0.14, 0.86, 0.1), _place(i * spacing, 0.43, 0),
          _Farm.trim,
          baseShade: 0.8);
      merged.add(tjg.ConeGeometry(0.1, 0.16, 4),
          _place(i * spacing, 0.94, 0, yaw: math.pi / 4), _Farm.trim);
    }
    group.add(merged.mesh('fence-pickets', flat: true)!);
    return group;
  }
}

// ---- shape helpers -------------------------------------------------------------------------

/// The distance from [p] to a partial arc's curve (its ends included).
double _arcDistance(Vec2 p, WallArc arc) {
  final offset = p - arc.center;
  var angle = math.atan2(offset.y, offset.x) - arc.startAngle;
  angle = ((angle % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
  if (angle <= arc.sweep) {
    return (offset.length - arc.radius).abs();
  }
  final start = Vec2(arc.center.x + math.cos(arc.startAngle) * arc.radius,
      arc.center.y + math.sin(arc.startAngle) * arc.radius);
  final end = Vec2(
      arc.center.x + math.cos(arc.startAngle + arc.sweep) * arc.radius,
      arc.center.y + math.sin(arc.startAngle + arc.sweep) * arc.radius);
  return math.min(p.distanceTo(start), p.distanceTo(end));
}

/// A water shape's bounding box.
Rect _waterBox(WaterShape shape) {
  switch (shape) {
    case WaterCircle(:final center, :final radius):
      return Rect(center - Vec2(radius, radius), center + Vec2(radius, radius));
    case WaterRect(:final rect):
      return rect;
    case WaterPolygon(:final points):
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      for (final p in points) {
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
      if (points.isEmpty) return Rect(Vec2.zero, Vec2.zero);
      return Rect(Vec2(minX, minY), Vec2(maxX, maxY));
  }
}

/// Signed distance to a water shape's edge: negative inside.
double _waterSignedDistance(WaterShape shape, Vec2 p) {
  switch (shape) {
    case WaterCircle(:final center, :final radius):
      return p.distanceTo(center) - radius;
    case WaterRect(:final rect):
      final dx = math.max(rect.min.x - p.x, p.x - rect.max.x);
      final dy = math.max(rect.min.y - p.y, p.y - rect.max.y);
      if (dx <= 0 && dy <= 0) return math.max(dx, dy);
      return math
          .sqrt(math.pow(math.max(dx, 0), 2) + math.pow(math.max(dy, 0), 2));
    case WaterPolygon(:final points):
      if (points.length < 3) return 99;
      var best = double.infinity;
      for (var i = 0; i < points.length; i++) {
        best = math.min(best,
            _segmentDistance(p, points[i], points[(i + 1) % points.length]));
      }
      return shape.contains(p) ? -best : best;
  }
}

/// A flat polygon as a triangle fan around [points]' centroid; with
/// [flatOnXY] it lies in its own XY plane (centred on the centroid) like
/// the plane geometries, else on the ground plane in world z.
tjs.BufferGeometry _polygonGeometry(List<Vec2> points,
    {bool flatOnXY = false}) {
  if (points.length < 3) return tjs.BufferGeometry();
  final center = _centroid(points);
  final positions = <double>[];
  final normals = <double>[];
  for (var i = 0; i < points.length; i++) {
    final p0 = points[i];
    final p1 = points[(i + 1) % points.length];
    if (flatOnXY) {
      // Local +y is world -z: flip the game's y.
      positions.addAll([0, 0, 0]);
      positions.addAll([p0.x - center.x, center.y - p0.y, 0]);
      positions.addAll([p1.x - center.x, center.y - p1.y, 0]);
      normals.addAll([0, 0, 1, 0, 0, 1, 0, 0, 1]);
    } else {
      positions.addAll([center.x, 0, center.y]);
      positions.addAll([p0.x, 0, p0.y]);
      positions.addAll([p1.x, 0, p1.y]);
      normals.addAll([0, 1, 0, 0, 1, 0, 0, 1, 0]);
    }
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

// ---- reachability ----------------------------------------------------------------------------

/// Where an egg can roll from the tee: a flood fill over a half-unit grid
/// of the bounds, stopped wherever a wall (straight, or a partial arc as
/// its chords) crosses the step between two cells, and carried through the
/// rabbit holes (an egg reaching one end comes out of the other). Water
/// does not stop it - an island is still turf - and neither do rocks or
/// bumpers standing free.
class _ReachGrid {
  _ReachGrid._(this.bounds, this.cols, this.rows, this._reachable);

  static const double cell = 0.5;

  final Rect bounds;
  final int cols;
  final int rows;
  final Uint8List _reachable;

  /// How many cells the flood never reached.
  int get unreachableCount =>
      _reachable.length - _reachable.fold<int>(0, (sum, v) => sum + v);

  bool reachableAt(Vec2 p) {
    final col = ((p.x - bounds.min.x) / cell).floor().clamp(0, cols - 1);
    final row = ((p.y - bounds.min.y) / cell).floor().clamp(0, rows - 1);
    return _reachable[row * cols + col] == 1;
  }

  static _ReachGrid of(HoleDef hole) {
    final bounds = hole.bounds;
    final cols = math.max(1, (bounds.width / cell).ceil());
    final rows = math.max(1, (bounds.height / cell).ceil());
    final reachable = Uint8List(cols * rows);
    final segments = <(Vec2, Vec2)>[
      for (final wall in hole.walls) (wall.a, wall.b),
    ];
    for (final arc in hole.arcs) {
      if (arc.sweep >= 2 * math.pi - 0.01) continue; // a free-standing rock
      final steps = (arc.sweep * arc.radius / 0.5).ceil().clamp(2, 128).toInt();
      for (var i = 0; i < steps; i++) {
        final a0 = arc.startAngle + i / steps * arc.sweep;
        final a1 = arc.startAngle + (i + 1) / steps * arc.sweep;
        segments.add((
          Vec2(arc.center.x + math.cos(a0) * arc.radius,
              arc.center.y + math.sin(a0) * arc.radius),
          Vec2(arc.center.x + math.cos(a1) * arc.radius,
              arc.center.y + math.sin(a1) * arc.radius),
        ));
      }
    }
    Vec2 centerOf(int col, int row) => Vec2(
        bounds.min.x + (col + 0.5) * cell, bounds.min.y + (row + 0.5) * cell);
    int? cellOf(Vec2 p) {
      final col = ((p.x - bounds.min.x) / cell).floor();
      final row = ((p.y - bounds.min.y) / cell).floor();
      if (col < 0 || row < 0 || col >= cols || row >= rows) return null;
      return row * cols + col;
    }

    bool crossesWall(Vec2 a, Vec2 b) {
      for (final (p, q) in segments) {
        if (_segmentsCross(a, b, p, q)) return true;
      }
      return false;
    }

    final queue = <int>[];
    void seed(Vec2 p) {
      final index = cellOf(p);
      if (index == null || reachable[index] == 1) return;
      reachable[index] = 1;
      queue.add(index);
    }

    seed(hole.tee);
    var head = 0;
    while (head < queue.length) {
      final index = queue[head++];
      final col = index % cols;
      final row = index ~/ cols;
      final here = centerOf(col, row);
      // Through a rabbit hole: reaching one end opens the other.
      for (final pair in hole.portals) {
        if (here.distanceTo(pair.a) <= pair.radius) seed(pair.b);
        if (here.distanceTo(pair.b) <= pair.radius) seed(pair.a);
      }
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nc = col + dc;
        final nr = row + dr;
        if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
        final next = nr * cols + nc;
        if (reachable[next] == 1) continue;
        if (crossesWall(here, centerOf(nc, nr))) continue;
        reachable[next] = 1;
        queue.add(next);
      }
    }
    return _ReachGrid._(bounds, cols, rows, reachable);
  }
}

/// Whether segments [a]-[b] and [p]-[q] touch or cross.
bool _segmentsCross(Vec2 a, Vec2 b, Vec2 p, Vec2 q) {
  double orient(Vec2 o, Vec2 u, Vec2 v) =>
      (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x);
  bool onSegment(Vec2 o, Vec2 u, Vec2 v) =>
      math.min(o.x, u.x) - 1e-9 <= v.x &&
      v.x <= math.max(o.x, u.x) + 1e-9 &&
      math.min(o.y, u.y) - 1e-9 <= v.y &&
      v.y <= math.max(o.y, u.y) + 1e-9;
  final d1 = orient(p, q, a);
  final d2 = orient(p, q, b);
  final d3 = orient(a, b, p);
  final d4 = orient(a, b, q);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  if (d1.abs() < 1e-12 && onSegment(p, q, a)) return true;
  if (d2.abs() < 1e-12 && onSegment(p, q, b)) return true;
  if (d3.abs() < 1e-12 && onSegment(a, b, p)) return true;
  if (d4.abs() < 1e-12 && onSegment(a, b, q)) return true;
  return false;
}
