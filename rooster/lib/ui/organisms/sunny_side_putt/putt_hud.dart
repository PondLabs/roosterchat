// The HUD of Sunny Side Putt: the mode-and-hole banner, the hole timer
// ring (pulsing through the last fifteen seconds), the scorecard strip,
// the power-up inventory with its three slots, and the between-hole
// results card. Pure Flutter (the game renders under it), fed by the
// [PuttMatch] and, where a human must be able to tap back, callbacks.
//
// Everything readable goes through `Intl.message` inline (the arb sync is
// a separate step); colors come from the brand palette in `putt_art.dart`.
// Non-interactive regions ignore pointers, so aim drags pass through to
// the game under the HUD.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';

import 'putt_art.dart';
import 'putt_match.dart';

/// The assembled HUD: a thin strip layout over the game.
class PuttHud extends StatelessWidget {
  final PuttMatch match;

  /// The audio tap (menu buttons click).
  final void Function(PuttSfx sfx)? onSfx;

  final VoidCallback onOpenMenu;

  /// The match-over card's leave button; default pops through the match.
  final VoidCallback? onLeave;

  const PuttHud({
    super.key,
    required this.match,
    required this.onOpenMenu,
    this.onSfx,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: IgnorePointer(
        ignoring: false,
        child: Column(
          children: [
            _PuttTopBar(match: match, onOpenMenu: onOpenMenu),
            Expanded(
              child: Center(
                child: _PuttMiddle(
                  match: match,
                  onLeave: onLeave,
                ),
              ),
            ),
            _PuttBottomBar(match: match),
          ],
        ),
      ),
    );
  }
}

// ---- top bar: mode chip, hole facts, timer, menu button -------------------------------

class _PuttTopBar extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback onOpenMenu;

  const _PuttTopBar({required this.match, required this.onOpenMenu});

  @override
  Widget build(BuildContext context) {
    final hole = match.hole;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(child: PuttModeChip(match: match)),
          const Spacer(),
          if (hole != null) ...[
            const SizedBox(width: 8),
            IgnorePointer(
              child: PuttTimerRing(
                secondsRemaining: match.secondsRemaining,
                totalSeconds: match.timerSeconds.toDouble(),
              ),
            ),
          ],
          IconButton(
            tooltip: labelPuttOpenMenu(),
            icon: const Icon(Icons.pause, color: PuttPalette.shell),
            onPressed: onOpenMenu,
          ),
        ],
      ),
    );
  }
}

/// The mode chip: which game, which hole, which par. Long text in other
/// languages has room: the chip wraps to two lines before it gives up.
class PuttModeChip extends StatelessWidget {
  final PuttMatch match;

