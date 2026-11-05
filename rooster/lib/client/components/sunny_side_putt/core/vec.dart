// 2D vector math for Sunny Side Putt's core. Pure Dart: no Flutter imports,
// so the physics, the hole model and the rules engine run headless in tests
// and on every platform the app ships to.
//
// Determinism contract: every operation is plain IEEE-754 arithmetic
// (+, -, *, /, sqrt) in a fixed order, so the same inputs always produce the
// same outputs on the same build. Nothing here reads the clock or generates
// randomness (see `rng.dart` for the seeded generator).
library;

import 'dart:math' as math;

/// An immutable 2D vector of doubles, in abstract world units.
///
/// Holes are authored in units, roughly one unit per egg-and-a-half of room;
/// the renderer scales them to pixels. All core math uses [Vec2].
class Vec2 {
  final double x;
  final double y;

  const Vec2(this.x, this.y);

  static const Vec2 zero = Vec2(0, 0);

  /// Parses `[x, y]` as produced by [toJson].
  factory Vec2.fromList(List<Object?> list) =>
      Vec2((list[0] as num).toDouble(), (list[1] as num).toDouble());

  factory Vec2.fromMap(Map<Object?, Object?> map) =>
      Vec2((map['x'] as num).toDouble(), (map['y'] as num).toDouble());

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
  Vec2 operator *(double factor) => Vec2(x * factor, y * factor);
  Vec2 operator /(double factor) => Vec2(x / factor, y / factor);

  /// Negation, so `-v` reads like math.
  Vec2 operator -() => Vec2(-x, -y);

  double dot(Vec2 other) => x * other.x + y * other.y;

  /// The 2D cross product (z component): sign tells which side of [this]
  /// (as a direction) [other] is on.
  double cross(Vec2 other) => x * other.y - y * other.x;

  double get lengthSquared => x * x + y * y;
  double get length => math.sqrt(lengthSquared);

  /// The unit vector pointing the same way, or [fallback] when this vector
  /// is (numerically) zero, so normalization never produces NaN.
  Vec2 normalized([Vec2 fallback = Vec2.zero]) {
    final len = length;
    if (len < epsilon) return fallback;
    return Vec2(x / len, y / len);
  }

  /// `v.normalized()` (or zero) scaled to [length].
  Vec2 scaledTo(double length) {
    final dir = normalized();
    return Vec2(dir.x * length, dir.y * length);
  }

  /// Rotated by [radians]. Coordinates match the screen (x right, y down),
  /// so a positive angle turns clockwise as drawn; angles come from
  /// `atan2(y, x)` and stay consistent everywhere in the core.
  Vec2 rotated(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Vec2(x * c - y * s, x * s + y * c);
  }

  /// The angle in radians of the vector's direction, in (-pi, pi].
  double get angle => math.atan2(y, x);

  double distanceTo(Vec2 other) => (this - other).length;

  /// Linear interpolation toward [other]; [t] of 0 gives this, 1 gives
  /// [other]. Not clamped, so overshooting extrapolates.
  Vec2 lerp(Vec2 other, double t) =>
      Vec2(x + (other.x - x) * t, y + (other.y - y) * t);

  /// Component-wise bounds, for clamping points into a box.
  Vec2 clamped(Vec2 min, Vec2 max) => Vec2(
        x.clamp(min.x, max.x).toDouble(),
        y.clamp(min.y, max.y).toDouble(),
      );

  /// A vector of length [distance] pointing at [target].
  Vec2 towards(Vec2 target, double distance) =>
      (target - this).scaledTo(distance);

  bool get isZero => lengthSquared < epsilon * epsilon;

  /// Perpendicular of unit length (90 rotation, same orientation rule as
  /// [rotated]). Falls back to a fixed axis for the zero vector.
  Vec2 get perpendicular => Vec2(-y, x).normalized(Vec2(1, 0));

  /// Equality up to the physics epsilon, for tests and dedup checks.
  bool approximates(Vec2 other, [double epsilon = epsilon]) =>
      (x - other.x).abs() < epsilon && (y - other.y).abs() < epsilon;

  /// `[x, y]`, JSON-safe: always doubles, never ints after a round trip.
  List<double> toList() => [x, y];

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  @override
  String toString() => 'Vec2($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  /// Comparison slack used across the core. About a thousandth of an egg
  /// radius: comfortably above double noise, far below anything visible.
  static const double epsilon = 1e-9;
}

/// An axis-aligned rectangle, used for hole bounds and rectangular water.
class Rect {
  final Vec2 min;
  final Vec2 max;

  const Rect(this.min, this.max);

  static const Rect zero = Rect(Vec2.zero, Vec2.zero);

  factory Rect.fromCenter(Vec2 center, double halfWidth, double halfHeight) =>
      Rect(center - Vec2(halfWidth, halfHeight),
          center + Vec2(halfWidth, halfHeight));

  double get width => max.x - min.x;
  double get height => max.y - min.y;
  Vec2 get center => (min + max) / 2;

  bool contains(Vec2 p) =>
      p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y;

  /// True when the rectangle overlaps the circle at [center] with
  /// [radius] (the distance from the circle's center to the box).
  bool overlapsCircle(Vec2 center, double radius) {
    final cx = center.x.clamp(min.x, max.x).toDouble();
    final cy = center.y.clamp(min.y, max.y).toDouble();
    final dx = center.x - cx;
    final dy = center.y - cy;
    return dx * dx + dy * dy <= radius * radius;
  }

  Map<String, Object?> toJson() => {'min': min.toJson(), 'max': max.toJson()};

  factory Rect.fromJson(Map<Object?, Object?> json) => Rect(
      Vec2.fromMap(json['min'] as Map<Object?, Object?>),
      Vec2.fromMap(json['max'] as Map<Object?, Object?>));

  @override
  String toString() => 'Rect($min, $max)';
}
