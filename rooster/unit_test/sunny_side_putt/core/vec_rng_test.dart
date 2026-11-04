// Tests for the match-seeded RNG and the vector math it leans on: stream
// determinism, state serialization, and the web-safety invariants that keep
// replays identical whether the host runs on the VM or in a browser.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/rng.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

void main() {
  group('GameRng', () {
    test('same seed, same stream', () {
      final a = GameRng.seeded(20260101);
      final b = GameRng.seeded(20260101);
      final streamA = [for (var i = 0; i < 1000; i++) a.nextDouble()];
      final streamB = [for (var i = 0; i < 1000; i++) b.nextDouble()];
      expect(streamB, streamA);
    });

    test('different seeds diverge', () {
      final a = GameRng.seeded(1);
      final b = GameRng.seeded(2);
      expect(
        [for (var i = 0; i < 100; i++) a.nextDouble()],
        isNot([for (var i = 0; i < 100; i++) b.nextDouble()]),
      );
    });

    test('nearby seeds diverge (seed expansion works)', () {
      final a = GameRng.seeded(1000);
      final b = GameRng.seeded(1001);
      final first = [for (var i = 0; i < 8; i++) a.nextUint32()].join(',');
      final second = [for (var i = 0; i < 8; i++) b.nextUint32()].join(',');
      expect(second, isNot(first));
    });

    test('nextDouble stays in [0, 1) and is spread out', () {
      final rng = GameRng.seeded(42);
      final values = [for (var i = 0; i < 10000; i++) rng.nextDouble()];
      for (final value in values) {
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(1));
      }
      final above = values.where((v) => v > 0.5).length;
      // 10000 draws: within 5% of half, comfortably.
      expect(above, inExclusiveRange(4600, 5400));
    });

    test('nextInt stays in range and covers it', () {
      final rng = GameRng.seeded(7);
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        final value = rng.nextInt(5);
        expect(value, inExclusiveRange(-1, 5));
        seen.add(value);
      }
      expect(seen, {0, 1, 2, 3, 4});
    });

    test('nextSymmetric is centered', () {
      final rng = GameRng.seeded(9);
      final values = [for (var i = 0; i < 10000; i++) rng.nextSymmetric(0.05)];
      for (final value in values) {
        expect(value.abs(), lessThanOrEqualTo(0.05));
      }
      final positive = values.where((v) => v > 0).length;
      expect(positive, inExclusiveRange(4600, 5400));
    });

    test('state round-trips and continues the stream', () {
      final rng = GameRng.seeded(777);
      for (var i = 0; i < 50; i++) {
        rng.nextDouble();
      }
      final saved =
          GameRng.fromList(jsonDecode(jsonEncode(rng.toList())) as List);
      final expected = [for (var i = 0; i < 20; i++) rng.nextDouble()];
      final restored = [for (var i = 0; i < 20; i++) saved.nextDouble()];
      expect(restored, expected);
    });

    test('string seeds are stable and different per text', () {
      final a = GameRng.seededText('sunny-side-putt');
      final b = GameRng.seededText('sunny-side-putt');
      final c = GameRng.seededText('sunny-side-putt ');
      expect(
        [for (var i = 0; i < 50; i++) a.nextDouble()],
        [for (var i = 0; i < 50; i++) b.nextDouble()],
      );
      expect(
        [for (var i = 0; i < 50; i++) a.nextDouble()],
        isNot([for (var i = 0; i < 50; i++) c.nextDouble()]),
      );
    });
  });

  group('Vec2', () {
    test('arithmetic', () {
      const a = Vec2(1, 2);
      const b = Vec2(3, -1);
      expect(a + b, const Vec2(4, 1));
      expect(a - b, const Vec2(-2, 3));
      expect(a * 2, const Vec2(2, 4));
      expect(b.dot(a), 1);
      expect(
        a.cross(b),
        1 * (-1) - 2 * 3,
      );
      expect(-a, const Vec2(-1, -2));
    });

    test('length, normalization, angle', () {
      const v = Vec2(3, 4);
      expect(v.length, 5);
      expect(v.normalized().approximates(const Vec2(0.6, 0.8)), isTrue);
      expect(v.scaledTo(10).approximates(const Vec2(6, 8)), isTrue);
      expect(const Vec2(0, 0).normalized(), Vec2.zero); // no NaN
      expect(const Vec2(1, 0).angle, 0);
      expect(const Vec2(0, 1).angle, closeTo(math.pi / 2, 1e-9));
    });

    test('rotation is exact at quarter turns (screen-convention y-down)', () {
      const v = Vec2(1, 0);
      expect(v.rotated(math.pi / 2).approximates(const Vec2(0, 1)), isTrue);
      expect(v.rotated(math.pi).approximates(const Vec2(-1, 0)), isTrue);
      expect(
        v.rotated(3 * math.pi / 2).approximates(const Vec2(0, -1)),
        isTrue,
      );
    });

    test('lerp, distance, clamp', () {
      const a = Vec2(0, 0);
      const b = Vec2(10, 20);
      expect(a.lerp(b, 0.25), const Vec2(2.5, 5));
      expect(a.distanceTo(b), closeTo(math.sqrt(500), 1e-9));
      expect(
        const Vec2(50, -5).clamped(const Vec2(0, 0), const Vec2(10, 10)),
        const Vec2(10, 0),
      );
    });

    test('JSON round trip preserves doubles exactly', () {
      const v = Vec2(3.14159, -2.71828);
      final restored =
          Vec2.fromList(jsonDecode(jsonEncode(v.toList())) as List);
      expect(restored, v);
    });
  });

  group('Rect', () {
    test('contains and overlapsCircle', () {
      final rect = Rect(const Vec2(0, 0), const Vec2(10, 10));
      expect(rect.contains(const Vec2(5, 5)), isTrue);
      expect(rect.contains(const Vec2(10.1, 5)), isFalse);
      expect(rect.overlapsCircle(const Vec2(11, 5), 1.2), isTrue);
      expect(rect.overlapsCircle(const Vec2(12, 5), 1.2), isFalse);
      expect(rect.overlapsCircle(const Vec2(-0.5, -0.5), 0.72), isTrue);
    });
  });
}
