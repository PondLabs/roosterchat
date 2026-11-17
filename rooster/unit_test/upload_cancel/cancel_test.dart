@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';

import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

/// The pending event of [txid] last shown.
matrix.Event pendingOf(List<matrix.Event> echoes, String txid) =>
    echoes.lastWhere((e) => e.eventId == txid);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test(
      'Cancel while the file is being prepared (the media config not '
      'answered yet): no upload, no event, the message is gone', () async {
    final transport = CancelTransport()..holdConfig = Completer<void>();
    final (mx, room) =
        await loopClient('cancel_preparing', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final cancelled = <String>[];
    mx.onCancelSendEvent.stream.listen(cancelled.add);

    final (send, sending) = startSend(room);
    await until(() =>
        send.transactionId != null &&
        echoes.any((e) => e.eventId == send.transactionId));
    final txid = send.transactionId!;
    await until(() => transport.configHeld == 1);
    expect(pendingOf(echoes, txid).status.isSending, isTrue);
    expect(room.canCancelSend(txid), isTrue);

    // Counted from before the tap: nothing of it is shown after.
    final shownBefore = echoes.length;
    await pendingOf(echoes, txid).cancelSend();
    transport.holdConfig!.complete();
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    print('cancel while preparing: ${transport.byRoute}; uploads '
        '${transport.uploads.length}, events ${transport.events.length}');
    expect(transport.uploads, isEmpty);
    expect(transport.events, isEmpty);
    expect(echoes.skip(shownBefore).where((e) => e.eventId == txid), isEmpty,
        reason: 'never shown again');
    expect(cancelled, contains(txid));
    expect(await goneFrom(room, txid), isTrue);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'Cancel during the uploads: both requests in flight are aborted within '
      '1 s, no new attempt goes out after, no event, the message is gone',
      () async {
    final transport = CancelTransport()..holdUploads = true;
    final clock = ManualSendClock();
    final (mx, room) = await loopClient('cancel_uploading', transport, clock);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final (send, sending) = startSend(room);
    await until(() => transport.open == 2);
    final txid = send.transactionId!;
    expect(room.canCancelSend(txid), isTrue);

    final shownBefore = echoes.length;
    transport.cancelledAt = Stopwatch()..start();
    await pendingOf(echoes, txid).cancelSend();
    expect(await sending, isNull);
    await until(() => transport.aborts.length == 2);
    // Everything the loop could wait for, and more.
    clock.advance(const Duration(minutes: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    print('cancel while uploading: uploads ${transport.uploads.length}, '
        'aborted ${transport.aborts.length} after ${transport.aborts}, '
        'answered ${transport.answeredUploads}, events '
        '${transport.events.length}, waits ${clock.waits}');
    expect(
        transport.aborts, everyElement(lessThan(const Duration(seconds: 1))));
    expect(transport.uploads, hasLength(2), reason: 'no new attempt');
    expect(transport.answeredUploads, 0);
    expect(clock.waits, isEmpty);
    expect(transport.events, isEmpty);
    expect(echoes.skip(shownBefore).where((e) => e.eventId == txid), isEmpty);
    expect(await goneFrom(room, txid), isTrue,
        reason: 'its bytes and parts let go');
    await mx.dispose(closeDatabase: true);
  });

  test(
      'Cancel while a failed part waits to be tried again: no new attempt '
      'goes out after', () async {
    final transport = LoopTransport()
      ..onUpload =
          (_, __) async => throw http.ClientException('Connection reset');
    final clock = ManualSendClock();
    final (mx, room) = await loopClient('cancel_waiting', transport, clock);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final (send, sending) = startSend(room, withThumbnail: false);
    await until(() => clock.waiting);
    final txid = send.transactionId!;
    await pendingOf(echoes, txid).cancelSend();
    expect(await sending, isNull,
        reason: 'it ends at once, not after the wait');
    clock.advance(const Duration(minutes: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    print('cancel while waiting to try again: uploads '
        '${transport.uploads.length}, waits ${clock.waits}, events '
        '${transport.events.length}');
    expect(transport.uploads, hasLength(1));
    expect(clock.waits, [const Duration(seconds: 2)]);
    expect(transport.events, isEmpty);
    expect(await goneFrom(room, txid), isTrue);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a text waiting in the queue behind a send whose request left: Cancel '
      'takes it out at once, the send in front goes on and is the only '
      'event sent', () async {
    final transport = CancelTransport();
    final hold = Completer<void>();
    transport.holdNextSend = hold.future;
    final (mx, room) =
        await loopClient('cancel_queued_text', transport, ManualSendClock());
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final cancelled = <String>[];
    mx.onCancelSendEvent.stream.listen(cancelled.add);

    final first = room
        .sendEvent({'msgtype': 'm.text', 'body': 'first'}, txid: 'txn_first');
    await until(() => transport.events.length == 1);
    final second = room
        .sendEvent({'msgtype': 'm.text', 'body': 'second'}, txid: 'txn_second');
    await until(() =>
        room.sendingQueue.length == 2 &&
        echoes.any((e) => e.eventId == 'txn_second'));

    // The first one's request left: the server may have it.
    expect(room.canCancelSend('txn_first'), isFalse);
    await expectLater(
        pendingOf(echoes, 'txn_first').cancelSend(), throwsException);
    expect(room.canCancelSend('txn_second'), isTrue);

    final shownBefore = echoes.length;
    await pendingOf(echoes, 'txn_second').cancelSend();
    expect(await second.timeout(const Duration(seconds: 5)), isNull,
        reason: 'out of the queue before the send in front ends');
    expect(room.sendingQueue, hasLength(1));
    expect(hold.isCompleted, isFalse);

    hold.complete();
    final firstId = await first;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    print('queued text cancelled: events sent '
        '${transport.events.map((e) => e.txid).toList()}');
    expect(firstId, isNotNull);
    expect(transport.events.map((e) => e.txid), ['txn_first']);
    expect(cancelled.toSet(), {'txn_second'});
    expect(echoes.skip(shownBefore).where((e) => e.eventId == 'txn_second'),
        isEmpty);
    expect(await mx.database.getEventById('txn_second', room), isNull);
    expect(room.sendingQueue, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a text cancelled before its request leaves, with nothing in front of '
      'it in the queue: no PUT /send', () async {
    final transport = CancelTransport();
    final (mx, room) =
        await loopClient('cancel_text_at_head', transport, ManualSendClock());

    final sending =
        room.sendEvent({'msgtype': 'm.text', 'body': 'text'}, txid: 'txn_text');
    expect(room.cancelSending('txn_text'), isTrue);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    print('text cancelled at the head of the queue: events '
        '${transport.events.length}');
    expect(transport.events, isEmpty);
    expect(await mx.database.getEventById('txn_text', room), isNull);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'cancelled by the room alone during the upload: the send itself takes '
      'away the event it showed', () async {
    final transport = CancelTransport()..holdUploads = true;
    final (mx, room) =
        await loopClient('cancel_room_alone', transport, ManualSendClock());
    final cancelled = <String>[];
    mx.onCancelSendEvent.stream.listen(cancelled.add);

    final (send, sending) = startSend(room);
    await until(() => transport.open == 2);
    final txid = send.transactionId!;
    expect(await mx.database.getEventById(txid, room), isNotNull,
        reason: 'shown and stored while it uploads');

    // No caller takes the event away: only the flag is set.
    expect(room.cancelSending(txid), isTrue);
    expect(await sending, isNull);

    print('cancelled by the room alone: stored '
        '${await mx.database.getEventById(txid, room) != null}, cancel '
        'events $cancelled');
    expect(await goneFrom(room, txid), isTrue);
    expect(cancelled, contains(txid));
    await mx.dispose(closeDatabase: true);
  });
}
