import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

void main() {
  test('a name that is not on the fixed list is written invalid_name', () {
    final log = SpeedLog(frames: _NoFrames());
    // Lowercase words, shaped like the names in the code.
    final span = log.startSpan('holiday')
      ..mark('lisbon', values: {'alice': 1})
      ..unavailable('beach')
      ..finish(outcome: 'alice');

    expect(span.name, invalidSpeedName);
    expect(span.steps.map((s) => s.name), [invalidSpeedName, invalidSpeedName]);
    expect(span.steps.first.values.keys, [invalidSpeedName]);
    expect(span.outcome, invalidSpeedName);
    final report = buildSpeedReport(log);
    for (final word in ['holiday', 'lisbon', 'alice', 'beach']) {
      expect(report, isNot(contains(word)), reason: word);
    }

    // A listed name passes as it is.
    final send = log.startSpan(SpeedOperation.textSend)
      ..mark(SpeedStep.request, values: {SpeedValue.status: 200})
      ..finish(outcome: SpeedOutcome.failed);
    expect(send.name, 'text_send');
    expect(send.steps.single.name, 'request');
    expect(send.steps.single.values, {'status': 200});
    expect(send.outcome, 'failed');
  });

  test(
      'the names the text send, sync and image_prepare spans use are on '
      'the list', () {
    expect(SpeedOperation.all, {'text_send', 'sync', 'image_prepare'});
    expect(SpeedStep.all, {
      'send', 'echo', 'echo_painted', 'queue_wait', 'request', 'retry', //
      'answer', 'response', 'processing', 'clean_up', 'next_request', 'error',
      'header', 'decode', 'encode', // image_prepare (and queue_wait)
    });
    expect(SpeedValue.all, {
      'attempt', 'status', 'retry_after_ms', //
      'bytes', 'width', 'height', 'frames', // image_prepare
    });
    expect(SpeedOutcome.all, {'ok', 'failed', 'incomplete', 'abandoned'});
  });

  test('every listed name is a fixed identifier, and the operations fit', () {
    final identifier = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
    for (final name in [
      ...SpeedOperation.all,
      ...SpeedStep.all,
      ...SpeedValue.all,
      ...SpeedOutcome.all,
      ...SpeedError.all,
      invalidSpeedName,
    ]) {
      expect(identifier.hasMatch(name), isTrue, reason: name);
    }
    // invalid_name takes one more operation in the finished spans.
    expect(SpeedOperation.all.length + 1,
        lessThanOrEqualTo(SpeedLog.maxOperations));
  });
}
