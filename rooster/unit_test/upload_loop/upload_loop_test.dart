@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';

import 'loop_fakes.dart';

/// What a connection that breaks looks like to the HTTP client.
Never _connectionReset() => throw http.ClientException('Connection reset');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AttachmentSends.instance.clear());

  test(
      'the file goes up once, the thumbnail whose upload broke goes up again '
      'after 2 s, and the event leaves under the same transaction id',
      () async {
    final transport = LoopTransport();
    transport.onUpload = (body, attempt) async {
      if (body.length == thumbnailBytes && attempt == 1) _connectionReset();
      return transport.accept(body);
    };
    final clock = ManualSendClock();
    final (mx, room) = await loopClient('loop_thumbnail', transport, clock);

    final (send, sending) = startSend(room);
    await until(() => clock.waiting);
    expect(clock.waits, [const Duration(seconds: 2)]);
    expect(send.upload.retrying, isTrue);
    expect(PendingAttachmentStatus.describe(send).label,
        PendingAttachmentStatus.labelPendingFileRetrying);
    clock.advance(const Duration(seconds: 2));
    final id = await sending;

    print('thumbnail dropped: ${transport.byRoute}; file uploads '
        '${transport.uploadsOf(fileBytes)}, thumbnail uploads '
        '${transport.uploadsOf(thumbnailBytes)}, waits ${clock.waits}');
    expect(id, isNotNull);
    expect(transport.uploadsOf(fileBytes), 1);
    expect(transport.uploadsOf(thumbnailBytes), 2);
    final event = transport.events.single;
    expect(event.txid, send.transactionId);
    expect(transport.uploadUris, hasLength(2));
    expect({event.body['url'], event.body['info']['thumbnail_url']},
        transport.uploadUris.map((u) => u.toLowerCase()).toSet());
    expect(send.stage, AttachmentSendStage.sent);
    expect(send.upload.retrying, isFalse);
    expect(send.upload.failedAttempts, 1);
    expect(send.upload.sentBytes, fileBytes + thumbnailBytes);
    expect(room.sendingFileUploads, isEmpty, reason: 'let go once sent');
    expect(room.sendingFilePlaceholders, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  group('a network failure', () {
    test('is tried again twice, after 2 s and 8 s, then the message fails',
        () async {
      final transport = LoopTransport()
        ..onUpload = (_, __) async => _connectionReset();
      final clock = ManualSendClock();
      final (mx, room) = await loopClient('loop_network', transport, clock);
      final (send, sending) = startSend(room, withThumbnail: false);
      await until(() => clock.waiting);
      clock.advance(const Duration(seconds: 2));
      await until(() => clock.waiting);
      clock.advance(const Duration(seconds: 8));
      expect(await sending, isNull);
      print('network failure: ${transport.byRoute}, waits ${clock.waits}');
      expect(clock.waits,
          [const Duration(seconds: 2), const Duration(seconds: 8)]);
      expect(transport.uploads, hasLength(3));
      expect(send.stage, AttachmentSendStage.failed);
      await mx.dispose(closeDatabase: true);
    });

    for (final (ran, retried) in [(61, false), (59, true)]) {
      test(
          'after the upload ran $ran s: ${retried ? '' : 'not '}tried '
          'again by itself', () async {
        final transport = LoopTransport();
        final breaks = Completer<void>();
        transport.onUpload = (body, attempt) async {
          if (attempt == 1) {
            await breaks.future;
            _connectionReset();
          }
          return transport.accept(body);
        };
        final clock = ManualSendClock();
        final (mx, room) = await loopClient('loop_ran_$ran', transport, clock);
        final (send, sending) = startSend(room, withThumbnail: false);
        await until(() => transport.open == 1);
        clock.advance(Duration(seconds: ran));
        breaks.complete();
        if (retried) {
          await until(() => clock.waiting);
          clock.advance(const Duration(seconds: 2));
        }
        final id = await sending;
        print('failed after $ran s: ${transport.byRoute}, '
            'waits ${clock.waits}');
        expect(transport.uploads, hasLength(retried ? 2 : 1));
        expect(clock.waits, retried ? [const Duration(seconds: 2)] : isEmpty);
        expect(id, retried ? isNotNull : isNull);
        expect(send.stage,
            retried ? AttachmentSendStage.sent : AttachmentSendStage.failed);
        await mx.dispose(closeDatabase: true);
      });
    }
  });

  for (final (status, errcode) in [(413, 'M_TOO_LARGE'), (403, 'M_FORBIDDEN')])
    test('a $status $errcode ends the send at the first attempt', () async {
      final transport = LoopTransport()
        ..onUpload =
            (_, __) async => json(status, {'errcode': errcode, 'error': 'No'});
      final clock = ManualSendClock();
      final (mx, room) = await loopClient('loop_$status', transport, clock);
      final (send, sending) = startSend(room, withThumbnail: false);
      expect(await sending, isNull);
      print('$status $errcode: ${transport.byRoute}, waits ${clock.waits}');
      expect(transport.uploads, hasLength(1));
      expect(clock.waits, isEmpty);
      expect(send.stage, AttachmentSendStage.failed);
      await mx.dispose(closeDatabase: true);
    });

  test(
      'a healthy upload of 5 minutes is never cut, and its pending event '
      'read again meanwhile is not taken for a lost one', () async {
    final transport = LoopTransport();
    final answers = Completer<void>();
    transport.onUpload = (body, _) async {
      await answers.future;
      return transport.accept(body);
    };
    final clock = ManualSendClock();
    // The SDK takes a pending event older than this for a lost one.
    final (mx, room) = await loopClient('loop_5_minutes', transport, clock,
        sendTimelineEventTimeout: const Duration(milliseconds: 50));
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final (send, sending) = startSend(room, withThumbnail: false);
    await until(() => transport.open == 1);
    for (var s = 0; s < 5 * 60; s += 30) {
      clock.advance(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Read again from the store, as opening the chat does.
    final reread = await mx.database.getEventById(send.transactionId!, room);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reread?.status.isSending, isTrue);
    answers.complete();
    final id = await sending;

    final mine = echoes.where((e) => e.eventId == send.transactionId);
    print('5 minutes: ${transport.byRoute}, waits ${clock.waits}, statuses '
        '${mine.map((e) => e.status.name).toList()}');
    expect(mine.where((e) => e.status.isError), isEmpty);
    expect(id, isNotNull);
    expect(transport.uploads, hasLength(1));
    expect(clock.waits, isEmpty);
    expect(send.stage, AttachmentSendStage.sent);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'the file and its thumbnail upload at the same time, and the line '
      'counts them together', () async {
    final transport = LoopTransport();
    final answers = Completer<void>();
    transport.onUpload = (body, _) async {
      await answers.future;
      return transport.accept(body);
    };
    final clock = ManualSendClock();
    final (mx, room) = await loopClient('loop_together', transport, clock);
    final (send, sending) = startSend(room);
    await until(() => transport.open == 2);
    expect(send.upload.waitingForServer, isTrue);
    expect(send.upload.totalBytes, fileBytes + thumbnailBytes);
    answers.complete();
    expect(await sending, isNotNull);
    print('together: ${transport.byRoute}, most open ${transport.mostOpen}');
    expect(transport.mostOpen, 2);
    expect(send.upload.sentBytes, fileBytes + thumbnailBytes);
    await mx.dispose(closeDatabase: true);
  });

  test('the pending event goes through the uploading stage', () async {
    final transport = LoopTransport();
    final answers = Completer<void>();
    transport.onUpload = (body, _) async {
      await answers.future;
      return transport.accept(body);
    };
    final (mx, room) =
        await loopClient('loop_stage', transport, ManualSendClock());
    // Read as each echo arrives: the SDK changes its pending event's map
    // in place afterwards.
    final stages = <(String, matrix.FileSendingStatus?)>[];
    mx.onTimelineEvent.stream
        .listen((e) => stages.add((e.eventId, e.fileSendingStatus)));
    final (send, sending) = startSend(room);
    await until(() => transport.open == 2);
    stages.removeWhere((s) => s.$1 != send.transactionId);
    print('stages while uploading: $stages');
    expect(stages.last.$2, matrix.FileSendingStatus.uploading);
    answers.complete();
    expect(await sending, isNotNull);
    await mx.dispose(closeDatabase: true);
  });
}
