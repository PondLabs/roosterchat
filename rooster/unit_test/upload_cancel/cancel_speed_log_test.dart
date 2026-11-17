@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

import '../speed_log/fake_account.dart';
import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

/// A cancelled send is timed as `cancelled` in the speed log, not as a
/// failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CancelTransport transport;
  late MatrixClient client;
  late MatrixRoom room;
  final echoes = <matrix.Event>[];

  setUp(() async {
    TextSendTrace.nextFrameDrawn = () async => false;
    transport = CancelTransport();
    client = await fakeAccount('cancel_speed_log', transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    echoes.clear();
    mx.onTimelineEvent.stream.listen(echoes.add);
    SpeedLog.instance.spans.clear();
  });

  tearDown(() async {
    AttachmentSends.instance.clear();
    await client.close();
  });

  test('a file cancelled during its upload: file_send ends as cancelled',
      () async {
    transport.holdUploads = true;
    final trace = FileSendTrace.start(sendPressed: FileSendTrace.now());
    final send =
        AttachmentSend(roomKey: room.localId, attachment: null, trace: trace);
    AttachmentSends.instance.add(send);
    final file = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
    final sending =
        sendMatrixFile(room.matrixRoom, TrackedMatrixAttachment(file, send));
    await until(() => transport.open == 1);
    final pending = echoes.lastWhere((e) => e.eventId == send.transactionId);

    await room.cancelSend(room.convertEvent(pending));
    expect(await sending, isNull);

    print('file_send of a cancelled file: ${trace.span.outcome}');
    expect(trace.span.isFinished, isTrue);
    expect(trace.span.outcome, SpeedOutcome.cancelled);
  });

  test('a text cancelled in the queue: text_send ends as cancelled', () async {
    final hold = Completer<void>();
    transport.holdNextSend = hold.future;
    final inFront = room.sendMessage(message: 'in front');
    await until(() => transport.events.length == 1);

    final trace = TextSendTrace.forComposer(
        sendPressed: TextSendTrace.now(),
        message: 'cancelled',
        hasAttachments: false)!;
    final traced =
        TextSendTrace.send(trace, () => room.sendMessage(message: 'cancelled'));
    await until(() => room.matrixRoom.sendingQueue.length == 2);
    final queued = echoes.lastWhere((e) => e.body == 'cancelled');

    await room.cancelSend(room.convertEvent(queued));
    await traced;
    hold.complete();
    await inFront;

    print('text_send of a cancelled text: ${trace.span.outcome}');
    expect(trace.span.isFinished, isTrue);
    expect(trace.span.outcome, SpeedOutcome.cancelled);
  });
}
