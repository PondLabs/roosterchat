// A model which holds the delayed event and it's timer

import 'dart:async';

import 'package:matrix/matrix.dart';

class DelayedEventCanceller {
  final String delayedEventId;
  final Timer restartTimer;

  // ROOSTER: The API the delayed event was scheduled with (T5.2): it is
  // restarted and cancelled there, whatever `/versions` says later.
  final DelayedEventsSupport via;

  DelayedEventCanceller({
    required this.delayedEventId,
    required this.restartTimer,
    this.via = DelayedEventsSupport.unstable, // ROOSTER
  });
}
