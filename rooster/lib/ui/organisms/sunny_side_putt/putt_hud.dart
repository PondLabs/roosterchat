// The HUD of Sunny Side Putt, over the 3D farm: the course chip (top
// left), the hole bar (hole, par, my strokes and the timer, with the
// course's progress dots under it), the camera and settings buttons (top
// right), the headline banners, the scorecard (bottom left), the hint line
// (bottom centre), the power-up carton with its targeting (bottom right),
// and the between-hole, course-awards (putt_awards_card.dart) and
// match-over cards. Pure Flutter (the game
// renders under it), fed by the [PuttMatch] and, where a human taps back,
// callbacks and the [PuttTargeting] flow.
//
// Ink panels over the bright green, cream type, yolk for the numbers and
// comb red for the one urgent thing (the last fifteen seconds); Sora for
// numbers and banners, Nunito Sans for labels (docs/brand/README.md).
// Nothing sits over the middle of the green while a hole plays but a "?"
// box's prize, told big for three seconds as Putt Party tells it; every
// panel that only shows ignores pointers, so aim drags reach the game
// under the HUD.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/utils/common_strings.dart';

import 'putt_art.dart';
import 'putt_look.dart';
import 'putt_match.dart';
import 'putt_powerup_icons.dart';
import 'putt_targeting.dart';
import 'spectator_strip.dart';

part 'putt_awards_card.dart';

/// The assembled HUD over the game.
class PuttHud extends StatefulWidget {
  final PuttMatch match;

  /// The audio tap (buttons and slots click).
  final void Function(PuttSfx sfx)? onSfx;

  final VoidCallback onOpenMenu;

  /// The match-over card's leave button; default leaves through the match.
  final VoidCallback? onLeave;

  /// The camera button: the whole hole or back in close. No button when
  /// left out.
  final VoidCallback? onToggleCamera;

  /// Whether the camera shows the whole hole right now: the camera
  /// button's icon and tooltip offer the other view.
  final bool cameraOverview;

  /// The power-up targeting the view's pointer plumbing shares; the HUD
  /// keeps its own when left out (a HUD alone still casts and picks).
  final PuttTargeting? targeting;

  /// True while I aim or my egg rolls: the scorecard folds down to my own
  /// line, so the green it covered shows.
  final ValueListenable<bool>? busy;

  /// True while the keys hold the aim (rather than a drag): the hint line
  /// says how the keys putt.
  final ValueListenable<bool>? keyAiming;

  /// The name of the player the camera watches once my egg is in; null
  /// while it is on mine.
  final ValueListenable<String?>? watching;

  /// Whether the green is on screen yet: until it is, the banners wait
  /// (a hole's card plays when the player can see the hole, not during a
  /// slow boot). Left out, the green counts as shown.
  final ValueListenable<bool>? shown;

  const PuttHud({
    super.key,
    required this.match,
    required this.onOpenMenu,
    this.onSfx,
    this.onLeave,
    this.onToggleCamera,
    this.cameraOverview = false,
    this.targeting,
    this.busy,
    this.keyAiming,
    this.watching,
    this.shown,
  });

  @override
  State<PuttHud> createState() => _PuttHudState();
}

class _PuttHudState extends State<PuttHud> {
  PuttTargeting? _own;

  PuttTargeting get _targeting =>
      widget.targeting ?? (_own ??= PuttTargeting());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _tapSlot(int slot, String effectId) =>
      puttUseSlot(widget.match, _targeting, slot, effectId,
          onSfx: widget.onSfx);

