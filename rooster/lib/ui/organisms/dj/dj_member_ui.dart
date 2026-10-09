// The booth as it shows on call members, wherever they are listed (the
// sidebar's voice list, the call tiles): a spinning record next to the DJ, a
// raised hand next to whoever asked for the decks, and the right-click
// actions to ask for, pass or leave the decks.
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const djHandEmoji = '✋';

class DjMemberBadges extends StatelessWidget {
  const DjMemberBadges(
      {required this.dj, required this.userId, this.size = 16, super.key});

  final DjSession? dj;
  final String userId;
  final double size;

  static String get tooltipDjBadge => Intl.message("DJ",
      name: "tooltipDjBadge",
      desc: "Tooltip on the record next to the name of whoever is the DJ in "
          "a call, while nothing plays");

  static String tooltipDjBadgePlaying(String title) =>
      Intl.message("DJ · playing $title",
          name: "tooltipDjBadgePlaying",
          args: [title],
          desc: "Tooltip on the record next to the DJ's name in a call; the "
              "placeholder is the song playing");

  static String tooltipDjBadgePaused(String title) => Intl.message(
      "DJ · paused $title",
      name: "tooltipDjBadgePaused",
      args: [title],
      desc: "Tooltip on the record next to the DJ's name in a call, with the "
          "music paused; the placeholder is the song");

  static String get tooltipDjAsked => Intl.message("Asked to be the DJ",
      name: "tooltipDjAsked",
      desc: "Tooltip on the raised hand next to the name of someone in a call "
          "who asked to become the DJ");

  @override
  Widget build(BuildContext context) {
    final dj = this.dj;
    if (dj == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: dj,
      builder: (context, _) {
        final isDj = dj.isDjUser(userId);
        final asked = !isDj && dj.hasRequestedUser(userId);
        if (!isDj && !asked) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (isDj)
              Tooltip(
                message: switch (dj.current) {
                  null => tooltipDjBadge,
                  final current => dj.isPlaying
                      ? tooltipDjBadgePlaying(current.title)
                      : tooltipDjBadgePaused(current.title),
                },
                child: VinylDisc(
                  size: size,
                  spinning: dj.isPlaying && !dj.isBuffering,
                ),
              ),
            if (asked)
              Tooltip(
                message: tooltipDjAsked,
                child: Text(djHandEmoji,
                    style: TextStyle(fontSize: size * 0.85, height: 1)),
              ),
          ],
        );
      },
    );
  }
}

/// The booth as a row of its own under the people in a voice channel in the
/// sidebar, like a music bot: the record, who DJs and what plays. Shows
/// only while someone DJs.
class DjSidebarRow extends StatelessWidget {
  const DjSidebarRow(
      {required this.dj,
      required this.nameOf,
      this.onTap,
      this.height = 37,
      super.key});

  final DjSession dj;

  /// Display name of a user id.
  final String Function(String userId) nameOf;
  final VoidCallback? onTap;
  final double height;

  static String get labelDjNothingPlaying => Intl.message("Nothing playing",
      name: "labelDjNothingPlaying",
      desc: "Under the DJ's name in the list of who is in a voice channel, "
          "while the DJ plays nothing");

  static String labelDjSidebarDj(String name) => Intl.message("DJ · $name",
      name: "labelDjSidebarDj",
      args: [name],
      desc: "Row for the DJ booth in the list of who is in a voice channel; "
          "the placeholder is the DJ's name");

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dj,
      builder: (context, _) {
        final djUserId = dj.djUserId;
        if (dj.isDisposed || djUserId == null || dj.isVacant) {
          return const SizedBox.shrink();
        }
        final track = dj.current;
        final color = Theme.of(context).colorScheme.secondary;
        final song = track == null
            ? labelDjNothingPlaying
            : track.artist == null
                ? track.title
                : '${track.title} · ${track.artist}';
        return SizedBox(
          height: height,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  spacing: 8,
                  children: [
                    VinylDisc(
                        size: 24,
                        spinning: dj.isPlaying && !dj.isBuffering,
                        label: track?.thumbnail == null
                            ? null
                            : NetworkImage(track!.thumbnail!)),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(labelDjSidebarDj(nameOf(djUserId)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: color, height: 1.2)),
                          Text(song,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: color.withValues(alpha: 0.7),
                                      height: 1.2)),
                        ],
                      ),
                    ),
                    if (track != null && !dj.isPlaying)
                      Icon(Icons.pause_rounded, size: 14, color: color),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Right-click actions on the call member [userId] ([displayName]).
