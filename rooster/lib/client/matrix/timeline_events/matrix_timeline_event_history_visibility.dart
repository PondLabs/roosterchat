import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.history_visibility`: who can read the room's messages from now
/// on changed.
class MatrixTimelineEventHistoryVisibility extends MatrixTimelineEventState {
  MatrixTimelineEventHistoryVisibility(super.event, {required super.client});

  static String messageHistoryVisibilityShared(String user) => Intl.message(
      "$user made new messages readable by every member, including those "
      "who join later",
      name: "messageHistoryVisibilityShared",
      args: [user],
      desc: "Timeline line for the 'shared' history visibility: members "
          "can read the room's history from this point on, even messages "
          "sent before they joined");

  static String messageHistoryVisibilityInvited(String user) => Intl.message(
      "$user made new messages readable by members from the time they were "
      "invited",
      name: "messageHistoryVisibilityInvited",
      args: [user],
      desc: "Timeline line for the 'invited' history visibility");

  static String messageHistoryVisibilityJoined(String user) => Intl.message(
      "$user made new messages readable by members from the time they "
      "joined",
      name: "messageHistoryVisibilityJoined",
      args: [user],
      desc: "Timeline line for the 'joined' history visibility");

  static String messageHistoryVisibilityWorldReadable(String user) =>
      Intl.message("$user made new messages readable by anyone",
          name: "messageHistoryVisibilityWorldReadable",
          args: [user],
          desc: "Timeline line for the 'world_readable' history visibility: "
              "anyone, even people who are not in the room, can read it");

  static String messageHistoryVisibilityChanged(String user) =>
      Intl.message("$user changed who can read the room history",
          name: "messageHistoryVisibilityChanged",
          args: [user],
          desc: "Timeline line for a change to the room's history "
              "visibility that the app cannot describe (unknown or "
              "missing)");

  String? get visibility => contentString('history_visibility');

  @override
  IconData get icon => Icons.history;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    return switch (visibility) {
      'shared' => messageHistoryVisibilityShared(user),
      'invited' => messageHistoryVisibilityInvited(user),
      'joined' => messageHistoryVisibilityJoined(user),
      'world_readable' => messageHistoryVisibilityWorldReadable(user),
      _ => messageHistoryVisibilityChanged(user),
    };
  }
}
