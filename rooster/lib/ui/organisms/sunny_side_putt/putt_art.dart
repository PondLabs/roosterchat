// The art of Sunny Side Putt, drawn in code: the Rooster palette and the
// painting functions for every shape on the green - eggs, nest, hedges,
// hay, the hen, water, the rooster host. No images, no shaders, nothing
// platform-specific, so the board renders identically on desktop, web and
// mobile, and Flame and Flutter widgets share the same painters (both hand
// a `dart:ui` Canvas around).
//
// Style rules from the brand guide: flat palette colours, ink outlines
// everywhere, one loud red; humour from the situation, not from a busy
// silhouette. The rooster host wears the comb like a crown - he runs this
// farm.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

/// The brand palette (docs/brand/README.md), plus the shades the board
/// derives from it. No colour outside these on the green.
abstract final class PuttPalette {
  static const ink = ui.Color(0xFF211614);

  static const comb = ui.Color(0xFFE8382A);

  /// The day primary: comb deepened so labels keep contrast on cream.
  static const combDeep = ui.Color(0xFFC9452B);

  static const yolk = ui.Color(0xFFF89B17);

  static const cream = ui.Color(0xFFF7EDE1);

  /// The rooster's face - egg shells take it too.
  static const shell = ui.Color(0xFFFCF8F1);

  static const stone = ui.Color(0xFF8D8178);

  static const spruce = ui.Color(0xFF2E3B33);

  /// The apron around the fairway: spruce warmed with ink so the cream
  /// fairway reads as cut grass-boards on soil.
  static const apron = ui.Color(0xFF26302A);

  /// Fairway water: the link blue the app already uses for links.
  static const water = ui.Color(0xFF8FB4DA);

  static const waterDeep = ui.Color(0xFF6E97BD);

  /// Player ring tints, cycled by player index: recognisable on cream and
  /// on the apron, none of them comb red (that is the bumper's colour).
  static const playerTints = [
    yolk,
    ui.Color(0xFF8FB4DA), // water blue
    ui.Color(0xFFB48F9D), // a dusty rose
    ui.Color(0xFF9DB48F), // a moss green
    ui.Color(0xFFB4A48F), // a tan
    ui.Color(0xFF9F8FB4), // a lavender
    ui.Color(0xFF8FB4B4), // a teal
    ui.Color(0xFFB4B48F), // an olive
  ];

  static ui.Color tintForIndex(int index) =>
      playerTints[index % playerTints.length];
}

// ---- painting helpers ---------------------------------------------------------

final ui.Paint _fill = ui.Paint();

final ui.Paint _outline = ui.Paint()..style = ui.PaintingStyle.stroke;

final ui.Paint _line = ui.Paint()..style = ui.PaintingStyle.stroke;

ui.Paint solidPaint(ui.Color color) => _fill..color = color;

ui.Paint strokePaint(ui.Color color, double width) => _outline
  ..color = color
  ..strokeWidth = width
  ..strokeCap = ui.StrokeCap.round;

/// Draws one shape twice: the ink outline a touch bigger, then the fill.
void _inked(FillShape shape, ui.Color fill, double outlineWidth) {
  final paintFill = solidPaint(fill);
  final paintOutline = strokePaint(PuttPalette.ink, outlineWidth);
  shape(paintFill);
  shape(paintOutline);
}

typedef FillShape = void Function(ui.Paint paint);

// ---- the fairway ---------------------------------------------------------------

/// Fills [rect] with the cream plank fairway: horizontal boards, stone
/// seams. [t] animates nothing - the fairway is the calm thing.
void drawFairway(ui.Canvas canvas, ui.Rect rect, {double plankHeight = 2.2}) {
  canvas.drawRect(rect, solidPaint(PuttPalette.cream));
  final seam = strokePaint(
      ui.Color.fromARGB(38, 141, 129, 120), // stone at ~15 %
      0.06);
  var y = rect.top;
  while (y < rect.bottom) {
    y += plankHeight;
    canvas.drawLine(ui.Offset(rect.left, y), ui.Offset(rect.right, y), seam);
  }
}

