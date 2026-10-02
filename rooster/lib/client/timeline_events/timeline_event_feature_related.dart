import 'package:rooster/client/timeline.dart';

abstract class TimelineEventFeatureRelated {
  EventRelationshipType? get relationshipType;

  String? get relatedEventId;
}
