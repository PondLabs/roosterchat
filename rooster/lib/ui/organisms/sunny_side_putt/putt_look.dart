// A player's look on the view's side: the pick "Your egg" keeps on this
// device (like the game's volumes, see putt_audio.dart), and the 2D
// drawings of it - the little egg on the scorecard, the cards and the name
// tags, and the big egg and the chick in "Your egg". The 3D egg paints its
// own band (world3d/actors.dart) and the chick wears its own hats
// (world3d/hatch.dart); these follow the same designs, flat.
//
// Two styles: the little egg (a glyph a dozen pixels tall over the HUD's
// ink) is filled with the player's colour and wears its pattern in pale
// shell, bold and simplified; the big one is drawn as the green shows it,
// a pastel shell with the pattern in the player's colour, and its face.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:rooster/client/components/sunny_side_putt/core/look.dart';
import 'package:rooster/config/preferences/string_preference.dart';

import 'putt_art.dart';

// ---- the pick, kept ----------------------------------------------------------------

/// The look picked in "Your egg" (`pattern/hat`), for every match after.
/// Local-only, like the volumes: it travels with the player into each
/// match instead (the join, then a `LookInput`).
final puttEggLook = StringPreference('putt_egg_look', defaultValue: '');

/// The look this device wears into a match: the last pick, else the
/// default.
PuttLook savedPuttLook() => PuttLook.decode(puttEggLook.value);

/// Keeps [look] for the matches to come.
Future<void> savePuttLook(PuttLook look) => puttEggLook.set(look.encode());

// ---- the palette of the looks --------------------------------------------------------

const Color _strawColor = Color(0xFFEDBE58);
const Color _strawLight = Color(0xFFF8DB8A);
const Color _pearl = Color(0xFFFFF8EE);

/// The crown's deep gold: the yolk's would melt into the chick's yellow.
const Color _gold = Color(0xFFD98A14);
const Color _chickYellow = Color(0xFFFFC61A);
const Color _chickLight = Color(0xFFFFE066);
const Color _chickWing = Color(0xFFF2A90F);
const Color _chickBeak = Color(0xFFF28C28);
const Color _chickBlush = Color(0xFFFF9E9E);

/// The pale shell a big egg is painted on, for a player of [tint]: a
/// quarter of their colour in the egg's cream (the green's own mix).
Color puttShellOf(Color tint) =>
    Color.lerp(const Color(0xFFFFF8EE), tint, 0.25) ?? tint;

/// [color] darkened by [factor] (the band's edges).
Color _deepOf(Color color, [double factor = 0.78]) => Color.from(
      alpha: color.a,
      red: color.r * factor,
      green: color.g * factor,
      blue: color.b * factor,
    );

// ---- the egg -------------------------------------------------------------------------

/// The egg's profile in [box], narrower at the crown: the outline every
/// drawn egg shares.
Path puttEggPath(Rect box) {
  final w = box.width, h = box.height;
  final egg = Path()
    ..moveTo(w / 2, 0)
    ..cubicTo(w * 0.86, 0, w, h * 0.36, w, h * 0.62)
    ..cubicTo(w, h * 0.86, w * 0.78, h, w / 2, h)
    ..cubicTo(w * 0.22, h, 0, h * 0.86, 0, h * 0.62)
    ..cubicTo(0, h * 0.36, w * 0.14, 0, w / 2, 0)
    ..close();
  return box.topLeft == Offset.zero ? egg : egg.shift(box.topLeft);
}

/// A heart [size] wide round [c], its point down.
Path _heart(Offset c, double size) {
  final w = size, h = size * 0.92;
  return Path()
    ..moveTo(c.dx, c.dy + h * 0.48)
    ..cubicTo(c.dx - w * 0.62, c.dy + h * 0.02, c.dx - w * 0.5, c.dy - h * 0.6,
        c.dx, c.dy - h * 0.22)
    ..cubicTo(c.dx + w * 0.5, c.dy - h * 0.6, c.dx + w * 0.62, c.dy + h * 0.02,
        c.dx, c.dy + h * 0.48)
    ..close();
}

