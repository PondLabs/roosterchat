// The constellation of the login page, still and faint: what the space
// column shows below its last bubble (docs/whos-around-rail.md), so what is
// left of the column reads as sky over the houses rather than as nothing.
// Drawn once in Dart, not with the login page's shader, which animates at 60
// frames a second and would keep the app drawing all day.
import 'dart:math';

import 'package:flutter/material.dart';

class NightSky extends StatelessWidget {
  const NightSky({super.key, this.opacity = 0.14});

  /// How bright the brightest star is, against the column's surface.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: NightSkyPainter(
            color: Theme.of(context).colorScheme.onSurface, opacity: opacity),
      ),
    );
  }
}

class NightSkyPainter extends CustomPainter {
  const NightSkyPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  /// The same sky every time: a fixed seed, and the stars drawn from the
  /// front of one list, so a taller column adds stars without moving the
  /// ones already there.
  static const int seed = 1917;

  /// Stars per square pixel of column: one every 1600 px².
  static const double density = 1 / 1600;

  static const int maxStars = 160;

  /// Two stars closer than this are joined by a line.
  static const double reach = 44;

  static final List<Offset> _unitStars = _makeUnitStars();
  static final List<double> _radii = _makeRadii();

  static List<Offset> _makeUnitStars() {
    final random = Random(seed);
    return [
      for (var i = 0; i < maxStars; i++)
        Offset(random.nextDouble(), random.nextDouble())
    ];
  }

  static List<double> _makeRadii() {
    final random = Random(seed + 1);
    return [for (var i = 0; i < maxStars; i++) 0.7 + random.nextDouble() * 1.3];
  }

  /// Where the stars are in a sky of [size]: the first [count] of the unit
  /// square's, scaled. Also the test's way of knowing what was drawn.
  static List<Offset> starsFor(Size size) {
    final count =
        (size.width * size.height * density).round().clamp(0, maxStars);
    return [
      for (var i = 0; i < count; i++)
        Offset(_unitStars[i].dx * size.width, _unitStars[i].dy * size.height)
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stars = starsFor(size);
    final line = Paint()
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < stars.length; i++) {
      for (var j = i + 1; j < stars.length; j++) {
        final d = (stars[i] - stars[j]).distance;
        if (d >= reach) continue;
        line.color = color.withValues(alpha: opacity * 0.45 * (1 - d / reach));
        canvas.drawLine(stars[i], stars[j], line);
      }
    }
    final dot = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < stars.length; i++) {
      // The small ones fainter, as far stars are.
      final radius = _radii[i];
      dot.color = color.withValues(
          alpha: opacity * (0.45 + 0.55 * (radius - 0.7) / 1.3));
      canvas.drawCircle(stars[i], radius, dot);
    }
  }

  @override
  bool shouldRepaint(NightSkyPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}
