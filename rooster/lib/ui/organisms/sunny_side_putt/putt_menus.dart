// The menus of Sunny Side Putt: pause (with the leave double-check), the
// in-game settings sheet with the music and SFX volume sliders persisted
// to the local preferences, and the course-vote sheet casual shows after
// a course ends.
//
// The sliders write their levels to SharedPreferences through the same
// `DoublePreference` objects `putt_audio.dart` reads its buses from, so a
// level picked here survives the app and applies live on the audio side;
// with no audio service (tests, silent launches) the buses are silent
// doubles and nothing else happens.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';

import 'putt_art.dart';
import 'putt_audio.dart';
import 'putt_match.dart';

// ---- the pause menu --------------------------------------------------------------------

/// The pause card: resume, settings, leave, and the rooster host asking
/// (with his eyes) whether you really meant that last one.
class PuttPauseMenu extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback onOpenSettings;
  final VoidCallback onResume;
  final VoidCallback onLeave;

  const PuttPauseMenu({
    super.key,
    required this.match,
    required this.onOpenSettings,
    required this.onResume,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return _MenuSheet(
      title: labelPuttPaused(),
      children: [
        const SizedBox(height: 6),
        SizedBox(
          width: 120,
          height: 96,
          child: CustomPaint(
            painter: _RoosterPainter(phase: 0),
          ),
        ),
        const SizedBox(height: 6),
        _MenuButton(
          key: const Key('putt-menu-resume'),
          label: labelPuttResume(),
          onPressed: onResume,
          filled: true,
        ),
        _MenuButton(
          key: const Key('putt-menu-settings'),
          label: labelPuttSettings(),
          onPressed: onOpenSettings,
        ),
        _MenuButton(
          key: const Key('putt-menu-leave'),
          label: labelPuttLeave(),
          onPressed: onLeave,
          destructive: true,
        ),
      ],
    );
  }
}

/// The leave double-check: the round goes on without you once you leave.
class PuttLeaveConfirm extends StatelessWidget {
  final VoidCallback onStay;
  final VoidCallback onLeave;

