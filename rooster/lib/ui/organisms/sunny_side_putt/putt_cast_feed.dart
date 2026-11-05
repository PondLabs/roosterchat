// The cast feed of Sunny Side Putt: every power-up anyone casts, told to
// everyone in a compact toast under the top bar - the caster's picture
// (or colour), the power-up's icon and a short line ("Lou: Corn Rain",
// "Maya stole your Gust!", "Jonas's shell blocked it"). The match keeps
// the calls ([PuttMatch.castCalls]); the feed queues the ones it has not
// shown, so a run of casts reads one after another, and hurries a toast
// along when others wait behind it. Clear of the green's middle, and it
// eats no pointer.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';

import 'putt_art.dart';
import 'putt_hud.dart' show puttPowerUpName;
import 'putt_match.dart';
import 'putt_powerup_icons.dart';

/// The line a call reads, in the viewer's words: who cast what, who stole
/// what from whom, whose shell held.
String puttCastLine(PuttMatch match, PuttCastCall call) {
  final me = match.localPlayerId;
  String name(String? id) => id == null ? '' : displayNameOf(match, id);
  switch (call.kind) {
    case PuttCastCallKind.cast:
      final power = puttPowerUpName(call.effectId);
      return call.casterId == me
          ? labelPuttCastByMe(power)
          : labelPuttCastBy(name(call.casterId), power);
    case PuttCastCallKind.steal:
      final power = puttPowerUpName(call.stolenId ?? call.effectId);
      if (call.otherId == me) {
        return labelPuttStoleFromMe(name(call.casterId), power);
      }
      if (call.casterId == me) {
        return labelPuttIStole(name(call.otherId), power);
      }
      return labelPuttStole(name(call.casterId), name(call.otherId), power);
    case PuttCastCallKind.swap:
      return labelPuttSwappedWithMe(name(call.casterId));
    case PuttCastCallKind.blocked:
      final power = puttPowerUpName(call.effectId);
      if (call.otherId == me) {
        return labelPuttMyShellBlocked(name(call.casterId), power);
      }
      if (call.casterId == me) {
        return labelPuttShellBlockedMine(name(call.otherId), power);
      }
      return labelPuttShellBlocked(
          name(call.otherId), name(call.casterId), power);
    case PuttCastCallKind.knock:
      return call.casterId == me
          ? labelPuttIKnocked(name(call.otherId))
          : labelPuttKnockedMe(name(call.casterId));
  }
}

/// How a call sits with the viewer: on the wrong end of it (robbed,
/// swapped), on the good end (my cast, my shell, my theft), or watching.
enum PuttCastTone { againstMe, mine, theirs }

PuttCastTone puttCastTone(PuttMatch match, PuttCastCall call) {
  final me = match.localPlayerId;
  switch (call.kind) {
    case PuttCastCallKind.steal:
    case PuttCastCallKind.swap:
      if (call.otherId == me) return PuttCastTone.againstMe;
      return call.casterId == me ? PuttCastTone.mine : PuttCastTone.theirs;
    case PuttCastCallKind.blocked:
      return call.otherId == me ? PuttCastTone.mine : PuttCastTone.theirs;
    case PuttCastCallKind.knock:
      return call.otherId == me ? PuttCastTone.againstMe : PuttCastTone.mine;
    case PuttCastCallKind.cast:
      return call.casterId == me ? PuttCastTone.mine : PuttCastTone.theirs;
  }
}

/// The feed: one toast at a time, the next one coming up as the last one
/// goes. Placed under the top bar by the game view.
class PuttCastFeed extends StatefulWidget {
  final PuttMatch match;

  const PuttCastFeed({super.key, required this.match});

  /// How long a toast stays with nobody waiting, and the least it stays
  /// when one waits or more do, in seconds.
  static const double life = 2.6;
  static const double hurriedLife = 1.3;
  static const double rushedLife = 0.95;

  /// The fade in and the fade out.
  static const double fadeIn = 0.18;
  static const double fadeOut = 0.24;

  /// Calls waiting past this many drop the oldest, stale news (one about
  /// someone else before one about the viewer).
  static const int maxWaiting = 4;

  @override
  State<PuttCastFeed> createState() => _PuttCastFeedState();
}

