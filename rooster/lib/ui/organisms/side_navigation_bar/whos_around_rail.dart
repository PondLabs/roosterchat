// The rail under the spaces: every voice channel of every space, as a bubble
// each, the ones with people in them first, with their faces and a green
// ring; the quiet ones dimmed, to pull up a chair in. See
// docs/whos-around-rail.md.
import 'dart:async';
import 'dart:math';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/anchored_popover.dart';
import 'package:rooster/ui/atoms/live_media_indicator.dart';
import 'package:rooster/ui/atoms/room_text_button.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:rooster/ui/molecules/space_selector.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:rooster/ui/organisms/home_screen/home_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class WhosAroundRail extends StatefulWidget {
  const WhosAroundRail({
    required this.source,
    this.width = 70,
    this.filterClient,
    this.onOpen,
    this.onOpenChat,
    this.onJoin,
    super.key,
  });

  final LiveVoiceChannelsSource source;

  /// The space column's width; a bubble is as wide as a space's icon.
  final double width;

  /// Only this account's channels, when accounts are not mixed.
  final Client? filterClient;

  /// Opens the channel (its page, with the people in it and a join button).
  final void Function(Room room)? onOpen;

  /// Opens the channel's text chat.
  final void Function(Room room)? onOpenChat;

  /// Joins the call in the channel.
  final void Function(Room room)? onJoin;

  /// How many bubbles the rail shows at once, the channels with people in
  /// them first. Past that it shows one fewer and "+N" for the rest, which
  /// opens the whole list.
  static const int maxBubbles = 8;

  /// Names a bubble's tooltip lists before "and N more".
  static const int maxTooltipNames = 6;

  /// Between bubbles: their rings reach 4 px past them.
  static const double spacing = 10;

  static String get labelWhosAround => Intl.message("Who's around",
      name: "labelWhosAround",
      desc: "Title of the list of every voice channel with people in it, "
          "opened from the rail under the spaces");

  static String labelMoreLiveChannels(int howMany) => Intl.plural(howMany,
      one: "1 more channel with people in it",
      other: "$howMany more channels with people in them",
      name: "labelMoreLiveChannels",
      args: [howMany],
      desc: "Tooltip of the +N bubble under the spaces, which stands for the "
          "voice channels with people in them that the rail has no room for");

  static String labelMoreChannels(int howMany) => Intl.plural(howMany,
      one: "1 more channel",
      other: "$howMany more channels",
      name: "labelMoreChannels",
      args: [howMany],
      desc: "Tooltip of the +N bubble under the spaces, which stands for the "
          "voice channels the rail has no room for, none of them with people "
          "in it");

  static String get labelQuietPullUpAChair =>
      Intl.message("It's quiet. Pull up a chair.",
          name: "labelQuietPullUpAChair",
          desc: "Under the name of a voice channel with nobody in it, in the "
              "tooltip of its bubble under the spaces");

  static String get labelPullUpAChair => Intl.message("Pull up a chair",
      name: "labelPullUpAChair",
      desc: "Heading of the voice channels with nobody in them, in the list "
          "opened from the +N bubble under the spaces");

  static String labelPeopleInChannel(int howMany) => Intl.plural(howMany,
      one: "1 person",
      other: "$howMany people",
      name: "labelPeopleInChannel",
      args: [howMany],
      desc: "How many people are in a voice channel, in the list of channels "
          "with people in them");

  static String labelAndMoreInChannel(int howMany) =>
      Intl.message("and $howMany more",
          name: "labelAndMoreInChannel",
          args: [howMany],
          desc: "Last line of a bubble's tooltip under the spaces, for the "
              "people in the channel past the six it names");

  static String get labelOpenChannel => Intl.message("Open channel",
      name: "labelOpenChannel",
      desc: "Menu entry on a voice channel in the rail under the spaces that "
          "opens the channel's page");

  static String get labelJoinCall => Intl.message("Join call",
      name: "labelJoinCall",
      desc: "Menu entry on a voice channel in the rail under the spaces that "
          "joins its call");

  @override
  State<WhosAroundRail> createState() => _WhosAroundRailState();
}

