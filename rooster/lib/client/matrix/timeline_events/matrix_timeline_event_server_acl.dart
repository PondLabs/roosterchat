import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.server_acl`: which servers may take part in the room changed.
/// The timeline only says that it changed; the rules themselves belong to
/// the room's moderation settings.
class MatrixTimelineEventServerAcl extends MatrixTimelineEventState {
  MatrixTimelineEventServerAcl(super.event, {required super.client});

  static String messageServerAclChanged(String user) =>
      Intl.message("$user changed which servers can take part in the room",
          name: "messageServerAclChanged",
          args: [user],
          desc: "Timeline line for when someone changes the room's server "
              "access rules (Matrix calls them server ACLs)");

  @override
  IconData get icon => Icons.dns_outlined;

  @override
  String getBody({Timeline? timeline}) =>
      messageServerAclChanged(senderName(timeline: timeline));
}