/// The ground around the fairway: warm dark apron.
void drawApron(ui.Canvas canvas, ui.Rect rect) {
  canvas.drawRect(rect, solidPaint(PuttPalette.apron));
}

// ---- walls -----------------------------------------------------------------------

/// A hedge wall (straight): spruce with ink outline, rounded caps. Bumpers
/// are comb red and wear a yolk cap at each end.
void drawWallSegment(
  ui.Canvas canvas,
  ui.Offset a,
  ui.Offset b,
  double width, {
  bool bumper = false,
}) {
  final fill = bumper ? PuttPalette.comb : PuttPalette.spruce;
  _line
    ..color = fill
    ..strokeWidth = width
    ..strokeCap = ui.StrokeCap.round;
  // The stroke-capped line is the body; ink it by stroking wider first.
  canvas.drawLine(a, b, strokePaint(PuttPalette.ink, width + 0.22));
  canvas.drawLine(a, b, _line);
  if (bumper) {
    final bodyPaint = solidPaint(PuttPalette.yolk);
    final half = width / 2 + 0.12;
    for (final cap in [a, b]) {
      canvas.drawCircle(cap, half - 0.12, strokePaint(PuttPalette.ink, 0.22));
      canvas.drawCircle(cap, half - 0.12, bodyPaint);
    }
  }
}

/// A hedge arc: the same spruce-and-ink treatment around the circle at
/// [center], from [startAngle] sweeping [sweep].
void drawWallArc(ui.Canvas canvas, ui.Offset center, double radius,
    double startAngle, double sweep, double width,
    {bool bumper = false}) {
  final fill = bumper ? PuttPalette.comb : PuttPalette.spruce;
  final inkBox =
      ui.Rect.fromCircle(center: center, radius: radius + (width + 0.22) / 2);
  final bodyBox =
      ui.Rect.fromCircle(center: center, radius: radius + width / 2);
  canvas.drawArc(inkBox, startAngle, sweep, false,
      strokePaint(PuttPalette.ink, width + 0.22));
  canvas.drawArc(bodyBox, startAngle, sweep, false, strokePaint(fill, width));
}

// ---- the nest and the tee ---------------------------------------------------------

/// The nest: a straw ring with a dark want-in-there hole, in [center] with
/// nest radius [radius] (the physics capture radius; the drawn ring is a
/// touch wider).
void drawNest(ui.Canvas canvas, ui.Offset center, double radius,
    {double time = 0}) {
  final outer = radius * 1.25;
  // A soil shadow first.
  canvas.drawCircle(
      center, outer, solidPaint(ui.Color.fromARGB(70, 33, 22, 20)));
  final straw = strokePaint(PuttPalette.yolk, radius * 0.34)
    ..strokeCap = ui.StrokeCap.round;
  final strawInk = strokePaint(PuttPalette.ink, radius * 0.34 + 0.12);
  final strawDeep = ui.Color(0xFFD3831F);
  final strawShade = strokePaint(strawDeep, radius * 0.16);
  for (var i = 0; i < 12; i++) {
    final angle = i * math.pi / 6 + time * 0.15;
    final direction = ui.Offset(math.cos(angle), math.sin(angle));
    final inner = center + direction * (radius * 0.55);
    final outerPoint = center + direction * outer;
    canvas.drawLine(outerPoint, inner, strawInk);
    canvas.drawLine(outerPoint, inner, straw);
    // A shade strand on half the straws for weave.
    if (i.isEven) {
      canvas.drawLine(
          center + direction * (radius * 0.7), outerPoint, strawShade);
    }
  }
  // The hole.
  canvas.drawCircle(
      center, radius * 0.72, solidPaint(const ui.Color(0xFF2A2118)));
  canvas.drawCircle(center, radius * 0.72, strokePaint(PuttPalette.ink, 0.14));
}

/// The tee marker: a small cream cup an egg sits in.
void drawTeeMarker(ui.Canvas canvas, ui.Offset center, double scale) {
  final path = ui.Path()
    ..addOval(ui.Rect.fromCenter(
        center: center, width: scale * 1.6, height: scale * 1.1));
  canvas.drawPath(path, solidPaint(PuttPalette.cream));
  canvas.drawPath(path, strokePaint(PuttPalette.ink, 0.16));
}

