import 'dart:developer';

/// Now on the clock the engine stamps `FrameTiming`s with, in microseconds.
/// Native: the engine's clock is Dart's monotonic timeline clock (it sets
/// `fml::TimePoint::SetClockSource(DartTimelineTicksSinceEpoch)` at start).
int frameClockMicros() => Timeline.now;
