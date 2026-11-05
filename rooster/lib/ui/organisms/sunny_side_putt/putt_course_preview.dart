// A hole from above, as a picture for the course cards: the launch
// options' course picker and casual's next-course vote. The pictures are
// PNGs drawn ahead of time by `tools/gen_putt_previews_test.dart` from the
// course data (the 3D world needs a GPU); a hole without one is painted
// live by the same painter, so a new course still shows its green.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart'
    show Vec2;

import 'putt_art.dart';
import 'putt_mini_map.dart';

/// The pictures' pixel size (16:10).
const Size puttPreviewSize = Size(320, 200);

/// Where the hole [holeId]'s picture lives.
String puttHolePreviewAsset(String holeId) =>
    'assets/sunny_side_putt/previews/$holeId.png';

/// The hole's picture: its PNG, or the painter when it has none.
class PuttHolePreview extends StatelessWidget {
  final HoleDef hole;

  const PuttHolePreview({super.key, required this.hole});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: puttPreviewSize.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          puttHolePreviewAsset(hole.id),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              CustomPaint(painter: PuttHolePreviewPainter(hole)),
        ),
      ),
    );
  }
}

/// A course's colours, after its corner of the farm (world3d/theme.dart's
/// turf and meadow, and its rails). The hole's id prefix names the course.
// ponytail: copied from the private _Theme in world3d/theme.dart; keep in
// step by hand, or make the theme public if the two drift.
({Color meadow, Color light, Color dark, Color fringe, Color rail}) _look(
    String holeId) {
  final prefix = holeId.split('_').first;
  return switch (prefix) {
    'maze' => (
        meadow: const Color(0xFF8BA951),
        light: const Color(0xFF7CBB37),
        dark: const Color(0xFF68AB2D),
        fringe: const Color(0xFF4F9223),
        rail: const Color(0xFF3E6E1E),
      ),
    'pond' => (
        meadow: const Color(0xFF7DB85C),
        light: const Color(0xFF6CBB3E),
        dark: const Color(0xFF5AAB35),
        fringe: const Color(0xFF45922A),
        rail: const Color(0xFFBDB6A8),
      ),
    'road' => (
        meadow: const Color(0xFF92B85A),
        light: const Color(0xFF6AB836),
        dark: const Color(0xFF57A72E),
        fringe: const Color(0xFF428E24),
        rail: const Color(0xFFF1EEE8),
      ),
    'barn' => (
        meadow: const Color(0xFF6FAE4A),
        light: const Color(0xFF72C63E),
        dark: const Color(0xFF5EB234),
        fringe: const Color(0xFF47962A),
        rail: const Color(0xFFA53A2C),
      ),
    _ => (
        meadow: const Color(0xFF8FC25C),
        light: const Color(0xFF73BE3A),
        dark: const Color(0xFF60B130),
        fringe: const Color(0xFF4B9A26),
        rail: const Color(0xFFB98A55),
      ),
  };
}

/// Paints the hole from above: the meadow, the green's turf (mown in
/// stripes, its relief lit from the top left), the water, the boosts, the
/// rails, the hazards, the tee and the nest. Turned so the hole fills the
/// picture, the tee low and the nest high where that fits as well.
class PuttHolePreviewPainter extends CustomPainter {
  final HoleDef hole;

  PuttHolePreviewPainter(this.hole);

