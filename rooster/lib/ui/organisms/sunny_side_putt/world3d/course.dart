// The course itself: the mown turf (one texture carrying stripes, the
// rails' contact shadows, the shores, the silo's spiral and the nest's
// shade), the wooden table it sits on, timber rails (the outer fence set
// outside the green so its face is where the physics' line is), rubber
// bumpers, boulders, ponds that ripple, speed belts whose chevrons run,
// rabbit holes, the silo, the "?" crates' face, the straw nest with its
// flag, the tee mat and the sign beside it with the hole's number.
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

/// The lawn's paint and what it reads: the kit's, and the same off the UI
/// isolate in a [_TurfJob] (pure Dart, no GPU objects).
mixin _LawnPaint {
  HoleDef get hole;
  _Theme get theme;
  _TableShape get shape;
  _TableShape get _reach => shape;

  /// The garden beds' ground per theme: mulch, dark earth, moss, gravel,
  /// straw.
  int get _gardenGround => switch (theme.kind) {
        _ThemeKind.coop => 0x7A5233,
        _ThemeKind.maze => 0x6A4A2C,
        _ThemeKind.pond => 0x5C8A3C,
        _ThemeKind.road => 0xB9A27E,
        _ThemeKind.barn => 0xC9A55A,
      };

  /// The lawn's texture: mown stripes across the tee-to-nest line, a
  /// darker fringe at the edge, contact shade along every rail, rock and
  /// bumper, sandy shores around the ponds (their beds darker), the
  /// silo's spiral pull, the rabbit holes' dug earth and the nest's ring
  /// of shade.
  _Bitmap _lawnBitmap() {
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
      final box = Rect(
        Vec2(math.min(wall.a.x, wall.b.x), math.min(wall.a.y, wall.b.y)),
        Vec2(math.max(wall.a.x, wall.b.x), math.max(wall.a.y, wall.b.y)),
      );
      if (wall.ledge) {
        // A ledge shades only its foot, below it; its lip is the tiers'.
        final high = wall.highSide;
        stampDistance(
            box,
            (p) => (p - wall.a).dot(high) < 0
                ? _segmentDistance(p, wall.a, wall.b)
                : 99);
        continue;
      }
      final half = (_isPerimeter(wall) ? 0 : _innerThickness / 2) +
          (wall.bumper ? 0.06 : 0);
      stampDistance(
        box,
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

        // Contact shade along rails and rocks, and a tight dark line at
        // their feet that seats them on the turf.
        final contact = nearest[row * width + col];
        if (contact < shadeReach) {
          final k = math.pow(1 - contact / shadeReach, 1.6).toDouble();
          color = _mix(color, _Farm.turfShade, k * 0.55);
          if (contact < 0.22) {
            color = _shade(color, 0.78 + 0.22 * (contact / 0.22));
          }
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
          } else if (signed < 0.5) {
            // A narrow lip of wet sand: a causeway between two ponds keeps
            // its green middle.
            final k = _softBand(signed, 0.2, 0.14);
            bitmap.blend(col, row, _mix(_Farm.shore, 0xC9B07A, 0.35), k * 0.85);
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

    // Hills: the slopes facing the sun lighter, the far ones darker (the
    // relief reads even where the light is flat), mown rings following
    // the contours, and a crease of shade where a slope meets the level.
    if (hole.hills.isNotEmpty) {
      final (sx, sy, sz) = theme.sunFrom;
      final sunLength = math.sqrt(sx * sx + sy * sy + sz * sz);
      final lx = sx / sunLength, ly = sy / sunLength, lz = sz / sunLength;
      for (final hill in hole.hills) {
        final reach = hill.reach;
        final c0 =
            colOf(math.min(hill.a.x, hill.b.x) - reach).clamp(0, width - 1);
        final c1 =
            colOf(math.max(hill.a.x, hill.b.x) + reach).clamp(0, width - 1);
        final r0 =
            rowOf(math.max(hill.a.y, hill.b.y) + reach).clamp(0, height - 1);
        final r1 =
            rowOf(math.min(hill.a.y, hill.b.y) - reach).clamp(0, height - 1);
        final rise = hill.height.abs();
        for (var row = r0; row <= r1; row++) {
          for (var col = c0; col <= c1; col++) {
            final point = worldAt(col, row);
            final s = _segmentDistance(point, hill.a, hill.b);
            if (s >= reach || !_reach.reachableAt(point)) continue;
            final g = hole.groundGradientAt(point);
            final n = math.sqrt(g.x * g.x + 1 + g.y * g.y);
            // The light the slope gets beyond what level turf gets: an
            // absolute difference, so a low sun (the Barn's dusk) does not
            // blow the far slopes to black on top of the real lighting.
            final lit = (-g.x * lx + ly - g.y * lz) / n;
            final relative = ((lit - ly) * 1.6).clamp(-0.3, 0.3);
            final base = bitmap.get(col, row);
            var color = _shade(base, 1 + relative * 0.75);
            // Contour rings: the mower followed the slope.
            final level = hill.heightAt(point).abs();
            if (level > 0.02 && level < rise - 0.02) {
              final ring = ((level / rise) * 5).floor().isEven;
              color = _shade(color, ring ? 1.035 : 0.965);
            }
            // The crease at the foot (or round the rim, on a dip).
            final u = ((s - hill.top) / hill.skirt).clamp(0.0, 1.0);
            final crease = hill.height > 0
                ? _softBand(1 - u, 0.12, 0.1)
                : _softBand(u, 0.12, 0.1);
            if (crease > 0) color = _mix(color, _Farm.turfShade, crease * 0.22);
            bitmap.set(col, row, color);
          }
        }
      }
    }

    // Tiers: a terrace's top a touch brighter than the floor below it, a
    // pale lip along every drop and a shade at its foot, and a ramp lit by
    // the side it faces (like a hill's slopes) with chevrons up its rise.
    if (hole.terraces.isNotEmpty || hole.ramps.isNotEmpty) {
      void over(Rect box, void Function(int col, int row, Vec2 point) paint) {
        final c0 = colOf(box.min.x).clamp(0, width - 1);
        final c1 = colOf(box.max.x).clamp(0, width - 1);
        final r0 = rowOf(box.max.y).clamp(0, height - 1);
        final r1 = rowOf(box.min.y).clamp(0, height - 1);
        for (var row = r0; row <= r1; row++) {
          for (var col = c0; col <= c1; col++) {
            final point = worldAt(col, row);
            if (_reach.reachableAt(point)) paint(col, row, point);
          }
        }
      }

      Rect boxOf(Iterable<Vec2> points, double pad) {
        var minX = double.infinity, minY = double.infinity;
        var maxX = -double.infinity, maxY = -double.infinity;
        for (final p in points) {
          minX = math.min(minX, p.x);
          minY = math.min(minY, p.y);
          maxX = math.max(maxX, p.x);
          maxY = math.max(maxY, p.y);
        }
        return Rect(Vec2(minX - pad, minY - pad), Vec2(maxX + pad, maxY + pad));
      }

      for (final terrace in hole.terraces) {
        over(boxOf(terrace.points, 0), (col, row, point) {
          if (!terrace.contains(point)) return;
          bitmap.set(col, row, _shade(bitmap.get(col, row), 1.06));
        });
      }
      // Every step reads from above: the floor at its foot lies in its
      // shade, deeper and wider the taller the step, and the top of a drop
      // (where no rail stands) carries a pale lip where the light catches
      // the turf's rim, with a little shade sinking to it.
      final lipLight = _mix(theme.turfLight, 0xFFF6D5, 0.5);
      for (final (a, b) in _stepEdges(hole)) {
        final run = b - a;
        final length = run.length;
        if (length < 1e-6) continue;
        final along = run * (1 / length);
        final across = Vec2(-along.y, along.x);
        over(boxOf([a, b], 2.0), (col, row, point) {
          final d = _segmentDistance(point, a, b);
          if (d > 2.0) return;
          final side = (point - a).dot(across);
          final here = hole.tierHeightAt(point);
          final there = hole.tierHeightAt(point - across * (2 * side));
          final rise = there - here;
          var color = bitmap.get(col, row);
          if (rise >= 0.2) {
            final reach = 0.6 + rise * 0.9;
            if (d >= reach) return;
            final k = math.pow(1 - d / reach, 1.6).toDouble() * 0.55;
            color = _mix(color, _Farm.turfShade, k);
          } else if (rise <= -0.2) {
            if (d > 0.5) return;
            final t = ((point - a).dot(along)).clamp(0.0, length);
            if (_railAlong(a + along * t, along)) return;
            final rim = _softBand(d, 0.1, 0.05);
            final lip = _softBand(d, 0.34, 0.16) * (1 - rim);
            if (lip > 0) color = _mix(color, _Farm.turfShade, lip * 0.35);
            if (rim > 0) color = _mix(color, lipLight, rim * 0.85);
          } else {
            return;
          }
          bitmap.set(col, row, color);
        });
      }
      final (sx, sy, sz) = theme.sunFrom;
      final sunLength = math.sqrt(sx * sx + sy * sy + sz * sz);
      final lx = sx / sunLength, ly = sy / sunLength, lz = sz / sunLength;
      for (final ramp in hole.ramps) {
        final (left, right) = ramp.sides;
        over(boxOf([left.$1, left.$2, right.$1, right.$2], 0),
            (col, row, point) {
          if (!ramp.covers(point)) return;
          final g = ramp.gradientAt(point);
          final n = math.sqrt(g.x * g.x + 1 + g.y * g.y);
          final lit = (-g.x * lx + ly - g.y * lz) / n;
          final relative = ((lit - ly) * 1.6).clamp(-0.3, 0.3);
          var color = _shade(bitmap.get(col, row), 1 + relative * 0.75);
          // Chevrons pointing up the ramp, mown into it.
          final axis = ramp.to - ramp.from;
          final offset = point - ramp.from;
          final up = offset.dot(axis) / ramp.length;
          final aside = offset.cross(axis).abs() / ramp.length;
          final phase = (up - aside * 0.7) / 1.3;
          final band = phase - phase.floorToDouble();
          color = _shade(color, band < 0.38 ? 1.12 : 0.93);
          bitmap.set(col, row, color);
        });
      }
    }

    // The nest: a dish of shade deepening toward the cup (the green worn
    // down round it), and a dark ring of turf at its rim.
    final nest = hole.nest;
    final reach = nest.radius * 1.9;
    final c0 = colOf(nest.position.x - reach).clamp(0, width - 1);
    final c1 = colOf(nest.position.x + reach).clamp(0, width - 1);
    final r0 = rowOf(nest.position.y + reach).clamp(0, height - 1);
    final r1 = rowOf(nest.position.y - reach).clamp(0, height - 1);
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        final d = worldAt(col, row).distanceTo(nest.position);
        final k = _softBand(d, nest.radius * 1.4, nest.radius * 0.5);
        if (k > 0) bitmap.blend(col, row, _Farm.turfShade, k * 0.45);
        final rim = 1 - ((d - nest.radius * 1.04) / (nest.radius * 0.12)).abs();
        if (rim > 0)
          bitmap.blend(col, row, 0x24401A, rim.clamp(0.0, 1.0) * 0.6);
      }
    }

    return bitmap;
  }

  /// Whether a rail (not a ledge) stands along [direction] through [point]:
  /// the step there is the rail's to face.
  bool _railAlong(Vec2 point, Vec2 direction) {
    for (final wall in hole.walls) {
      if (wall.ledge) continue;
      final run = wall.b - wall.a;
      final length = run.length;
      if (length < 1e-6) continue;
      if ((run * (1 / length)).cross(direction).abs() > 0.02) continue;
      if (_segmentDistance(point, wall.a, wall.b) < 0.05) return true;
    }
    return false;
  }

  /// Whether [wall] runs along the green's edge (the outer fence).
  bool _isPerimeter(WallSegment wall) {
    final b = hole.bounds;
    bool onX(double x) =>
        (wall.a.x - x).abs() < 0.01 && (wall.b.x - x).abs() < 0.01;
    bool onY(double y) =>
        (wall.a.y - y).abs() < 0.01 && (wall.b.y - y).abs() < 0.01;
    return onX(b.min.x) || onX(b.max.x) || onY(b.min.y) || onY(b.max.y);
  }
}

