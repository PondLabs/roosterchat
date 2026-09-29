import 'package:cockhouse/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:cockhouse/client/timeline_events/timeline_event_add_reaction.dart';

class MatrixTimelineEventAddReaction extends MatrixTimelineEvent
    implements TimelineEventAddReaction {
  MatrixTimelineEventAddReaction(super.event, {required super.client});
}
