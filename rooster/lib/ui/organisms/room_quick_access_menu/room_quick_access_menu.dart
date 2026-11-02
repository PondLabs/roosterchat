import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/calendar_room/calendar_room_component.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/event_search/event_search_component.dart';
import 'package:rooster/client/components/invitation/invitation_component.dart';
import 'package:rooster/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:rooster/client/components/voip/voip_component.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/invitation_view/send_invitation.dart';
import 'package:rooster/ui/organisms/voice_activity/voice_activity_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RoomQuickAccessMenu {
  final Room room;
  late final List<RoomQuickAccessMenuEntry> actions;

  static String get promptRoomInvite => Intl.message("Invite",
      name: "promptRoomInvite",
      desc:
          "Button in a room's header (and on a space's page) that invites people to it, and the title of the invite dialog it opens");

  static String get labelRoomCallHistory => Intl.message("Call history",
      name: "labelRoomCallHistory",
      desc:
          "Button of a voice channel (or a space) that shows who was in its calls, day by day, and the title of that dialog");

  static String get promptRoomCall => Intl.message("Call",
      name: "promptRoomCall",
      desc: "Button in a direct message's header that starts a voice call");

  static String get promptRoomOpenCalendar => Intl.message("Calendar",
      name: "promptRoomOpenCalendar",
      desc: "Button in a room's header that shows the room's calendar");

  static String get promptRoomPinnedMessages => Intl.message("Pinned Messages",
      name: "promptRoomPinnedMessages",
      desc: "Button in a room's header that shows the room's pinned messages");

  static String get promptRoomWidgets => Intl.message("Widgets",
      name: "promptRoomWidgets",
      desc:
          "Button in a room's header that lists the room's widgets (small web apps added to the room)");

  static String get promptRoomToggleSidePanel => Intl.message("Toggle Panel",
      name: "promptRoomToggleSidePanel",
      desc:
          "Button in a room's header that shows or hides the panel on the right (members, search, pinned messages)");

  RoomQuickAccessMenu({required this.room, required BuildContext context}) {
    final bool canSearch =
        room.client.getComponent<EventSearchComponent>() != null;

    final invitation = room.client.getComponent<InvitationComponent>();

    final bool supportsPinnedMessages =
        room.getComponent<PinnedMessagesComponent>() != null;

    final calls = room.client.getComponent<VoipComponent>();
    final direct = room.client.getComponent<DirectMessagesComponent>();
    final calendar = room.getComponent<CalendarRoom>();
    final bool canCall =
        calls != null && direct?.isRoomDirectMessage(room) == true;

    final bool isVoipRoom = room.getComponent<VoipRoomComponent>() != null;

    // Dont show widgets in Voip room. If the widget uses MatrixRTC,
    // it seems to interfere with the ongoing call...
    final bool hasWidgets = isVoipRoom == false &&
        room.client.getComponent<WidgetComponent>() != null;

    actions = [
      if (invitation != null)
        RoomQuickAccessMenuEntry(
            id: "Invite",
            name: promptRoomInvite,
            action: (context) => AdaptiveDialog.show(context,
                builder: (context) => SendInvitationWidget(
                      room.client,
                      invitation,
                      roomId: room.identifier,
                      displayName: room.displayName,
                      existingMembers: room.memberIds,
                    ),
                title: promptRoomInvite),
            icon: Icons.person_add),
      if (isVoipRoom)
        RoomQuickAccessMenuEntry(
            id: "Call history",
            name: labelRoomCallHistory,
            action: (context) => AdaptiveDialog.show(context,
                builder: (context) => VoiceActivityView(rooms: [room]),
                title: labelRoomCallHistory),
            icon: Icons.history),
      if (canCall)
        RoomQuickAccessMenuEntry(
            id: "Call",
            name: promptRoomCall,
            action: (context) =>
                calls.startCall(room.identifier, CallType.voice),
            icon: Icons.call),
      if (preferences.hideRoomSidePanel.value == false ||
          MediaQuery.sizeOf(context).mobile) ...[
        if (calendar?.hasCalendar == true && calendar?.isCalendarRoom == false)
          RoomQuickAccessMenuEntry(
              id: "Calendar",
              name: promptRoomOpenCalendar,
              action: (context) => EventBus.openCalendar.add(null),
              icon: Icons.calendar_month),
        if (supportsPinnedMessages)
          RoomQuickAccessMenuEntry(
              id: "Pinned Messages",
              name: promptRoomPinnedMessages,
              action: (context) => EventBus.openPinnedMessages.add(null),
              icon: Icons.push_pin),
        if (canSearch)
          RoomQuickAccessMenuEntry(
              id: "Search",
              name: CommonStrings.promptSearch,
              action: (context) => EventBus.startSearch.add(null),
              icon: Icons.search),
        if (hasWidgets)
          RoomQuickAccessMenuEntry(
              id: "Widgets",
              name: promptRoomWidgets,
              action: (context) => EventBus.openWidgets.add(null),
              icon: Icons.widgets),
      ],
      if (MediaQuery.sizeOf(context).desktop)
        RoomQuickAccessMenuEntry(
            id: "Toggle Panel",
            name: promptRoomToggleSidePanel,
            action: (context) => EventBus.toggleRoomSidePanel.add(null),
            icon: preferences.hideRoomSidePanel.value
                ? Icons.chevron_left
                : Icons.chevron_right),
    ];
  }
}

class RoomQuickAccessMenuEntry {
  /// Stable, untranslated: names the entry in widget keys.
  final String id;
  final String name;
  final Function(BuildContext context)? action;
  final IconData icon;

  RoomQuickAccessMenuEntry(
      {required this.id,
      required this.name,
      required this.action,
      required this.icon});
}