// ---- sensors -----------------------------------------------------------------------

/// A pond: water fill, deep rim, and ripples that breathe with [time].
void drawWaterCircle(
    ui.Canvas canvas, ui.Offset center, double radius, double time) {
  canvas.drawCircle(center, radius, solidPaint(PuttPalette.water));
  canvas.drawCircle(center, radius, strokePaint(PuttPalette.waterDeep, 0.22));
  final ripple = strokePaint(PuttPalette.shell, 0.1);
  for (var i = 0; i < 3; i++) {
    final phase = (time * 0.5 + i / 3) % 1;
    canvas.drawCircle(
      center,
      radius * (0.25 + 0.6 * phase),
      ripple
        ..color = ui.Color.fromARGB(((1 - phase) * 140).toInt(), 252, 248, 241),
    );
  }
}

/// A boost strip: stone board with yolk chevrons pointing along [to].
void drawBoostStrip(
    ui.Canvas canvas, ui.Offset from, ui.Offset to, double width) {
  final axis = (to - from);
  final length = axis.distance;
  final angle = math.atan2(axis.dy, axis.dx);
  canvas.save();
  canvas.translate(from.dx, from.dy);
  canvas.rotate(angle);
  // Board.
  final board = ui.Rect.fromLTWH(0, -width / 2, length, width);
  canvas.drawRect(board, solidPaint(PuttPalette.stone));
  canvas.drawRect(board, strokePaint(PuttPalette.ink, 0.16));
  // Chevrons march on: 3 of them, static positions, drawn along the axis.
  final chevron = strokePaint(PuttPalette.yolk, 0.22);
  for (var i = 0; i < 3; i++) {
    final x = length * (0.2 + 0.3 * i);
    final path = ui.Path()
      ..moveTo(x - 0.35, -width * 0.3)
      ..lineTo(x + 0.35, 0)
      ..lineTo(x - 0.35, width * 0.3);
    canvas.drawPath(path, chevron);
  }
  canvas.restore();
}

/// A rabbit hole (portal): a dark burrow with a spruce rim.
void drawPortal(ui.Canvas canvas, ui.Offset center, double radius,
    {double time = 0}) {
  canvas.drawCircle(center, radius, strokePaint(PuttPalette.ink, 0.24));
  canvas.drawCircle(center, radius, solidPaint(const ui.Color(0xFF1D1512)));
  // A swirl: three arcs turning slowly.
  final swirl = strokePaint(PuttPalette.spruce, 0.12);
  for (var i = 0; i < 3; i++) {
    final start = time * 1.5 + i * 2 * math.pi / 3;
    canvas.drawArc(
      ui.Rect.fromCircle(center: center, radius: radius * 0.6),
      start,
      math.pi * 0.6,
      false,
      swirl,
    );
  }
}

/// The "?" egg-carton block: a cream carton with a raised comb-red question
/// mark, bobbing with [time], gone while [collected].
void drawQuestionBox(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  double time, {
  bool collected = false,
}) {
  if (collected) return;
  final bob = math.sin(time * 2.4) * radius * 0.12;
  final top = center + ui.Offset(0, bob);
  // The carton: a squarish cup with the classic dimpled top.
  final box = ui.Rect.fromCenter(
      center: top, width: radius * 1.7, height: radius * 1.5);
  _inked(
    (paint) => canvas.drawRRect(
        ui.RRect.fromRectAndRadius(box, ui.Radius.circular(radius * 0.3)),
        paint),
    PuttPalette.cream,
    0.18,
  );
  // Carton dimples.
  final dimple = strokePaint(const ui.Color(0xFFDFD2C2), 0.08);
  for (final offset in [
    ui.Offset(-radius * 0.5, -radius * 0.2),
    ui.Offset(radius * 0.5, -radius * 0.2),
    ui.Offset(0, -radius * 0.2),
    ui.Offset(0, radius * 0.4),
  ]) {
    canvas.drawCircle(top + offset, radius * 0.16, dimple);
  }
  // The question mark, comb red, bouncing on its own beat.
  final qm = strokePaint(PuttPalette.comb, 0.28)
    ..strokeCap = ui.StrokeCap.round;
  final path = ui.Path()
    ..moveTo(top.dx - radius * 0.3, top.dy - radius * 0.28)
    ..cubicTo(
      top.dx - radius * 0.3,
      top.dy - radius * 0.62,
      top.dx + radius * 0.34,
      top.dy - radius * 0.62,
      top.dx + radius * 0.34,
      top.dy - radius * 0.3,
    )
    ..cubicTo(
      top.dx + radius * 0.34,
      top.dy - radius * 0.08,
      top.dx + radius * 0.02,
      top.dy - radius * 0.14,
      top.dx + radius * 0.02,
      top.dy + radius * 0.16,
    );
  canvas.drawPath(path, qm);
  canvas.drawCircle(
      top + ui.Offset(0.02 * radius, radius * 0.46), radius * 0.09, qm);
}