/// A five-point star round [c], a point up.
Path _star(Offset c, double outer, [double inner = 0.44]) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final angle = -math.pi / 2 + i * math.pi / 5;
    final radius = i.isEven ? outer : outer * inner;
    final p = c + Offset(math.cos(angle), math.sin(angle)) * radius;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// A band across [box] between heights [top] and [bottom] (shares of the
/// height), its edges zig-zagged with [teeth] teeth of [depth].
Path _zigzagBand(Rect box, double top, double bottom, int teeth, double depth) {
  final path = Path();
  final step = box.width / teeth;
  path.moveTo(box.left, box.top + box.height * top);
  for (var i = 0; i < teeth; i++) {
    final x = box.left + i * step;
    path
      ..lineTo(x + step / 2, box.top + box.height * (top - depth))
      ..lineTo(x + step, box.top + box.height * top);
  }
  path.lineTo(box.right, box.top + box.height * bottom);
  for (var i = teeth; i > 0; i--) {
    final x = box.left + i * step;
    path
      ..lineTo(x - step / 2, box.top + box.height * (bottom + depth))
      ..lineTo(x - step, box.top + box.height * bottom);
  }
  return path..close();
}

/// A wave across [box] at height [y] (a share of the height), [amplitude]
/// high, [periods] of it, as a line to stroke.
Path _wave(Rect box, double y, double amplitude, double periods,
    {double phase = 0}) {
  final path = Path();
  const steps = 32;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final p = Offset(
      box.left + box.width * t,
      box.top +
          box.height *
              (y + amplitude * math.sin((t * periods + phase) * 2 * math.pi)),
    );
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path;
}

