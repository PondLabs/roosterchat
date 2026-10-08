import 'dart:async';

import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/calendar_room/calendar_room_component.dart';
import 'package:rooster/client/components/soundboard/entrance_sound.dart';
import 'package:rooster/client/components/voice_channel_status/voice_channel_status_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/client/matrix/components/dj/dj_booths.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/space.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/live_media_indicator.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:rooster/ui/atoms/voice_state_indicator.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/anchored_popover.dart';
import 'package:rooster/ui/atoms/dot_indicator.dart';
import 'package:rooster/ui/atoms/notification_badge.dart';
import 'package:rooster/ui/atoms/tiny_pill.dart';
import 'package:rooster/ui/molecules/show_on_hover.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/navigation/adaptive_text_dialog.dart';
import 'package:rooster/ui/navigation/navigation_utils.dart';
import 'package:rooster/ui/organisms/channel_categories/channel_category_actions.dart';
import 'package:rooster/ui/organisms/channel_invites/channel_invites.dart';
import 'package:rooster/ui/organisms/dj/dj_booth_panel.dart';
import 'package:rooster/ui/organisms/dj/dj_member_ui.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:rooster/ui/pages/settings/room_settings_page.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/text_utils.dart';
import 'package:rooster_calendar_widget/calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTextButton extends StatefulWidget {
  const RoomTextButton(
    this.room, {
    this.highlight = false,
    this.onTap,
    this.space,
    super.key,
  });

  /// Our live call in [room], from the call manager's own list. Not from
  /// VoipRoomComponent.currentSession: a session registers itself with the
  /// call manager while it is being made, before the component gets it back
  /// from the join, so on that list update the component still said none,
  /// and nothing came after it to look again. The row then never lit up.
  static VoipSession? callSessionIn(Room room, Iterable<VoipSession> sessions) {
    for (final session in sessions) {
      if (session.roomId == room.identifier &&
          session.client == room.client &&
          session.state != VoipState.ended) {
        return session;
      }
    }
    return null;
  }

  /// How many rows of members a voice channel shows under it. A fuller
  /// channel shows one fewer, and "and N more" on the last row opens the
  /// rest: a busy channel used to push every room below it off the screen.
  static const maxVisibleMembers = 8;

  final bool highlight;
  final Room room;
  final Function(Room room, {bool bypassSpecialRoomType})? onTap;

  /// The space whose sidebar lists the room, if any: its people can be
  /// invited, and its admins put the room under another heading.
  final Space? space;

  @override
  State<RoomTextButton> createState() => _RoomTextButtonState();

  static String get tooltipOpenChannelChat => Intl.message("Open chat",
      name: "tooltipOpenChannelChat",
      desc: "Button on a voice channel in the sidebar that opens its text "
          "chat rather than the call");

  static String get tooltipEditChannel => Intl.message("Edit channel",
      name: "tooltipEditChannel",
      desc: "Button on a channel in the sidebar that opens its settings");

  static String get labelSetVoiceChannelStatus =>
      Intl.message("Set a channel status",
          name: "labelSetVoiceChannelStatus",
          desc: "Under the name of a voice channel we are in, while it has no "
              "status; opens the field to set one");

  static String get labelVoiceChannelStatus => Intl.message("Channel status",
      name: "labelVoiceChannelStatus",
      desc: "Title of the dialog setting what a voice channel is up to");

  static String get labelVoiceChannelStatusDescription => Intl.message(
      "Everyone sees it under the channel's name. Leave it empty to clear it.",
      name: "labelVoiceChannelStatusDescription",
      desc: "Explains the status of a voice channel, in the dialog setting it");

  static String get labelVoiceChannelStatusPlaceholder =>
      Intl.message("What's going on in here?",
          name: "labelVoiceChannelStatusPlaceholder",
          desc: "Placeholder of the field setting a voice channel's status");

  static String get promptHideInviteToVoice => Intl.message("Hide",
      name: "promptHideInviteToVoice",
      desc: "Button closing the invite to voice row under a voice channel");

  /// Asks for [status]'s new text and sets it.
  static Future<void> editVoiceChannelStatus(
      BuildContext context, VoiceChannelStatusComponent status) async {
    final text = await AdaptiveTextDialog.show(context,
        title: labelVoiceChannelStatus,
        description: labelVoiceChannelStatusDescription,
        placeholder: labelVoiceChannelStatusPlaceholder,
        defaultText: status.status);
    if (text == null) return;
    try {
      await status.setStatus(text);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not set the voice channel status");
      if (context.mounted) {
        AdaptiveDialog.showError(context, e, s, title: labelVoiceChannelStatus);
      }
    }
  }

  static List<ContextMenuItem> createRoomContextMenuItems(
      BuildContext context, Room room,
      {Space? space}) {
    var voipRoom = room.getComponent<VoipRoomComponent>();
    final status = room.getComponent<VoiceChannelStatusComponent>();
    final inCall = callSessionIn(
            room, clientManager?.callManager.currentSessions ?? const []) !=
        null;
    return [
      ContextMenuItem(
          text: "Mark as Read",
          icon: Icons.visibility,
          onPressed: () => room.markAsRead()),
      if (!room.isFavorite)
        ContextMenuItem(
            text: "Set as Favorite",
            icon: Icons.favorite,
            onPressed: () => room.setAsFavorite(true)),
      if (room.isFavorite)
        ContextMenuItem(
            text: "Unfavorite",
            icon: Icons.heart_broken_outlined,
            onPressed: () => room.setAsFavorite(false)),
      if (room.isSpecialRoomType)
        ContextMenuItem(
            text: "Open as Text Chat",
            icon: Icons.tag,
            onPressed: () => EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier, bypassSpecialRoomType: true)),
      if (room.permissions.canInviteUser)
        ContextMenuItem(
            text: ChannelInvites.promptInvitePeople,
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () =>
                ChannelInvites.inviteToChannel(context, room, space: space)),
      if (inCall)
        ContextMenuItem(
            text: ChannelInvites.labelInviteToVoice,
            icon: Icons.group_add_outlined,
            onPressed: () => ChannelInvites.showVoiceInviteDialog(context, room,
                space: space)),
      if (inCall && status != null && status.canSetStatus)
        ContextMenuItem(
            text: labelSetVoiceChannelStatus,
            icon: Icons.edit_outlined,
            onPressed: () => editVoiceChannelStatus(context, status)),
      if (space != null && ChannelCategoryActions.canEdit(space))
        ContextMenuItem(
            text: ChannelCategoryActions.promptMoveToCategory,
            icon: Icons.drive_file_move_outline,
            onPressed: () =>
                ChannelCategoryActions.moveChannel(context, space, room)),
      if (voipRoom != null &&
          voipRoom.canJoinCall &&
          voipRoom.currentSession == null &&
          preferences.soundboardEntranceSoundId.value != null)
        ContextMenuItem(
            text: "Join Without Entrance Sound",
            icon: Icons.volume_off,
            onPressed: () {
              EntranceSoundGate.instance.requestSilentJoin(room.identifier);
              EventBus.doOpenRoom(room.identifier,
                  clientId: room.client.identifier);
            }),
      if (voipRoom != null && preferences.developerMode.value)
        ContextMenuItem(
          text: "Clear Membership Status",
          icon: Icons.call_end,
          onPressed: () => voipRoom.clearAllCallMembershipStatus(),
        ),
      ContextMenuItem(
          text: "Settings",
          icon: Icons.settings,
          onPressed: () {
            NavigationUtils.navigateTo(
                context,
                RoomSettingsPage(
                  room: room,
                  contextSpace: space,
                ));
          }),
    ];
  }
}

