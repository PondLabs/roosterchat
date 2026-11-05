// The power-ups' own icons: twelve little stickers drawn in code, one per
// effect, in the board's style (putt_art.dart) - chunky shapes, flat brand
// colours, an ink outline, a soft shine on the top left, and a thin cream
// edge around the whole silhouette so each one reads on the ink carton and
// on a light card alike (the crow is black). No font and no images: the
// same paths on desktop, web and mobile.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'putt_art.dart';

/// A power-up's icon, [size] logical pixels square. An id the set does not
/// know draws a cream "?" on a yolk carton square, like the crates on the
/// green.
class PuttPowerUpIcon extends StatelessWidget {
  final String effectId;
  final double size;

  /// What a screen reader says for the icon; none when it only decorates
  /// a label that already names the power-up.
  final String? semanticLabel;

  const PuttPowerUpIcon({
    super.key,
    required this.effectId,
    required this.size,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PowerUpIconPainter(effectId)),
    );
    final label = semanticLabel;
    if (label == null) return icon;
    return Semantics(label: label, image: true, child: icon);
  }
}

/// Paints [effectId]'s icon into [size] on [canvas], centred: the
/// painter's own work, for whoever needs the icon outside a widget (the 3D
/// world paints the crow's loot into a texture with it).
void paintPuttPowerUpIcon(Canvas canvas, Size size, String effectId) {
  final scale = size.shortestSide / _box;
  canvas
    ..save()
    ..translate(
        (size.width - _box * scale) / 2, (size.height - _box * scale) / 2)
    ..scale(scale);
  _glyphOf(effectId).paint(canvas);
  canvas.restore();
}

class _PowerUpIconPainter extends CustomPainter {
  final String effectId;

  const _PowerUpIconPainter(this.effectId);

  @override
  void paint(Canvas canvas, Size size) =>
      paintPuttPowerUpIcon(canvas, size, effectId);

  @override
  bool shouldRepaint(_PowerUpIconPainter oldDelegate) =>
      oldDelegate.effectId != effectId;
}

// ---- the set --------------------------------------------------------------------------

/// The icons are drawn on a square this many units wide.
const double _box = 100;

/// The ink outline: 2.4 px at 28 px.
const double _outline = 8.5;

/// The cream edge outside the outline: 1.1 px at 28 px.
const double _edge = 4;

const Map<String, _Glyph Function()> _builders = {
  'hawk_eye': _hawkEye,
  'nest_magnet': _nestMagnet,
  'ghost_egg': _ghostEgg,
  'chicken_hop': _chickenHop,
  'rabbit_hole': _rabbitHole,
  'gust': _gust,
  'thick_shell': _thickShell,
  'strong_coffee': _strongCoffee,
  'nest_swap': _nestSwap,
  'sprinkler': _sprinkler,
  'corn_rain': _cornRain,
  'thieving_crow': _thievingCrow,
};

final Map<String, _Glyph> _built = {};

final _Glyph _unknown = _questionCarton();

_Glyph _glyphOf(String effectId) {
  final build = _builders[effectId];
  if (build == null) return _unknown;
  return _built.putIfAbsent(effectId, build);
}

// ---- colours --------------------------------------------------------------------------

const Color _ink = PuttPalette.ink;
const Color _shell = PuttPalette.shell;
const Color _cream = PuttPalette.cream;
const Color _yolk = PuttPalette.yolk;
const Color _comb = PuttPalette.comb;
const Color _stone = PuttPalette.stone;

/// Water and wind: the fairway's water blue.
const Color _sky = PuttPalette.water;

/// The shine on the top left of the main shape.
const Color _shine = Color(0xA6FFFFFF);

/// Straw in shade: the nest's weave.
const Color _strawDeep = Color(0xFFD3831F);

/// The rabbit hole's dark, as on the green.
const Color _burrow = Color(0xFF1D1512);

/// The inside of a rabbit's ear: the light comb red of the brand's comb
/// tile.
const Color _earPink = Color(0xFFFF8466);

/// The corn husk: the lime player tint.
const Color _husk = Color(0xFF8CCB2E);

