// A photo sent by asynchronous upload, on the SDK's fake homeserver under
// our HTTP client: the event first, to mxcs reserved before, then the
// thumbnail and the file; a failure taken back and retried; refused
// reservations; other files; ten photos at once.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_fakes.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late AsyncTransport transport;
  late ManualSendClock clock;
  late matrix.Client mx;
  late matrix.Room room;
  var n = 0;

  setUp(() async {
    AttachmentSends.instance.clear();
    transport = AsyncTransport();
    clock = ManualSendClock();
    (mx, room) = await loopClient('async_photo_${n++}', transport, clock);
  });

  tearDown(() => mx.dispose(closeDatabase: true));

  test(
      'the event leaves first, with the reserved mxcs, the size and the '
      'blurhash; then the thumbnail and the file go up, in that order',
      () async {
    final attachment = photo();
    final id = await sendAttachment(room, attachment);
    expect(id, isNotNull);

    expect(transport.log, [
      'POST create',
      'POST create',
      'PUT send',
      'PUT upload thumbnail',
      'PUT upload file',
    ]);
    final content = transport.events.single.body;
    expect(content['msgtype'], 'm.image');
    expect(content['url'], 'mxc://fakeserver.notexisting/r1');
    final info = content['info'] as Map<String, dynamic>;
    expect(info['thumbnail_url'], 'mxc://fakeserver.notexisting/r2');
    expect(info['w'], 640);
    expect(info['h'], 480);
    expect(info['xyz.amorgan.blurhash'], 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
    expect((info['thumbnail_info'] as Map)['w'], 160);

    // What went up is the photo and its thumbnail, to their own mxcs.
    expect(transport.putsByMxc['mxc://fakeserver.notexisting/r1'],
        attachment.file.bytes);
    expect(transport.putsByMxc['mxc://fakeserver.notexisting/r2'],
        attachment.thumbnailFile!.bytes);
    expect(transport.uploads, isEmpty, reason: 'no POST /upload');
    expect(attachment.send.stage, AttachmentSendStage.sent);
    expect(AttachmentSends.instance.all, isEmpty);
    expect(asyncPhotoSendOf(room, attachment.send.transactionId!), isNull);
  });

  test(
      'an upload that fails for good, after its new attempts, takes the '
      'message back and leaves a failed message whose Retry is a new event',
      () async {
    transport.onPut = (body, _) async => body.length == fileBytes
        ? json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'})
        : null;
    final attachment = photo();
    final sending = sendAttachment(room, attachment);
    // The upload loop's two new attempts, 2 s and 8 s after a failure.
    for (final wait in const [Duration(seconds: 2), Duration(seconds: 8)]) {
      await until(() => clock.waiting);
      clock.advance(wait);
    }
    expect(await sending, isNull);

    expect(transport.log, [
      'POST create',
      'POST create',
      'PUT send',
      'PUT upload thumbnail',
      'PUT upload file',
      'PUT upload file',
      'PUT upload file',
      'PUT redact',
    ]);
    final send = attachment.send;
    expect(send.stage, AttachmentSendStage.failed);
    final photoSend = failedPhoto(room, send)!;
    final failedId = photoSend.failedMessageId!;
    final failedMessage = (await shown(room, failedId))!;
    expect(failedMessage.status, matrix.EventStatus.error);
    expect(failedMessage.content['url'], isNull);
    // The photo is held for Retry, no file picked again.
    expect(
        room.sendingFilePlaceholders[failedId]!.bytes, attachment.file.bytes);
    final firstTxid = transport.events.single.txid;

    transport.onPut = null;
    transport.log.clear();
    expect(await photoSend.retry(), isNotNull);
    expect(transport.log, [
      'POST create',
      'POST create',
      'PUT send',
      'PUT upload thumbnail',
      'PUT upload file',
    ]);
    final retried = transport.events.last;
    expect(retried.txid, isNot(firstTxid));
    expect(retried.txid, isNot(failedId));
    expect(retried.body['url'], 'mxc://fakeserver.notexisting/r3');
    expect(send.stage, AttachmentSendStage.sent);
    expect(await shown(room, failedId), isNull,
        reason: 'the failed message gives way to the new one');
  });

  for (final (name, status, errcode) in const [
    ('no such endpoint', 404, 'M_UNRECOGNIZED'),
    ('forbidden', 403, 'M_FORBIDDEN'),
    ('too many pending', 429, 'M_LIMIT_EXCEEDED'),
  ]) {
    test('a refused reservation ($name) sends the photo upload first, as sent',
        () async {
      transport.onCreate = (_) => json(status, {'errcode': errcode});
      final attachment = photo();
      expect(await sendAttachment(room, attachment), isNotNull);
      expect(transport.log,
          ['POST create', 'POST upload', 'POST upload', 'PUT send']);
      expect(transport.refusedCreates, 1, reason: 'one refused per photo');
      expect(attachment.send.stage, AttachmentSendStage.sent);
      expect(transport.events.single.body['url'],
          startsWith('mxc://fakeserver.notexisting/u'));
    });
  }

  test(
      'a homeserver without the endpoint is not asked again for the next '
      'photo; one that refused for another reason is', () async {
    transport.onCreate = (_) => json(404, {'errcode': 'M_UNRECOGNIZED'});
    await sendAttachment(room, photo());
    await sendAttachment(room, photo(seed: 2));
    expect(transport.creates, 1);

    final (otherMx, otherRoom) =
        await loopClient('async_photo_other_${n++}', transport, clock);
    transport.creates = 0;
    transport.onCreate =
        (call) => call == 1 ? json(429, {'errcode': 'M_LIMIT_EXCEEDED'}) : null;
    await sendAttachment(otherRoom, photo());
    await sendAttachment(otherRoom, photo(seed: 2));
    expect(transport.creates, 3, reason: '1 refused, then the 2 of a photo');
    await otherMx.dispose(closeDatabase: true);
  });

  test('a video and a plain file are uploaded first, without a reservation',
      () async {
    for (final file in [
      matrix.MatrixVideoFile(
          bytes: Uint8List(fileBytes), name: 'clip.mp4', mimeType: 'video/mp4'),
      matrix.MatrixFile(
          bytes: Uint8List(fileBytes),
          name: 'notes.pdf',
          mimeType: 'application/pdf'),
    ]) {
      final send = AttachmentSend(roomKey: 'test:$roomId', attachment: null);
      final attachment = TrackedMatrixAttachment(file, send);
      expect(sendsByAsyncUpload(attachment), isFalse);
      transport.log.clear();
      expect(await sendMatrixAttachment(room, attachment), isNotNull);
      expect(transport.log, ['POST upload', 'PUT send']);
    }
    expect(transport.creates, 0);
    // A photo read from disk is not either: its key is made at each upload.
    final fromDisk = MatrixProcessedAttachment(matrix.MatrixImageFile(
        bytes: Uint8List(0), name: 'big.jpg', mimeType: 'image/jpeg'));
    expect(sendsByAsyncUpload(fromDisk), isFalse);
  });

  test(
      'ten photos at once stay within the homeserver\'s pending reservations '
      'and four uploads at once', () async {
    transport.holdPuts = true;
    final photos = [for (var i = 1; i <= 10; i++) photo(seed: i)];
    final sending = [for (final p in photos) sendAttachment(room, p)];
    // The four uploads to reservations hold every slot until released.
    await until(() => transport.puts.length == 4);
    expect(transport.openUploads, 4);
    transport.releasePuts.complete();
    final ids = await Future.wait(sending);

    expect(ids, everyElement(isNotNull));
    expect(transport.refusedCreates, 0);
    expect(transport.mostPending, lessThanOrEqualTo(transport.pendingLimit));
    expect(transport.mostPending, maxOpenPhotoReservations);
    expect(transport.mostOpenUploads, 4);
    // Two photos by reservation, the eight others upload first.
    expect(transport.answeredPuts, 4);
    expect(transport.uploads, hasLength(16));
    expect(photos.map((p) => p.send.stage),
        everyElement(AttachmentSendStage.sent));
  });
}
