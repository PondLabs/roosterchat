@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import 'loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test('Cancel on a failed file lets go of its file, thumbnail and uploads',
      () async {
    final transport = LoopTransport()..failSends = 1;
    final (mx, room) =
        await loopClient('kept_cancel', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    final txid = send.transactionId!;
    expect(room.sendingFileUploads[txid], isNotEmpty);

    await echoes.lastWhere((e) => e.eventId == txid).cancelSend();

    expect(room.sendingFilePlaceholders, isNot(contains(txid)));
    expect(room.sendingFileThumbnails, isNot(contains(txid)));
    expect(room.sendingFileUploads, isNot(contains(txid)));
    await mx.dispose(closeDatabase: true);
  });

  test('a part that goes up after its message was cancelled is not kept',
      () async {
    final transport = LoopTransport()..failSends = 1;
    final answers = Completer<void>();
    transport.onUpload = (body, _) async {
      await answers.future;
      return transport.accept(body);
    };
    final (mx, room) =
        await loopClient('kept_after_cancel', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room, withThumbnail: false);
    await until(() => transport.open == 1);
    final txid = send.transactionId!;

    await echoes.lastWhere((e) => e.eventId == txid).cancelSend();
    answers.complete();
    await sending;

    expect(room.sendingFileUploads, isNot(contains(txid)));
    await mx.dispose(closeDatabase: true);
  });

  test(
      '"Retry" with the file kept: the line counts it as sent, and only the '
      'thumbnail goes up', () async {
    final transport = LoopTransport();
    transport.onUpload = (body, attempt) async {
      if (body.length == thumbnailBytes && attempt == 1) {
        return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      }
      return transport.accept(body);
    };
    final (mx, room) =
        await loopClient('kept_count', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final failed = echoes.lastWhere((e) => e.eventId == send.transactionId);

    expect(await retryMatrixFile(failed, send), isNotNull);

    expect(transport.uploadsOf(fileBytes), 1);
    expect(transport.uploadsOf(thumbnailBytes), 2);
    expect(send.upload.sentBytes, fileBytes + thumbnailBytes);
    await mx.dispose(closeDatabase: true);
  });
}