/// The coffee in the mug.
const Color _coffee = Color(0xFF5A321F);

/// The crow's wing: a lighter slate over the slate body, its feathers read.
const Color _crowWing = Color(0xFF727C99);

/// The "?" crates' darker yolk edge, as on the green.
const Color _cartonEdge = Color(0xFFD9780C);

// ---- the icons ------------------------------------------------------------------------

/// Hawk Eye: a sharp eye, yolk iris, under a stern brow.
_Glyph _hawkEye() {
  final eye = Path()
    ..moveTo(9, 60)
    ..cubicTo(24, 32, 64, 22, 91, 46)
    ..cubicTo(72, 78, 30, 84, 9, 60)
    ..close();
  const iris = Offset(52, 55);
  final brow = Path()
    ..moveTo(9, 44)
    ..cubicTo(28, 20, 64, 12, 91, 24)
    ..lineTo(90, 38)
    ..cubicTo(64, 32, 36, 38, 14, 58)
    ..close();
  return _Glyph([
    _Shape(eye, _shell, inside: [
      _Mark(_circle(iris, 19), _yolk),
      _Mark(_circle(iris, 19), _ink, width: 4),
      _Mark(_circle(iris, 8.5), _ink),
      _Mark(_circle(iris + const Offset(-6, -6), 4.5), _shell),
    ]),
    _Shape(brow, _ink),
  ]);
}

/// Nest Magnet: a horseshoe magnet, tilted, pulling at an egg in its nest.
_Glyph _nestMagnet() {
  final magnet = Path()
    ..moveTo(-22, 16)
    ..lineTo(-22, 0)
    ..arcToPoint(const Offset(22, 0), radius: const Radius.circular(22))
    ..lineTo(22, 16)
    ..lineTo(9, 16)
    ..lineTo(9, 0)
    ..arcToPoint(const Offset(-9, 0),
        radius: const Radius.circular(9), clockwise: false)
    ..lineTo(-9, 16)
    ..close();
  const at = Offset(64, 32);
  const tilt = 0.62;
  final nest = Path()
    ..moveTo(10, 70)
    ..cubicTo(12, 84, 22, 90, 34, 90)
    ..cubicTo(46, 90, 56, 84, 58, 70)
    ..cubicTo(46, 75, 22, 75, 10, 70)
    ..close();
  return _Glyph([
    _Shape(_egg(const Offset(34, 62), 24, 30), _shell, inside: [
      _Mark(_arc(const Offset(34, 63), 8, math.pi * 1.05, 0.9), _shine,
          width: 4),
    ]),
    _Shape(nest, _yolk, inside: [
      for (final x in [16.0, 28.0, 40.0, 52.0])
        _Mark(_segment(Offset(x - 5, 72), Offset(x + 5, 92)), _strawDeep,
            width: 3.5),
    ]),
    _Shape(_place(magnet, at, tilt), _comb, inside: [
      _Mark(
          _place(_arc(Offset.zero, 15.5, math.pi * 1.1, 0.9), at, tilt), _shine,
          width: 4.5),
    ]),
    _Shape(_place(_rect(-22, 7, -9, 16), at, tilt), _shell, outline: 6),
    _Shape(_place(_rect(9, 7, 22, 16), at, tilt), _shell, outline: 6),
  ]);
}

/// Ghost Egg: a see-through egg of a ghost, wavy hem, round eyes.
_Glyph _ghostEgg() {
  const pivot = Offset(50, 50);
  const tilt = -0.1;
  final body = Path()
    ..moveTo(21, 82)
    ..cubicTo(19, 46, 31, 11, 50, 11)
    ..cubicTo(69, 11, 81, 46, 79, 82)
    ..cubicTo(78, 91, 61, 91, 60, 82)
    ..cubicTo(59, 91, 41, 91, 40, 82)
    ..cubicTo(39, 91, 22, 91, 21, 82)
    ..close();
  return _Glyph([
    _Shape(_turn(body, pivot, tilt), _shell.withValues(alpha: 0.72), inside: [
      _Mark(
          _turn(
              _arc(const Offset(50, 46), 22, math.pi * 1.1, 0.75), pivot, tilt),
          _shine,
          width: 5),
      _Mark(
          _turn(
              Path()
                ..addOval(Rect.fromCenter(
                    center: const Offset(39, 44), width: 9, height: 13))
                ..addOval(Rect.fromCenter(
                    center: const Offset(61, 44), width: 9, height: 13))
                ..addOval(Rect.fromCenter(
                    center: const Offset(50, 63), width: 9, height: 10)),
              pivot,
              tilt),
          _ink),
    ]),
  ]);
}

