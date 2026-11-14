/// The speed log: how long requests and user-visible operations take on this
/// device, kept in memory only, without content.
///
/// - Requests are recorded by `SpeedHttpClient`
///   (`lib/utils/network/speed_http_client.dart`), which every account's
///   `matrix.Client` sends through. Nothing to do at call sites.
/// - An operation (a text send, a voice join...) is a [SpeedSpan]:
///
///   ```dart
///   final span = SpeedLog.instance.startSpan('text_send');
///   await span.run(() async {          // requests inside are linked to it
///     span.mark('echo_painted');        // a step from the last mark to now
///     await span.time('request', () => room.sendTextEvent(text));
///     span.unavailable('server_queue'); // cannot be timed from app code
///   });
///   span.finish();                      // or finish(outcome: 'failed')
///   ```
///
/// - `buildSpeedReport` (`speed_report.dart`) turns the log into text.
///
/// Span, step and outcome names must be fixed identifiers written in the
/// code (`[a-z][a-z0-9_]*`, at most 40 characters), never text from a
/// message, a file or a person; any other name is written as `invalid_name`.
/// Step values are numbers only (sizes, counts).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/ring_buffer.dart';

/// Reports the duration of each UI frame drawn while it is listened to.
abstract class FrameSource {
  void listen(void Function(Duration frame) onFrame);
  void cancel();
}

/// The engine's frame timings, through [SchedulerBinding.addTimingsCallback].
/// Without a binding (a plain unit test) it reports nothing, so spans say
/// the longest frame is unavailable.
class SchedulerFrameSource implements FrameSource {
  TimingsCallback? _callback;

  @override
  void listen(void Function(Duration frame) onFrame) {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      return;
    }
    final callback = _callback = (List<FrameTiming> timings) {
      for (final timing in timings) {
        onFrame(timing.totalSpan);
      }
    };
    binding.addTimingsCallback(callback);
  }

  @override
  void cancel() {
    final callback = _callback;
    if (callback == null) return;
    _callback = null;
    SchedulerBinding.instance.removeTimingsCallback(callback);
  }
}

/// One step of a span. [duration] is null when the step cannot be timed from
/// app code: the report says `unavailable` instead of guessing.
class SpanStep {
  const SpanStep(this.name, this.start, this.duration, this.values);

  final String name;

  /// From the start of the span.
  final Duration start;
  final Duration? duration;

  /// Numbers that describe the step (`bytes`, `width`...).
  final Map<String, num> values;

  bool get available => duration != null;
}

/// One user-visible operation under a random local id, made of named steps
/// timed on the speed log's monotonic clock.
class SpeedSpan {
  SpeedSpan._(this._log, String name)
      : name = _identifier(name),
        id = _randomId(),
        startedAt = _log.now();

  final SpeedLog _log;
  final String name;

  /// Random, local to this device, links the span's requests to it.
  final String id;

  /// On the log's clock.
  final Duration startedAt;

  final List<SpanStep> steps = [];
  Duration? _lastMark;
  Duration? _longestFrame;
  final Map<String, int> _attempts = {};

  /// Set by [finish].
  Duration? duration;
  String? outcome;

  bool get isFinished => duration != null;

  /// The longest UI frame drawn while the span was open; null when no frame
  /// was reported (the report says `unavailable`).
  Duration? get longestFrame => _longestFrame;

  Duration get _elapsed => _log.now() - startedAt;

  /// A step from the previous mark (or the span's start) to now.
  void mark(String step, {Map<String, num> values = const {}}) {
    final now = _elapsed;
    final from = _lastMark ?? Duration.zero;
    _lastMark = now;
    _add(SpanStep(_identifier(step), from, now - from, values));
  }

  /// A step that lasts as long as [body]. Steps timed this way may overlap.
  Future<T> time<T>(String step, Future<T> Function() body,
      {Map<String, num> values = const {}}) async {
    final from = _elapsed;
    try {
      return await body();
    } finally {
      _add(SpanStep(_identifier(step), from, _elapsed - from, values));
    }
  }

