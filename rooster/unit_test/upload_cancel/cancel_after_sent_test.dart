@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../speed_log/fake_account.dart';
import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test(
      '"Cancel" from a menu opened during the upload, tapped after the '
      'server took the event: the message stays in the timeline and the '
      'database, with one PUT /send (probe F)', () async {
    final transport = CancelTransport()..holdUploads = true;
    final client = await fakeAccount('cancel_after_sent', transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    final room = await plainRoom(client);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final cancelled = <String>[];
    mx.onCancelSendEvent.stream.listen(cancelled.add);
    final timeline = await room.matrixRoom.getTimeline();
    bool shown(String txid) => timeline.events
        .any((e) => e.eventId == txid || e.transactionId == txid);

    final send = AttachmentSend(roomKey: room.localId, attachment: null);
    AttachmentSends.instance.add(send);
    final file = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
    final sending =
        sendMatrixFile(room.matrixRoom, TrackedMatrixAttachment(file, send));
    await until(() => transport.open == 1);
    final txid = send.transactionId!;
    // The menu opens here, on the event of this moment.
    final menuEvent = echoes.lastWhere((e) => e.eventId == txid);
    expect(room.matrixRoom.canCancelSend(txid), isTrue);

    transport.releaseUploads.complete();
    final id = await sending;
    expect(id, isNotNull);
    // The sync brings the event back, as the server does.
    final sent = echoes.lastWhere((e) => e.eventId == id);
    await mx.handleSync(matrix.SyncUpdate(
      nextBatch: 'echo',
      rooms: matrix.RoomsUpdate(join: {
        room.matrixRoom.id: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(events: [
          matrix.MatrixEvent(
            type: sent.type,
            content: sent.content,
            eventId: id!,
            senderId: mx.userID!,
            originServerTs: DateTime.now(),
            unsigned: {'transaction_id': txid},
          ),
        ])),
      }),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(room.matrixRoom.canCancelSend(txid), isFalse,
        reason: 'its PUT /send left: never cancellable again');

    // "Cancel" on the menu opened before.
    await room.cancelSend(room.convertEvent(menuEvent));
    await expectLater(menuEvent.cancelSend(), throwsException);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final stored = await mx.database.getEventById(id, room.matrixRoom);
    print('Cancel after the send ended: in the timeline ${shown(txid)}, in '
        'the database ${stored != null}, PUT /send '
        '${transport.events.length}, cancel events $cancelled');
    expect(shown(txid), isTrue);
    expect(stored, isNotNull);
    expect(transport.events, hasLength(1));
    expect(cancelled, isEmpty);
    expect(room.matrixRoom.isSendCancelled(txid), isFalse);
    await client.close();
  });
}
