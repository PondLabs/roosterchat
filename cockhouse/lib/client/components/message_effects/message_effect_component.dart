import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/component.dart';
import 'package:cockhouse/client/timeline_events/timeline_event.dart';

abstract class MessageEffectComponent<T extends Client>
    implements Component<T> {
  void doEffect(TimelineEvent event);

  bool hasEffect(TimelineEvent event);
}
