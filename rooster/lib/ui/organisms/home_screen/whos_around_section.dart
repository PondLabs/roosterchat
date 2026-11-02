// The top of the Home screen's list: who is in a voice channel right now,
// in every space of every account, with a button to join them, and the
// quiet channels under it to pull up a chair in. See docs/whos-around.md.
import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/soundboard/entrance_sound.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/face_cluster.dart';
import 'package:rooster/ui/atoms/live_media_indicator.dart';
import 'package:rooster/ui/atoms/room_text_button.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:rooster/ui/organisms/home_screen/home_screen_view.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class WhosAroundSection extends StatefulWidget {
  const WhosAroundSection({
    required this.source,
    this.filterClient,
    this.onOpen,
    this.onOpenChat,
    this.onJoin,
    super.key,
  });

  final LiveVoiceChannelsSource source;

  /// Only this account's channels, when accounts are not mixed.
  final Client? filterClient;

  /// Opens the channel's page; by default through the event bus, which
  /// also opens its space.
  final void Function(Room room)? onOpen;

  /// Opens the channel's text chat.
  final void Function(Room room)? onOpenChat;

  /// Joins the call: by default a join request the channel's page takes as
  /// it opens, with the entrance sound.
  final void Function(Room room)? onJoin;

  /// Quiet channels listed before "N more channels".
  static const int maxQuiet = 5;

  static String get labelWhosAround => Intl.message("Who's around",
      name: "labelWhosAround",
      desc: "Header of the voice channels with people in them, at the top of "
          "the Home screen's list");

  static String get labelPullUpAChair => Intl.message("Pull up a chair",
      name: "labelPullUpAChair",
      desc: "Header of the voice channels with nobody in them, under who's "
          "around on the Home screen");

  static String labelPeopleInChannel(int howMany) => Intl.plural(howMany,
      one: "1 person",
      other: "$howMany people",
      name: "labelPeopleInChannel",
      args: [howMany],
      desc: "How many people are in a voice channel, under its name on the "
          "Home screen");

  static String labelMoreChannels(int howMany) => Intl.plural(howMany,
      one: "1 more channel",
      other: "$howMany more channels",
      name: "labelMoreChannels",
      args: [howMany],
      desc: "Row under the quiet voice channels on the Home screen that "
          "shows the rest of them");

  static String get labelJoinCall => Intl.message("Join call",
      name: "labelJoinCall",
      desc: "Button on a voice channel with people in it, on the Home "
          "screen, that joins its call");

  static String get labelOpenChannel => Intl.message("Open channel",
      name: "labelOpenChannel",
      desc: "Menu entry on a voice channel on the Home screen that opens the "
          "channel's page");

  static String get labelYouAreInHere => Intl.message("You're in here",
      name: "labelYouAreInHere",
      desc: "On the Home screen, next to the voice channel whose call we are "
          "in, where the join button would be");

  static void open(Room room) =>
      EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);

  static void openChat(Room room) => EventBus.doOpenRoom(room.identifier,
      clientId: room.client.identifier, bypassSpecialRoomType: true);

  /// Opens the channel and has its page join the call, the way "Join
  /// Without Entrance Sound" does, with the sound.
  static void join(Room room) {
    EntranceSoundGate.instance.requestJoin(room.identifier);
    open(room);
  }

  @override
  State<WhosAroundSection> createState() => _WhosAroundSectionState();
}

