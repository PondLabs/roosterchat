import 'dart:async';

import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:test/test.dart';

/// Hands batches of frames to the log, already on its clock.
class _FakeFrames implements FrameSource {
  void Function(List<FrameSample>)? onBatch;
  int listens = 0;

  bool get listening => onBatch != null;

  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {
    listens++;
    this.onBatch = onBatch;
  }

  @override
  void cancel() => onBatch = null;

  void deliver(List<FrameSample> batch) => onBatch!(batch);
}

/// A frame drawn from [startMs] to [endMs] on the log's clock.
FrameSample _frame(int startMs, int endMs) =>
    FrameSample(Duration(milliseconds: startMs), Duration(milliseconds: endMs));

void main() {
  test('steps are timed on a monotonic clock', () async {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('text_send');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    span.mark('echo_painted');
    await span.time('request', () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, values: {'status': 200});
    span.finish();

    final echo = span.steps[0];
    final request = span.steps[1];
    expect(echo.name, 'echo_painted');
    expect(echo.start, Duration.zero);
    expect(echo.duration!.inMilliseconds, greaterThanOrEqualTo(30));
    expect(request.name, 'request');
    expect(request.start, greaterThanOrEqualTo(echo.duration!));
    expect(request.duration!.inMilliseconds, greaterThanOrEqualTo(50));
    expect(request.values, {'status': 200});
    expect(
        span.duration, greaterThanOrEqualTo(request.start + request.duration!));
    expect(log.spans.toList(), [span]);
    expect(log.openSpans, isEmpty);
  });

  test('a step that cannot be timed is unavailable, not guessed', () {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('text_send')..unavailable('answer');
    span.finish();

    expect(span.steps.single.available, isFalse);
    expect(span.steps.single.duration, isNull);
    expect(buildSpeedReport(log), contains('  answer unavailable'));
  });

  test('each span gets a different random id', () {
    final log = SpeedLog(frames: _FakeFrames());
    final ids = {for (var i = 0; i < 200; i++) log.startSpan('sync').id};
    expect(ids, hasLength(200));
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{16}$').hasMatch(id)), isTrue);
  });

  test('keeps the longest frame drawn while the span was open', () {
    var now = Duration.zero;
    final frames = _FakeFrames();
    final log = SpeedLog(frames: frames, clock: () => now);
    final first = log.startSpan('text_send');
    now = const Duration(milliseconds: 100);
    final second = log.startSpan('sync');
    now = const Duration(milliseconds: 200);
    first.finish();
    now = const Duration(milliseconds: 300);
    second.finish();
    frames.deliver([
      _frame(10, 22), // 12 ms, first only
      _frame(150, 198), // 48 ms, both
      _frame(220, 290), // 70 ms, second only
      _frame(400, 405), // after both: they stop waiting
    ]);

    expect(frames.listens, 1);
    expect(frames.listening, isFalse, reason: 'no span waits, no listening');
    expect(first.longestFrame, const Duration(milliseconds: 48));
    expect(second.longestFrame, const Duration(milliseconds: 70));
  });

  test(
      'frames arrive in batches: only those drawn during the span count, and '
      'a span closed before its batch gets it when it comes', () {
    var now = Duration.zero;
    final frames = _FakeFrames();
    final log = SpeedLog(frames: frames, clock: () => now);
    now = const Duration(milliseconds: 1000);
    final span = log.startSpan('text_send');
    // A batch while the span is open, with a frame from before it.
    now = const Duration(milliseconds: 1100);
    frames.deliver([_frame(900, 990), _frame(1010, 1030)]);
    now = const Duration(milliseconds: 1200);
    span.finish();
    expect(span.longestFrame, const Duration(milliseconds: 20));
    expect(frames.listening, isTrue, reason: 'its last frames are not in yet');

    // The next batch, a second later: inside, then after the span.
    now = const Duration(milliseconds: 2100);
    frames.deliver([
      _frame(1150, 1195), // 45 ms, inside
      _frame(1190, 1260), // 70 ms, began inside, counts
      _frame(1300, 1400), // 100 ms, after the span
    ]);
    expect(span.longestFrame, const Duration(milliseconds: 70));
    expect(frames.listening, isFalse);
    expect(buildSpeedReport(log), contains('longest_frame=70ms'));
  });

  test('a closed span stops waiting for frames that never come', () {
    var now = Duration.zero;
    final frames = _FakeFrames();
    final log = SpeedLog(frames: frames, clock: () => now);
    final first = log.startSpan('sync');
    now = const Duration(milliseconds: 10);
    first.finish();
    expect(frames.listening, isTrue);

    // No batch for longer than the wait: the next span drops the first.
    now += SpeedLog.frameWait + const Duration(milliseconds: 1);
    final second = log.startSpan('sync')..finish();
    now += SpeedLog.frameWait + const Duration(milliseconds: 1);
    // A late batch, with a frame drawn during the first span only.
    frames.deliver([_frame(5, 9)]);

    expect(frames.listening, isFalse);
    expect(first.longestFrame, isNull);
    expect(second.longestFrame, isNull);
  });

  test('without frames the longest frame is unavailable', () {
    // The default source, with no Flutter binding in a plain unit test.
    final log = SpeedLog();
    final span = log.startSpan('sync')..finish();

    expect(span.longestFrame, isNull);
    expect(buildSpeedReport(log), contains('longest_frame=unavailable'));
  });

  test('a name that is not a fixed identifier is not kept', () {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('Send to @alice:example.org')
      ..mark('photo.jpg', values: {'File Name': 1})
      ..finish(outcome: 'failed: !room:example.org');

    final report = buildSpeedReport(log);
    expect(report, isNot(contains('@')));
    expect(report, isNot(contains('example.org')));
    expect(report, isNot(contains('alice')));
    expect(report, isNot(contains('photo')));
    expect(span.name, 'invalid_name');
    expect(span.steps.single.name, 'invalid_name');
    expect(span.steps.single.values.keys.single, 'invalid_name');
    expect(span.outcome, 'invalid_name');
  });

  test('a span with no finish does not stay open forever', () {
    final log = SpeedLog(frames: _FakeFrames());
    final first = log.startSpan('sync');
    for (var i = 0; i < SpeedLog.maxOpenSpans; i++) {
      log.startSpan('sync');
    }
    expect(first.outcome, 'abandoned');
    expect(log.openSpans, hasLength(SpeedLog.maxOpenSpans));
  });

  test('run links the code inside to the span through async gaps', () async {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('text_send');
    SpeedSpan? seen;
    await span.run(() async {
      await Future<void>.delayed(Duration.zero);
      seen = SpeedLog.currentSpan;
    });
    expect(seen, same(span));
    expect(SpeedLog.currentSpan, isNull);
    expect(SpeedLog.nextAttempt(span, 'PUT /send/t1'), 1);
    expect(SpeedLog.nextAttempt(span, 'PUT /send/t1'), 2);
    expect(SpeedLog.nextAttempt(span, 'PUT /send/t2'), 1);
    expect(SpeedLog.nextAttempt(null, 'PUT /send/t1'), 1);
  });
}
