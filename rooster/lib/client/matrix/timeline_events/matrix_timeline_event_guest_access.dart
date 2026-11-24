import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.guest_access`: whether guest accounts may join changed.
class MatrixTimelineEventGuestAccess extends MatrixTimelineEventState {
  MatrixTimelineEventGuestAccess(super.event, {required super.client});

  static String messageGuestAccessAllowed(String user) =>
      Intl.message("$user let guests join the room",
          name: "messageGuestAccessAllowed",
          args: [user],
          desc: "Timeline line for when someone allows guest accounts "
              "(temporary accounts without a password) to join the room");

  static String messageGuestAccessForbidden(String user) =>
      Intl.message("$user stopped guests from joining the room",
          name: "messageGuestAccessForbidden",
          args: [user],
          desc: "Timeline line for when someone stops guest accounts from "
              "joining the room");

  static String messageGuestAccessChanged(String user) =>
      Intl.message("$user changed guest access to the room",
          name: "messageGuestAccessChanged",
          args: [user],
          desc: "Timeline line for a change to the room's guest access that "
              "the app cannot describe (unknown or missing)");

  String? get guestAccess => contentString('guest_access');

  @override
  IconData get icon => Icons.person_outline;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    return switch (guestAccess) {
      'can_join' => messageGuestAccessAllowed(user),
      'forbidden' => messageGuestAccessForbidden(user),
      _ => messageGuestAccessChanged(user),
    };
  }
}
