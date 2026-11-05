// The menus of Sunny Side Putt: pause (with the leave double-check), "Your
// egg" (the band pattern for my egg and the hat for my chick), the in-game
// settings sheet with the music and SFX volume sliders persisted to the
// local preferences, and the course-vote sheet casual shows after a course
// ends.
//
// The sliders write their levels to SharedPreferences through the same
// `DoublePreference` objects `putt_audio.dart` reads its buses from, so a
// level picked here survives the app and applies live on the audio side;
// with no audio service (tests, silent launches) the buses are silent
// doubles and nothing else happens. "Your egg" keeps its pick the same way
// (`putt_look.dart`), and puts it on in the match at once.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/utils/common_strings.dart';

import 'putt_art.dart';
import 'putt_audio.dart';
import 'putt_look.dart';
import 'putt_match.dart';

// ---- the pause menu --------------------------------------------------------------------

/// The pause card: resume, my egg's look, settings, leave, and the rooster
/// host asking (with his eyes) whether you really meant that last one.
class PuttPauseMenu extends StatelessWidget {
  final PuttMatch match;
  final VoidCallback onOpenSettings;
  final VoidCallback onResume;
  final VoidCallback onLeave;

  /// Opens "Your egg"; no button when left out.
  final VoidCallback? onOpenLook;

  const PuttPauseMenu({
    super.key,
    required this.match,
    required this.onOpenSettings,
    required this.onResume,
    required this.onLeave,
    this.onOpenLook,
  });

  @override
  Widget build(BuildContext context) {
    return _MenuSheet(
      title: labelPuttPaused(),
      children: [
        const SizedBox(height: 6),
        // The brand's own mark: the rooster in his headphones.
        Image.asset(
          'assets/images/app_icon/app_icon_transparent_cropped.png',
          key: const Key('putt-menu-mark'),
          width: 96,
          height: 96,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 6),
        _MenuButton(
          key: const Key('putt-menu-resume'),
          label: labelPuttResume(),
          onPressed: onResume,
          filled: true,
        ),
        if (onOpenLook != null)
          _MenuButton(
            key: const Key('putt-menu-look'),
            label: labelPuttYourEgg(),
            onPressed: onOpenLook!,
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

// ---- your egg ----------------------------------------------------------------------------

/// "Your egg": the band pattern for my egg and the hat my chick wears when
/// it hatches, the two drawn as the green shows them, in my colour (that
/// one comes with my seat). A pick is kept on this device for every match
/// after ([savePuttLook]) and put on in this one at once
/// ([PuttMatch.wear]): everyone sees it.
class PuttLookSheet extends StatefulWidget {
  final PuttMatch match;
  final VoidCallback onClose;

  /// Told of every pick (the view clicks).
  final VoidCallback? onPick;

  const PuttLookSheet({
    super.key,
    required this.match,
    required this.onClose,
    this.onPick,
  });

  @override
  State<PuttLookSheet> createState() => _PuttLookSheetState();
}

class _PuttLookSheetState extends State<PuttLookSheet> {
  late PuttLook _look = widget.match.look;

  void _pick(PuttLook look) {
    if (look == _look) return;
    setState(() => _look = look);
    unawaited(savePuttLook(look));
    widget.match.wear(look);
    widget.onPick?.call();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final tint = puttTintOf(match, match.localPlayerId);
    final look = _look;
    return _MenuSheet(
      title: labelPuttYourEgg(),
      scrollable: true,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: CustomPaint(
            key: const Key('putt-look-preview'),
            painter: _LookPreviewPainter(tint, look),
          ),
        ),
        const SizedBox(height: 10),
        _LookHeading(labelPuttLookPattern(puttPatternName(look.pattern))),
        _LookRow(children: [
          for (final pattern in EggPattern.values)
            _LookTile(
              key: Key('putt-look-pattern-${pattern.name}'),
              label: puttPatternName(pattern),
              selected: look.pattern == pattern,
              onTap: () => _pick(look.copyWith(pattern: pattern)),
              painter: _PatternTilePainter(tint, pattern),
            ),
        ]),
        const SizedBox(height: 10),
        _LookHeading(look.hat == HatchlingHat.none
            ? labelPuttHatNone()
            : labelPuttLookHat(puttHatName(look.hat))),
        _LookRow(children: [
          for (final hat in HatchlingHat.values)
            _LookTile(
              key: Key('putt-look-hat-${hat.name}'),
              label: puttHatName(hat),
              selected: look.hat == hat,
              onTap: () => _pick(look.copyWith(hat: hat)),
              painter: _HatTilePainter(tint, hat),
            ),
        ]),
        const SizedBox(height: 10),
        Text(
          labelPuttLookWhoSees(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: PuttPalette.stone, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        _MenuButton(
          key: const Key('putt-look-close'),
          label: CommonStrings.promptDone,
          onPressed: widget.onClose,
          filled: true,
        ),
      ],
    );
  }
}

class _LookHeading extends StatelessWidget {
  final String text;

  const _LookHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: PuttPalette.ink, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A row of choices that wraps on a narrow sheet.
class _LookRow extends StatelessWidget {
  final List<Widget> children;

  const _LookRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: children,
    );
  }
}

/// One choice: its drawing on a tile, ringed in yolk when picked, its name
/// in the tooltip and for screen readers.
class _LookTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final CustomPainter painter;

  const _LookTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.painter,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 54,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: selected
                    ? PuttPalette.yolk.withValues(alpha: 0.2)
                    : PuttPalette.shell,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? PuttPalette.yolk
                      : PuttPalette.ink.withValues(alpha: 0.25),
                  width: selected ? 2.5 : 1.2,
                ),
              ),
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big egg in my colour and pattern, and my chick in its shell with
/// its hat, side by side on a patch of shadow.
class _LookPreviewPainter extends CustomPainter {
  final Color tint;
  final PuttLook look;

  const _LookPreviewPainter(this.tint, this.look);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final h = size.height * 0.84;
    final eggWidth = h * 0.78;
    final gap = h * 0.28;
    final total = eggWidth + gap + h;
    final left = (size.width - total) / 2;
    final top = size.height - h - 6;
    final shadow = Paint()..color = PuttPalette.ink.withValues(alpha: 0.14);
    final egg = Rect.fromLTWH(left, top, eggWidth, h);
    final chick = Rect.fromLTWH(left + eggWidth + gap, top, h, h);
    for (final box in [egg, chick]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(box.center.dx, box.bottom),
              width: box.width * 0.9,
              height: 10),
          shadow);
    }
    paintPuttBigEgg(canvas, egg, tint, look.pattern);
    paintPuttChick(canvas, chick, tint, look.hat);
  }

  @override
  bool shouldRepaint(_LookPreviewPainter old) =>
      old.tint != tint || old.look != look;
}

