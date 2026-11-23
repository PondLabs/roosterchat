import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_tombstone.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_generic.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// `m.room.tombstone`: the room was upgraded and a new room replaces it.
class MatrixTimelineEventTombstone extends MatrixTimelineEvent
    implements TimelineEventGeneric {
  MatrixTimelineEventTombstone(super.event, {required super.client});

  static String messageUserReplacedRoom(String user) => Intl.message(
      "$user upgraded this room. The conversation continues in "
      "the new room.",
      desc: "Timeline line for when someone upgrades a room: it is "
          "closed and a new room (Matrix calls it the replacement room) "
          "takes its place",
      args: [user],
      name: "messageUserReplacedRoom");

  MatrixRoomTombstone? get tombstone =>
      MatrixRoomTombstone.fromContent(event.content, senderId: event.senderId);

  @override
  IconData get icon => Icons.upgrade;

  @override
  String get plainTextBody => getBody();

  @override
  bool get showSenderAvatar => false;

  @override
  String getBody({Timeline? timeline}) {
    var name = event.senderFromMemoryOrFallback.displayName ?? event.senderId;
    return messageUserReplacedRoom(name);
  }
}
