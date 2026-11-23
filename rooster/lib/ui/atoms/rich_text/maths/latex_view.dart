import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rooster/ui/atoms/rich_text/maths/latex_parser.dart';

/// Draws a `data-mx-maths` formula with Flutter widgets. A formula that does
/// not parse is shown as its LaTeX source in monospace.
class LatexView extends StatelessWidget {
  const LatexView(this.latex, {this.display = false, this.style, super.key});

  final String latex;

  /// Block (`<div>`) rather than inline (`<span>`) maths.
  final bool display;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    MathNode? node;
    try {
      node = LatexParser.parse(latex);
    } on LatexParseException {
      node = null;
    }

    final Widget content = node == null
        ? LatexFallback(latex, style: base)
        : _MathBuilder(base, display).build(node, 1);

    return Semantics(
      label: latex,
      excludeSemantics: true,
      child: display
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: content))
          : content,
    );
  }
}

/// The LaTeX source of a formula that could not be drawn.
class LatexFallback extends StatelessWidget {
  const LatexFallback(this.latex, {required this.style, super.key});

  final String latex;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(latex,
        style: style.copyWith(
            fontFamily: 'Code',
            fontFeatures: const [FontFeature.disable('calt')]));
  }
}

/// A fraction: numerator over a rule over denominator.
class LatexFractionBox extends StatelessWidget {
  const LatexFractionBox(
      {required this.numerator,
      required this.denominator,
      required this.color,
      required this.thickness,
      super.key});

  final Widget numerator;
  final Widget denominator;
  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: thickness * 2),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: numerator),
            Padding(
              padding: EdgeInsets.symmetric(vertical: thickness * 1.5),
              child:
                  ColoredBox(color: color, child: SizedBox(height: thickness)),
            ),
            Center(child: denominator),
          ],
        ),
      ),
    );
  }
}

/// A base with a superscript and/or a subscript.
class LatexScriptsBox extends StatelessWidget {
  const LatexScriptsBox(
      {required this.base,
      this.superscript,
      this.subscript,
      required this.shift,
      super.key});

  final Widget base;
  final Widget? superscript;
  final Widget? subscript;
  final double shift;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        base,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            superscript ?? SizedBox(height: shift),
            subscript ?? SizedBox(height: shift),
          ],
        ),
      ],
    );
  }
}

class _MathBuilder {
  _MathBuilder(this.style, this.display);

  final TextStyle style;
  final bool display;

  double get _fontSize => style.fontSize ?? 14;
  Color get _color => style.color ?? Colors.black;

  TextStyle _text(double scale, {bool italic = false, bool bold = false}) =>
      style.copyWith(
        fontSize: _fontSize * scale,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: bold ? FontWeight.bold : null,
        height: 1.1,
      );

  Widget build(MathNode node, double scale,
      {bool bold = false, bool upright = false}) {
    final size = _fontSize * scale;
    Widget child(MathNode n, double s) =>
        build(n, s, bold: bold, upright: upright);

    switch (node) {
      case MathSymbol(:final text, :final kind):
        final widget = Text(text,
            style: _text(scale,
                italic: kind == MathSymbolKind.variable && !upright,
                bold: bold));
        final gap = switch (kind) {
          MathSymbolKind.operator => size * 0.22,
          MathSymbolKind.relation => size * 0.28,
          _ => 0.0,
        };
        if (kind == MathSymbolKind.punctuation) {
          return Padding(
              padding: EdgeInsets.only(right: size * 0.17), child: widget);
        }
        return gap == 0
            ? widget
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: gap), child: widget);
      case MathRow(:final children):
        if (children.length == 1) return child(children.first, scale);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final c in children) child(c, scale)],
        );
      case MathFraction(:final numerator, :final denominator):
        final inner =
            display && scale >= 1 ? scale : math.max(0.6, scale * 0.8);
        return LatexFractionBox(
          numerator: child(numerator, inner),
          denominator: child(denominator, inner),
          color: _color,
          thickness: math.max(1, size * 0.06),
        );
      case MathScripts(:final base, :final superscript, :final subscript):
        final small = math.max(0.5, scale * 0.7);
        return LatexScriptsBox(
          base: child(base, scale),
          superscript: superscript == null ? null : child(superscript, small),
          subscript: subscript == null ? null : child(subscript, small),
          shift: size * 0.45,
        );
      case MathRoot(:final body, :final index):
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != null)
              Padding(
                padding: EdgeInsets.only(bottom: size * 0.5),
                child: child(index, math.max(0.5, scale * 0.55)),
              ),
            CustomPaint(
              painter: _RadicalPainter(_color, math.max(1, size * 0.06), size),
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(size * 0.6, size * 0.15, size * 0.1, 0),
                child: child(body, scale),
              ),
            ),
          ],
        );
      case MathDelimited(:final left, :final body, :final right):
        Widget delimiter(String text) => text.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(
                width: size * 0.4,
                child: FittedBox(
                    fit: BoxFit.fill,
                    child: Text(text, style: _text(scale, bold: bold))));
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              delimiter(left),
              Center(child: child(body, scale)),
              delimiter(right),
            ],
          ),
        );
      case MathSpace(:final width):
        return SizedBox(width: math.max(0, width * size));
      case MathStyled(child: final inner, bold: final b, upright: final u):
        return build(inner, scale, bold: bold || b, upright: upright || u);
    }
  }
}

class _RadicalPainter extends CustomPainter {
  _RadicalPainter(this.color, this.thickness, this.fontSize);

  final Color color;
  final double thickness;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final width = fontSize * 0.55;
    final top = thickness / 2;
    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..lineTo(width * 0.25, size.height * 0.52)
      ..lineTo(width * 0.55, size.height - top)
      ..lineTo(width, top)
      ..lineTo(size.width, top);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness);
  }

  @override
  bool shouldRepaint(_RadicalPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.thickness != thickness ||
      oldDelegate.fontSize != fontSize;
}