/// A pattern's tile: the egg in my colour wearing it.
class _PatternTilePainter extends CustomPainter {
  final Color tint;
  final EggPattern pattern;

  const _PatternTilePainter(this.tint, this.pattern);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final h = size.height;
    final w = h * 0.78;
    paintPuttBigEgg(
        canvas, Rect.fromLTWH((size.width - w) / 2, 0, w, h), tint, pattern);
  }

  @override
  bool shouldRepaint(_PatternTilePainter old) =>
      old.tint != tint || old.pattern != pattern;
}

/// A hat's tile: my chick wearing it.
class _HatTilePainter extends CustomPainter {
  final Color tint;
  final HatchlingHat hat;

  const _HatTilePainter(this.tint, this.hat);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final side = math.min(size.width, size.height);
    paintPuttChick(
        canvas,
        Rect.fromLTWH((size.width - side) / 2, size.height - side, side, side),
        tint,
        hat);
  }

  @override
  bool shouldRepaint(_HatTilePainter old) => old.tint != tint || old.hat != hat;
}

/// A pattern's name, as "Your egg" says it.
String puttPatternName(EggPattern pattern) => switch (pattern) {
      EggPattern.zigzag => labelPuttPatternZigzag(),
      EggPattern.stripes => labelPuttPatternStripes(),
      EggPattern.dots => labelPuttPatternDots(),
      EggPattern.hearts => labelPuttPatternHearts(),
      EggPattern.stars => labelPuttPatternStars(),
      EggPattern.waves => labelPuttPatternWaves(),
    };

