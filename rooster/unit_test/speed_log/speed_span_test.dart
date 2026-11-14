import 'dart:async';

import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:test/test.dart';

class _FakeFrames implements FrameSource {
  void Function(Duration)? onFrame;
  int listens = 0;

  @override
  void listen(void Function(Duration frame) onFrame) {
    listens++;
    this.onFrame = onFrame;
  }

  @override
  void cancel() => onFrame = null;
}

void main() {
  test('steps are timed on a monotonic clock', () async {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('text_send');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    span.mark('echo_painted');
    await span.time('request', () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, values: {'bytes': 120});
    span.finish();

    final echo = span.steps[0];
    final request = span.steps[1];
    expect(echo.name, 'echo_painted');
    expect(echo.start, Duration.zero);
    expect(echo.duration!.inMilliseconds, greaterThanOrEqualTo(30));
    expect(request.name, 'request');
    expect(request.start, greaterThanOrEqualTo(echo.duration!));
    expect(request.duration!.inMilliseconds, greaterThanOrEqualTo(50));
    expect(request.values, {'bytes': 120});
    expect(
        span.duration, greaterThanOrEqualTo(request.start + request.duration!));
    expect(log.spans.toList(), [span]);
    expect(log.openSpans, isEmpty);
  });

  test('a step that cannot be timed is unavailable, not guessed', () {
    final log = SpeedLog(frames: _FakeFrames());
    final span = log.startSpan('voice_join')..unavailable('server_queue');
    span.finish();

    expect(span.steps.single.available, isFalse);
    expect(span.steps.single.duration, isNull);
    expect(buildSpeedReport(log), contains('  server_queue unavailable'));
  });

  test('each span gets a different random id', () {
    final log = SpeedLog(frames: _FakeFrames());
    final ids = {for (var i = 0; i < 200; i++) log.startSpan('sync').id};
    expect(ids, hasLength(200));
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{16}$').hasMatch(id)), isTrue);
  });

  test('keeps the longest frame drawn while the span was open', () {
    final frames = _FakeFrames();
    final log = SpeedLog(frames: frames);
    final first = log.startSpan('file_send');
    frames.onFrame!(const Duration(milliseconds: 12));
    final second = log.startSpan('text_send');
    frames.onFrame!(const Duration(milliseconds: 48));
    first.finish();
    frames.onFrame!(const Duration(milliseconds: 70));
    second.finish();

    expect(frames.listens, 1);
    expect(frames.onFrame, isNull, reason: 'no span open, no listening');
    expect(first.longestFrame, const Duration(milliseconds: 48));
    expect(second.longestFrame, const Duration(milliseconds: 70));
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
    expect(SpeedLog.nextAttempt(span, 'PUT /send'), 1);
    expect(SpeedLog.nextAttempt(span, 'PUT /send'), 2);
    expect(SpeedLog.nextAttempt(null, 'PUT /send'), 1);
  });
}
