// The spectator strip: the one-line "you're watching from the fence" bar
// under the timer while the course is full - who is playing, who else is
// watching, and the promise (the engine keeps) that a freed seat takes you
// at the next hole.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'putt_art.dart';
import 'putt_match.dart';

class SpectatorStrip extends StatelessWidget {
  final PuttMatch match;

  const SpectatorStrip({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final playing = [
      for (final player in match.engine.players)
        if (!player.spectator) displayNameOf(match, player.id),
    ];
    final watching = [
      for (final player in match.engine.players)
        if (player.spectator && player.id != match.localPlayerId)
          displayNameOf(match, player.id),
    ];
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: PuttPalette.ink.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PuttPalette.spruce, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labelPuttSpectatorTitle(),
              style: const TextStyle(
                  color: PuttPalette.cream,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              labelPuttSpectatorDetail(playing.length, watching.length),
              style: const TextStyle(color: PuttPalette.stone, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String labelPuttSpectatorTitle() =>
    Intl.message("You're watching from the fence",
        name: "labelPuttSpectatorTitle",
        desc: "The spectator strip's title, shown when the round is full; the "
            "next free seat starts the spectator at the next hole's tee");

String labelPuttSpectatorDetail(int playing, int watching) =>
    Intl.message("$playing on the green · $watching watching with you",
        name: "labelPuttSpectatorDetail",
        args: [playing, watching],
        desc: "The spectator strip's counts; the placeholders are how many "
            "players are in the hole and how many others are watching");