/// Chicken Hop: an egg that has sprouted chicken wings, off in a hop.
_Glyph _chickenHop() {
  const centre = Offset(50, 52);
  const tilt = 0.14;
  final wing = Path()
    ..moveTo(38, 42)
    ..cubicTo(30, 28, 21, 23, 12, 26)
    ..cubicTo(9, 34, 13, 40, 19, 40)
    ..cubicTo(17, 47, 23, 52, 29, 50)
    ..cubicTo(29, 57, 35, 60, 40, 57)
    ..close();
  return _Glyph([
    _Shape(_turn(wing, centre, tilt), _cream, inside: [
      _Mark(
          _turn(_segment(const Offset(19, 30), const Offset(28, 32)), centre,
              tilt),
          _shine,
          width: 3.5),
    ]),
    _Shape(_turn(_mirror(wing), centre, tilt), _cream),
    _Shape(_egg(centre, 40, 52, tilt), _shell, inside: [
      _Mark(
          _turn(_arc(centre + const Offset(0, 2), 14, math.pi * 1.05, 0.9),
              centre, tilt),
          _shine,
          width: 5),
    ]),
  ]);
}

/// Rabbit Hole: a white rabbit's ears poking out of a burrow.
_Glyph _rabbitHole() {
  const hole = Rect.fromLTRB(14, 66, 86, 88);
  final burrow = Path()..addOval(hole);
  _Shape ear(Offset centre, double tilt) {
    final base = Offset(centre.dx, centre.dy + 36);
    return _Shape(
        _turn(
            Path()
              ..addOval(Rect.fromCenter(center: centre, width: 19, height: 76)),
            base,
            tilt),
        _shell,
        inside: [
          _Mark(
              _turn(
                  Path()
                    ..addOval(Rect.fromCenter(
                        center: centre + const Offset(1, 4),
                        width: 8,
                        height: 56)),
                  base,
                  tilt),
              _earPink),
        ]);
  }

  return _Glyph([
    _Shape(burrow, _burrow),
    _Clip(
      Path()
        ..addRect(Rect.fromLTRB(0, 0, _box, hole.center.dy))
        ..addOval(hole),
      [ear(const Offset(38, 46), -0.24), ear(const Offset(62, 48), 0.22)],
    ),
    _Clip(Path()..addRect(Rect.fromLTRB(0, hole.center.dy, _box, _box)),
        [_Shape(burrow, _burrow)]),
  ]);
}

/// Gust: three curling lines of wind.
_Glyph _gust() {
  final wind = Path()
    ..moveTo(17, 29)
    ..lineTo(56, 29)
    ..arcTo(Rect.fromCircle(center: const Offset(56, 21.5), radius: 7.5),
        math.pi / 2, -math.pi * 1.5, false)
    ..moveTo(13, 50)
    ..lineTo(72, 50)
    ..arcTo(Rect.fromCircle(center: const Offset(72, 42.5), radius: 7.5),
        math.pi / 2, -math.pi * 1.5, false)
    ..moveTo(23, 71)
    ..lineTo(58, 71)
    ..arcTo(Rect.fromCircle(center: const Offset(58, 78.5), radius: 7.5),
        -math.pi / 2, math.pi * 1.5, false);
  return _Glyph([_Line(wind, _sky, 8)]);
}