class _RoomTextButtonState extends State<RoomTextButton> {
  String get labelDjPlaying => Intl.message("DJing",
      name: "labelDjPlaying",
      desc: "Tooltip on the record next to someone in a voice channel who "
          "is the DJ and has music playing");

  String get labelDjPaused => Intl.message("DJing, paused",
      name: "labelDjPaused",
      desc: "Tooltip on the record next to someone in a voice channel who "
          "is the DJ with their music paused");

  static String labelMoreMembers(int count) => Intl.message("and $count more",
      name: "labelMoreMembers",
      args: [count],
      desc: "Last row under a voice channel with more people in it than the "
          "list shows; opens the rest of them");

  late List<StreamSubscription> subs;
  CalendarRoom? calendarRoom;
  ActivitiesComponent? activities;
  List<RoomActivitySession>? activitySessions;
  List<MatrixCalendarEventState>? calendarEvents;

  /// Our call in this room, while we are in it. Only then do we hear the
  /// members, so only then can the list show who is speaking.
  VoipSession? voiceSession;
  StreamSubscription? voiceLevelSub;
  Set<String> speakingMembers = const {};

  /// Who in the list has had their member asked for, once each.
  final Set<String> fetchedMembers = {};

  /// What the voice channel is up to, under its name.
  VoiceChannelStatusComponent? statusComponent;