class _PuttCastFeedState extends State<PuttCastFeed>
    with SingleTickerProviderStateMixin {
  /// Runs only while a toast is up (made with the first one).
  Ticker? _ticker;
  final List<PuttCastCall> _waiting = [];
  PuttCastCall? _current;

  /// The current toast's age and the age it goes at, seconds.
  double _age = 0;
  double _life = PuttCastFeed.life;
  Duration _startedAt = Duration.zero;
  Duration _now = Duration.zero;

  /// The newest serial taken in, and the hole the calls belong to.
  int _seen = 0;
  int _hole = 0;

  @override
  void initState() {
    super.initState();
    final calls = widget.match.castCalls;
    // What was called before the feed came up is old news.
    _seen = calls.isEmpty ? 0 : calls.last.serial;
    _hole = widget.match.holeNumber;
    widget.match.addListener(_takeIn);
  }

  @override
  void didUpdateWidget(covariant PuttCastFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.match, widget.match)) {
      oldWidget.match.removeListener(_takeIn);
      widget.match.addListener(_takeIn);
      final calls = widget.match.castCalls;
      _seen = calls.isEmpty ? 0 : calls.last.serial;
      _waiting.clear();
    }
  }

  @override
  void dispose() {
    widget.match.removeListener(_takeIn);
    _ticker?.dispose();
    super.dispose();
  }

  /// Takes in the calls past [_seen]; a new hole drops what still waits.
  void _takeIn() {
    final match = widget.match;
    if (match.holeNumber != _hole || match.phase != PuttPhase.holePlay) {
      _hole = match.holeNumber;
      _waiting.clear();
    }
    var fresh = false;
    for (final call in match.castCalls) {
      if (call.serial <= _seen) continue;
      _seen = call.serial;
      // The match rewrites a call while its cast's events drain (a crow's
      // cast becomes its theft): the newest word for each serial wins.
      _waiting.removeWhere((waiting) => waiting.serial == call.serial);
      _waiting.add(call);
      fresh = true;
    }
    if (!fresh) return;
    while (_waiting.length > PuttCastFeed.maxWaiting) {
      final theirs = _waiting.indexWhere(
          (call) => puttCastTone(match, call) == PuttCastTone.theirs);
      _waiting.removeAt(theirs < 0 ? 0 : theirs);
    }
    if (_current == null) {
      _next();
    } else {
      _hurry();
    }
    if (mounted) setState(() {});
  }

  void _next() {
    final ticker = _ticker ??= createTicker(_onTick);
    if (_waiting.isEmpty) {
      _current = null;
      if (ticker.isActive) ticker.stop();
      return;
    }
    _current = _waiting.removeAt(0);
    _age = 0;
    _startedAt = _now;
    _life = PuttCastFeed.life;
    _hurry();
    if (!ticker.isActive) {
      _now = Duration.zero;
      _startedAt = Duration.zero;
      ticker.start();
    }
  }

  /// Others wait: the toast up now goes once it has been read, sooner
  /// the more wait.
  void _hurry() {
    if (_waiting.isEmpty) return;
    final least = _waiting.length > 1
        ? PuttCastFeed.rushedLife
        : PuttCastFeed.hurriedLife;
    _life = math.min(_life, math.max(least, _age + 0.3));
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    _age = (elapsed - _startedAt).inMicroseconds / 1e6;
    if (_age >= _life) _next();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final call = _current;
    if (call == null) return const SizedBox.shrink();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final appear = (_age / PuttCastFeed.fadeIn).clamp(0.0, 1.0);
    final leave =
        ((_age - (_life - PuttCastFeed.fadeOut)) / PuttCastFeed.fadeOut)
            .clamp(0.0, 1.0);
    final opacity = (appear * (1 - leave)).clamp(0.0, 1.0);
    final eased = Curves.easeOutBack.transform(appear);
    final slide = still ? 0.0 : -10 * (1 - eased) - 6 * leave;
    final scale = still ? 1.0 : 0.94 + 0.06 * eased;
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, slide),
          child: Transform.scale(
            scale: scale,
            child: PuttCastToast(
              key: ValueKey('putt-cast-${call.serial}'),
              match: widget.match,
              call: call,
            ),
          ),
        ),
      ),
    );
  }
}

/// One call's toast: the lead player's picture (or colour dot), the
/// power-up's icon, the line; its edge says how it sits with the viewer.
class PuttCastToast extends StatelessWidget {
  final PuttMatch match;
  final PuttCastCall call;

  const PuttCastToast({super.key, required this.match, required this.call});