/// [pattern] in [color] over the egg in [box] (the caller clips to the
/// egg): as the green paints it, or [bold] - fewer, bigger shapes, for an
/// egg a dozen pixels tall.
void paintPuttEggPattern(
  Canvas canvas,
  Rect box,
  EggPattern pattern,
  Color color, {
  bool bold = false,
  Color? edge,
}) {
  final w = box.width, h = box.height;
  Offset at(double x, double y) => box.topLeft + Offset(w * x, h * y);
  final fill = Paint()..color = color;
  final rim = edge == null
      ? null
      : (Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.025));
  void shape(Path path) {
    canvas.drawPath(path, fill);
    if (rim != null) canvas.drawPath(path, rim);
  }

  switch (pattern) {
    case EggPattern.zigzag:
      if (bold) {
        shape(_zigzagBand(box, 0.46, 0.64, 3, 0.07));
        return;
      }
      shape(_zigzagBand(box, 0.42, 0.6, 5, 0.05));
      for (final (x, y, r) in const [
        (0.17, 0.29, 0.04),
        (0.83, 0.29, 0.04),
        (0.2, 0.74, 0.045),
        (0.4, 0.75, 0.045),
        (0.6, 0.75, 0.045),
        (0.8, 0.74, 0.045),
      ]) {
        shape(
            Path()..addOval(Rect.fromCircle(center: at(x, y), radius: w * r)));
      }
    case EggPattern.stripes:
      final bands = bold
          ? const [(0.36, 0.47), (0.58, 0.7)]
          : const [(0.08, 0.15), (0.42, 0.58), (0.66, 0.74), (0.82, 0.9)];
      for (final (top, bottom) in bands) {
        shape(Path()
          ..addRect(Rect.fromLTRB(
              box.left, box.top + h * top, box.right, box.top + h * bottom)));
      }
    case EggPattern.dots:
      final dots = bold
          ? const [
              (0.3, 0.42, 0.11),
              (0.7, 0.42, 0.11),
              (0.5, 0.62, 0.11),
              (0.26, 0.8, 0.1),
              (0.74, 0.8, 0.1),
            ]
          : const [
              (0.13, 0.32, 0.055),
              (0.87, 0.32, 0.055),
              (0.3, 0.5, 0.06),
              (0.7, 0.5, 0.06),
              (0.1, 0.6, 0.05),
              (0.9, 0.6, 0.05),
              (0.5, 0.64, 0.06),
              (0.28, 0.76, 0.06),
              (0.72, 0.76, 0.06),
              (0.5, 0.9, 0.055),
              (0.5, 0.12, 0.05),
              (0.25, 0.17, 0.045),
              (0.75, 0.17, 0.045),
            ];
      for (final (x, y, r) in dots) {
        shape(
            Path()..addOval(Rect.fromCircle(center: at(x, y), radius: w * r)));
      }
    case EggPattern.hearts:
      if (bold) {
        shape(_heart(at(0.5, 0.62), w * 0.6));
        return;
      }
      shape(_heart(at(0.5, 0.53), w * 0.3));
      shape(_heart(at(0.13, 0.52), w * 0.2));
      shape(_heart(at(0.87, 0.52), w * 0.2));
      for (final y in const [0.39, 0.665]) {
        shape(Path()
          ..addRect(Rect.fromLTRB(box.left, box.top + h * (y - 0.008),
              box.right, box.top + h * (y + 0.008))));
      }
    case EggPattern.stars:
      if (bold) {
        shape(_star(at(0.5, 0.62), w * 0.36));
        return;
      }
      shape(_star(at(0.5, 0.53), w * 0.19));
      shape(_star(at(0.13, 0.52), w * 0.12));
      shape(_star(at(0.87, 0.52), w * 0.12));
      for (final (x, y) in const [(0.3, 0.76), (0.7, 0.76), (0.5, 0.88)]) {
        shape(Path()
          ..addOval(Rect.fromCircle(center: at(x, y), radius: w * 0.035)));
      }
    case EggPattern.waves:
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (bold) {
        canvas.drawPath(_wave(box, 0.56, 0.06, 1.5),
            line..strokeWidth = math.max(1.2, h * 0.13));
        return;
      }
      canvas.drawPath(_wave(box, 0.5, 0.04, 2.5), line..strokeWidth = h * 0.15);
      canvas.drawPath(
          _wave(box, 0.76, 0.02, 3, phase: 0.5), line..strokeWidth = h * 0.04);
      canvas.drawPath(_wave(box, 0.12, 0.015, 2.5, phase: 0.5),
          line..strokeWidth = h * 0.035);
  }
}

/// A player's little egg in [box]: filled with their [tint], their
/// pattern in pale shell, a glint, an ink line round it and, with [hat],
/// their chick's hat on top.
void paintPuttEggGlyph(Canvas canvas, Rect box, Color tint, PuttLook look,
    {bool hat = true}) {
  final w = box.width, h = box.height;
  final egg = puttEggPath(box);
  canvas.drawPath(egg, Paint()..color = tint);
  canvas.save();
  canvas.clipPath(egg);
  paintPuttEggPattern(
      canvas, box, look.pattern, PuttPalette.shell.withValues(alpha: 0.82),
      bold: true);
  canvas.restore();
  canvas
    ..drawOval(
        Rect.fromLTWH(
            box.left + w * 0.22, box.top + h * 0.16, w * 0.22, h * 0.24),
        Paint()..color = PuttPalette.shell.withValues(alpha: 0.75))
    ..drawPath(
        egg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, h / 11)
          ..color = PuttPalette.ink);
  if (hat) {
    paintPuttHat(
        canvas, look.hat, Offset(box.center.dx, box.top + h * 0.04), w * 0.82);
  }
}

