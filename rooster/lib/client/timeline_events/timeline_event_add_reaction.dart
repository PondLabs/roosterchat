import 'package:rooster/client/timeline_events/timeline_event.dart';

abstract class TimelineEventAddReaction extends TimelineEvent {
  /// The event reacted to.
  String? get reactsTo;
}