  const PuttLeaveConfirm(
      {super.key, required this.onStay, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return _MenuSheet(
      title: labelPuttLeaveTitle(),
      children: [
        const SizedBox(height: 4),
        Text(
          promptPuttLeaveDetail(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: PuttPalette.ink, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _MenuButton(
          key: const Key('putt-leave-stay'),
          label: labelPuttStay(),
          onPressed: onStay,
          filled: true,
        ),
        _MenuButton(
          key: const Key('putt-leave-confirm'),
          label: labelPuttLeave(),
          onPressed: onLeave,
          destructive: true,
        ),
      ],
    );
  }
}

// ---- settings ----------------------------------------------------------------------------

/// The settings sheet: music volume and SFX volume, persisted. The sliders
/// update their bus live while dragging and save once, on release. The
/// view hands in the audio service's buses (silent doubles when the view
/// runs muted); tests hand in whatever they need to watch.
class PuttSettingsSheet extends StatefulWidget {
  final PuttBuses buses;
  final VoidCallback onClose;

  const PuttSettingsSheet({
    super.key,
    required this.buses,
    required this.onClose,
  });

  @override
  State<PuttSettingsSheet> createState() => _PuttSettingsSheetState();
}

class _PuttSettingsSheetState extends State<PuttSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final buses = widget.buses;
    return _MenuSheet(
      title: labelPuttGameSettings(),
      children: [
        _VolumeSlider(
          key: const Key('putt-music-volume'),
          label: labelPuttMusicVolume(),
          value: buses.musicVolume,
          onChanged: (v) => setState(() => buses.musicVolume = v),
          onCommit: (v) => puttMusicVolume.set(v),
        ),
        const SizedBox(height: 8),
        _VolumeSlider(
          key: const Key('putt-sfx-volume'),
          label: labelPuttSfxVolume(),
          value: buses.sfxVolume,
          onChanged: (v) => setState(() => buses.sfxVolume = v),
          onCommit: (v) => puttSfxVolume.set(v),
        ),
        const SizedBox(height: 12),
        _MenuButton(
          key: const Key('putt-settings-close'),
          label: labelPuttDone(),
          onPressed: widget.onClose,
          filled: true,
        ),
      ],
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  const _VolumeSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: PuttPalette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            onChangeEnd: onCommit,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.end,
            style: const TextStyle(
                color: PuttPalette.ink,
                fontSize: 12,
                fontFeatures: [ui.FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

// ---- the course vote -----------------------------------------------------------------------

/// Casual's vote sheet: the courses on file, one card each, pick one and
/// it starts. (Multi-player vote tallying rides the session; the local
/// host-like view picks straight away.)
class PuttVoteSheet extends StatelessWidget {
  final List<CourseDef> options;
  final void Function(String courseId) onPick;

  const PuttVoteSheet({super.key, required this.options, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return _MenuSheet(
      title: labelPuttChooseNextCourse(),
      children: [
        for (final course in options)
          _CourseCard(
            course: course,
            onPlay: () => onPick(course.id),
          ),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseDef course;
  final VoidCallback onPlay;

  const _CourseCard({required this.course, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final holes = course.holes.length;
    final par = course.holes.fold<int>(0, (sum, hole) => sum + hole.par);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PuttPalette.ink, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.id,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: PuttPalette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                Text(
                  labelPuttCourseCard(holes, par),
                  style:
                      const TextStyle(color: PuttPalette.stone, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: Key('putt-vote-${course.id}'),
            style: FilledButton.styleFrom(
                backgroundColor: PuttPalette.combDeep,
                foregroundColor: PuttPalette.shell,
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed: onPlay,
            child: Text(labelPuttPlayCourse()),
          ),
        ],
      ),
    );
  }
}

// ---- furniture ------------------------------------------------------------------------------

class _MenuSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MenuSheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    // The scrim eats the drags a paused game must not hear.
    return Container(
      color: PuttPalette.ink.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: PuttPalette.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PuttPalette.ink, width: 3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PuttPalette.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final bool destructive;

  const _MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? PuttPalette.combDeep : PuttPalette.ink;
    final child = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: filled
            ? (destructive ? PuttPalette.combDeep : PuttPalette.comb)
            : PuttPalette.shell,
        foregroundColor: filled ? PuttPalette.shell : foreground,
        side: BorderSide(color: PuttPalette.ink, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    );
  }
}

/// The rooster host, bobbing gently, drawn by the shared painters.
class _RoosterPainter extends CustomPainter {
  final double phase;

  _RoosterPainter({required this.phase});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final scale = size.shortestSide / 2.6;
    drawRoosterHead(
      canvas,
      ui.Offset(size.width * 0.62, size.height * 0.52),
      scale,
      bob: phase,
    );
  }

  @override
  bool shouldRepaint(_RoosterPainter old) => old.phase != phase;
}

// ---- strings ---------------------------------------------------------------------------------

String labelPuttPaused() => Intl.message("Paused",
    name: "labelPuttPaused", desc: "Title of the pause menu");

String labelPuttResume() => Intl.message("Back to the green",
    name: "labelPuttResume", desc: "Button that unpauses the game");

String labelPuttSettings() => Intl.message("Settings",
    name: "labelPuttSettings",
    desc: "Button that opens the game's settings (the volume sliders)");

String labelPuttLeave() => Intl.message("Leave game",
    name: "labelPuttLeave",
    desc: "Button that leaves the match; the round keeps going without "
        "the player");

String labelPuttLeaveTitle() => Intl.message("Leave the game?",
    name: "labelPuttLeaveTitle",
    desc: "Title of the confirmation before leaving");

String promptPuttLeaveDetail() => Intl.message(
    "The round keeps going without you. The hole scores you the strokes "
    "you took, at least par plus two.",
    name: "promptPuttLeaveDetail",
    desc: "What leaving does, in the confirmation: the unfinished hole "
        "scores max(strokes taken, par + 2)");

String labelPuttStay() => Intl.message("Stay",
    name: "labelPuttStay",
    desc: "Button that declines leaving and returns to the game");

String labelPuttGameSettings() => Intl.message("Game settings",
    name: "labelPuttGameSettings", desc: "Title of the settings sheet");

String labelPuttMusicVolume() => Intl.message("Music volume",
    name: "labelPuttMusicVolume",
    desc: "Slider: how loud the game's music plays");

String labelPuttSfxVolume() => Intl.message("SFX volume",
    name: "labelPuttSfxVolume",
    desc: "Slider: how loud the game's sound effects play");

String labelPuttDone() => Intl.message("Done",
    name: "labelPuttDone", desc: "Button that closes the settings sheet");

String labelPuttChooseNextCourse() => Intl.message("Choose the next course",
    name: "labelPuttChooseNextCourse",
    desc: "Title of the vote sheet after a casual course ends");

String labelPuttCourseCard(int holes, int par) =>
    Intl.message("$holes holes · par $par",
        name: "labelPuttCourseCard",
        args: [holes, par],
        desc: "A course card's facts in the vote sheet; the placeholders are "
            "the hole count and the pars added up");

String labelPuttPlayCourse() => Intl.message("Play",
    name: "labelPuttPlayCourse",
    desc: "Button on a course card that starts that course");
