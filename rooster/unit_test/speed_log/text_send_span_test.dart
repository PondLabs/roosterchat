@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

import 'fake_account.dart';

/// A measurement that throws in both of the room's calls.
class _ThrowingTrace extends TextSendTrace {
  _ThrowingTrace(super.span) : super.forTest();

  final List<String> calls = [];

  @override
  void sending(matrix.Room room, String txid) {
    calls.add('sending');
    throw StateError('sending');
  }

  @override
  void sent({required bool ok}) {
    calls.add('sent');
    throw StateError('sent');
  }
}

const _sendRoute =
    'PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTransport transport;
  late MatrixClient client;
  late MatrixRoom room;

  setUp(() async {
    // A frame is drawn 5 ms after it is asked for.
    TextSendTrace.nextFrameDrawn =
        () => Future.delayed(const Duration(milliseconds: 5), () => true);
    transport = FakeTransport();
    client = await fakeAccount('text_send_test', transport);
    // Only the send talks to the server while it runs: the SDK's sync loop
    // stops after the round in flight.
    client.getMatrixClient().backgroundSync = false;
    await client.getMatrixClient().oneShotSync();
    room = await plainRoom(client);
    SpeedLog.instance.requests.clear();
    SpeedLog.instance.spans.clear();
    transport.seen.clear();
  });

  tearDown(() => client.close());

  /// Sends [text] the way the composer does, and returns its span.
  Future<SpeedSpan> sendText(String text) async {
    final trace = TextSendTrace.forComposer(
        sendPressed: TextSendTrace.now(), message: text, hasAttachments: false);
    await TextSendTrace.send(trace, () => room.sendMessage(message: text));
    return trace!.span;
  }

  test('a text send is a span from Send to the answer', () async {
    final span = await sendText('Hello');

    expect(span.name, SpeedOperation.textSend);
    expect(span.outcome, SpeedOutcome.ok);
    expect(span.steps.map((s) => s.name), [
      SpeedStep.send,
      SpeedStep.echo,
      SpeedStep.echoPainted,
      SpeedStep.queueWait,
      SpeedStep.request,
      SpeedStep.answer,
    ]);
    expect(span.steps.every((s) => s.available), isTrue,
        reason: buildSpeedReport(SpeedLog.instance));
    final request = span.steps.firstWhere((s) => s.name == SpeedStep.request);
    expect(request.values, {SpeedValue.attempt: 1, SpeedValue.status: 200});
    // Steps follow each other on the span's clock.
    final echo = span.steps[1];
    final answer = span.steps.last;
    expect(echo.start, span.steps.first.duration);
    // The echo is the pending message, shown before the request leaves;
    // not the sent one the SDK shows after the answer.
    expect(echo.start + echo.duration!, lessThanOrEqualTo(request.start));
    expect(
        answer.start, greaterThanOrEqualTo(request.start + request.duration!));
    expect(
        span.duration, greaterThanOrEqualTo(answer.start + answer.duration!));
    print(buildSpeedReport(SpeedLog.instance));
  });

  test('a 429 with retry_after_ms is a new attempt that shows the value',
      () async {
    transport
      ..throttleSends = 1
      ..retryAfterMs = 30;

    final span = await sendText('Hello again');

    final sends = span.steps
        .where((s) => s.name == SpeedStep.request || s.name == SpeedStep.retry)
        .toList();
    expect(sends.map((s) => s.name), [SpeedStep.request, SpeedStep.retry]);
    expect(sends[0].values, {
      SpeedValue.attempt: 1,
      SpeedValue.status: 429,
      SpeedValue.retryAfterMs: 30,
    });
    expect(sends[1].values, {SpeedValue.attempt: 2, SpeedValue.status: 200});
    // The SDK waited the 30 ms it was told to before the new attempt.
    expect(sends[1].start - sends[0].start,
        greaterThanOrEqualTo(const Duration(milliseconds: 30)));
    expect(span.outcome, SpeedOutcome.ok);

    final report = buildSpeedReport(SpeedLog.instance);
    expect(report, contains('status=429 attempt=1 op=${span.id}'));
    expect(report, contains('retry_after_ms=30'));
    expect(report, contains('status=200 attempt=2 op=${span.id}'));
    expect(report,
        matches(RegExp(r'\n  retry \+\d+\.?\d*ms \S+ attempt=2 status=200\n')));
    print(report);
  });

  test('text in an unencrypted room makes one PUT /send and nothing else',
      () async {
    expect(room.matrixRoom.encrypted, isFalse);

    final span = await sendText('Just one request');

    final ofSpan = SpeedLog.instance.requests
        .toList()
        .where((r) => r.operationId == span.id)
        .map((r) => '${r.method} ${r.route}')
        .toList();
    expect(ofSpan, [_sendRoute]);
    // Nothing else reached the server while the send ran, from any zone.
    expect(transport.seen, [_sendRoute]);
  });

  test('a send the SDK gives up on is a failed span', () async {
    // Rate limited for longer than the SDK waits (a minute): it gives up.
    transport
      ..throttleSends = 1
      ..retryAfterMs = 120000;

    final span = await sendText('Not this time');

    expect(span.outcome, SpeedOutcome.failed);
    expect(span.steps.where((s) => s.name == SpeedStep.request).single.values,
        containsPair(SpeedValue.status, 429));
  });

  test('without an observable frame the echo is not said to be painted',
      () async {
    TextSendTrace.nextFrameDrawn = () async => false;

    final span = await sendText('Hidden window');

    final painted =
        span.steps.singleWhere((s) => s.name == SpeedStep.echoPainted);
    expect(painted.available, isFalse);
    expect(span.steps.singleWhere((s) => s.name == SpeedStep.echo).available,
        isTrue);
  });

  test('a measurement that throws never stops the send', () async {
    final trace =
        _ThrowingTrace(SpeedLog.instance.startSpan(SpeedOperation.textSend));
    Object? sent;

    await TextSendTrace.send(trace, () async {
      return sent = await room.sendMessage(message: 'Sent all the same');
    });

    expect(trace.calls, ['sending', 'sent']);
    expect(transport.seen, [_sendRoute]);
    expect(sent, isNotNull, reason: 'the send returns the sent event');
  });

  test('a message with attachments or no text is not a text send', () {
    expect(
        TextSendTrace.forComposer(
            sendPressed: Duration.zero, message: 'hi', hasAttachments: true),
        isNull);
    expect(
        TextSendTrace.forComposer(
            sendPressed: Duration.zero, message: '  ', hasAttachments: false),
        isNull);
  });
}
