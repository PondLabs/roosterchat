import 'package:rooster/client/client.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';

abstract class TimelineEventEncrypted extends TimelineEvent {
  Future<TimelineEvent?> attemptDecrypt(Room room);
}
