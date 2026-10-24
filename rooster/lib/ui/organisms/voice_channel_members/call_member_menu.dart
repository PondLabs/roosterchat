import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_moves_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/user_list.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/call_view/voip_stream_view.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Someone under a voice channel in the sidebar, being dragged to another.
class CallMemberDrag {
  const CallMemberDrag(this.from, this.userId);

  final MatrixRoom from;
  final String userId;
}

/// What can be done to someone in a voice channel from the sidebar, as in
/// Discord: open their profile, message them, turn them down, move them to
/// another channel or out of the call.
abstract final class CallMemberMenu {
  static String get promptCallMemberProfile => Intl.message("Profile",
      name: "promptCallMemberProfile",
      desc: "Entry in the menu of someone in a voice channel in the sidebar: "
          "opens their profile");

  static String get promptCallMemberMessage => Intl.message("Message",
      name: "promptCallMemberMessage",
      desc: "Entry in the menu of someone in a voice channel in the sidebar: "
          "opens our direct messages with them");

  static String get promptCallMemberMoveTo => Intl.message("Move To…",
      name: "promptCallMemberMoveTo",
      desc: "Entry in the menu of someone in a voice channel in the sidebar: "
          "picks another voice channel to move them to");

  static String get promptCallMemberDisconnect => Intl.message("Disconnect",
      name: "promptCallMemberDisconnect",
      desc: "Entry in the menu of someone in a voice channel in the sidebar: "
          "takes them out of the call");

  static String get promptCallMemberCopyUserId => Intl.message("Copy User ID",
      name: "promptCallMemberCopyUserId",
      desc: "Entry in the menu of someone in a voice channel in the sidebar: "
          "copies their Matrix user id");

  static String labelCallMemberMoveTo(String name) =>
      Intl.message("Move $name to",
          name: "labelCallMemberMoveTo",
          args: [name],
          desc: "Title of the list of voice channels to move someone to, with "
              "their name");

  static String get errorCallMemberMove => Intl.message("Could not move them",
      name: "errorCallMemberMove",
      desc: "Title of the error shown when moving someone to another voice "
          "channel, or out of the call, failed");

  /// Whether we may drag [userId] out of [room]'s call.
  static bool canMove(Room room, String userId) =>
      room is MatrixRoom && MatrixCallMovesComponent.canMove(room, userId);

  /// The voice channels of [space] besides [room], the ones we can join.
  static List<Room> otherVoiceChannels(Room room, Space? space) => [
        for (final other in space?.rooms ?? const <Room>[])
          if (other != room &&
              (other.getComponent<VoipRoomComponent>()?.canJoinCall ?? false))
            other,
      ];

  /// Moves [userId] from [from]'s call to [to]'s, or out of it, saying so
  /// when it could not be done.
  static Future<void> move(
      BuildContext context, Room from, String userId, Room? to) async {
    final moves = from.client.getComponent<MatrixCallMovesComponent>();
    if (moves == null || from is! MatrixRoom) return;
    try {
      await moves.move(from, userId, to is MatrixRoom ? to : null);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not move $userId");
      if (context.mounted) {
        AdaptiveDialog.showError(context, e, s, title: errorCallMemberMove);
      }
    }
  }

  static List<tiamat.ContextMenuItem> items(
    BuildContext context, {
    required Room room,
    required String userId,
    Space? space,
    VoipSession? session,
  }) {
    final client = room.client;
    final member = room.getMemberOrFallback(userId);
    final isSelf = userId == client.self?.identifier;
    final canMove = CallMemberMenu.canMove(room, userId);
    final channels = canMove ? otherVoiceChannels(room, space) : const <Room>[];
    // Their voice, when we are in the call with them.
    final voice = isSelf
        ? null
        : session?.streams.where(
            (s) => s.streamUserId == userId && s.type == VoipStreamType.audio);

    return [
      if (voice != null && voice.isNotEmpty)
        ...VoipStreamView.streamContextMenuItems(voice.first, member),
      tiamat.ContextMenuItem(
          text: promptCallMemberProfile,
          icon: Icons.person_rounded,
          onPressed: () =>
              UserProfile.show(context, client: client, userId: userId)),
      if (!isSelf)
        tiamat.ContextMenuItem(
            text: promptCallMemberMessage,
            icon: Icons.chat_bubble_rounded,
            onPressed: () => openDirectMessage(client, userId)),
      if (channels.isNotEmpty)
        tiamat.ContextMenuItem(
            text: promptCallMemberMoveTo,
            icon: Icons.swap_horiz_rounded,
            onPressed: () =>
                pickChannelAndMove(context, room, userId, channels)),
      if (canMove)
        tiamat.ContextMenuItem(
            text: promptCallMemberDisconnect,
            icon: Icons.call_end_rounded,
            color: ColorScheme.of(context).error,
            onPressed: () => move(context, room, userId, null)),
      tiamat.ContextMenuItem(
          text: promptCallMemberCopyUserId,
          icon: Icons.copy_rounded,
          onPressed: () => Clipboard.setData(ClipboardData(text: userId))),
      ...RoomMemberList.userContextMenuItems(context,
          userId: userId,
          userDisplayName: member.displayName,
          room: room,
          isSelf: isSelf),
    ];
  }

  static Future<void> pickChannelAndMove(BuildContext context, Room from,
      String userId, List<Room> channels) async {
    final to = await AdaptiveDialog.pickOne<Room>(
      context,
      title:
          labelCallMemberMoveTo(from.getMemberOrFallback(userId).displayName),
      items: channels,
      itemBuilder: (context, room, callback) => SizedBox(
        height: 40,
        child: tiamat.TextButton(room.displayName,
            icon: Icons.volume_up_rounded, onTap: callback),
      ),
    );
    if (to != null && context.mounted) await move(context, from, userId, to);
  }

  /// Opens our direct messages with [userId], made first if there are none.
  static Future<void> openDirectMessage(Client client, String userId) async {
    final component = client.getComponent<DirectMessagesComponent>();
    if (component == null) return;
    final existing = component.directMessageRooms
        .where((room) => component.getDirectMessagePartnerId(room) == userId);
    final room = existing.isNotEmpty
        ? existing.first
        : await component.createDirectMessage(userId);
    if (room != null) {
      EventBus.doOpenRoom(room.identifier, clientId: client.identifier);
    }
  }
}
