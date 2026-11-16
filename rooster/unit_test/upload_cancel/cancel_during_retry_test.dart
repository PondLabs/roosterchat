@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../speed_log/fake_account.dart';
import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

/// Uploads where the first thumbnail is refused (the message fails with
/// its file kept) and the second waits for [hold].
void _thumbnailRefusedThenHeld(LoopTransport transport, Completer<void> hold) {
  var thumbnails = 0;
  transport.onUpload = (body, attempt) async {
    if (body.length == thumbnailBytes) {
      thumbnails++;
      if (thumbnails == 1) {
        return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      }
      if (thumbnails == 2) await hold.future;
    }
    return transport.accept(body);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  test(
      'through the app: Cancel on a failed file while its "Retry" uploads: '
      'no event after the Cancel, and the message is gone (probe P4)',
      () async {
    final transport = LoopTransport();
    final hold = Completer<void>();
    _thumbnailRefusedThenHeld(transport, hold);
    final client = await fakeAccount('cancel_retry_app', transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    final room = await plainRoom(client);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final cancelled = <String>[];
    mx.onCancelSendEvent.stream.listen(cancelled.add);

    final send = AttachmentSend(roomKey: room.localId, attachment: null);
    AttachmentSends.instance.add(send);
    final file = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
    final thumbnail = matrix.MatrixImageFile(
        bytes: Uint8List.fromList(List.filled(thumbnailBytes, 2)),
        name: 'a.jpg',
        mimeType: 'image/jpeg');
    expect(
        await sendMatrixFile(room.matrixRoom,
            TrackedMatrixAttachment(file, send, thumbnailFile: thumbnail)),
        isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.status.isError, isTrue);

    final retry = room.retrySend(room.convertEvent(failed));
    await until(() => transport.open == 1);
    // The menu was opened on the failed message: its Cancel.
    await room.cancelSend(room.convertEvent(failed));
    final shownAfterCancel = echoes.length;
    hold.complete();
    await retry;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    print('P4 Cancel during a Retry: uploads ${transport.uploads.length}, '
        'PUT /send ${transport.events.length}, held files '
        '${room.matrixRoom.sendingFilePlaceholders.length}, kept '
        '${room.matrixRoom.sendingFileUploads.length}, followed sends '
        '${AttachmentSends.instance.all.length}');
    expect(transport.events, isEmpty);
    expect(
        echoes.skip(shownAfterCancel).where((e) => e.eventId == txid), isEmpty);
    expect(cancelled, contains(txid));
    expect(await goneFrom(room.matrixRoom, txid), isTrue);
    expect(AttachmentSends.instance.all, isEmpty);
    await client.close();
  });

  test(
      'in an encrypted room: Cancel in the middle of a "Retry" sends no '
      'event, and nothing went up in the clear (probe R5)',
      skip: skipWithoutVodozemac, () async {
    final transport = OnlyUsTransport();
    final hold = Completer<void>();
    _thumbnailRefusedThenHeld(transport, hold);
    final (mx, room) =
        await cryptoClient('cancel_retry_crypto', transport, encrypted: true);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);

    final retrying = retryMatrixFile(failed, send);
    await until(() => transport.open == 1);
    await failed.cancelSend();
    hold.complete();
    final id = await retrying;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    print('R5 Cancel during a Retry, encrypted room: id $id; uploads '
        '${transport.uploads.length}, in the clear '
        '${clearUploads(transport.uploads)}; events '
        '${transport.events.length}');
    expect(id, isNull);
    expect(transport.events, isEmpty);
    expect(clearUploads(transport.uploads), 0);
    expect(await goneFrom(room, txid), isTrue);
    await mx.dispose(closeDatabase: true);
  });
}