/// A hole's turf work sent off the UI isolate: the table's shape and the
/// lawn's pixels (on the web, where there are no isolates, it runs in
/// place, a step of its own).
class _TurfJob with _LawnPaint {
  _TurfJob(this.hole, this.theme);

  @override
  final HoleDef hole;
  @override
  final _Theme theme;
  @override
  late final _TableShape shape = _TableShape.of(hole);
}

/// What [_prepareTurf] brings back.
typedef _Turf = ({
  _TableShape shape,
  _Bitmap paint,
  (List<double>, List<double>, List<double>) arrays,
});

/// [compute]'s entry: the shape, the lawn painted over it, the turf's
/// geometry.
_Turf _prepareTurf(_TurfJob job) => (
      shape: job.shape,
      paint: job._lawnBitmap(),
      arrays: job.shape.topArrays(turf: true, relief: job.hole),
    );

/// Builds one hole's course pieces. Every piece is a fresh subtree the
/// world parents under its kind group; the hole's animated pieces register
/// with [animated].
/// How deep the nest's cup runs below the turf: room for a holed egg and
/// the chick to drop out of sight. As deep as the wide nest it used to be
/// (radius 1.7) however narrow it is now: a hole, not a dish.
double _nestCupDepth(double radius) => math.max(radius * 0.8, 1.36);

/// The cup's inside, drawn before the opening's depth (and both before the
/// turf and everything else): see [_CourseKit.nest].
const int _cupOrder = -2;
const int _openingOrder = -1;

class _CourseKit with _LawnPaint {
  _CourseKit(this.hole,
      {required this.eggRadius,
      required this.animated,
      required this.rig,
      required this.theme,
      required this.flagShakeUntil})
      : _rand = _Rand(_seedOf(hole.id));

  /// Until when (the frame clock) the flag shakes: an egg just dropped in.
  final double Function() flagShakeUntil;

  /// The course's look: the rails' style, the turf's greens.
  @override
  final _Theme theme;

  @override
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

  /// The tiers' steps, faced in the course's own build (see
  /// [_stepMaterial]): under a ledge's lip and under every rail that
  /// stands on a step.
  late final tjs.MeshStandardMaterial _cliffMaterial =
      _stepMaterial(theme.kind);

  /// The belt frames keep timber whatever the rails are.
  late final tjs.MeshStandardMaterial _timber = tjs.MeshStandardMaterial({
    tjs.MaterialProperty.color: _lin(_Farm.wood),
    tjs.MaterialProperty.map: _woodGrainTexture(),
    tjs.MaterialProperty.roughness: 0.78,
    tjs.MaterialProperty.metalness: 0.0,
  });

  tjs.DataTexture? _crateFace;

  /// The table's shape: where the egg can roll, the garden islands, the
  /// carved-away stretches (see `table_shape.dart`).

  /// The table's outline and reach: worked out here unless [takeTurf]
  /// brought it from off the UI isolate.
  @override
  _TableShape get shape => _shape ??= _TableShape.of(hole);
  _TableShape? _shape;

  /// The lawn's pixels, painted off the UI isolate (null: paint them here).
  _Bitmap? _lawnPaint;

  /// The turf's geometry arrays, worked out off the UI isolate (null:
  /// here).
  (List<double>, List<double>, List<double>)? _turfArrays;

  /// Takes what [_prepareTurf] worked out for this hole.
  void takeTurf(_Turf turf) {
    _shape = turf.shape;
    _lawnPaint = turf.paint;
    _turfArrays = turf.arrays;
  }

  tjs.DataTexture _lawnTexture() => (_lawnPaint ?? _lawnBitmap()).texture();

  // ---- the turf ---------------------------------------------------------------------

