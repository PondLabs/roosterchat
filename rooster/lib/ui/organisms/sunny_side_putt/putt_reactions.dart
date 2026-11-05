// Quick reactions in Sunny Side Putt: a player taps one (or presses 1-5)
// and everyone sees a bubble pop over that player's egg - a cheer, a laugh,
// a wow, fire, a "nice one". They ride the engine's input journal like any
// move (see `ReactInput`), change nothing in the game, and fade in a
// couple of seconds. The game hands the layer the bubbles' pixels after
// every rendered frame, like the name tags.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'putt_art.dart';

/// How a reaction looks: its glyph and its colour on the bubble.
(IconData, Color) puttReactionLook(String reaction) => switch (reaction) {
      'cheer' => (Icons.celebration_rounded, PuttPalette.yolk),
      'laugh' => (Icons.sentiment_very_satisfied_rounded, PuttPalette.yolk),
      'wow' => (Icons.auto_awesome_rounded, const Color(0xFF2F9BE8)),
      'fire' => (Icons.local_fire_department_rounded, PuttPalette.comb),
      'gg' => (Icons.thumb_up_alt_rounded, const Color(0xFF3A9A4A)),
      _ => (Icons.favorite_rounded, PuttPalette.comb),
    };

/// What a reaction says (its button's tooltip).
String puttReactionLabel(String reaction) => switch (reaction) {
      'cheer' => labelPuttReactCheer(),
      'laugh' => labelPuttReactLaugh(),
      'wow' => labelPuttReactWow(),
      'fire' => labelPuttReactFire(),
      'gg' => labelPuttReactNice(),
      _ => labelPuttReact(),
    };

/// One bubble this frame: which reaction, at which surface pixel (the spot
/// over the egg), and how far through its life (0..1).
@immutable
class PuttBubble {
  final String key;
  final String reaction;
  final Offset at;
  final double progress;

  const PuttBubble({
    required this.key,
    required this.reaction,
    required this.at,
    required this.progress,
  });
}

/// The bubbles' places, refreshed once per rendered frame.
class PuttBubbleBoard extends ChangeNotifier {
  List<PuttBubble> _bubbles = const [];

  List<PuttBubble> get bubbles => _bubbles;

  void update(List<PuttBubble> bubbles) {
    if (bubbles.isEmpty && _bubbles.isEmpty) return;
    _bubbles = bubbles;
    notifyListeners();
  }
}

/// The bubble layer: each one pops in over its egg, rises a little and
/// fades.
class PuttBubbles extends StatelessWidget {
  final PuttBubbleBoard board;

  const PuttBubbles({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: board,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final bubble in board.bubbles) _placed(bubble, still: still),
          ],
        ),
      ),
    );
  }

  Widget _placed(PuttBubble bubble, {required bool still}) {
    final t = bubble.progress.clamp(0.0, 1.0);
    // In with a pop, a slow rise, out in the last fifth.
    final pop = still ? 1.0 : Curves.elasticOut.transform(math.min(1, t * 5));
    final opacity = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    final rise = still ? 0.0 : t * 26;
    return Positioned(
      key: ValueKey(bubble.key),
      left: bubble.at.dx,
      top: bubble.at.dy - rise,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1),
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.4 + 0.6 * pop,
            alignment: Alignment.bottomCenter,
            child: _Bubble(reaction: bubble.reaction),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String reaction;

  const _Bubble({required this.reaction});

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = puttReactionLook(reaction);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: PuttPalette.cream,
            shape: BoxShape.circle,
            border: Border.all(color: PuttPalette.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x55211614),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 28, color: colour),
        ),
        CustomPaint(size: const Size(12, 7), painter: _TailPainter()),
      ],
    );
  }
}

/// The bubble's tail, pointing down at the egg.
class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = PuttPalette.ink)
      ..drawPath(
          Path()
            ..moveTo(2.5, 0)
            ..lineTo(size.width - 2.5, 0)
            ..lineTo(size.width / 2, size.height - 3)
            ..close(),
          Paint()..color = PuttPalette.cream);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => false;
}

/// The reaction picker: a round button that opens a row of the five
/// reactions; a pick sends it and folds the row. A short cooldown keeps
/// a happy thumb from flooding the green.
class PuttReactionPicker extends StatefulWidget {
  final ValueChanged<String> onReact;

  const PuttReactionPicker({super.key, required this.onReact});

  @override
  State<PuttReactionPicker> createState() => _PuttReactionPickerState();
}

class _PuttReactionPickerState extends State<PuttReactionPicker> {
  bool _open = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static const _cooldown = Duration(milliseconds: 700);
  static const _reactions = ['cheer', 'laugh', 'wow', 'fire', 'gg'];

  void _send(String reaction) {
    final now = DateTime.now();
    if (now.difference(_last) < _cooldown) return;
    _last = now;
    widget.onReact(reaction);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: MediaQuery.maybeDisableAnimationsOf(context) == true
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _open
              ? Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  height: 40,
                  decoration: BoxDecoration(
                    color: PuttPalette.ink.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final reaction in _reactions)
                        _ReactionButton(
                          reaction: reaction,
                          onTap: () => _send(reaction),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Tooltip(
          message: labelPuttReact(),
          child: Material(
            color: PuttPalette.ink.withValues(alpha: 0.86),
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('putt-react'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  _open ? Icons.close_rounded : Icons.add_reaction_rounded,
                  color: PuttPalette.cream,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String reaction;
  final VoidCallback onTap;

  const _ReactionButton({required this.reaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = puttReactionLook(reaction);
    return Tooltip(
      message: puttReactionLabel(reaction),
      child: InkWell(
        key: Key('putt-react-$reaction'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: colour, size: 24),
        ),
      ),
    );
  }
}

// ---- strings ---------------------------------------------------------------------

String labelPuttReact() => Intl.message("React",
    name: "labelPuttReact",
    desc: "Tooltip of the button that opens the quick reactions a player "
        "can send in Sunny Side Putt (a bubble over their egg)");

String labelPuttReactCheer() => Intl.message("Cheer",
    name: "labelPuttReactCheer",
    desc: "A quick reaction in Sunny Side Putt: a party popper bubble over "
        "the player's egg");

String labelPuttReactLaugh() => Intl.message("Ha!",
    name: "labelPuttReactLaugh",
    desc: "A quick reaction in Sunny Side Putt: a laughing face over the "
        "player's egg (after a funny shot)");

String labelPuttReactWow() => Intl.message("Wow",
    name: "labelPuttReactWow",
    desc: "A quick reaction in Sunny Side Putt: sparkles over the player's "
        "egg (for an impressive shot)");

String labelPuttReactFire() => Intl.message("On fire",
    name: "labelPuttReactFire",
    desc: "A quick reaction in Sunny Side Putt: a flame over the player's "
        "egg (someone is playing very well)");

String labelPuttReactNice() => Intl.message("Nice one",
    name: "labelPuttReactNice",
    desc: "A quick reaction in Sunny Side Putt: a thumbs up over the "
        "player's egg (praising another player's shot)");
