import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/timeline.dart';

abstract class TimelineEventFeatureReactions {
  bool hasReactions(Timeline timeline);

  Map<Emoticon, Set<String>> getReactions(Timeline timeline);
}