  /// The green: one plane carrying the procedural lawn.
  tjs.Mesh lawn() {
    final bounds = hole.bounds;
    // Up close the blades show: a tiling normal map, a tile every 1.6 units.
    final blades = _grassNormalTexture()
      ..repeat.setValues(bounds.width / 1.6, bounds.height / 1.6);
    // The turf follows the table's shape: no green where the walls have
    // carved the course away.
    return tjs.Mesh(
      _topGeometry(_turfArrays ?? shape.topArrays(turf: true, relief: hole)),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: _lawnTexture(),
        tjs.MaterialProperty.normalMap: blades,
        tjs.MaterialProperty.normalScale: tjs.Vector2(0.55, 0.55),
        tjs.MaterialProperty.roughness: 0.96,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'lawn'
      ..receiveShadow = true;
  }

  // ---- the table ----------------------------------------------------------------------

  /// The wooden table the green sits on, in the hole's own shape: a
  /// timber lip past the green's edge and a planked skirt following the
  /// outline down to the meadow.
  tjs.Group table() {
    final bounds = hole.bounds;
    final group = tjs.Group()..name = 'table';
    final rim = tjs.Mesh(
      shape.top(turf: false),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(_Farm.woodTop),
        tjs.MaterialProperty.map: _woodGrainTexture(),
        tjs.MaterialProperty.roughness: 0.8,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'table-rim'
      ..position.y = -0.005
      ..receiveShadow = true;
    final skirtGrain = _woodGrainTexture()..repeat.setValues(1, 1);
    final skirt = tjs.Mesh(
      shape.skirt(_tableHeight),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(_Farm.tableSide),
        tjs.MaterialProperty.map: skirtGrain,
        tjs.MaterialProperty.roughness: 0.85,
        tjs.MaterialProperty.metalness: 0.0,
      }),
    )
      ..name = 'table-skirt'
      ..castShadow = true
      ..receiveShadow = true;
    group
      ..add(rim)
      ..add(skirt);
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
      // A post only where the table runs under it.
      if (!shape.keptAt(spot + (center - spot).normalized(Vec2.zero) * 0.6)) {
        continue;
      }
      final away = (spot - center);
      final push = Vec2(
        away.x.sign *
            (spot.x == bounds.min.x || spot.x == bounds.max.x ? outward : 0),
        away.y.sign *
            (spot.y == bounds.min.y || spot.y == bounds.max.y ? outward : 0),
      );
      final at = spot + push;
      // A post by a raised tier stands as tall as the fence there.
      final rise =
          hole.tierHeightAt(spot + (center - spot).normalized(Vec2.zero) * 0.6);
      final tall = rise + _railHeight + 0.42;
      posts.add(
        tjs.BoxGeometry(0.82, tall, 0.82),
        _place(at.x, tall / 2, at.y),
        _Farm.post,
        baseShade: 0.82,
      );
      posts.add(
        tjg.ConeGeometry(0.62, 0.42, 4),
        _place(at.x, tall + 0.21, at.y, yaw: math.pi / 4),
        _Farm.barnRed,
      );
    }
    final postMesh = posts.mesh('table-posts');
    if (postMesh != null) group.add(postMesh);
    return group;
  }

  // ---- the tiers' steps -------------------------------------------------------------------

  /// The faces of the tiers' steps: wherever the ground steps down along a
  /// terrace's edge or a ramp's side and no rail stands on the line (a
  /// rail carries its own face, see [_railPiece]), a face in the course's
  /// timber, stone or hay drops from the high turf to the low - so a drop
  /// reads as a step of the table, not a stretched slope. Null when the
  /// hole is one level.
  tjs.Object3D? cliffs() {
    final edges = _stepEdges(hole);
    if (edges.isEmpty) return null;
    final face = _QuadSink();
    for (final (a, b) in edges) {
      final run = b - a;
      final length = run.length;
      if (length < 1e-6) continue;
      final along = run * (1 / length);
      final across = Vec2(-along.y, along.x);
      final steps = math.max(1, (length / 0.25).ceil());
      // The levels either side at a point of the edge, read a hair inside
      // its ends (a corner's other edge is right there).
      (double, double, bool) levels(double t) {
        final inset = (t * length).clamp(0.02, length - 0.02) / length;
        final p = a + run * inset;
        final one = hole.tierHeightAt(p + across * 0.03);
        final other = hole.tierHeightAt(p - across * 0.03);
        return (math.min(one, other), math.max(one, other), one < other);
      }

      for (var i = 0; i < steps; i++) {
        final t0 = i / steps, t1 = (i + 1) / steps;
        final p0 = a + run * t0, p1 = a + run * t1;
        if (_railAlong((p0 + p1) * 0.5, along)) continue;
        final (lo0, hi0, _) = levels(t0);
        final (lo1, hi1, _) = levels(t1);
        if (hi0 - lo0 < 0.02 && hi1 - lo1 < 0.02) continue;
        // The face looks out over the low side.
        final (_, _, oneLow) = levels((t0 + t1) / 2);
        final out = oneLow ? across : across * -1;
        final u0 = t0 * length / 2.4, u1 = t1 * length / 2.4;
        face.quad(
            [
              (p0.x, lo0, p0.y),
              (p1.x, lo1, p1.y),
              (p1.x, hi1, p1.y),
              (p0.x, hi0, p0.y),
            ],
            out,
            [
              (u0, lo0 / 0.62),
              (u1, lo1 / 0.62),
              (u1, hi1 / 0.62),
              (u0, hi0 / 0.62),
            ]);
      }
    }
    if (face.isEmpty) return null;
    return tjs.Group()
      ..name = 'cliffs'
      ..add(face.mesh('cliff-face', _cliffMaterial)!);
  }

  // ---- the rails ------------------------------------------------------------------------

  /// A timber rail along [a]-[b]: the outer fence stands just outside the
  /// green (its inner face on the physics' line), an inner wall stands
  /// centred and slim. Rails run long by their own thickness so corners
  /// close.
  tjs.Group rail(Vec2 a, Vec2 b) {
    final wall = WallSegment(a, b);
    final perimeter = _isPerimeter(wall);
    if (perimeter) {
      final bounds = hole.bounds;
      Vec2 clip(Vec2 p) => Vec2(p.x.clamp(bounds.min.x, bounds.max.x),
          p.y.clamp(bounds.min.y, bounds.max.y));
      a = clip(a);
      b = clip(b);
    }
    // Only where the table runs under it: over carved-away ground a rail
    // would float. Where a tier steps under it, it stands on the high
    // ground with the step's face below it.
    final runs = [
      for (final (from, to) in shape.keptRuns(a, b))
        ..._steppedRuns(from, to, perimeter),
    ];
    if (runs.length == 1 &&
        runs.single.flat &&
        runs.single.from.distanceTo(a) < 1e-6 &&
        runs.single.to.distanceTo(b) < 1e-6) {
      return _railPiece(a, b, perimeter);
    }
    final group = tjs.Group()..name = 'wall';
    for (final run in runs) {
      group.add((run.varying
          ? _profileRail(run, perimeter)
          : _railPiece(run.from, run.to, perimeter,
              low: run.low,
              high: run.high,
              longAtStart: run.atStart,
              longAtEnd: run.atEnd))
        ..name = 'wall-piece');
    }
    return group;
  }

  /// A rail piece from [a] to [b] standing on the ground at [high], the
  /// step's face below it down to [low] when the ground steps under it.
  /// It runs long by its thickness at the ends that close a corner
  /// ([longAtStart], [longAtEnd]), not where a stepped wall changes level.
  tjs.Group _railPiece(Vec2 a, Vec2 b, bool perimeter,
      {double low = 0,
      double high = 0,
      bool longAtStart = true,
      bool longAtEnd = true}) {
    final thickness = perimeter ? _fenceThickness : _innerThickness;
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
    // The extensions, along local x: back past a, on past b.
    final back = longAtStart ? thickness / 2 : 0.0;
    final on = longAtEnd ? thickness / 2 : 0.0;
    final long = length + (longAtStart && longAtEnd ? thickness : back + on);
    final shift = (on - back) / 2;
    final group = tjs.Group()
      ..name = 'wall'
      // The rail runs a to b: long local x, turned by the run's angle (the
      // game's y-down angle reads a negative world turn about y).
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, high, mid.y);
    final body = tjs.Mesh(
      _woodBox(long, _railHeight, thickness),
      _railMaterial,
    )
      ..name = 'wall-body'
      ..position.setValues(shift, _railHeight / 2, 0)
      ..castShadow = true
      ..receiveShadow = true;
    final cap = tjs.Mesh(_railCap(long + 0.08, thickness), _capMaterial)
      ..name = 'wall-cap'
      ..position.setValues(shift, _railHeight, 0)
      ..castShadow = true
      ..receiveShadow = true;
    group
      ..add(body)
      ..add(cap);
    if (theme.rails == _RailStyle.hedge) {
      group.add(_cornTop(long, thickness)..position.x = shift);
    }
    if (high - low > 0.01) {
      group.add(tjs.Mesh(
        _woodBox(long, high - low, thickness),
        _cliffMaterial,
      )
        ..name = 'wall-step'
        ..position.setValues(shift, (low - high) / 2, 0)
        ..castShadow = true
        ..receiveShadow = true);
    }
    return group;
  }

  /// The tiers' heights either side of the wall [a]-[b] along it, as runs
  /// of one level (a rail on the flat, on a terrace, along a terrace's
  /// edge) and runs that climb (along a ramp's side). A perimeter fence
  /// reads the green inside it and the lip outside.
  List<_WallRun> _steppedRuns(Vec2 a, Vec2 b, bool perimeter) {
    final run = b - a;
    final length = run.length;
    if (length < 1e-6 || (hole.terraces.isEmpty && hole.ramps.isEmpty)) {
      return [_WallRun(a, b, 0, 0)];
    }
    final along = run * (1 / length);
    final across = Vec2(-along.y, along.x);
    final reach = perimeter ? _fenceThickness + 0.1 : _innerThickness / 2 + 0.1;
    (double, double) levels(double t) {
      final p = a + run * t;
      final one = hole.tierHeightAt(p + across * reach);
      final other = hole.tierHeightAt(p - across * reach);
      return (math.min(one, other), math.max(one, other));
    }

    bool same((double, double) x, (double, double) y) =>
        (x.$1 - y.$1).abs() < 0.004 && (x.$2 - y.$2).abs() < 0.004;
    final steps = math.max(1, (length / 0.1).ceil());
    final samples = [for (var i = 0; i <= steps; i++) levels(i / steps)];
    // Where the levels change between two samples: a jump (one changing
    // step, found by halving) or a climb (several in a row).
    final cuts = <double>[0];
    final climbs = <(int, int)>[];
    var i = 0;
    while (i < steps) {
      if (same(samples[i], samples[i + 1])) {
        i++;
        continue;
      }
      var j = i;
      while (j < steps && !same(samples[j], samples[j + 1])) {
        j++;
      }
      if (j - i == 1) {
        var lo = i / steps, hi = (i + 1) / steps;
        for (var k = 0; k < 12; k++) {
          final m = (lo + hi) / 2;
          if (same(levels(m), samples[i])) {
            lo = m;
          } else {
            hi = m;
          }
        }
        cuts.add((lo + hi) / 2);
      } else {
        cuts.add(i / steps);
        cuts.add(j / steps);
        climbs.add((i, j));
      }
      i = j;
    }
    cuts.add(1);
    final runs = <_WallRun>[];
    for (var k = 0; k + 1 < cuts.length; k++) {
      final t0 = cuts[k], t1 = cuts[k + 1];
      if (t1 - t0 < 1e-6) continue;
      final from = a + run * t0, to = a + run * t1;
      final climb = climbs.where((c) => c.$1 / steps == t0).firstOrNull;
      if (climb != null) {
        runs.add(_WallRun(from, to, 0, 0,
            profile: [
              for (var s = climb.$1; s <= climb.$2; s++) samples[s],
            ],
            atStart: k == 0,
            atEnd: k + 2 == cuts.length));
      } else {
        final (low, high) = levels((t0 + t1) / 2);
        runs.add(_WallRun(from, to, low, high,
            atStart: k == 0, atEnd: k + 2 == cuts.length));
      }
    }
    return runs;
  }

  /// A rail along a climbing run (a ramp's side): its body and a flat trim
  /// ride the higher ground, the step's face below them, all following
  /// the run's sampled levels.
  tjs.Group _profileRail(_WallRun run, bool perimeter) {
    final thickness = perimeter ? _fenceThickness : _innerThickness;
    final span = run.to - run.from;
    final length = span.length;
    final mid = (run.from + run.to) * 0.5;
    final profile = run.profile;
    final xs = [
      for (var i = 0; i < profile.length; i++)
        -length / 2 + length * i / (profile.length - 1),
    ];
    final highs = [for (final level in profile) level.$2];
    final lows = [for (final level in profile) level.$1];
    final group = tjs.Group()
      ..name = 'wall'
      ..rotation.y = -math.atan2(span.y, span.x)
      ..position.setValues(mid.x, 0, mid.y);
    group
      ..add(tjs.Mesh(
          _profileBox(xs, [for (final h in highs) h],
              [for (final h in highs) h + _railHeight], thickness),
          _railMaterial)
        ..name = 'wall-body'
        ..castShadow = true
        ..receiveShadow = true)
      ..add(tjs.Mesh(
          // A touch longer than the body, as a straight rail's is: ends
          // flush with the body's flickered through it.
          _profileBox([
            xs.first - 0.04,
            ...xs.sublist(1, xs.length - 1),
            xs.last + 0.04,
          ], [
            for (final h in highs) h + _railHeight - 0.02
          ], [
            for (final h in highs) h + _railHeight + 0.1
          ], thickness + 0.12),
          _capMaterial)
        ..name = 'wall-cap'
        ..castShadow = true)
      ..add(tjs.Mesh(_profileBox(xs, lows, highs, thickness), _cliffMaterial)
        ..name = 'wall-step'
        ..castShadow = true
        ..receiveShadow = true);
    return group;
  }

  /// A prism along local x through [xs], [thickness] deep across z, its
  /// bottom and top following [bottoms] and [tops]: the two long faces, the
  /// top, the bottom and both ends. UVs run in world units, like
  /// [_woodBox]'s.
  tjs.BufferGeometry _profileBox(List<double> xs, List<double> bottoms,
      List<double> tops, double thickness) {
    final positions = <double>[];
    final normals = <double>[];
    final uvs = <double>[];
    final h = thickness / 2;
    void quad(List<(double, double, double)> corners,
        (double, double, double) n, List<(double, double)> uv) {
      for (final k in const [0, 1, 2, 0, 2, 3]) {
        final (x, y, z) = corners[k];
        positions.addAll([x, y, z]);
        normals.addAll([n.$1, n.$2, n.$3]);
        uvs.addAll([uv[k].$1, uv[k].$2]);
      }
    }

    for (var i = 0; i + 1 < xs.length; i++) {
      final x0 = xs[i], x1 = xs[i + 1];
      final b0 = bottoms[i], b1 = bottoms[i + 1];
      final t0 = tops[i], t1 = tops[i + 1];
      // The face toward +z, wound counter-clockwise seen from +z.
      quad([
        (x0, b0, h),
        (x1, b1, h),
        (x1, t1, h),
        (x0, t0, h)
      ], (
        0,
        0,
        1
      ), [
        (x0 / 2.4, b0 / 0.62),
        (x1 / 2.4, b1 / 0.62),
        (x1 / 2.4, t1 / 0.62),
        (x0 / 2.4, t0 / 0.62)
      ]);
      // The face toward -z.
      quad([
        (x1, b1, -h),
        (x0, b0, -h),
        (x0, t0, -h),
        (x1, t1, -h)
      ], (
        0,
        0,
        -1
      ), [
        (x1 / 2.4, b1 / 0.62),
        (x0 / 2.4, b0 / 0.62),
        (x0 / 2.4, t0 / 0.62),
        (x1 / 2.4, t1 / 0.62)
      ]);
      // The top, facing up (the slope's tilt is small enough to light it as
      // level).
      quad([(x0, t0, h), (x1, t1, h), (x1, t1, -h), (x0, t0, -h)], (0, 1, 0),
          [(x0 / 2.4, 0), (x1 / 2.4, 0), (x1 / 2.4, 0.5), (x0 / 2.4, 0.5)]);
      // The bottom, facing down.
      quad([(x0, b0, -h), (x1, b1, -h), (x1, b1, h), (x0, b0, h)], (0, -1, 0),
          [(x0 / 2.4, 0), (x1 / 2.4, 0), (x1 / 2.4, 0.5), (x0 / 2.4, 0.5)]);
    }
    // The ends.
    final first = 0, last = xs.length - 1;
    quad([
      (xs[first], bottoms[first], -h),
      (xs[first], bottoms[first], h),
      (xs[first], tops[first], h),
      (xs[first], tops[first], -h),
    ], (
      -1,
      0,
      0
    ), [
      (0, bottoms[first] / 0.62),
      (0.2, bottoms[first] / 0.62),
      (0.2, tops[first] / 0.62),
      (0, tops[first] / 0.62)
    ]);
    quad([
      (xs[last], bottoms[last], h),
      (xs[last], bottoms[last], -h),
      (xs[last], tops[last], -h),
      (xs[last], tops[last], h),
    ], (
      1,
      0,
      0
    ), [
      (0, bottoms[last] / 0.62),
      (0.2, bottoms[last] / 0.62),
      (0.2, tops[last] / 0.62),
      (0, tops[last] / 0.62)
    ]);
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
      ..setAttributeFromString(
          'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false))
      ..setAttributeFromString(
          'uv', tjs.Float32BufferAttribute.fromList(uvs, 2, false));
  }

  /// The corn hedge's top: tassels standing up along it, leaves arching
  /// out of its sides, a cob here and there (in the rail's own frame). A
  /// piece too short for a tassel (a sliver where a hedge ends on a tier's
  /// edge) carries none.
  tjs.Object3D _cornTop(double length, double thickness) {
    final merged = _Merged();
    final rand = _Rand(_seedOf('${hole.id}/corn/$length'));
    for (var x = -length / 2 + 0.3; x < length / 2 - 0.2; x += 0.62) {
      final h = rand.range(0.22, 0.4);
      merged.add(
          tjg.ConeGeometry(0.07, h, 4),
          _place(x + rand.range(-0.1, 0.1), _railHeight + 0.1 + h / 2,
              rand.range(-0.08, 0.08)),
          rand.chance(0.5) ? 0xD9B76A : 0xE8CC80);
      for (final side in [-1.0, 1.0]) {
        if (!rand.chance(0.55)) continue;
        merged.add(
            tjs.BoxGeometry(0.5, 0.025, 0.11),
            _place(x, _railHeight * rand.range(0.55, 0.95),
                side * (thickness / 2 + 0.12),
                yaw: side * math.pi / 2 + rand.range(-0.4, 0.4), roll: -0.45),
            rand.chance(0.5) ? 0x5E9A35 : 0x79B145);
      }
      if (rand.chance(0.16)) {
        merged.add(
            tjg.CylinderGeometry(0.07, 0.09, 0.32, 6),
            _place(x, _railHeight * 0.72,
                (rand.chance(0.5) ? 1 : -1) * (thickness / 2 + 0.05),
                tilt: 0.3),
            0xF2C845);
      }
    }
    return merged.mesh('wall-corn', flat: true) ??
        (tjs.Group()..name = 'wall-corn');
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
    if (full) {
      // In the Barn, the round obstacles are hay bales stood on end.
      return theme.kind == _ThemeKind.barn
          ? _standingBale(arc.center, arc.radius)
          : _boulder(arc.center, arc.radius);
    }
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
          _railCap(length + _innerThickness, _innerThickness), _capMaterial)
        ..name = 'wall-cap'
        ..position.y = _railHeight
        ..castShadow = true);
    return group;
  }

  /// The rail's top: a rounded nosing a touch wider than the rail (flat
  /// trim on the barn's boards), its grain running along the rail.
  tjs.BufferGeometry _railCap(double length, double thickness) {
    if (theme.rails == _RailStyle.barnBoard) {
      return _woodBox(length, 0.12, thickness + 0.12)..translate(0, 0.06, 0);
    }
    final radius = thickness / 2 + 0.06;
    // A half-round along x: a cylinder laid on its side, squashed, its
    // lower half hidden in the rail.
    final geometry = tjg.CylinderGeometry(radius, radius, length, 14, 1)
      ..rotateZ(math.pi / 2)
      ..scale(1, 0.62, 1);
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final uv = geometry.attributes['uv'] as tjs.BufferAttribute;
    for (var i = 0; i < uv.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      uv.setXY(i, x / 2.4, (math.atan2(y, z) / math.pi) * 0.8);
    }
    uv.needsUpdate = true;
    return geometry;
  }

  // ---- bumpers ----------------------------------------------------------------------------

  /// A straight bumper: a red rubber rail with yolk-capped ends and a
  /// cream band - the pinball rail the egg bounces off. Where a tier steps
  /// under it, it stands on the high ground with the step's face below.
  tjs.Group bumperRail(WallSegment wall) {
    final runs = _steppedRuns(wall.a, wall.b, false);
    if (runs.length == 1 && runs.single.flat) {
      return _bumperPiece(wall.a, wall.b);
    }
    final group = tjs.Group()..name = 'bumper';
    for (final run in runs) {
      if (!run.varying) {
        group.add(_bumperPiece(run.from, run.to, low: run.low, high: run.high));
        continue;
      }
      // Up a climb, in short pieces each at its own level.
      final pieces = run.profile.length - 1;
      for (var i = 0; i < pieces; i++) {
        final level = run.profile[i];
        group.add(_bumperPiece(run.from.lerp(run.to, i / pieces),
            run.from.lerp(run.to, (i + 1) / pieces),
            low: level.$1, high: level.$2));
      }
    }
    return group;
  }

  tjs.Group _bumperPiece(Vec2 a, Vec2 b, {double low = 0, double high = 0}) {
    final run = b - a;
    final length = run.length;
    final mid = (a + b) * 0.5;
    const height = 0.62;
    const thickness = 0.44;
    final group = tjs.Group()
      ..name = 'bumper'
      ..rotation.y = -math.atan2(run.y, run.x)
      ..position.setValues(mid.x, high, mid.y);
    if (high - low > 0.01) {
      group.add(tjs.Mesh(
          _woodBox(length + thickness, high - low, thickness), _cliffMaterial)
        ..name = 'bumper-step'
        ..position.y = (low - high) / 2
        ..castShadow = true
        ..receiveShadow = true);
    }
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

  /// A boulder: a rounded, lumpy stone sunk into the turf, moss on its
  /// crown, smooth-shaded like the eggs that roll by it.
  tjs.Mesh _boulder(Vec2 at, double radius) {
    final rand = _Rand(_seedOf('${hole.id}/${at.x}/${at.y}'));
    final geometry =
        _lumpyStone(rand, detail: radius > 1.2 ? 3 : 2, lumps: 0.1);
    final merged = _Merged()
      ..add(
        geometry,
        _place(0, 0, 0,
            sx: radius * 1.02, sy: radius * 0.72, sz: radius * 1.02),
        _Farm.rock,
        baseShade: 0.62,
      );
    final mesh = merged.mesh('rock', flat: false)!;
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
    // The pull, drawn: two dashed rings turning in toward the silo,
    // opposite ways, the inner one quicker.
    final swirls = <(tjs.Mesh, double)>[];
    for (final (fraction, speed) in const [(0.82, 0.5), (0.6, -0.8)]) {
      final radius = well.radius * fraction;
      final swirl = tjs.Mesh(
        _dashedRing(radius - 0.14, radius + 0.14, 10, 0.55),
        _unlit(_Farm.trim, opacity: 0.55, depthWrite: false),
      )
        ..name = 'well-swirl'
        ..rotation.x = -math.pi / 2
        ..position.y = 0.03
        ..renderOrder = 2;
      group.add(swirl);
      swirls.add((swirl, speed));
    }
    animated.add(_AnimatedBy((time, dt) {
      for (final (swirl, speed) in swirls) {
        swirl.rotation.z = time * speed;
      }
    }));

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
    // A traced pond's shore: its foam is a ribbon of its own (below).
    final shore = <List<Vec2>>[];
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
        center = _centroid(points);
        // Traced, not fanned: a pond cut round an island or a causeway is
        // not star-shaped, and a fan from its centre laid water (and its
        // white rim) over the land.
        geometry = _tracedWaterGeometry(shape, center, shore: shore);
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
      final foamK = shore.isEmpty ? _softBand(inside, 0.18, 0.16) : 0.0;
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
    final ribbon = _shoreRibbon(shore, shape, 0.24, center);
    if (ribbon != null) {
      // Over the sheet's still rim (the ripple only starts inside it).
      group.add(tjs.Mesh(
        ribbon,
        tjs.MeshBasicMaterial({
          tjs.MaterialProperty.map: _foamFadeTexture(),
          tjs.MaterialProperty.color: _lin(_Farm.waterFoam),
          tjs.MaterialProperty.transparent: true,
          tjs.MaterialProperty.depthWrite: false,
          // A loop runs either way round: both faces.
          tjs.MaterialProperty.side: tjs.DoubleSide,
        }),
      )
        ..name = 'water-foam'
        ..rotation.x = -math.pi / 2
        ..position.setValues(center.x, 0.055, center.y)
        ..renderOrder = 1);
    }

    // The ripple: gentle crossing waves, normals refreshed so the sun's
    // glints dance. Still at the rim, full a unit in.
    final rims = Float32List(count);
    for (var i = 0; i < count; i++) {
      rims[i] = (-_waterSignedDistance(
              shape, Vec2(center.x + rest[i * 2], center.y - rest[i * 2 + 1])))
          .clamp(0.0, 1.0);
    }
    final phase = _rand.range(0, 6.28);
    var lastUpdate = -1.0;
    animated.add(_AnimatedBy((time, dt) {
      // Thirty updates a second is plenty for water.
      if ((time - lastUpdate).abs() < 1 / 30) return;
      lastUpdate = time;
      for (var i = 0; i < count; i++) {
        final x = rest[i * 2];
        final y = rest[i * 2 + 1];
        final rim = rims[i];
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

    // Sun glints: soft white twinkles coming and going on the water.
    final glints = <(_Billboard, double, double)>[];
    final box0 = _waterBox(shape);
    final glintCount =
        ((box0.width * box0.height) / 7).round().clamp(3, 16).toInt();
    for (var attempt = 0;
        attempt < glintCount * 4 && glints.length < glintCount;
        attempt++) {
      final spot = Vec2(_rand.range(box0.min.x, box0.max.x),
          _rand.range(box0.min.y, box0.max.y));
      if (-_waterSignedDistance(shape, spot) < 0.5) continue;
      final glint = _Billboard(
          map: _EggView3D._shadowTexture, blending: tjs.AdditiveBlending)
        ..name = 'water-glint'
        ..position.setValues(spot.x, 0.12, spot.y)
        ..renderOrder = 4;
      group.add(glint);
      glints.add((glint, _rand.range(0, 6.28), _rand.range(1.6, 3.2)));
    }
    animated.add(_AnimatedBy((time, dt) {
      for (final (glint, phase, speed) in glints) {
        final wave = math.max(0.0, math.sin(time * speed + phase));
        final flash = math.pow(wave, 10).toDouble();
        glint.material?.opacity = flash * 0.9;
        final size = 0.25 + flash * 0.5;
        glint.scale.setValues(size, size, 1);
      }
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
      // Two centimetres over the frame's top (0.06): at half a centimetre
      // the belt and the timber under it flickered through each other.
      ..position.y = 0.08
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

  /// The nest: a cup sunk into the green (a dark opening flush with the
  /// turf, a wall falling away to a floor), straw lining its rim, and the
  /// flag on its far rim flying the hole's number.
  ///
  /// The turf is one mesh, not cut: the cup's inside is drawn first
  /// ([_cupOrder]), then an invisible disc at the opening writes the
  /// turf's depth there ([_openingOrder]), so the turf drawn after it
  /// fails the depth test over the opening and the cup shows through.
  /// Anything drawn after that disc is cut at the turf line there, so what
  /// goes down into the cup (a holed egg, the chick) draws with the cup's
  /// inside, at [_cupOrder].
  tjs.Group nest({String? label}) {
    final nest = hole.nest;
    final group = tjs.Group()
      ..name = 'nest'
      ..position.setValues(nest.position.x, 0, nest.position.y);
    final r = nest.radius;
    final depth = _nestCupDepth(r);
    // The wall: the inside of a slightly tapered tube, earth lit on the
    // sun's side at the top, falling to near black at the floor.
    final wallGeometry = tjg.CylinderGeometry(r, r * 0.92, depth, 48, 3, true)
      ..translate(0, -depth / 2, 0);
    final wallPosition =
        wallGeometry.attributes['position'] as tjs.BufferAttribute;
    final wallColors = <double>[];
    for (var i = 0; i < wallPosition.count; i++) {
      final x = wallPosition.getX(i)!.toDouble() / r;
      final z = wallPosition.getZ(i)!.toDouble() / r;
      final down = -wallPosition.getY(i)!.toDouble() / depth;
      // The wall lit toward the sun's side (the far side's inside faces
      // the camera most of the time), the floor's end in shadow.
      final lit = (0.5 + 0.5 * (-z * 0.7 - x * 0.3)).clamp(0.0, 1.0);
      final color = _lin(_mix(_mix(0x4A2E18, 0x8A5E36, lit), 0x120A05,
          math.pow(down, 0.7).toDouble()));
      wallColors.addAll([color.red, color.green, color.blue]);
    }
    wallGeometry.setAttributeFromString(
        'color', tjs.Float32BufferAttribute.fromList(wallColors, 3, false));
    group.add(tjs.Mesh(
      wallGeometry,
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.side: tjs.BackSide,
      }),
    )
      ..name = 'nest-cup-wall'
      ..renderOrder = _cupOrder);
    // The floor: dark earth with a few strands of straw.
    group.add(tjs.Mesh(
      tjg.CircleGeometry(radius: r * 0.92, segments: 48),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.map: _cupTexture(),
      }),
    )
      ..name = 'nest-cup'
      ..rotation.x = -math.pi / 2
      ..position.y = -depth
      ..renderOrder = _cupOrder);
    // The opening: no colour, only the turf's depth (lifted a hair and
    // pulled nearer by polygon offset, so the turf under it never wins a
    // tie). No more: what lies on the turf over it (an egg rolling over
    // the lip) must not be cut by it.
    group.add(tjs.Mesh(
      tjg.CircleGeometry(radius: r, segments: 48),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.colorWrite: false,
        tjs.MaterialProperty.polygonOffset: true,
        tjs.MaterialProperty.polygonOffsetFactor: -1.0,
        tjs.MaterialProperty.polygonOffsetUnits: -1.0,
      }),
    )
      ..name = 'nest-opening'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.005
      ..renderOrder = _openingOrder);

    // The straw: a low, lumpy ring lining the rim (outside the opening, so
    // the hole stays a hole), and strands lying on the turf round it.
    final straw = _Merged();
    final torus = tjg.TorusGeometry(r * 1.1, r * 0.09, 8, 48);
    final position = torus.attributes['position'] as tjs.BufferAttribute;
    for (var i = 0; i < position.count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      final k =
          1 + (_hash2((x * 40).round(), (y * 40).round(), 5) - 0.5) * 0.08;
      position.setXYZ(i, x * k, y * k, z * k);
    }
    straw.add(
        torus, _place(0, r * 0.02, 0, tilt: math.pi / 2, sz: 0.5), _Farm.straw,
        baseShade: 0.7);
    for (var i = 0; i < 30; i++) {
      final angle = i / 30 * math.pi * 2 + _rand.range(-0.1, 0.1);
      final radial = r * _rand.range(1.08, 1.28);
      final length = _rand.range(0.35, 0.6) * r;
      straw.add(
        tjs.BoxGeometry(length, 0.03, 0.06),
        _place(
          math.cos(angle) * radial,
          0.04 + _rand.range(0, 0.06),
          math.sin(angle) * radial,
          yaw: -angle + _rand.range(1.2, 1.9) * (i.isEven ? 1 : -1),
          tilt: _rand.range(-0.12, 0.12),
          roll: _rand.range(-0.12, 0.12),
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
      _paintHoleNumber(canvas,
          ui.Rect.fromLTWH(4, 0, size.width - 20, size.height), label ?? '',
          color: const ui.Color(0xFFFFF4E4), fontSize: 78);
    });
    const flagWidth = 1.5;
    const flagHeight = 1.05;
    final cloth = _gridPlane(flagWidth, flagHeight, 12, 4)
      ..translate(flagWidth / 2 + 0.06, poleHeight - flagHeight / 2 - 0.08, 0);
    final flag = tjs.Mesh(
      cloth,
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: flagTexture,
        // A little of its own light, so the number reads at dusk too.
        tjs.MaterialProperty.emissive: _lin(0xFFFFFF),
        tjs.MaterialProperty.emissiveMap: flagTexture,
        tjs.MaterialProperty.roughness: 0.85,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.side: tjs.DoubleSide,
      })
        ..emissiveIntensity = 0.32,
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
        final excited =
            ((flagShakeUntil() - time) / 1.4).clamp(0.0, 1.0).toDouble();
        final wave = math.sin(x * 3.2 - time * (5.2 + excited * 9) + y * 0.6) *
            (0.16 + excited * 0.3) *
            reach;
        clothPosition.setXYZ(
            i, x - reach * reach * 0.05, y - reach * 0.06, wave);
      }
      clothPosition.needsUpdate = true;
      cloth.computeVertexNormals();
    }));
    return group;
  }

  /// The cup floor's paint: deep brown earth, a little lighter toward the
  /// wall, and a few strands of straw lying on it.
  tjs.DataTexture _cupTexture() {
    const size = 128;
    final bitmap = _Bitmap(size, size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = (x + 0.5) / size * 2 - 1;
        final dy = (y + 0.5) / size * 2 - 1;
        final d = math.sqrt(dx * dx + dy * dy).clamp(0.0, 1.0);
        // The wall lit toward the sun's side (texture v up is the far
        // side), the floor in shadow.
        final lit = (0.5 + 0.5 * (dy * 0.7 - dx * 0.3)).clamp(0.0, 1.0);
        final wall = math.pow(d, 1.5).toDouble();
        bitmap.set(x, y, _mix(0x140C06, _mix(0x24170C, 0x3A2616, lit), wall));
      }
    }
    // Strands on the floor: short strokes in dull straw.
    final rand = _Rand(29);
    for (var i = 0; i < 26; i++) {
      final angle = rand.range(0, math.pi * 2);
      final radial = rand.range(0.05, 0.62);
      final cx = size / 2 + math.cos(angle) * radial * size / 2;
      final cy = size / 2 + math.sin(angle) * radial * size / 2;
      final heading = rand.range(0, math.pi);
      final length = rand.range(6, 13);
      for (var t = -length / 2; t <= length / 2; t += 0.5) {
        final px = (cx + math.cos(heading) * t).round();
        final py = (cy + math.sin(heading) * t).round();
        if (px < 0 || py < 0 || px >= size || py >= size) continue;
        bitmap.blend(px, py, i.isEven ? 0x6A5230 : 0x52402A, 0.45);
      }
    }
    return bitmap.texture();
  }

  // ---- the hens' walks --------------------------------------------------------------------------

  /// Every hen's beat worn into the green: a soft band about a hen wide
  /// along her stops in order (round the loop when she walks three or
  /// more, out and back when she paces two), faded at its ends and where
  /// it meets water, and a few three-toed prints where she stands a while
  /// (`dwellSeconds` over 0). Worn grass, not a road: a duller, drier
  /// turf at half opacity, its edges soft and a little uneven. Hens that
  /// share a beat (the Coop's merry-go-round) wear it once. One mesh for
  /// the hole, laid on [groundAt] (hills, tiers) just over the lawn and
  /// drawn first of the turf's marks, under the eggs' shadows, the aim and
  /// its guide. Null when no hen walks the green (the Pond's ducks swim).
  tjs.Mesh? henPaths(double Function(Vec2 point) groundAt) {
    final tracks =
        _HenTracks(hole, groundAt, _Rand(_seedOf('${hole.id}/hens')));
    final beats = <String>{};
    final prints = <String>{};
    String keyOf(Vec2 p) =>
        '${(p.x * 10).round()},${(p.y * 10).round()}'; // a tenth of a unit
    for (final obstacle in hole.obstacles) {
      if (_henSwims(hole, obstacle)) continue;
      final stops = obstacle.stops;
      if (stops.length >= 2 &&
          beats.add((stops.map((stop) => keyOf(stop.at)).toList()..sort())
              .join(';'))) {
        tracks.walk(obstacle);
      }
      for (final stop in stops) {
        final waits = stop.dwellSeconds > 0 || stops.length == 1;
        if (waits && prints.add(keyOf(stop.at))) {
          tracks.prints(stop.at, obstacle.radius);
        }
      }
    }
    if (tracks.isEmpty) return null;
    // The turf's darker green, dulled toward dry earth, and lit like the
    // turf (sun, slopes, shadows), so it reads as worn grass on every
    // course's light rather than as a dark stain.
    final worn = _shade(_mix(theme.turfDark, 0x9C8A5A, 0.55), 0.92);
    return tjs.Mesh(
      tracks.geometry(),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(worn),
        tjs.MaterialProperty.map: _henTrackTexture(),
        tjs.MaterialProperty.roughness: 0.98,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: _HenTracks.opacity,
        tjs.MaterialProperty.depthWrite: false,
        tjs.MaterialProperty.side: tjs.DoubleSide,
      }),
    )
      ..name = 'hen-paths'
      ..receiveShadow = true
      ..renderOrder = _HenTracks.renderOrder;
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

  // ---- the tee's sign ---------------------------------------------------------------------------

  /// The tee's sign board, in world units, and how far it leans back so
  /// the cameras above read it.
  static const double _signWidth = 1.5;
  static const double _signHeight = 1.05;
  static const double _signLean = 0.3;

  /// The sign's paint in the course's colours: the board, and the ink of
  /// the number and its border.
  (int, int) get _signPaint => switch (theme.kind) {
        _ThemeKind.coop => (0xFAF1E4, 0xC63A2C),
        _ThemeKind.maze => (0xF4C542, 0x2F6B2A),
        _ThemeKind.pond => (0x2F7DB8, 0xFFFFFF),
        _ThemeKind.road => (0xF5C21B, 0x1E1A18),
        _ThemeKind.barn => (0xC63A2C, 0xFFF4E4),
      };

  /// The tee's sign: a post on the meadow beside the table and a board
  /// painted in the course's colours with the hole's number ([label]),
  /// leaning back a touch. Decoration only: it stands off the table, where
  /// no egg rolls, and out of the close camera's way (see [teeSignSpot]).
  /// Null without a number, or with no room for it.
  tjs.Group? teeSign({String? label}) {
    final spot = teeSignSpot;
    if (label == null || label.isEmpty || spot == null) return null;
    final (at, facing) = spot;
    // The board stands over the rail by the tee, however high the tee.
    final rise =
        hole.hasRelief ? math.max(0.0, hole.groundHeightAt(hole.tee)) : 0.0;
    final boardY = _tableHeight + rise + 1.45;
    final group = tjs.Group()
      ..name = 'tee-sign'
      ..position.setValues(at.x, -_tableHeight, at.y)
      ..rotation.y = math.atan2(facing.x, facing.y);
    group.userData['number'] = label;
    // The post, the board nailed to its front: the board's own wood shows
    // as a frame round the paint.
    final wood = _Merged()
      ..add(tjs.BoxGeometry(0.22, boardY + 0.2, 0.2),
          _place(0, (boardY + 0.2) / 2, -0.2), 0x8A5E3A,
          baseShade: 0.6)
      ..add(tjs.BoxGeometry(_signWidth + 0.16, _signHeight + 0.16, 0.1),
          _place(0, boardY, 0, tilt: -_signLean), 0x9A6438);
    group.add(wood.mesh('tee-sign-wood')!);

    final (board, ink) = _signPaint;
    final paint = _paintedTexture(160, 112, board, (canvas, size) {
      // Two planks: their seam, a little grain.
      final grain = ui.Paint()..color = const ui.Color(0x16000000);
      for (var i = 0; i < 7; i++) {
        canvas.drawRect(
            ui.Rect.fromLTWH(0, 6.0 + i * 15.5 + (i % 3) * 2, size.width, 1.5),
            grain);
      }
      canvas.drawRect(ui.Rect.fromLTWH(0, size.height / 2 - 1.5, size.width, 3),
          ui.Paint()..color = const ui.Color(0x30000000));
      // A painted border, a nail in each corner.
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(11, 11, size.width - 22, size.height - 22),
          const ui.Radius.circular(12),
        ),
        ui.Paint()
          ..color = ui.Color(0xFF000000 | ink)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      final nail = ui.Paint()..color = const ui.Color(0xFF3A2A20);
      for (final x in [5.0, size.width - 5]) {
        for (final y in [5.0, size.height - 5]) {
          canvas.drawCircle(ui.Offset(x, y), 2.6, nail);
        }
      }
      _paintHoleNumber(
          canvas, ui.Rect.fromLTWH(0, 2, size.width, size.height), label,
          color: ui.Color(0xFF000000 | ink), fontSize: 74);
    });
    final face = tjs.Mesh(
      tjs.PlaneGeometry(_signWidth, _signHeight),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: paint,
        // A little of its own light, so the number reads at dusk too.
        tjs.MaterialProperty.emissive: _lin(0xFFFFFF),
        tjs.MaterialProperty.emissiveMap: paint,
        tjs.MaterialProperty.roughness: 0.82,
        tjs.MaterialProperty.metalness: 0.0,
      })
        ..emissiveIntensity = theme.kind == _ThemeKind.barn ? 0.4 : 0.14,
    )
      ..name = 'tee-sign-face'
      // Just proud of the board, leaning with it.
      ..position.setValues(
          0, boardY + math.sin(_signLean) * 0.056, math.cos(_signLean) * 0.056)
      ..rotation.x = -_signLean
      ..receiveShadow = true;
    group.add(face);
    return group;
  }

  /// Where the tee's sign stands and the way its board faces (a unit
  /// vector on the ground): on the meadow just off the table, as near the
  /// tee as the table allows - never on the camera's side of the green,
  /// never straight behind the egg on the tee where the play camera looks
  /// from, clear of the host and of the corners' lanterns. Null when nothing
  /// round the tee will do.
  late final (Vec2, Vec2)? teeSignSpot = _findTeeSignSpot();

  (Vec2, Vec2)? _findTeeSignSpot() {
    final tee = hole.tee;
    final bounds = hole.bounds;
    // The camera at the tee hangs behind the egg, looking at the nest.
    final yaw = PuttCameraRig.yawToward(tee, hole.nest.position);
    final away = Vec2(math.sin(yaw), math.cos(yaw));
    final host = _hostSpotOf(hole);
    // The Barn's lanterns stand off the table's corners.
    const lip = _fenceThickness + 1.8;
    final lanterns = [
      for (final x in [bounds.min.x - lip, bounds.max.x + lip])
        for (final y in [bounds.min.y - lip, bounds.max.y + lip]) Vec2(x, y),
    ];
    // Off the table with room for the post and the board round it.
    bool offTable(Vec2 p) {
      if (shape.keptAt(p)) return false;
      for (var k = 0; k < 8; k++) {
        final angle = k * math.pi / 4;
        if (shape.keptAt(p + Vec2(math.cos(angle), math.sin(angle)) * 0.9)) {
          return false;
        }
      }
      return true;
    }

    Vec2? best;
    var bestScore = double.infinity;
    for (var step = 0; step < 72; step++) {
      final angle = step * math.pi / 36;
      final direction = Vec2(math.cos(angle), math.sin(angle));
      // Within 35 degrees of straight behind the egg: between it and the
      // camera, in the way. (The tee mostly backs onto the table's end, so
      // the sign may stand behind it off to a side.)
      if (direction.dot(away) < -0.82) continue;
      // Within a stroll of the tee, or not at all: a sign across the table
      // (a tee by the camera's edge, the Coop's Nesting Boxes) read as
      // nobody's.
      for (var reach = 1.5; reach < 15; reach += 0.25) {
        final p = tee + direction * reach;
        if (!offTable(p)) continue;
        if (p.y > bounds.max.y - 1) break;
        if (p.distanceTo(host) < 5.5) break;
        if (lanterns.any((lantern) => p.distanceTo(lantern) < 2)) break;
        // Beside the tee rather than ahead along the shot or behind it.
        final score = reach * (1 + 0.3 * direction.dot(away).abs());
        if (score < bestScore) {
          best = p;
          bestScore = score;
        }
        break;
      }
    }
    if (best == null) return null;
    // The board turns halfway between the close camera at the tee and the
    // overview's, both out on the camera's side.
    final toCamera = (tee - away * 12 - best).normalized(const Vec2(0, 1));
    final facing = (toCamera + const Vec2(0, 1)).normalized(const Vec2(0, 1));
    return (best, facing);
  }

  // ---- garden beds -------------------------------------------------------------------------------

  /// The walled-off ground planted in the theme's way: flower beds by the
  /// coop, corn in the maze, reeds by the pond, wheat along the road,
  /// straw at the barn. Plants keep clear of the rails. Null when the whole
  /// green is in play.
  tjs.Object3D? garden() {
    if (_reach._reach.unreachableCount == 0) return null;
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
        // Islands only: carved-away ground is the meadow's.
        if (_reach.reachableAt(p) || !shape.keptAt(p) || nearRail(p)) continue;
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

  /// A round bale stood on its end where the Barn puts an obstacle: the
  /// circle the egg bounces off is its footprint. The rolled hay spirals
  /// on its top, twine bands ring its side, and loose straw lies round
  /// its foot.
  tjs.Mesh _standingBale(Vec2 at, double radius) {
    final rand = _Rand(_seedOf('${hole.id}/bale/${at.x}/${at.y}'));
    final height = math.max(0.9, radius * 1.15);
    final merged = _Merged()
      ..add(tjg.CylinderGeometry(radius, radius * 1.02, height, 28, 4),
          _place(0, height / 2, 0), _Farm.hay,
          baseShade: 0.72);
    // The roll's spiral on the top: rings of darker and lighter hay.
    final rings = math.max(3, (radius / 0.22).round());
    for (var i = 1; i <= rings; i++) {
      final r = radius * i / (rings + 0.6);
      merged.add(
          tjg.TorusGeometry(r, 0.035, 4, 28),
          _place(0, height + 0.005, 0, tilt: math.pi / 2),
          i.isEven ? _Farm.hayDark : _Farm.strawLight);
    }
    for (final band in [0.3, 0.7]) {
      merged.add(tjg.TorusGeometry(radius * 1.012 + 0.01, 0.04, 5, 32),
          _place(0, height * band, 0, tilt: math.pi / 2), _Farm.strawDark);
    }
    // Loose straw at the foot, each a little higher than the last, so
    // two that cross never share a top (they flickered where they did).
    for (var i = 0; i < 10; i++) {
      final angle = rand.range(0, math.pi * 2);
      final out = radius + rand.range(0.05, 0.4);
      merged.add(
          tjs.BoxGeometry(rand.range(0.35, 0.6), 0.03, 0.05),
          _place(math.cos(angle) * out, 0.02 + i * 0.004, math.sin(angle) * out,
              yaw: rand.range(0, math.pi)),
          rand.chance(0.5) ? _Farm.straw : _Farm.strawLight);
    }
    return merged.mesh('bale', flat: false, roughness: 0.95)!
      ..name = 'rock'
      ..position.setValues(at.x, 0, at.y);
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
          // Proud of the roll's flat end by more than a hair, or the two
          // flicker through each other from across the green.
          _place(side * (length / 2 + 0.025), radius, 0,
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

// ---- the hens' walks ------------------------------------------------------------------------

/// Whether [obstacle] swims rather than walks: the Pond's ducks, by name
/// or by a stop out on the water. Swimmers wear no path.
bool _henSwims(HoleDef hole, MovingObstacle obstacle) =>
    obstacle.id.contains('duck') ||
    obstacle.stops
        .any((stop) => hole.water.any((pond) => pond.contains(stop.at)));

/// The worn band's alpha: soft across (v), and faded in over the first
/// quarter of u and out over the last, so a band's ends set u from 0 and
/// to 1 while its middle stays at 0.5. White: the material's colour tints
/// it. Small, and the hole's own: it goes with the hole's material.
tjs.DataTexture _henTrackTexture() {
  const size = 32;
  final bitmap = _Bitmap(size, size);
  double ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  for (var y = 0; y < size; y++) {
    // Across: full in the middle half, easing out to nothing at the edges.
    final v = (y + 0.5) / size;
    final across = ease((1 - (2 * v - 1).abs()) / 0.55);
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size;
      final ends = u < 0.25
          ? ease(u / 0.25)
          : u > 0.75
              ? ease((1 - u) / 0.25)
              : 1.0;
      bitmap.set(x, y, 0xFFFFFF, (255 * across * ends).round());
    }
  }
  return bitmap.texture(srgb: false);
}

/// The geometry of a hole's hen paths and prints, poured into one list of
/// triangles (x, ground height + lift, y) with their u/v into
/// [_henTrackTexture].
class _HenTracks {
  _HenTracks(this.hole, this.groundAt, this.rand);

  final HoleDef hole;
  final double Function(Vec2 point) groundAt;
  final _Rand rand;

  /// The band's opacity at its fullest: the lawn shows through.
  static const double opacity = 0.5;

  /// Drawn before the eggs' shadows and tint discs (2) and the aim (4 and
  /// up, no depth test).
  static const int renderOrder = 1;

  /// How far over the turf the band lies, and the prints over it.
  static const double lift = 0.012;
  static const double printLift = 0.016;

  /// The band's half width against the hen's collision radius.
  static const double widthOfRadius = 0.75;

  /// Samples along the band, world units.
  static const double step = 0.35;

  final List<double> _positions = [];
  final List<double> _uvs = [];

  bool get isEmpty => _positions.isEmpty;

  bool _wet(Vec2 p) => hole.water.any((pond) => pond.contains(p));

  /// [obstacle]'s beat as a band: round its stops (the corners eased)
  /// when it has three or more, along its one leg (a little past each
  /// end, faded) when it has two. Broken, and faded, where water lies.
  void walk(MovingObstacle obstacle) {
    final stops = [for (final stop in obstacle.stops) stop.at];
    if (stops.length < 2) return;
    final halfWidth = obstacle.radius * widthOfRadius;
    final closed = stops.length > 2;
    final List<Vec2> line;
    if (closed) {
      line = _eased(stops, halfWidth);
    } else {
      final along = (stops[1] - stops[0]).normalized(const Vec2(1, 0));
      final past = obstacle.radius * 0.5;
      line = [stops[0] - along * past, stops[1] + along * past];
    }
    final points = _sample(line, closed: closed);
    if (points.length < 2) return;
    // The dry stretches: the whole loop when none of it is wet.
    final wet = [for (final p in points) _wet(p)];
    if (closed && !wet.contains(true)) {
      _band(points, halfWidth, closed: true);
      return;
    }
    // Start a loop at a wet sample, so no dry stretch wraps the seam.
    var start = 0;
    if (closed) start = wet.indexOf(true);
    var run = <Vec2>[];
    for (var k = 0; k < points.length + (closed ? 1 : 0); k++) {
      final i = (start + k) % points.length;
      if (wet[i]) {
        if (run.length >= 2) _band(run, halfWidth, closed: false);
        run = [];
      } else {
        run.add(points[i]);
      }
    }
    if (run.length >= 2) _band(run, halfWidth, closed: false);
  }

  /// A loop's corners eased into short curves, so the band's inner edge
  /// never folds over itself where the hen turns.
  static List<Vec2> _eased(List<Vec2> loop, double cut) {
    final eased = <Vec2>[];
    final n = loop.length;
    for (var i = 0; i < n; i++) {
      final before = loop[(i - 1 + n) % n];
      final at = loop[i];
      final after = loop[(i + 1) % n];
      final inLength = at.distanceTo(before);
      final outLength = at.distanceTo(after);
      if (inLength < 1e-6 || outLength < 1e-6) {
        eased.add(at);
        continue;
      }
      final from =
          at + (before - at) * (math.min(cut, inLength * 0.4) / inLength);
      final to =
          at + (after - at) * (math.min(cut, outLength * 0.4) / outLength);
      for (var k = 0; k <= 4; k++) {
        final t = k / 4;
        eased.add(
            from * ((1 - t) * (1 - t)) + at * (2 * (1 - t) * t) + to * (t * t));
      }
    }
    return eased;
  }

  /// [line] walked in [step]s (its corners kept), round to its start when
  /// [closed].
  static List<Vec2> _sample(List<Vec2> line, {required bool closed}) {
    final points = <Vec2>[line.first];
    final legs = closed ? line.length : line.length - 1;
    for (var i = 0; i < legs; i++) {
      final a = line[i];
      final b = line[(i + 1) % line.length];
      final length = a.distanceTo(b);
      final count = math.max(1, (length / step).ceil());
      for (var k = 1; k <= count; k++) {
        points.add(a.lerp(b, k / count));
      }
    }
    // A loop's last sample is its first again.
    if (closed && points.length > 1) points.removeLast();
    return points;
  }

  /// A band of [halfWidth] down [points]: its edges wander a little, its
  /// width breathes, each vertex on the ground under it. Its ends fade
  /// unless [closed] (a loop has none).
  void _band(List<Vec2> points, double halfWidth, {required bool closed}) {
    final n = points.length;
    final phase = rand.range(0, math.pi * 2);
    final distances = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      distances[i] = distances[i - 1] + points[i - 1].distanceTo(points[i]);
    }
    final total = distances.last;
    final fade = math.min(halfWidth * 1.4, total / 2.5);
    final lefts = <Vec2>[];
    final rights = <Vec2>[];
    final us = <double>[];
    for (var i = 0; i < n; i++) {
      final before = points[closed ? (i - 1 + n) % n : math.max(0, i - 1)];
      final after = points[closed ? (i + 1) % n : math.min(n - 1, i + 1)];
      final tangent = (after - before).normalized(const Vec2(1, 0));
      final normal = Vec2(-tangent.y, tangent.x);
      final d = distances[i];
      final wander = math.sin(d * 0.9 + phase) * 0.07 +
          math.sin(d * 2.3 + phase * 1.7) * 0.04;
      final width = halfWidth *
          (1 +
              0.1 * math.sin(d * 1.7 + phase * 0.6) +
              0.06 * math.sin(d * 3.1 + phase * 2.3));
      final middle = points[i] + normal * wander;
      lefts.add(middle - normal * width);
      rights.add(middle + normal * width);
      us.add(closed
          ? 0.5
          : d < fade
              ? 0.25 * d / fade
              : total - d < fade
                  ? 1 - 0.25 * (total - d) / fade
                  : 0.5);
    }
    final legs = closed ? n : n - 1;
    for (var i = 0; i < legs; i++) {
      final j = (i + 1) % n;
      _vertex(lefts[i], us[i], 0);
      _vertex(rights[i], us[i], 1);
      _vertex(rights[j], us[j], 1);
      _vertex(lefts[i], us[i], 0);
      _vertex(rights[j], us[j], 1);
      _vertex(lefts[j], us[j], 0);
    }
  }

  /// A few scuffed three-toed prints round [at], where a hen of [radius]
  /// stands and shifts her feet. None on water.
  void prints(Vec2 at, double radius) {
    if (_wet(at)) return;
    final size = radius / 1.5;
    final count = 4 + rand.below(3);
    for (var k = 0; k < count; k++) {
      final angle = rand.range(0, math.pi * 2);
      final heel = at +
          Vec2(math.cos(angle), math.sin(angle)) *
              (rand.range(0.2, 0.62) * radius);
      if (_wet(heel)) continue;
      final heading = rand.range(0, math.pi * 2);
      final scale = size * rand.range(0.85, 1.1);
      // Three toes fanned forward, the middle one longest.
      for (final (turn, length) in const [
        (-0.62, 0.24),
        (0.0, 0.3),
        (0.62, 0.24)
      ]) {
        final dir = Vec2(math.cos(heading + turn), math.sin(heading + turn));
        final side = Vec2(-dir.y, dir.x) * (0.05 * scale);
        _vertex(heel + side, 0.5, 0.5, lift: printLift);
        _vertex(heel - side, 0.5, 0.5, lift: printLift);
        _vertex(heel + dir * (length * scale), 0.5, 0.5, lift: printLift);
      }
    }
  }

  void _vertex(Vec2 p, double u, double v, {double lift = lift}) {
    _positions.addAll([p.x, groundAt(p) + lift, p.y]);
    _uvs.addAll([u, v]);
  }

  /// The triangles, their normals the ground's own under each corner
  /// (lit like the turf it lies on, both faces drawn).
  tjs.BufferGeometry geometry() {
    final normals = <double>[];
    for (var i = 0; i < _positions.length; i += 3) {
      final slope = hole.hasRelief
          ? hole.groundGradientAt(Vec2(_positions[i], _positions[i + 2]))
          : Vec2.zero;
      final length = math.sqrt(slope.x * slope.x + 1 + slope.y * slope.y);
      normals.addAll([-slope.x / length, 1 / length, -slope.y / length]);
    }
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(_positions, 3, false))
      ..setAttributeFromString(
          'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false))
      ..setAttributeFromString(
          'uv', tjs.Float32BufferAttribute.fromList(_uvs, 2, false));
  }
}

// ---- shape helpers -------------------------------------------------------------------------

/// A ring of [dashes] arcs between [inner] and [outer], each filling
/// [fill] of its share of the circle, as one flat geometry (in its own XY
/// plane, like the ring geometries).
tjs.BufferGeometry _dashedRing(
    double inner, double outer, int dashes, double fill) {
  final positions = <double>[];
  final normals = <double>[];
  const steps = 8;
  for (var d = 0; d < dashes; d++) {
    final start = d / dashes * math.pi * 2;
    final sweep = fill / dashes * math.pi * 2;
    for (var i = 0; i < steps; i++) {
      final a0 = start + i / steps * sweep;
      final a1 = start + (i + 1) / steps * sweep;
      final p = [
        (math.cos(a0) * inner, math.sin(a0) * inner),
        (math.cos(a0) * outer, math.sin(a0) * outer),
        (math.cos(a1) * outer, math.sin(a1) * outer),
        (math.cos(a1) * inner, math.sin(a1) * inner),
      ];
      for (final index in const [0, 1, 2, 0, 2, 3]) {
        positions.addAll([p[index].$1, p[index].$2, 0]);
        normals.addAll([0, 0, 1]);
      }
    }
  }
  return tjs.BufferGeometry()
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false));
}

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
/// A pond's surface traced over a grid (marching squares, each crossing
/// found along its cell edge by bisection), in the plane's local
/// coordinates round [center] (x across, y = the game's -y): any outline,
/// convex or not, holes and all. Indexed, so the ripple stays seamless.
tjs.BufferGeometry _tracedWaterGeometry(WaterShape shape, Vec2 center,
    {List<List<Vec2>>? shore}) {
  const cell = 0.3;
  final box = _waterBox(shape);
  final x0 = box.min.x - cell;
  final y0 = box.min.y - cell;
  final cols = ((box.width + cell * 2) / cell).ceil();
  final rows = ((box.height + cell * 2) / cell).ceil();
  bool inside(Vec2 p) => shape.contains(p);
  final grid = List<bool>.generate(
      (cols + 1) * (rows + 1),
      (i) => inside(
          Vec2(x0 + (i % (cols + 1)) * cell, y0 + (i ~/ (cols + 1)) * cell)));
  bool at(int c, int r) => grid[r * (cols + 1) + c];
  Vec2 corner(int c, int r) => Vec2(x0 + c * cell, y0 + r * cell);

  final positions = <double>[];
  final indices = <int>[];
  final ids = <int, int>{};
  // The outline's vertices (the crossings), and its segments, one per pair
  // of crossings that follow each other round a cell's polygon.
  final crossings = <int>{};
  final segments = <(int, int)>[];
  // Vertices keyed on a half-cell lattice: corners at even, edge
  // crossings at odd coordinates, so neighbours share them.
  int vertex(int key, Vec2 p) => ids.putIfAbsent(key, () {
        positions.addAll([p.x - center.x, center.y - p.y, 0]);
        return positions.length ~/ 3 - 1;
      });
  int cornerId(int c, int r) =>
      vertex((r * 2) * (cols * 2 + 3) + c * 2, corner(c, r));
  int crossId(int c0, int r0, int c1, int r1) {
    final a = corner(c0, r0);
    final b = corner(c1, r1);
    var lo = a, hi = b;
    if (!at(c0, r0)) {
      lo = b;
      hi = a;
    }
    for (var k = 0; k < 6; k++) {
      final m = (lo + hi) * 0.5;
      if (inside(m)) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final id = vertex((r0 + r1) * (cols * 2 + 3) + (c0 + c1), (lo + hi) * 0.5);
    crossings.add(id);
    return id;
  }

  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final s0 = at(c, r), s1 = at(c + 1, r);
      final s2 = at(c + 1, r + 1), s3 = at(c, r + 1);
      final index = (s0 ? 1 : 0) | (s1 ? 2 : 0) | (s2 ? 4 : 0) | (s3 ? 8 : 0);
      if (index == 0) continue;
      int v0() => cornerId(c, r);
      int v1() => cornerId(c + 1, r);
      int v2() => cornerId(c + 1, r + 1);
      int v3() => cornerId(c, r + 1);
      int e0() => crossId(c, r, c + 1, r);
      int e1() => crossId(c + 1, r, c + 1, r + 1);
      int e2() => crossId(c, r + 1, c + 1, r + 1);
      int e3() => crossId(c, r, c, r + 1);
      final polygon = switch (index) {
        15 => [v0(), v1(), v2(), v3()],
        1 => [v0(), e0(), e3()],
        2 => [e0(), v1(), e1()],
        4 => [e1(), v2(), e2()],
        8 => [e3(), e2(), v3()],
        3 => [v0(), v1(), e1(), e3()],
        6 => [e0(), v1(), v2(), e2()],
        12 => [e3(), e1(), v2(), v3()],
        9 => [v0(), e0(), e2(), v3()],
        7 => [v0(), v1(), v2(), e2(), e3()],
        14 => [e0(), v1(), v2(), v3(), e3()],
        13 => [v0(), e0(), e1(), v2(), v3()],
        11 => [v0(), v1(), e1(), e2(), v3()],
        5 => [v0(), e0(), e1(), v2(), e2(), e3()],
        10 => [e0(), v1(), e1(), e2(), v3(), e3()],
        _ => const <int>[],
      };
      for (var i = 0; i < polygon.length; i++) {
        final a = polygon[i];
        final b = polygon[(i + 1) % polygon.length];
        if (crossings.contains(a) && crossings.contains(b)) {
          segments.add((a, b));
        }
      }
      for (var i = 1; i + 1 < polygon.length; i++) {
        var a = polygon[0], b = polygon[i], d = polygon[i + 1];
        // Wound to face the plane's +z (the world's up once laid down).
        final ax = positions[a * 3], ay = positions[a * 3 + 1];
        final cross = (positions[b * 3] - ax) * (positions[d * 3 + 1] - ay) -
            (positions[b * 3 + 1] - ay) * (positions[d * 3] - ax);
        if (cross < 0) {
          final t = b;
          b = d;
          d = t;
        }
        indices.addAll([a, b, d]);
      }
    }
  }
  if (shore != null) {
    Vec2 world(int id) =>
        Vec2(center.x + positions[id * 3], center.y - positions[id * 3 + 1]);
    shore.addAll(_chainShore(segments, world));
  }
  final normals = List<double>.filled(positions.length, 0);
  for (var i = 2; i < normals.length; i += 3) {
    normals[i] = 1;
  }
  return tjs.BufferGeometry()
    ..setIndex(indices)
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false));
}

