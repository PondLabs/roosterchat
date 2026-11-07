// The table takes the hole's shape. Where the walls close a stretch of the
// bounding rectangle off from the tee, and that stretch reaches the
// rectangle's edge, it is carved out of the table altogether: the meadow
// shows below it and the table's skirt follows the fairway's outline, the
// sculpted platform of a real course. A stretch walled off in the middle of
// the green (an island) stays on the table as a garden bed.
//
// The shape is a mask on a quarter-unit grid over the bounds grown by the
// table's lip: the cells the egg can reach, plus the islands, grown half a
// unit so every rail has a ledge to stand on, plus the lip wherever the
// green comes up to the edge. Marching squares turn the mask into the top
// (turf inside the bounds, timber on the lip) and the outline the skirt
// drops from.
part of '../putt_world3d.dart';

class _TableShape {
  _TableShape._(
      this.bounds, this.domain, this.cols, this.rows, this._kept, this._reach);

  static const double cell = 0.25;

  /// The lip: how far the table runs past the green's edge (a whole number
  /// of cells, so the green's edge falls on a cell boundary).
  static const double lip = 1.25;

  final Rect bounds;
  final Rect domain;
  final int cols;
  final int rows;
  final Uint8List _kept;
  final _ReachGrid _reach;

  /// Whether the egg can roll to [p] from the tee.
  bool reachableAt(Vec2 p) => _reach.reachableAt(p);

  /// Whether [p] is on the table (the green, a garden island, the lip).
  bool keptAt(Vec2 p) {
    final col = ((p.x - domain.min.x) / cell).floor();
    final row = ((p.y - domain.min.y) / cell).floor();
    if (col < 0 || row < 0 || col >= cols || row >= rows) return false;
    return _kept[row * cols + col] == 1;
  }

  /// Whether [p] lies inside the bounds but was carved off the table.
  bool carvedAt(Vec2 p) => bounds.contains(p) && !keptAt(p);

