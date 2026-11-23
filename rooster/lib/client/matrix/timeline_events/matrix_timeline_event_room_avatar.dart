import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.avatar`: the room's picture changed, or was removed.
class MatrixTimelineEventRoomAvatar extends MatrixTimelineEventState {
  MatrixTimelineEventRoomAvatar(super.event, {required super.client});

  static String messageRoomAvatarChanged(String user) =>
      Intl.message("$user changed the room picture",
          name: "messageRoomAvatarChanged",
          args: [user],
          desc: "Timeline line for when someone sets a new picture (avatar) "
              "for the room");

  static String messageRoomAvatarRemoved(String user) =>
      Intl.message("$user removed the room picture",
          name: "messageRoomAvatarRemoved",
          args: [user],
          desc: "Timeline line for when someone removes the room's picture "
              "(avatar)");

  @override
  IconData get icon => Icons.image_outlined;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    return contentString('url') == null
        ? messageRoomAvatarRemoved(user)
        : messageRoomAvatarChanged(user);
  }
}