  @override
  Widget build(BuildContext context) {
    final targeting = _targeting;
    return ListenableBuilder(
      listenable: targeting,
      builder: (context, _) {
        final match = widget.match;
        final inPlay = match.phase == PuttPhase.holePlay;
        final picking = inPlay && targeting.picking != null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(builder: (context, constraints) {
              final scorecardWidth =
                  math.min(240.0, constraints.maxWidth * 0.34);
              // The scorecard keeps to about a third of the height: on a
              // short screen the leaders and me, then how many more.
              final scorecardRows = ((constraints.maxHeight * 0.34 - 44) / 22)
                  .floor()
                  .clamp(3, 8);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _topRowHeight,
                        child: _PuttTopRow(
                          match: match,
                          onOpenMenu: widget.onOpenMenu,
                          onToggleCamera: widget.onToggleCamera,
                          cameraOverview: widget.cameraOverview,
                        ),
                      ),
                      Expanded(
                        child: _PuttMiddle(
                            match: match,
                            onLeave: widget.onLeave,
                            shown: widget.shown),
                      ),
                      if (inPlay)
                        _PuttBottomRow(
                          match: match,
                          targeting: targeting,
                          scorecardWidth: scorecardWidth,
                          scorecardRows: scorecardRows,
                          busy: widget.busy,
                          keyAiming: widget.keyAiming,
                          watching: widget.watching,
                          onTapSlot: _tapSlot,
                          onSfx: widget.onSfx,
                        ),
                    ],
                  ),
                  if (picking)
                    Positioned(
                      right: 0,
                      bottom: _slotSize + 12,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.max(
                            140.0,
                            constraints.maxHeight -
                                _topRowHeight -
                                _slotSize -
                                24,
                          ),
                        ),
                        child: PuttPlayerPicker(
                          match: match,
                          targeting: targeting,
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}

/// A carton slot used: what a click on it does, and what Enter or Space
/// do on the keyboard's highlight. A cast says so with its own sound;
/// arming and picking click.
void puttUseSlot(
  PuttMatch match,
  PuttTargeting targeting,
  int slot,
  String effectId, {
  void Function(PuttSfx sfx)? onSfx,
}) {
  if (puttPowerAimOf(effectId) != PuttPowerAim.none) {
    onSfx?.call(PuttSfx.click);
  }
  targeting.tapSlot(match, slot, effectId);
}

const double _topRowHeight = 88;
const double _slotSize = 56;
const double _slotGap = 8;

// ---- type, colour and panels -----------------------------------------------------------

/// The HUD's type: Sora for numbers and banners, Nunito Sans for labels.
/// Both are variable fonts, so the weight rides the axis as well.
abstract final class _Type {
  static FontWeight _weightOf(double weight) =>
      FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

  /// Numbers and banners: Sora, tabular figures so a ticking clock does
  /// not jiggle.
  static TextStyle display(
    double size, {
    Color color = PuttPalette.cream,
    double weight = 800,
    double height = 1.1,
  }) =>
      TextStyle(
        fontFamily: 'Sora',
        fontSize: size,
        height: height,
        color: color,
        fontWeight: _weightOf(weight),
        fontVariations: [FontVariation.weight(weight)],
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The small capitals over the numbers: Nunito Sans 800, spaced out.
  static TextStyle label(
    double size, {
    Color? color,
    double spacing = 1.1,
  }) =>
      TextStyle(
        fontFamily: 'NunitoSans',
        fontSize: size,
        height: 1.2,
        letterSpacing: spacing,
        color: color ?? PuttPalette.cream.withValues(alpha: 0.7),
        fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation.weight(800)],
      );

  /// Names and sentences: Nunito Sans.
  static TextStyle body(
    double size, {
    Color color = PuttPalette.cream,
    double weight = 700,
    FontStyle? style,
  }) =>
      TextStyle(
        fontFamily: 'NunitoSans',
        fontSize: size,
        height: 1.25,
        color: color,
        fontStyle: style,
        fontWeight: _weightOf(weight),
        fontVariations: [FontVariation.weight(weight)],
      );

  /// A Twemoji glyph from the bundled font.
  static TextStyle emoji(double size) => TextStyle(
        fontFamily: 'EmojiFont',
        fontSize: size,
        height: 1.0,
        color: PuttPalette.shell,
      );
}

/// The birdie's green: the one status colour the brand keeps besides its
/// own (green is what "under par, nicely done" reads as).
const Color _birdieGreen = Color(0xFF7BD35A);

/// The colour a score term is called in: gold for the rare ones, green
/// for a birdie, cream for par, stone and comb as it goes over.
Color puttTermColor(ScoreTerm term) => switch (term) {
      ScoreTerm.holeInOne ||
      ScoreTerm.albatross ||
      ScoreTerm.eagle =>
        PuttPalette.yolk,
      ScoreTerm.birdie => _birdieGreen,
      ScoreTerm.par => PuttPalette.cream,
      ScoreTerm.bogey => PuttPalette.stone,
      ScoreTerm.doubleBogey ||
      ScoreTerm.tripleBogey ||
      ScoreTerm.more =>
        PuttPalette.comb,
    };

/// A HUD panel: ink over the green, a hairline edge and a soft shadow so
/// it reads over grass and sky alike.
// Nearly solid: at 86% the farm behind (a flower, a bird) showed through
// the scorecard and the hole bar, over their text.
/// The HUD's panels: ink, as good as solid (at 0.93 the birds and the
/// trees behind still showed through the hole bar's numbers).
BoxDecoration _panel({
  double alpha = 0.98,
  double radius = 16,
  Color? edge,
  bool shadow = true,
}) =>
    BoxDecoration(
      color: PuttPalette.ink.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: edge ?? PuttPalette.cream.withValues(alpha: 0.08),
        width: edge == null ? 1 : 2,
      ),
      boxShadow: shadow ? _shadow : null,
    );

const List<BoxShadow> _shadow = [
  BoxShadow(color: Color(0x47000000), blurRadius: 14, offset: Offset(0, 4)),
];

/// A player's mark: a little egg in their colour, [size] tall, wearing
/// their look - the pattern they picked for their egg, their chick's hat
/// on top (`putt_look.dart` draws it).
class _TintDot extends StatelessWidget {
  final Color color;
  final PuttLook look;
  final double size;

  const _TintDot(this.color, {this.look = PuttLook.standard, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return PuttEggGlyph(tint: color, look: look, size: size);
  }
}

// ---- the top row: course chip, hole bar, buttons --------------------------------------

class _PuttTopRow extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback onOpenMenu;
  final VoidCallback? onToggleCamera;
  final bool cameraOverview;

  const _PuttTopRow({
    required this.match,
    required this.onOpenMenu,
    required this.onToggleCamera,
    required this.cameraOverview,
  });

  @override
  Widget build(BuildContext context) {
    final toggle = onToggleCamera;
    return CustomMultiChildLayout(
      delegate: _TopRowLayout(),
      children: [
        LayoutId(
          id: _TopRowLayout.chip,
          child: IgnorePointer(child: PuttCourseChip(match: match)),
        ),
        if (match.hole != null)
          LayoutId(
            id: _TopRowLayout.bar,
            child: IgnorePointer(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: PuttHoleBar(match: match),
              ),
            ),
          ),
        LayoutId(
          id: _TopRowLayout.buttons,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (toggle != null) ...[
                PuttRoundButton(
                  key: const Key('putt-camera'),
                  icon: cameraOverview
                      ? Icons.zoom_in_map_rounded
                      : Icons.zoom_out_map_rounded,
                  tooltip: cameraOverview
                      ? tooltipPuttCameraClose()
                      : tooltipPuttCameraWhole(),
                  onPressed: toggle,
                ),
                const SizedBox(width: 8),
              ],
              PuttRoundButton(
                key: const Key('putt-settings'),
                icon: Icons.settings_rounded,
                tooltip: labelPuttOpenMenu(),
                onPressed: onOpenMenu,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The top row's layout: the hole bar keeps the middle, the buttons the
/// right edge, and the course chip gets what is left of the left half.
/// The bar shrinks (its [FittedBox]) before it would run into a side.
class _TopRowLayout extends MultiChildLayoutDelegate {
  static const chip = 'chip';
  static const bar = 'bar';
  static const buttons = 'buttons';
  static const gap = 10.0;

  @override
  void performLayout(Size size) {
    var buttonsSize = Size.zero;
    if (hasChild(buttons)) {
      buttonsSize = layoutChild(buttons, BoxConstraints.loose(size));
      positionChild(buttons, Offset(size.width - buttonsSize.width, 0));
    }
    var barWidth = 0.0;
    if (hasChild(bar)) {
      final room = math.max(0.0, size.width - 2 * (buttonsSize.width + gap));
      barWidth = layoutChild(bar, BoxConstraints(maxWidth: room)).width;
      positionChild(bar, Offset((size.width - barWidth) / 2, 0));
    }
    if (hasChild(chip)) {
      final room = barWidth > 0
          ? (size.width - barWidth) / 2 - gap
          : size.width - buttonsSize.width - gap;
      layoutChild(chip, BoxConstraints(maxWidth: math.max(0.0, room)));
      positionChild(chip, Offset.zero);
    }
  }

  @override
  bool shouldRelayout(_TopRowLayout oldDelegate) => false;
}

/// Which course, which mode: the chip in the top left.
class PuttCourseChip extends StatelessWidget {
  final PuttMatch match;

  const PuttCourseChip({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final name = match.courseName;
    if (name == null) return const SizedBox.shrink();
    final second = match.phase == PuttPhase.awaitingNextCourse
        ? labelPuttCourseDone()
        : modeName(match.config.mode);
    return LayoutBuilder(builder: (context, constraints) {
      // Too narrow for a name worth reading: the bar says the rest.
      if (constraints.maxWidth < 96) return const SizedBox.shrink();
      return Container(
        constraints:
            BoxConstraints(maxWidth: math.min(constraints.maxWidth, 260)),
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: _panel(radius: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: PuttPalette.yolk.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag_rounded,
                  size: 17, color: PuttPalette.yolk),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Type.display(14.5, weight: 700, height: 1.2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    second.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Type.label(10,
                        color: PuttPalette.cream.withValues(alpha: 0.62)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

String labelPuttModeCasual() => Intl.message("Casual",
    name: "labelPuttModeCasual",
    desc: "The casual mode: one course, then the group votes the next");

String labelPuttModeTournament() => Intl.message("Tournament",
    name: "labelPuttModeTournament",
    desc: "The tournament mode: drawn courses, accumulated score");

String labelPuttModeBarnyardChaos() => Intl.message("Barnyard Chaos",
    name: "labelPuttModeBarnyardChaos",
    desc: "The chaos mode: everyone starts with two power-ups and double "
        "\"?\" boxes");

String modeName(GameMode mode) {
  switch (mode) {
    case GameMode.casual:
      return labelPuttModeCasual();
    case GameMode.tournament:
      return labelPuttModeTournament();
    case GameMode.barnyardChaos:
      return labelPuttModeBarnyardChaos();
  }
}

/// A round ink button with a cream icon: the camera and the settings.
class PuttRoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const PuttRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          const BoxDecoration(shape: BoxShape.circle, boxShadow: _shadow),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 22,
        style: IconButton.styleFrom(
          backgroundColor: PuttPalette.ink.withValues(alpha: 0.92),
          foregroundColor: PuttPalette.cream,
          hoverColor: PuttPalette.cream.withValues(alpha: 0.1),
          fixedSize: const Size(44, 44),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          side: BorderSide(color: PuttPalette.cream.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

// ---- the hole bar ---------------------------------------------------------------------------

/// The strip across the top: HOLE 3/6, PAR 3, STROKES 2 (mine, this hole)
/// and the clock, with the course's holes as dots under it.
class PuttHoleBar extends StatelessWidget {
  final PuttMatch match;

  const PuttHoleBar({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final hole = match.hole;
    if (hole == null) return const SizedBox.shrink();
    final inCourse = match.holeInCourse;
    final count = match.courseHoleCount;
    // Not translated: the hole's number over the course's count, digits.
    final holeText =
        inCourse > 0 && count > 0 ? '$inCourse/$count' : '${match.holeNumber}';
    final holed = match.myBall?.holed ?? false;
    final segments = <Widget>[
      _BarSegment(
        label: labelPuttBarHole(),
        child: Text(holeText, style: _barNumber()),
      ),
      _BarSegment(
        label: labelPuttBarPar(),
        child: Text('${hole.par}', style: _barNumber()),
      ),
      if (!match.isSpectator)
        _BarSegment(
          label: labelPuttBarStrokes(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${match.myStrokesThisHole}', style: _barNumber()),
              if (holed) ...[
                const SizedBox(width: 3),
                const Icon(Icons.check_rounded, size: 18, color: _birdieGreen),
              ],
            ],
          ),
        ),
      _BarSegment(
        label: labelPuttBarTime(),
        child: PuttTimerRing(
          secondsRemaining: match.secondsRemaining,
          totalSeconds: match.timerSeconds.toDouble(),
          running: match.phase == PuttPhase.holePlay,
        ),
      ),
    ];
    // The course's dots ride inside the bar, under its numbers: a pill of
    // their own under it covered a strip more of the green (round 4's
    // frames had crates and tags hidden behind it).
    final dots = inCourse > 0 && count > 1;
    return Container(
      padding: EdgeInsets.fromLTRB(6, 7, 6, dots ? 6 : 7),
      decoration: _panel(radius: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 30,
                    color: PuttPalette.cream.withValues(alpha: 0.12),
                  ),
                segments[i],
              ],
            ],
          ),
          if (dots) ...[
            const SizedBox(height: 5),
            PuttHoleDots(current: inCourse, count: count, bare: true),
          ],
        ],
      ),
    );
  }

  static TextStyle _barNumber() =>
      _Type.display(22, color: PuttPalette.yolk, height: 1.05);
}

class _BarSegment extends StatelessWidget {
  final String label;
  final Widget child;

  const _BarSegment({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), maxLines: 1, style: _Type.label(10)),
            const SizedBox(height: 2),
            child,
          ],
        ),
      ),
    );
  }
}

/// The course's holes as dots: played filled cream, the current one yolk
/// and larger, the rest outlined.
class PuttHoleDots extends StatelessWidget {
  /// The hole on the green, 1-based.
  final int current;
  final int count;

  /// Inside another panel (the hole bar): no pill of its own.
  final bool bare;

  const PuttHoleDots(
      {super.key,
      required this.current,
      required this.count,
      this.bare = false});

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var hole = 1; hole <= count; hole++) _dot(hole),
      ],
    );
    return Semantics(
      label: labelPuttHoleOf(current, count),
      child: bare
          ? row
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: _panel(alpha: 0.62, radius: 10, shadow: false),
              child: row,
            ),
    );
  }

  Widget _dot(int hole) {
    final now = hole == current;
    final played = hole < current;
    final size = now ? 10.0 : 7.0;
    return Container(
      key: Key('putt-hole-dot-$hole'),
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: now
            ? PuttPalette.yolk
            : played
                ? PuttPalette.cream
                : null,
        border: now || played
            ? null
            : Border.all(
                color: PuttPalette.cream.withValues(alpha: 0.55), width: 1.4),
      ),
    );
  }
}

// ---- the timer ----------------------------------------------------------------------------

/// The hole's clock: a small ring that empties clockwise beside the time
/// left (m:ss), calm until fifteen seconds remain - then the pair turns
/// comb red and pulses, the colour the ears have already heard ticking.
class PuttTimerRing extends StatefulWidget {
  final double secondsRemaining;
  final double totalSeconds;

  /// Whether the clock is running: a hole over (cleared inside its last
  /// fifteen seconds) stops the pulse with it.
  final bool running;

  const PuttTimerRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    this.running = true,
  });

  @override
  State<PuttTimerRing> createState() => PuttTimerRingState();

  /// True while the clock should pulse: the hole's last fifteen seconds.
  bool get isPulsing =>
      running && secondsRemaining > 0 && secondsRemaining <= 15;
}

class PuttTimerRingState extends State<PuttTimerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant PuttTimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.isPulsing && !_reduceMotion) {
      // Started once: the HUD rebuilds every frame, and restarting the
      // repeat each time would pin the pulse at its peak.
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else if (pulse.isAnimating || pulse.value != 0) {
      pulse.stop();
      pulse.value = 0;
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.secondsRemaining.ceil().clamp(0, 5999);
    final urgent = widget.isPulsing;
    final colour = urgent ? PuttPalette.comb : PuttPalette.yolk;
    final progress = widget.totalSeconds <= 0
        ? 0.0
        : (widget.secondsRemaining / widget.totalSeconds).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final scale = 1 + 0.08 * Curves.easeInOut.transform(pulse.value);
        return Transform.scale(scale: scale, child: child);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (urgent) const SizedBox.shrink(key: Key('putt-timer-pulse')),
          SizedBox(
            key: const Key('putt-timer-ring'),
            width: 19,
            height: 19,
            child: CustomPaint(
              painter: _TimerRingPainter(progress: progress, colour: colour),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            puttClock(seconds),
            style: _Type.display(22, color: colour, height: 1.05),
          ),
        ],
      ),
    );
  }
}