/// The egg as the green shows it, in [box]: a pastel shell of [tint], the
/// pattern in the full colour, speckles, the face and an ink line.
void paintPuttBigEgg(Canvas canvas, Rect box, Color tint, EggPattern pattern) {
  final w = box.width, h = box.height;
  Offset at(double x, double y) => box.topLeft + Offset(w * x, h * y);
  final egg = puttEggPath(box);
  canvas.drawPath(egg, Paint()..color = puttShellOf(tint));
  canvas.save();
  canvas.clipPath(egg);
  paintPuttEggPattern(canvas, box, pattern, tint, edge: _deepOf(tint));
  // Speckles, as on the shell.
  final speckle = Paint()..color = const Color(0x59C9B79E);
  for (var i = 0; i < 18; i++) {
    final x = (i * 0.618 + 0.11) % 1.0;
    final y = (i * 0.377 + 0.2) % 1.0;
    canvas.drawCircle(at(x, y), w * 0.012, speckle);
  }
  canvas.restore();
  // The face: two ink eyes with a glint, a little yolk beak.
  for (final side in const [-1.0, 1.0]) {
    final eye = at(0.5 + side * 0.13, 0.28);
    canvas
      ..drawCircle(eye, w * 0.055, Paint()..color = PuttPalette.ink)
      ..drawCircle(eye + Offset(w * 0.018, -w * 0.018), w * 0.02,
          Paint()..color = PuttPalette.shell);
  }
  canvas.drawPath(
      Path()
        ..moveTo(at(0.5, 0.32).dx, at(0.5, 0.32).dy)
        ..lineTo(at(0.455, 0.37).dx, at(0.455, 0.37).dy)
        ..lineTo(at(0.545, 0.37).dx, at(0.545, 0.37).dy)
        ..close(),
      Paint()..color = PuttPalette.yolk);
  canvas.drawPath(
      egg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, w * 0.035)
        ..color = PuttPalette.ink);
}

// ---- the hats ------------------------------------------------------------------------

