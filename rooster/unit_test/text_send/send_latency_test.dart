@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

import '../pending_media/matrix_fakes.dart' show composerSend;
import '../speed_log/fake_account.dart';
import 'text_send_fakes.dart';

/// How soon a text leaves after Send in a room without encryption and with
/// nothing ahead of it in the room's queue: from Send (the composer's
/// [composerSend], what the chat runs) to the `PUT /send` leaving, read
/// from the speed log's `request` step, on the SDK's fake homeserver (no
/// network). Three messages, one after the other; the median is printed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MatrixClient client;
  late MatrixRoom room;

  setUp(() async {
    TextSendTrace.nextFrameDrawn = () async => true;
    client = await fakeAccount('send_latency', FakeTransport());
    client.getMatrixClient().backgroundSync = false;
    await client.getMatrixClient().oneShotSync();
    room = await joinedRoom(client, encrypted: false);
    SpeedLog.instance.spans.clear();
  });

  tearDown(() => client.close());

  test('the PUT /send leaves under 50 ms after Send (median of 3)', () async {
    final leftAfter = <Duration>[];
    for (var i = 0; i < 3; i++) {
      expect(room.matrixRoom.sendingQueue, isEmpty, reason: 'queue empty');
      composerSend(room, message: 'Message ${i + 1}').send();
      final span = await _finished(i + 1);
      expect(span.outcome, SpeedOutcome.ok);
      leftAfter.add(
          span.steps.singleWhere((s) => s.name == SpeedStep.request).start);
    }
    final sorted = [...leftAfter]..sort();
    final median = sorted[1];
    String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
    // ignore: avoid_print
    print('Send to PUT /send leaving, ms: ${leftAfter.map(ms).join(', ')}; '
        'median ${ms(median)}');
    expect(median, lessThan(const Duration(milliseconds: 50)));
  });
}

/// The [count]th finished text_send span, once it is.
Future<SpeedSpan> _finished(int count) async {
  List<SpeedSpan> sends() => SpeedLog.instance.spans
      .toList()
      .where((s) => s.name == SpeedOperation.textSend)
      .toList();
  await until(() => sends().length >= count);
  return sends()[count - 1];
}