/// Thick Shell: an egg behind a comb-red shield.
_Glyph _thickShell() {
  final shield = Path()
    ..moveTo(47, 45)
    ..quadraticBezierTo(68, 37, 89, 45)
    ..lineTo(89, 62)
    ..cubicTo(89, 78, 80, 86, 68, 91)
    ..cubicTo(56, 86, 47, 78, 47, 62)
    ..close();
  return _Glyph([
    _Shape(_egg(const Offset(38, 44), 44, 58), _shell, inside: [
      _Mark(_arc(const Offset(38, 46), 15, math.pi * 1.05, 0.9), _shine,
          width: 5),
    ]),
    _Shape(shield, _comb, inside: [
      _Mark(_rect(63, 30, 73, 100), _yolk),
      _Mark(_segment(const Offset(54, 52), const Offset(54, 66)), _shine,
          width: 4.5),
    ]),
  ]);
}

/// Strong Coffee: a steaming comb-red mug with a yolk bolt on it.
_Glyph _strongCoffee() {
  final steam = Path()
    ..moveTo(31, 30)
    ..cubicTo(24, 24, 38, 18, 31, 12)
    ..moveTo(49, 30)
    ..cubicTo(42, 24, 56, 18, 49, 12);
  final handle = Path()
    ..moveTo(64, 51)
    ..cubicTo(84, 49, 84, 77, 64, 75);
  final body = Path()
    ..addRRect(RRect.fromLTRBAndCorners(14, 40, 68, 90,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(16),
        bottomRight: const Radius.circular(16)));
  final bolt = Path()
    ..moveTo(45, 50)
    ..lineTo(31, 70)
    ..lineTo(40, 70)
    ..lineTo(35, 85)
    ..lineTo(52, 63)
    ..lineTo(43, 63)
    ..lineTo(49, 50)
    ..close();
  return _Glyph([
    _Line(steam, _shell, 6),
    _Line(handle, _comb, 8),
    _Shape(body, _comb, inside: [
      _Mark(_segment(const Offset(21, 54), const Offset(21, 74)), _shine,
          width: 5),
    ]),
    _Shape(Path()..addOval(const Rect.fromLTRB(14, 33, 68, 47)), _comb,
        inside: [
          _Mark(Path()..addOval(const Rect.fromLTRB(20, 36, 62, 45)), _coffee),
        ]),
    _Shape(bolt, _yolk, outline: 4),
  ]);
}

/// Nest Swap: two eggs across a circle of two arrows, each chasing the
/// other's place.
_Glyph _nestSwap() {
  const centre = Offset(50, 50);
  const radius = 30.0;
  final ring = Rect.fromCircle(center: centre, radius: radius);
  final arrows = Path()
    ..addArc(ring, math.pi * 1.42, math.pi * 0.5)
    ..addArc(ring, math.pi * 0.42, math.pi * 0.5);
  Path head(double angle) {
    final out = Offset(math.cos(angle), math.sin(angle));
    final along = Offset(-math.sin(angle), math.cos(angle)); // clockwise
    final base = centre + out * radius;
    final tip = base + along * 13;
    final a = base + out * 11;
    final b = base - out * 11;
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
  }

  return _Glyph([
    _Line(arrows, _comb, 7),
    _Shape(head(math.pi * 1.92), _comb, outline: 6),
    _Shape(head(math.pi * 0.92), _comb, outline: 6),
    _Shape(_egg(const Offset(30, 30), 25, 31, -0.2), _shell, inside: [
      _Mark(_arc(const Offset(30, 31), 8.5, math.pi * 1.05, 0.9), _shine,
          width: 4),
    ]),
    _Shape(_egg(const Offset(70, 70), 25, 31, -0.2), _yolk, inside: [
      _Mark(_arc(const Offset(70, 71), 8.5, math.pi * 1.05, 0.9), _shine,
          width: 4),
    ]),
  ]);
}

/// Sprinkler: a sprinkler head on its stake, throwing drops of water.
_Glyph _sprinkler() {
  const nozzle = Offset(50, 58);
  return _Glyph([
    _Line(_segment(const Offset(50, 76), const Offset(50, 87)), _stone, 7),
    for (final centre in const [Offset(23, 40), Offset(50, 22), Offset(77, 40)])
      _Shape(_flyingDrop(centre, nozzle), _sky, outline: 6, inside: [
        _Mark(_circle(centre + const Offset(-2.5, 1), 2.5), _shine),
      ]),
    _Shape(
        Path()
          ..addRRect(RRect.fromLTRBR(44, 52, 56, 64, const Radius.circular(3))),
        _cream,
        outline: 6),
    _Shape(
        Path()
          ..addRRect(RRect.fromLTRBR(35, 62, 65, 80, const Radius.circular(7))),
        _yolk,
        inside: [
          _Mark(_segment(const Offset(41, 68), const Offset(48, 68)), _shine,
              width: 4),
        ]),
  ]);
}