/// The clock's face: minutes, a colon, two-digit seconds.
String puttClock(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  // Not translated: a clock readout (minutes:seconds), read the same way
  // in every language the game speaks.
  return '$minutes:$rest';
}

/// The clock's dial: a faint disc with the time left as a wedge that
/// drains clockwise from twelve, ringed so it never reads as a letter.
class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color colour;

  _TimerRingPainter({required this.progress, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius,
        Paint()..color = PuttPalette.cream.withValues(alpha: 0.16));
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2.5),
        -math.pi / 2,
        2 * math.pi * progress,
        true,
        Paint()..color = colour,
      );
    }
    canvas.drawCircle(
      center,
      radius - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.colour != colour;
}

// ---- the middle: headline banner, between-hole cards ----------------------------------

/// The middle of the screen: the newest headline, high up; between holes
/// a beat for it (my score term, or how the hole ended), then the results
/// card rising in; at match over the verdict card. Reduced motion shows the
/// card at once.
class _PuttMiddle extends StatefulWidget {
  final PuttMatch match;
  final VoidCallback? onLeave;

  /// See [PuttHud.shown].
  final ValueListenable<bool>? shown;

  const _PuttMiddle({required this.match, required this.onLeave, this.shown});

  @override
  State<_PuttMiddle> createState() => _PuttMiddleState();
}

class _PuttMiddleState extends State<_PuttMiddle>
    with SingleTickerProviderStateMixin {
  // The card waits for the last sink's celebration (the egg hatching in
  // the nest, the camera in close on it) before it rises over the green:
  // early, it stood over the chick and the nest (round 5's play-013800).
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  /// The results card fades in over the clock's last half second (the
  /// awards after it take just that rise).
  static const _reveal = Interval(0.86, 1, curve: Curves.easeOutCubic);

  bool _reduceMotion = false;

  /// The phase and hole the clock last started for.
  String? _seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncPhase();
  }

  @override
  void didUpdateWidget(covariant _PuttMiddle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPhase();
  }

  void _syncPhase() {
    final match = widget.match;
    final awards = match.engine.courseAwardsUp;
    final seen =
        '${match.phase.name}-${match.holeNumber}${awards ? '-awards' : ''}';
    if (seen == _seen) return;
    _seen = seen;
    if (match.phase != PuttPhase.holeScoreboard) {
      _clock.value = 0;
    } else if (_reduceMotion) {
      _clock.value = 1;
    } else if (awards) {
      // The awards follow the results card at once: only its rise.
      _clock.forward(from: _reveal.begin);
    } else {
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final phase = match.phase;
        final reveal = phase == PuttPhase.holeScoreboard
            ? _reveal.transform(_clock.value)
            : phase == PuttPhase.matchOver
                ? 1.0
                : 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The banner keeps its place in the tree through the phases,
            // so one that is up when the hole ends plays on rather than
            // popping a second time.
            Opacity(
              opacity: 1 - reveal,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.shown ?? const _Always(),
                builder: (context, shown, _) => shown
                    ? _banner() ?? const SizedBox.shrink()
                    : const SizedBox.shrink(),
              ),
            ),
            if (phase == PuttPhase.matchOver)
              LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: PuttMatchOverCard(
                    match: match,
                    onLeave: widget.onLeave,
                    maxHeight: constraints.maxHeight,
                  ),
                ),
              )
            else if (phase == PuttPhase.holeScoreboard)
              IgnorePointer(
                ignoring: reveal < 1,
                child: Opacity(
                  opacity: reveal,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - reveal)),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: match.engine.courseAwardsUp
                            ? PuttCourseAwardsCard(
                                match: match,
                                maxHeight: constraints.maxHeight,
                              )
                            : PuttHoleResultsCard(
                                match: match,
                                maxHeight: constraints.maxHeight,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The newest headline, high in the middle: under the hole bar, clear
  /// of the green's centre.
  Widget? _banner() {
    final match = widget.match;
    final headline = match.headline;
    if (headline == null) return null;
    return IgnorePointer(
      child: Align(
        // The hole's card low in the middle, over the near rail and the
        // meadow: up high it covered each hole's landmark (the barn, the
        // lake, the maze's far side) in the opening shot. The others high,
        // under the hole bar, clear of the green's middle.
        // A score call high, over the top of the hatch's close-up (the chick
        // stands in the middle of it).
        alignment: switch (match.headlineKind) {
          PuttHeadlineKind.holeStart => const Alignment(0, 0.5),
          // At the top, right under the hole bar: the hatch's close-up has
          // the chick under it.
          PuttHeadlineKind.scoreTerm => const Alignment(0, -1),
          _ => const Alignment(0, -0.62),
        },
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: PuttHeadline(
            headline,
            key: ValueKey(match.headlineSerial),
            detail: match.headlineDetail,
            kind: match.headlineKind,
            term: match.headlineTerm,
          ),
        ),
      ),
    );
  }
}

/// The banner that pops when a hole starts, I hole, time runs out.
class PuttHeadline extends StatefulWidget {
  final String text;

  /// A second, smaller line (a hole start's par and course).
  final String? detail;

  final PuttHeadlineKind? kind;

  /// The score term a [PuttHeadlineKind.scoreTerm] banner calls: its
  /// colour.
  final ScoreTerm? term;

  const PuttHeadline(
    this.text, {
    super.key,
    this.detail,
    this.kind,
    this.term,
  });

  @override
  State<PuttHeadline> createState() => _PuttHeadlineState();
}

