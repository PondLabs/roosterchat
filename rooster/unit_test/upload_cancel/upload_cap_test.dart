@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';

import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test(
      'ten attachments, each a file and its thumbnail: never more than four '
      'upload requests open at once, and all ten are sent', () async {
    final transport = CancelTransport()..holdUploads = true;
    final (mx, room) =
        await loopClient('cap_ten', transport, ManualSendClock());

    final sends = [for (var i = 0; i < 10; i++) startSend(room)];
    await until(() => transport.open == 4);
    // Time for any fifth to open, if one could.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(transport.open, 4);
    expect(transport.uploads, hasLength(4));

    transport.releaseUploads.complete();
    final ids = await Future.wait(sends.map((s) => s.$2));

    print('ten attachments: ${transport.uploads.length} uploads, at most '
        '${transport.mostOpen} open at once, ${transport.events.length} '
        'events');
    expect(transport.mostOpen, matrix.maxUploadsAtOnce);
    expect(transport.mostOpen, 4);
    expect(ids, everyElement(isNotNull));
    expect(transport.uploads, hasLength(20));
    expect(transport.events, hasLength(10));
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a message cancelled while its uploads wait for their turn never '
      'uploads, and gives no slot away: four can open again after', () async {
    final transport = CancelTransport()..holdUploads = true;
    final (mx, room) =
        await loopClient('cap_cancel', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final first = [startSend(room), startSend(room)];
    await until(() => transport.open == 4);
    final waiting = startSend(room);
    final after = startSend(room);
    await until(() =>
        echoes.any((e) => e.eventId == after.$1.transactionId) &&
        echoes.any((e) =>
            e.eventId == after.$1.transactionId &&
            e.fileSendingStatus == matrix.FileSendingStatus.uploading));
    // Its parts are in the line for a slot by now.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(transport.open, 4);
    final txid = waiting.$1.transactionId!;
    await echoes.lastWhere((e) => e.eventId == txid).cancelSend();
    expect(await waiting.$2, isNull);

    transport.releaseUploads.complete();
    final ids = await Future.wait([...first, after].map((s) => s.$2));
    expect(ids, everyElement(isNotNull));
    final uploadsBefore = transport.uploads.length;
    print('cancelled while waiting for a slot: $uploadsBefore uploads for '
        '3 messages sent, ${transport.events.length} events, at most '
        '${transport.mostOpen} open');
    expect(uploadsBefore, 6);
    expect(transport.events.map((e) => e.txid), isNot(contains(txid)));
    expect(transport.open, 0);

    // Every slot came back.
    transport
      ..releaseUploads = Completer<void>()
      ..mostOpen = 0;
    final again = [startSend(room), startSend(room)];
    await until(() => transport.open == 4);
    transport.releaseUploads.complete();
    await Future.wait(again.map((s) => s.$2));
    expect(transport.mostOpen, 4);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'six messages whose uploads are refused for good give every slot back: '
      'four can open after', () async {
    final transport = CancelTransport()
      ..onUpload = (_, __) async =>
          json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
    final (mx, room) =
        await loopClient('cap_failures', transport, ManualSendClock());

    final failed = [for (var i = 0; i < 6; i++) startSend(room)];
    final ids = await Future.wait(failed.map((s) => s.$2))
        .timeout(const Duration(seconds: 10));
    expect(ids, everyElement(isNull));
    expect(transport.uploads, hasLength(12));

    transport
      ..onUpload = null
      ..holdUploads = true;
    final again = [startSend(room), startSend(room)];
    await until(() => transport.open == 4);
    print('after 12 refused uploads: ${transport.open} open at once');
    transport.releaseUploads.complete();
    await Future.wait(again.map((s) => s.$2));
    await mx.dispose(closeDatabase: true);
  });
}
