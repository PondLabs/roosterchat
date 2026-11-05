// The hole from above, small, in the corner under the course's chip: while
// the viewer aims with the nest out of sight (the close camera on a long
// hole), it shows the whole hole - its walls and water, the nest, the
// eggs - and where the arrow points, turned with the camera so that up on
// the map is ahead on the screen. The game hands the layer a frame after
// every rendered frame, like the nest's marker.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart'
    show Vec2;

import 'putt_art.dart';

/// What the map shows this frame.
@immutable
class PuttMiniMapFrame {
  final HoleDef hole;

  /// The camera's heading over the ground (a unit vector, game
  /// coordinates): it points up on the map.
  final Vec2 forward;

  final Vec2 mine;
  final Color tint;

  /// The other eggs on the green, and their colours.
  final List<(Vec2, Color)> others;

  /// The aim: its angle (the game's, radians) and power (0 to 1).
  final double aimAngle;
  final double aimPower;

  const PuttMiniMapFrame({
    required this.hole,
    required this.forward,
    required this.mine,
    required this.tint,
    required this.others,
    required this.aimAngle,
    required this.aimPower,
  });
}

/// Where the map sits on the screen: under the course's chip, top left.
const Rect puttMiniMapRect = Rect.fromLTWH(12, 72, 176, 132);

/// The map layer: nothing while there is no frame.
class PuttMiniMap extends StatelessWidget {
  final ValueListenable<PuttMiniMapFrame?> frame;