  /// A step that exists but cannot be timed from app code.
  void unavailable(String step) =>
      _add(SpanStep(_identifier(step), _elapsed, null, const {}));

  /// Runs [body] so the requests it makes, through any async gap, are
  /// recorded with this span's id and numbered as attempts.
  R run<R>(R Function() body) =>
      runZoned(body, zoneValues: {SpeedLog._spanKey: this});

  /// Closes the span and moves it to the log. Later calls do nothing.
  void finish({String outcome = 'ok'}) {
    if (isFinished) return;
    duration = _elapsed;
    this.outcome = _identifier(outcome);
    _log._close(this);
  }

  void _add(SpanStep step) {
    if (steps.length >= SpeedLog.maxStepsPerSpan) return;
    steps.add(SpanStep(step.name, step.start, step.duration, {
      for (final value in step.values.entries)
        _identifier(value.key): value.value,
    }));
  }

  void _frame(Duration frame) {
    if (_longestFrame == null || frame > _longestFrame!) _longestFrame = frame;
  }

  /// The attempt number of the next request with this [key] in the span.
  int _nextAttempt(String key) =>
      _attempts.update(key, (n) => n + 1, ifAbsent: () => 1);

  static final Random _random = Random.secure();

  static String _randomId() => List.generate(
      8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static final RegExp _fixedIdentifier = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  /// [name] if it looks like a constant from the code, else `invalid_name`:
  /// a name built from content would carry that content into the report.
  static String _identifier(String name) =>
      _fixedIdentifier.hasMatch(name) ? name : 'invalid_name';
}

/// The in-memory speed log: the newest requests and finished spans, in two
/// [RingBuffer]s of fixed size. Always on; nothing leaves the device.
class SpeedLog {
  SpeedLog({
    int requestCapacity = 512,
    int spanCapacity = 256,
    FrameSource? frames,
    Duration Function()? clock,
  })  : requests = RingBuffer(requestCapacity),
        spans = RingBuffer(spanCapacity),
        _frames = frames ?? SchedulerFrameSource(),
        _clock = clock ?? (Stopwatch()..start()).elapsedFrom;

  /// The log of the app. Tests make their own.
  static final SpeedLog instance = SpeedLog();

  static const maxStepsPerSpan = 64;
  static const maxOpenSpans = 64;
  static final Object _spanKey = Object();

  final RingBuffer<RequestRecord> requests;

  /// Finished spans, oldest first.
  final RingBuffer<SpeedSpan> spans;

  final FrameSource _frames;
  final Duration Function() _clock;
  final List<SpeedSpan> _open = [];

  /// Monotonic time since the log started.
  Duration now() => _clock();

  /// Spans not finished yet, oldest first.
  List<SpeedSpan> get openSpans => List.unmodifiable(_open);

  SpeedSpan startSpan(String name) {
    final span = SpeedSpan._(this, name);
    if (_open.isEmpty) _frames.listen(_onFrame);
    // A span nobody finishes must not hold memory forever.
    if (_open.length >= maxOpenSpans) _open.first.finish(outcome: 'abandoned');
    _open.add(span);
    return span;
  }

  /// The span the current code runs in (see [SpeedSpan.run]).
  static SpeedSpan? get currentSpan => Zone.current[_spanKey] as SpeedSpan?;

  /// The attempt number for a request with [key] (method and route) in
  /// [span]: 1, 2, 3... per span, 1 outside one.
  static int nextAttempt(SpeedSpan? span, String key) =>
      span?._nextAttempt(key) ?? 1;

  void recordRequest(RequestRecord record) => requests.add(record);

  void _onFrame(Duration frame) {
    for (final span in _open) {
      span._frame(frame);
    }
  }

  void _close(SpeedSpan span) {
    _open.remove(span);
    spans.add(span);
    if (_open.isEmpty) _frames.cancel();
  }
}

extension on Stopwatch {
  Duration elapsedFrom() => elapsed;
}
