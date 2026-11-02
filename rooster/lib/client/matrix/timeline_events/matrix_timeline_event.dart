import 'dart:convert';

import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixTimelineEvent implements TimelineEvent {
  final MatrixClient client;

  matrix.Event event;

  MatrixTimelineEvent(this.event, {required this.client});

  /// The text of a deleted event: the SDK's own is the English "Redacted".
  static String get messageTimelineRedactedBody => Intl.message("Redacted",
      name: "messageTimelineRedactedBody",
      desc: "Stands in for the text of a message that was deleted (Matrix "
          "calls it redacted), such as above a reply to it");

  /// An event the app has no words for, by its Matrix type. The SDK's own
  /// text for one is English.
  static String messageTimelineUnknownEventType(String type) =>
      Intl.message("Unknown Event Type: $type",
          name: "messageTimelineUnknownEventType",
          args: [type],
          desc: "Stands for a room event the app cannot show (seen in "
              "developer mode and in previews), with its Matrix event type");

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
  ///
  /// Computed once: the SDK parses the formatted body (HTML) to text on
  /// every call, and the room panel, the reply quotes and the chat asked
  /// for it on every rebuild. A changed event is a new instance.
  @override
  String get plainTextBody => _plainTextBody ??= event.redacted
      ? messageTimelineRedactedBody
      : event.text.isNotEmpty
          ? event.plaintextBody
          : event.type;
  String? _plainTextBody;
}