  const PuttMiniMap({super.key, required this.frame});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ValueListenableBuilder<PuttMiniMapFrame?>(
          valueListenable: frame,
          builder: (context, map, _) {
            if (map == null) return const SizedBox.shrink();
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: puttMiniMapRect,
                  child: CustomPaint(
                    key: const Key('putt-mini-map'),
                    painter: PuttMiniMapPainter(map),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Paints the map: the panel, the water, the walls, the nest, the eggs
/// and the arrow's heading.
class PuttMiniMapPainter extends CustomPainter {
  final PuttMiniMapFrame map;

  PuttMiniMapPainter(this.map);

  /// Where the game point [p] lands in a map of [size], given the hole's
  /// [centre], the camera's [forward] and the [scale] (pixels per unit).
  static Offset place(
      Vec2 p, Vec2 centre, Vec2 forward, double scale, Size size) {
    final d = p - centre;
    // The camera's right over the ground, then ahead is up.
    final right = Vec2(-forward.y, forward.x);
    return Offset(size.width / 2 + d.dot(right) * scale,
        size.height / 2 - d.dot(forward) * scale);
  }

  /// The pixels per unit that fit the hole's bounds, turned, into [size]
  /// with a margin.
  static double fit(HoleDef hole, Vec2 forward, Size size) {
    final b = hole.bounds;
    final centre = (b.min + b.max) * 0.5;
    final right = Vec2(-forward.y, forward.x);
    var spanX = 0.0;
    var spanY = 0.0;
    for (final corner in [
      b.min,
      Vec2(b.max.x, b.min.y),
      b.max,
      Vec2(b.min.x, b.max.y),
    ]) {
      final d = corner - centre;
      spanX = math.max(spanX, d.dot(right).abs());
      spanY = math.max(spanY, d.dot(forward).abs());
    }
    const margin = 10.0;
    return math.min((size.width / 2 - margin) / math.max(spanX, 1e-6),
        (size.height / 2 - margin) / math.max(spanY, 1e-6));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final panel =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas
      ..drawRRect(panel.shift(const Offset(0, 2)),
          Paint()..color = const Color(0x40000000))
      ..drawRRect(
          panel, Paint()..color = PuttPalette.ink.withValues(alpha: 0.86))
      ..drawRRect(
          panel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = PuttPalette.cream.withValues(alpha: 0.14))
      ..save()
      ..clipRRect(panel);

    final hole = map.hole;
    final forward = map.forward;
    final scale = fit(hole, forward, size);
    final b = hole.bounds;
    final centre = (b.min + b.max) * 0.5;
    Offset at(Vec2 p) => place(p, centre, forward, scale, size);

    // The table: the bounds, a soft turf.
    canvas.drawPath(
        Path()
          ..addPolygon([
            at(b.min),
            at(Vec2(b.max.x, b.min.y)),
            at(b.max),
            at(Vec2(b.min.x, b.max.y)),
          ], true),
        Paint()..color = const Color(0xFF5E9E45).withValues(alpha: 0.55));

    final water = Paint()..color = const Color(0xFF4AA3DF);
    for (final shape in hole.water) {
      switch (shape) {
        case WaterCircle(:final center, :final radius):
          canvas.drawCircle(at(center), radius * scale, water);
        case WaterRect(:final rect):
          canvas.drawPath(
              Path()
                ..addPolygon([
                  at(rect.min),
                  at(Vec2(rect.max.x, rect.min.y)),
                  at(rect.max),
                  at(Vec2(rect.min.x, rect.max.y)),
                ], true),
              water);
        case WaterPolygon(:final points):
          canvas.drawPath(
              Path()..addPolygon([for (final p in points) at(p)], true), water);
      }
    }

    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = PuttPalette.cream.withValues(alpha: 0.9);
    final bumper = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = PuttPalette.comb;
    for (final segment in hole.walls) {
      if (segment.ledge) continue;
      canvas.drawLine(
          at(segment.a), at(segment.b), segment.bumper ? bumper : wall);
    }
    for (final arc in hole.arcs) {
      const steps = 14;
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final angle = arc.startAngle + arc.sweep * i / steps;
        final p = at(
            arc.center + Vec2(math.cos(angle), math.sin(angle)) * arc.radius);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, arc.bumper ? bumper : wall);
    }

    // The nest: a dark cup ringed in straw, and its red flag.
    final nest = at(hole.nest.position);
    final cup = math.max(hole.nest.radius * scale, 3.5);
    canvas
      ..drawCircle(nest, cup + 1.5, Paint()..color = const Color(0xFFE8C77A))
      ..drawCircle(nest, cup, Paint()..color = const Color(0xFF2A1D14))
      ..drawPath(
          Path()
            ..moveTo(nest.dx, nest.dy - cup - 11)
            ..lineTo(nest.dx + 9, nest.dy - cup - 7.5)
            ..lineTo(nest.dx, nest.dy - cup - 4)
            ..close(),
          Paint()..color = PuttPalette.comb)
      ..drawLine(
          Offset(nest.dx, nest.dy - cup - 11),
          Offset(nest.dx, nest.dy),
          Paint()
            ..strokeWidth = 1.4
            ..color = PuttPalette.cream);

    for (final (position, colour) in map.others) {
      canvas
        ..drawCircle(at(position), 3.6, Paint()..color = PuttPalette.ink)
        ..drawCircle(at(position), 2.8, Paint()..color = colour);
    }

    // Mine, and where the arrow points: a ray as long as the pull is hard.
    final mine = at(map.mine);
    final heading = Vec2(math.cos(map.aimAngle), math.sin(map.aimAngle));
    final right = Vec2(-forward.y, forward.x);
    final along = Offset(heading.dot(right), -heading.dot(forward));
    final reach = 14 + map.aimPower.clamp(0.0, 1.0) * 34;
    final tip = mine + along * reach;
    final ray = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = PuttPalette.yolk;
    final side = Offset(-along.dy, along.dx);
    canvas
      ..drawLine(mine, tip, ray)
      ..drawPath(
          Path()
            ..moveTo((tip + along * 5).dx, (tip + along * 5).dy)
            ..lineTo((tip + side * 4).dx, (tip + side * 4).dy)
            ..lineTo((tip - side * 4).dx, (tip - side * 4).dy)
            ..close(),
          Paint()..color = PuttPalette.yolk)
      ..drawCircle(mine, 5.2, Paint()..color = PuttPalette.ink)
      ..drawCircle(mine, 4, Paint()..color = map.tint)
      ..restore();
  }

  @override
  bool shouldRepaint(PuttMiniMapPainter oldDelegate) => true;
}