  /// The pointer is over the channel's own row (not the people under it):
  /// its buttons show.
  bool hovering = false;

  /// Calls whose "Invite to voice" row was closed. Per call, so the next
  /// one offers it again.
  static final Expando<bool> inviteRowHidden = Expando();

  @override
  void initState() {
    calendarRoom = widget.room.getComponent<CalendarRoom>();
    activities = widget.room.getComponent<ActivitiesComponent>();
    statusComponent = widget.room.getComponent<VoiceChannelStatusComponent>();
    final isVoiceRoom = widget.room.getComponent<VoipRoomComponent>() != null;

    subs = [
      widget.room.onUpdate.listen(onRoomUpdate),
      if (calendarRoom != null)
        calendarRoom!.onEventsChanged.listen(onCalendarEventsChanged),
      if (activities != null)
        activities!.onSessionsChanged.listen(onSessionsChanged),
      if (isVoiceRoom && clientManager != null)
        clientManager!.callManager.currentSessions.onListUpdated.listen((_) {
          final before = voiceSession;
          attachVoiceSession();
          // In the call or out of it: the status prompt and the invite
          // row come and go with it, speaking or not.
          if (!identical(before, voiceSession) && mounted) setState(() {});
        }),
      if (statusComponent != null)
        statusComponent!.onChanged.listen((_) {
          if (mounted) setState(() {});
        }),
      if (isVoiceRoom)
        DjBooths.onChanged.listen((_) {
          if (mounted) setState(() {});
        }),
    ];

    if (isVoiceRoom) attachVoiceSession();

    if (activities != null) {
      activitySessions = activities?.getSessions();
      sortActivities();
    }

    if (calendarRoom?.calendar != null) {
      onCalendarEventsChanged(());
    }

    fetchNewMembers();

    super.initState();
  }

  void onSessionsChanged(void event) {
    setState(() {
      activitySessions = activities?.getSessions();
      sortActivities();
    });
    fetchNewMembers();
  }

  /// Asks for the member of everyone listed for the first time, for their
  /// name and avatar. Not only of who was there when the row was built:
  /// people also turn up later, some of them in the call for hours (a sync
  /// putting the time right after the app starts), and were shown as their
  /// user id.
  void fetchNewMembers() {
    for (final activity in activitySessions ?? const <RoomActivitySession>[]) {
      for (final participant in activity.participants) {
        if (!fetchedMembers.add(participant)) continue;
        widget.room.fetchMember(participant).then((_) {
          if (mounted) setState(() {});
        }, onError: (Object e, StackTrace s) {
          Log.onError(e, s, content: "Could not fetch $participant");
        });
      }
    }
  }

  void sortActivities() {
    activitySessions?.sort(
        (a, b) => (a.thirdparty ? 1 : 0).compareTo(b.thirdparty ? 1 : 0));
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    voiceLevelSub?.cancel();
    super.dispose();
  }

  void attachVoiceSession() {
    final session = RoomTextButton.callSessionIn(
        widget.room, clientManager?.callManager.currentSessions ?? const []);
    if (identical(session, voiceSession)) return;

    voiceLevelSub?.cancel();
    voiceSession = session;
    voiceLevelSub =
        session?.onUpdateVolumeVisualizers.listen((_) => updateSpeaking());
    updateSpeaking();
  }

  /// Everyone whose voice is coming through right now, ourselves included.
  /// Screen share audio is not someone talking.
  void updateSpeaking() {
    final session = voiceSession;
    final speaking = session == null
        ? const <String>{}
        : session.streams
            .where((stream) =>
                stream.type != VoipStreamType.screenshare &&
                stream.type != VoipStreamType.screenshareAudio &&
                stream.type != VoipStreamType.music &&
                stream.audiolevel > 0.5)
            .map((stream) => stream.streamUserId)
            .toSet();

    if (setEquals(speaking, speakingMembers)) return;
    if (!mounted) return;
    setState(() => speakingMembers = speaking);
  }