  const PuttModeChip({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final hole = match.hole;
    if (match.phase == PuttPhase.awaitingNextCourse) {
      return _chip(
        Text(
          labelPuttCourseDone(),
          style: const TextStyle(
              color: PuttPalette.cream, fontWeight: FontWeight.w600),
        ),
      );
    }
    final text = [
      modeName(match.config.mode),
      if (hole != null)
        (match.config.mode == GameMode.tournament
            ? labelPuttHoleOf(match.holeNumber, _holeCount())
            : labelPuttHole(match.holeNumber)),
    ].join(' · ');
    final par = hole == null ? null : labelPuttPar(hole.par);
    return _chip(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
                color: PuttPalette.cream, fontWeight: FontWeight.w600),
          ),
          if (par != null)
            Text(
              par,
              style: const TextStyle(color: PuttPalette.yolk, fontSize: 12),
            ),
        ],
      ),
    );
  }

  /// Tournament's course list is fixed, so the "of N" is known; casual
  /// grows by vote and shows only the hole number.
  int _holeCount() =>
      match.config.courses.fold(0, (sum, course) => sum + course.holes.length);

  Widget _chip(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: PuttPalette.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
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

// ---- the timer ring ---------------------------------------------------------------------

/// The hole timer: a ring that empties clockwise with the seconds in the
/// middle, calm until fifteen seconds remain - then it pulses in comb red,
/// the color the ears have already heard ticking.
class PuttTimerRing extends StatefulWidget {
  final double secondsRemaining;
  final double totalSeconds;

  const PuttTimerRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  @override
  State<PuttTimerRing> createState() => PuttTimerRingState();

  /// True while the ring should pulse: the hole's last fifteen seconds.
  bool get isPulsing => secondsRemaining > 0 && secondsRemaining <= 15;
}

class PuttTimerRingState extends State<PuttTimerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant PuttTimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.isPulsing && pulse.status != AnimationStatus.forward) {
      pulse.repeat(reverse: true);
    } else if (!widget.isPulsing && pulse.status != AnimationStatus.dismissed) {
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
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final scale = 1 + 0.12 * pulse.value;
        final seconds = widget.secondsRemaining.ceil();
        final urgent = widget.isPulsing;
        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (urgent) Container(key: const Key('putt-timer-pulse')),
              SizedBox(
                key: const Key('putt-timer-ring'),
                width: 52,
                height: 52,
                child: CustomPaint(
                  painter: _TimerRingPainter(
                    progress: (seconds / widget.totalSeconds).clamp(0.0, 1.0),
                    urgent: urgent,
                  ),
                  child: Center(
                    child: Text(
                      '$seconds',
                      style: TextStyle(
                        color: urgent ? PuttPalette.comb : PuttPalette.cream,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final bool urgent;

  _TimerRingPainter({required this.progress, required this.urgent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = PuttPalette.ink.withValues(alpha: 0.55);
    canvas.drawCircle(center, radius, track);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = urgent ? PuttPalette.comb : PuttPalette.yolk;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * progress, false, ring);
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.urgent != urgent;
}

// ---- the middle: headline banner, between-hole cards ----------------------------------

class _PuttMiddle extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback? onLeave;

  const _PuttMiddle({required this.match, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    if (match.phase == PuttPhase.matchOver) {
      return PuttMatchOverCard(match: match, onLeave: onLeave);
    }
    if (match.phase == PuttPhase.holeScoreboard) {
      return PuttHoleResultsCard(match: match);
    }
    final headline = match.headline;
    if (headline == null) return const SizedBox.shrink();
    return IgnorePointer(child: PuttHeadline(headline));
  }
}

/// The banner that pops when a hole starts, someone holes, time runs out.
class PuttHeadline extends StatefulWidget {
  final String text;

  const PuttHeadline(this.text, {super.key});

  @override
  State<PuttHeadline> createState() => _PuttHeadlineState();
}

class _PuttHeadlineState extends State<PuttHeadline> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: PuttPalette.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PuttPalette.yolk, width: 2),
      ),
      child: Text(
        widget.text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: PuttPalette.cream,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Between holes: the hole's results, per-par, ranked, with the Continue
/// the match's host input hangs on.
class PuttHoleResultsCard extends StatelessWidget {
  final PuttMatch match;

  const PuttHoleResultsCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final rows = match.scoreboard;
    return _card(
      title: match.headline ?? labelPuttScores(),
      children: [
        for (final row in rows)
          _scoreRow(
            name: displayNameOf(match, row.playerId),
            detail: labelPuttHoleStrokes(_lastHoleStrokes(row)),
            total: labelPuttTotal(row.total),
            mine: row.playerId == match.localPlayerId,
          ),
        const SizedBox(height: 8),
        // Only the host's own card continues; in a local match that is me.
        FilledButton(
          key: const Key('putt-continue'),
          style: FilledButton.styleFrom(
              backgroundColor: PuttPalette.comb,
              foregroundColor: PuttPalette.shell),
          onPressed: match.advance,
          child: Text(labelPuttContinue()),
        ),
      ],
    );
  }

  int _lastHoleStrokes(ScoreRow row) {
    final strokes = List<int?>.of(row.holeStrokes);
    while (strokes.isNotEmpty && strokes.last == null) {
      strokes.removeLast();
    }
    return strokes.isEmpty ? 0 : strokes.last!;
  }
}

/// Match over: the totals, ranked, and the way out.
class PuttMatchOverCard extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback? onLeave;

  const PuttMatchOverCard({super.key, required this.match, this.onLeave});

  @override
  Widget build(BuildContext context) {
    final rows = match.scoreboard;
    final winner = rows.isEmpty ? null : rows.first;
    return _card(
      title: winner == null
          ? labelPuttMatchOver()
          : labelPuttWinner(displayNameOf(match, winner.playerId)),
      children: [
        for (final row in rows)
          _scoreRow(
            name: displayNameOf(match, row.playerId),
            detail: row.relative == 0
                ? labelPuttRelativeEven()
                : relativeText(row.relative),
            total: labelPuttTotal(row.total),
            mine: row.playerId == match.localPlayerId,
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('putt-leave-green'),
          style: FilledButton.styleFrom(
              backgroundColor: PuttPalette.combDeep,
              foregroundColor: PuttPalette.shell),
          onPressed: onLeave ?? match.leave,
          child: Text(labelPuttLeaveGreen()),
        ),
      ],
    );
  }
}

// ---- the bottom bar: scorecard strip and inventory ------------------------------------

class _PuttBottomBar extends StatelessWidget {
  final PuttMatch match;

  const _PuttBottomBar({required this.match});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: IgnorePointer(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PuttScorecardStrip(match: match),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PuttInventory(
              slots: match.myInventory,
              onUse: (effectId) => match.usePowerUp(effectId),
              enabled: match.myShotReady || match.phase == PuttPhase.holePlay,
            ),
          ],
        ),
      ),
    );
  }
}

