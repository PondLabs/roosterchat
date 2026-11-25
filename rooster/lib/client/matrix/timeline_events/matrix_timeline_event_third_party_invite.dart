import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.third_party_invite`: someone was invited by an email address or
/// phone number. An invitation is revoked by sending it again empty.
class MatrixTimelineEventThirdPartyInvite extends MatrixTimelineEventState {
  MatrixTimelineEventThirdPartyInvite(super.event, {required super.client});

  static String messageThirdPartyInvite(String user, String invitee) =>
      Intl.message("$user invited $invitee to the room",
          name: "messageThirdPartyInvite",
          args: [user, invitee],
          desc: "Timeline line for when someone invites a person by email "
              "or phone number, with the invitee's display name (often a "
              "shortened address)");

  static String messageThirdPartyInviteRevoked(String user, String invitee) =>
      Intl.message("$user revoked the invitation for $invitee",
          name: "messageThirdPartyInviteRevoked",
          args: [user, invitee],
          desc: "Timeline line for when someone withdraws an invitation "
              "sent by email or phone number, with the invitee's display "
              "name");

  static String messageThirdPartyInviteRevokedUnnamed(String user) =>
      Intl.message("$user revoked an invitation",
          name: "messageThirdPartyInviteRevokedUnnamed",
          args: [user],
          desc: "Timeline line for when someone withdraws an invitation "
              "sent by email or phone number, when the app does not know "
              "whose it was");

  @override
  IconData get icon => Icons.forward_to_inbox_outlined;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    final invitee = contentString('display_name');
    if (invitee != null) return messageThirdPartyInvite(user, invitee);
    final revoked = previousContentString('display_name');
    return revoked == null
        ? messageThirdPartyInviteRevokedUnnamed(user)
        : messageThirdPartyInviteRevoked(user, revoked);
  }
}
