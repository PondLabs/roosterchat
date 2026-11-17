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

/// The room's encryption state, set at once (no sync round).
void _encryptNow(matrix.Room room) => room.setState(matrix.StrippedStateEvent(
      type: matrix.EventTypes.Encryption,
      stateKey: '',
      senderId: room.client.userID!,
      content: {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2},
    ));

/// What the event [sent] says about its file: `plain`, `encrypted file`,
/// or `ENCRYPTED url` (an encrypted event pointing to a clear upload).
Future<String> _eventSays(matrix.Client mx, matrix.Room room,
    ({String type, String txid, Map<String, dynamic> body}) sent) async {
  if (sent.type != matrix.EventTypes.Encrypted) return 'plain';
  final event = await decryptSent(mx, room, sent);
  return event.content['url'] != null ? 'ENCRYPTED url' : 'encrypted file';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  test(
      'the room starts encrypting while the file goes up in the clear: no '
      'event, the send fails where it shows, and "Retry" uploads it again, '
      'encrypted',
      skip: skipWithoutVodozemac, () async {
    final transport = OnlyUsTransport();
    final hold = Completer<void>();
    transport.onUpload = (body, _) async {
      await hold.future;
      return transport.accept(body);
    };
    final (mx, room) =
        await cryptoClient('encrypts_mid_upload', transport, encrypted: false);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final (send, sending) = startSend(room);
    await until(() => transport.open == 2);
    await turnOnEncryption(mx);
    expect(room.encrypted, isTrue);
    hold.complete();
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    final clearBefore = clearUploads(transport.uploads);
    print('room encrypts during the upload: events '
        '${transport.events.length}, pending event error '
        '${failed.status.isError}, stage ${send.stage}, uploads '
        '${transport.uploads.length} (in the clear $clearBefore)');
    expect(transport.events, isEmpty);
    expect(failed.status.isError, isTrue);
    expect(send.stage, AttachmentSendStage.failed);

    final id = await retryMatrixFile(failed, send);
    final sent = transport.events.single;
    final event = await decryptSent(mx, room, sent);
    final file = event.content['file'] as Map<String, dynamic>;
    print('Retry: id $id, uploads ${transport.uploads.length} (in the clear '
        '${clearUploads(transport.uploads)}), event ${sent.type}, url '
        '${event.content['url']}');
    expect(id, isNotNull);
    expect(sent.type, matrix.EventTypes.Encrypted);
    expect(event.content['url'], isNull);
    expect((event.content['info'] as Map)['thumbnail_url'], isNull);
    expect(clearUploads(transport.uploads), clearBefore,
        reason: 'nothing more in the clear');
    expect(
        await decryptUpload(
            file, transport.uploadsByUri[file['url'] as String]!),
        Uint8List.fromList(List.filled(fileBytes, 1)));
    await mx.dispose(closeDatabase: true);
  });

  test(
      'the room starts encrypting 0 to 40 turns after the pending event '
      'shows: no encrypted event ever points to an upload in the clear '
      '(probe sonda-c2-sala-criptografa-durante-o-envio)',
      skip: skipWithoutVodozemac, () async {
    final outcomes = <String, List<int>>{};
    for (var turns = 0; turns <= 40; turns++) {
      final transport = OnlyUsTransport();
      final (mx, room) = await cryptoClient('encrypts_turn_$turns', transport,
          encrypted: false);
      // As every send after the first: the media config is cached.
      await mx.getConfig();
      var seen = 0;
      final listening = mx.onTimelineEvent.stream.listen((e) async {
        if (++seen != 1) return;
        for (var i = 0; i < turns; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        _encryptNow(room);
      });
      final file = matrix.MatrixFile(
          bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
      final id = await room.sendFileEvent(file);
      await listening.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final says = transport.events.isEmpty
          ? 'no event'
          : await _eventSays(mx, room, transport.events.single);
      final outcome = '${id == null ? 'failed' : 'sent'}, $says, uploads in '
          'the clear ${clearUploads(transport.uploads)}';
      (outcomes[outcome] ??= []).add(turns);
      await mx.dispose(closeDatabase: true);
    }
    for (final MapEntry(key: outcome, value: turns) in outcomes.entries) {
      print('encrypts $turns turn(s) after the pending event: $outcome');
    }
    expect(outcomes.keys.where((o) => o.contains('ENCRYPTED url')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
