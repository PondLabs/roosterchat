@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/utils/network/upload_progress.dart';

import 'stream_fakes.dart';

/// A file sent from disk that is deleted, cut short or written to while it
/// is sent: the message fails where it shows, with the reason, and no event
/// describes a file the server did not get.
void main() {
  late Directory folder;
  setUp(() async => folder = await testFolder());
  tearDown(() async {
    AttachmentSends.instance.clear();
    intl.Intl.defaultLocale = null;
    await removeFolder(folder);
  });

  /// What the message's line says, in English and in Portuguese.
  Future<(String, String)> lineOf(AttachmentSend send) async {
    await initializeMessages('en');
    intl.Intl.defaultLocale = 'en';
    final en = PendingAttachmentStatus.describe(send).label;
    await initializeMessages('pt');
    intl.Intl.defaultLocale = 'pt';
    final pt = PendingAttachmentStatus.describe(send).label;
    intl.Intl.defaultLocale = null;
    return (en, pt);
  }

  /// [send] failed and shows why; its pending event is failed too, in the
  /// room's database.
  Future<void> expectShownFailure(
      matrix.Client mx, matrix.Room room, AttachmentSend send) async {
    final event = (await mx.database.getEventById(send.transactionId!, room))!;
    final (en, pt) = await lineOf(send);
    print('the message: ${send.stage}, its event ${event.status}, problem '
        '${send.upload.problem}; the line says "$en" / "$pt"');
    expect(send.stage, AttachmentSendStage.failed);
    expect(event.status, matrix.EventStatus.error);
    expect(send.upload.problem, UploadProblem.fileChanged);
    expect(en, 'The file was changed or deleted');
    expect(pt, 'O arquivo foi alterado ou apagado');
  }

  test(
      'cut short while it goes up: the send ends at once, no new attempt, no '
      'event, and the message says why', () async {
    final (file, _) = await writeTestFile(folder, 'shrinks.bin', 48 * mib);
    final server = await LocalUploadServer.start()
      ..holdAfter = 2 * mib;
    final transport = LocalUploadTransport(server);
    final (mx, room) =
        await streamClient('stream_shrinks', transport, encrypted: false);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final sending = sendMatrixFile(room, processed);
    await server.held.first;
    final writer = await file.open(mode: FileMode.append);
    await writer.truncate(3 * mib);
    await writer.close();
    server.release();
    final id = await sending;

    print('cut to 3 MB: ${server.uploads.length} upload(s), '
        '${source.bytesRead} bytes read, ${transport.events.length} events, '
        'files open ${source.openFiles}');
    expect(id, isNull);
    expect(server.uploads, hasLength(1));
    expect(server.uploads.single.complete, isFalse);
    expect(transport.events, isEmpty);
    expect(source.openFiles, 0);
    await expectShownFailure(mx, room, send);
    await mx.dispose(closeDatabase: true);
    transport.closeConnections();
    await server.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'deleted while the loop waits to try again: the new attempt finds it '
      'gone and the message says why', () async {
    final (file, _) = await writeTestFile(folder, 'gone.bin', 9 * mib);
    final transport = BreaksMidBody(1);
    final clock = ManualSendClock();
    final (mx, room) = await streamClient('stream_gone', transport,
        encrypted: false, clock: clock);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final sending = sendMatrixFile(room, processed);
    await until(() => clock.waiting);
    // Closed while it waits: Windows lets it be deleted.
    await file.delete();
    clock.advance(const Duration(seconds: 2));
    final id = await sending;

    print('deleted: ${transport.attempts} upload attempt(s), '
        '${source.opens} openings, waits ${clock.waits}');
    expect(id, isNull);
    // The new attempt's request ends with no byte (the file is gone), and
    // none follows it: no third request, no other wait.
    expect(transport.attempts, 2);
    expect(transport.uploads, isEmpty);
    expect(source.opens, 1);
    expect(clock.waits, [const Duration(seconds: 2)]);
    expect(transport.events, isEmpty);
    await expectShownFailure(mx, room, send);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'written to after it was attached (same size, new time): nothing is '
      'read or sent, and the message says why', () async {
    final (file, _) = await writeTestFile(folder, 'edited.bin', 9 * mib);
    final transport = OnlyUsTransport();
    final (mx, room) =
        await streamClient('stream_edited', transport, encrypted: false);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    await writeTestFile(folder, 'edited.bin', 9 * mib, seed: 2);
    await file.setLastModified(DateTime.now().add(const Duration(minutes: 1)));
    final id = await sendMatrixFile(room, processed);

    print('edited: ${source.bytesRead} bytes read, ${source.opens} openings, '
        '${transport.uploads.length} uploads');
    expect(id, isNull);
    expect(source.bytesRead, 0);
    expect(source.opens, 0);
    expect(transport.uploads, isEmpty);
    expect(transport.events, isEmpty);
    await expectShownFailure(mx, room, send);

    // Retry reads the file as it is now, which is not the one attached:
    // it fails the same way, and says so again.
    final failed = (await mx.database.getEventById(send.transactionId!, room))!;
    expect(await retryMatrixFile(failed, send), isNull);
    expect(transport.uploads, isEmpty);
    await expectShownFailure(mx, room, send);
    await mx.dispose(closeDatabase: true);
  });
}