  /// Whether any of the bounds was carved away.
  late final bool carved = () {
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final center = _centerOf(col, row);
        if (bounds.contains(center) && _kept[row * cols + col] == 0) {
          return true;
        }
      }
    }
    return false;
  }();

  Vec2 _centerOf(int col, int row) => Vec2(
      domain.min.x + (col + 0.5) * cell, domain.min.y + (row + 0.5) * cell);

  static _TableShape of(HoleDef hole) {
    final bounds = hole.bounds;
    final reach = _ReachGrid.of(hole, cell: cell);
    final domain = Rect(
        bounds.min - const Vec2(lip, lip), bounds.max + const Vec2(lip, lip));
    final cols = (domain.width / cell).round();
    final rows = (domain.height / cell).round();
    final pad = (lip / cell).round();
    final inner = Uint8List(cols * rows); // reach (+ islands), in bounds
    final innerCols = reach.cols;
    final innerRows = reach.rows;

    // The exterior: unreachable cells that touch the bounds' edge, and all
    // the unreachable cells joined to them. The rest of the unreachable
    // ground is an island.
    final exterior = Uint8List(innerCols * innerRows);
    final queue = <int>[];
    bool reachable(int c, int r) => reach._reachable[r * innerCols + c] == 1;
    for (var r = 0; r < innerRows; r++) {
      for (var c = 0; c < innerCols; c++) {
        final edge =
            r == 0 || c == 0 || r == innerRows - 1 || c == innerCols - 1;
        if (edge && !reachable(c, r)) {
          exterior[r * innerCols + c] = 1;
          queue.add(r * innerCols + c);
        }
      }
    }
    var head = 0;
    while (head < queue.length) {
      final index = queue[head++];
      final c = index % innerCols;
      final r = index ~/ innerCols;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nc = c + dc;
        final nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= innerCols || nr >= innerRows) continue;
        final next = nr * innerCols + nc;
        if (exterior[next] == 1 || reachable(nc, nr)) continue;
        exterior[next] = 1;
        queue.add(next);
      }
    }
    for (var r = 0; r < innerRows; r++) {
      for (var c = 0; c < innerCols; c++) {
        if (exterior[r * innerCols + c] == 0) {
          inner[(r + pad) * cols + (c + pad)] = 1;
        }
      }
    }

    // Grown two cells inside the bounds, so the rails along a carved edge
    // stand on timber, not on air.
    final kept = Uint8List(cols * rows);
    for (var r = pad; r < pad + innerRows; r++) {
      for (var c = pad; c < pad + innerCols; c++) {
        var near = false;
        for (var dr = -2; dr <= 2 && !near; dr++) {
          for (var dc = -2; dc <= 2 && !near; dc++) {
            final rr = r + dr;
            final cc = c + dc;
            if (rr < pad || cc < pad || rr >= pad + innerRows) continue;
            if (cc >= pad + innerCols) continue;
            if (inner[rr * cols + cc] == 1) near = true;
          }
        }
        if (near) kept[r * cols + c] = 1;
      }
    }
    // The lip: wherever the green (or its ledge) meets the bounds' edge,
    // the table runs on past it.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final insideR = r >= pad && r < pad + innerRows;
        final insideC = c >= pad && c < pad + innerCols;
        if (insideR && insideC) continue;
        final rr = r.clamp(pad, pad + innerRows - 1);
        final cc = c.clamp(pad, pad + innerCols - 1);
        if (kept[rr * cols + cc] == 1) kept[r * cols + c] = 1;
      }
    }
    return _TableShape._(bounds, domain, cols, rows, kept, reach);
  }

  // ---- marching squares ---------------------------------------------------------

  /// Whether the cell at ([col], [row]) is in [mask]'s set (out of range
  /// is never in it, so outlines close).
  bool _in(int col, int row, bool Function(int col, int row) mask) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) return false;
    return mask(col, row);
  }

  bool _keptCell(int col, int row) => _kept[row * cols + col] == 1;

  bool _insideCell(int col, int row) => bounds.contains(_centerOf(col, row));

  /// The top as triangles (x, z pairs in a flat list), for cells passing
  /// [mask]: the fill of marching squares over the cell centres.
  List<double> _fill(bool Function(int col, int row) mask) {
    final out = <double>[];
    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final s0 = _in(col, row, mask);
        final s1 = _in(col + 1, row, mask);
        final s2 = _in(col + 1, row + 1, mask);
        final s3 = _in(col, row + 1, mask);
        final index = (s0 ? 1 : 0) | (s1 ? 2 : 0) | (s2 ? 4 : 0) | (s3 ? 8 : 0);
        if (index == 0) continue;
        final x0 = domain.min.x + (col + 0.5) * cell;
        final z0 = domain.min.y + (row + 0.5) * cell;
        final x1 = x0 + cell;
        final z1 = z0 + cell;
        final xm = x0 + cell / 2;
        final zm = z0 + cell / 2;
        final v0 = (x0, z0), v1 = (x1, z0), v2 = (x1, z1), v3 = (x0, z1);
        final e0 = (xm, z0), e1 = (x1, zm), e2 = (xm, z1), e3 = (x0, zm);
        final polygon = switch (index) {
          15 => [v0, v1, v2, v3],
          1 => [v0, e0, e3],
          2 => [e0, v1, e1],
          4 => [e1, v2, e2],
          8 => [e3, e2, v3],
          3 => [v0, v1, e1, e3],
          6 => [e0, v1, v2, e2],
          12 => [e3, e1, v2, v3],
          9 => [v0, e0, e2, v3],
          7 => [v0, v1, v2, e2, e3],
          14 => [e0, v1, v2, v3, e3],
          13 => [v0, e0, e1, v2, v3],
          11 => [v0, v1, e1, e2, v3],
          5 => [v0, e0, e1, v2, e2, e3],
          10 => [e0, v1, e1, e2, v3, e3],
          _ => const <(double, double)>[],
        };
        // A fan, wound to face up (+y) once x/z map to the world.
        for (var i = 1; i + 1 < polygon.length; i++) {
          final a = polygon[0];
          final b = polygon[i + 1];
          final c = polygon[i];
          out.addAll([a.$1, a.$2, b.$1, b.$2, c.$1, c.$2]);
        }
      }
    }
    return out;
  }

  /// The outline of the table (marching squares' contour over the kept
  /// cells), as segments: x0, z0, x1, z1.
  List<double> _outline() {
    final out = <double>[];
    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final s0 = _in(col, row, _keptCell);
        final s1 = _in(col + 1, row, _keptCell);
        final s2 = _in(col + 1, row + 1, _keptCell);
        final s3 = _in(col, row + 1, _keptCell);
        final index = (s0 ? 1 : 0) | (s1 ? 2 : 0) | (s2 ? 4 : 0) | (s3 ? 8 : 0);
        if (index == 0 || index == 15) continue;
        final x0 = domain.min.x + (col + 0.5) * cell;
        final z0 = domain.min.y + (row + 0.5) * cell;
        final x1 = x0 + cell;
        final z1 = z0 + cell;
        final xm = x0 + cell / 2;
        final zm = z0 + cell / 2;
        final e0 = (xm, z0), e1 = (x1, zm), e2 = (xm, z1), e3 = (x0, zm);
        final segments = switch (index) {
          1 || 14 => [(e0, e3)],
          2 || 13 => [(e0, e1)],
          4 || 11 => [(e1, e2)],
          8 || 7 => [(e2, e3)],
          3 || 12 => [(e1, e3)],
          6 || 9 => [(e0, e2)],
          5 => [(e0, e1), (e2, e3)],
          10 => [(e1, e2), (e3, e0)],
          _ => const <((double, double), (double, double))>[],
        };
        for (final (a, b) in segments) {
          out.addAll([a.$1, a.$2, b.$1, b.$2]);
        }
      }
    }
    return out;
  }

  /// The top: the turf inside the bounds (UVs over the bounds, for the
  /// lawn's texture), or the timber lip outside them.
  tjs.BufferGeometry top({required bool turf, HoleDef? relief}) =>
      _topGeometry(topArrays(turf: turf, relief: relief));

  /// [top]'s positions, normals and uvs: pure Dart, so the turf's can be
  /// worked out off the UI isolate.
  (List<double>, List<double>, List<double>) topArrays(
      {required bool turf, HoleDef? relief}) {
    var flat = _fill(
        (col, row) => _keptCell(col, row) && (_insideCell(col, row) == turf));
    final positions = <double>[];
    final normals = <double>[];
    final uvs = <double>[];
    // The turf rides the hole's relief: each vertex at the ground's height,
    // its normal from the ground's gradient. A tier's edge is a step, not
    // a slope: the triangles are cut along every terrace edge and ramp
    // side, and each piece is laid by the tier it lies on, so the two
    // levels part exactly on the line.
    final hilly = relief != null && relief.hasRelief;
    final tiered = relief != null &&
        (relief.terraces.isNotEmpty || relief.ramps.isNotEmpty);
    if (tiered) {
      flat = _cutAlongSteps(flat, [
        ..._stepEdges(relief),
        // A ramp's ends are level with what they meet, but cut there too,
        // each piece then takes the ramp's profile exactly.
        for (final ramp in relief.ramps) ...[
          (ramp.sides.$1.$1, ramp.sides.$2.$1),
          ramp.top,
        ],
      ]);
    }
    for (var i = 0; i < flat.length; i += 6) {
      final _Tier? tier;
      if (tiered) {
        tier = _tierUnder(
            relief,
            Vec2((flat[i] + flat[i + 2] + flat[i + 4]) / 3,
                (flat[i + 1] + flat[i + 3] + flat[i + 5]) / 3));
      } else {
        tier = null;
      }
      for (var k = i; k < i + 6; k += 2) {
        final x = flat[k];
        final z = flat[k + 1];
        if (hilly) {
          final point = Vec2(x, z);
          var height = 0.0;
          var g = Vec2.zero;
          for (final hill in relief.hills) {
            height += hill.heightAt(point);
            g += hill.gradientAt(point);
          }
          if (tier != null) {
            height += tier.heightAt(point);
            g += tier.gradientAt(point);
          }
          final n = math.sqrt(g.x * g.x + 1 + g.y * g.y);
          positions.addAll([x, height, z]);
          normals.addAll([-g.x / n, 1 / n, -g.y / n]);
        } else {
          positions.addAll([x, 0, z]);
          normals.addAll([0, 1, 0]);
        }
        if (turf) {
          uvs.addAll([
            (x - bounds.min.x) / bounds.width,
            1 - (z - bounds.min.y) / bounds.height,
          ]);
        } else {
          uvs.addAll([x / 2.4, z / 2.4]);
        }
      }
    }
    return (positions, normals, uvs);
  }

  /// The skirt: the outline dropped to the meadow, each face turned out.
  tjs.BufferGeometry skirt(double height) {
    final lines = _outline();
    final positions = <double>[];
    final normals = <double>[];
    final uvs = <double>[];
    for (var i = 0; i < lines.length; i += 4) {
      var ax = lines[i],
          az = lines[i + 1],
          bx = lines[i + 2],
          bz = lines[i + 3];
      final dx = bx - ax;
      final dz = bz - az;
      final length = math.sqrt(dx * dx + dz * dz);
      if (length < 1e-6) continue;
      // Out is the side off the table.
      var nx = dz / length;
      var nz = -dx / length;
      final probe = Vec2(
          (ax + bx) / 2 + nx * cell * 0.4, (az + bz) / 2 + nz * cell * 0.4);
      if (keptAt(probe)) {
        nx = -nx;
        nz = -nz;
        final tx = ax, tz = az;
        ax = bx;
        az = bz;
        bx = tx;
        bz = tz;
      }
      final u0 = (ax + az) / 3;
      final u1 = (bx + bz) / 3;
      // Two triangles, wound so the face looks out.
      final quad = [
        (ax, 0.0, az, u0, 1.0),
        (bx, 0.0, bz, u1, 1.0),
        (bx, -height, bz, u1, 0.0),
        (ax, 0.0, az, u0, 1.0),
        (bx, -height, bz, u1, 0.0),
        (ax, -height, az, u0, 0.0),
      ];
      for (final (x, y, z, u, v) in quad) {
        positions.addAll([x, y, z]);
        normals.addAll([nx, 0, nz]);
        uvs.addAll([u, v]);
      }
    }
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
      ..setAttributeFromString(
          'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false))
      ..setAttributeFromString(
          'uv', tjs.Float32BufferAttribute.fromList(uvs, 2, false));
  }

  /// The stretches of the wall [a]-[b] that stand on the table (a side of
  /// them kept): a rail over carved-away ground would float.
  List<(Vec2, Vec2)> keptRuns(Vec2 a, Vec2 b) {
    final run = b - a;
    final length = run.length;
    if (length < 1e-6) return const [];
    final direction = run * (1 / length);
    final side = Vec2(-direction.y, direction.x) * 0.45;
    final steps = math.max(1, (length / (cell * 2)).ceil());
    final runs = <(Vec2, Vec2)>[];
    double? start;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = a + run * t;
      final on = keptAt(p + side) || keptAt(p - side);
      if (on && start == null) start = t;
      if ((!on || i == steps) && start != null) {
        final end = on ? t : (i - 0.5) / steps;
        if (end > start) runs.add((a + run * start, a + run * end));
        start = null;
      }
    }
    return runs;
  }
}

