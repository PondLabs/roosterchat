/// The speed log: how long requests and user-visible operations take on this
/// device, kept in memory only, without content.
///
/// - Requests are recorded by `SpeedHttpClient`
///   (`lib/utils/network/speed_http_client.dart`), which every account's
///   `matrix.Client` sends through. Nothing to do at call sites.
/// - An operation (a text send, a voice join...) is a [SpeedSpan]:
///
///   ```dart
///   final span = SpeedLog.instance.startSpan(SpeedOperation.textSend);
///   await span.run(() async {       // requests inside are linked to it
///     span.mark(SpeedStep.echo);     // a step from the last mark to now
///     await span.time(SpeedStep.request, () => room.sendTextEvent(text));
///     span.unavailable(SpeedStep.answer); // cannot be timed from app code
///   });
///   span.finish();                   // or finish(outcome: SpeedOutcome.failed)
///   ```
///
/// - `buildSpeedReport` (`speed_report.dart`) turns the log into text.
///
/// Names are a fixed list, in `speed_names.dart` and nowhere else: span
/// names in `SpeedOperation.all`, steps in `SpeedStep.all`, the names of
/// numbers on steps in `SpeedValue.all`, outcomes in `SpeedOutcome.all`.
/// Any other name, even one shaped like them, is written `invalid_name`, so
/// text from a message, a file or a person never reaches the report. To add
/// a name: a constant in its class there, and the same constant in that
/// class's `all`. Merging a branch that added names too: keep both sides'
/// entries in each `all`. `SpeedOperation.all` plus `invalid_name` must fit
/// in [SpeedLog.maxOperations] (`speed_names_test.dart` checks). Step values
/// are numbers only (sizes, counts).
///
/// Attempts: inside a span, a request is attempt 1 the first time it is
/// sent, and 2, 3... each time the same request is sent again (the SDK's
/// retry of a send reuses its transaction id). "The same request" means the
/// same method, full URL (path and query) and body length, so two different
/// requests of one route, such as a file and its thumbnail to
/// `POST /_matrix/media/v3/upload` or two `sendToDevice` with their own
/// transaction ids, are each attempt 1. The span keeps only a salted hash of
/// each request (the salt is random per span), never its URL, and forgets
/// them all in [SpeedSpan.finish]. Outside a span every request is attempt 1.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show FramePhase;

import 'package:crypto/crypto.dart';
import 'package:flutter/scheduler.dart';
import 'package:rooster/diagnostic/speed_log/frame_clock.dart'
    if (dart.library.js_interop) 'package:rooster/diagnostic/speed_log/frame_clock_web.dart';
import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/ring_buffer.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// One UI frame: when its work ran, from [start] (build start) to [end]
/// (raster finish), on the speed log's clock, and how long it took from
/// vsync to raster finish.
class FrameSample {
  FrameSample(this.start, this.end, [Duration? duration])
      : duration = duration ?? end - start;

  final Duration start;
  final Duration end;
  final Duration duration;
}

/// Reports the UI frames drawn while it is listened to.
abstract class FrameSource {
  /// From now on, hands [onBatch] the frames drawn, in the batches the
  /// engine reports them in (about one a second in release, so a frame can
  /// arrive after the span it was drawn in has closed), timed on [clock].
  void listen(
      Duration Function() clock, void Function(List<FrameSample>) onBatch);
  void cancel();
}

/// The engine's frame timings, through [SchedulerBinding.addTimingsCallback].
/// Without a binding (a plain unit test) it reports nothing, so spans say
/// the longest frame is unavailable.
class SchedulerFrameSource implements FrameSource {
  TimingsCallback? _callback;

