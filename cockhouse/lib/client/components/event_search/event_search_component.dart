import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/component.dart';
import 'package:cockhouse/client/timeline_events/timeline_event.dart';

abstract class EventSearchSession {
  Stream<List<TimelineEvent>> startSearch(String searchTerm);

  Stream<List<TimelineEvent>> continueSearch();

  bool get currentlySearching;

  bool get canContinueSearch;
}

abstract class EventSearchComponent<T extends Client> implements Component<T> {
  Future<EventSearchSession> createSearchSession(Room room);

  List<String> getSupportedSearchFeatures(Room room);
}
