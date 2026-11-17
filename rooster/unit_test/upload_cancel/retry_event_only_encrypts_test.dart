@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  test(
      '"Retry" that sends only the event of a file uploaded in the clear, '
      'and the room starts encrypting while that event waits in the queue: '
      'no encrypted event points to the clear upload, and the next Retry '
      'uploads the file again, encrypted (probe H)',
      skip: skipWithoutVodozemac, () async {
    final transport = OnlyUsTransport()..failSends = 1;
    final (mx, room) =
        await cryptoClient('retry_event_only', transport, encrypted: false);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    // Uploaded in the clear, its PUT /send refused.
    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.content['url'], isA<String>());
    expect(isUploadedFileEvent(failed), isTrue, reason: 'only the event goes');
    final uploadsBefore = transport.uploads.length;

    // A text in front, its PUT /send held: the Retry's event waits behind.
    transport.holdSend = Completer<void>();
    final inFront = room
        .sendEvent({'msgtype': 'm.text', 'body': 'front'}, txid: 'txn_front');
    await until(() => transport.sendsArrived == 2);
    final retrying = retryMatrixFile(failed, send);
    await until(() => room.sendingQueue.length == 2);
    await turnOnEncryption(mx);
    transport.holdSend!.complete();
    final id = await retrying;
    await inFront;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final fileEvents = <String>[];
    for (final sent in transport.events.skip(1)) {
      if (sent.txid != txid) continue;
      final event = sent.type == matrix.EventTypes.Encrypted
          ? await decryptSent(mx, room, sent)
          : null;
      fileEvents.add(event == null
          ? 'plain'
          : event.content['url'] != null
              ? 'ENCRYPTED with a clear url'
              : 'encrypted with file');
    }
    print('Retry of the event only, room encrypted meanwhile: id $id, file '
        'events $fileEvents, new uploads '
        '${transport.uploads.length - uploadsBefore}, stage ${send.stage}');
    expect(id, isNull);
    expect(fileEvents, isEmpty);
    expect(send.stage, AttachmentSendStage.failed);

    // The next Retry: the clear upload is not reused, the file goes again.
    final failedAgain = echoes.lastWhere((e) => e.eventId == txid);
    final again = await retryMatrixFile(failedAgain, send);
    final sent = transport.events.last;
    final event = await decryptSent(mx, room, sent);
    final file = event.content['file'] as Map<String, dynamic>;
    print('next Retry: id $again, event ${sent.type}, url '
        '${event.content['url']}, uploads in the clear '
        '${clearUploads(transport.uploads)} of ${transport.uploads.length}');
    expect(again, isNotNull);
    expect(event.content['url'], isNull);
    expect(
        await decryptUpload(
            file, transport.uploadsByUri[file['url'] as String]!),
        Uint8List.fromList(List.filled(fileBytes, 1)));
    expect(clearUploads(transport.uploads),
        clearUploads(transport.uploads.take(uploadsBefore).toList()),
        reason: 'nothing more in the clear');
    await mx.dispose(closeDatabase: true);
  });
}
