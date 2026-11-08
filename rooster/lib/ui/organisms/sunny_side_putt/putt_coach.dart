// The aim coach: until the viewer's first putt of the match, and again
// whenever they sit a while with their egg ready, a hand over the egg
// shows the gesture - press, pull back away from the nest, let go - while
// the aim the green draws grows with it: the band back to the hand and the
// row of white chevrons toward the nest, one more per level of the pull
// (the HUD's hint line says it in words, out of the way of the eggs).
// The game hands it the egg's pixel and the way to the nest on screen
// after every rendered frame ([PuttCoachCue]); null hides it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'putt_art.dart';

/// Where the coach stands this frame: the egg's surface pixel and the
/// unit direction, on screen, from the egg to the nest.
@immutable
class PuttCoachCue {
  final Offset egg;
  final Offset toward;

  const PuttCoachCue({required this.egg, required this.toward});

  @override
  bool operator ==(Object other) =>
      other is PuttCoachCue && other.egg == egg && other.toward == toward;

  @override
  int get hashCode => Object.hash(egg, toward);
}

/// Where the coach draws for [cue], for the name tags to keep clear of:
/// the hand's whole pull (it is drawn from 14 px left of its point to 40
/// right, 4 above to 50 below) and the row of chevrons toward the nest.
/// Round 4's frames had the hand over other players' tags.
List<Rect> puttCoachObstacles(PuttCoachCue cue) {
  final back = -cue.toward;
  final press = cue.egg + back * 26;
  final pulled = cue.egg + back * (26 + 110);
  final hand = Rect.fromLTRB(
    math.min(press.dx, pulled.dx) - 14,
    math.min(press.dy, pulled.dy) - 4,
    math.max(press.dx, pulled.dx) + 40,
    math.max(press.dy, pulled.dy) + 50,
  );
  final row = Rect.fromPoints(cue.egg + cue.toward * _rowStart,
          cue.egg + cue.toward * (_rowStart + _rowLength))
      .inflate(14);
  return [hand, row];
}

/// Where the coach's row starts past the egg's pixel, one chevron's
/// length and the step to the next, as the green draws them.
const double _rowStart = 26;
const double _chevronLength = 9;
const double _chevronWidth = 22;
const double _chevronPitch = 16;
const int _rowLevels = 8;
const double _rowLength = (_rowLevels - 1) * _chevronPitch + _chevronLength;

/// The coach layer: listens to [cue] and loops the gesture over the egg.
class PuttCoach extends StatefulWidget {
  final ValueListenable<PuttCoachCue?> cue;

  const PuttCoach({super.key, required this.cue});

  @override
  State<PuttCoach> createState() => _PuttCoachState();
}