/// Corn Rain: a corn cob in its husk, kernels falling off it.
_Glyph _cornRain() {
  const at = Offset(32, 62);
  const tilt = -0.8;
  final cob = Path()
    ..moveTo(0, -15)
    ..cubicTo(22, -18, 48, -15, 58, -8)
    ..quadraticBezierTo(67, 0, 58, 8)
    ..cubicTo(48, 15, 22, 18, 0, 15)
    ..cubicTo(-8, 15, -8, -15, 0, -15)
    ..close();
  final grid = Path();
  for (var x = 10.0; x < 64; x += 10) {
    grid.addPath(_segment(Offset(x, -20), Offset(x, 20)), Offset.zero);
  }
  for (final y in [-5.0, 5.0]) {
    grid.addPath(_segment(Offset(0, y), Offset(70, y)), Offset.zero);
  }
  final upperLeaf = _leaf(const Offset(-12, 0), const Offset(26, -19), 15);
  final lowerLeaf = _leaf(const Offset(-12, 0), const Offset(26, 19), 15);
  Path kernel(Offset c, double turn) => _turn(
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: 12, height: 14),
            const Radius.circular(5))),
      c,
      turn);
  return _Glyph([
    _Shape(_place(cob, at, tilt), _yolk, inside: [
      _Mark(_place(grid, at, tilt), _strawDeep, width: 3),
      _Mark(
          _place(
              _segment(const Offset(16, -10), const Offset(40, -11)), at, tilt),
          _shine,
          width: 4),
    ]),
    _Shape(_place(upperLeaf, at, tilt), _husk),
    _Shape(_place(lowerLeaf, at, tilt), _husk, inside: [
      _Mark(
          _place(_segment(const Offset(4, 7), const Offset(18, 13)), at, tilt),
          _shine,
          width: 3.5),
    ]),
    _Shape(kernel(const Offset(60, 74), 0.3), _yolk, outline: 6),
    _Shape(kernel(const Offset(82, 56), -0.4), _yolk, outline: 6),
    _Shape(kernel(const Offset(78, 82), 0.5), _yolk, outline: 6),
  ]);
}

/// Thieving Crow: a black crow with a yolk beak and a shifty eye.
_Glyph _thievingCrow() {
  final tail = Path()
    ..moveTo(36, 58)
    ..lineTo(11, 74)
    ..lineTo(16, 84)
    ..lineTo(42, 72)
    ..close();
  const middle = Offset(48, 58);
  final body = _turn(
      Path()..addOval(Rect.fromCenter(center: middle, width: 54, height: 36)),
      middle,
      -0.38);
  final wing = _turn(
      Path()
        ..moveTo(28, 52)
        ..cubicTo(36, 44, 56, 44, 64, 52)
        ..lineTo(58, 62)
        ..lineTo(52, 59)
        ..lineTo(46, 66)
        ..lineTo(40, 61)
        ..lineTo(32, 66)
        ..close(),
      middle,
      -0.38);
  final beak = Path()
    ..moveTo(79, 27)
    ..quadraticBezierTo(88, 29, 91, 40)
    ..quadraticBezierTo(85, 42, 78, 44)
    ..close();
  final legs = Path()
    ..moveTo(44, 74)
    ..lineTo(42, 88)
    ..moveTo(54, 72)
    ..lineTo(56, 88);
  // A slate bird rather than an ink one: ink on the carton's ink fill
  // vanished.
  const crow = Color(0xFF4B5266);
  return _Glyph([
    _Line(legs, _ink, 3),
    _Shape(tail, crow),
    _Shape(body, crow),
    _Shape(wing, _crowWing, outline: 5),
    _Shape(_circle(const Offset(68, 35), 16), crow, inside: [
      _Mark(_arc(const Offset(68, 36), 10, math.pi * 1.05, 0.9),
          _shine.withValues(alpha: 0.35),
          width: 4),
    ]),
    _Shape(beak, _yolk, outline: 6),
    _Shape(_circle(const Offset(71, 32), 6.5), _shell, outline: 3, inside: [
      _Mark(_circle(const Offset(73, 33), 3.4), _ink),
      _Mark(_rect(60, 20, 82, 30.5), _ink),
    ]),
  ]);
}

