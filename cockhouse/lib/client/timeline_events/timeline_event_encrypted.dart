import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/timeline_events/timeline_event.dart';

abstract class TimelineEventEncrypted extends TimelineEvent {
  Future<TimelineEvent?> attemptDecrypt(Room room);
}
