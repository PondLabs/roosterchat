// The targeting reticle of Sunny Side Putt: while a point power-up is
// armed, what it would do where the pointer is, drawn flat on the green
// through the 3D camera - the Rabbit Hole's reach around my egg and where
// the hop would land, the Sprinkler's spray and the eggs it would soak, the
// Gust's pull on every other egg. Painted over the world, under the HUD,
// and never in the way of a pointer.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'putt_art.dart';
import 'putt_match.dart';
import 'putt_targeting.dart';

/// Ground points to surface pixels (the world's own camera).
typedef PuttProjector = ui.Offset Function(Vec2 world);

class PuttReticle extends StatelessWidget {
  final PuttMatch match;
  final PuttTargeting targeting;
  final PuttProjector project;

  const PuttReticle({
    super.key,
    required this.match,
    required this.targeting,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    final armed = targeting.armed;
    if (armed == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ReticlePainter(
          effectId: armed,
          hover: targeting.hover,
          mine: match.myBall == null ? null : match.myEggRenderPosition,
          others: [
            for (final egg in PuttTargeting.otherEggs(match))
              match.renderPositionOf(egg.playerId),
          ],
          project: project,
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final String effectId;
  final Vec2? hover;
  final Vec2? mine;
  final List<Vec2> others;
  final PuttProjector project;

  _ReticlePainter({
    required this.effectId,
    required this.hover,
    required this.mine,
    required this.others,
    required this.project,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hover = this.hover;
    final mine = this.mine;
    switch (effectId) {
      case 'rabbit_hole':
        if (mine == null) return;
        // The hop's reach, around my egg.
        _ground(canvas, mine, kRabbitHoleMaxDistance,
            fill: PuttPalette.yolk.withValues(alpha: 0.1),
            stroke: PuttPalette.shell.withValues(alpha: 0.85),
            dashed: true);
        if (hover == null) return;
        var hop = hover - mine;
        if (hop.length > kRabbitHoleMaxDistance) {
          hop = hop.scaledTo(kRabbitHoleMaxDistance);
        }
        final landing = mine + hop;
        _dotted(canvas, project(mine), project(landing), PuttPalette.shell);
        _ground(canvas, landing, 0.9,
            fill: PuttPalette.yolk.withValues(alpha: 0.35),
            stroke: PuttPalette.yolk);
      case 'sprinkler':
        if (hover == null) return;
        _ground(canvas, hover, kSprinklerRadius,
            fill: PuttPalette.water.withValues(alpha: 0.22),
            stroke: PuttPalette.water);
        // The eggs it would soak, and which way the spray sends them.
        for (final egg in others) {
          final away = egg - hover;
          if (away.length > kSprinklerRadius) continue;
          _ground(canvas, egg, 0.8,
              fill: PuttPalette.comb.withValues(alpha: 0.18),
              stroke: PuttPalette.comb);
          if (away.length > 0.2) {
            _arrow(canvas, project(egg + away.scaledTo(0.9)),
                project(egg + away.scaledTo(2.6)), PuttPalette.shell);
          }
        }
        _crosshair(canvas, project(hover), PuttPalette.shell);
      case 'gust':
        if (hover == null) return;
        // Every other egg is pushed toward the spot.
        for (final egg in others) {
          final toward = hover - egg;
          if (toward.length < 0.2) continue;
          final reach = math.min(toward.length, 3.2);
          _arrow(canvas, project(egg), project(egg + toward.scaledTo(reach)),
              PuttPalette.shell);
        }
        _ground(canvas, hover, 1.1,
            fill: PuttPalette.shell.withValues(alpha: 0.2),
            stroke: PuttPalette.shell);
        _crosshair(canvas, project(hover), PuttPalette.shell);
      default:
        if (hover == null) return;
        _ground(canvas, hover, 1,
            fill: PuttPalette.yolk.withValues(alpha: 0.25),
            stroke: PuttPalette.yolk);
    }
  }

  /// A circle lying on the green, through the camera's perspective.
  void _ground(
    Canvas canvas,
    Vec2 center,
    double radius, {
    required Color fill,
    required Color stroke,
    bool dashed = false,
  }) {
    const segments = 48;
    final path = Path();
    for (var i = 0; i <= segments; i++) {
      final angle = i / segments * 2 * math.pi;
      final at =
          project(center + Vec2(math.cos(angle), math.sin(angle)) * radius);
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    if (!dashed) {
      canvas.drawPath(path, line);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 14) {
        canvas.drawPath(metric.extractPath(at, at + 8), line);
      }
    }
  }

  /// The spot itself: a small ring with ticks, ink-edged so it reads on
  /// grass and water alike.
  void _crosshair(Canvas canvas, Offset at, Color colour) {
    for (final (width, paint) in [
      (5.0, PuttPalette.ink.withValues(alpha: 0.55)),
      (2.4, colour),
    ]) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = paint;
      canvas.drawCircle(at, 7, line);
      for (final direction in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ]) {
        canvas.drawLine(at + direction * 11, at + direction * 16, line);
      }
    }
  }

  void _dotted(Canvas canvas, Offset from, Offset to, Color colour) {
    final dot = Paint()..color = colour;
    final length = (to - from).distance;
    if (length < 1) return;
    for (var at = 0.0; at <= length; at += 9) {
      canvas.drawCircle(Offset.lerp(from, to, at / length)!, 2, dot);
    }
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Color colour) {
    final shaft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: 0.9);
    final delta = to - from;
    if (delta.distance < 6) return;
    canvas.drawLine(from, to, shaft);
    final heading = delta.direction;
    for (final side in const [-1, 1]) {
      final wing = heading + math.pi + side * 0.5;
      canvas.drawLine(
          to, to + Offset(math.cos(wing), math.sin(wing)) * 9, shaft);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => true;
}