// ---- the tiers' steps ---------------------------------------------------------------

/// The tier under a piece of turf: a terrace (flat at its height) or a
/// ramp, laid by its profile along its axis with the width ignored, so the
/// piece's corners on the ramp's side keep the ramp's height and the side
/// stays a crisp step.
class _Tier {
  _Tier.terrace(Terrace this.terrace) : ramp = null;
  _Tier.ramp(Ramp this.ramp) : terrace = null;

  final Terrace? terrace;
  final Ramp? ramp;

  double heightAt(Vec2 point) => terrace?.height ?? ramp!.profileAt(point);

  Vec2 gradientAt(Vec2 point) =>
      terrace != null ? Vec2.zero : ramp!.profileGradientAt(point);
}

/// The tier holding [point] - the highest, as the ground takes it - or
/// null on the green's own level.
_Tier? _tierUnder(HoleDef hole, Vec2 point) {
  _Tier? tier;
  var best = 0.0;
  for (final terrace in hole.terraces) {
    if (terrace.height > best && terrace.contains(point)) {
      best = terrace.height;
      tier = _Tier.terrace(terrace);
    }
  }
  for (final ramp in hole.ramps) {
    final rise = ramp.heightAt(point);
    if (rise > best) {
      best = rise;
      tier = _Tier.ramp(ramp);
    }
  }
  return tier;
}

