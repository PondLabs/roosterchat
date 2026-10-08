import 'dart:convert';

import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixTimelineEvent implements TimelineEvent {
  final MatrixClient client;

  matrix.Event event;

  MatrixTimelineEvent(this.event, {required this.client});

  @override
  bool get editable => false;

  @override
  String get eventId => event.eventId;

  @override
  DateTime get originServerTs => event.originServerTs;

  @override
  String get senderId => event.senderId;

  @override
  String get source =>
      const JsonEncoder.withIndent('  ').convert(event.toJson());

  @override
  bool get mentionsRoom => event.mentions.room;

  @override
  List<String> get mentions => event.mentions.userIds;

  @override
  bool get mentionsSelf {
    final self = client.matrixClient.userID;
    if (self == null || event.senderId == self) return false;

    final mentions = event.mentions;
    if (mentions.userIds.contains(self)) return true;
    if (mentions.room &&
        MatrixRoomPermissions.canUserMentionRoom(event.senderId, event.room)) {
      return true;
    }

    // With m.mentions, the list is the whole answer: the Matrix spec has
    // the rules matching our name in the text not apply. Clients that write
    // none mention by name, which our push rules know (a room muted by a
    // rule does not highlight, as it does not notify).
    if (event.content.containsKey('m.mentions')) return false;
    try {
      return client.matrixClient.pushruleEvaluator.match(event).highlight;
    } catch (_) {
      return false;
    }
  }

  @override
  TimelineEventStatus get status => switch (event.status) {
        matrix.EventStatus.error => TimelineEventStatus.error,
        matrix.EventStatus.sending => TimelineEventStatus.sending,
        matrix.EventStatus.sent => TimelineEventStatus.sent,
        matrix.EventStatus.synced => TimelineEventStatus.synced,
      };

  /// The event's text, or its type when it has none: the SDK's own fallback
  /// reads "Unknown message format of type ...", which the timeline's folded
  /// summary and failed sends would show.
  @override
  String get plainTextBody => event.redacted || event.text.isNotEmpty
      ? event.plaintextBody
      : event.type;
}