class _PuttCoachState extends State<PuttCoach>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    widget.cue.addListener(_cueChanged);
    _cueChanged();
  }

  @override
  void didUpdateWidget(PuttCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue != widget.cue) {
      oldWidget.cue.removeListener(_cueChanged);
      widget.cue.addListener(_cueChanged);
      _cueChanged();
    }
  }

  void _cueChanged() {
    final showing = widget.cue.value != null;
    if (showing && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!showing && _loop.isAnimating) {
      _loop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_cueChanged);
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<PuttCoachCue?>(
        valueListenable: widget.cue,
        builder: (context, cue, _) {
          if (cue == null) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _loop,
              builder: (context, _) =>
                  _gesture(cue, _loop.value, constraints.biggest),
            ),
          );
        },
      ),
    );
  }

  Widget _gesture(PuttCoachCue cue, double t, Size size) {
    final g = _CoachPose.at(t);
    final back = -cue.toward;
    final press = cue.egg + back * 26;
    final hand = press + back * (110 * g.pull);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CoachPainter(
              egg: cue.egg,
              toward: cue.toward,
              press: press,
              hand: hand,
              pose: g,
            ),
          ),
        ),
        // The hand: its fingertip on the press point.
        Positioned(
          left: hand.dx - 14,
          top: hand.dy - 4,
          child: Opacity(
            opacity: g.handAlpha,
            child: Transform.scale(
              scale: g.handScale,
              alignment: Alignment.topLeft,
              // An ink line round the cream hand (four crisp shadows) and
              // a soft drop under it: it reads over light and dark turf.
              child: const Icon(
                Icons.touch_app_rounded,
                size: 54,
                color: PuttPalette.cream,
                shadows: [
                  Shadow(color: PuttPalette.ink, offset: Offset(1.6, 0)),
                  Shadow(color: PuttPalette.ink, offset: Offset(-1.6, 0)),
                  Shadow(color: PuttPalette.ink, offset: Offset(0, 1.6)),
                  Shadow(color: PuttPalette.ink, offset: Offset(0, -1.6)),
                  Shadow(
                      color: Color(0x88211614),
                      blurRadius: 6,
                      offset: Offset(1, 3)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The gesture at loop time t: how far the hand has pulled (0..1), how it
/// shows, and how the aim and the press ripple look.
class _CoachPose {
  final double pull;
  final double handAlpha;
  final double handScale;
  final double arrowAlpha;
  final double ripple;

  const _CoachPose({
    required this.pull,
    required this.handAlpha,
    required this.handScale,
    required this.arrowAlpha,
    required this.ripple,
  });

  static double _ease(double k) => k * k * (3 - 2 * k);

  /// 0-0.1 the hand settles on the press point; 0.1-0.2 it presses (a
  /// ripple); 0.2-0.6 it pulls back while the aim grows; 0.6-0.7 it lets
  /// go (the aim fades, the hand lifts away); then it comes
  /// back to wait at the press point, half seen, for the next round - so
  /// the gesture is on screen nearly all the time.
  factory _CoachPose.at(double t) {
    if (t < 0.1) {
      final k = t / 0.1;
      return _CoachPose(
          pull: 0,
          handAlpha: 0.6 + 0.4 * k,
          handScale: 1.1 - 0.1 * k,
          arrowAlpha: 0,
          ripple: -1);
    }
    if (t < 0.2) {
      final k = (t - 0.1) / 0.1;
      return _CoachPose(
          pull: 0,
          handAlpha: 1,
          handScale: 1 - 0.1 * math.sin(k * math.pi),
          arrowAlpha: 0,
          ripple: k);
    }
    if (t < 0.6) {
      final k = _ease((t - 0.2) / 0.4);
      return _CoachPose(
          pull: k, handAlpha: 1, handScale: 0.95, arrowAlpha: 1, ripple: -1);
    }
    if (t < 0.7) {
      final k = (t - 0.6) / 0.1;
      return _CoachPose(
          pull: 1,
          handAlpha: 1 - k,
          handScale: 0.95 + 0.2 * k,
          arrowAlpha: 1 - k,
          ripple: -1);
    }
    final k = ((t - 0.7) / 0.12).clamp(0.0, 1.0);
    return _CoachPose(
        pull: 0, handAlpha: 0.6 * k, handScale: 1.1, arrowAlpha: 0, ripple: -1);
  }
}

class _CoachPainter extends CustomPainter {
  final Offset egg;
  final Offset toward;
  final Offset press;
  final Offset hand;
  final _CoachPose pose;

  const _CoachPainter({
    required this.egg,
    required this.toward,
    required this.press,
    required this.hand,
    required this.pose,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The press: a ring spreading from the fingertip.
    if (pose.ripple >= 0) {
      canvas.drawCircle(
        press,
        8 + pose.ripple * 22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = PuttPalette.cream.withValues(alpha: 1 - pose.ripple),
      );
    }
    if (pose.arrowAlpha <= 0) return;
    final ink = PuttPalette.ink.withValues(alpha: 0.55 * pose.arrowAlpha);
    final white = Colors.white.withValues(alpha: 0.95 * pose.arrowAlpha);
    // The pull: the band from the egg back to the hand, a ring at its end,
    // as the green draws it.
    final back = -toward;
    final bandStart = egg + back * 12;
    final bandLength = (hand - bandStart).distance;
    if (pose.pull > 0.02 && bandLength > 8) {
      for (final (width, paint) in [(9.0, ink), (5.0, white)]) {
        canvas.drawLine(
            bandStart,
            hand,
            Paint()
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round
              ..color = paint);
      }
      canvas
        ..drawCircle(
            hand,
            10,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8
              ..color = ink)
        ..drawCircle(
            hand,
            10,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = white);
    }
    // The row: one white chevron per level of the pull, toward the nest.
    final levels = (pose.pull * _rowLevels).ceil().clamp(1, _rowLevels);
    final side = Offset(-toward.dy, toward.dx);
    for (var i = 0; i < levels; i++) {
      final base = egg + toward * (_rowStart + i * _chevronPitch);
      final tip = base + toward * _chevronLength;
      final path = Path()
        ..moveTo(base.dx + side.dx * _chevronWidth / 2,
            base.dy + side.dy * _chevronWidth / 2)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(base.dx - side.dx * _chevronWidth / 2,
            base.dy - side.dy * _chevronWidth / 2)
        ..close();
      canvas
        ..drawPath(
            path.shift(back * 2.5),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = ink)
        ..drawPath(path, Paint()..color = white);
    }
  }

  @override
  bool shouldRepaint(_CoachPainter oldDelegate) =>
      oldDelegate.egg != egg ||
      oldDelegate.toward != toward ||
      oldDelegate.hand != hand ||
      oldDelegate.pose.arrowAlpha != pose.arrowAlpha ||
      oldDelegate.pose.ripple != pose.ripple;
}
