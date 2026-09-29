import 'package:cockhouse/client/components/emoticon/emoticon.dart';
import 'package:cockhouse/client/timeline.dart';

abstract class TimelineEventFeatureReactions {
  bool hasReactions(Timeline timeline);

  Map<Emoticon, Set<String>> getReactions(Timeline timeline);
}