class _WhosAroundRailState extends State<WhosAroundRail> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(WhosAroundRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) {
      _sub?.cancel();
      _listen();
    }
  }

  void _listen() {
    _sub = widget.source.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool _ours(Room room) =>
      widget.filterClient == null || room.client == widget.filterClient;

  static bool _sameRoom(Room a, Room b) =>
      identical(a, b) || (a.identifier == b.identifier && a.client == b.client);

  @override
  Widget build(BuildContext context) {
    final live = [
      for (final channel in widget.source.channels)
        if (_ours(channel.room)) channel
    ];
    final quiet = [
      for (final room in widget.source.voiceChannels)
        if (_ours(room) && !live.any((c) => _sameRoom(c.room, room))) room
    ];
    if (live.isEmpty && quiet.isEmpty) return const SizedBox.shrink();

    final size = widget.width - SpaceSelector.padding.horizontal;
    final total = live.length + quiet.length;
    final shown = total <= WhosAroundRail.maxBubbles
        ? total
        : WhosAroundRail.maxBubbles - 1;
    final hidden = total - shown;
    final liveShown = live.take(shown).toList();
    final quietShown = quiet.take(shown - liveShown.length).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const tiamat.Seperator(),
        Padding(
          padding: SpaceSelector.padding.copyWith(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: WhosAroundRail.spacing,
            children: [
              for (final channel in liveShown)
                _LiveBubble(
                  key: ValueKey("whos-around-${channel.room.client.identifier}"
                      "-${channel.room.identifier}"),
                  channel: channel,
                  size: size,
                  onOpen: widget.onOpen,
                  onOpenChat: widget.onOpenChat,
                  onJoin: widget.onJoin,
                ),
              for (final room in quietShown)
                _QuietBubble(
                  key: ValueKey("whos-around-quiet-${room.client.identifier}"
                      "-${room.identifier}"),
                  room: room,
                  space: widget.source.spaceOf(room),
                  size: size,
                  onOpen: widget.onOpen,
                  onOpenChat: widget.onOpenChat,
                  onJoin: widget.onJoin,
                ),
              if (hidden > 0)
                _MoreBubble(
                  key: const ValueKey("whos-around-more"),
                  live: live,
                  quiet: quiet,
                  hiddenCount: hidden,
                  hiddenLiveCount: live.length - liveShown.length,
                  spaceOf: widget.source.spaceOf,
                  size: size,
                  onOpen: widget.onOpen,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The right-click (long press on touch) entries of a channel's bubble.
List<tiamat.ContextMenuItem> _channelMenu(Room room,
    {required bool inCall,
    void Function(Room room)? onOpen,
    void Function(Room room)? onOpenChat,
    void Function(Room room)? onJoin}) {
  final canJoin =
      !inCall && room.getComponent<VoipRoomComponent>()?.canJoinCall == true;
  return [
    tiamat.ContextMenuItem(
        text: WhosAroundRail.labelOpenChannel,
        icon: Icons.volume_up,
        onPressed: () => onOpen?.call(room)),
    tiamat.ContextMenuItem(
        text: RoomTextButton.tooltipOpenChannelChat,
        icon: Icons.chat_bubble_rounded,
        onPressed: () => onOpenChat?.call(room)),
    if (canJoin)
      tiamat.ContextMenuItem(
          text: WhosAroundRail.labelJoinCall,
          icon: Icons.call,
          onPressed: () => onJoin?.call(room)),
  ];
}

/// A voice channel with people in it: their faces in a tile with a green
/// ring, the DJ's record and a LIVE badge when there are.
class _LiveBubble extends StatefulWidget {
  const _LiveBubble({
    required this.channel,
    required this.size,
    this.onOpen,
    this.onOpenChat,
    this.onJoin,
    super.key,
  });

  final LiveVoiceChannel channel;
  final double size;
  final void Function(Room room)? onOpen;
  final void Function(Room room)? onOpenChat;
  final void Function(Room room)? onJoin;

  @override
  State<_LiveBubble> createState() => _LiveBubbleState();
}

class _LiveBubbleState extends State<_LiveBubble> {
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
  void didUpdateWidget(_LiveBubble oldWidget) {
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
    final channel = widget.channel;
    final room = channel.room;
    final colors = Theme.of(context).colorScheme;
    final members = [
      for (final id in channel.participants) room.getMemberOrFallback(id)
    ];
    final media = channel.media;
    final dj = channel.dj;

    Widget tile = _Tile(
      size: widget.size,
      ring: true,
      pulseKey: Object.hash(channel.participants.join(","), channel.ours,
          channel.dj, channel.musicPlaying, media.length),
      semanticsLabel: room.displayName,
      onTap: () => widget.onOpen?.call(room),
      badges: [
        if (dj != null)
          Positioned(
            left: -6,
            bottom: -6,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black, blurRadius: 4)],
              ),
              child: VinylDisc(size: 18, spinning: channel.musicPlaying),
            ),
          ),
        if (media.isNotEmpty)
          Positioned(right: -8, top: -8, child: LiveMediaIndicator(media)),
      ],
      child: _Faces(
        members: members.take(4).toList(),
        total: members.length,
        size: widget.size,
        tileColor: colors.surfaceContainerHigh,
      ),
    );

    if (!MediaQuery.sizeOf(context).mobile) {
      tile = tiamat.Tooltip(
        content: _ChannelTooltip(channel: channel, members: members),
        preferredDirection: AxisDirection.right,
        child: tile,
      );
    }

    return AdaptiveContextMenu(
      items: _channelMenu(room,
          inCall: channel.ours,
          onOpen: widget.onOpen,
          onOpenChat: widget.onOpenChat,
          onJoin: widget.onJoin),
      child: tile,
    );
  }
}

/// A voice channel with nobody in it: its picture or initial, dimmed, with
/// a speaker in the corner, to pull up a chair in.
class _QuietBubble extends StatelessWidget {
  const _QuietBubble({
    required this.room,
    required this.space,
    required this.size,
    this.onOpen,
    this.onOpenChat,
    this.onJoin,
    super.key,
  });

  final Room room;
  final Space? space;
  final double size;
  final void Function(Room room)? onOpen;
  final void Function(Room room)? onOpenChat;
  final void Function(Room room)? onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dim = colors.onSurfaceVariant.withValues(alpha: 0.7);
    Widget tile = _Tile(
      size: size,
      background: colors.surfaceContainer,
      semanticsLabel: room.displayName,
      onTap: () => onOpen?.call(room),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _QuietFace(room: room, size: size, color: dim),
          Positioned(
            right: 5,
            bottom: 4,
            child: Icon(Icons.volume_up_rounded, size: 13, color: dim),
          ),
        ],
      ),
    );

    if (!MediaQuery.sizeOf(context).mobile) {
      tile = tiamat.Tooltip(
        content: _QuietTooltip(room: room, space: space),
        preferredDirection: AxisDirection.right,
        child: tile,
      );
    }

    return AdaptiveContextMenu(
      items: _channelMenu(room,
          inCall: false,
          onOpen: onOpen,
          onOpenChat: onOpenChat,
          onJoin: onJoin),
      child: tile,
    );
  }
}