/// The foam ribbon's fade across its width: white, opaque at the edge (v
/// 0), gone at the inner side (v 1). Made per pond, so it dies with the
/// hole's materials.
tjs.DataTexture _foamFadeTexture() {
  const width = 4;
  const height = 32;
  final bitmap = _Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    final v = (y + 0.5) / height;
    final t = (1 - v).clamp(0.0, 1.0);
    final alpha = (255 * 0.95 * t * t * (3 - 2 * t)).round();
    for (var x = 0; x < width; x++) {
      bitmap.set(x, y, 0xFFFFFF, alpha);
    }
  }
  return bitmap.texture();
}

/// The traced outline's [segments] (pairs of vertex ids) chained into its
/// loops, each in order, as world points.
List<List<Vec2>> _chainShore(List<(int, int)> segments, Vec2 Function(int) at) {
  final next = <int, List<int>>{};
  for (final (a, b) in segments) {
    next.putIfAbsent(a, () => []).add(b);
    next.putIfAbsent(b, () => []).add(a);
  }
  final seen = <int>{};
  final loops = <List<Vec2>>[];
  for (final start in next.keys) {
    if (seen.contains(start)) continue;
    final loop = <int>[start];
    seen.add(start);
    var previous = -1;
    var current = start;
    while (true) {
      final options = next[current]!;
      final step = options.firstWhere(
          (id) => id != previous && !seen.contains(id),
          orElse: () => -1);
      if (step < 0) break;
      loop.add(step);
      seen.add(step);
      previous = current;
      current = step;
    }
    // Crossings bunched at a corner (a few millimetres apart) make segments
    // whose direction means nothing: keep one point of each bunch.
    const merge = 0.06;
    final points = <Vec2>[];
    for (final id in loop) {
      final p = at(id);
      if (points.isEmpty || points.last.distanceTo(p) > merge) points.add(p);
    }
    while (points.length > 1 && points.first.distanceTo(points.last) <= merge) {
      points.removeLast();
    }
    if (points.length >= 3) loops.add(points);
  }
  return loops;
}