/// An id the set does not know: a cream "?" on a yolk carton square.
_Glyph _questionCarton() {
  final question = Path()
    ..moveTo(38, 39)
    ..cubicTo(38, 25, 62, 25, 62, 39)
    ..cubicTo(62, 49, 50, 49, 50, 59);
  return _Glyph([
    _Shape(
        Path()
          ..addRRect(
              RRect.fromLTRBR(14, 14, 86, 86, const Radius.circular(16))),
        _yolk,
        inside: [
          _Mark(
              Path()
                ..addRRect(
                    RRect.fromLTRBR(20, 20, 80, 80, const Radius.circular(11))),
              _cartonEdge,
              width: 4),
          _Mark(_segment(const Offset(23, 30), const Offset(23, 48)), _shine,
              width: 5),
        ]),
    _Line(question, _cream, 9),
    _Shape(_circle(const Offset(50, 72), 5), _cream, outline: 6),
  ]);
}

// ---- drawing ------------------------------------------------------------------------------

/// One icon: its parts back to front on the [_box] square. The cream edge
/// goes down first, under every part, so only the silhouette's outside
/// keeps it.
class _Glyph {
  final List<_Part> parts;

  const _Glyph(this.parts);

  void paint(Canvas canvas) {
    for (final part in parts) {
      part.paintEdge(canvas);
    }
    for (final part in parts) {
      part.paint(canvas);
    }
  }
}

abstract class _Part {
  const _Part();

  /// This part's share of the cream edge: its outline, widened.
  void paintEdge(Canvas canvas) {}

  void paint(Canvas canvas);
}

/// A filled shape with an ink outline; [inside] is drawn on its fill,
/// clipped to it, under the outline.
class _Shape extends _Part {
  final Path path;
  final Color color;
  final double outline;
  final List<_Part> inside;

  const _Shape(
    this.path,
    this.color, {
    this.outline = _outline,
    this.inside = const [],
  });

  @override
  void paintEdge(Canvas canvas) =>
      canvas.drawPath(path, _stroke(_cream, outline + 2 * _edge));

  @override
  void paint(Canvas canvas) {
    canvas.drawPath(path, Paint()..color = color);
    if (inside.isNotEmpty) {
      canvas
        ..save()
        ..clipPath(path);
      for (final part in inside) {
        part.paint(canvas);
      }
      canvas.restore();
    }
    canvas.drawPath(path, _stroke(_ink, outline));
  }
}

/// An open line [width] wide, inked along both sides, round at the ends.
class _Line extends _Part {
  final Path path;
  final Color color;
  final double width;

  const _Line(this.path, this.color, this.width);

  @override
  void paintEdge(Canvas canvas) =>
      canvas.drawPath(path, _stroke(_cream, width + _outline + 2 * _edge));

  @override
  void paint(Canvas canvas) {
    canvas
      ..drawPath(path, _stroke(_ink, width + _outline))
      ..drawPath(path, _stroke(color, width));
  }
}

/// A detail on another part: no outline, no edge. A line when [width] is
/// given, else a fill.
class _Mark extends _Part {
  final Path path;
  final Color color;
  final double? width;

  const _Mark(this.path, this.color, {this.width});

  @override
  void paint(Canvas canvas) {
    final width = this.width;
    canvas.drawPath(
        path, width == null ? (Paint()..color = color) : _stroke(color, width));
  }
}

/// Parts drawn only inside [clip].
class _Clip extends _Part {
  final Path clip;
  final List<_Part> parts;

  const _Clip(this.clip, this.parts);