/// The scorecard: one chip per player - name, total strokes, and what the
/// running hole has cost them so far. Me first, then by total, then id.
class PuttScorecardStrip extends StatelessWidget {
  final PuttMatch match;

  const PuttScorecardStrip({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final rows = match.scoreboard;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          _PlayerChip(
            name: displayNameOf(match, row.playerId),
            total: row.total,
            thisHole: match.engine.strokesInHole(row.playerId),
            isMe: row.playerId == match.localPlayerId,
            isWatching: match.engine.isSpectator(row.playerId),
          ),
      ],
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String name;
  final int total;
  final int thisHole;
  final bool isMe;
  final bool isWatching;

  const _PlayerChip({
    required this.name,
    required this.total,
    required this.thisHole,
    required this.isMe,
    required this.isWatching,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? PuttPalette.yolk.withValues(alpha: 0.92)
            : PuttPalette.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe ? PuttPalette.ink : PuttPalette.spruce,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMe ? labelPuttYouName(name) : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isMe ? PuttPalette.ink : PuttPalette.cream,
            ),
          ),
          Text(
            isWatching
                ? labelPuttWatching()
                : labelPuttChipCounts(total, thisHole),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isMe
                  ? PuttPalette.ink.withValues(alpha: 0.8)
                  : PuttPalette.stone,
            ),
          ),
        ],
      ),
    );
  }
}

/// The power-up inventory: three fixed slots, filled left to right, each
/// tap spends the effect (its target-shaped UIs come with the effects
/// ticket). Empty slots show the carton's dotted outline.
class PuttInventory extends StatelessWidget {
  final List<String> slots;
  final void Function(String effectId)? onUse;
  final bool enabled;

  const PuttInventory({
    super.key,
    required this.slots,
    this.onUse,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('putt-inventory'),
      children: [
        for (var i = 0; i < PowerUpInventory.cap; i++)
          _slot(i, i < slots.length ? slots[i] : null),
      ],
    );
  }