/// [hat] on a head whose top is at [top] and which is [width] across: the
/// chick's in "Your egg", the little egg's on a tag or the scorecard.
void paintPuttHat(Canvas canvas, HatchlingHat hat, Offset top, double width) {
  if (hat == HatchlingHat.none) return;
  final w = width;
  final ink = Paint()
    ..color = PuttPalette.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, w * 0.07)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  void inked(Path path, Color fill) {
    canvas
      ..drawPath(path, ink)
      ..drawPath(path, Paint()..color = fill);
  }

  Offset at(double x, double y) => top + Offset(w * x, w * y);
  switch (hat) {
    case HatchlingHat.none:
      return;
    case HatchlingHat.strawHat:
      // A wide brim, the crown over it, a red band.
      inked(
          Path()
            ..addOval(Rect.fromCenter(
                center: at(0, 0.16), width: w * 1.3, height: w * 0.3)),
          _strawColor);
      inked(
          Path()
            ..addRRect(RRect.fromRectAndCorners(
              Rect.fromLTRB(at(-0.34, -0.2).dx, at(-0.34, -0.2).dy,
                  at(0.34, 0.16).dx, at(0.34, 0.16).dy),
              topLeft: Radius.circular(w * 0.2),
              topRight: Radius.circular(w * 0.2),
            )),
          _strawLight);
      canvas.drawRect(
          Rect.fromLTRB(at(-0.34, 0.02).dx, at(-0.34, 0.02).dy,
              at(0.34, 0.12).dx, at(0.34, 0.12).dy),
          Paint()..color = PuttPalette.comb);
    case HatchlingHat.bow:
      // Two loops and the knot, perched to one side.
      final knot = at(0.2, 0.06);
      for (final side in const [-1.0, 1.0]) {
        inked(
            Path()
              ..moveTo(knot.dx, knot.dy)
              ..lineTo(knot.dx + side * w * 0.34, knot.dy - w * 0.2)
              ..quadraticBezierTo(knot.dx + side * w * 0.42, knot.dy,
                  knot.dx + side * w * 0.34, knot.dy + w * 0.16)
              ..close(),
            PuttPalette.comb);
      }
      inked(Path()..addOval(Rect.fromCircle(center: knot, radius: w * 0.09)),
          PuttPalette.combDeep);
    case HatchlingHat.crown:
      // A band and three points, a red jewel, pearls on the tips.
      final crown = Path()
        ..moveTo(at(-0.34, 0.2).dx, at(-0.34, 0.2).dy)
        ..lineTo(at(-0.38, -0.16).dx, at(-0.38, -0.16).dy)
        ..lineTo(at(-0.17, 0.0).dx, at(-0.17, 0.0).dy)
        ..lineTo(at(0, -0.24).dx, at(0, -0.24).dy)
        ..lineTo(at(0.17, 0.0).dx, at(0.17, 0.0).dy)
        ..lineTo(at(0.38, -0.16).dx, at(0.38, -0.16).dy)
        ..lineTo(at(0.34, 0.2).dx, at(0.34, 0.2).dy)
        ..close();
      inked(crown, _gold);
      canvas.drawCircle(
          at(0, 0.1), w * 0.065, Paint()..color = PuttPalette.comb);
      for (final (x, y) in const [
        (-0.38, -0.16),
        (0.0, -0.24),
        (0.38, -0.16)
      ]) {
        canvas.drawCircle(at(x, y), w * 0.055, Paint()..color = _pearl);
      }
    case HatchlingHat.headphones:
      // The band over the top, a cup on each side, red rims: the host's.
      final band = Paint()
        ..color = PuttPalette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.1)
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(center: at(0, 0.5), width: w * 1.04, height: w * 1.1),
          math.pi * 1.05,
          math.pi * 0.9,
          false,
          band);
      for (final side in const [-1.0, 1.0]) {
        final cup = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: at(side * 0.5, 0.52), width: w * 0.24, height: w * 0.4),
            Radius.circular(w * 0.1));
        canvas
          ..drawRRect(cup, Paint()..color = PuttPalette.ink)
          ..drawRRect(
              cup.deflate(w * 0.05),
              Paint()
                ..color = PuttPalette.comb
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(0.6, w * 0.04));
      }
    case HatchlingHat.daisy:
      // White petals round a yolk heart, tucked over one eye.
      final centre = at(-0.26, 0.12);
      final petals = Path();
      for (var i = 0; i < 7; i++) {
        final angle = i * 2 * math.pi / 7;
        final p = centre + Offset(math.cos(angle), math.sin(angle)) * w * 0.13;
        petals.addOval(Rect.fromCircle(center: p, radius: w * 0.085));
      }
      inked(petals, _pearl);
      canvas.drawCircle(centre, w * 0.08, Paint()..color = PuttPalette.yolk);
  }
}

// ---- the chick ---------------------------------------------------------------------