class _PuttHeadlineState extends State<PuttHeadline>
    with SingleTickerProviderStateMixin {
  /// In, hold, out: the banner pops, stays a breath, then goes. The hole's
  /// own card goes with the camera's opening sweep, before the play view. A
  /// score call ("Hole in one!") waits for the chick's first hop: the
  /// close-up is the chick's before it is the banner's.
  static const int _scoreWaitMs = 900;
  static const int _showMs = 2600;
  static const int _holeStartMs = 1600;

  int get _waitMs =>
      widget.kind == PuttHeadlineKind.scoreTerm ? _scoreWaitMs : 0;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.kind == PuttHeadlineKind.holeStart
        ? const Duration(milliseconds: _holeStartMs)
        : Duration(milliseconds: _waitMs + _showMs),
  )..forward();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, child) {
        // Its own time, past the wait.
        final total = _clock.duration!.inMilliseconds;
        final shown = total - _waitMs;
        final t = ((_clock.value * total - _waitMs) / shown).clamp(0.0, 1.0);
        // 0-8%: in; 90-100%: out, a quick shrink and lift (a slow fade
        // left a ghost of the banner printed over the lawn).
        final appear = (t / 0.08).clamp(0.0, 1.0);
        final leave = ((t - 0.9) / 0.1).clamp(0.0, 1.0);
        final gone = 1 - leave;
        final opacity = (appear * gone * gone).clamp(0.0, 1.0);
        final scale = reduceMotion
            ? 1.0
            : (0.92 + 0.08 * Curves.easeOutCubic.transform(appear)) *
                (1 - 0.14 * leave);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, reduceMotion ? 0 : -18 * leave),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: _banner(),
    );
  }

  Widget _banner() {
    final kind = widget.kind;
    final term = widget.term;
    final big = kind == PuttHeadlineKind.holeStart ||
        kind == PuttHeadlineKind.scoreTerm;
    final colour = term == null ? PuttPalette.cream : puttTermColor(term);
    final detail = widget.detail;
    return Container(
      padding: EdgeInsets.fromLTRB(30, big ? 12 : 11, 30, big ? 15 : 13),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: _panel(
        alpha: 0.93,
        radius: 24,
        edge: term == null ? null : colour.withValues(alpha: 0.75),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: _Type.display(big ? 44 : 30, color: colour, height: 1.08),
          ),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(
              detail.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: _Type.label(14, color: PuttPalette.yolk, spacing: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- the cards -------------------------------------------------------------------------------

/// The scoreboard rows of players still in the match, in the engine's
/// order (rising total, then id).
List<ScoreRow> _presentRows(PuttMatch match) => [
      for (final row in match.scoreboard)
        if (match.engine.player(row.playerId) != null) row,
    ];

/// Golf ranks: ties share a place, the next one skips ahead (1, 1, 3).
List<int> _ranks(List<ScoreRow> rows) {
  final ranks = <int>[];
  for (var i = 0; i < rows.length; i++) {
    ranks.add(
        i > 0 && rows[i].total == rows[i - 1].total ? ranks[i - 1] : i + 1);
  }
  return ranks;
}

/// Between holes: the hole and its par, how it ended, and one row per
/// player ranked by total - their strokes here, the term they earned and
/// where they stand against par - with the Continue the host moves on.
class PuttHoleResultsCard extends StatelessWidget {
  final PuttMatch match;
  final double? maxHeight;

  const PuttHoleResultsCard({super.key, required this.match, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final par = match.par;
    final number =
        match.holeInCourse > 0 ? match.holeInCourse : match.holeNumber;
    final index = match.holeNumber - 1;
    final world = match.engine.world;
    final played = <ScoreRow>[];
    final watching = <ScoreRow>[];
    for (final row in _presentRows(match)) {
      final strokes = index >= 0 && index < row.holeStrokes.length
          ? row.holeStrokes[index]
          : null;
      (strokes == null ? watching : played).add(row);
    }
    final ranks = _ranks(played);
    final subtitle = match.holeEndLine ?? match.headline;
    return _PuttCard(
      maxHeight: maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            labelPuttResultsTitle(number, par),
            textAlign: TextAlign.center,
            style: _Type.display(24),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle.toUpperCase(),
              key: const Key('putt-results-subtitle'),
              textAlign: TextAlign.center,
              style: _Type.label(12, color: PuttPalette.yolk, spacing: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          const _TotalHeader(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < played.length; i++)
                    _CardRow(
                      rank: ranks[i],
                      tint: puttTintOf(match, played[i].playerId),
                      look: puttLookOf(match, played[i].playerId),
                      name: displayNameOf(match, played[i].playerId),
                      mine: played[i].playerId == match.localPlayerId,
                      detail: labelPuttHoleStrokes(
                          played[i].holeStrokes[index] ?? 0),
                      badge: _TermBadge(
                        term: ScoreTerm.of(
                            played[i].holeStrokes[index] ?? 0, par),
                        holed: world?.ball(played[i].playerId)?.holed ?? true,
                      ),
                      relative: played[i].relative,
                    ),
                  for (final row in watching)
                    _CardRow(
                      tint: puttTintOf(match, row.playerId),
                      look: puttLookOf(match, row.playerId),
                      name: displayNameOf(match, row.playerId),
                      mine: row.playerId == match.localPlayerId,
                      watching: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Only the host's own card continues; in a local match that is me.
          // In a live session the card moves on by itself: the button
          // fills as its seconds run out.
          _ContinueButton(match: match),
        ],
      ),
    );
  }
}

/// The results' Continue: tapping moves on at once; when the match moves
/// on by itself (a live session), a lighter band sweeps across the button
/// as the seconds run out.
class _ContinueButton extends StatefulWidget {
  final PuttMatch match;

  const _ContinueButton({required this.match});

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    return AnimatedBuilder(
      animation: _frames,
      builder: (context, _) {
        // The pause's full length is the match's: the card may be built
        // again while it runs, and the band must not start over.
        final left = match.engine.scoreboardSecondsLeft;
        final total = match.config.scoreboardSeconds.toDouble();
        final counting = total > 0 && left > 0;
        final done =
            counting ? (1 - left / total).clamp(0.0, 1.0).toDouble() : 0.0;
        return Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('putt-continue'),
                style: _cardButton(PuttPalette.comb),
                onPressed: match.advance,
                child: Text(counting
                    ? labelPuttContinueIn(left.ceil())
                    : labelPuttContinue()),
              ),
            ),
            // The time going: a cream bar filling along the button's foot
            // (an ink wash over the red dimmed the label and read as dark
            // red on red).
            if (done > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        key: const Key('putt-continue-time'),
                        widthFactor: done,
                        child: Container(
                          height: 4,
                          color: PuttPalette.cream.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Match over: the winner, the totals ranked, and the way out.
class PuttMatchOverCard extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback? onLeave;
  final double? maxHeight;

  const PuttMatchOverCard(
      {super.key, required this.match, this.onLeave, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final row in _presentRows(match))
        if (!match.engine.isSpectator(row.playerId)) row,
    ];
    final ranks = _ranks(rows);
    final winner = rows.isEmpty ? null : rows.first;
    final tie = rows.length > 1 && rows[1].total == rows[0].total;
    final title = winner == null
        ? labelPuttMatchOver()
        : tie
            ? labelPuttTie()
            : labelPuttWinner(displayNameOf(match, winner.playerId));
    return _PuttCard(
      maxHeight: maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Not translated: an emoji glyph, not a word.
          Text('🏆', textAlign: TextAlign.center, style: _Type.emoji(40)),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _Type.display(28, color: PuttPalette.yolk),
          ),
          if (winner != null) ...[
            const SizedBox(height: 4),
            Text(
              labelPuttMatchOver().toUpperCase(),
              textAlign: TextAlign.center,
              style: _Type.label(12),
            ),
          ],
          const SizedBox(height: 12),
          if (rows.isNotEmpty) const _TotalHeader(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _CardRow(
                      rank: ranks[i],
                      tint: puttTintOf(match, rows[i].playerId),
                      look: puttLookOf(match, rows[i].playerId),
                      name: displayNameOf(match, rows[i].playerId),
                      mine: rows[i].playerId == match.localPlayerId,
                      detail: labelPuttTotal(rows[i].total),
                      relative: rows[i].relative,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('putt-leave-green'),
            style: _cardButton(PuttPalette.combDeep),
            onPressed: onLeave ?? match.leave,
            child: Text(labelPuttLeaveGreen()),
          ),
        ],
      ),
    );
  }
}

ButtonStyle _cardButton(Color colour) => FilledButton.styleFrom(
      backgroundColor: colour,
      foregroundColor: PuttPalette.shell,
      minimumSize: const Size(0, 44),
      textStyle: _Type.body(15, weight: 800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// The cards' frame: a dark panel, big enough for eight players.
class _PuttCard extends StatelessWidget {
  final Widget child;
  final double? maxHeight;

  const _PuttCard({required this.child, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      constraints: BoxConstraints(
        maxWidth: 470,
        maxHeight: math.max(0.0, (maxHeight ?? double.infinity) - 12),
      ),
      // Solid, like the HUD's other panels: what stood behind it showed
      // through its rows.
      decoration: _panel(alpha: 0.98, radius: 22),
      child: child,
    );
  }
}

/// "TOTAL" over the cards' last column.
class _TotalHeader extends StatelessWidget {
  const _TotalHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 2),
      child: Text(
        labelPuttScorecardTotal().toUpperCase(),
        textAlign: TextAlign.end,
        style:
            _Type.label(9.5, color: PuttPalette.cream.withValues(alpha: 0.5)),
      ),
    );
  }
}

/// A card row: rank, colour dot, name, what they did (strokes), the term
/// badge, and the total against par.
class _CardRow extends StatelessWidget {
  final int? rank;
  final Color tint;
  final PuttLook look;
  final String name;
  final bool mine;
  final bool watching;
  final String? detail;
  final Widget? badge;
  final int relative;

  const _CardRow({
    this.rank,
    required this.tint,
    this.look = PuttLook.standard,
    required this.name,
    required this.mine,
    this.watching = false,
    this.detail,
    this.badge,
    this.relative = 0,
  });

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final badge = this.badge;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: mine
          ? BoxDecoration(
              color: PuttPalette.yolk.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              rank == null ? '' : '$rank',
              style: _Type.display(14,
                  color: rank == 1
                      ? PuttPalette.yolk
                      : PuttPalette.cream.withValues(alpha: 0.5)),
            ),
          ),
          _TintDot(tint, look: look, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mine ? labelPuttYouName(name) : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Type.body(14,
                  weight: mine ? 800 : 700,
                  color: watching ? PuttPalette.stone : PuttPalette.cream),
            ),
          ),
          if (watching)
            Text(
              labelPuttWatching(),
              style: _Type.body(12,
                  color: PuttPalette.stone, style: FontStyle.italic),
            )
          else ...[
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(
                detail,
                style: _Type.body(12,
                    color: PuttPalette.cream.withValues(alpha: 0.72)),
              ),
            ],
            if (badge != null) ...[const SizedBox(width: 8), badge],
            SizedBox(
              width: 44,
              child: Text(
                relativeText(relative),
                textAlign: TextAlign.end,
                style: _Type.display(16, color: _relativeColour(relative)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _relativeColour(int relative) => relative < 0
    ? PuttPalette.yolk
    : relative == 0
        ? PuttPalette.cream
        : PuttPalette.cream.withValues(alpha: 0.75);

/// The term a hole earned, as a pill in its colour; an egg that never
/// reached the nest says so instead.
class _TermBadge extends StatelessWidget {
  final ScoreTerm term;
  final bool holed;

  const _TermBadge({required this.term, required this.holed});

  @override
  Widget build(BuildContext context) {
    final colour = holed ? puttTermColor(term) : PuttPalette.stone;
    // Stone is too quiet for small type on ink: lift it toward cream.
    final ink = colour == PuttPalette.stone
        ? Color.lerp(PuttPalette.stone, PuttPalette.cream, 0.35)!
        : colour;
    return Container(
      constraints: const BoxConstraints(minWidth: 62),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Text(
        (holed ? puttBadgeText(term) : labelPuttBadgeOutOfTime()).toUpperCase(),
        maxLines: 1,
        textAlign: TextAlign.center,
        style: _Type.label(9.5, color: ink, spacing: 0.8),
      ),
    );
  }
}

/// The badge's word for a term (the banners call them with more cheer).
String puttBadgeText(ScoreTerm term) {
  switch (term) {
    case ScoreTerm.holeInOne:
      return labelPuttBadgeHoleInOne();
    case ScoreTerm.albatross:
      return labelPuttBadgeAlbatross();
    case ScoreTerm.eagle:
      return labelPuttBadgeEagle();
    case ScoreTerm.birdie:
      return labelPuttBadgeBirdie();
    case ScoreTerm.par:
      return labelPuttBadgePar();
    case ScoreTerm.bogey:
      return labelPuttBadgeBogey();
    case ScoreTerm.doubleBogey:
      return labelPuttBadgeDoubleBogey();
    case ScoreTerm.tripleBogey:
      return labelPuttBadgeTripleBogey();
    case ScoreTerm.more:
      return labelPuttBadgeMore();
  }
}

// ---- the bottom row: scorecard, hint, inventory ---------------------------------------

/// A listenable that is always false (no game told the HUD it is busy).
class _Never implements ValueListenable<bool> {
  const _Never();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A flag that is always up (the green shown, when nobody says).
class _Always implements ValueListenable<bool> {
  const _Always();

  @override
  bool get value => true;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _PuttBottomRow extends StatelessWidget {
  final PuttMatch match;
  final PuttTargeting targeting;
  final double scorecardWidth;
  final int scorecardRows;
  final ValueListenable<bool>? busy;
  final ValueListenable<bool>? keyAiming;
  final ValueListenable<String?>? watching;
  final void Function(int slot, String effectId) onTapSlot;
  final void Function(PuttSfx sfx)? onSfx;

  const _PuttBottomRow({
    required this.match,
    required this.targeting,
    required this.scorecardWidth,
    required this.scorecardRows,
    this.busy,
    this.keyAiming,
    this.watching,
    required this.onTapSlot,
    this.onSfx,
  });

  @override
  Widget build(BuildContext context) {
    final spectator = match.isSpectator;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: busy ?? const _Never(),
            builder: (context, folded, _) => AnimatedSize(
              duration: MediaQuery.maybeDisableAnimationsOf(context) == true
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomLeft,
              child: PuttScorecard(
                match: match,
                width: scorecardWidth,
                maxRows: scorecardRows,
                compact: folded,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IgnorePointer(
            child: PuttHintLine(
                match: match,
                targeting: targeting,
                aiming: busy,
                keyAiming: keyAiming,
                watching: watching),
          ),
        ),
        if (!spectator) ...[
          const SizedBox(width: 12),
          PuttInventory(
            slots: match.myInventory,
            enabled: PuttTargeting.canUseNow(match),
            activeSlot: targeting.armedSlot ?? targeting.pickingSlot,
            highlightSlot: targeting.keySlot,
            pickSerials: match.myPickSerials,
            onTap: onTapSlot,
            onSfx: onSfx,
          ),
        ],
      ],
    );
  }
}

/// The scorecard: every player by total - colour dot, name, strokes on
/// this hole (a check once in the nest), and the total against par - with
/// whoever is watching from the fence last. Past [maxRows] it shows the
/// leaders and me, then how many more.
class PuttScorecard extends StatelessWidget {
  final PuttMatch match;
  final double width;
  final int maxRows;

  /// Folded to my own line (while I aim or my egg rolls).
  final bool compact;

  const PuttScorecard({
    super.key,
    required this.match,
    this.width = 240,
    this.maxRows = 8,
    this.compact = false,
  });

  static const double _holeColumn = 40;
  static const double _totalColumn = 42;

  @override
  Widget build(BuildContext context) {
    final engine = match.engine;
    final world = engine.world;
    final rows = _presentRows(match);
    // Players by total, then whoever watches.
    final all = [
      for (final row in rows)
        if (!engine.isSpectator(row.playerId)) row,
      for (final row in rows)
        if (engine.isSpectator(row.playerId)) row,
    ];
    var shown = all;
    if (all.length > maxRows) {
      // One line goes to the count of the rest; my own row always stays.
      final keep = math.max(1, maxRows - 1);
      final mine = all.indexWhere((row) => row.playerId == match.localPlayerId);
      shown = mine >= keep
          ? [...all.take(keep - 1), all[mine]]
          : all.take(keep).toList();
    }
    if (compact) {
      final mine = all.where((row) => row.playerId == match.localPlayerId);
      shown = mine.isNotEmpty ? [mine.first] : all.take(1).toList();
    }
    final hidden = compact ? 0 : all.length - shown.length;
    final header = _Type.label(9.5,
        color: PuttPalette.cream.withValues(alpha: 0.55), spacing: 0.9);
    // On a narrow screen (a phone held upright) the number columns give
    // way, so a row never runs out of room; the name keeps a sliver.
    final inner = width - 28; // the panel's padding and the row's
    final squeeze =
        ((inner - 40) / (_holeColumn + _totalColumn)).clamp(0.4, 1.0);
    final holeColumn = _holeColumn * squeeze;
    final totalColumn = _totalColumn * squeeze;
    return Container(
      key: const Key('putt-scorecard'),
      width: width,
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
      decoration: _panel(radius: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labelPuttScorecard().toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _Type.label(10.5),
                    ),
                  ),
                  for (final (label, width) in [
                    (labelPuttScorecardHole(), holeColumn),
                    (labelPuttScorecardTotal(), totalColumn),
                  ])
                    SizedBox(
                      width: width,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(label.toUpperCase(), style: header),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
          ],
          for (final row in shown)
            engine.isSpectator(row.playerId)
                ? _ScorecardRow(
                    name: displayNameOf(match, row.playerId),
                    tint: puttTintOf(match, row.playerId),
                    look: puttLookOf(match, row.playerId),
                    mine: row.playerId == match.localPlayerId,
                    holeColumn: holeColumn,
                    totalColumn: totalColumn,
                    watching: true,
                  )
                : _ScorecardRow(
                    name: displayNameOf(match, row.playerId),
                    tint: puttTintOf(match, row.playerId),
                    look: puttLookOf(match, row.playerId),
                    mine: row.playerId == match.localPlayerId,
                    holeColumn: holeColumn,
                    totalColumn: totalColumn,
                    strokes: engine.strokesInHole(row.playerId),
                    holed: world?.ball(row.playerId)?.holed ?? false,
                    relative: row.relative,
                  ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 3, 6, 1),
              child: Text(
                labelPuttScorecardMore(hidden),
                style: _Type.body(11.5,
                    color: PuttPalette.cream.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScorecardRow extends StatelessWidget {
  final String name;
  final Color tint;
  final PuttLook look;
  final bool mine;
  final double holeColumn;
  final double totalColumn;
  final bool watching;
  final int strokes;
  final bool holed;
  final int relative;

  const _ScorecardRow({
    required this.name,
    required this.tint,
    this.look = PuttLook.standard,
    required this.mine,
    required this.holeColumn,
    required this.totalColumn,
    this.watching = false,
    this.strokes = 0,
    this.holed = false,
    this.relative = 0,
  });

  @override
  Widget build(BuildContext context) {
    final number = _Type.display(14,
        color: strokes == 0 && !holed
            ? PuttPalette.cream.withValues(alpha: 0.45)
            : PuttPalette.cream);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: mine
          ? BoxDecoration(
              color: PuttPalette.yolk.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          _TintDot(tint, look: look, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mine ? labelPuttYouName(name) : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Type.body(12.5,
                  weight: mine ? 800 : 700,
                  color: watching ? PuttPalette.stone : PuttPalette.cream),
            ),
          ),
          if (watching)
            Flexible(
              child: Text(
                labelPuttWatching(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Type.body(11,
                    color: PuttPalette.stone, style: FontStyle.italic),
              ),
            )
          else ...[
            SizedBox(
              width: holeColumn,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (holed)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(Icons.check_rounded,
                            size: 14, color: _birdieGreen),
                      ),
                    Text('$strokes', style: number),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: totalColumn,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  relativeText(relative),
                  style: _Type.display(14, color: _relativeColour(relative)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The line at the bottom centre: what to do right now. The targeting
/// prompt while a slot is armed, a short "not now" when a tap could not
/// arm, "drag anywhere to aim" until the first putt and "let go to putt"
/// while that first pull is on, the spectator note while watching. Where
/// a keyboard is likely (desktop, a browser), the first line also names
/// the keys once, and a pull held by the keys says how they putt.
class PuttHintLine extends StatefulWidget {
  final PuttMatch match;
  final PuttTargeting targeting;

  /// True while I aim or my egg rolls (the game's busy flag): with my egg
  /// at rest, a pull is on.
  final ValueListenable<bool>? aiming;

  /// True while the keys hold the aim, not a drag.
  final ValueListenable<bool>? keyAiming;

  /// Who the camera watches once my egg is in.
  final ValueListenable<String?>? watching;

  const PuttHintLine(
      {super.key,
      required this.match,
      required this.targeting,
      this.aiming,
      this.keyAiming,
      this.watching});

  /// Whether this platform likely has a keyboard: a desktop, or a browser
  /// (a phone's browser has none to speak of, so its platform rules).
  static bool get hasKeyboard {
    if (kIsWeb) {
      return defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }

  @override
  State<PuttHintLine> createState() => _PuttHintLineState();
}

class _PuttHintLineState extends State<PuttHintLine>
    with SingleTickerProviderStateMixin {
  /// How long a "not now" line stays up.
  late final AnimationController _notice;

  late int _noticeSerial;

  @override
  void initState() {
    super.initState();
    _notice = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _noticeSerial = widget.targeting.noticeSerial;
  }

  @override
  void didUpdateWidget(covariant PuttHintLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serial = widget.targeting.noticeSerial;
    if (serial != _noticeSerial) {
      _noticeSerial = serial;
      if (widget.targeting.notice != null) _notice.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _notice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    if (match.isSpectator) return SpectatorStrip(match: match);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final aiming = widget.aiming;
    final keyAiming = widget.keyAiming;
    final keys = PuttHintLine.hasKeyboard;
    return AnimatedBuilder(
      animation:
          Listenable.merge([_notice, aiming, keyAiming, widget.watching]),
      builder: (context, _) {
        final targeting = widget.targeting;
        final armed = targeting.armed;
        final notice = targeting.notice;
        final mine = match.myBall;
        final pulling = (aiming?.value ?? false) &&
            mine != null &&
            mine.asleep &&
            !mine.holed;
        Widget? line;
        if (armed != null) {
          line = _HintPill(
            key: ValueKey('armed-$armed'),
            powerUp: armed,
            text: labelPuttTargetPrompt(armed),
            detail: labelPuttTargetCancel(),
            accent: true,
          );
        } else if (notice != null && _notice.isAnimating) {
          line =
              _HintPill(key: ValueKey('notice-$_noticeSerial'), text: notice);
        } else if (match.myShotReady &&
            !match.hasPutted &&
            targeting.picking == null) {
          final byKeys = keyAiming?.value ?? false;
          line = pulling && byKeys
              ? _HintPill(
                  key: const ValueKey('release-keys'),
                  icon: Icons.keyboard_rounded,
                  text: labelPuttKeyReleaseHint(),
                  detail: labelPuttKeyReleaseDetail(),
                )
              : pulling
                  ? _HintPill(
                      key: const ValueKey('release'),
                      icon: Icons.sports_golf_rounded,
                      text: labelPuttReleaseHint(),
                    )
                  : _HintPill(
                      key: const ValueKey('aim'),
                      icon: Icons.touch_app_rounded,
                      text: labelPuttAimHint(),
                      detail: keys ? labelPuttKeysHint() : null,
                    );
        } else if (widget.watching?.value case final name?) {
          line = _HintPill(
            key: ValueKey('watching-$name'),
            icon: Icons.visibility_rounded,
            text: labelPuttWatchingPlayer(name),
          );
        }
        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            // The new line takes the old one's place at once and fades in:
            // two lines crossfading on one pill read as a muddle.
            layoutBuilder: (current, previous) =>
                current ?? const SizedBox.shrink(),
            child: line ?? const SizedBox.shrink(key: ValueKey('none')),
          ),
        );
      },
    );
  }
}

class _HintPill extends StatelessWidget {
  final String text;
  final String? detail;

  /// The power-up the line is about, by effect id: its icon leads.
  final String? powerUp;
  final IconData? icon;
  final bool accent;

  const _HintPill({
    super.key,
    required this.text,
    this.detail,
    this.powerUp,
    this.icon,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final powerUp = this.powerUp;
    final icon = this.icon;
    final detail = this.detail;
    return Container(
      key: const Key('putt-hint'),
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: _panel(
        alpha: 0.92,
        radius: 16,
        edge: accent ? PuttPalette.yolk.withValues(alpha: 0.7) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (powerUp != null) ...[
            PuttPowerUpIcon(effectId: powerUp, size: 24),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: 18, color: PuttPalette.yolk),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _Type.body(13.5, weight: 800),
                ),
                // A size up and brighter: at 11.5 it read as small print.
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Type.body(12.5,
                        color: PuttPalette.cream.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- the power-up carton ------------------------------------------------------------------

/// The power-up inventory: three slots filled left to right, each power-up
/// its icon on ink with the name and what it does in the tooltip; empty
/// slots a dashed outline. The slot whose power-up waits for a spot or a
/// player glows; the one the keyboard's Tab is on wears a ring. A "?" box's
/// prize is told where it lands: its slot pops with a flash and says the
/// prize's name over itself for a moment. (It was told by a big card in the
/// middle of the screen, a slot machine's reel over the egg being played:
/// in the way.)
class PuttInventory extends StatelessWidget {
  final List<String> slots;
  final void Function(int slot, String effectId)? onTap;
  final bool enabled;

  /// The slot that is armed or picking, if any.
  final int? activeSlot;

  /// The slot the keyboard's highlight is on, if any.
  final int? highlightSlot;

  /// Per slot, how many "?" boxes have dropped a power-up into it
  /// ([PuttMatch.myPickSerials]): a count that moves is a prize arriving.
  final List<int> pickSerials;

  /// The prize's sound as its slot names it.
  final void Function(PuttSfx sfx)? onSfx;

  const PuttInventory({
    super.key,
    required this.slots,
    this.onTap,
    this.enabled = true,
    this.activeSlot,
    this.highlightSlot,
    this.pickSerials = const [],
    this.onSfx,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('putt-inventory'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < PowerUpInventory.cap; i++) ...[
          if (i > 0) const SizedBox(width: _slotGap),
          _PowerSlot(
            index: i,
            effectId: i < slots.length ? slots[i] : null,
            enabled: enabled,
            active: activeSlot == i,
            highlighted: highlightSlot == i && i < slots.length,
            pickSerial: i < pickSerials.length ? pickSerials[i] : 0,
            onTap: onTap,
            onSfx: onSfx,
          ),
        ],
      ],
    );
  }
}

class _PowerSlot extends StatefulWidget {
  final int index;
  final String? effectId;
  final bool enabled;
  final bool active;
  final bool highlighted;
  final int pickSerial;
  final void Function(int slot, String effectId)? onTap;
  final void Function(PuttSfx sfx)? onSfx;

  const _PowerSlot({
    required this.index,
    required this.effectId,
    required this.enabled,
    required this.active,
    required this.highlighted,
    required this.onTap,
    this.pickSerial = 0,
    this.onSfx,
  });

  @override
  State<_PowerSlot> createState() => _PowerSlotState();
}

class _PowerSlotState extends State<_PowerSlot> with TickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// A power-up just in the slot says its name above it for a moment: the
  /// icons alone told a new player nothing (and on a touch screen there is
  /// no hover for the tooltip).
  late final AnimationController _fresh = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// The prize landing: a pop of the icon and a flash round the slot.
  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncGlow();
  }

  @override
  void didUpdateWidget(covariant _PowerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncGlow();
    final effectId = widget.effectId;
    if (effectId == null) return;
    // A "?" box's prize: it lands with a pop, its sound, and its name.
    if (widget.pickSerial != oldWidget.pickSerial) {
      widget.onSfx?.call(PuttSfx.powerUpReveal);
      _land.forward(from: 0);
      _fresh.forward(from: 0);
      return;
    }
    // A power-up that moves in otherwise says its name; so does the one
    // Tab lands on (a keyboard has no hover for the tooltip).
    if (effectId != oldWidget.effectId ||
        (widget.highlighted && !oldWidget.highlighted)) {
      _fresh.forward(from: 0);
    }
  }

  void _syncGlow() {
    if (widget.active && !_reduceMotion) {
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    } else if (_glow.isAnimating) {
      _glow.stop();
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    _fresh.dispose();
    _land.dispose();
    super.dispose();
  }

  /// The new power-up's name over the slot: in, a hold, out.
  Widget _freshName(String name) {
    return AnimatedBuilder(
      animation: _fresh,
      builder: (context, child) {
        final t = _fresh.value;
        if (!_fresh.isAnimating || t >= 1) return const SizedBox.shrink();
        final appear = (t / 0.1).clamp(0.0, 1.0);
        final leave = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        return Opacity(
          opacity: appear * (1 - leave),
          child: Transform.translate(
            offset: Offset(0, _reduceMotion ? 0 : 6 * (1 - appear)),
            child: child,
          ),
        );
      },
      child: Container(
        key: const Key('putt-slot-fresh'),
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        decoration: BoxDecoration(
          color: PuttPalette.ink.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PuttPalette.yolk, width: 1.5),
          boxShadow: _shadow,
        ),
        child: Text(name,
            maxLines: 1, softWrap: false, style: _Type.body(12.5, weight: 800)),
      ),
    );
  }

  /// The prize just stopped: it pops big and settles with a bounce.
  Widget _landed(Widget icon) {
    if (!_land.isAnimating) return icon;
    final scale = 1.45 - 0.45 * Curves.elasticOut.transform(_land.value);
    return Transform.scale(scale: scale, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final effectId = widget.effectId;
    final key = Key('putt-slot-${widget.index}');
    if (effectId == null) {
      return Tooltip(
        message: labelPuttEmptySlot(),
        child: SizedBox(
          key: key,
          width: _slotSize,
          height: _slotSize,
          child: const CustomPaint(painter: _EmptySlotPainter()),
        ),
      );
    }
    final enabled = widget.enabled && widget.onTap != null;
    final active = widget.active;
    final name = puttPowerUpName(effectId);
    final slot = AnimatedBuilder(
      animation: Listenable.merge([_glow, _land]),
      builder: (context, child) {
        // The prize's landing: a cream flash fading to the yolk ring.
        final flash = _land.isAnimating ? 1 - _land.value : 0.0;
        final glow = !active
            ? 0.0
            : _reduceMotion
                ? 1.0
                : 0.55 + 0.45 * Curves.easeInOut.transform(_glow.value);
        return Container(
          width: _slotSize,
          height: _slotSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? Color.lerp(PuttPalette.ink, PuttPalette.yolk, 0.28)
                : Color.lerp(PuttPalette.ink.withValues(alpha: 0.86),
                    PuttPalette.yolk, 0.45 * flash),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(PuttPalette.yolk, PuttPalette.cream, flash)!,
              width: active || flash > 0 ? 3 : 2,
            ),
            boxShadow: [
              ..._shadow,
              if (active)
                BoxShadow(
                  color: PuttPalette.yolk.withValues(alpha: 0.6 * glow),
                  blurRadius: 6 + 14 * glow,
                  spreadRadius: 1 + 2 * glow,
                ),
              if (flash > 0)
                BoxShadow(
                  color: PuttPalette.yolk.withValues(alpha: 0.9 * flash),
                  blurRadius: 8 + 22 * (1 - flash),
                  spreadRadius: 2 + 8 * (1 - flash),
                ),
            ],
          ),
          child: _landed(child!),
        );
      },
      child: PuttPowerUpIcon(effectId: effectId, size: 28),
    );
    final named = Stack(
      clipBehavior: Clip.none,
      children: [
        slot,
        // The keyboard's highlight: a cream ring just outside the slot.
        if (widget.highlighted)
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('putt-slot-highlight'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PuttPalette.cream, width: 2.5),
                ),
              ),
            ),
          ),
        // Stepped up slot by slot, so three filled at once never overlap,
        // and flush with the slot's right edge: the carton stands at the
        // screen's, and a name centred on the last slot ran off it.
        Positioned(
          right: 0,
          bottom: _slotSize + 8 + widget.index * 32,
          child: IgnorePointer(child: _freshName(name)),
        ),
      ],
    );
    return Tooltip(
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: PuttPalette.ink.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
      ),
      richMessage: TextSpan(
        style: _Type.body(12.5, weight: 600),
        children: [
          TextSpan(text: name, style: _Type.body(13.5, weight: 800)),
          TextSpan(text: '\n${puttPowerUpDetail(effectId)}'),
        ],
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        focused: widget.highlighted,
        label: name,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => widget.onTap!(widget.index, effectId) : null,
            child: Opacity(opacity: widget.enabled ? 1 : 0.5, child: named),
          ),
        ),
      ),
    );
  }
}

/// An empty slot: the carton's dashed outline over a faint ink fill, an
/// empty egg cup (a faint egg's outline) in the middle.
class _EmptySlotPainter extends CustomPainter {
  const _EmptySlotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1.5), const Radius.circular(16));
    // Near solid, like the HUD's panels: at 0.55 the farm's flowers and
    // fences showed through it.
    canvas.drawRRect(
        rrect, Paint()..color = PuttPalette.ink.withValues(alpha: 0.82));
    // The cup: an egg's outline, broad at the base, narrower at the top.
    final w = size.width * 0.17;
    final h = size.height * 0.22;
    final c = size.center(Offset.zero);
    final egg = Path()
      ..moveTo(c.dx, c.dy - h)
      ..cubicTo(c.dx + w * 0.8, c.dy - h, c.dx + w * 1.12, c.dy + h * 0.1,
          c.dx + w, c.dy + h * 0.38)
      ..cubicTo(c.dx + w * 0.8, c.dy + h * 0.95, c.dx - w * 0.8,
          c.dy + h * 0.95, c.dx - w, c.dy + h * 0.38)
      ..cubicTo(c.dx - w * 1.12, c.dy + h * 0.1, c.dx - w * 0.8, c.dy - h, c.dx,
          c.dy - h)
      ..close();
    canvas
      ..drawPath(egg, Paint()..color = PuttPalette.cream.withValues(alpha: 0.1))
      ..drawPath(
          egg,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = PuttPalette.cream.withValues(alpha: 0.4));
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = PuttPalette.cream.withValues(alpha: 0.7);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 10) {
        canvas.drawPath(metric.extractPath(at, at + 5), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_EmptySlotPainter oldDelegate) => false;
}

/// The picker a player power-up opens over the carton: the players it can
/// go to (a colour dot, the name, and for the crow what it would take),
/// or why there is nobody - and nothing is spent until a pick.
class PuttPlayerPicker extends StatelessWidget {
  final PuttMatch match;
  final PuttTargeting targeting;

  const PuttPlayerPicker({
    super.key,
    required this.match,
    required this.targeting,
  });

  @override
  Widget build(BuildContext context) {
    final effectId = targeting.picking;
    if (effectId == null) return const SizedBox.shrink();
    final candidates = PuttTargeting.candidates(match, effectId);
    final crow = effectId == 'thieving_crow';
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('putt-picker'),
        width: 300,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
        decoration: _panel(
          alpha: 0.95,
          radius: 18,
          edge: PuttPalette.yolk.withValues(alpha: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PuttPowerUpIcon(effectId: effectId, size: 24),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    crow ? labelPuttPickSteal() : labelPuttPickSwap(),
                    maxLines: 2,
                    style: _Type.display(15, weight: 700, height: 1.2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 4, 6),
                child: Text(
                  PuttTargeting.nobodyToPick(match, effectId),
                  style: _Type.body(13,
                      color: PuttPalette.cream.withValues(alpha: 0.75)),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final id in candidates)
                        _PickRow(
                          key: Key('putt-pick-$id'),
                          name: displayNameOf(match, id),
                          tint: puttTintOf(match, id),
                          look: puttLookOf(match, id),
                          powerUp: crow ? _firstSlotPowerUp(id) : null,
                          onTap: () => targeting.castOn(match, id),
                        ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('putt-pick-cancel'),
                onPressed: targeting.cancel,
                style: TextButton.styleFrom(
                  foregroundColor: PuttPalette.cream,
                  textStyle: _Type.body(13, weight: 800),
                ),
                child: Text(CommonStrings.promptCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the crow would take from [playerId]: their first slot.
  String? _firstSlotPowerUp(String playerId) {
    final inventory = match.engine.player(playerId)?.inventory.toList();
    if (inventory == null || inventory.isEmpty) return null;
    return inventory.first;
  }
}

class _PickRow extends StatelessWidget {
  final String name;
  final Color tint;
  final PuttLook look;

  /// What picking this player would bring home, by effect id.
  final String? powerUp;
  final VoidCallback onTap;

  const _PickRow({
    super.key,
    required this.name,
    required this.tint,
    this.look = PuttLook.standard,
    required this.powerUp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final powerUp = this.powerUp;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: PuttPalette.yolk.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            _TintDot(tint, look: look, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Type.body(14, weight: 800),
              ),
            ),
            if (powerUp != null) ...[
              const SizedBox(width: 8),
              // What the crow would bring home: its icon and its name.
              Container(
                padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
                decoration: BoxDecoration(
                  color: PuttPalette.yolk.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PuttPowerUpIcon(effectId: powerUp, size: 24),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Text(
                        puttPowerUpName(powerUp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Type.body(12.5,
                            weight: 800, color: PuttPalette.yolk),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- power-up names and lines -----------------------------------------------------------
// (their icons are drawn in putt_powerup_icons.dart)

/// The twelve effects' display names, by id (the ids the engine's registry
/// carries; unknown ids fall back to themselves so nothing renders blank).
String puttPowerUpName(String effectId) {
  switch (effectId) {
    case 'hawk_eye':
      return labelPuttPowerHawkEye();
    case 'nest_magnet':
      return labelPuttPowerNestMagnet();
    case 'ghost_egg':
      return labelPuttPowerGhostEgg();
    case 'chicken_hop':
      return labelPuttPowerChickenHop();
    case 'rabbit_hole':
      return labelPuttPowerRabbitHole();
    case 'gust':
      return labelPuttPowerGust();
    case 'thick_shell':
      return labelPuttPowerThickShell();
    case 'strong_coffee':
      return labelPuttPowerStrongCoffee();
    case 'nest_swap':
      return labelPuttPowerNestSwap();
    case 'sprinkler':
      return labelPuttPowerSprinkler();
    case 'corn_rain':
      return labelPuttPowerCornRain();
    case 'thieving_crow':
      return labelPuttPowerThievingCrow();
    default:
      return effectId;
  }
}

/// What each effect does, in one line, for the slot's tooltip.
String puttPowerUpDetail(String effectId) {
  switch (effectId) {
    case 'hawk_eye':
      return labelPuttPowerHawkEyeDetail();
    case 'nest_magnet':
      return labelPuttPowerNestMagnetDetail();
    case 'ghost_egg':
      return labelPuttPowerGhostEggDetail();
    case 'chicken_hop':
      return labelPuttPowerChickenHopDetail();
    case 'rabbit_hole':
      return labelPuttPowerRabbitHoleDetail();
    case 'gust':
      return labelPuttPowerGustDetail();
    case 'thick_shell':
      return labelPuttPowerThickShellDetail();
    case 'strong_coffee':
      return labelPuttPowerStrongCoffeeDetail();
    case 'nest_swap':
      return labelPuttPowerNestSwapDetail();
    case 'sprinkler':
      return labelPuttPowerSprinklerDetail();
    case 'corn_rain':
      return labelPuttPowerCornRainDetail();
    case 'thieving_crow':
      return labelPuttPowerThievingCrowDetail();
    default:
      return puttPowerUpName(effectId);
  }
}

String labelPuttPowerHawkEye() => Intl.message("Hawk Eye",
    name: "labelPuttPowerHawkEye",
    desc: "Power-up: the next shot is perfectly straight, no wobble");

String labelPuttPowerNestMagnet() => Intl.message("Nest Magnet",
    name: "labelPuttPowerNestMagnet",
    desc: "Power-up: the egg turns magnetic when it passes near the nest");

String labelPuttPowerGhostEgg() => Intl.message("Ghost Egg",
    name: "labelPuttPowerGhostEgg",
    desc: "Power-up: the player's next shot passes through fences and "
        "obstacles");

String labelPuttPowerChickenHop() => Intl.message("Chicken Hop",
    name: "labelPuttPowerChickenHop",
    desc: "Power-up: the next shot flies over obstacles");

String labelPuttPowerRabbitHole() => Intl.message("Rabbit Hole",
    name: "labelPuttPowerRabbitHole",
    desc: "Power-up: teleport your egg a limited distance, no stroke "
        "spent");

String labelPuttPowerGust() => Intl.message("Gust",
    name: "labelPuttPowerGust",
    desc: "Power-up: wind pushes every egg but your own");

String labelPuttPowerThickShell() => Intl.message("Thick Shell",
    name: "labelPuttPowerThickShell",
    desc: "Power-up: blocks the next power-up aimed at you");

String labelPuttPowerStrongCoffee() => Intl.message("Strong Coffee",
    name: "labelPuttPowerStrongCoffee",
    desc: "Power-up: the next shot is thirty percent stronger");

String labelPuttPowerNestSwap() => Intl.message("Nest Swap",
    name: "labelPuttPowerNestSwap",
    desc: "Power-up: swap your egg's position with a chosen player's");

String labelPuttPowerSprinkler() => Intl.message("Sprinkler",
    name: "labelPuttPowerSprinkler",
    desc: "Power-up: mark a point; eggs near it are pushed away");

String labelPuttPowerCornRain() => Intl.message("Corn Rain",
    name: "labelPuttPowerCornRain",
    desc: "Power-up: corn kernels nudge every egg but your own");

String labelPuttPowerThievingCrow() => Intl.message("Thieving Crow",
    name: "labelPuttPowerThievingCrow",
    desc: "Power-up: steal a power-up from a chosen player");

String labelPuttPowerHawkEyeDetail() =>
    Intl.message("Your next shot goes dead straight, no wobble.",
        name: "labelPuttPowerHawkEyeDetail",
        desc: "Tooltip line under the Hawk Eye power-up's name: what it "
            "does");

String labelPuttPowerNestMagnetDetail() =>
    Intl.message("Your next shot is pulled into the nest when it rolls close.",
        name: "labelPuttPowerNestMagnetDetail",
        desc: "Tooltip line under the Nest Magnet power-up's name: what it "
            "does");

String labelPuttPowerGhostEggDetail() =>
    Intl.message("Your next shot rolls through rails, rocks and hens.",
        name: "labelPuttPowerGhostEggDetail",
        desc: "Tooltip line under the Ghost Egg power-up's name: what it "
            "does");

String labelPuttPowerChickenHopDetail() =>
    Intl.message("Your next shot hops over whatever is in the way.",
        name: "labelPuttPowerChickenHopDetail",
        desc: "Tooltip line under the Chicken Hop power-up's name: what it "
            "does");

String labelPuttPowerRabbitHoleDetail() =>
    Intl.message("Pop your egg up at a spot nearby, no stroke spent.",
        name: "labelPuttPowerRabbitHoleDetail",
        desc: "Tooltip line under the Rabbit Hole power-up's name: what it "
            "does (the player picks the spot, a few steps away at most)");

String labelPuttPowerGustDetail() => Intl.message(
    "For a few seconds the wind blows every other egg toward a spot you pick.",
    name: "labelPuttPowerGustDetail",
    desc: "Tooltip line under the Gust power-up's name: what it does "
        "(the wind keeps carrying the eggs for a few seconds)");

String labelPuttPowerThickShellDetail() => Intl.message(
    "For half a minute, your egg shrugs off the next push another player sends.",
    name: "labelPuttPowerThickShellDetail",
    desc: "Tooltip line under the Thick Shell power-up's name: for "
        "thirty seconds it blocks the next Gust, Sprinkler or Corn "
        "Rain that would hit the player's egg");

String labelPuttPowerStrongCoffeeDetail() =>
    Intl.message("Your next shot leaves 30% harder.",
        name: "labelPuttPowerStrongCoffeeDetail",
        desc: "Tooltip line under the Strong Coffee power-up's name: what it "
            "does");

String labelPuttPowerNestSwapDetail() =>
    Intl.message("Trade places with another player's egg.",
        name: "labelPuttPowerNestSwapDetail",
        desc: "Tooltip line under the Nest Swap power-up's name: what it "
            "does");

String labelPuttPowerSprinklerDetail() => Intl.message(
    "Soak a spot for a few seconds: the eggs around it get pushed away.",
    name: "labelPuttPowerSprinklerDetail",
    desc: "Tooltip line under the Sprinkler power-up's name: what it "
        "does");

String labelPuttPowerCornRainDetail() =>
    Intl.message("Corn kernels rain down and knock every egg but yours about.",
        name: "labelPuttPowerCornRainDetail",
        desc: "Tooltip line under the Corn Rain power-up's name: what it "
            "does");

String labelPuttPowerThievingCrowDetail() =>
    Intl.message("Steal a power-up from another player.",
        name: "labelPuttPowerThievingCrowDetail",
        desc: "Tooltip line under the Thieving Crow power-up's name: what it "
            "does (it takes the other player's first one)");

// ---- strings ---------------------------------------------------------------------------------

String labelPuttOpenMenu() => Intl.message("Settings (Esc)",
    name: "labelPuttOpenMenu",
    desc: "Tooltip of the HUD's settings (gear) button: the volume sliders "
        "and leave; Esc opens it too");

String tooltipPuttCameraWhole() => Intl.message("See the whole hole (C)",
    name: "tooltipPuttCameraWhole",
    desc: "Tooltip of the HUD's camera button while the camera is in close: "
        "it pulls back to show the whole hole; C is the key that does the "
        "same");

String tooltipPuttCameraClose() => Intl.message("Back in close (C)",
    name: "tooltipPuttCameraClose",
    desc: "Tooltip of the HUD's camera button while it shows the whole "
        "hole: it goes back to the close view of the player's egg; C is the "
        "key that does the same");

String labelPuttBarHole() => Intl.message("Hole",
    name: "labelPuttBarHole",
    desc: "Small label in the bar at the top of the game, over the hole's "
        "number in its course (e.g. 3/6)");

String labelPuttBarPar() => Intl.message("Par",
    name: "labelPuttBarPar",
    desc: "Small label in the bar at the top of the game, over the hole's "
        "par (the strokes it should take)");

String labelPuttBarStrokes() => Intl.message("Strokes",
    name: "labelPuttBarStrokes",
    desc: "Small label in the bar at the top of the game, over the strokes "
        "the player has taken on this hole");

String labelPuttBarTime() => Intl.message("Time",
    name: "labelPuttBarTime",
    desc: "Small label in the bar at the top of the game, over the time "
        "left on the hole's clock");

String labelPuttHoleOf(int hole, int count) =>
    Intl.message("Hole $hole of $count",
        name: "labelPuttHoleOf",
        args: [hole, count],
        desc: "Read out for the row of dots under the top bar, one per hole "
            "of the course: which hole is on the green, e.g. Hole 2 of 6");

String labelPuttCourseDone() => Intl.message("Course done",
    name: "labelPuttCourseDone",
    desc: "Under the course's name while the group votes the next course");

String labelPuttWatchingPlayer(String name) => Intl.message("Watching $name",
    name: "labelPuttWatchingPlayer",
    args: [name],
    desc: "Hint line at the bottom of the game once the player's own egg is "
        "in the nest: the camera follows another player still out on the "
        "hole; the placeholder is that player's name");

String labelPuttAimHint() =>
    Intl.message("Drag anywhere to aim · let go to putt",
        name: "labelPuttAimHint",
        desc: "Hint line at the bottom of the game until the player's first "
            "putt: dragging anywhere pulls the slingshot, releasing it "
            "strikes the egg");

String labelPuttReleaseHint() =>
    Intl.message("Let go to putt · pull further for more power",
        name: "labelPuttReleaseHint",
        desc: "Hint line at the bottom of the game while the player pulls "
            "the slingshot for their first putt: releasing strikes the egg, "
            "a longer pull hits it harder");

String labelPuttKeysHint() => Intl.message(
    "Arrow keys aim and set the power · Space putts · Tab power-ups",
    name: "labelPuttKeysHint",
    desc: "Second line of the first aim hint, on desktop and in the "
        "browser: the arrow keys turn the aim (left and right) and set "
        "the power (up and down), Space putts, Tab moves through the "
        "power-up slots. Words, not arrow symbols: the game's fonts "
        "have none");

String labelPuttKeyReleaseHint() => Intl.message("Space or Enter to putt",
    name: "labelPuttKeyReleaseHint",
    desc: "Hint line while the player aims their first putt with the "
        "keyboard: Space or Enter strikes the egg");

String labelPuttKeyReleaseDetail() =>
    Intl.message("Shift with the arrows turns finer · Esc cancels",
        name: "labelPuttKeyReleaseDetail",
        desc: "Second line of the hint while the player aims with the "
            "keyboard: holding Shift with the left and right arrow keys "
            "turns the aim in small steps, Esc drops the aim without "
            "putting");

String labelPuttScorecard() => Intl.message("Scorecard",
    name: "labelPuttScorecard",
    desc: "Title of the score panel in the bottom left corner of the game");

String labelPuttScorecardMore(int count) => Intl.plural(count,
    one: "+$count more player",
    other: "+$count more players",
    name: "labelPuttScorecardMore",
    args: [count],
    desc: "The score panel's last line on a short screen, when not every "
        "player fits: how many more are in the match");

String labelPuttScorecardHole() => Intl.message("Hole",
    name: "labelPuttScorecardHole",
    desc: "Column header in the score panel: the strokes each player has "
        "taken on this hole");

String labelPuttScorecardTotal() => Intl.message("Total",
    name: "labelPuttScorecardTotal",
    desc: "Column header in the score panel and the score cards: each "
        "player's strokes over (+) or under (-) the pars played");

String labelPuttResultsTitle(int hole, int par) =>
    Intl.message("Hole $hole · Par $par",
        name: "labelPuttResultsTitle",
        args: [hole, par],
        desc: "Title of the results card between holes; the placeholders are "
            "the hole's number in its course and its par");

String labelPuttContinue() => Intl.message("Continue",
    name: "labelPuttContinue",
    desc: "Button that moves the match on after "
        "a hole's results");

String labelPuttContinueIn(int seconds) => Intl.message("Continue · $seconds",
    name: "labelPuttContinueIn",
    args: [seconds],
    desc: "Button that moves the match on after a hole's results, with "
        "the seconds left before the match moves on by itself");

String labelPuttWinner(String name) => Intl.message("$name wins!",
    name: "labelPuttWinner",
    args: [name],
    desc: "The match-over card's title; the placeholder is the winner's "
        "name");

String labelPuttTie() => Intl.message("It's a tie!",
    name: "labelPuttTie",
    desc: "The match-over card's title when two or more players share the "
        "lowest total");

String labelPuttEvenShort() => Intl.message("E",
    name: "labelPuttEvenShort",
    desc: "A total level with the pars played, in the narrow score columns: "
        "golf's E for even (neither over nor under par)");

/// The signed difference against par: +3 over, −1 under, E level.
String relativeText(int relative) {
  if (relative == 0) return labelPuttEvenShort();
  // Not translated: the arithmetic signs (a true minus) before the number.
  final signed = relative > 0 ? '+$relative' : '−${-relative}';
  return labelPuttRelative(signed);
}

String labelPuttRelative(String signed) => Intl.message("$signed",
    name: "labelPuttRelative",
    args: [signed],
    desc: "A match total's strokes over (+) or under (-) the pars played; "
        "nothing but the signed number, e.g. +3 or -1, sign included");

String labelPuttTotal(int total) => Intl.plural(total,
    one: "$total stroke",
    other: "$total strokes",
    name: "labelPuttTotal",
    args: [total],
    desc: "A player's stroke total across the match, on the match-over "
        "card; the placeholder is the count");

String labelPuttHoleStrokes(int strokes) => Intl.plural(strokes,
    one: "$strokes stroke",
    other: "$strokes strokes",
    name: "labelPuttHoleStrokes",
    args: [strokes],
    desc: "The strokes a player took on the hole just finished, on the "
        "results card between holes");

String labelPuttWatching() => Intl.message("Watching",
    name: "labelPuttWatching",
    desc: "In place of a spectator's scores: they are not playing");

String labelPuttYouName(String name) => Intl.message("$name (you)",
    name: "labelPuttYouName",
    args: [name],
    desc: "The scorecard marks the local player; the placeholder is their "
        "name");

String labelPuttEmptySlot() => Intl.message("Empty slot",
    name: "labelPuttEmptySlot",
    desc: "Tooltip of an empty power-up inventory slot");

String labelPuttLeaveGreen() => Intl.message("Leave the green",
    name: "labelPuttLeaveGreen",
    desc: "Button that ends the match for this player and leaves the game");

String labelPuttBadgeHoleInOne() => Intl.message("Hole in one",
    name: "labelPuttBadgeHoleInOne",
    desc: "Badge on the results card: the hole took one stroke");

String labelPuttBadgeAlbatross() => Intl.message("Albatross",
    name: "labelPuttBadgeAlbatross",
    desc: "Badge on the results card: three strokes under par");

String labelPuttBadgeEagle() => Intl.message("Eagle",
    name: "labelPuttBadgeEagle",
    desc: "Badge on the results card: two strokes under par");

String labelPuttBadgeBirdie() => Intl.message("Birdie",
    name: "labelPuttBadgeBirdie",
    desc: "Badge on the results card: one stroke under par");

String labelPuttBadgePar() => Intl.message("Par",
    name: "labelPuttBadgePar",
    desc: "Badge on the results card: exactly the hole's par");

String labelPuttBadgeBogey() => Intl.message("Bogey",
    name: "labelPuttBadgeBogey",
    desc: "Badge on the results card: one stroke over par");

String labelPuttBadgeDoubleBogey() => Intl.message("Double bogey",
    name: "labelPuttBadgeDoubleBogey",
    desc: "Badge on the results card: two strokes over par");

String labelPuttBadgeTripleBogey() => Intl.message("Triple bogey",
    name: "labelPuttBadgeTripleBogey",
    desc: "Badge on the results card: three strokes over par");

String labelPuttBadgeMore() => Intl.message("In the nest",
    name: "labelPuttBadgeMore",
    desc: "Badge on the results card: four or more strokes over par, holed "
        "but with no golf term left to call it");

String labelPuttBadgeOutOfTime() => Intl.message("Out of time",
    name: "labelPuttBadgeOutOfTime",
    desc: "Badge on the results card for an egg the clock stopped before it "
        "reached the nest (it scores par plus two, or its strokes if more)");
