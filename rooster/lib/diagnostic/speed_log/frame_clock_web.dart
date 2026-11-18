import 'package:web/web.dart' as web;

/// Now on the clock the engine stamps `FrameTiming`s with, in microseconds.
/// Web: the engine stamps frames with `performance.now()`
/// (`FrameTimingRecorder`); `Timeline.now` is wall time there.
int frameClockMicros() => (web.window.performance.now() * 1000).toInt();
