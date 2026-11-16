@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import 'encrypted_fakes.dart';
import 'loop_fakes.dart';

/// A file message in an encrypted room whose file went up and whose
/// thumbnail was refused: the failed event, its send, and the transport,
/// whose next thumbnail upload waits for the returned completer.
Future<
    (
      matrix.Client,
      matrix.Room,
      OnlyUsTransport,
      AttachmentSend,
      matrix.Event,
      Completer<void>
    )> _halfUploaded(String name) async {
  final transport = OnlyUsTransport();
  final hold = Completer<void>();
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
  final (mx, room) = await cryptoClient(name, transport, encrypted: true);
  final echoes = <matrix.Event>[];
  final listening = mx.onTimelineEvent.stream.listen(echoes.add);
  final (send, sending) = startSend(room);
  expect(await sending, isNull);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await listening.cancel();
  final failed = echoes.lastWhere((e) => e.eventId == send.transactionId);
  expect(failed.status.isError, isTrue);
  expect(room.sendingFileUploads[send.transactionId]!.keys,
      [matrix.FileSendPart.file]);
  expect(clearUploads(transport.uploads), 0);
  return (mx, room, transport, send, failed, hold);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  test(
      'two sends of one half-uploaded message in an encrypted room, the '
      'second starting as the first ends and lets its parts go: nothing is '
      'ever uploaded in the clear (50 runs)',
      skip: skipWithoutVodozemac, () async {
    var clear = 0;
    var uploads = 0;
    for (var run = 0; run < 50; run++) {
      // How many turns of the event loop after the second send shows its
      // pending event the first one's PUT /send is answered.
      final turns = run % 13;
      final (mx, room, transport, send, failed, hold) =
          await _halfUploaded('race_$run');
      final txid = send.transactionId!;
      transport.holdSend = Completer<void>();
      hold.complete();
      // The first send: its thumbnail goes up, its event is on its way.
      final first = retryMatrixFile(failed, send);
      await until(() => transport.sendsArrived == 1);
      var echoesOfSecond = 0;
      final listening = mx.onTimelineEvent.stream.listen((e) async {
        if (e.eventId != txid || ++echoesOfSecond != 1) return;
        for (var i = 0; i < turns; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        transport.holdSend!.complete();
      });
      // The second send of the same message, straight to the SDK: the
      // app's own guard is tested apart.
      final second = retryMatrixFile(failed, null);
      await first;
      await second;
      await listening.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clear += clearUploads(transport.uploads);
      uploads += transport.uploads.length;
      await mx.dispose(closeDatabase: true);
    }
    print('race, 50 runs: $uploads uploads, $clear of them in the clear');
    expect(clear, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
