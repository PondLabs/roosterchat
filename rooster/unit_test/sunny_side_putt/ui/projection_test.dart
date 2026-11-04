// The 3D camera's projection: the invariants the renderer leans on.
// Pure math - no Flame, no pixels - so the camera's behavior is pinned
// without a screen.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_camera.dart';

void main() {
  group('putt camera projection', () {
    test('the point under the target projects to the middle of the screen', () {
      final camera = PuttCamera(viewport: const ui.Size(800, 600))
        ..distance = 40;
      for (final yaw in [for (var i = 0; i < 12; i++) i / 12 * 2 * math.pi]) {
        for (final pitch in [35.0, 55.0, 70.0]) {
          camera
            ..yaw = yaw
            ..pitchDeg = pitch;
          final screen = camera.project(Vec2.zero);
          expect(screen.dx, closeTo(400, 0.01), reason: 'yaw $yaw');
          expect(screen.dy, closeTo(300, 0.01), reason: 'yaw $yaw');
        }
      }
    });

    test('a ground grid unprojects back onto itself', () {
      final camera = PuttCamera(viewport: const ui.Size(800, 600))
        ..yaw = 0.7
        ..pitchDeg = 48
        ..distance = 45;
      for (final x in [-14.0, -3.0, 0.0, 5.5, 17.0]) {
        for (final y in [-9.0, 0.0, 8.0]) {
          final world = Vec2(x, y);
          final screen = camera.project(world);
          final back = camera.screenToWorld(screen);
          expect(back, isNotNull);
          expect(back!.x, closeTo(x, 1e-4), reason: 'at ($x, $y)');
          expect(back.y, closeTo(y, 1e-4), reason: 'at ($x, $y)');
        }
      }
    });

    test('closer ground points sort at a nearer depth', () {
      final camera = PuttCamera(viewport: const ui.Size(800, 600))
        ..yaw = 0.4
        ..pitchDeg = 55
        ..distance = 40;
      final near = camera.depthOf(const Vec2(2, -1));
      final far = camera.depthOf(const Vec2(2, 9));
      expect(near, lessThan(far));
    });

    test('tilt squashes the ground view monotonically', () {
      // The same ground segment seen from a lower tilt covers more
      // screen height than from a steeper one.
      double spread(double pitch) {
        final camera = PuttCamera(viewport: const ui.Size(800, 600))
          ..yaw = 0
          ..pitchDeg = pitch
          ..distance = 40;
        final top = camera.project(const Vec2(0, -5));
        final bottom = camera.project(const Vec2(0, 5));
        return (bottom.dy - top.dy).abs();
      }

      expect(spread(40), lessThan(spread(55)));
      expect(spread(55), lessThan(spread(70)));
    });

    test('zoom moves the screen radii wider as the distance closes', () {
      final camera = PuttCamera(viewport: const ui.Size(800, 600))
        ..yaw = 0
        ..pitchDeg = 55;
      double spanAt(double distance) {
        camera..distance = distance;
        final outer = camera.project(const Vec2(2, 0));
        final center = camera.project(Vec2.zero);
        return (outer - center).distance;
      }

      expect(spanAt(120), lessThan(spanAt(60)));
      expect(spanAt(60), lessThan(spanAt(30)));
      expect(spanAt(30), lessThan(spanAt(15)));
    });

    test('a full-frame camera sweep never projects a NaN', () {
      final camera = PuttCamera(viewport: const ui.Size(800, 600))
        ..fitToHole(const Rect(Vec2(-2, -3), Vec2(50, 29)));
      var checked = 0;
      for (var yaw = 0.0; yaw < 2 * math.pi; yaw += math.pi / 12) {
        for (final pitch in [35.0, 55.0, 70.0]) {
          camera
            ..yaw = yaw
            ..pitchDeg = pitch;
          for (final point in [
            const Vec2(2, 3),
            const Vec2(45, 2),
            const Vec2(-2, 24),
            const Vec2(24, 13),
            const Vec2(24, 13),
            const Vec2(50, -3),
          ]) {
            final screen = camera.project(point);
            expect(screen.dx.isFinite, isTrue, reason: 'yaw $yaw');
            expect(screen.dy.isFinite, isTrue, reason: 'yaw $yaw');
            checked++;
          }
        }
      }
      expect(checked, greaterThan(60));
    });
  });
}