///
/// On the DJ, [musicVolume] (the listener's own music slider) comes first:
/// right-clicking whoever plays the music is where people look for it.
List<tiamat.ContextMenuItem> djMemberMenuItems(
  DjSession? dj, {
  required String userId,
  required String displayName,
  Widget? musicVolume,
}) {
  if (dj == null || dj.isDisposed) return const [];
  final actions = _actions(dj, userId: userId, displayName: displayName);
  if (musicVolume == null || !dj.isDjUser(userId) || dj.current == null) {
    return actions;
  }
  return [
    tiamat.ContextMenuItem(
      text: labelDjMusicVolume,
      customBuilder: (context, onClicked, {closeMenu}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            tiamat.Text.labelLow(labelDjMusic),
            musicVolume,
          ],
        ),
      ),
    ),
    ...actions,
  ];
}

String get labelDjMusicVolume => Intl.message("Music volume",
    name: "labelDjMusicVolume",
    desc: "Names the DJ booth's music volume slider in the menu opened on "
        "the DJ in a call (the slider is only for the user)");

String get labelDjMusic => Intl.message("Music",
    name: "labelDjMusic",
    desc: "Short label before the DJ booth's music volume slider, in the "
        "menu opened on the DJ in a call");

String get promptDjStopDjing => Intl.message("Stop DJing",
    name: "promptDjStopDjing",
    desc: "Button and menu entry that makes the user stop being the DJ: the "
        "music stops and the DJ booth is free for someone else");

String promptDjStopHandingOver(String name) =>
    Intl.message("Stop handing over to $name",
        name: "promptDjStopHandingOver",
        args: [name],
        desc: "Menu entry on someone the DJ is passing the DJ booth to: calls "
            "the pass off");

String promptDjPassDecksTo(String name) => Intl.message(
    "Pass the decks to $name",
    name: "promptDjPassDecksTo",
    args: [name],
    desc: "Menu entry on someone in the call: makes them the DJ (hands them "
        "\"the decks\" of the DJ booth)");

String promptDjPassDecksToAsker(String name) =>
    Intl.message("Pass the decks to $name ✋",
        name: "promptDjPassDecksToAsker",
        args: [name],
        desc: "Menu entry on someone in the call who asked to become the DJ "
            "(the raised hand): makes them the DJ");

String messageDjMemberCantDj(String name) =>
    Intl.message("$name's app can't DJ",
        name: "messageDjMemberCantDj",
        args: [name],
        desc: "Note in the menu opened on someone in a call whose app cannot "
            "play music for the call, so the DJ booth can't be passed to them");

String messageDjMemberOnWeb(String name) => Intl.message(
    "$name is on the web: only the desktop app can DJ",
    name: "messageDjMemberOnWeb",
    args: [name],
    desc: "Note in the menu opened on someone in a call who uses the app in "
        "a browser, so the DJ booth can't be passed to them");

String messageDjMemberOnPlatform(String name, String platform) =>
    Intl.message("$name is on $platform: only the desktop app can DJ",
        name: "messageDjMemberOnPlatform",
        args: [name, platform],
        desc: "Note in the menu opened on someone in a call who uses the app "
            "on a phone or a Mac (the second placeholder: Android, iOS, "
            "macOS), so the DJ booth can't be passed to them");

String get promptDjStopAsking => Intl.message("Stop asking to be the DJ",
    name: "promptDjStopAsking",
    desc: "Menu entry on the DJ in a call: takes back the user's request to "
        "become the DJ");

String get promptDjRequest => Intl.message("Request to become DJ",
    name: "promptDjRequest",
    desc: "Menu entry on the DJ in a call: asks them to pass the DJ booth "
        "to the user");

String get promptDjBecome => Intl.message("Become the DJ",
    name: "promptDjBecome",
    desc: "Menu entry on the user themselves in a call while nobody is the "
        "DJ: takes the DJ booth");

String get labelDjDesktopOnlyMenu =>
    Intl.message("🎧 The decks live in the desktop app",
        name: "labelDjDesktopOnlyMenu",
        desc: "Note in the menus of the DJ booth in apps that can't be the DJ "
            "(web, phones): DJing needs the desktop app");

String promptDjTakeOverAway(int minutes) =>
    Intl.message("Take the decks (DJ away $minutes min)",
        name: "promptDjTakeOverAway",
        args: [minutes],
        desc: "Button and menu entry that takes the DJ booth from a DJ who has "
            "been away; the placeholder is how many minutes away allow it");

