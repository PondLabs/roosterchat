@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/sync_trace.dart';

import 'fake_account.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

/// Counts how often the log starts listening for frames, and hands it a
/// frame drawn now whenever [draw] is called.
class _CountingFrames implements FrameSource {
  int listens = 0;
  Duration Function()? _clock;
  void Function(List<FrameSample> batch)? _onBatch;

  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {
    listens++;
    _clock = clock;
    _onBatch = onBatch;
  }

  @override
  void cancel() => _onBatch = null;

  void draw() {
    final now = _clock?.call();
    if (now == null) return;
    _onBatch?.call([FrameSample(now, now + const Duration(milliseconds: 4))]);
  }
}

List<String> _names(SpeedSpan span) => [for (final s in span.steps) s.name];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'each sync of an account is a span: request, response, processing, '
      'clean-up, next request', () async {
    // Logged in, the SDK's sync loop runs on its own, as in the app; the
    // fake server holds each long poll for 50 ms.
    final client = await fakeAccount('sync_span_test', FakeTransport());
    SpeedLog.instance.spans.clear();

    List<SpeedSpan> rounds() => [
          for (final span in SpeedLog.instance.spans.toList())
            if (span.name == SpeedOperation.sync) span
        ];
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (rounds().length < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final round = rounds().last;
    expect(round.outcome, SpeedOutcome.ok);
    expect(_names(round), [
      SpeedStep.response,
      SpeedStep.processing,
      SpeedStep.cleanUp,
      SpeedStep.nextRequest,
    ]);
    // The steps follow each other from the request to the next one.
    var end = Duration.zero;
    for (final step in round.steps) {
      expect(step.start, end, reason: step.name);
      end = step.start + step.duration!;
    }
    expect(round.duration, greaterThanOrEqualTo(end));
    // The long poll is the response step.
    expect(round.steps.first.duration,
        greaterThanOrEqualTo(const Duration(milliseconds: 50)));

    print(buildSpeedReport(SpeedLog.instance));

    final open = SpeedLog.instance.openSpans
        .where((s) => s.name == SpeedOperation.sync)
        .toList();
    await client.close();
    expect(open, isNotEmpty);
    expect(open.every((s) => s.isFinished), isTrue,
        reason: 'closing the client closes its round');
  });

  group('read from the SDK sync status', () {
    late StreamController<matrix.SyncStatusUpdate> statuses;
    late SpeedLog log;
    late SyncSpeedTrace trace;

    setUp(() {
      statuses = StreamController<matrix.SyncStatusUpdate>(sync: true);
      log = SpeedLog(frames: _NoFrames());
      trace = SyncSpeedTrace(statuses.stream, log: log);
    });

    void report(matrix.SyncStatus status, {double? progress}) =>
        statuses.add(matrix.SyncStatusUpdate(status, progress: progress));

    test('1000 rounds of one account listen for frames once', () {
      var now = Duration.zero;
      final frames = _CountingFrames();
      final log = SpeedLog(frames: frames, clock: () => now);
      final statuses = StreamController<matrix.SyncStatusUpdate>(sync: true);
      SyncSpeedTrace(statuses.stream, log: log);

      for (var i = 0; i < 1000; i++) {
        for (final status in [
          matrix.SyncStatus.waitingForResponse,
          matrix.SyncStatus.processing,
          matrix.SyncStatus.cleaningUp,
          matrix.SyncStatus.finished,
        ]) {
          statuses.add(matrix.SyncStatusUpdate(status));
          now += const Duration(milliseconds: 10);
          // Frames drawn all along, so the log never waits for any.
          frames.draw();
        }
        // Past the log's wait for a closed span's frames.
        now += SpeedLog.frameWait * 2;
        frames.draw();
      }

      expect(log.spans.length, SpeedLog.spansPerOperation);
      expect(frames.listens, 1);
    });

    test('a fake sync for a local echo does not end the wait for a response',
        () {
      report(matrix.SyncStatus.waitingForResponse);
      // A message sent during the long poll: the SDK's fake sync.
      report(matrix.SyncStatus.processing, progress: 1);
      expect(log.openSpans.single.steps, isEmpty);

      report(matrix.SyncStatus.processing);
      report(matrix.SyncStatus.processing, progress: 1);
      expect(_names(log.openSpans.single), [SpeedStep.response]);
    });

    test('a failed round is failed and keeps its back-off as next request', () {
      report(matrix.SyncStatus.waitingForResponse);
      report(matrix.SyncStatus.processing);
      report(matrix.SyncStatus.error);
      report(matrix.SyncStatus.waitingForResponse);

      final failed = log.spans.toList().single;
      expect(failed.outcome, SpeedOutcome.failed);
      expect(_names(failed),
          [SpeedStep.response, SpeedStep.error, SpeedStep.nextRequest]);
    });

    test('a round dropped before clean-up is incomplete', () {
      report(matrix.SyncStatus.waitingForResponse);
      report(matrix.SyncStatus.processing);
      report(matrix.SyncStatus.waitingForResponse);

      expect(log.spans.toList().single.outcome, SpeedOutcome.incomplete);
    });

    test('a round still going when the client closes is abandoned', () async {
      report(matrix.SyncStatus.waitingForResponse);
      await trace.dispose();

      expect(log.spans.toList().single.outcome, SpeedOutcome.abandoned);
      expect(log.openSpans, isEmpty);
    });
  });
}
