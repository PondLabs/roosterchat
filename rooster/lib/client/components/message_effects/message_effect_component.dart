import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';

abstract class MessageEffectComponent<T extends Client>
    implements Component<T> {
  void doEffect(TimelineEvent event);

  bool hasEffect(TimelineEvent event);
}