  @override
  void paintEdge(Canvas canvas) {
    canvas
      ..save()
      ..clipPath(clip);
    for (final part in parts) {
      part.paintEdge(canvas);
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas) {
    canvas
      ..save()
      ..clipPath(clip);
    for (final part in parts) {
      part.paint(canvas);
    }
    canvas.restore();
  }
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

// ---- shapes --------------------------------------------------------------------------------

Path _circle(Offset centre, double radius) =>
    Path()..addOval(Rect.fromCircle(center: centre, radius: radius));

Path _rect(double left, double top, double right, double bottom) =>
    Path()..addRect(Rect.fromLTRB(left, top, right, bottom));

Path _segment(Offset from, Offset to) => Path()
  ..moveTo(from.dx, from.dy)
  ..lineTo(to.dx, to.dy);

/// An arc of the circle at [centre]: from [start] radians, [sweep] on,
/// clockwise.
Path _arc(Offset centre, double radius, double start, double sweep) => Path()
  ..addArc(Rect.fromCircle(center: centre, radius: radius), start, sweep);

/// An egg [width] by [height] around [centre], widest a little below its
/// middle, turned [tilt] radians.
Path _egg(Offset centre, double width, double height, [double tilt = 0]) {
  final rx = width / 2;
  final ry = height / 2;
  Offset at(double x, double y) =>
      Offset(centre.dx + x * rx, centre.dy + y * ry);
  final top = at(0, -1);
  final right = at(1, 0.12);
  final bottom = at(0, 1);
  final left = at(-1, 0.12);
  final c1 = at(0.56, -1), c2 = at(1, -0.5);
  final c3 = at(1, 0.66), c4 = at(0.56, 1);
  final c5 = at(-0.56, 1), c6 = at(-1, 0.66);
  final c7 = at(-1, -0.5), c8 = at(-0.56, -1);
  final path = Path()
    ..moveTo(top.dx, top.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, right.dx, right.dy)
    ..cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, bottom.dx, bottom.dy)
    ..cubicTo(c5.dx, c5.dy, c6.dx, c6.dy, left.dx, left.dy)
    ..cubicTo(c7.dx, c7.dy, c8.dx, c8.dy, top.dx, top.dy)
    ..close();
  return tilt == 0 ? path : _turn(path, centre, tilt);
}

/// A drop flying out of [from]: its round end leading at [centre], its
/// point trailing back.
Path _flyingDrop(Offset centre, Offset from) {
  final back = from - centre;
  final drop = Path()
    ..moveTo(0, 13)
    ..cubicTo(3, 8, 9, 4, 9, -2)
    ..arcToPoint(const Offset(-9, -2),
        radius: const Radius.circular(9), clockwise: false)
    ..cubicTo(-9, 4, -3, 8, 0, 13)
    ..close();
  return _place(drop, centre, math.atan2(back.dy, back.dx) - math.pi / 2);
}

/// A leaf from [base] to [tip], [width] across at its widest.
Path _leaf(Offset base, Offset tip, double width) {
  final middle = (base + tip) / 2;
  final along = tip - base;
  final across = Offset(-along.dy, along.dx) / along.distance * width;
  final a = middle + across;
  final b = middle - across;
  return Path()
    ..moveTo(base.dx, base.dy)
    ..quadraticBezierTo(a.dx, a.dy, tip.dx, tip.dy)
    ..quadraticBezierTo(b.dx, b.dy, base.dx, base.dy)
    ..close();
}

/// [path] mirrored left to right across the middle of the box.
Path _mirror(Path path) => path.transform(Float64List.fromList([
      -1, 0, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      _box, 0, 0, 1, //
    ]));

/// [path] turned [angle] radians (clockwise on screen) about its origin,
/// then moved to [to].
Path _place(Path path, Offset to, double angle) {
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  return path.transform(Float64List.fromList([
    cos, sin, 0, 0, //
    -sin, cos, 0, 0, //
    0, 0, 1, 0, //
    to.dx, to.dy, 0, 1, //
  ]));
}

/// [path] turned [angle] radians (clockwise on screen) about [pivot].
Path _turn(Path path, Offset pivot, double angle) =>
    _place(path.shift(-pivot), pivot, angle);