/// A quiet channel's picture at half strength, or its initial.
class _QuietFace extends StatelessWidget {
  const _QuietFace(
      {required this.room, required this.size, required this.color});

  final Room room;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final image = room.avatar;
    final name = room.displayName.replaceFirst(RegExp(r"^[#@]"), "");
    final initial = name.isEmpty ? "" : name.characters.first.toUpperCase();
    final letter = Center(
      child: Text(
        initial,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: size * 0.38, fontWeight: FontWeight.w700, color: color),
      ),
    );
    if (image == null) return letter;
    return Opacity(
      opacity: 0.5,
      child: Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => letter,
      ),
    );
  }
}

/// The channel, its space and who is in it, next to a bubble under the
/// pointer.
class _ChannelTooltip extends StatelessWidget {
  const _ChannelTooltip({required this.channel, required this.members});

  final LiveVoiceChannel channel;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final space = channel.space;
    final shown = members.take(WhosAroundRail.maxTooltipNames).toList();
    final rest = members.length - shown.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          tiamat.Text.labelEmphasised(channel.room.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (space != null)
            tiamat.Text.labelLow(space.displayName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          for (final member in shown)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                _Face(member, size: 18, radius: 6),
                Flexible(
                  child: tiamat.Text.body(member.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (channel.djPlaying.containsKey(member.identifier))
                  VinylDisc(
                      size: 14,
                      spinning: channel.djPlaying[member.identifier] == true),
                if (channel.liveMedia[member.identifier]?.isNotEmpty == true)
                  LiveMediaIndicator(channel.liveMedia[member.identifier]!),
              ],
            ),
          if (rest > 0)
            tiamat.Text.labelLow(WhosAroundRail.labelAndMoreInChannel(rest),
                color: colors.secondary),
        ],
      ),
    );
  }
}

