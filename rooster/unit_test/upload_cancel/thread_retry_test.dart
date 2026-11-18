@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../upload_loop/loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test(
      '"Retry" on a file of a thread that failed before any upload went '
      'through sends its event in the thread', () async {
    final transport = LoopTransport();
    var refused = false;
    transport.onUpload = (body, _) async {
      if (!refused) {
        refused = true;
        return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      }
      return transport.accept(body);
    };
    final (mx, room) =
        await loopClient('thread_retry', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final send = AttachmentSend(roomKey: 'test:$roomId', attachment: null);
    final file = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
    expect(
        await sendMatrixFile(room, TrackedMatrixAttachment(file, send),
            threadRootEventId: r'$root', threadLastEventId: r'$last'),
        isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final txid = send.transactionId!;
    expect(room.sendingFileUploads[txid], isNull, reason: 'nothing went up');
    final failed = echoes.lastWhere((e) => e.eventId == txid);

    expect(await retryMatrixFile(failed, send), isNotNull);
    final relation = transport.events.single.body['m.relates_to'];
    print('Retry in a thread: uploads ${transport.uploads.length}, '
        'relation $relation');
    expect(relation, {
      'event_id': r'$root',
      'rel_type': matrix.RelationshipTypes.thread,
      'is_falling_back': true,
      'm.in_reply_to': {'event_id': r'$last'},
    });
    await mx.dispose(closeDatabase: true);
  });
}