/// The chick in its half shell (in [tint]'s pale), wearing [hat], in
/// [box]: the one that pops out of the nest.
void paintPuttChick(Canvas canvas, Rect box, Color tint, HatchlingHat hat,
    {bool shell = true}) {
  final w = box.width, h = box.height;
  Offset at(double x, double y) => box.topLeft + Offset(w * x, h * y);
  final ink = Paint()
    ..color = PuttPalette.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, w * 0.03);
  // The body, rising out of the shell.
  final body =
      Rect.fromCenter(center: at(0.5, 0.66), width: w * 0.62, height: h * 0.42);
  canvas
    ..drawOval(body, Paint()..color = _chickYellow)
    ..drawOval(body, ink);
  for (final side in const [-1.0, 1.0]) {
    final wing = Rect.fromCenter(
        center: at(0.5 + side * 0.3, 0.64), width: w * 0.16, height: h * 0.2);
    canvas
      ..drawOval(wing, Paint()..color = _chickWing)
      ..drawOval(wing, ink);
  }
  // The head, its tuft, the face.
  final head = at(0.5, 0.36);
  final headRadius = w * 0.24;
  for (final (x, y, r) in const [
    (0.0, -1.08, 0.24),
    (-0.22, -1.0, 0.18),
    (0.24, -0.98, 0.17),
  ]) {
    final tuft = head + Offset(x, y) * headRadius;
    canvas
      ..drawCircle(tuft, headRadius * r, Paint()..color = _chickLight)
      ..drawCircle(tuft, headRadius * r, ink);
  }
  canvas
    ..drawCircle(head, headRadius, Paint()..color = _chickYellow)
    ..drawCircle(head, headRadius, ink);
  for (final side in const [-1.0, 1.0]) {
    final eye = head + Offset(side * headRadius * 0.38, -headRadius * 0.08);
    canvas
      ..drawOval(
          Rect.fromCenter(
              center: eye + Offset(side * headRadius * 0.16, headRadius * 0.42),
              width: headRadius * 0.34,
              height: headRadius * 0.2),
          Paint()..color = _chickBlush)
      ..drawCircle(eye, headRadius * 0.15, Paint()..color = PuttPalette.ink)
      ..drawCircle(eye + Offset(headRadius * 0.05, -headRadius * 0.05),
          headRadius * 0.05, Paint()..color = PuttPalette.shell);
  }
  final beak = Path()
    ..moveTo(head.dx - headRadius * 0.2, head.dy + headRadius * 0.16)
    ..lineTo(head.dx + headRadius * 0.2, head.dy + headRadius * 0.16)
    ..lineTo(head.dx, head.dy + headRadius * 0.48)
    ..close();
  canvas
    ..drawPath(beak, Paint()..color = _chickBeak)
    ..drawPath(beak, ink);
  if (shell) {
    // The bottom half of its shell, the cut zig-zagged.
    final cut = Path()..moveTo(at(0.12, 0.7).dx, at(0.12, 0.7).dy);
    const teeth = 6;
    for (var i = 1; i <= teeth * 2; i++) {
      final x = 0.12 + 0.76 * i / (teeth * 2);
      cut.lineTo(
          at(x, i.isOdd ? 0.75 : 0.7).dx, at(x, i.isOdd ? 0.75 : 0.7).dy);
    }
    cut
      ..cubicTo(at(0.9, 0.92).dx, at(0.9, 0.92).dy, at(0.72, 1.0).dx,
          at(0.72, 1.0).dy, at(0.5, 1.0).dx, at(0.5, 1.0).dy)
      ..cubicTo(at(0.28, 1.0).dx, at(0.28, 1.0).dy, at(0.1, 0.92).dx,
          at(0.1, 0.92).dy, at(0.12, 0.7).dx, at(0.12, 0.7).dy)
      ..close();
    canvas
      ..drawPath(
          cut, Paint()..color = Color.lerp(tint, const Color(0xFFFFF8EE), 0.3)!)
      ..drawPath(cut, ink);
  }
  paintPuttHat(
      canvas, hat, head - Offset(0, headRadius * 0.92), headRadius * 2);
}

// ---- the widgets --------------------------------------------------------------------

/// A player's little egg, [size] tall: their colour, their pattern and
/// their chick's hat - the mark on the scorecard, the cards and the tags.
class PuttEggGlyph extends StatelessWidget {
  final Color tint;
  final PuttLook look;
  final double size;

  /// Whether it wears the chick's hat (a mark too small for one leaves it
  /// off).
  final bool hat;

  const PuttEggGlyph({
    super.key,
    required this.tint,
    this.look = PuttLook.standard,
    this.size = 13,
    this.hat = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 0.8, size),
      painter: PuttEggGlyphPainter(tint, look, hat: hat),
    );
  }
}

class PuttEggGlyphPainter extends CustomPainter {
  final Color tint;
  final PuttLook look;
  final bool hat;

  const PuttEggGlyphPainter(this.tint, this.look, {this.hat = true});

  @override
  void paint(Canvas canvas, Size size) =>
      paintPuttEggGlyph(canvas, Offset.zero & size, tint, look, hat: hat);

  @override
  bool shouldRepaint(PuttEggGlyphPainter oldDelegate) =>
      oldDelegate.tint != tint ||
      oldDelegate.look != look ||
      oldDelegate.hat != hat;
}