  void onCalendarEventsChanged(void event) {
    setState(() {
      calendarEvents = calendarRoom!
          .getEventsOnDay(DateTime.now())
          .where((i) => i.isUnavailability == false)
          .toList();
    });
  }

  void onRoomUpdate(void event) {
    setState(() {});
  }

  static const double height = 37;

  @override
  Widget build(BuildContext context) {
    IconData defaultIcon = widget.room.icon;

    var color = Theme.of(context).colorScheme.secondary;

    if (widget.room.notificationCount > 0 ||
        widget.room.highlightedNotificationCount > 0 ||
        widget.highlight) {
      color = Theme.of(context).colorScheme.onSurface;
    }

    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon = (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);

    String displayName = widget.room.displayName;

    Color? avatarPlaceholderColor =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.defaultColor
            : null;

    String? avatarPlaceholderText =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.displayName
            : null;

    bool startsWithEmoji =
        TextUtils.isEmoji(widget.room.displayName.characters.first);

    if (startsWithEmoji && widget.room.avatar == null) {
      shouldShowDefaultIcon = false;
      var emoji = displayName.characters.first;
      displayName = displayName.characters.skip(1).string.trim();
      avatarPlaceholderColor = Colors.transparent;
      avatarPlaceholderText = emoji;
    }
    Widget Function(Widget header, BuildContext context)? body;

    if (calendarEvents?.isNotEmpty == true) {
      body = buildEvents;
    }

    if (activitySessions?.isNotEmpty == true) {
      body = buildActivities;
    }

    final statusLine = buildStatusLine();

    // The channel's own row, under which the rest hangs.
    Widget Function(Widget child, BuildContext context)? customBuilder;
    if (body != null || statusLine != null) {
      customBuilder = (child, context) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hoverable(SizedBox(height: height, child: child)),
            if (statusLine != null) statusLine,
          ],
        );
        return body == null ? header : body(header, context);
      };
    }

    final badge = widget.room.displayHighlightedNotificationCount > 0
        ? NotificationBadge(widget.room.displayHighlightedNotificationCount)
        : widget.room.displayNotificationCount > 0
            ? const Padding(padding: EdgeInsets.all(2.0), child: DotIndicator())
            : null;
    final showActions = (hovering || widget.highlight) &&
        !ShowOnHover.useTouchControls(context);

    Widget result = SizedBox(
      height: customBuilder == null ? height : null,
      child: tiamat.TextButton(
        displayName,
        customBuilder: customBuilder,
        highlighted: widget.highlight,
        icon: shouldShowDefaultIcon ? defaultIcon : null,
        avatar: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        avatarRadius: 12,
        avatarPlaceholderColor: avatarPlaceholderColor,
        avatarPlaceholderText: avatarPlaceholderText,
        iconColor: color,
        textColor: color,
        softwrap: false,
        onTap: () => widget.onTap?.call(widget.room),
        footer: (showActions ? buildRowActions() : null) ?? badge,
      ),
    );

    if (customBuilder == null) result = hoverable(result);

    result = AdaptiveContextMenu(
      items: RoomTextButton.createRoomContextMenuItems(context, widget.room,
          space: widget.space),
      child: result,
    );

    return result;
  }

  Widget hoverable(Widget child) => MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: child,
      );

  /// The buttons at the end of the channel's row, under the pointer or
  /// while it is open: its chat (a voice channel's), invite, settings.
  Widget? buildRowActions() {
    final room = widget.room;
    final onTap = widget.onTap;
    final actions = [
      if (room.isSpecialRoomType && onTap != null)
        buildRowAction(
            Icons.chat_bubble_rounded,
            RoomTextButton.tooltipOpenChannelChat,
            () => onTap(room, bypassSpecialRoomType: true)),
      if (room.permissions.canInviteUser)
        buildRowAction(
            Icons.person_add_alt_1_rounded,
            ChannelInvites.promptInvitePeople,
            () => ChannelInvites.inviteToChannel(context, room,
                space: widget.space)),
      if (room.permissions.canEditAnything)
        buildRowAction(
            Icons.settings_rounded,
            RoomTextButton.tooltipEditChannel,
            () => NavigationUtils.navigateTo(context,
                RoomSettingsPage(room: room, contextSpace: widget.space))),
    ];
    if (actions.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  Widget buildRowAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// The voice channel's status under its name, or, in the call and
  /// allowed to, the prompt to set one.
  Widget? buildStatusLine() {
    final component = statusComponent;
    if (component == null) return null;
    final status = component.status;
    final canEdit = voiceSession != null && component.canSetStatus;
    if (status == null && !canEdit) return null;

    final color = Theme.of(context).colorScheme.secondary;
    Widget line = Padding(
      // Under the channel's name, past its icon.
      padding: const EdgeInsets.fromLTRB(42, 0, 8, 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              status ?? RoomTextButton.labelSetVoiceChannelStatus,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
              child: Icon(Icons.edit_rounded, size: 12, color: color),
            ),
        ],
      ),
    );

    if (canEdit) {
      line = InkWell(
        onTap: () => RoomTextButton.editVoiceChannelStatus(context, component),
        borderRadius: BorderRadius.circular(4),
        child: line,
      );
    }
    return line;
  }

  /// Under the people in our call: a row listing who else to call over.
  Widget buildInviteToVoice() {
    final session = voiceSession;
    if (session == null || inviteRowHidden[session] == true) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;

    return AnchoredPopover(
      key: const ValueKey("inviteToVoice"),
      alignment: PopoverAlignment.start,
      gap: 4,
      anchorBuilder: (context, open, toggle) => SizedBox(
        height: height,
        child: tiamat.TextButton(
          ChannelInvites.labelInviteToVoice,
          textColor: colors.secondary,
          highlighted: open,
          avatarPlaceholderText: "+",
          avatarBuilder: (_) => DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              // An avatar's corners, as the people above have.
              borderRadius: BorderRadius.circular(12 / 1.25),
            ),
            child: Center(
              child: Icon(Icons.person_add_alt_1_rounded,
                  size: 14, color: colors.onSurfaceVariant),
            ),
          ),
          footer: Tooltip(
            message: RoomTextButton.promptHideInviteToVoice,
            child: InkWell(
              onTap: () => setState(() => inviteRowHidden[session] = true),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close_rounded,
                    size: 16, color: colors.secondary),
              ),
            ),
          ),
          onTap: toggle,
        ),
      ),
      popoverBuilder: (context, close) => Material(
        color: colors.surfaceContainer,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 340),
          child: VoiceInviteList(
            room: widget.room,
            space: widget.space,
            limit: 5,
            onSeeMore: () {
              close();
              ChannelInvites.showVoiceInviteDialog(this.context, widget.room,
                  space: widget.space);
            },
          ),
        ),
      ),
    );
  }

  Widget buildActivities(Widget header, BuildContext context) {
    Iterable<RoomActivitySession> sessions = activitySessions!;

    if (activitySessions!.any((i) => i.thirdparty == false)) {
      sessions = activitySessions!.where((i) => i.thirdparty == false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var activity in sessions)
                buildActivity(
                  activity,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildActivity(RoomActivitySession activity) {
    return AdaptiveContextMenu(
      items: [
        tiamat.ContextMenuItem(
          text: "Clear Memberships",
          onPressed: () {
            activities!.clearMemberships(activity);
          },
        ),
      ],
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: ColorScheme.of(context).surfaceTint.withAlpha(10),
            borderRadius: BorderRadius.circular(8)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: activity.associatedWidget == null
                ? null
                : () => onWidgetTapped(activity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activity.thirdparty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                    child: Row(
                      spacing: 8,
                      children: [
                        SizedBox(
                            height: 20,
                            width: 20,
                            child: activity.icon.build(context)),
                        tiamat.Text.labelLow(activity.name),
                      ],
                    ),
                  ),
                if (activity.thirdparty)
                  tiamat.Seperator(
                    padding: 2,
                  ),
                ...buildCallMembers(activity),
                if (!activity.thirdparty) buildDj(),
                if (!activity.thirdparty) buildInviteToVoice(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The members of [activity] in the order they are listed. One that fits
  /// keeps the order it always had. Past [RoomTextButton.maxVisibleMembers]
  /// only the first ones show, so ourselves and whoever is live come first;
  /// nobody else moves.
  List<String> orderedMembers(RoomActivitySession activity) {
    final members = activity.participants.toList();
    if (members.length <= RoomTextButton.maxVisibleMembers) return members;

    final self = widget.room.client.self?.identifier;
    int rank(String id) {
      if (id == self) return 0;
      final media = activity.liveMedia[id] ?? const <LiveMedia>{};
      if (media.contains(LiveMedia.screen)) return 1;
      if (media.contains(LiveMedia.camera)) return 2;
      return 3;
    }

    final position = {for (final (i, id) in members.indexed) id: i};
    members.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : position[a]!.compareTo(position[b]!);
    });
    return members;
  }

  /// Everyone in [activity], one row each, with the rows past
  /// [RoomTextButton.maxVisibleMembers] behind "and N more".
  List<Widget> buildCallMembers(RoomActivitySession activity) {
    Widget row(String participant) => buildCallMember(participant,
        showActivityIcons: activity.thirdparty == false,
        liveMedia: activity.liveMedia[participant] ?? const {},
        voiceState: activity.voiceState[participant] ?? const {},
        djPlaying: activity.djPlaying[participant]);

    final members = orderedMembers(activity);
    if (members.length <= RoomTextButton.maxVisibleMembers) {
      return [for (final member in members) row(member)];
    }

    // The last row is "and N more", so it never stands for one person.
    final shown = RoomTextButton.maxVisibleMembers - 1;
    return [
      for (final member in members.take(shown)) row(member),
      buildMoreMembers(activity, members.skip(shown).toList(), row),
    ];
  }

  /// The row that stands for [hidden], and the list of them it opens.
  Widget buildMoreMembers(RoomActivitySession activity, List<String> hidden,
      Widget Function(String participant) row) {
    final colors = Theme.of(context).colorScheme;
    // Someone talking behind it still shows: the row takes their ring.
    final speaking =
        !activity.thirdparty && hidden.any(speakingMembers.contains);

    return AnchoredPopover(
      // One per activity: a row that moves must keep its open list.
      key: ValueKey("moreMembers_${activity.application}"),
      alignment: PopoverAlignment.start,
      gap: 4,
      anchorBuilder: (context, open, toggle) => SizedBox(
        height: height,
        child: tiamat.TextButton(
          labelMoreMembers(hidden.length),
          textColor: colors.secondary,
          highlighted: open,
          avatarPlaceholderText: "+",
          avatarBuilder: (_) => SpeakingIndicator(
            speaking: speaking,
            radius: 12,
            ringGap: 1.5,
            ringWidth: 2,
            waveTravel: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                // An avatar's corners, for the ring to follow.
                borderRadius: BorderRadius.circular(12 / 1.25),
              ),
              child: Center(
                child: Icon(Icons.more_horiz,
                    size: 16, color: colors.onSurfaceVariant),
              ),
            ),
          ),
          footer: Icon(open ? Icons.expand_less : Icons.expand_more,
              size: 18, color: colors.secondary),
          onTap: toggle,
        ),
      ),
      popoverBuilder: (context, close) => Material(
        color: colors.surfaceContainer,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          // Wide enough for a name and its badges, short enough to scroll
          // rather than cover the screen in a very full channel.
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 340),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [for (final member in hidden) row(member)],
          ),
        ),
      ),
    );
  }

  /// The DJ, under the people in the call. Only in our own call: the booth
  /// is heard over its data channel.
  Widget buildDj() {
    final session = voiceSession;
    final dj = DjBooths.of(session);
    if (session == null || dj == null) return const SizedBox.shrink();
    String nameOf(String userId) =>
        widget.room.getMemberOrFallback(userId).displayName;
    return ListenableBuilder(
      listenable: dj,
      // Built when the menu opens, so it matches the booth at that moment.
      builder: (context, child) => AdaptiveContextMenu(
        items: dj.djUserId == null
            ? const []
            : djMemberMenuItems(dj,
                userId: dj.djUserId!,
                displayName: nameOf(dj.djUserId!),
                musicVolume: DjMusicVolume(session: session)),
        child: child!,
      ),
      child: DjSidebarRow(
        dj: dj,
        nameOf: nameOf,
        height: height,
        onTap: () {
          DjBooths.showPanel(session);
          widget.onTap?.call(widget.room);
        },
      ),
    );
  }

  Widget buildEvents(Widget header, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 0, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceDim.withAlpha(180),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  tiamat.Text.labelLow("Today: "),
                  for (var event in calendarEvents!) buildEvent(event),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildCallMember(String identifier,
      {bool showActivityIcons = true,
      Set<LiveMedia> liveMedia = const {},
      Set<VoiceState> voiceState = const {},
      bool? djPlaying}) {
    var color = Theme.of(context).colorScheme.secondary;

    final member = widget.room.getMemberOrFallback(identifier);

    bool canShowActivityIcons = activitySessions != null && showActivityIcons;

    // Only in our own call: the booth is heard over its data channel.
    final dj = showActivityIcons ? DjBooths.of(voiceSession) : null;

    final row = SizedBox(
      height: height,
      child: tiamat.TextButton(
        member.displayName,
        textColor: color,
        avatar: member.avatar,
        avatarPlaceholderColor: member.defaultColor,
        avatarPlaceholderText: member.displayName,
        // Scaled down from the call tiles to stay inside this row.
        avatarBuilder: (avatar) => SpeakingIndicator(
          // Voice members only, not people in a third party activity.
          speaking: showActivityIcons && speakingMembers.contains(identifier),
          radius: 12,
          ringGap: 1.5,
          ringWidth: 2,
          waveTravel: 5,
          child: avatar,
        ),
        footer: canShowActivityIcons
            ? Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                child: Row(
                  children: [
                    if (dj != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
                        child: DjMemberBadges(dj: dj, userId: identifier),
                      )
                    // Outside the call: what their membership says. The
                    // record spins while their music plays.
                    else if (djPlaying != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
                        child: Tooltip(
                          message: djPlaying ? labelDjPlaying : labelDjPaused,
                          child: VinylDisc(size: 16, spinning: djPlaying),
                        ),
                      ),
                    if (voiceState.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
                        child: VoiceStateIndicator(voiceState),
                      ),
                    if (liveMedia.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                        child: LiveMediaIndicator(liveMedia),
                      ),
                    for (var i in activitySessions!.where((i) =>
                        i.thirdparty == true &&
                        i.participants.contains(identifier)))
                      ClipRRect(
                        borderRadius: BorderRadiusGeometry.circular(4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: i.associatedWidget == null
                                ? null
                                : () => onWidgetTapped(i),
                            child: SizedBox(
                                height: 30,
                                width: 30,
                                child: Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: i.icon.build(context),
                                )),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
    );

    if (dj == null) return row;
    // Built when the menu opens, so it matches the booth at that moment.
    return ListenableBuilder(
      listenable: dj,
      builder: (context, child) => AdaptiveContextMenu(
        items: djMemberMenuItems(dj,
            userId: identifier,
            displayName: member.displayName,
            musicVolume: DjMusicVolume(session: voiceSession!)),
        child: child!,
      ),
      child: row,
    );
  }

  Widget buildEvent(MatrixCalendarEventState event) {
    var color =
        calendarRoom!.calendar!.config.getColorFromUser(event.senderId!);

    return TinyPill(
      event.data.title,
      background: calendarRoom!.calendar!.config.processEventColor(
        color,
        context,
      ),
      foreground: calendarRoom!.calendar!.config.processEventTextColor(
        color,
        context,
      ),
    );
  }

  Future<void> onWidgetTapped(RoomActivitySession activity) async {
    bool isInActivity = WidgetComponent.currentSessions.any(
      (element) =>
          element.info.type == activity.application &&
          widget.room == element.room,
    );

    if (isInActivity == false) {
      var confirm = await AdaptiveDialog.confirmation(context,
          prompt: "Open **${activity.associatedWidget!.name}**?");
      if (confirm == true) {
        WidgetComponent.runWidget(
            widget.room, context, activity.associatedWidget!);
      }
    } else {
      Log.i("Already has a widget in for this session");
    }
  }
}
