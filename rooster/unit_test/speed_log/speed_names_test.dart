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

  test('unlisted value names on one step are counted, not merged', () {
    final log = SpeedLog(frames: _NoFrames());
    final span = log.startSpan(SpeedOperation.textSend)
      ..mark(SpeedStep.request, values: {
        'alice': 70001,
        'bob': 90002,
        SpeedValue.status: 200,
      })
      ..mark(SpeedStep.answer, values: {'carol': 50003})
      ..finish();

    // The values of unlisted names are dropped: invalid_name says how many
    // there were.
    expect(span.steps[0].values, {invalidSpeedName: 2, SpeedValue.status: 200});
    expect(span.steps[1].values, {invalidSpeedName: 1});
    final report = buildSpeedReport(log);
    expect(report, contains(' invalid_name=2 status=200\n'));
    expect(report, contains(' invalid_name=1\n'));
    for (final word in ['alice', 'bob', 'carol']) {
      expect(report, isNot(contains(word)), reason: word);
    }
    // The dropped values, in any line but the span's own: its random id
    // (`op=`) is hexadecimal and could hold any digits.
    final lines =
        report.split('\n').where((line) => !line.contains('op=')).join('\n');
    for (final value in ['70001', '90002', '50003']) {
      expect(lines, isNot(contains(value)), reason: value);
    }
  });

  test(
      'the names the text send, sync, image_prepare and voice_join spans use '
      'are on the list', () {
    expect(SpeedOperation.all, {
      'text_send', 'sync', 'image_prepare', 'voice_join', 'file_send', //
      'media_show',
    });
    expect(SpeedStep.all, {
      'send', 'echo', 'echo_painted', 'queue_wait', 'request', 'retry', //
      'answer', 'server_wait', 'processing', 'clean_up', 'client_work', //
      'next_request', 'error',
      'header', 'decode', 'encode', // image_prepare (and queue_wait)
      // file_send (and echo, request, retry)
      'attached', 'preview_painted', 'prepared', 'upload', 'confirmed',
      // voice_join
      'leave_previous', 'output_device', 'foci', 'openid_token', 'sfu_token',
      'sfu_livekit_cloud', 'sfu_self_hosted', 'microphone_early',
      'prepare_connection', 'membership_clear_wait', 'membership_write',
      'connect', 'connect_websocket', 'connect_join_response', //
      'connect_media', 'microphone_options', 'microphone_open', 'sfu_region',
      'sfu_region_other', 'microphone_published', 'first_remote_audio',
      // media_show (and decode)
      'cache_hit', 'cache_miss', 'download', 'first_paint',
    });
    expect(SpeedValue.all, {
      'attempt', 'status', 'retry_after_ms', //
      'bytes', 'width', 'height', 'frames', // image_prepare
      'thumbnail_bytes', // file_send
      'level', // media_show
    });
    expect(SpeedOutcome.all,
        {'ok', 'failed', 'incomplete', 'abandoned', 'cancelled'});
    expect(SpeedError.all, {
      'aborted', 'cancelled', 'timeout', 'socket', 'tls', 'http', 'client',
      'other', //
      'upload_stalled', 'upload_no_answer', // a media upload's time limits
    });
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
