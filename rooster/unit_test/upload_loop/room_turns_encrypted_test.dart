@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import 'encrypted_fakes.dart';
import 'loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  /// A file message sent in a plain room through [transport], failed; the
  /// room then starts encrypting. Its client, room, send and failed event.
  Future<(matrix.Client, matrix.Room, AttachmentSend, matrix.Event)>
      failedThenEncrypted(String name, OnlyUsTransport transport) async {
    final (mx, room) = await cryptoClient(name, transport, encrypted: false);
    final echoes = <matrix.Event>[];
    final listening = mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await listening.cancel();
    final failed = echoes.lastWhere((e) => e.eventId == send.transactionId);
    expect(failed.status.isError, isTrue);
    await turnOnEncryption(mx);
    expect(room.encrypted, isTrue);
    return (mx, room, send, failed);
  }

  /// The event "Retry" sent, decrypted: its file must be the encrypted one
  /// and decrypt, from what the transport received, to the file's bytes.
  Future<void> expectEncryptedFile(
      matrix.Client mx, matrix.Room room, OnlyUsTransport transport) async {
    final sent = transport.events.last;
    expect(sent.type, matrix.EventTypes.Encrypted);
    final event = await decryptSent(mx, room, sent);
    expect(event.content['url'], isNull, reason: 'no upload in the clear');
    final file = event.content['file'] as Map<String, dynamic>;
    final upload = transport.uploadsByUri[file['url'] as String]!;
    expect(
        await decryptUpload(file, upload), List.filled(fileBytes, 1).toList());
    final info = event.content['info'] as Map;
    expect(info['thumbnail_url'], isNull);
    expect(info['thumbnail_file'], isA<Map>());
  }

  test(
      'uploads done in a plain room, PUT /send failed, the room turns '
      'encrypted: "Retry" uploads the file again, encrypted, and the '
      'encrypted event never points to the upload in the clear',
      skip: skipWithoutVodozemac, () async {
    final transport = OnlyUsTransport()..failSends = 1;
    final (mx, room, send, failed) =
        await failedThenEncrypted('turns_encrypted_sent', transport);
    expect(transport.uploads, hasLength(2));
    expect(isUploadedFileEvent(failed), isFalse,
        reason: 'its url is an upload in the clear');

    expect(await retryMatrixFile(failed, send), isNotNull);

    print('room turned encrypted after PUT /send failed: uploads '
        '${transport.uploads.length} (2 before), clear ones '
        '${clearUploads(transport.uploads.skip(2).toList())} after Retry; '
        'event ${transport.events.last.type}');
    expect(transport.uploads, hasLength(4));
    expect(clearUploads(transport.uploads.skip(2).toList()), 0);
    await expectEncryptedFile(mx, room, transport);
    expect(send.stage, AttachmentSendStage.sent);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'the file kept from a plain room is let go once the room encrypts: '
      'it goes up again, encrypted, with the thumbnail',
      skip: skipWithoutVodozemac, () async {
    final transport = OnlyUsTransport();
    transport.onUpload = (body, attempt) async {
      if (body.length == thumbnailBytes && attempt == 1) {
        return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      }
      return transport.accept(body);
    };
    final (mx, room, send, failed) =
        await failedThenEncrypted('turns_encrypted_kept', transport);
    expect(room.sendingFileUploads[send.transactionId]!.keys,
        [matrix.FileSendPart.file]);

    expect(await retryMatrixFile(failed, send), isNotNull);

    print('kept file from a plain room: file uploads '
        '${transport.uploadsOf(fileBytes)}, thumbnail uploads '
        '${transport.uploadsOf(thumbnailBytes)}');
    expect(transport.uploadsOf(fileBytes), 2);
    expect(clearUploads(transport.uploads.skip(2).toList()), 0);
    await expectEncryptedFile(mx, room, transport);
    await mx.dispose(closeDatabase: true);
  });
}
