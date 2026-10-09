// The DJ booth: who's on the decks, what's playing, what's next.
//
// Everyone sees the same booth; only the DJ's has controls. Listeners get
// their own volume and, on desktop, a way to ask for the decks.
import 'dart:async';

import 'package:rooster/client/components/dj/dj_links.dart';
import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/filled_icon_button_style.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/dj/dj_member_ui.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/organisms/dj/dj_prompts.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// "3:07", "1:02:45".
String formatDjTime(int ms) {
  final total = (ms / 1000).floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

double get maxDjMusicVolume => kIsWeb ? 1.0 : 1.5;

/// Sets how loud the booth's music plays for us. [save] keeps it: while a
/// slider is dragged only the sound follows, and the level is saved (with
/// everything listening to settings) once, when it is let go.
Future<void> setDjMusicVolume(VoipSession session, double volume,
    {bool save = true}) async {
  final streams = session.streams
      .where((s) =>
          s.type == VoipStreamType.music &&
          s.direction == VoipStreamDirection.incoming)
      .toList();
  if (!save) {
    for (final stream in streams.whereType<MatrixLivekitVoipStream>()) {
      if (!session.isDeafened) stream.applyVolume(volume);
    }
    _liveMusicVolume.value = volume;
    return;
  }
  if (streams.isEmpty) {
    await preferences.djMusicVolume.set(volume);
  } else {
    for (final stream in streams) {
      await stream.setVolume(volume);
    }
  }
  // Cleared last: everything reading it falls back to the saved level, and
  // clearing it first makes the DJ's own music jump back to the old one for
  // as long as it takes to write the new one.
  _liveMusicVolume.value = null;
}

/// The level while a music slider is being dragged, for the DJ's monitor
/// and the other sliders; null otherwise.
final ValueNotifier<double?> _liveMusicVolume = ValueNotifier(null);
ValueListenable<double?> get liveDjMusicVolume => _liveMusicVolume;

class DjBoothPanel extends StatelessWidget {
  const DjBoothPanel(
      {required this.session, required this.dj, this.onClose, super.key});

  final VoipSession session;
  final DjSession dj;
  final VoidCallback? onClose;

  static String get labelDjBoothTitle => Intl.message("DJ Booth",
      name: "labelDjBoothTitle",
      desc: "Title of the DJ booth panel in a call: music everyone in the "
          "call hears, played by one of them, the DJ");

  static String get tooltipDjCloseBooth => Intl.message("Close the booth",
      name: "tooltipDjCloseBooth",
      desc: "Tooltip on the button that closes the DJ booth panel");

  Member _member(String userId) =>
      session.client.getRoom(session.roomId)!.getMemberOrFallback(userId);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: tiamat.Tile.low(
        child: ListenableBuilder(
          listenable: dj,
          builder: (context, _) {
            if (dj.isDisposed) return const SizedBox.shrink();
            final nobody = dj.djIdentity == null || dj.isVacant;
            final vacant = nobody && !dj.isJoining && !dj.isDj;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                Expanded(
                  child: vacant
                      ? _Vacant(dj: dj)
                      : _Booth(session: session, dj: dj, memberOf: _member),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
      child: Row(
        children: [
          VinylDisc(size: 20, spinning: dj.isPlaying && !dj.isBuffering),
          const SizedBox(width: 10),
          Expanded(child: tiamat.Text.largeTitle(labelDjBoothTitle)),
          if (onClose != null)
            IconButton(
              tooltip: tooltipDjCloseBooth,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class _Vacant extends StatelessWidget {
  const _Vacant({required this.dj});

  final DjSession dj;

  static String get labelDjDecksFree => Intl.message("The decks are free",
      name: "labelDjDecksFree",
      desc: "Title of the DJ booth while nobody is the DJ (\"the decks\" are "
          "the DJ's controls)");

  static String labelDjLeftoverSongs(int howMany) => Intl.plural(howMany,
      one: "Pick up where the last DJ left off: 1 song waiting.",
      other: "Pick up where the last DJ left off: $howMany songs waiting.",
      name: "labelDjLeftoverSongs",
      args: [howMany],
      desc: "In the DJ booth while nobody is the DJ, when the last DJ left "
          "songs in the queue; the number is how many");

  static String get labelDjVacantDescription => Intl.message(
      "Play music everyone in the call hears at the same time. Each listener "
      "sets their own volume.",
      name: "labelDjVacantDescription",
      desc: "Explains the DJ booth while nobody is the DJ and nothing is "
          "queued");

  static String get promptDjTakeDecksToPlay =>
      Intl.message("Take the decks to play music",
          name: "promptDjTakeDecksToPlay",
          desc: "Button in the DJ booth while nobody is the DJ: makes the user "
              "the DJ");

  @override
  Widget build(BuildContext context) {
    final leftover = dj.current != null || dj.queue.isNotEmpty;
    final count = dj.queue.length + (dj.current != null ? 1 : 0);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const VinylDisc(size: 120, spinning: false),
            const SizedBox(height: 4),
            tiamat.Text.largeTitle(labelDjDecksFree),
            tiamat.Text.labelLow(
              leftover ? labelDjLeftoverSongs(count) : labelDjVacantDescription,
            ),
            const SizedBox(height: 4),
            if (dj.caps.canDj)
              tiamat.Button(
                  text: promptDjTakeDecksToPlay, onTap: () => dj.becomeDj())
            else
              const DjDesktopOnlyNote(),
          ],
        ),
      ),
    );
  }
}

class DjDesktopOnlyNote extends StatelessWidget {
  const DjDesktopOnlyNote({super.key});

  static String get labelDjDesktopOnlyNote => Intl.message(
      "🎧 Want the aux? Play YouTube, SoundCloud or your own tracks for the "
      "whole call from the desktop app. Until then, enjoy the set from here.",
      name: "labelDjDesktopOnlyNote",
      desc: "In the DJ booth of an app that can't be the DJ (web, phones): "
          "being the DJ needs the desktop app. A link to download it "
          "follows");

  @override
  Widget build(BuildContext context) {
    return DesktopAppNotice(labelDjDesktopOnlyNote);
  }
}

/// A booth with a DJ: everything in one scroll, so no section can push
/// another off screen however many requests or links pile up.
class _Booth extends StatelessWidget {
  const _Booth(
      {required this.session, required this.dj, required this.memberOf});

  final VoipSession session;
  final DjSession dj;
  final Member Function(String userId) memberOf;

  static String get labelDjAskedHowTo => Intl.message(
      "You asked for the decks. Once the DJ passes them to you, you can add "
      "music.",
      name: "labelDjAskedHowTo",
      desc: "In the DJ booth, to someone who asked the DJ to pass them the "
          "booth (\"the decks\")");

  static String get labelDjHowToStart => Intl.message(
      "Want to play music? Ask for the decks above; the DJ can pass them to "
      "you.",
      name: "labelDjHowToStart",
      desc: "In the DJ booth, to a listener: how to become the DJ (\"Ask for "
          "the decks\" is the button above)");

  static String get labelDjQueueEmptyDj =>
      Intl.message("Songs you add line up here. Drag them to reorder.",
          name: "labelDjQueueEmptyDj",
          desc: "In the DJ booth's empty queue, to the DJ");

  static String get labelDjQueueEmpty => Intl.message("Nothing queued.",
      name: "labelDjQueueEmpty",
      desc: "In the DJ booth's empty queue, to listeners");

  static String labelDjHandingOverLocked(String name) => Intl.message(
      "Handing the decks to $name. The music keeps playing; the queue is "
      "locked until they take over.",
      name: "labelDjHandingOverLocked",
      args: [name],
      desc: "In the DJ booth, to the DJ, while the booth is being passed to "
          "someone (the placeholder)");

  static String labelDjHandingOver(String name) => Intl.message(
      "Handing the decks to $name…",
      name: "labelDjHandingOver",
      args: [name],
      desc: "In the DJ booth, to listeners, while the DJ passes the booth to "
          "someone (the placeholder)");

  /// Editing is the DJ's, and stops while the decks change hands.
  bool get editable => dj.isDj && dj.passTarget == null;

  @override
  Widget build(BuildContext context) {
    final queue = dj.queue;
    final booth = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _DjStrip(
              key: const ValueKey('strip'), dj: dj, memberOf: memberOf),
        ),
        if (_handover(context) case final line?)
          SliverToBoxAdapter(key: const ValueKey('handover'), child: line),
        SliverToBoxAdapter(
          key: const ValueKey('now'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _NowPlaying(session: session, dj: dj),
          ),
        ),
        if (dj.isDj)
          SliverToBoxAdapter(
            key: const ValueKey('add'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _AddBar(dj: dj, enabled: editable),
            ),
          ),
        if (!dj.isDj && !dj.isJoining && dj.caps.canDj)
          SliverToBoxAdapter(
            key: const ValueKey('how-to-start'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: tiamat.Text.labelLow(
                  dj.hasRequested ? labelDjAskedHowTo : labelDjHowToStart),
            ),
          ),
        if (dj.isDj && dj.requests.isNotEmpty)
          SliverToBoxAdapter(
            key: const ValueKey('requests'),
            child: _Requests(dj: dj, memberOf: memberOf),
          ),
        SliverToBoxAdapter(
          key: const ValueKey('queue-header'),
          child: _QueueHeader(dj: dj, editable: editable),
        ),
        if (queue.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: tiamat.Text.labelLow(
                  dj.isDj ? labelDjQueueEmptyDj : labelDjQueueEmpty),
            ),
          )
        else if (editable)
          SliverReorderableList(
            itemCount: queue.length,
            onReorder: dj.move,
            itemBuilder: (context, i) => _QueueRow(
              key: ValueKey(queue[i].id),
              dj: dj,
              track: queue[i],
              index: i,
              editable: true,
              addedBy: memberOf(queue[i].addedBy),
            ),
          )
        else
          SliverList.builder(
            itemCount: queue.length,
            itemBuilder: (context, i) => _QueueRow(
              key: ValueKey(queue[i].id),
              dj: dj,
              track: queue[i],
              index: i,
              editable: false,
              addedBy: memberOf(queue[i].addedBy),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
    return editable ? _BoothDrop(dj: dj, child: booth) : booth;
  }

  Widget? _handover(BuildContext context) {
    final target = dj.passTarget;
    if (target == null || dj.isJoining) return null;
    final member = memberOf(djUserIdOf(target));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            spacing: 10,
            children: [
              const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              Expanded(
                child: tiamat.Text.labelLow(dj.isDj
                    ? labelDjHandingOverLocked(member.displayName)
                    : labelDjHandingOver(member.displayName)),
              ),
              if (dj.isDj)
                TextButton(
                    onPressed: dj.cancelPass,
                    child: Text(CommonStrings.promptCancel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DjStrip extends StatelessWidget {
  const _DjStrip({required this.dj, required this.memberOf, super.key});

  final DjSession dj;
  final Member Function(String userId) memberOf;

  static String labelDjHandingYou(String name) =>
      Intl.message("$name is handing you the decks…",
          name: "labelDjHandingYou",
          args: [name],
          desc: "Top of the DJ booth while the DJ (the placeholder) passes the "
              "booth to the user");

  static String get labelDjGettingReady =>
      Intl.message("Getting the decks ready…",
          name: "labelDjGettingReady",
          desc: "Top of the DJ booth while the user's app gets ready to be the "
              "DJ");

  static String get labelDjYouOnDecks => Intl.message("You're on the decks",
      name: "labelDjYouOnDecks",
      desc: "Top of the DJ booth when the user is the DJ");

  static String labelDjOnDecks(String name) =>
      Intl.message("$name is on the decks",
          name: "labelDjOnDecks",
          args: [name],
          desc: "Top of the DJ booth: who the DJ is (the placeholder)");

  static String get promptDjAskedCancel => Intl.message("✋ Asked · Cancel",
      name: "promptDjAskedCancel",
      desc: "Button at the top of the DJ booth after the user asked to "
          "become the DJ: shows they asked, and takes the request back");

  static String get promptDjAskForDecks => Intl.message("Ask for the decks",
      name: "promptDjAskForDecks",
      desc: "Button at the top of the DJ booth: asks the DJ to pass the "
          "booth (\"the decks\") to the user");

  @override
  Widget build(BuildContext context) {
    final member = memberOf(dj.djUserId ?? dj.selfUserId);
    final you = dj.isDj || dj.djIdentity == dj.selfIdentity;
    final String line;
    if (dj.isJoining && dj.djIdentity != dj.selfIdentity) {
      line = labelDjHandingYou(member.displayName);
    } else if (dj.isJoining) {
      line = labelDjGettingReady;
    } else {
      line = you ? labelDjYouOnDecks : labelDjOnDecks(member.displayName);
    }

    // On one line: a label too long for the row is cut short (see below).
    Widget label(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

    Widget? action;
    if (dj.isDj) {
      action = TextButton.icon(
        onPressed: () => dj.stopDjing(),
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: label(promptDjStopDjing),
      );
    } else if (dj.isJoining) {
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          if (dj.djIdentity != dj.selfIdentity)
            Flexible(
              child: TextButton(
                  onPressed: () => dj.stopDjing(),
                  child: label(CommonStrings.promptPoliteNo)),
            ),
        ],
      );
    } else if (dj.caps.canDj && dj.canTakeOver) {
      action = Tooltip(
        message: takeOverLabel,
        child: TextButton.icon(
          onPressed: () => dj.takeOver(),
          icon: const Icon(Icons.album_rounded, size: 16),
          label: label(takeOverLabel),
        ),
      );
    } else if (dj.caps.canDj) {
      final away = dj.djAwayFor;
      action = dj.hasRequested
          ? TextButton(
              onPressed: () => dj.requestDj(false),
              child: label(promptDjAskedCancel),
            )
          : TextButton.icon(
              onPressed: () => dj.requestDj(true),
              icon: const Icon(Icons.back_hand_outlined, size: 16),
              label: label(promptDjAskForDecks),
            );
      if (away != null) {
        action = Tooltip(
            message: takeOverWait(member.displayName, away), child: action);
      }
    }

    final trailing = action;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                tiamat.Avatar(
                    radius: 16,
                    image: member.avatar,
                    placeholderColor: member.defaultColor,
                    placeholderText: member.displayName),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: VinylDisc(
                      size: 16, spinning: dj.isPlaying && !dj.isBuffering),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: tiamat.Text.labelEmphasised(line,
                  overflow: TextOverflow.ellipsis),
            ),
            // A long label (a longer language, the take-over one) is cut
            // short rather than pushing the row past the booth's edge.
            if (trailing != null)
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests({required this.dj, required this.memberOf});

  final DjSession dj;
  final Member Function(String userId) memberOf;

  static String get labelDjAskingForDecks => Intl.message(
      "✋ Asking for the decks",
      name: "labelDjAskingForDecks",
      desc: "Heading, in the DJ's booth, of the list of people who asked to "
          "become the DJ");

  static String get promptDjPassDecks => Intl.message("Pass the decks",
      name: "promptDjPassDecks",
      desc: "Button next to someone who asked to become the DJ: passes them "
          "the DJ booth");

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              tiamat.Text.labelLow(labelDjAskingForDecks),
              for (final identity in dj.requests)
                Builder(builder: (context) {
                  final member = memberOf(djUserIdOf(identity));
                  final canPass = dj.passTarget == null &&
                      dj.capsOf(identity)?.canDj == true;
                  return LayoutBuilder(
                    builder: (context, constraints) => Row(
                      spacing: 10,
                      children: [
                        tiamat.Avatar(
                            radius: 12,
                            image: member.avatar,
                            placeholderColor: member.defaultColor,
                            placeholderText: member.displayName),
                        Expanded(
                            child: tiamat.Text.label(member.displayName,
                                overflow: TextOverflow.ellipsis)),
                        // Half the row at most, cut short with its whole
                        // label in the tooltip: a longer language's label
                        // ran past the booth's edge.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth / 2),
                          child: Tooltip(
                            message: promptDjPassDecks,
                            child: TextButton(
                              onPressed:
                                  canPass ? () => dj.passTo(identity) : null,
                              child: Text(promptDjPassDecks,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

/// The song on the decks: sleeve and record, title, progress, controls and
/// the listener's own volume.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying({required this.session, required this.dj});

  final VoipSession session;
  final DjSession dj;

  static String get labelDjIdleDj => Intl.message(
      "Nothing on the decks. Paste a link below to start the music.",
      name: "labelDjIdleDj",
      desc: "In the DJ booth, to the DJ, while no song plays");

  static String get labelDjIdleListener => Intl.message("Nothing playing yet.",
      name: "labelDjIdleListener",
      desc: "In the DJ booth, to listeners, while no song plays");

  static String get labelDjSongPaused => Intl.message("Paused",
      name: "labelDjSongPaused",
      desc: "Under the song in the DJ booth while the DJ has paused it");

  static String get tooltipDjRestart => Intl.message("Back to the start",
      name: "tooltipDjRestart",
      desc: "Tooltip on the DJ's button that plays the song from its start");

  static String get tooltipDjPauseForEveryone =>
      Intl.message("Pause for everyone",
          name: "tooltipDjPauseForEveryone",
          desc: "Tooltip on the DJ's pause button: the music pauses for the "
              "whole call");

  static String get tooltipDjStopNothingNext =>
      Intl.message("Stop (nothing next)",
          name: "tooltipDjStopNothingNext",
          desc: "Tooltip on the DJ's next-song button when the queue is empty: "
              "it stops the music");

  static String get tooltipDjNextSong => Intl.message("Next song",
      name: "tooltipDjNextSong",
      desc: "Tooltip on the DJ's button that plays the next song in the "
          "queue");

  static String get promptDjOpenSongPage => Intl.message("Open the song page",
      name: "promptDjOpenSongPage",
      desc: "Button and menu entry in the DJ booth that opens the web page a "
          "song came from");

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  Timer? _clock;
  double? _dragging;
  String? _draggingTrack;

  DjSession get dj => widget.dj;

  @override
  void initState() {
    super.initState();
    // The position moves on its own: redraw it a few times a second.
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && dj.isPlaying) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = dj.current;
    // A drag left over from the previous song means nothing for this one.
    if (_draggingTrack != null && _draggingTrack != track?.id) {
      _dragging = null;
      _draggingTrack = null;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: track == null ? _idle(context) : _playing(context, track),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 12,
          children: [
            const VinylDisc(size: 56, spinning: false),
            Expanded(
              child: tiamat.Text.labelLow(dj.isDj
                  ? _NowPlaying.labelDjIdleDj
                  : _NowPlaying.labelDjIdleListener),
            ),
          ],
        ),
        DjMusicVolume(session: widget.session, width: null),
      ],
    );
  }

  Widget _playing(BuildContext context, DjTrack track) {
    final duration = dj.durationMs ?? track.durationMs ?? 0;
    final position = _dragging?.round() ?? dj.positionMs;
    final spinning = dj.isPlaying && !dj.isBuffering;
    final controls = dj.isDj && dj.passTarget == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Sleeve(track: track, spinning: spinning),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  tiamat.Text.labelEmphasised(track.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (track.artist != null)
                    tiamat.Text.labelLow(track.artist!,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    spacing: 6,
                    children: [
                      DjSourceChip(track.kind),
                      if (dj.isBuffering)
                        Flexible(
                          child: tiamat.Text.tiny(CommonStrings.labelLoading,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )
                      else if (!dj.isPlaying)
                        Flexible(
                          child: tiamat.Text.tiny(_NowPlaying.labelDjSongPaused,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: controls ? 6 : 0, disabledThumbRadius: 0),
          ),
          child: Slider(
            value: duration > 0 ? position.clamp(0, duration).toDouble() : 0,
            max: duration > 0 ? duration.toDouble() : 1,
            onChanged: controls && duration > 0 && !dj.isBuffering
                ? (v) => setState(() {
                      _dragging = v;
                      _draggingTrack = track.id;
                    })
                : null,
            onChangeEnd: controls && duration > 0 && !dj.isBuffering
                ? (v) {
                    if (_draggingTrack == dj.current?.id) dj.seek(v.round());
                    setState(() {
                      _dragging = null;
                      _draggingTrack = null;
                    });
                  }
                : null,
          ),
        ),
        Row(
          children: [
            tiamat.Text.tiny(formatDjTime(position)),
            const Spacer(),
            tiamat.Text.tiny(duration > 0 ? formatDjTime(duration) : '--:--'),
          ],
        ),
        Row(
          children: [
            if (dj.isDj) ...[
              IconButton(
                tooltip: _NowPlaying.tooltipDjRestart,
                icon: const Icon(Icons.replay_rounded),
                onPressed:
                    controls && !dj.isBuffering ? () => dj.seek(0) : null,
              ),
              IconButton.filled(
                style: filledIconButtonStyle(context),
                tooltip: dj.isPlaying
                    ? _NowPlaying.tooltipDjPauseForEveryone
                    : CommonStrings.promptPlay,
                iconSize: 28,
                icon: Icon(dj.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
                onPressed: controls ? dj.togglePause : null,
              ),
              IconButton(
                tooltip: dj.queue.isEmpty
                    ? _NowPlaying.tooltipDjStopNothingNext
                    : _NowPlaying.tooltipDjNextSong,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: controls ? dj.skip : null,
              ),
            ],
            const Spacer(),
            if (track.pageUrl case final page?)
              IconButton(
                tooltip: _NowPlaying.promptDjOpenSongPage,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                onPressed: () =>
                    LinkUtils.open(Uri.parse(page), context: context),
              ),
          ],
        ),
        // A line of its own, the booth's whole width: a long slider sets a
        // level precisely.
        DjMusicVolume(session: widget.session, width: null),
      ],
    );
  }
}

/// The song's art in a sleeve, with the record half out of it, turning.
class _Sleeve extends StatelessWidget {
  const _Sleeve({required this.track, required this.spinning});

  final DjTrack track;
  final bool spinning;

  static const double size = 72;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.45,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: size * 0.45,
            top: 2,
            child: VinylDisc(
              size: size - 4,
              spinning: spinning,
              label: track.thumbnail == null
                  ? null
                  : NetworkImage(track.thumbnail!),
            ),
          ),
          DjTrackArt(track: track, size: size, radius: 6, elevated: true),
        ],
      ),
    );
  }
}

class DjTrackArt extends StatelessWidget {
  const DjTrackArt(
      {required this.track,
      this.size = 40,
      this.radius = 4,
      this.elevated = false,
      super.key});

  final DjTrack track;
  final double size;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DjSourceChip.colorOf(track.kind),
            Color.lerp(DjSourceChip.colorOf(track.kind), Colors.black, 0.6)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded,
            color: Colors.white70, size: size * 0.45),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated
            ? const [
                BoxShadow(
                    color: Colors.black38, blurRadius: 8, offset: Offset(2, 2))
              ]
            : null,
      ),
      child: track.thumbnail == null
          ? placeholder
          : Image.network(
              track.thumbnail!,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

/// The label a song's source extension gave it, or "File" for the DJ's own.
class DjSourceChip extends StatelessWidget {
  const DjSourceChip(this.kind, {super.key});

  final String kind;

  static const _palette = [
    Color(0xFFE53935),
    Color(0xFFFF7A1A),
    Color(0xFF1DB954),
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
    Color(0xFFFDD835),
  ];

  static Color colorOf(String kind) {
    if (kind == DjTrack.fileKind) return const Color(0xFF26A69A);
    if (kind == DjTrack.linkKind) return const Color(0xFF7E57C2);
    // The same label gets the same colour on every client.
    final hash = kind
        .toLowerCase()
        .codeUnits
        .fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }

  static String get labelDjSourceFile => Intl.message("File",
      name: "labelDjSourceFile",
      desc: "Tag on a song in the DJ booth that plays from a file on the "
          "DJ's computer");

  static String get labelDjSourceLink => Intl.message("Link",
      name: "labelDjSourceLink",
      desc: "Tag on a song in the DJ booth that plays from a link");

  static String nameOf(String kind) {
    if (kind == DjTrack.fileKind) return labelDjSourceFile;
    if (kind == DjTrack.linkKind) return labelDjSourceLink;
    // Clients from before extensions sent lowercase names.
    return kind == kind.toLowerCase()
        ? kind[0].toUpperCase() + kind.substring(1)
        : kind;
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(kind);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(nameOf(kind),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Mute button and slider for the booth's music, for this listener only.
class DjMusicVolume extends StatefulWidget {
  const DjMusicVolume(
      {required this.session, this.width = defaultWidth, super.key});

  /// Long enough to set a level precisely: at 88 px a pixel was over 1 %.
  static const double defaultWidth = 180;

  /// Null: the slider takes all the width it is given (the booth's own
  /// line), and the level is written next to it.

  final VoipSession session;
  final double? width;

  static String tooltipDjMusicVolume(int percent) => Intl.message(
      "Music volume, only for you ($percent%)",
      name: "tooltipDjMusicVolume",
      args: [percent],
      desc: "Tooltip on the DJ booth's music volume slider, which only "
          "changes what the user hears; the number is the level in percent");

  static String get tooltipDjUnmuteMusic => Intl.message("Unmute the music",
      name: "tooltipDjUnmuteMusic",
      desc: "Tooltip on the button that brings back the DJ booth's music for "
          "the user");

  static String get tooltipDjMuteMusic => Intl.message("Mute the music for you",
      name: "tooltipDjMuteMusic",
      desc: "Tooltip on the button that mutes the DJ booth's music for the "
          "user only");

  @override
  State<DjMusicVolume> createState() => _DjMusicVolumeState();
}

class _DjMusicVolumeState extends State<DjMusicVolume> {
  StreamSubscription? _sub;

  /// Being dragged: the level is only saved when let go.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _sub = preferences.djMusicVolume.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _liveMusicVolume.addListener(_onLive);
  }

  void _onLive() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _liveMusicVolume.removeListener(_onLive);
    // Gone mid-drag (the booth swaps its idle and playing layouts when a DJ
    // starts or a song changes): the slider is never let go, so save the
    // level here, or the next music stream plays at the old one.
    final live = _liveMusicVolume.value;
    if (_dragging && live != null) setDjMusicVolume(widget.session, live);
    super.dispose();
  }

  void _toggleMute() {
    final volume = preferences.djMusicVolume.value;
    if (volume > 0) {
      preferences.djMusicPremuteVolume.set(volume);
      setDjMusicVolume(widget.session, 0);
    } else {
      final back = preferences.djMusicPremuteVolume.value;
      setDjMusicVolume(widget.session, back > 0 ? back : 0.6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final volume = (_liveMusicVolume.value ?? preferences.djMusicVolume.value)
        .clamp(0.0, maxDjMusicVolume);
    final fill = widget.width == null;
    final slider = Tooltip(
      message: DjMusicVolume.tooltipDjMusicVolume((volume * 100).round()),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 5,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
        child: Slider(
          value: volume,
          max: maxDjMusicVolume,
          onChangeStart: (_) => _dragging = true,
          onChanged: (v) => setDjMusicVolume(widget.session, v, save: false),
          onChangeEnd: (v) {
            _dragging = false;
            setDjMusicVolume(widget.session, v);
          },
        ),
      ),
    );
    return Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        IconButton(
          tooltip: volume == 0
              ? DjMusicVolume.tooltipDjUnmuteMusic
              : DjMusicVolume.tooltipDjMuteMusic,
          icon: Icon(
            volume == 0
                ? Icons.volume_off_rounded
                : volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            size: 20,
          ),
          onPressed: _toggleMute,
        ),
        if (fill) ...[
          Expanded(child: slider),
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: tiamat.Text.labelLow('${(volume * 100).round()}%'),
            ),
          ),
        ] else
          SizedBox(width: widget.width, child: slider),
      ],
    );
  }
}

/// Queues the audio files among [paths] (others are skipped).
Future<void> addDjFiles(DjSession dj, List<String> paths) async {
  final audio = [
    for (final path in paths)
      if (DjPlatform.audioFileExtensions
          .contains(path.split('.').last.toLowerCase()))
        path
  ];
  if (audio.isEmpty) return;
  dj.addTracks(await DjPlatform.instance
      .localTracks(audio, addedBy: dj.selfUserId, newId: dj.newTrackId));
}

final Set<_BoothDropState> _boothDrops = {};

/// Whether a file dropped at [globalPosition] lands on a DJ's booth, which
/// takes it, so the chat behind should not upload it too.
bool djBoothTakesDrop(Offset globalPosition) => _boothDrops.any((drop) {
      final box = drop.context.findRenderObject() as RenderBox?;
      return box != null &&
          box.attached &&
          (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
    });

/// Audio files dropped on the booth go into the DJ's queue.
class _BoothDrop extends StatefulWidget {
  const _BoothDrop({required this.dj, required this.child});

  final DjSession dj;
  final Widget child;

  static String get labelDjDropSongs => Intl.message("Drop songs to queue them",
      name: "labelDjDropSongs",
      desc: "Over the DJ booth while the DJ drags audio files onto it");

  @override
  State<_BoothDrop> createState() => _BoothDropState();
}

class _BoothDropState extends State<_BoothDrop> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _boothDrops.add(this);
  }

  @override
  void dispose() {
    _boothDrops.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovered = true),
      onDragExited: (_) => setState(() => _hovered = false),
      onDragDone: (details) {
        setState(() => _hovered = false);
        addDjFiles(widget.dj, [
          for (final file in details.files)
            if (file.path.isNotEmpty) file.path
        ]);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovered)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.85),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                      child:
                          tiamat.Text.largeTitle(_BoothDrop.labelDjDropSongs)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the DJ pastes links and adds files.
class _AddBar extends StatefulWidget {
  const _AddBar({required this.dj, required this.enabled});

  final DjSession dj;
  final bool enabled;

  static String get labelDjAddSongsDialogTitle =>
      Intl.message("Add songs from this computer",
          name: "labelDjAddSongsDialogTitle",
          desc: "Title of the file chooser that adds audio files to the DJ "
              "booth's queue");

  static String labelDjLinkCount(int howMany) => Intl.plural(howMany,
      one: "1 link",
      other: "$howMany links",
      name: "labelDjLinkCount",
      args: [howMany],
      desc: "Under the DJ booth's box for links: how many links were pasted");

  static String labelDjNoSourceForHost(String host) =>
      Intl.message("No installed source plays links from $host",
          name: "labelDjNoSourceForHost",
          args: [host],
          desc: "Under the DJ booth's box for links: no installed source "
              "extension takes links from that site (the placeholder)");

  static String labelDjPlayedBy(String source) =>
      Intl.message("Played by $source",
          name: "labelDjPlayedBy",
          args: [source],
          desc: "Under the DJ booth's box for links: what will play the pasted "
              "link, usually the name of a source extension");

  static String get labelDjAddLocked => Intl.message(
      "Locked while the decks change hands",
      name: "labelDjAddLocked",
      desc: "Placeholder of the DJ booth's box for links while the booth is "
          "being passed to someone else");

  static String get labelDjAddHintLinks =>
      Intl.message("Paste a link or drop files",
          name: "labelDjAddHintLinks",
          desc: "Placeholder of the DJ booth's box for links, with a source "
              "extension installed");

  static String get labelDjAddHintFiles =>
      Intl.message("Drop songs here, or choose files",
          name: "labelDjAddHintFiles",
          desc: "Placeholder of the DJ booth's box for links, with no source "
              "extension installed (only audio files can be added)");

  static String get promptDjChooseFiles => Intl.message("Choose files…",
      name: "promptDjChooseFiles",
      desc: "Button in the DJ booth that picks audio files to queue");

  static String get tooltipDjPlayNext => Intl.message("Play next (Shift+Enter)",
      name: "tooltipDjPlayNext",
      desc: "Tooltip on the DJ booth's button that queues the pasted link "
          "first; Shift+Enter is its keyboard shortcut");

  static String get tooltipDjAddMusicEmpty =>
      Intl.message("Paste a link above, or pick songs from this computer",
          name: "tooltipDjAddMusicEmpty",
          desc: "Tooltip on the DJ booth's Add music button while no link is "
              "pasted: it then picks files");

  static String get tooltipDjAddToQueue => Intl.message(
      "Add to the queue (Enter)",
      name: "tooltipDjAddToQueue",
      desc: "Tooltip on the DJ booth's Add music button with a link pasted; "
          "Enter is its keyboard shortcut");

  static String get promptDjAddMusic => Intl.message("Add music",
      name: "promptDjAddMusic",
      desc: "Button in the DJ booth that queues the pasted link, or picks "
          "audio files");

  static String get promptDjAddAnotherSource => Intl.message(
      "Add another music source…",
      name: "promptDjAddAnotherSource",
      desc: "Button in the DJ booth that installs one more source extension "
          "(what lets the booth play links from a site)");

  static String get promptDjAddSource => Intl.message("Add a music source…",
      name: "promptDjAddSource",
      desc: "Button in the DJ booth that installs a source extension (what "
          "lets the booth play links from a site)");

  static String labelDjAddingLink(String link) => Intl.message("Adding $link",
      name: "labelDjAddingLink",
      args: [link],
      desc: "In the DJ booth while a pasted link (the placeholder) is looked "
          "up to be queued");

  static String labelDjAddingLinks(int howMany) => Intl.plural(howMany,
      one: "Adding 1 link…",
      other: "Adding $howMany links…",
      name: "labelDjAddingLinks",
      args: [howMany],
      desc: "In the DJ booth while pasted links are looked up to be queued");

  @override
  State<_AddBar> createState() => _AddBarState();
}

class _AddBarState extends State<_AddBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<DjLink> _links = const [];
  final ValueListenable<List<DjSourceInfo>>? _sources =
      DjPlatform.instance.sources?.installed;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final links = DjLinks.parseAll(_text.text);
      if (links.length != _links.length ||
          (links.isNotEmpty && links.first.url != _links.firstOrNull?.url)) {
        setState(() => _links = links);
      }
    });
    _sources?.addListener(_onSources);
  }

  void _onSources() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sources?.removeListener(_onSources);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasSources => _sources?.value.isNotEmpty ?? false;

  void _add({bool next = false}) {
    if (_links.isEmpty || !widget.enabled) return;
    // Kept when nothing was taken (the booth changed hands meanwhile).
    if (widget.dj.addLinks(_text.text, next: next) == 0) return;
    _text.clear();
    _focus.requestFocus();
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: _AddBar.labelDjAddSongsDialogTitle,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: DjPlatform.audioFileExtensions,
      // A browser gives the files' contents, not where they are.
      withData: kIsWeb,
    );
    if (!widget.enabled) return;
    if (kIsWeb) {
      final dj = widget.dj;
      dj.addTracks(await DjPlatform.instance.pickedTracks([
        for (final file in result?.files ?? const <PlatformFile>[])
          if (file.bytes != null) (name: file.name, bytes: file.bytes!)
      ], addedBy: dj.selfUserId, newId: dj.newTrackId));
      return;
    }
    await addDjFiles(widget.dj, [
      for (final file in result?.files ?? const <PlatformFile>[])
        if (file.path != null) file.path!
    ]);
  }

  /// The big button: adds what is pasted, or with nothing pasted opens the
  /// file chooser, so it always does something.
  void _primary() => _links.isEmpty ? _addFiles() : _add();

  String _describe(List<DjLink> links) {
    if (links.length > 1) return _AddBar.labelDjLinkCount(links.length);
    final link = links.single;
    final source = widget.dj.resolver?.sourceFor(link);
    return source == null
        ? _AddBar.labelDjNoSourceForHost(link.host)
        : _AddBar.labelDjPlayedBy(source);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = widget.dj.pendingAdds;
    final canAdd = widget.enabled && _links.isNotEmpty;
    final hint = !widget.enabled
        ? _AddBar.labelDjAddLocked
        : widget.dj.resolver?.hint ??
            (_hasSources
                ? _AddBar.labelDjAddHintLinks
                : _AddBar.labelDjAddHintFiles);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        CallbackShortcuts(
          // Enter adds, Shift+Enter plays next; Ctrl+Enter makes a new line
          // for pasting several links by hand.
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): _add,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
                _add(next: true),
          },
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 3,
            enabled: widget.enabled,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              hintText: hint,
              prefixIcon: const Icon(Icons.link_rounded, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        // Wraps rather than cutting a label off when the booth is narrow.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled ? _addFiles : null,
              icon: const Icon(Icons.audio_file_outlined, size: 18),
              label: Text(_AddBar.promptDjChooseFiles),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: _AddBar.tooltipDjPlayNext,
                icon: const Icon(Icons.low_priority_rounded, size: 20),
                onPressed: canAdd ? () => _add(next: true) : null,
              ),
              // Its label is cut short rather than running past the booth's
              // edge in a longer language.
              Flexible(
                child: Tooltip(
                  message: _links.isEmpty
                      ? _AddBar.tooltipDjAddMusicEmpty
                      : _AddBar.tooltipDjAddToQueue,
                  child: FilledButton.icon(
                    onPressed: widget.enabled ? _primary : null,
                    icon: const Icon(Icons.playlist_add_rounded, size: 20),
                    label: Text(_AddBar.promptDjAddMusic,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ]),
          ],
        ),
        if (_links.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: tiamat.Text.tiny(_describe(_links)),
          ),
        // Stays after the first install, for adding sources for other sites.
        if (_sources != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.extension_outlined, size: 16),
              label: Text(_hasSources
                  ? _AddBar.promptDjAddAnotherSource
                  : _AddBar.promptDjAddSource),
              onPressed: () => installDjSource(context),
            ),
          ),
        if (pending.isNotEmpty)
          Row(
            spacing: 8,
            children: [
              const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5)),
              const DjSourceChip(DjTrack.linkKind),
              Expanded(
                child: tiamat.Text.tiny(
                    pending.length == 1
                        ? _AddBar.labelDjAddingLink(pending.single.link.url)
                        : _AddBar.labelDjAddingLinks(pending.length),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
      ],
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.dj, required this.editable});

  final DjSession dj;
  final bool editable;

  static String get labelDjUpNext => Intl.message("Up next",
      name: "labelDjUpNext",
      desc: "Heading of the DJ booth's queue while it is empty");

  static String labelDjUpNextSongs(int howMany) => Intl.plural(howMany,
      one: "Up next · 1 song",
      other: "Up next · $howMany songs",
      name: "labelDjUpNextSongs",
      args: [howMany],
      desc: "Heading of the DJ booth's queue: how many songs it holds");

  static String labelDjUpNextSongsTime(int howMany, String time) =>
      Intl.plural(howMany,
          one: "Up next · 1 song · $time",
          other: "Up next · $howMany songs · $time",
          name: "labelDjUpNextSongsTime",
          args: [howMany, time],
          desc: "Heading of the DJ booth's queue: how many songs it holds "
              "and how long they play, like 1:02:45");

  static String get tooltipDjShuffle => Intl.message("Shuffle",
      name: "tooltipDjShuffle",
      desc: "Tooltip on the DJ's button that shuffles the queue");

  static String get tooltipDjClearQueue => Intl.message("Clear the queue",
      name: "tooltipDjClearQueue",
      desc: "Tooltip on the DJ's button that empties the queue");

  static String get labelDjClearQueueTitle => Intl.message("Clear the queue?",
      name: "labelDjClearQueueTitle",
      desc: "Title of the window asking the DJ whether to empty the queue");

  static String labelDjClearQueuePrompt(int howMany) => Intl.plural(howMany,
      one: "Removes 1 song. The one playing keeps playing.",
      other: "Removes $howMany songs. The one playing keeps playing.",
      name: "labelDjClearQueuePrompt",
      args: [howMany],
      desc: "In the window asking the DJ whether to empty the queue");

  @override
  Widget build(BuildContext context) {
    final queue = dj.queue;
    final total = queue.fold<int>(0, (sum, t) => sum + (t.durationMs ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: tiamat.Text.labelLow(queue.isEmpty
                ? labelDjUpNext
                : total > 0
                    ? labelDjUpNextSongsTime(queue.length, formatDjTime(total))
                    : labelDjUpNextSongs(queue.length)),
          ),
          if (editable && queue.length > 1)
            IconButton(
              tooltip: tooltipDjShuffle,
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              onPressed: dj.shuffle,
            ),
          if (editable && queue.isNotEmpty)
            IconButton(
              tooltip: tooltipDjClearQueue,
              icon: const Icon(Icons.clear_all_rounded, size: 20),
              onPressed: () async {
                final yes = await AdaptiveDialog.confirmation(context,
                    title: labelDjClearQueueTitle,
                    prompt: labelDjClearQueuePrompt(queue.length),
                    confirmationText: CommonStrings.promptClear,
                    cancelText: promptDjKeep,
                    dangerous: true);
                if (yes == true) dj.clearQueue();
              },
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.dj,
    required this.track,
    required this.index,
    required this.editable,
    required this.addedBy,
    super.key,
  });

  final DjSession dj;
  final DjTrack track;
  final int index;
  final bool editable;
  final Member addedBy;

  static String get promptDjPlayNow => Intl.message("Play now",
      name: "promptDjPlayNow",
      desc: "Menu entry on a song in the DJ booth's queue: plays it at once");

  static String get promptDjPlayNext => Intl.message("Play next",
      name: "promptDjPlayNext",
      desc: "Menu entry on a song in the DJ booth's queue: moves it to the "
          "top of the queue");

  static String get tooltipDjDragToReorder => Intl.message("Drag to reorder",
      name: "tooltipDjDragToReorder",
      desc: "Tooltip on the handle that moves a song within the DJ booth's "
          "queue");

  static String labelDjAddedBy(String name) => Intl.message("added by $name",
      name: "labelDjAddedBy",
      args: [name],
      desc: "Under a song in the DJ booth's queue: who queued it. Follows "
          "the artist, after a dot");

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _hover = false;

  DjTrack get track => widget.track;

  List<tiamat.ContextMenuItem> _items(BuildContext context) => [
        if (widget.editable) ...[
          tiamat.ContextMenuItem(
              text: _QueueRow.promptDjPlayNow,
              icon: Icons.play_arrow_rounded,
              onPressed: () => widget.dj.playNow(track.id)),
          if (widget.index > 0)
            tiamat.ContextMenuItem(
                text: _QueueRow.promptDjPlayNext,
                icon: Icons.low_priority_rounded,
                onPressed: () => widget.dj.playNext(track.id)),
          tiamat.ContextMenuItem(
              text: CommonStrings.promptEdit,
              icon: Icons.edit_rounded,
              onPressed: () => editDjTrack(context, widget.dj, track)),
        ],
        if (track.pageUrl case final page?)
          tiamat.ContextMenuItem(
              text: _NowPlaying.promptDjOpenSongPage,
              icon: Icons.open_in_new_rounded,
              onPressed: () =>
                  LinkUtils.open(Uri.parse(page), context: context)),
        if (widget.editable)
          tiamat.ContextMenuItem(
              text: CommonStrings.promptRemove,
              icon: Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              onPressed: () => widget.dj.remove(track.id)),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Without a mouse there is no hover: the handle is always there.
    final showHandle =
        widget.editable && (_hover || MediaQuery.sizeOf(context).touchControls);
    final number = SizedBox(
      width: 28,
      child: Center(
        child: showHandle
            ? ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: _QueueRow.tooltipDjDragToReorder,
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 18, color: scheme.outline),
                  ),
                ),
              )
            : tiamat.Text.tiny('${widget.index + 1}'),
      ),
    );

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        color: _hover ? scheme.surfaceContainerHigh : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          spacing: 10,
          children: [
            number,
            DjTrackArt(track: track, size: 40),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  tiamat.Text.label(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    spacing: 6,
                    children: [
                      DjSourceChip(track.kind),
                      Flexible(
                        child: tiamat.Text.tiny(
                          [
                            if (track.artist != null) track.artist!,
                            _QueueRow.labelDjAddedBy(
                                widget.addedBy.displayName),
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (track.durationMs != null)
              tiamat.Text.tiny(formatDjTime(track.durationMs!)),
            if (widget.editable)
              SizedBox(
                width: 32,
                // Not there while hidden: no clicking or tabbing to it.
                child: Visibility(
                  visible: _hover || MediaQuery.sizeOf(context).touchControls,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    tooltip: CommonStrings.promptRemove,
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => widget.dj.remove(track.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return AdaptiveContextMenu(items: _items(context), child: row);
  }
}

/// Lets the DJ fix a queued song: another link (resolved again) or another
/// title.
Future<void> editDjTrack(
    BuildContext context, DjSession dj, DjTrack track) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => _EditTrackDialog(track: track),
  );
  if (result == null) return;
  // A new link is looked up in the add bar's "Adding…" line, and a failure
  // arrives as a booth notice.
  dj.editTrack(track.id, link: result.$1, title: result.$2);
}

/// Owns its text fields, which outlive the pop while the dialog animates
/// out.
class _EditTrackDialog extends StatefulWidget {
  const _EditTrackDialog({required this.track});

  final DjTrack track;

  static String get labelDjEditSongTitle => Intl.message("Edit song",
      name: "labelDjEditSongTitle",
      desc: "Title of the window where the DJ changes a queued song's title "
          "or link");

  static String get labelDjSongTitleField => Intl.message("Title",
      name: "labelDjSongTitleField",
      desc: "Label of the box for a queued song's title, when the DJ edits "
          "it");

  static String get labelDjSongLinkField => Intl.message("Link",
      name: "labelDjSongLinkField",
      desc: "Label of the box for a queued song's link, when the DJ edits it");

  static String get labelDjSongLinkHelper =>
      Intl.message("Played by the music source that takes it",
          name: "labelDjSongLinkHelper",
          desc: "Under the box for a queued song's link: the source extension "
              "that takes links from that site plays it");

  @override
  State<_EditTrackDialog> createState() => _EditTrackDialogState();
}

class _EditTrackDialogState extends State<_EditTrackDialog> {
  late final TextEditingController _link =
      TextEditingController(text: widget.track.pageUrl ?? '');
  late final TextEditingController _title =
      TextEditingController(text: widget.track.title);

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_EditTrackDialog.labelDjEditSongTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            TextField(
              controller: _title,
              maxLength: DjTrack.maxText,
              decoration: InputDecoration(
                  labelText: _EditTrackDialog.labelDjSongTitleField),
            ),
            TextField(
              controller: _link,
              decoration: InputDecoration(
                  labelText: _EditTrackDialog.labelDjSongLinkField,
                  helperText: _EditTrackDialog.labelDjSongLinkHelper,
                  helperMaxLines: 3),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(CommonStrings.promptCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, (_link.text, _title.text)),
            child: Text(CommonStrings.promptSave)),
      ],
    );
  }
}

/// Compact "now playing" line for the top of the call, opening the booth.
class DjNowPlayingPill extends StatelessWidget {
  const DjNowPlayingPill(
      {required this.dj,
      required this.onTap,
      this.padding = EdgeInsets.zero,
      super.key});

  final DjSession dj;
  final VoidCallback onTap;

  /// Around the pill, only while it shows.
  final EdgeInsets padding;

  static String get labelDjPillIdle => Intl.message(
      "DJ booth · nothing playing",
      name: "labelDjPillIdle",
      desc: "Pill at the top of a call that opens the DJ booth, while someone "
          "is the DJ and nothing plays");

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dj,
      builder: (context, _) {
        final track = dj.current;
        // While someone DJs, even between songs: it is how listeners find
        // the booth.
        if (dj.isDisposed || dj.djIdentity == null || dj.isVacant) {
          return const SizedBox.shrink();
        }
        final line = track == null
            ? labelDjPillIdle
            : track.artist == null
                ? track.title
                : '${track.title} · ${track.artist}';
        return Padding(
          padding: padding,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      VinylDisc(
                          size: 22,
                          spinning: dj.isPlaying && !dj.isBuffering,
                          label: track?.thumbnail == null
                              ? null
                              : NetworkImage(track!.thumbnail!)),
                      Flexible(
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                      if (track != null && !dj.isPlaying)
                        const Icon(Icons.pause_rounded,
                            size: 16, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