/// Where the ground can step: every terrace edge and both sides of every
/// ramp (a ramp's foot and top are level with what they meet).
List<(Vec2, Vec2)> _stepEdges(HoleDef hole) => [
      for (final terrace in hole.terraces)
        for (var i = 0; i < terrace.points.length; i++) terrace.edge(i),
      for (final ramp in hole.ramps) ...[ramp.sides.$1, ramp.sides.$2],
    ];

/// [flat] (triangles as x, z pairs) with every triangle a step's line
/// crosses cut along that line, the pieces fanned back into triangles in
/// the same winding. Each piece then lies wholly on one side of every
/// step, so it takes one tier's height.
List<double> _cutAlongSteps(List<double> flat, List<(Vec2, Vec2)> edges) {
  final boxes = [
    for (final (a, b) in edges)
      (
        math.min(a.x, b.x) - 0.01,
        math.min(a.y, b.y) - 0.01,
        math.max(a.x, b.x) + 0.01,
        math.max(a.y, b.y) + 0.01,
      ),
  ];
  final out = <double>[];
  for (var i = 0; i < flat.length; i += 6) {
    final minX = math.min(flat[i], math.min(flat[i + 2], flat[i + 4]));
    final maxX = math.max(flat[i], math.max(flat[i + 2], flat[i + 4]));
    final minZ = math.min(flat[i + 1], math.min(flat[i + 3], flat[i + 5]));
    final maxZ = math.max(flat[i + 1], math.max(flat[i + 3], flat[i + 5]));
    List<List<(double, double)>>? pieces;
    for (var e = 0; e < edges.length; e++) {
      final (x0, z0, x1, z1) = boxes[e];
      if (x1 < minX || x0 > maxX || z1 < minZ || z0 > maxZ) continue;
      pieces ??= [
        [
          (flat[i], flat[i + 1]),
          (flat[i + 2], flat[i + 3]),
          (flat[i + 4], flat[i + 5]),
        ],
      ];
      final (a, b) = edges[e];
      pieces = [for (final piece in pieces) ..._splitByLine(piece, a, b)];
    }
    if (pieces == null) {
      for (var k = i; k < i + 6; k++) {
        out.add(flat[k]);
      }
      continue;
    }
    for (final piece in pieces) {
      for (var k = 1; k + 1 < piece.length; k++) {
        out.addAll([
          piece[0].$1,
          piece[0].$2,
          piece[k].$1,
          piece[k].$2,
          piece[k + 1].$1,
          piece[k + 1].$2,
        ]);
      }
    }
  }
  return out;
}