  /// The heading that fills [size] best (the four axes), the one that
  /// puts the nest above the tee winning a tie.
  static Vec2 heading(HoleDef hole, Size size) {
    final toNest = hole.nest.position - hole.tee;
    Vec2? best;
    var bestScore = -1.0;
    for (final f in const [Vec2(0, 1), Vec2(0, -1), Vec2(1, 0), Vec2(-1, 0)]) {
      final score = PuttMiniMapPainter.fit(hole, f, size) *
          (toNest.dot(f) > 0 ? 1.0 : 0.98);
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }
    return best!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final look = _look(hole.id);
    final forward = heading(hole, size);
    final right = Vec2(-forward.y, forward.x);
    final scale = PuttMiniMapPainter.fit(hole, forward, size) * 0.9;
    final b = hole.bounds;
    final centre = (b.min + b.max) * 0.5;
    Offset at(Vec2 p) =>
        PuttMiniMapPainter.place(p, centre, forward, scale, size);
    Path polygon(List<Vec2> points) =>
        Path()..addPolygon([for (final p in points) at(p)], true);
    final corners = [
      b.min,
      Vec2(b.max.x, b.min.y),
      b.max,
      Vec2(b.min.x, b.max.y)
    ];
    final unit = scale; // pixels per game unit

    // The meadow, darker towards the corners.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(colors: [
            look.meadow,
            Color.lerp(look.meadow, PuttPalette.ink, 0.35)!,
          ], radius: 0.9)
              .createShader(Offset.zero & size));

    // The table: a shadow, its fringe, then the turf inside the bounds.
    final tableRect = polygon(corners).getBounds();
    final table =
        RRect.fromRectAndRadius(tableRect, Radius.circular(unit * 0.4));
    final lip = table.inflate(unit * 0.5);
    canvas
      ..drawRRect(lip.shift(Offset(0, unit * 0.35)),
          Paint()..color = const Color(0x55000000))
      ..drawRRect(lip, Paint()..color = look.fringe)
      ..save()
      ..clipRRect(table);

    // Turf cells: mown stripes a unit wide across the play, lit by the
    // slope (the light from the picture's top left) and raised by height.
    final light = (forward - right).normalized(const Vec2(0, 1));
    const cell = 2.0;
    final reach = _Reach(hole);
    final paint = Paint();
    for (var y = tableRect.top; y < tableRect.bottom; y += cell) {
      for (var x = tableRect.left; x < tableRect.right; x += cell) {
        final sx = x + cell / 2 - size.width / 2;
        final sy = size.height / 2 - (y + cell / 2);
        final p = centre + right * (sx / scale) + forward * (sy / scale);
        final stripe = ((p.dot(forward)).floor()).isEven;
        var colour = !reach.at(p)
            ? Color.lerp(look.fringe, look.meadow, 0.4)!
            : stripe
                ? look.light
                : look.dark;
        if (hole.hasRelief) {
          final height = hole.groundHeightAt(p);
          final shade =
              (-hole.groundGradientAt(p).dot(light) * 0.9 + height * 0.12)
                  .clamp(-0.45, 0.45);
          colour = shade >= 0
              ? Color.lerp(colour, const Color(0xFFFFF6C8), shade)!
              : Color.lerp(colour, const Color(0xFF14301A), -shade)!;
        }
        canvas.drawRect(
            Rect.fromLTWH(x, y, cell + 0.5, cell + 0.5), paint..color = colour);
      }
    }
    canvas.restore();

    // Water: a deep rim, a bright pool.
    final pool = Paint()..color = PuttPalette.water;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, unit * 0.18)
      ..color = PuttPalette.waterDeep;
    for (final shape in hole.water) {
      final path = switch (shape) {
        WaterCircle(:final center, :final radius) => Path()
          ..addOval(Rect.fromCircle(center: at(center), radius: radius * unit)),
        WaterRect(:final rect) => polygon([
            rect.min,
            Vec2(rect.max.x, rect.min.y),
            rect.max,
            Vec2(rect.min.x, rect.max.y),
          ]),
        WaterPolygon(:final points) => polygon(points),
      };
      canvas
        ..drawPath(path, pool)
        ..drawPath(path, rim);
    }

    // Boosts: a yolk strip with chevrons down it.
    for (final boost in hole.boosts) {
      final axis = (boost.to - boost.from).normalized(const Vec2(1, 0));
      final side = Vec2(-axis.y, axis.x) * (boost.width / 2);
      canvas.drawPath(
          polygon([
            boost.from + side,
            boost.to + side,
            boost.to - side,
            boost.from - side,
          ]),
          Paint()..color = PuttPalette.yolk.withValues(alpha: 0.75));
      final length = (boost.to - boost.from).length;
      final chevron = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, unit * 0.12)
        ..color = PuttPalette.shell;
      for (var t = 0.4; t < length; t += 0.9) {
        final tip = boost.from + axis * t;
        final back = tip - axis * (boost.width * 0.3);
        canvas.drawPath(
            Path()
              ..moveTo(at(back + side * 0.6).dx, at(back + side * 0.6).dy)
              ..lineTo(at(tip).dx, at(tip).dy)
              ..lineTo(at(back - side * 0.6).dx, at(back - side * 0.6).dy),
            chevron);
      }
    }

    // Kickers: a timber ramp.
    for (final kicker in hole.kickers) {
      final axis = (kicker.to - kicker.from).normalized(const Vec2(1, 0));
      final side = Vec2(-axis.y, axis.x) * (kicker.width / 2);
      canvas.drawPath(
          polygon([
            kicker.from + side,
            kicker.to + side,
            kicker.to - side,
            kicker.from - side,
          ]),
          Paint()..color = const Color(0xFFC79A5E));
    }

    // The rails: a shadow, then the rail. Ledges are drawn as a thin drop.
    final railWidth = math.max(2.6, unit * 0.32);
    Paint rail(Color colour, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colour;
    final shadow = rail(const Color(0x66000000), railWidth);
    final plain = rail(look.rail, railWidth);
    final bumper = rail(PuttPalette.comb, railWidth);
    final ledge = rail(const Color(0x8014301A), math.max(1.4, unit * 0.14));
    final drop = Offset(railWidth * 0.35, railWidth * 0.5);
    Path arcPath(WallArc arc) {
      final steps = math.max(8, (arc.sweep.abs() * arc.radius * 4).ceil());
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final angle = arc.startAngle + arc.sweep * i / steps;
        final p = at(
            arc.center + Vec2(math.cos(angle), math.sin(angle)) * arc.radius);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    for (final pass in [0, 1]) {
      for (final segment in hole.walls) {
        if (segment.ledge) {
          if (pass == 1) canvas.drawLine(at(segment.a), at(segment.b), ledge);
          continue;
        }
        canvas.drawLine(
            at(segment.a) + (pass == 0 ? drop : Offset.zero),
            at(segment.b) + (pass == 0 ? drop : Offset.zero),
            pass == 0 ? shadow : (segment.bumper ? bumper : plain));
      }
      for (final arc in hole.arcs) {
        final path = arcPath(arc);
        canvas.drawPath(pass == 0 ? path.shift(drop) : path,
            pass == 0 ? shadow : (arc.bumper ? bumper : plain));
      }
    }

    // Hazards and helpers: the movers at their first stop, the wells, the
    // portals, the "?" boxes.
    for (final obstacle in hole.obstacles) {
      if (obstacle.stops.isEmpty) continue;
      final c = at(obstacle.stops.first.at);
      canvas
        ..drawCircle(c + drop, obstacle.radius * unit,
            shadow..style = PaintingStyle.fill)
        ..drawCircle(c, obstacle.radius * unit,
            Paint()..color = const Color(0xFF8A5A3B));
      shadow.style = PaintingStyle.stroke;
    }
    for (final well in hole.wells) {
      canvas.drawCircle(
          at(well.position),
          well.radius * unit,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xAA2A1D14),
              const Color(0x002A1D14),
            ]).createShader(Rect.fromCircle(
                center: at(well.position), radius: well.radius * unit)));
    }
    for (final portal in hole.portals) {
      for (final end in [portal.a, portal.b]) {
        canvas
          ..drawCircle(at(end), portal.radius * unit,
              Paint()..color = const Color(0xFF6B4BC8))
          ..drawCircle(at(end), portal.radius * unit * 0.55,
              Paint()..color = const Color(0xFFC9B8FF));
      }
    }
    for (final box in hole.boxes) {
      final r = math.max(3.0, box.radius * unit);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCircle(center: at(box.position), radius: r),
              Radius.circular(r * 0.3)),
          Paint()..color = PuttPalette.yolk);
    }

    // The tee: a cream mat with the egg on it.
    final tee = at(hole.tee);
    final mat = math.max(5.0, unit * 0.55);
    canvas
      ..drawRRect(
          RRect.fromRectAndRadius(Rect.fromCircle(center: tee, radius: mat),
              Radius.circular(mat * 0.35)),
          Paint()..color = PuttPalette.cream.withValues(alpha: 0.9))
      ..drawOval(
          Rect.fromCenter(center: tee, width: mat * 0.9, height: mat * 1.15),
          Paint()..color = PuttPalette.shell)
      ..drawOval(
          Rect.fromCenter(center: tee, width: mat * 0.9, height: mat * 1.15),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = PuttPalette.stone);

    // The nest: straw, a dark cup, the red flag.
    final nest = at(hole.nest.position);
    final cup = math.max(hole.nest.radius * unit * 0.6, 3.5);
    final pole = math.max(14.0, unit * 1.6);
    canvas
      ..drawCircle(nest, cup * 1.6, Paint()..color = const Color(0xFFE8C77A))
      ..drawCircle(
          nest,
          cup * 1.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFFB08A3E))
      ..drawCircle(nest, cup, Paint()..color = const Color(0xFF2A1D14))
      ..drawLine(
          nest,
          nest - Offset(0, pole),
          Paint()
            ..strokeWidth = 1.6
            ..color = PuttPalette.shell)
      ..drawPath(
          Path()
            ..moveTo(nest.dx, nest.dy - pole)
            ..lineTo(nest.dx + pole * 0.6, nest.dy - pole * 0.78)
            ..lineTo(nest.dx, nest.dy - pole * 0.56)
            ..close(),
          Paint()..color = PuttPalette.comb);
  }

  @override
  bool shouldRepaint(PuttHolePreviewPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

/// Where the egg can roll from the tee, on a quarter-unit grid over the
/// bounds (the rails and arcs block, a ledge's drop does not): the rest of
/// the table is shown as rough, the way the 3D world carves it away.
class _Reach {
  static const double cell = 0.25;
  final Vec2 origin;
  final int cols;
  final int rows;
  final List<bool> _kept;

  factory _Reach(HoleDef hole) {
    final b = hole.bounds;
    final cols = math.max(1, ((b.max.x - b.min.x) / cell).ceil());
    final rows = math.max(1, ((b.max.y - b.min.y) / cell).ceil());
    final kept = List.filled(cols * rows, false);
    final blocks = <(Vec2, Vec2)>[
      for (final w in hole.walls)
        if (!w.ledge) (w.a, w.b),
      for (final arc in hole.arcs)
        for (var i = 0; i < 12; i++)
          (
            arc.center +
                Vec2(math.cos(arc.startAngle + arc.sweep * i / 12),
                        math.sin(arc.startAngle + arc.sweep * i / 12)) *
                    arc.radius,
            arc.center +
                Vec2(math.cos(arc.startAngle + arc.sweep * (i + 1) / 12),
                        math.sin(arc.startAngle + arc.sweep * (i + 1) / 12)) *
                    arc.radius,
          ),
    ];
    Vec2 centreOf(int c, int r) =>
        Vec2(b.min.x + (c + 0.5) * cell, b.min.y + (r + 0.5) * cell);
    bool crosses(Vec2 p, Vec2 q) {
      for (final (a, d) in blocks) {
        final d1 = (q - p).cross(a - p), d2 = (q - p).cross(d - p);
        final d3 = (d - a).cross(p - a), d4 = (d - a).cross(q - a);
        if ((d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)) return true;
      }
      return false;
    }

    final start = (
      ((hole.tee.x - b.min.x) / cell).floor().clamp(0, cols - 1),
      ((hole.tee.y - b.min.y) / cell).floor().clamp(0, rows - 1),
    );
    final queue = [start];
    kept[start.$2 * cols + start.$1] = true;
    while (queue.isNotEmpty) {
      final (c, r) = queue.removeLast();
      for (final (nc, nr) in [(c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)]) {
        if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
        if (kept[nr * cols + nc]) continue;
        if (crosses(centreOf(c, r), centreOf(nc, nr))) continue;
        kept[nr * cols + nc] = true;
        queue.add((nc, nr));
      }
    }
    return _Reach._(b.min, cols, rows, kept);
  }

  _Reach._(this.origin, this.cols, this.rows, this._kept);

  bool at(Vec2 p) {
    final c = ((p.x - origin.x) / cell).floor().clamp(0, cols - 1);
    final r = ((p.y - origin.y) / cell).floor().clamp(0, rows - 1);
    return _kept[r * cols + c];
  }
}