/// A hat's name, as "Your egg" says it.
String puttHatName(HatchlingHat hat) => switch (hat) {
      HatchlingHat.none => labelPuttHatNone(),
      HatchlingHat.strawHat => labelPuttHatStraw(),
      HatchlingHat.bow => labelPuttHatBow(),
      HatchlingHat.crown => labelPuttHatCrown(),
      HatchlingHat.headphones => labelPuttHatHeadphones(),
      HatchlingHat.daisy => labelPuttHatDaisy(),
    };

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
                  puttCourseName(course.id),
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
                textStyle: _menuLabel,
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

  /// Scrolls when the screen is shorter than the sheet (a tall one).
  final bool scrollable;

  const _MenuSheet(
      {required this.title, required this.children, this.scrollable = false});

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, textAlign: TextAlign.center, style: _menuTitle),
        ...children,
      ],
    );
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
        child: DefaultTextStyle.merge(
          style: _menuBody,
          child: scrollable ? SingleChildScrollView(child: column) : column,
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
        textStyle: _menuLabel,
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

/// The menus' type, the HUD's own: titles in its display face (Sora),
/// the rest in its label face (Nunito Sans) - the platform's plain sans
/// read like another app next to the HUD.
const TextStyle _menuTitle = TextStyle(
  fontFamily: 'Sora',
  color: PuttPalette.ink,
  fontSize: 20,
  fontWeight: FontWeight.w800,
  fontVariations: [ui.FontVariation.weight(800)],
);
const TextStyle _menuBody = TextStyle(fontFamily: 'NunitoSans');
const TextStyle _menuLabel = TextStyle(
  fontFamily: 'NunitoSans',
  fontSize: 14.5,
  fontWeight: FontWeight.w800,
  fontVariations: [ui.FontVariation.weight(800)],
);

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

String labelPuttYourEgg() => Intl.message("Your egg",
    name: "labelPuttYourEgg",
    desc: "Title of the sheet where a player picks the pattern on their egg "
        "and the hat on their chick, and the pause menu's button that opens "
        "it");

String labelPuttLookPattern(String pattern) => Intl.message("Pattern: $pattern",
    name: "labelPuttLookPattern",
    args: [pattern],
    desc: "Over the row of egg patterns in \"Your egg\"; the placeholder "
        "is the name of the pattern picked (Stripes, Dots...)");

String labelPuttLookHat(String hat) => Intl.message("Hat: $hat",
    name: "labelPuttLookHat",
    args: [hat],
    desc: "Over the row of hats in \"Your egg\", when one is picked; the "
        "placeholder is the hat's name (Crown, Bow...)");

String labelPuttLookWhoSees() => Intl.message(
    "Everyone sees your pattern on the green and your hat when your chick "
    "hatches.",
    name: "labelPuttLookWhoSees",
    desc: "Under the choices in \"Your egg\": who sees the pick, and where "
        "(the egg on the course, the chick that pops out of the shell in the "
        "nest)");

String labelPuttPatternZigzag() => Intl.message("Zigzag",
    name: "labelPuttPatternZigzag",
    desc: "An egg pattern: a zig-zag band round the egg, with dots");

String labelPuttPatternStripes() => Intl.message("Stripes",
    name: "labelPuttPatternStripes",
    desc: "An egg pattern: bold stripes round the egg");

String labelPuttPatternDots() => Intl.message("Dots",
    name: "labelPuttPatternDots",
    desc: "An egg pattern: polka dots all over the egg");

String labelPuttPatternHearts() => Intl.message("Hearts",
    name: "labelPuttPatternHearts",
    desc: "An egg pattern: a ring of hearts round the egg");

String labelPuttPatternStars() => Intl.message("Stars",
    name: "labelPuttPatternStars",
    desc: "An egg pattern: a ring of stars round the egg");

String labelPuttPatternWaves() => Intl.message("Waves",
    name: "labelPuttPatternWaves",
    desc: "An egg pattern: a wavy band round the egg");

String labelPuttHatNone() => Intl.message("No hat",
    name: "labelPuttHatNone",
    desc: "The choice of no hat for the chick that hatches from the egg");

String labelPuttHatStraw() => Intl.message("Straw hat",
    name: "labelPuttHatStraw",
    desc: "A hat for the chick: a farmer's straw hat");

String labelPuttHatBow() => Intl.message("Bow",
    name: "labelPuttHatBow",
    desc: "A hat for the chick: a ribbon bow on its head");

String labelPuttHatCrown() => Intl.message("Crown",
    name: "labelPuttHatCrown", desc: "A hat for the chick: a little crown");

String labelPuttHatHeadphones() => Intl.message("Headphones",
    name: "labelPuttHatHeadphones",
    desc: "A hat for the chick: headphones over its head, like the rooster "
        "host's");

String labelPuttHatDaisy() => Intl.message("Daisy",
    name: "labelPuttHatDaisy",
    desc: "A hat for the chick: a daisy (the flower) tucked on its head");

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