// ---- the egg -----------------------------------------------------------------------

/// One egg: shell white with ink outline, a yolk highlight, a tiny face,
/// seated in a player-tint ring. [squash] (0..0.3) flattens it with speed,
/// [look] turns the face toward its motion.
void drawEgg(
  ui.Canvas canvas,
  ui.Offset center,
  double radius, {
  ui.Color tint = PuttPalette.yolk,
  double squash = 0,
  ui.Offset look = ui.Offset.zero,
  double bob = 0,
}) {
  final at = center + ui.Offset(0, bob);
  final shellRect = ui.Rect.fromCenter(
    center: at,
    width: radius * 2 * (1 + squash * 0.5),
    height: radius * 2.3 * (1 - squash * 0.35),
  );
  final egg = ui.Path()..addOval(shellRect);
  // Tint ring first: the player's colour under the egg.
  canvas.drawOval(
      ui.Rect.fromCenter(
          center: at + ui.Offset(0, radius * 0.95),
          width: radius * 2.1,
          height: radius * 0.75),
      solidPaint(tint));
  canvas.drawOval(
      ui.Rect.fromCenter(
          center: at + ui.Offset(0, radius * 0.95),
          width: radius * 2.1,
          height: radius * 0.75),
      strokePaint(PuttPalette.ink, 0.14));
  canvas.drawPath(egg, solidPaint(PuttPalette.shell));
  canvas.drawPath(egg, strokePaint(PuttPalette.ink, 0.16));
  // Highlight: a small shell shine upper-left.
  canvas.drawOval(
    ui.Rect.fromCenter(
        center: at + ui.Offset(-radius * 0.35, -radius * 0.55),
        width: radius * 0.5,
        height: radius * 0.3),
    solidPaint(ui.Color.fromARGB(120, 255, 255, 255)),
  );
  // The face: two ink eyes and a yolk beak, both leaning where it looks.
  final eye = radius * 0.13;
  for (final side in [-1.0, 1.0]) {
    canvas.drawCircle(
      at +
          ui.Offset(side * radius * 0.34 + look.dx * radius * 0.1,
              -radius * 0.15 + look.dy * radius * 0.1),
      eye,
      solidPaint(PuttPalette.ink),
    );
  }
  final beak = ui.Path()
    ..moveTo(at.dx + look.dx * radius * 0.1, at.dy + radius * 0.02)
    ..lineTo(at.dx - radius * 0.14, at.dy + radius * 0.16)
    ..lineTo(at.dx + radius * 0.14, at.dy + radius * 0.16)
    ..close();
  canvas.drawPath(beak, solidPaint(PuttPalette.yolk));
}

// ---- the hen -----------------------------------------------------------------------