  @override
  void listen(
      Duration Function() clock, void Function(List<FrameSample>) onBatch) {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      return;
    }
    final callback = _callback = (List<FrameTiming> timings) {
      // From the engine's clock to the log's: both are monotonic, so the
      // offset between them read now holds for every frame of the batch.
      final offset = clock() - Duration(microseconds: frameClockMicros());
      Duration at(FrameTiming timing, FramePhase phase) =>
          Duration(microseconds: timing.timestampInMicroseconds(phase)) +
          offset;
      onBatch([
        for (final timing in timings)
          FrameSample(at(timing, FramePhase.buildStart),
              at(timing, FramePhase.rasterFinish), timing.totalSpan),
      ]);
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
  SpeedSpan._(this._log, String name, Duration? startedAt)
      : name = _listed(name, SpeedOperation.all),
        id = _randomId(),
        startedAt = startedAt ?? _log.now();

  final SpeedLog _log;
  final String name;

  /// Random, local to this device, links the span's requests to it.
  final String id;

  /// On the log's clock.
  final Duration startedAt;

  final List<SpanStep> steps = [];
  Duration? _lastMark;
  Duration? _longestFrame;

  /// How many times each request was sent in the span, by a salted hash of
  /// the request (see [_nextAttempt]). Emptied by [finish].
  final Map<String, int> _attempts = {};
  late final Hmac _attemptHash = Hmac(
      sha256, List.generate(16, (_) => _random.nextInt(256), growable: false));

  /// Set by [finish].
  Duration? duration;
  String? outcome;

  bool get isFinished => duration != null;

  /// The longest UI frame drawn while the span was open (its work and the
  /// span's overlap); null when no frame was reported (the report says
  /// `unavailable`). Frames arrive in batches: after [finish] it can still
  /// grow, until the log stops waiting for the span's frames
  /// ([SpeedLog.frameWait]).
  Duration? get longestFrame => _longestFrame;

  Duration get _elapsed => _log.now() - startedAt;

  /// Time since the span started, on the log's clock.
  Duration get elapsed => _elapsed;

  /// A step from the previous mark (or the span's start) to now.
  void mark(String step, {Map<String, num> values = const {}}) {
    final now = _elapsed;
    final from = _lastMark ?? Duration.zero;
    _lastMark = now;
    _add(SpanStep(step, from, now - from, values));
  }

  /// A step that lasts as long as [body]. Steps timed this way may overlap.
  Future<T> time<T>(String step, Future<T> Function() body,
      {Map<String, num> values = const {}}) async {
    final from = _elapsed;
    try {
      return await body();
    } finally {
      _add(SpanStep(step, from, _elapsed - from, values));
    }
  }

  /// A step that exists but cannot be timed from app code.
  void unavailable(String step) =>
      _add(SpanStep(step, _elapsed, null, const {}));

  /// A step measured another way on the log's clock, such as a request read
  /// from the log: [start] counts from the span's start, a null [duration]
  /// is unavailable.
  void addStep(String step, Duration start, Duration? duration,
          {Map<String, num> values = const {}}) =>
      _add(SpanStep(step, start, duration, values));

  /// Runs [body] so the requests it makes, through any async gap, are
  /// recorded with this span's id and numbered as attempts.
  R run<R>(R Function() body) =>
      runZoned(body, zoneValues: {SpeedLog._spanKey: this});

  /// Closes the span and moves it to the log. Later calls do nothing.
  void finish({String outcome = SpeedOutcome.ok}) {
    if (isFinished) return;
    duration = _elapsed;
    this.outcome = _listed(outcome, SpeedOutcome.all);
    _attempts.clear();
    _log._close(this);
  }

  void _add(SpanStep step) {
    if (steps.length >= SpeedLog.maxStepsPerSpan) return;
    steps.add(
        SpanStep(_listed(step.name, SpeedStep.all), step.start, step.duration, {
      for (final value in step.values.entries)
        _listed(value.key, SpeedValue.all): value.value,
    }));
  }

  /// When the span ended, on the log's clock; null while it is open.
  Duration? get _endedAt => duration == null ? null : startedAt + duration!;

  void _frames(List<FrameSample> batch) {
    final end = _endedAt;
    for (final frame in batch) {
      if (frame.end <= startedAt || (end != null && frame.start >= end)) {
        continue;
      }
      if (_longestFrame == null || frame.duration > _longestFrame!) {
        _longestFrame = frame.duration;
      }
    }
  }

  /// The attempt number of [request] (what identifies a request, see the
  /// library doc) in the span. Only its salted hash is kept, and nothing at
  /// all once the span is finished.
  int _nextAttempt(String request) {
    if (isFinished) return 1;
    final key = _attemptHash.convert(utf8.encode(request)).toString();
    return _attempts.update(key, (n) => n + 1, ifAbsent: () => 1);
  }

  /// How many distinct requests the span remembers for attempt numbering
  /// (0 once finished). Read by tests; the hashes themselves stay private.
  int get rememberedRequests => _attempts.length;

  static final Random _random = Random.secure();

  static String _randomId() => List.generate(
      8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  /// [name] if it is on the fixed list [names], else `invalid_name`: a name
  /// built from content would carry that content into the report.
  static String _listed(String name, Set<String> names) =>
      names.contains(name) ? name : invalidSpeedName;
}

/// Finished spans, the newest [perOperation] of each operation (span name)
/// in a [RingBuffer] of its own, so a frequent operation (a sync round every
/// 30 s) never pushes a rare one (a text send) out. At most [maxOperations]
/// operations are kept; spans of any further name are dropped. Span names
/// come from the fixed list (`SpeedOperation.all`, with `invalid_name`),
/// which fits in that bound, so the memory stays fixed.
class FinishedSpans {
  FinishedSpans({required this.perOperation, required this.maxOperations});

  final int perOperation;
  final int maxOperations;
  final Map<String, RingBuffer<(int, SpeedSpan)>> _byOperation = {};
  int _added = 0;

  /// The operations that have spans, in the order they first finished one.
  Iterable<String> get operations => _byOperation.keys;

  void add(SpeedSpan span) {
    var buffer = _byOperation[span.name];
    if (buffer == null) {
      if (_byOperation.length >= maxOperations) return;
      buffer = _byOperation[span.name] = RingBuffer(perOperation);
    }
    buffer.add((_added++, span));
  }

  int get length =>
      _byOperation.values.fold(0, (sum, buffer) => sum + buffer.length);

  /// Every kept span, oldest finished first.
  List<SpeedSpan> toList() {
    final all = [for (final buffer in _byOperation.values) ...buffer.toList()]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, span) in all) span];
  }

  void clear() {
    _byOperation.clear();
    _added = 0;
  }

  /// Slots allocated across the buffers, for tests that check it never
  /// grows past [perOperation] times [maxOperations].
  int get debugStorageSize => _byOperation.values
      .fold(0, (sum, buffer) => sum + buffer.debugStorage.length);
}