class _WhosAroundSectionState extends State<WhosAroundSection> {
  final List<StreamSubscription> _subs = [];
  bool _showAllQuiet = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _subs.add(preferences.showWhosAround.onChanged.listen((_) {
      if (mounted) setState(() {});
    }));
  }

  StreamSubscription? _sourceSub;

  void _listen() {
    _sourceSub?.cancel();
    _sourceSub = widget.source.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(WhosAroundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) _listen();
  }

  @override
  void dispose() {
    _sourceSub?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  bool _ours(Room room) =>
      widget.filterClient == null || room.client == widget.filterClient;

  static bool _sameRoom(Room a, Room b) =>
      identical(a, b) || (a.identifier == b.identifier && a.client == b.client);

  @override
  Widget build(BuildContext context) {
    if (!preferences.showWhosAround.value) return const SizedBox.shrink();
    final live = [
      for (final channel in widget.source.channels)
        if (_ours(channel.room)) channel
    ];
    final quiet = [
      for (final room in widget.source.voiceChannels)
        if (_ours(room) && !live.any((c) => _sameRoom(c.room, room))) room
    ];
    if (live.isEmpty && quiet.isEmpty) return const SizedBox.shrink();

    final quietShown =
        _showAllQuiet ? quiet : quiet.take(WhosAroundSection.maxQuiet).toList();
    final hiddenQuiet = quiet.length - quietShown.length;
    const rowPadding = EdgeInsets.fromLTRB(3, 4, 0, 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live.isNotEmpty) ...[
          _Heading(WhosAroundSection.labelWhosAround),
          for (final channel in live)
            Padding(
              padding: rowPadding,
              child: _LiveRow(
                key: ValueKey("whos-around-${channel.room.client.identifier}"
                    "-${channel.room.identifier}"),
                channel: channel,
                onOpen: widget.onOpen ?? WhosAroundSection.open,
                onOpenChat: widget.onOpenChat ?? WhosAroundSection.openChat,
                onJoin: widget.onJoin ?? WhosAroundSection.join,
              ),
            ),
        ],
        if (quiet.isNotEmpty) ...[
          _Heading(WhosAroundSection.labelPullUpAChair),
          for (final room in quietShown)
            Padding(
              padding: rowPadding,
              child: _QuietRow(
                key: ValueKey("whos-around-quiet-${room.client.identifier}"
                    "-${room.identifier}"),
                room: room,
                space: widget.source.spaceOf(room),
                onOpen: widget.onOpen ?? WhosAroundSection.open,
                onOpenChat: widget.onOpenChat ?? WhosAroundSection.openChat,
                onJoin: widget.onJoin ?? WhosAroundSection.join,
              ),
            ),
          if (hiddenQuiet > 0)
            Padding(
              padding: rowPadding,
              child: _MoreRow(
                key: const ValueKey("whos-around-more"),
                label: WhosAroundSection.labelMoreChannels(hiddenQuiet),
                onTap: () => setState(() => _showAllQuiet = true),
              ),
            ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: tiamat.Text.labelLow(text),
    );
  }
}

/// The right-click (long press on touch) entries of a channel's row.
List<tiamat.ContextMenuItem> _channelMenu(Room room,
    {required bool inCall,
    required void Function(Room room) onOpen,
    required void Function(Room room) onOpenChat,
    required void Function(Room room) onJoin}) {
  final canJoin =
      !inCall && room.getComponent<VoipRoomComponent>()?.canJoinCall == true;
  return [
    tiamat.ContextMenuItem(
        text: WhosAroundSection.labelOpenChannel,
        icon: Icons.volume_up,
        onPressed: () => onOpen(room)),
    tiamat.ContextMenuItem(
        text: RoomTextButton.tooltipOpenChannelChat,
        icon: Icons.chat_bubble_rounded,
        onPressed: () => onOpenChat(room)),
    if (canJoin)
      tiamat.ContextMenuItem(
          text: WhosAroundSection.labelJoinCall,
          icon: Icons.call,
          onPressed: () => onJoin(room)),
  ];
}

/// A row of the list, shaped like the rooms' rows beside it.
class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A voice channel with people in it: their faces, the channel, its space
/// and how many, the DJ's record and LIVE when there are, and the button
/// that joins them.
class _LiveRow extends StatefulWidget {
  const _LiveRow({
    required this.channel,
    required this.onOpen,
    required this.onOpenChat,
    required this.onJoin,
    super.key,
  });

  final LiveVoiceChannel channel;
  final void Function(Room room) onOpen;
  final void Function(Room room) onOpenChat;
  final void Function(Room room) onJoin;

  @override
  State<_LiveRow> createState() => _LiveRowState();
}

class _LiveRowState extends State<_LiveRow> {
  /// Who has had their member asked for, once each (see
  /// RoomTextButton.fetchNewMembers): a member the homeserver lazy loads is
  /// only its user id until then.
  final Set<String> fetched = {};

  @override
  void initState() {
    super.initState();
    fetchNewMembers();
  }

  @override
  void didUpdateWidget(_LiveRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    fetchNewMembers();
  }

  void fetchNewMembers() {
    for (final participant in widget.channel.participants) {
      if (!fetched.add(participant)) continue;
      widget.channel.room.fetchMember(participant).then((_) {
        if (mounted) setState(() {});
      }, onError: (Object e, StackTrace s) {
        Log.onError(e, s, content: "Could not fetch $participant");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final channel = widget.channel;
    final room = channel.room;
    final members = [
      for (final id in channel.participants) room.getMemberOrFallback(id)
    ];
    final space = channel.space;
    final people = WhosAroundSection.labelPeopleInChannel(members.length);
    final media = channel.media;
    final canJoin = !channel.ours &&
        room.getComponent<VoipRoomComponent>()?.canJoinCall == true;

    return AdaptiveContextMenu(
      items: _channelMenu(room,
          inCall: channel.ours,
          onOpen: widget.onOpen,
          onOpenChat: widget.onOpenChat,
          onJoin: widget.onJoin),
      child: _Row(
        onTap: () => widget.onOpen(room),
        child: LayoutBuilder(builder: (context, constraints) {
          // The sidebar can be as narrow as 200: the chip keeps its icon
          // only, so the channel's name keeps its room.
          final compact = constraints.maxWidth < 250;
          return Row(
            spacing: 8,
            children: [
              FaceCluster(members: members, total: members.length, size: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, line) => Row(
                        spacing: 6,
                        children: [
                          Flexible(
                            child: tiamat.Text.name(room.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (channel.dj != null)
                            VinylDisc(size: 14, spinning: channel.musicPlaying),
                          // Shrinks rather than overflows when a longer
                          // language's LIVE meets a narrow sidebar.
                          if (media.isNotEmpty)
                            ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: line.maxWidth / 2),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: LiveMediaIndicator(media),
                              ),
                            ),
                        ],
                      ),
                    ),
                    tiamat.Text.labelLow(
                        space == null
                            ? people
                            : "${space.displayName} · $people",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // At most 40% of the row, so a longer language's label is cut
              // short (the tooltip has it whole) instead of the row.
              if (channel.ours || canJoin)
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                  child: channel.ours
                      ? _Chip(
                          WhosAroundSection.labelYouAreInHere,
                          icon: Icons.headset_mic_rounded,
                          background: colors.surfaceContainerHighest,
                          foreground: colors.onSurfaceVariant,
                          compact: compact,
                        )
                      : _Chip(
                          WhosAroundSection.labelJoinCall,
                          icon: Icons.call_rounded,
                          background: colors.primary,
                          foreground: colors.onPrimary,
                          compact: compact,
                          onTap: () => widget.onJoin(room),
                        ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// A voice channel with nobody in it: its picture at half strength or its
/// initial, the channel and its space.
class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.room,
    required this.space,
    required this.onOpen,
    required this.onOpenChat,
    required this.onJoin,
    super.key,
  });

  final Room room;
  final Space? space;
  final void Function(Room room) onOpen;
  final void Function(Room room) onOpenChat;
  final void Function(Room room) onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dim = colors.onSurfaceVariant.withValues(alpha: 0.7);
    final image = room.avatar;
    final name = room.displayName.replaceFirst(RegExp(r"^[#@]"), "");
    final initial = name.isEmpty ? "" : name.characters.first.toUpperCase();
    final letter = Center(
      child: Text(
        initial,
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: dim),
      ),
    );

    return AdaptiveContextMenu(
      items: _channelMenu(room,
          inCall: false,
          onOpen: onOpen,
          onOpenChat: onOpenChat,
          onJoin: onJoin),
      child: _Row(
        onTap: () => onOpen(room),
        child: Row(
          spacing: 8,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40 / 3.4),
              child: ColoredBox(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                child: SizedBox.square(
                  dimension: 40,
                  child: image == null
                      ? letter
                      : Opacity(
                          opacity: 0.5,
                          child: Image(
                              image: image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => letter),
                        ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.name(room.displayName,
                      color: colors.onSurfaceVariant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  tiamat.Text.labelLow(
                      space?.displayName ?? HomeScreenView.labelHomeRoomsList,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.volume_up_rounded, size: 16, color: dim),
          ],
        ),
      ),
    );
  }
}

/// "N more channels": the quiet channels past the first five.
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Row(
      onTap: onTap,
      child: Row(
        spacing: 8,
        children: [
          SizedBox.square(
            dimension: 40,
            child: Center(
              child: Icon(Icons.expand_more, size: 18, color: colors.secondary),
            ),
          ),
          Expanded(child: tiamat.Text.labelLow(label, color: colors.secondary)),
        ],
      ),
    );
  }
}

/// A small pill: the join button, or "You're in here". Its icon alone when
/// [compact], with the text as its tooltip.
class _Chip extends StatelessWidget {
  const _Chip(this.text,
      {required this.icon,
      required this.background,
      required this.foreground,
      this.compact = false,
      this.onTap});

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: compact
              ? const EdgeInsets.all(7)
              : const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(icon, size: 14, color: foreground),
              if (!compact)
                Flexible(
                  child: tiamat.Text.tiny(text,
                      color: foreground,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
    // Compact, or cut short, the label is in the tooltip.
    return Tooltip(message: text, child: chip);
  }
}
