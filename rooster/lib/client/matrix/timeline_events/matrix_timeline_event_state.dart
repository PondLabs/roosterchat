import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_generic.dart';

/// A standard room state event shown as one line in the timeline, without
/// the sender's avatar. Each type reads its own content and says what
/// changed; content that is missing, redacted (`{}`) or of the wrong type
/// gives a plain line rather than an error.
abstract class MatrixTimelineEventState extends MatrixTimelineEvent
    implements TimelineEventGeneric {
  MatrixTimelineEventState(super.event, {required super.client});

  /// Who sent the event, by the name the room knows them by.
  String senderName({Timeline? timeline}) {
    if (timeline != null) {
      final name =
          timeline.room.getMemberOrFallback(event.senderId).displayName;
      if (name.isNotEmpty) return name;
    }
    return event.senderFromMemoryOrFallback.displayName ?? event.senderId;
  }

  /// [key] of the event's content when it is a string with more than
  /// whitespace in it.
  String? contentString(String key) => nonEmptyString(event.content[key]);

  /// [key] of the content the event replaced, when it is a non-empty string.
  String? previousContentString(String key) =>
      nonEmptyString(event.prevContent?[key]);

  static String? nonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  @override
  String get plainTextBody => getBody();

  @override
  bool get showSenderAvatar => false;
}