/// A quiet channel's name and space, and the invitation.
class _QuietTooltip extends StatelessWidget {
  const _QuietTooltip({required this.room, required this.space});

  final Room room;
  final Space? space;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          tiamat.Text.labelEmphasised(room.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (space != null)
            tiamat.Text.labelLow(space!.displayName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          tiamat.Text.labelLow(WhosAroundRail.labelQuietPullUpAChair,
              color: colors.secondary),
        ],
      ),
    );
  }
}

/// "+N": the channels the rail has no room for, opening the whole list:
/// who's around first, then the quiet channels to pull up a chair in.
class _MoreBubble extends StatelessWidget {
  const _MoreBubble({
    required this.live,
    required this.quiet,
    required this.hiddenCount,
    required this.hiddenLiveCount,
    required this.spaceOf,
    required this.size,
    this.onOpen,
    super.key,
  });

  final List<LiveVoiceChannel> live;
  final List<Room> quiet;
  final int hiddenCount;

  /// How many of the hidden channels have people in them: they get the ring.
  final int hiddenLiveCount;
  final Space? Function(Room room) spaceOf;
  final double size;
  final void Function(Room room)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = hiddenLiveCount > 0
        ? WhosAroundRail.labelMoreLiveChannels(hiddenLiveCount)
        : WhosAroundRail.labelMoreChannels(hiddenCount);
    return AnchoredPopover(
      alignment: PopoverAlignment.start,
      gap: 6,
      anchorBuilder: (context, open, toggle) {
        Widget tile = _Tile(
          size: size,
          ring: hiddenLiveCount > 0,
          pulseKey: hiddenLiveCount,
          background: hiddenLiveCount > 0 ? null : colors.surfaceContainer,
          semanticsLabel: label,
          onTap: toggle,
          child: Center(
            child: tiamat.Text.labelEmphasised("+$hiddenCount",
                color: colors.onSurfaceVariant),
          ),
        );
        if (!MediaQuery.sizeOf(context).mobile) {
          tile = tiamat.Tooltip(
              text: label,
              preferredDirection: AxisDirection.right,
              child: tile);
        }
        return tile;
      },
      popoverBuilder: (context, close) => _Popover(
        children: [
          if (live.isNotEmpty) _PopoverHeading(WhosAroundRail.labelWhosAround),
          for (final channel in live)
            _ChannelRow(
              channel: channel,
              onTap: () {
                close();
                onOpen?.call(channel.room);
              },
            ),
          if (quiet.isNotEmpty)
            _PopoverHeading(WhosAroundRail.labelPullUpAChair,
                first: live.isEmpty),
          for (final room in quiet)
            _QuietRow(
              room: room,
              space: spaceOf(room),
              onTap: () {
                close();
                onOpen?.call(room);
              },
            ),
        ],
      ),
    );
  }
}

