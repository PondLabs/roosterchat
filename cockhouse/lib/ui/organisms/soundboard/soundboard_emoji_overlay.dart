// Emoji overlay for soundboard triggers.
//
// Placed over the sender's avatar (Stack). It stays for as long as the sound
// plays: [entry] is the registry's, which the call controller clears when
// the audio ends. Entrance: scale 0.4->1 with easeOutBack + fade in; exit:
// fade + scale down. A new sound from the same sender swaps it. Never
// replaces the avatar — pure overlay, IgnorePointer.
import 'package:cockhouse/ui/molecules/soundboard_emoji_picker.dart';
import 'package:cockhouse/ui/organisms/soundboard/soundboard_overlay_registry.dart';
import 'package:flutter/material.dart';

class SoundboardEmojiOverlay extends StatelessWidget {
  /// What to show, or null for nothing.
  final SoundboardOverlayEntry? entry;

  const SoundboardEmojiOverlay({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        reverseDuration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn),
          child: ScaleTransition(
            scale: Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
                reverseCurve: Curves.easeIn)),
            child: child,
          ),
        ),
        child: entry == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(entry.eventId),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SoundboardEmojiView(
                  entry.emoji,
                  image: entry.image,
                  size: 34,
                ),
              ),
      ),
    );
  }
}
