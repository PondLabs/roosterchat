@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../speed_log/fake_account.dart';
import 'loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AttachmentSends.instance.clear());

  for (final (name, failure) in [
    (
      '500 M_UNKNOWN',
      () => json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'})
    ),
    (
      '403 M_FORBIDDEN',
      () => json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'})
    ),
  ]) {
    test(
        '"Retry" on a file whose PUT /send failed ($name) after its '
        'uploads: 0 new uploads, 1 event under the same transaction id',
        () async {
      final transport = LoopTransport()
        ..failSends = 1
        ..sendFailure = failure;
      final client =
          await fakeAccount('loop_retry_${name.hashCode}', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      final room = await plainRoom(client);
      final echoes = <matrix.Event>[];
      mx.onTimelineEvent.stream.listen(echoes.add);

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
      final uploads = transport.uploads.length;
      final first = transport.events.single;
      final seenBefore = transport.seen.length;

      await room.retrySend(room.convertEvent(failed));
      await until(() => send.isFinished);

      final again = transport.events.skip(1).toList();
      final routes = transport.seen.skip(seenBefore).toList();
      print('retry after PUT /send $name: uploads before $uploads, after '
          '${transport.uploads.length}; requests of the retry: $routes');
      expect(uploads, 2);
      expect(transport.uploads, hasLength(uploads), reason: 'no new upload');
      expect(again, hasLength(1));
      expect(again.single.txid, txid);
      expect(again.single.body['url'], first.body['url']);
      expect(again.single.body['info'], first.body['info']);
      expect(send.stage, AttachmentSendStage.sent);
      expect(room.matrixRoom.sendingFileUploads, isEmpty);
      await client.close();
    });
  }
}
