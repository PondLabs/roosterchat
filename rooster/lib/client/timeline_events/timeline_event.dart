import 'package:rooster/client/client.dart';

abstract class TimelineEvent<T extends Client> {
  TimelineEventStatus get status;

  String get plainTextBody;

  String get eventId;
  String get senderId;
  DateTime get originServerTs;
  String get source;
  bool get mentionsRoom;
  List<String> get mentions;

  /// Whether the event calls on us, for the timeline to highlight it: it
  /// mentions us or the whole room, or, from a client that lists no
  /// mentions, says our name (what our push rules highlight). Never one of
  /// our own.
  bool get mentionsSelf;

  bool get editable;

  @override
  int get hashCode => eventId.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }
}
