import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.name`: the room was renamed, or its name removed.
class MatrixTimelineEventRoomName extends MatrixTimelineEventState {
  MatrixTimelineEventRoomName(super.event, {required super.client});

  static String messageRoomNameChanged(String user, String name) =>
      Intl.message("$user changed the room name to $name",
          name: "messageRoomNameChanged",
          args: [user, name],
          desc: "Timeline line for when someone renames the room, with "
              "their name and the room's new name");

  static String messageRoomNameRemoved(String user) =>
      Intl.message("$user removed the room name",
          name: "messageRoomNameRemoved",
          args: [user],
          desc: "Timeline line for when someone clears the room's name");

  String? get name => contentString('name');

  @override
  IconData get icon => Icons.edit_outlined;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    final name = this.name;
    return name == null
        ? messageRoomNameRemoved(user)
        : messageRoomNameChanged(user, name);
  }
}