  @override
  Widget build(BuildContext context) {
    final tint = puttTintOf(match, call.leadId);
    final edge = switch (puttCastTone(match, call)) {
      PuttCastTone.againstMe => PuttPalette.comb,
      PuttCastTone.mine => PuttPalette.yolk,
      PuttCastTone.theirs => tint.withValues(alpha: 0.85),
    };
    final avatar = match.avatarOf?.call(call.leadId);
    final line = puttCastLine(match, call);
    return Container(
      key: const Key('putt-cast-toast'),
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: PuttPalette.ink.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: edge, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x47000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Lead(tint: tint, avatar: avatar),
          const SizedBox(width: 8),
          if (call.kind == PuttCastCallKind.knock)
            // An egg against an egg: a burst, no power-up in it (the line
            // says what happened).
            const Icon(Icons.flare_rounded, size: 24, color: PuttPalette.yolk)
          else
            PuttPowerUpIcon(
              effectId: call.iconId,
              size: 24,
              semanticLabel: puttPowerUpName(call.iconId),
            ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'NunitoSans',
                fontSize: 14,
                height: 1.2,
                color: PuttPalette.cream,
                fontWeight: FontWeight.w800,
                fontVariations: [FontVariation.weight(800)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lead player: their call picture ringed in their colour, else a
/// dot of the colour.
class _Lead extends StatelessWidget {
  final Color tint;
  final ImageProvider? avatar;

  const _Lead({required this.tint, required this.avatar});

  @override
  Widget build(BuildContext context) {
    final avatar = this.avatar;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatar == null ? PuttPalette.ink : tint,
        border: Border.all(color: tint, width: 2),
        image: avatar == null
            ? null
            : DecorationImage(image: avatar, fit: BoxFit.cover),
      ),
      child: avatar == null
          ? Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: tint,
                shape: BoxShape.circle,
                border: Border.all(
                    color: PuttPalette.shell.withValues(alpha: 0.85)),
              ),
            )
          : null,
    );
  }
}

// ---- strings -------------------------------------------------------------------

String labelPuttCastBy(String name, String power) =>
    Intl.message("$name: $power",
        name: "labelPuttCastBy",
        args: [name, power],
        desc: "The toast under the top bar when another player casts a "
            "power-up; the placeholders are the player's name and the "
            "power-up's name, e.g. Lou: Corn Rain");

String labelPuttCastByMe(String power) => Intl.message("You: $power",
    name: "labelPuttCastByMe",
    args: [power],
    desc: "The toast under the top bar when the player casts a power-up "
        "themselves; the placeholder is the power-up's name, e.g. You: "
        "Corn Rain");

String labelPuttStoleFromMe(String name, String power) =>
    Intl.message("$name stole your $power!",
        name: "labelPuttStoleFromMe",
        args: [name, power],
        desc: "The toast when another player's Thieving Crow takes a "
            "power-up from the player; the placeholders are the thief's "
            "name and the stolen power-up's name");

String labelPuttIStole(String name, String power) =>
    Intl.message("You stole $name's $power!",
        name: "labelPuttIStole",
        args: [name, power],
        desc: "The toast when the player's own Thieving Crow takes a "
            "power-up from another player; the placeholders are that "
            "player's name and the stolen power-up's name");

String labelPuttStole(String thief, String victim, String power) =>
    Intl.message("$thief stole $victim's $power",
        name: "labelPuttStole",
        args: [thief, victim, power],
        desc: "The toast when one player's Thieving Crow takes a power-up "
            "from another (neither of them the player); the placeholders "
            "are the thief's name, the other player's name and the stolen "
            "power-up's name");

String labelPuttSwappedWithMe(String name) =>
    Intl.message("$name swapped places with you!",
        name: "labelPuttSwappedWithMe",
        args: [name],
        desc: "The toast when another player's Nest Swap trades their egg's "
            "spot with the player's; the placeholder is their name");

String labelPuttKnockedMe(String name) =>
    Intl.message("$name knocked your egg!",
        name: "labelPuttKnockedMe",
        args: [name],
        desc: "The toast when another player's egg rolls into the player's "
            "resting egg and moves it; the placeholder is that player's name, "
            "e.g. Jonas knocked your egg!");

String labelPuttIKnocked(String name) => Intl.message("You knocked $name's egg",
    name: "labelPuttIKnocked",
    args: [name],
    desc: "The toast when the player's egg rolls into another player's "
        "resting egg and moves it; the placeholder is that player's name, "
        "e.g. You knocked Lou's egg");

String labelPuttMyShellBlocked(String caster, String power) =>
    Intl.message("Your shell blocked $caster's $power!",
        name: "labelPuttMyShellBlocked",
        args: [caster, power],
        desc: "The toast when the player's Thick Shell stops another "
            "player's power-up; the placeholders are the caster's name and "
            "the power-up's name, e.g. Your shell blocked Maya's Corn Rain!");

String labelPuttShellBlockedMine(String name, String power) =>
    Intl.message("$name's shell blocked your $power",
        name: "labelPuttShellBlockedMine",
        args: [name, power],
        desc: "The toast when another player's Thick Shell stops the "
            "player's own power-up; the placeholders are that player's name "
            "and the power-up's name");

String labelPuttShellBlocked(String name, String caster, String power) =>
    Intl.message("$name's shell blocked $caster's $power",
        name: "labelPuttShellBlocked",
        args: [name, caster, power],
        desc: "The toast when one player's Thick Shell stops another's "
            "power-up (neither of them the player); the placeholders are "
            "the shielded player's name, the caster's name and the "
            "power-up's name");