/// A channel in the "Who's around" list: faces, name, space and how many.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, this.onTap});

  final LiveVoiceChannel channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final room = channel.room;
    final members = [
      for (final id in channel.participants) room.getMemberOrFallback(id)
    ];
    final people = WhosAroundRail.labelPeopleInChannel(members.length);
    final space = channel.space;
    final media = channel.media;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          spacing: 10,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ColoredBox(
                color: colors.surfaceContainerHigh,
                child: SizedBox.square(
                  dimension: 32,
                  child: _Faces(
                    members: members.take(4).toList(),
                    total: members.length,
                    size: 32,
                    tileColor: colors.surfaceContainerHigh,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.label(room.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  tiamat.Text.labelLow(
                      space == null ? people : "${space.displayName} · $people",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (channel.dj != null)
              VinylDisc(size: 16, spinning: channel.musicPlaying),
            if (media.isNotEmpty) LiveMediaIndicator(media),
          ],
        ),
      ),
    );
  }
}

/// A quiet channel in the list: its initial, name and space.
class _QuietRow extends StatelessWidget {
  const _QuietRow({required this.room, required this.space, this.onTap});

  final Room room;
  final Space? space;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          spacing: 10,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ColoredBox(
                color: colors.surfaceContainer,
                child: SizedBox.square(
                  dimension: 32,
                  child: _QuietFace(
                      room: room,
                      size: 32,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.label(room.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  tiamat.Text.labelLow(
                      space?.displayName ?? HomeScreenView.labelHomeRoomsList,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.volume_up_rounded,
                size: 16, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PopoverHeading extends StatelessWidget {
  const _PopoverHeading(this.text, {this.first = true});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, first ? 4 : 10, 10, 6),
      child: tiamat.Text.labelEmphasised(text),
    );
  }
}

/// The list a bubble opens, styled like the sidebar's "and N more".
class _Popover extends StatelessWidget {
  const _Popover({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: children,
        ),
      ),
    );
  }
}

/// A space icon's shape, with a green ring while people are in the channel.
/// The ring breathes twice when the bubble appears and whenever [pulseKey]
/// changes (someone came or went, a badge changed), then rests: a ring that
/// breathed all the time would keep the app drawing frames all day. The
/// corners round a little more under the pointer, as the space icons' do.
class _Tile extends StatefulWidget {
  const _Tile({
    required this.size,
    required this.child,
    this.ring = false,
    this.pulseKey,
    this.onTap,
    this.semanticsLabel,
    this.background,
    this.badges = const [],
  });

  final double size;
  final Widget child;
  final bool ring;

  /// What the ring breathes about: a change of it is a breath.
  final Object? pulseKey;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Color? background;

  /// Positioned over the tile, outside its clip.
  final List<Widget> badges;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with SingleTickerProviderStateMixin {
  bool hovering = false;

  /// Two breaths in and out, at rest at either end.
  late final AnimationController breath = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400), value: 1);

