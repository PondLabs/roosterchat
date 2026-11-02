import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/push_notification/modifiers/hide_content.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixBackgroundTimelineEventMessage implements TimelineEventMessage {
  static String get labelNotificationUnknownEventType =>
      Intl.message("Unknown event type",
          name: "labelNotificationUnknownEventType",
          desc: "Text of a notification on Android for something in a room "
              "that is neither a message nor encrypted, which the app cannot "
              "describe");

  matrix.MatrixEvent event;

  MatrixBackgroundTimelineEventMessage(this.event);

  @override
  List<Attachment>? get attachments => null;

  @override
  String? get body => event.content.toString();

  @override
  String? get bodyFormat => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    return null;
  }

  @override
  bool get editable => false;

  @override
  String get eventId => event.eventId;

  @override
  String? get formattedBody => null;

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    throw UnimplementedError();
  }

  @override
  bool isEdited(Timeline timeline) {
    throw UnimplementedError();
  }

  @override
  DateTime get originServerTs => event.originServerTs;

  @override
  String get plainTextBody {
    if (event.type == matrix.EventTypes.Encrypted) {
      return NotificationModifierHideContent
          .notificationModifiersPrivacyEnhanced;
    }

    if (event.type == matrix.EventTypes.Message) {
      if (event.content["body"] is String) {
        return event.content["body"] as String;
      }
    }

    return labelNotificationUnknownEventType;
  }

  @override
  String get senderId => event.senderId;

  @override
  String get source => throw UnimplementedError();

  @override
  bool get mentionsRoom => throw UnimplementedError();

  @override
  List<String> get mentions => throw UnimplementedError();

  @override
  bool get mentionsSelf => false;

  @override
  TimelineEventStatus get status => throw UnimplementedError();

  @override
  String getPlaintextBody(Timeline timeline) {
    return plainTextBody;
  }
}
