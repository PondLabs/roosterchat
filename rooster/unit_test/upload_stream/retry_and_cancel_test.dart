@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import 'stream_fakes.dart';

void main() {
  late Directory folder;
  setUp(() async => folder = await testFolder());
  tearDown(() async {
    AttachmentSends.instance.clear();
    await removeFolder(folder);
  });

  test(
      'the connection breaks in the middle: the new attempt, 2 s later on '
      'the injected clock, reads the file again from disk and the server '
      'gets the right bytes', () async {
    final (file, hash) = await writeTestFile(folder, 'retry.bin', 9 * mib + 7);
    final transport = BreaksMidBody(1);
    final clock = ManualSendClock();
    final (mx, room) = await streamClient('stream_retry', transport,
        encrypted: false, clock: clock);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final sending = sendMatrixFile(room, processed);
    await until(() => clock.waiting);
    final openWhileWaiting = source.openFiles;
    clock.advance(const Duration(seconds: 2));
    final id = await sending;

    print('broken once: ${source.opens} openings, ${source.bytesRead} bytes '
        'read (the file is ${source.length}), waits ${clock.waits}, '
        '${transport.takenBeforeBreak} bytes taken before the break, files '
        'open during the wait: $openWhileWaiting; the server got '
        '${transport.uploads.single.length} bytes, same hash: '
        '${sha256Hex(transport.uploads.single) == hash}');
    expect(id, isNotNull);
    expect(send.stage, AttachmentSendStage.sent);
    expect(clock.waits, [const Duration(seconds: 2)]);
    expect(source.opens, 2);
    expect(openWhileWaiting, 0);
    expect(source.bytesRead,
        greaterThanOrEqualTo(source.length + transport.takenBeforeBreak[0]));
    expect(sha256Hex(transport.uploads.single), hash);
    expect(transport.events.single.body['info']['size'], 9 * mib + 7);
    expect(source.openFiles, 0);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'after the loop gives up (three breaks: waits of 2 s and 8 s), the '
      'message keeps the path, not the bytes, and Retry reads the file from '
      'disk again', () async {
    final (file, hash) = await writeTestFile(folder, 'retry3.bin', 9 * mib);
    final transport = BreaksMidBody(3);
    final clock = ManualSendClock();
    final (mx, room) = await streamClient('stream_retry_user', transport,
        encrypted: false, clock: clock);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final sending = sendMatrixFile(room, processed);
    await until(() => clock.waiting);
    clock.advance(const Duration(seconds: 2));
    await until(() => clock.waiting);
    clock.advance(const Duration(seconds: 8));
    expect(await sending, isNull);

    final txid = send.transactionId!;
    final kept = room.sendingFilePlaceholders[txid]!;
    final opensBefore = source.opens;
    final failedEvent = (await mx.database.getEventById(txid, room))!;
    print('failed: ${send.stage}, event ${failedEvent.status}, '
        '${source.opens} openings, kept ${kept.bytes.length} bytes and its '
        'source ${identical(kept.source, source)}');
    expect(send.stage, AttachmentSendStage.failed);
    expect(failedEvent.status, matrix.EventStatus.error);
    expect(
        clock.waits, [const Duration(seconds: 2), const Duration(seconds: 8)]);
    expect(kept.bytes, isEmpty);
    expect(identical(kept.source, source), isTrue);
    expect(source.openFiles, 0);

    final id = await retryMatrixFile(failedEvent, send);
    print('Retry: ${source.opens - opensBefore} more opening, the server got '
        '${transport.uploads.single.length} bytes, same hash: '
        '${sha256Hex(transport.uploads.single) == hash}');
    expect(id, isNotNull);
    expect(send.stage, AttachmentSendStage.sent);
    expect(source.opens, opensBefore + 1);
    expect(sha256Hex(transport.uploads.single), hash);
    expect(room.sendingFilePlaceholders[txid], isNull,
        reason: 'sent: the path is let go');
    expect(source.openFiles, 0);
    await mx.dispose(closeDatabase: true);
  });

  for (final encrypted in [false, true]) {
    test(
        'Cancel during the upload from disk aborts the request and closes the '
        'file: it is deleted at once (Windows refuses an open file)'
        '${encrypted ? ', encrypted room' : ''}',
        skip: encrypted ? skipWithoutVodozemac : false, () async {
      if (encrypted) await initVodozemac();
      final (file, _) = await writeTestFile(folder, 'cancel.bin', 48 * mib);
      final server = await LocalUploadServer.start()
        ..holdAfter = 2 * mib;
      final transport = LocalUploadTransport(server);
      final (mx, room) = await streamClient(
          'stream_cancel_$encrypted', transport,
          encrypted: encrypted);

      final (send, processed) = await attachByPath(file);
      final source = sourceOf(processed);
      final sending = sendMatrixFile(room, processed);
      final upload = await server.held.first;
      final readAtCancel = source.bytesRead;
      final cancelled = room.cancelSending(send.transactionId!);
      final id = await sending;
      final openAfter = source.openFiles;
      Object? deleteError;
      try {
        file.deleteSync();
      } catch (error) {
        deleteError = error;
      }
      server.release();
      await until(() => upload.broken || upload.complete);

      print('cancelled after ${upload.bytes} bytes at the server, '
          '$readAtCancel read: send returned $id, files open '
          '$openAfter, delete error $deleteError, the server saw the '
          'connection end early: ${upload.broken}, events '
          '${transport.events.length}');
      expect(cancelled, isTrue);
      expect(id, isNull);
      expect(openAfter, 0);
      expect(deleteError, isNull);
      expect(file.existsSync(), isFalse);
      expect(upload.broken, isTrue);
      expect(upload.complete, isFalse);
      expect(readAtCancel, lessThan(48 * mib));
      expect(transport.events, isEmpty);
      await mx.dispose(closeDatabase: true);
      transport.closeConnections();
      await server.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