  bool _breathedOnArrival = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_breathedOnArrival) return;
    _breathedOnArrival = true;
    _breathe();
  }

  @override
  void didUpdateWidget(_Tile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseKey != oldWidget.pulseKey) _breathe();
  }

  void _breathe() {
    if (!widget.ring || MediaQuery.disableAnimationsOf(context)) {
      breath.value = 1;
      return;
    }
    breath.forward(from: 0);
  }

  @override
  void dispose() {
    breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = widget.size / (hovering ? 5 : 3.4);
    final tile = TweenAnimationBuilder<double>(
      tween: Tween(end: radius),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      builder: (context, radius, child) => CustomPaint(
        foregroundPainter: widget.ring
            ? _RingPainter(breath: breath, cornerRadius: radius)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: widget.background ?? colors.surfaceContainerHigh,
            child: child,
          ),
        ),
      ),
      child: SizedBox(
          width: widget.size, height: widget.size, child: widget.child),
    );

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: RepaintBoundary(
            child: Stack(
              clipBehavior: Clip.none,
              children: [tile, ...widget.badges],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.breath, required this.cornerRadius})
      : super(repaint: breath);

  final Animation<double> breath;
  final double cornerRadius;

  static const double gap = 2;
  static const double width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // Two breaths over the run, none at rest.
    final breathing = sin(breath.value * pi * 2).abs();
    final ring = RRect.fromRectAndRadius(
            Offset.zero & size, Radius.circular(cornerRadius))
        .inflate(gap + width / 2);
    canvas.drawRRect(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + breathing
          ..color = SpeakingIndicator.color
              .withValues(alpha: 0.75 + 0.25 * breathing));
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.cornerRadius != cornerRadius || oldDelegate.breath != breath;
}

/// Up to four faces in a tile: one fills it, two sit corner to corner,
/// three make a triangle, four a grid, and a fuller channel's fourth cell
/// counts the rest.
class _Faces extends StatelessWidget {
  const _Faces({
    required this.members,
    required this.total,
    required this.size,
    required this.tileColor,
  });

  final List<Member> members;
  final int total;
  final double size;
  final Color tileColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (members.length) {
      case 0:
        return const SizedBox.shrink();
      case 1:
        return _Face(members[0], size: size, radius: 0);
      case 2:
        final face = size * 0.64;
        return Stack(children: [
          Positioned(
              left: 0,
              top: 0,
              child: _Face(members[0], size: face, radius: face / 3)),
          Positioned(
              right: 0,
              bottom: 0,
              child: _Face(members[1],
                  size: face, radius: face / 3, border: tileColor)),
        ]);
      case 3:
        final face = size * 0.48;
        return Stack(children: [
          Positioned(
              left: (size - face) / 2,
              top: 0,
              child: _Face(members[0], size: face, radius: face / 3)),
          Positioned(
              left: 0,
              bottom: 0,
              child: _Face(members[1], size: face, radius: face / 3)),
          Positioned(
              right: 0,
              bottom: 0,
              child: _Face(members[2], size: face, radius: face / 3)),
        ]);
      default:
        const gap = 2.0;
        final face = (size - gap * 3) / 2;
        final radius = face / 3;
        Widget cell(int index) {
          if (index == 3 && total > 4) {
            return SizedBox(
              width: face,
              height: face,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Center(
                  child: Text(
                    "+${total - 3}",
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: face * 0.42,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: colors.onSurfaceVariant),
                  ),
                ),
              ),
            );
          }
          return _Face(members[index], size: face, radius: radius);
        }

        return Stack(children: [
          Positioned(left: gap, top: gap, child: cell(0)),
          Positioned(left: gap * 2 + face, top: gap, child: cell(1)),
          Positioned(left: gap, top: gap * 2 + face, child: cell(2)),
          Positioned(left: gap * 2 + face, top: gap * 2 + face, child: cell(3)),
        ]);
    }
  }
}

/// Someone's avatar, or their initial on their colour.
class _Face extends StatelessWidget {
  const _Face(this.member,
      {required this.size, required this.radius, this.border});

  final Member member;
  final double size;
  final double radius;

  /// Outlines the face in this colour, to lift it off a face behind it.
  final Color? border;

  @override
  Widget build(BuildContext context) {
    // A member not loaded yet is its user id: its first letter, not the @.
    final name = member.displayName.replaceFirst("@", "");
    final initial = name.isEmpty ? "" : name.characters.first.toUpperCase();
    final placeholder = ColoredBox(
      color: member.defaultColor,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontSize: size / 2, height: 1),
        ),
      ),
    );
    final image = member.avatar;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: image == null
          ? placeholder
          : Image(
              image: image,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
