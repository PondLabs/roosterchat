import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/speed_summary.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

void main() {
  test('300 sync rounds do not push a text send out of the log', () {
    var now = Duration.zero;
    final log = SpeedLog(frames: _NoFrames(), clock: () => now);

    final send = log.startSpan(SpeedOperation.textSend);
    now += const Duration(milliseconds: 120);
    send.mark(SpeedStep.request);
    send.finish();
    for (var i = 0; i < 300; i++) {
      final round = log.startSpan(SpeedOperation.sync);
      now += const Duration(seconds: 30);
      round.mark(SpeedStep.serverWait);
      round.finish();
    }

    final summary = {for (final o in summarizeSpeedLog(log)) o.name: o};
    expect(summary[SpeedOperation.textSend]?.ok, 1);
    // Each operation keeps its own newest spans.
    expect(summary[SpeedOperation.sync]?.finished, SpeedLog.spansPerOperation);

    final report = buildSpeedReport(log);
    expect(report, contains('text_send ok=1/1 p50=120ms p95=120ms'));
    expect(report, contains('text_send op=${send.id} total=120ms'));
    expect(log.spans.toList().first, send, reason: 'oldest first');
  });

  test('the finished spans take a fixed amount of memory', () {
    final log = SpeedLog(frames: _NoFrames());
    for (var round = 0; round < 3; round++) {
      // Every listed operation and many invented names, many spans each.
      for (final name in [
        ...SpeedOperation.all,
        for (var i = 0; i < SpeedLog.maxOperations + 4; i++) 'op_$i',
      ]) {
        for (var i = 0; i < SpeedLog.spansPerOperation + 10; i++) {
          log.startSpan(name).finish();
        }
      }
    }

    // The invented names all count as one operation, invalid_name.
    final operations = {...SpeedOperation.all, invalidSpeedName};
    expect(log.spans.operations.toSet(), operations);
    expect(log.spans.length, operations.length * SpeedLog.spansPerOperation);
    expect(log.spans.debugStorageSize,
        operations.length * SpeedLog.spansPerOperation);

    log.spans.clear();
    expect(log.spans.toList(), isEmpty);
  });
}