String labelDjAwayWait(String name, int minutes, int limit) => Intl.message(
    "$name has been away $minutes min: the decks can be taken once they have "
    "been away $limit",
    name: "labelDjAwayWait",
    args: [name, minutes, limit],
    desc: "Tooltip and menu note on a DJ who is away: how many minutes they "
        "have been away, and after how many minutes the DJ booth can be "
        "taken from them");

List<tiamat.ContextMenuItem> _actions(
  DjSession dj, {
  required String userId,
  required String displayName,
}) {
  final isSelf = userId == dj.selfUserId;
  final canDj = dj.caps.canDj;

  if (dj.isDj) {
    if (isSelf) {
      return [
        tiamat.ContextMenuItem(
            text: promptDjStopDjing,
            icon: Icons.album_outlined,
            onPressed: () => dj.stopDjing()),
      ];
    }
    final candidate = dj.passCandidateFor(userId);
    if (candidate != null && dj.passTarget == candidate) {
      return [
        tiamat.ContextMenuItem(
            text: promptDjStopHandingOver(displayName),
            icon: Icons.close_rounded,
            onPressed: dj.cancelPass),
      ];
    }
    if (candidate != null) {
      return [
        tiamat.ContextMenuItem(
            text: dj.hasRequestedUser(userId)
                ? promptDjPassDecksToAsker(displayName)
                : promptDjPassDecksTo(displayName),
            icon: Icons.album_rounded,
            onPressed: () => dj.passTo(candidate)),
      ];
    }
    return [
      _note(switch (dj.platformOf(userId)) {
        null => messageDjMemberCantDj(displayName),
        'web' => messageDjMemberOnWeb(displayName),
        final String platform =>
          messageDjMemberOnPlatform(displayName, _platformName(platform)),
      }),
    ];
  }

  if (dj.isDjUser(userId) && !isSelf) {
    if (!canDj) return [_desktopOnly()];
    if (dj.isJoining) return const [];
    final away = dj.djAwayFor;
    return [
      if (dj.canTakeOver)
        tiamat.ContextMenuItem(
            text: takeOverLabel,
            icon: Icons.album_rounded,
            onPressed: () => dj.takeOver())
      else if (away != null)
        _note(takeOverWait(displayName, away)),
      dj.hasRequested
          ? tiamat.ContextMenuItem(
              text: promptDjStopAsking,
              icon: Icons.back_hand_outlined,
              onPressed: () => dj.requestDj(false))
          : tiamat.ContextMenuItem(
              text: promptDjRequest,
              icon: Icons.back_hand_rounded,
              onPressed: () => dj.requestDj(true)),
    ];
  }

  if (isSelf && dj.isVacant && dj.role == DjRole.listener) {
    if (!canDj) return [_desktopOnly()];
    return [
      tiamat.ContextMenuItem(
          text: promptDjBecome,
          icon: Icons.album_rounded,
          onPressed: () => dj.becomeDj()),
    ];
  }

  return const [];
}

/// The action that takes the decks from a DJ who has been away long enough.
String get takeOverLabel =>
    promptDjTakeOverAway(DjSession.takeOverAfterAway.inMinutes);

/// Why the decks can't be taken yet from [name], away for [away].
String takeOverWait(String name, Duration away) => labelDjAwayWait(
    name, away.inMinutes, DjSession.takeOverAfterAway.inMinutes);

/// What [platform] is called (a name, the same in every language).
String _platformName(String platform) => switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'macos' => 'macOS',
      _ => platform,
    };

/// A menu line saying DJing needs the desktop app, with a link to download
/// it.
tiamat.ContextMenuItem _desktopOnly() => tiamat.ContextMenuItem(
      text: labelDjDesktopOnlyMenu,
      customBuilder: (context, onClicked, {closeMenu}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Icon(Icons.desktop_windows_outlined,
                      size: 18, color: Theme.of(context).colorScheme.outline),
                  Flexible(child: tiamat.Text.labelLow(labelDjDesktopOnlyMenu)),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  DesktopAppNotice.openDownloads(context);
                  closeMenu?.call();
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(DesktopAppNotice.labelDownloadDesktopApp),
              ),
            ],
          ),
        ),
      ),
    );

/// A menu line that explains instead of acting.
tiamat.ContextMenuItem _note(String text) => tiamat.ContextMenuItem(
      text: text,
      customBuilder: (context, onClicked, {closeMenu}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Theme.of(context).colorScheme.outline),
              Flexible(child: tiamat.Text.labelLow(text)),
            ],
          ),
        ),
      ),
    );