  Widget _slot(int index, String? effectId) {
    final filled = effectId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: filled ? puttPowerUpName(effectId) : labelPuttEmptySlot(),
        child: InkWell(
          key: Key('putt-slot-$index'),
          onTap: filled && enabled ? () => onUse?.call(effectId) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 44,
            height: 52,
            decoration: BoxDecoration(
              color: filled
                  ? PuttPalette.comb.withValues(alpha: 0.9)
                  : PuttPalette.ink.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: filled ? PuttPalette.yolk : PuttPalette.stone,
                width: filled ? 2 : 1,
              ),
            ),
            child: Center(
              child: filled
                  ? Text(
                      _monogram(effectId),
                      style: const TextStyle(
                        color: PuttPalette.shell,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    )
                  : Icon(
                      Icons.help_outline,
                      size: 18,
                      color: PuttPalette.stone.withValues(alpha: 0.7),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// One or two letters standing in for the effect, before the effects
  /// ticket lands its icons.
  String _monogram(String effectId) {
    final name = puttPowerUpName(effectId);
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return name.substring(0, 1).toUpperCase();
    return words
        .take(2)
        .map((word) => word.substring(0, 1).toUpperCase())
        .join();
  }
}

// ---- shared card furniture ---------------------------------------------------------------

Widget _card({required String title, required List<Widget> children}) {
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(16),
    constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
    decoration: BoxDecoration(
      color: PuttPalette.cream,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: PuttPalette.ink, width: 3),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PuttPalette.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

Widget _scoreRow({
  required String name,
  required String detail,
  required String total,
  required bool mine,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: mine ? PuttPalette.yolk.withValues(alpha: 0.25) : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(color: PuttPalette.ink, fontSize: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(detail),
          const SizedBox(width: 12),
          Text(total, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}

// ---- power-up names ------------------------------------------------------------------------

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

String labelPuttPowerHawkEye() => Intl.message("Hawk Eye",
    name: "labelPuttPowerHawkEye",
    desc: "Power-up: the next shot is perfectly straight, no wobble");

String labelPuttPowerNestMagnet() => Intl.message("Nest Magnet",
    name: "labelPuttPowerNestMagnet",
    desc: "Power-up: the egg turns magnetic when it passes near the nest");

String labelPuttPowerGhostEgg() => Intl.message("Ghost Egg",
    name: "labelPuttPowerGhostEgg",
    desc: "Power-up: the egg passes through fences and obstacles for a "
        "few seconds");

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

// ---- strings ---------------------------------------------------------------------------------

String labelPuttOpenMenu() => Intl.message("Pause",
    name: "labelPuttOpenMenu", desc: "Tooltip of the HUD's pause button");

String labelPuttHoleOf(int hole, int count) =>
    Intl.message("Hole $hole of $count",
        name: "labelPuttHoleOf",
        args: [hole, count],
        desc: "Which hole of the course is on the green, e.g. Hole 2 of 6");

String labelPuttHole(int hole) => Intl.message("Hole $hole",
    name: "labelPuttHole",
    args: [hole],
    desc: "Which hole is on the green, without a course total to lean on "
        "(casual, where the group votes more courses in)");

String labelPuttCourseDone() => Intl.message("Course done",
    name: "labelPuttCourseDone",
    desc: "Shown instead of a hole number while the group votes the next "
        "course");

String labelPuttPar(int par) => Intl.message("Par $par",
    name: "labelPuttPar",
    args: [par],
    desc: "The hole's par - the strokes it should take");

String labelPuttScores() => Intl.message("Scores",
    name: "labelPuttScores",
    desc: "Title of the score list shown between holes");

String labelPuttContinue() => Intl.message("Continue",
    name: "labelPuttContinue",
    desc: "Button that moves the match on after "
        "a hole's results");

String labelPuttWinner(String name) => Intl.message("$name wins!",
    name: "labelPuttWinner",
    args: [name],
    desc: "The match-over card's title; the placeholder is the winner's "
        "name");

String labelPuttRelativeEven() => Intl.message("Even",
    name: "labelPuttRelativeEven",
    desc: "A match total level with the pars played - neither over nor "
        "under");

/// The signed difference next to a total: +3 over, -1 under.
String relativeText(int relative) {
  // Not translated: the arithmetic sign that prefixes the number.
  final sign = relative > 0 ? '+' : '';
  return labelPuttRelative('$sign$relative');
}

String labelPuttRelative(String signed) => Intl.message("$signed",
    name: "labelPuttRelative",
    args: [signed],
    desc: "A match total's strokes over (+) or under (-) the pars played; "
        "nothing but the signed number, e.g. +3 or -1, sign included");

String labelPuttTotal(int total) => Intl.message("$total strokes",
    name: "labelPuttTotal",
    args: [total],
    desc: "A player's stroke total across the match; the placeholder is "
        "the count");

String labelPuttHoleStrokes(int strokes) => Intl.plural(strokes,
    one: "$strokes stroke here",
    other: "$strokes strokes here",
    name: "labelPuttHoleStrokes",
    args: [strokes],
    desc: "Strokes a player has taken in the running hole, or took in the "
        "one just finished");

String labelPuttWatching() => Intl.message("Watching",
    name: "labelPuttWatching",
    desc: "Under a spectator's name in the scorecard: they are not "
        "playing");

String labelPuttYouName(String name) => Intl.message("$name (you)",
    name: "labelPuttYouName",
    args: [name],
    desc: "The scorecard chip marks the local player; the placeholder is "
        "their name");

String labelPuttChipCounts(int total, int thisHole) =>
    Intl.message("$total total · $thisHole here",
        name: "labelPuttChipCounts",
        args: [total, thisHole],
        desc: "The scorecard chip's counts: total strokes, then strokes in "
            "the current hole");

String labelPuttEmptySlot() => Intl.message("Empty slot",
    name: "labelPuttEmptySlot",
    desc: "Tooltip of an empty power-up inventory slot");

String labelPuttLeaveGreen() => Intl.message("Leave the green",
    name: "labelPuttLeaveGreen",
    desc: "Button that ends the match for this player and leaves the game");