/// The hen (the moving obstacle) at [center] with body [radius], waddling
/// on [phase]. A white hen, comb red on top, yolk beak.
void drawHen(ui.Canvas canvas, ui.Offset center, double radius,
    {double phase = 0}) {
  final bob = math.sin(phase * 2) * radius * 0.08;
  final at = center + ui.Offset(0, bob);
  final body =
      ui.Rect.fromCenter(center: at, width: radius * 2, height: radius * 1.9);
  // Body and tail: an egg with a flicked tail, inked.
  final bodyPath = ui.Path()
    ..addOval(body)
    ..addOval(ui.Rect.fromCenter(
        center: at + ui.Offset(-radius * 0.9, -radius * 0.5),
        width: radius * 0.9,
        height: radius * 0.7));
  canvas.drawPath(bodyPath, solidPaint(PuttPalette.shell));
  canvas.drawPath(bodyPath, strokePaint(PuttPalette.ink, 0.16));
  // The comb: three lobes.
  final comb = solidPaint(PuttPalette.comb);
  for (var i = 0; i < 3; i++) {
    final lobe = ui.Offset(
        at.dx + radius * 0.15 - i * radius * 0.28, at.dy - radius * 0.95);
    canvas.drawCircle(lobe, radius * 0.2 - i * radius * 0.03, comb);
  }
  // Eye and beak.
  canvas.drawCircle(at + ui.Offset(radius * 0.4, -radius * 0.15), radius * 0.1,
      solidPaint(PuttPalette.ink));
  final beakX = at.dx + radius * 0.75;
  final beak = ui.Path()
    ..moveTo(beakX, at.dy - radius * 0.1)
    ..lineTo(beakX + radius * 0.34, at.dy + radius * 0.05)
    ..lineTo(beakX, at.dy + radius * 0.12)
    ..close();
  canvas.drawPath(beak, solidPaint(PuttPalette.yolk));
}

// ---- scenery --------------------------------------------------------------------------

/// A hay bale: a yolk-amber roll with ink outline and slot lines.
void drawHay(ui.Canvas canvas, ui.Offset center, double scale) {
  final rect =
      ui.Rect.fromCenter(center: center, width: scale * 2, height: scale * 1.5);
  _inked(
    (paint) => canvas.drawRRect(
        ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(scale * 0.4)),
        paint),
    const ui.Color(0xFFEDD9A3),
    0.18,
  );
  final strand = strokePaint(const ui.Color(0xFFD8BC7F), 0.08);
  for (var i = 1; i < 3; i++) {
    canvas.drawLine(ui.Offset(rect.left + rect.width * i / 3, rect.top + 0.1),
        ui.Offset(rect.left + rect.width * i / 3, rect.bottom - 0.1), strand);
  }
  // A hair of straw poking out.
  canvas.drawLine(
      ui.Offset(rect.right - 0.2, rect.top),
      ui.Offset(rect.right + 0.3, rect.top - 0.35),
      strokePaint(PuttPalette.ink, 0.07));
}

/// A fence line: starting at [center], [posts] spruce posts with two rails.
void drawFence(ui.Canvas canvas, ui.Offset center, int posts, double spacing) {
  for (var i = 0; i < posts; i++) {
    final x = center.dx + i * spacing;
    final post = ui.Rect.fromLTWH(x, center.dy - 0.45, 0.3, 0.9);
    _inked(
        (paint) => canvas.drawRRect(
            ui.RRect.fromRectAndRadius(post, const ui.Radius.circular(0.1)),
            paint),
        PuttPalette.spruce,
        0.1);
  }
  final railY = [center.dy - 0.28, center.dy + 0.1];
  for (final y in railY) {
    canvas.drawLine(
        ui.Offset(center.dx, y),
        ui.Offset(center.dx + (posts - 1) * spacing, y),
        strokePaint(PuttPalette.spruce, 0.12));
  }
}

// ---- the host -------------------------------------------------------------------------

