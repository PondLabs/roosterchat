// Where an egg can stand on a hole: the turf it can roll to from the tee.
//
// A flood fill over a half-unit grid, stopped by rails, rocks and water,
// carried through the rabbit holes and over ledges both ways (a step is not
// a rail: the turf on top of it is turf, even where only a kicker's flight
// reaches it). The physics asks it only for the eggs that leave the ground's rules behind (a
// Ghost Egg through a hedge, a Chicken Hop over it, a Rabbit Hole's
// landing): one that ends where no egg could have rolled (inside a rock, in
// a garden bed, past the fence) comes back out at the nearest turf.
//
// Worked out once per hole, the first time it is asked for. Pure Dart,
// like the rest of the core.
library;

import 'dart:math' as math;

import 'hole.dart';
import 'physics.dart';
import 'vec.dart';

class HoleReach {
  static const double cell = 0.5;

  static final Expando<HoleReach> _cache = Expando();

  /// The reach of [hole], for eggs of [config]'s radius.
  static HoleReach of(HoleDef hole, PhysicsConfig config) =>
      _cache[hole] ??= HoleReach._fill(hole, config.ballRadius);

  final Rect _bounds;
  final int _cols;
  final int _rows;
  final List<bool> _reached;

  HoleReach._(this._bounds, this._cols, this._rows, this._reached);

  Vec2 _center(int c, int r) =>
      Vec2(_bounds.min.x + (c + 0.5) * cell, _bounds.min.y + (r + 0.5) * cell);

  int? _cellOf(Vec2 p) {
    final c = ((p.x - _bounds.min.x) / cell).floor();
    final r = ((p.y - _bounds.min.y) / cell).floor();
    if (c < 0 || r < 0 || c >= _cols || r >= _rows) return null;
    return r * _cols + c;
  }

  /// Whether an egg can roll to [p] from the tee.
  bool at(Vec2 p) {
    final index = _cellOf(p);
    return index != null && _reached[index];
  }

  /// [p] itself when an egg can stand there, else the middle of the nearest
  /// cell one can (the first of them in grid order when several are as
  /// near).
  Vec2 nearest(Vec2 p) {
    if (at(p)) return p;
    Vec2? best;
    var bestDistance = double.infinity;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (!_reached[r * _cols + c]) continue;
        final center = _center(c, r);
        final distance = (center - p).lengthSquared;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = center;
        }
      }
    }
    return best ?? p;
  }

  static HoleReach _fill(HoleDef hole, double ballRadius) {
    final bounds = hole.bounds;
    final cols = (bounds.width / cell).ceil();
    final rows = (bounds.height / cell).ceil();
    final reach =
        HoleReach._(bounds, cols, rows, List<bool>.filled(cols * rows, false));
    final clear = ballRadius * 0.9;

    bool open(Vec2 p) {
      if (hole.water.any((w) => w.contains(p))) return false;
      for (final wall in hole.walls) {
        if (wall.ledge) continue;
        if (_segmentDistance(p, wall.a, wall.b) < clear) return false;
      }
      for (final arc in hole.arcs) {
        if (_arcDistance(p, arc) < clear) return false;
      }
      return true;
    }

    bool crosses(Vec2 a, Vec2 b, Vec2 p, Vec2 q) {
      double side(Vec2 o, Vec2 u, Vec2 v) => (u - o).cross(v - o);
      return (side(p, q, a) > 0) != (side(p, q, b) > 0) &&
          (side(a, b, p) > 0) != (side(a, b, q) > 0);
    }

    bool step(Vec2 from, Vec2 to) {
      for (final wall in hole.walls) {
        if (!wall.ledge && crosses(from, to, wall.a, wall.b)) return false;
      }
      return true;
    }

    final queue = <int>[];
    void seed(Vec2 p) {
      final index = reach._cellOf(p);
      if (index == null || reach._reached[index]) return;
      reach._reached[index] = true;
      queue.add(index);
    }

    seed(hole.tee);
    for (var head = 0; head < queue.length; head++) {
      final index = queue[head];
      final c = index % cols;
      final r = index ~/ cols;
      final here = reach._center(c, r);
      for (final pair in hole.portals) {
        if (here.distanceTo(pair.a) <= pair.radius) seed(pair.b);
        if (here.distanceTo(pair.b) <= pair.radius) seed(pair.a);
      }
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nc = c + dc;
        final nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
        final next = nr * cols + nc;
        if (reach._reached[next]) continue;
        final there = reach._center(nc, nr);
        if (!open(there) || !step(here, there)) continue;
        reach._reached[next] = true;
        queue.add(next);
      }
    }
    return reach;
  }

  static double _segmentDistance(Vec2 p, Vec2 a, Vec2 b) {
    final ab = b - a;
    final length2 = ab.lengthSquared;
    final t =
        length2 < 1e-18 ? 0.0 : ((p - a).dot(ab) / length2).clamp(0.0, 1.0);
    return p.distanceTo(a + ab * t);
  }

  /// Distance from [p] to [arc]: to its line where [p]'s bearing lies in
  /// its span, else to its nearer end. A full circle (a rock, a bale) is
  /// solid: nothing inside it is clear of it.
  static double _arcDistance(Vec2 p, WallArc arc) {
    final span = arcSpan(arc);
    final offset = p - arc.center;
    if (span.$2 >= 2 * math.pi - 1e-9) {
      return math.max(0, offset.length - arc.radius);
    }
    var turn = (math.atan2(offset.y, offset.x) - span.$1) % (2 * math.pi);
    if (turn < 0) turn += 2 * math.pi;
    if (turn <= span.$2) return (offset.length - arc.radius).abs();
    Vec2 end(double angle) =>
        arc.center + Vec2(math.cos(angle), math.sin(angle)) * arc.radius;
    return math.min(
        p.distanceTo(end(span.$1)), p.distanceTo(end(span.$1 + span.$2)));
  }
}