/// A pond's foam as one ribbon along each loop of its shore: [width] wide
/// inward, mitred at the joints, opaque at the edge and fading to nothing
/// inside (its v runs 0 at the edge to 1 in). The foam painted on the
/// water's vertices sawtoothed along a diagonal shore: the grid is coarser
/// than the band.
tjs.BufferGeometry? _shoreRibbon(
    List<List<Vec2>> loops, WaterShape shape, double width, Vec2 center) {
  final positions = <double>[];
  final uvs = <double>[];
  final indices = <int>[];
  for (final loop in loops) {
    final n = loop.length;
    // Each segment's inward normal (the side the water is on).
    final normals = <Vec2>[];
    for (var i = 0; i < n; i++) {
      final a = loop[i];
      final b = loop[(i + 1) % n];
      final along = (b - a).normalized(const Vec2(1, 0));
      var normal = Vec2(-along.y, along.x);
      if (!shape.contains((a + b) * 0.5 + normal * 0.1)) normal = -normal;
      normals.add(normal);
    }
    final base = positions.length ~/ 3;
    for (var i = 0; i < n; i++) {
      final before = normals[(i - 1 + n) % n];
      final after = normals[i];
      final sum = before + after;
      final miter = sum.length < 1e-6 ? after : sum * (1 / sum.length);
      final scale = 1 / math.max(miter.dot(after), 0.5);
      final edge = loop[i];
      final inner = edge + miter * (width * scale);
      for (final (p, v) in [(edge, 0.0), (inner, 1.0)]) {
        positions.addAll([p.x - center.x, center.y - p.y, 0]);
        uvs.addAll([0.5, v]);
      }
    }
    for (var i = 0; i < n; i++) {
      final a = base + i * 2;
      final b = base + ((i + 1) % n) * 2;
      indices.addAll([a, b, a + 1, b, b + 1, a + 1]);
    }
  }
  if (indices.isEmpty) return null;
  final normals = List<double>.filled(positions.length, 0);
  for (var i = 2; i < normals.length; i += 3) {
    normals[i] = 1;
  }
  return tjs.BufferGeometry()
    ..setIndex(indices)
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false))
    ..setAttributeFromString(
        'uv', tjs.Float32BufferAttribute.fromList(uvs, 2, false));
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
/// bumpers standing free, nor ledges: both levels of a tier are the
/// course.
class _ReachGrid {
  _ReachGrid._(this.bounds, this.cell, this.cols, this.rows, this._reachable);

