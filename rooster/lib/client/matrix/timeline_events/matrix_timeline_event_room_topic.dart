import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_rich_topic.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';

/// `m.room.topic`: the room's topic changed. A Matrix v1.15 rich topic
/// (`m.topic` with `text/html`) is shown formatted under the line,
/// sanitized like a message's HTML; otherwise the line carries the text.
class MatrixTimelineEventRoomTopic extends MatrixTimelineEventState {
  MatrixTimelineEventRoomTopic(super.event, {required super.client});

  static String messageRoomTopicChanged(String user, String topic) =>
      Intl.message("$user changed the topic to: $topic",
          name: "messageRoomTopicChanged",
          args: [user, topic],
          desc: "Timeline line for when someone changes the room's topic "
              "(its description), with their name and the new topic");

  static String messageRoomTopicChangedFormatted(String user) =>
      Intl.message("$user changed the topic to:",
          name: "messageRoomTopicChangedFormatted",
          args: [user],
          desc: "Timeline line for when someone changes the room's topic "
              "to a formatted one, which is shown right under this line");

  static String messageRoomTopicRemoved(String user) =>
      Intl.message("$user removed the topic",
          name: "messageRoomTopicRemoved",
          args: [user],
          desc: "Timeline line for when someone clears the room's topic "
              "(its description)");

  late final MatrixRichTopic topic = MatrixRichTopic.fromContent(event.content);

  /// Whether the line is followed by the formatted topic.
  bool get hasFormattedTopic => topic.html != null;

  @override
  IconData get icon => Icons.short_text;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    if (topic.isEmpty) return messageRoomTopicRemoved(user);
    return messageRoomTopicChanged(user, topic.plain);
  }

  /// The line shown above [buildFormattedTopic], without the topic in it.
  String getFormattedLead({Timeline? timeline}) =>
      messageRoomTopicChangedFormatted(senderName(timeline: timeline));

  /// The rich topic, sanitized and rendered as a message's HTML is; null
  /// when it has no HTML representation.
  Widget? buildFormattedTopic() {
    final html = topic.html;
    if (html == null) return null;
    final roomId = event.roomId;
    return MatrixHtmlParser.parse(
        html, client, roomId == null ? null : client.getRoom(roomId),
        mentionsRoom: false);
  }
}