/// A convex [polygon] cut by the line through [a] and [b]: the part on each
/// side (one piece when the line misses it), the cyclic order kept.
List<List<(double, double)>> _splitByLine(
    List<(double, double)> polygon, Vec2 a, Vec2 b) {
  final ux = b.x - a.x;
  final uz = b.y - a.y;
  final sides = [
    for (final (x, z) in polygon) ux * (z - a.y) - uz * (x - a.x),
  ];
  const eps = 1e-9;
  var positive = false;
  var negative = false;
  for (final side in sides) {
    if (side > eps) positive = true;
    if (side < -eps) negative = true;
  }
  if (!positive || !negative) return [polygon];
  final one = <(double, double)>[];
  final other = <(double, double)>[];
  for (var i = 0; i < polygon.length; i++) {
    final j = (i + 1) % polygon.length;
    final p = polygon[i];
    final q = polygon[j];
    final sp = sides[i];
    final sq = sides[j];
    if (sp >= -eps) one.add(p);
    if (sp <= eps) other.add(p);
    if ((sp > eps && sq < -eps) || (sp < -eps && sq > eps)) {
      final t = sp / (sp - sq);
      final cut = (p.$1 + (q.$1 - p.$1) * t, p.$2 + (q.$2 - p.$2) * t);
      one.add(cut);
      other.add(cut);
    }
  }
  return [
    if (one.length >= 3) one,
    if (other.length >= 3) other,
  ];
}

/// A top's arrays as the geometry the renderer takes.
tjs.BufferGeometry _topGeometry(
        (List<double>, List<double>, List<double>) arrays) =>
    tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(arrays.$1, 3, false))
      ..setAttributeFromString(
          'normal', tjs.Float32BufferAttribute.fromList(arrays.$2, 3, false))
      ..setAttributeFromString(
          'uv', tjs.Float32BufferAttribute.fromList(arrays.$3, 2, false));