  /// The grid's step, world units.
  final double cell;

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

  static _ReachGrid of(HoleDef hole, {double cell = 0.5}) {
    final bounds = hole.bounds;
    final cols = math.max(1, (bounds.width / cell).ceil());
    final rows = math.max(1, (bounds.height / cell).ceil());
    final reachable = Uint8List(cols * rows);
    final segments = <(Vec2, Vec2)>[
      for (final wall in hole.walls)
        if (!wall.ledge) (wall.a, wall.b),
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

    // Each wall's box, so a step far from it skips the crossing test.
    final boxes = [
      for (final (p, q) in segments)
        (
          math.min(p.x, q.x) - cell,
          math.min(p.y, q.y) - cell,
          math.max(p.x, q.x) + cell,
          math.max(p.y, q.y) + cell,
        ),
    ];
    bool crossesWall(Vec2 a, Vec2 b) {
      for (var i = 0; i < segments.length; i++) {
        final (x0, y0, x1, y1) = boxes[i];
        if (a.x < x0 || a.x > x1 || a.y < y0 || a.y > y1) continue;
        final (p, q) = segments[i];
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
    return _ReachGrid._(bounds, cell, cols, rows, reachable);
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

// ---- the tiers' pieces -------------------------------------------------------------

/// A stretch of a wall at one level, or one that climbs: [low] and [high]
/// are the tiers either side (the rail stands on [high], the step's face
/// below it), or [profile] holds the levels sampled evenly along a climb
/// (a ramp's side). [atStart] and [atEnd] say whether the stretch ends
/// where the wall does (there the rail runs long to close the corner).
class _WallRun {
  _WallRun(this.from, this.to, this.low, this.high,
      {this.profile = const [], this.atStart = true, this.atEnd = true});

  final Vec2 from;
  final Vec2 to;
  final double low;
  final double high;
  final List<(double, double)> profile;
  final bool atStart;
  final bool atEnd;

  bool get varying => profile.isNotEmpty;

  /// On the green's own level, no step under it.
  bool get flat => !varying && low.abs() < 1e-6 && high.abs() < 1e-6;
}

/// Quads poured into one plain geometry (positions, normals, UVs): the
/// tiers' faces. Each quad's triangles are wound to face its normal; a
/// quad with no normal faces up.
class _QuadSink {
  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _uvs = [];

  bool get isEmpty => _positions.isEmpty;

  void quad(List<(double, double, double)> corners, Vec2? out,
      List<(double, double)> uv) {
    final n = out == null ? (0.0, 1.0, 0.0) : (out.x, 0.0, out.y);
    // Wind (0, 1, 2) to face n, else turn it round.
    final (ax, ay, az) = corners[0];
    final (bx, by, bz) = corners[1];
    final (cx, cy, cz) = corners[2];
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final vx = cx - ax, vy = cy - ay, vz = cz - az;
    final facing = (uy * vz - uz * vy) * n.$1 +
        (uz * vx - ux * vz) * n.$2 +
        (ux * vy - uy * vx) * n.$3;
    final order =
        facing >= 0 ? const [0, 1, 2, 0, 2, 3] : const [0, 2, 1, 0, 3, 2];
    for (final k in order) {
      final (x, y, z) = corners[k];
      _positions.addAll([x, y, z]);
      _normals.addAll([n.$1, n.$2, n.$3]);
      _uvs.addAll([uv[k].$1, uv[k].$2]);
    }
  }

  tjs.Mesh? mesh(String name, tjs.Material material) {
    if (_positions.isEmpty) return null;
    return tjs.Mesh(
      tjs.BufferGeometry()
        ..setAttributeFromString('position',
            tjs.Float32BufferAttribute.fromList(_positions, 3, false))
        ..setAttributeFromString(
            'normal', tjs.Float32BufferAttribute.fromList(_normals, 3, false))
        ..setAttributeFromString(
            'uv', tjs.Float32BufferAttribute.fromList(_uvs, 2, false)),
      material,
    )
      ..name = name
      ..castShadow = true
      ..receiveShadow = true;
  }
}