/// The rooster host: head in profile facing [facing] (radians; 0 looks
/// right), feather white, comb-crown of lobes, comb-red wattle, yolk beak,
/// ink eye with a shine. [bob] rocks the head gently. Used on the board
/// between holes and across the HUD and menus.
void drawRoosterHead(
  ui.Canvas canvas,
  ui.Offset center,
  double scale, {
  double facing = 0,
  double bob = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(facing);
  canvas.translate(0, bob);
  // The neck wedge under the head.
  final neck = ui.Path()
    ..moveTo(-scale * 0.15, scale * 0.35)
    ..lineTo(-scale * 0.55, scale * 1.05)
    ..lineTo(scale * 0.3, scale * 1.05)
    ..lineTo(scale * 0.35, scale * 0.4)
    ..close();
  canvas.drawPath(neck, solidPaint(PuttPalette.shell));
  // Head.
  final head = ui.Rect.fromCenter(
      center: ui.Offset.zero, width: scale * 1.5, height: scale * 1.4);
  // Comb crown: a fan of lobes arcing back from the crown.
  final comb = solidPaint(PuttPalette.comb);
  final combInk = strokePaint(PuttPalette.ink, 0.1);
  for (var i = 0; i < 4; i++) {
    final angle = -math.pi / 2 - 0.5 + i * 0.34;
    final lobeCenter = ui.Offset(
        math.cos(angle) * scale * 0.62, math.sin(angle) * scale * 0.62);
    final lobeRadius = scale * (0.3 - i * 0.035);
    canvas.drawCircle(lobeCenter, lobeRadius, combInk);
    canvas.drawCircle(lobeCenter, lobeRadius, comb);
  }
  canvas.drawOval(head, strokePaint(PuttPalette.ink, 0.16));
  canvas.drawOval(head, solidPaint(PuttPalette.shell));
  // Wattle under the beak side.
  canvas.drawCircle(ui.Offset(scale * 0.32, scale * 0.62), scale * 0.2, comb);
  // Yolk beak: a wedge pushing right.
  final beak = ui.Path()
    ..moveTo(scale * 0.55, -scale * 0.05)
    ..lineTo(scale * 1.05, scale * 0.14)
    ..lineTo(scale * 0.5, scale * 0.32)
    ..close();
  canvas.drawPath(beak, strokePaint(PuttPalette.ink, 0.1));
  canvas.drawPath(beak, solidPaint(PuttPalette.yolk));
  // Ink eye with a shell shine.
  canvas.drawCircle(ui.Offset(scale * 0.25, -scale * 0.12), scale * 0.17,
      solidPaint(PuttPalette.ink));
  canvas.drawCircle(ui.Offset(scale * 0.31, -scale * 0.18), scale * 0.05,
      solidPaint(PuttPalette.shell));
  // The little arched door of the brand, bottom of the neck.
  final door = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(-scale * 0.18, scale * 0.72, scale * 0.34, scale * 0.34),
      const ui.Radius.circular(1));
  canvas.drawRRect(door, solidPaint(PuttPalette.ink));
  canvas.restore();
}

// ---- particles --------------------------------------------------------------------------

/// One sparkle of a power-up burst: a four-point star.
void drawSparkle(ui.Canvas canvas, ui.Offset center, double size,
    double progress, ui.Color color) {
  final fade = (1 - progress).clamp(0.0, 1.0);
  final paint = solidPaint(color)..color = color.withValues(alpha: fade);
  final spokes = size * (0.4 + progress * 0.6);
  final path = ui.Path()
    ..moveTo(center.dx - spokes, center.dy)
    ..lineTo(center.dx, center.dy - spokes * 0.35)
    ..lineTo(center.dx + spokes, center.dy)
    ..lineTo(center.dx, center.dy + spokes * 0.35)
    ..close();
  canvas.drawPath(path, paint);
  final vertical = ui.Path()
    ..moveTo(center.dx, center.dy - spokes)
    ..lineTo(center.dx + spokes * 0.35, center.dy)
    ..lineTo(center.dx, center.dy + spokes)
    ..lineTo(center.dx - spokes * 0.35, center.dy)
    ..close();
  canvas.drawPath(vertical, paint);
}

/// Water droplets of a splash: little cream-blue arcs.
void drawDroplet(
    ui.Canvas canvas, ui.Offset center, double size, double progress) {
  final paint = solidPaint(PuttPalette.water)
    ..color = PuttPalette.water.withValues(alpha: (1 - progress).clamp(0, 1));
  canvas.drawCircle(center, size * (1 - progress * 0.5), paint);
}