/// The in-memory speed log: the newest requests in a [RingBuffer] and the
/// newest finished spans of each operation in [FinishedSpans], all of fixed
/// size. Always on; nothing leaves the device.
class SpeedLog {
  SpeedLog({
    int requestCapacity = 512,
    FrameSource? frames,
    Duration Function()? clock,
  })  : requests = RingBuffer(requestCapacity),
        spans = FinishedSpans(
            perOperation: spansPerOperation, maxOperations: maxOperations),
        _frames = frames ?? SchedulerFrameSource(),
        _clock = clock ?? (Stopwatch()..start()).elapsedFrom;

  /// The log of the app. Tests make their own.
  static final SpeedLog instance = SpeedLog();

  /// Finished spans kept per operation, and how many operations.
  static const spansPerOperation = 256;
  static const maxOperations = 16;

  static const maxStepsPerSpan = 64;
  static const maxOpenSpans = 64;

  /// How long a finished span waits for the batch that holds its last
  /// frames, when no frame drawn after it is reported first.
  static const frameWait = Duration(seconds: 3);
  static final Object _spanKey = Object();

  final RingBuffer<RequestRecord> requests;

  /// Finished spans, the newest of each operation.
  final FinishedSpans spans;

  final FrameSource _frames;
  final Duration Function() _clock;
  final List<SpeedSpan> _open = [];

  /// Finished spans whose last frames may still come (see [frameWait]).
  final List<SpeedSpan> _waitingForFrames = [];
  bool _listening = false;

  /// Monotonic time since the log started.
  Duration now() => _clock();

  /// Spans not finished yet, oldest first.
  List<SpeedSpan> get openSpans => List.unmodifiable(_open);

  /// Opens a span named [name], from now or from [startedAt] (an earlier
  /// [now]) when the operation began before it was known to need one.
  SpeedSpan startSpan(String name, {Duration? startedAt}) {
    final span = SpeedSpan._(this, name, startedAt);
    if (!_listening) {
      _listening = true;
      _frames.listen(now, _onFrames);
    }
    // A span nobody finishes must not hold memory forever.
    if (_open.length >= maxOpenSpans) {
      _open.first.finish(outcome: SpeedOutcome.abandoned);
    }
    _open.add(span);
    return span;
  }

  /// The span the current code runs in (see [SpeedSpan.run]).
  static SpeedSpan? get currentSpan => Zone.current[_spanKey] as SpeedSpan?;

  /// The attempt number of [request] in [span]: 1 the first time, 2, 3...
  /// each time the same [request] comes again, 1 outside a span. [request]
  /// is whatever identifies one request: `SpeedHttpClient` passes the
  /// method, full URL and body length. It may hold ids, because the span
  /// keeps only a salted hash of it (see the library doc).
  static int nextAttempt(SpeedSpan? span, String request) =>
      span?._nextAttempt(request) ?? 1;

  void recordRequest(RequestRecord record) => requests.add(record);

  void _onFrames(List<FrameSample> batch) {
    for (final span in [..._open, ..._waitingForFrames]) {
      span._frames(batch);
    }
    // Frames come in order: one drawn after a span means all of the span's
    // frames are in.
    _waitingForFrames.removeWhere(
        (span) => batch.any((frame) => frame.start >= span._endedAt!));
    _stopWaiting();
  }

  void _close(SpeedSpan span) {
    _open.remove(span);
    spans.add(span);
    _waitingForFrames.add(span);
    if (_waitingForFrames.length > maxOpenSpans) _waitingForFrames.removeAt(0);
    _stopWaiting();
  }

  /// Drops the spans that waited [frameWait] for their frames, and stops
  /// listening when no span is left to take frames.
  void _stopWaiting() {
    final now = this.now();
    _waitingForFrames.removeWhere((span) => now - span._endedAt! > frameWait);
    if (_listening && _open.isEmpty && _waitingForFrames.isEmpty) {
      _listening = false;
      _frames.cancel();
    }
  }
}

extension on Stopwatch {
  Duration elapsedFrom() => elapsed;
}
