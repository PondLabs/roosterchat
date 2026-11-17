@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/disk_file_source_io.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'stream_fakes.dart';

/// A file attached by its path is sent from disk on native: read in pieces
/// as the connection takes them, to a real server on 127.0.0.1.
/// A preparer that cannot decode the picture: it is sent as a plain file,
/// from the bytes it was read into.
class _CannotDecode extends ImagePreparer {
  @override
  Future<ImagePreparation?> prepare(Uint8List bytes,
          {PreparationCancel? cancel, bool reduce = false}) async =>
      null;
}

void main() {
  late Directory folder;
  setUp(() async => folder = await testFolder());
  tearDown(() async {
    AttachmentSends.instance.clear();
    await removeFolder(folder);
  });

  test(
      'a 200 MB file attached by its path goes up read from disk, never more '
      'than a few pieces ahead of what the request took, and the server '
      'gets the same bytes', () async {
    final (file, hash) = await writeTestFile(folder, 'big.bin', 200 * mib);
    final server = await LocalUploadServer.start();
    // The server reads slower than the disk: the connection fills, and
    // the client waits for it.
    server.readPause = const Duration(milliseconds: 5);
    final transport = LocalUploadTransport(server);
    final (mx, room) =
        await streamClient('stream_200', transport, encrypted: false);

    final (send, processed) = await attachByPath(file);
    final source = transport.source = sourceOf(processed);
    final placeholderBytes = processed.file.bytes.length;
    final id = await sendMatrixFile(room, processed);

    final upload = server.uploads.single;
    final event = transport.events.single.body;
    print('200 MB from disk: ${source.bytesRead} bytes read in '
        '${source.opens} opening(s), ${placeholderBytes} bytes held by the '
        'file, reads at most ${transport.mostAhead} bytes '
        '(${transport.mostAhead / DiskFileSource.piece} pieces) ahead of '
        'what the request took; the server got ${upload.bytes} bytes, '
        'sha256 ${upload.sha256Hex} (file $hash); files open after: '
        '${source.openFiles}');
    expect(id, isNotNull);
    expect(send.stage, AttachmentSendStage.sent);
    expect(placeholderBytes, 0);
    expect(upload.complete, isTrue);
    expect(upload.bytes, 200 * mib);
    expect(upload.sha256Hex, hash);
    expect(source.opens, 1);
    expect(source.bytesRead, 200 * mib);
    expect(source.openFiles, 0);
    expect(transport.mostAhead, lessThanOrEqualTo(4 * DiskFileSource.piece));
    expect(event['url'], upload.uri);
    expect(event['info']['size'], 200 * mib);
    expect(event['body'], 'big.bin');

    await mx.dispose(closeDatabase: true);
    transport.closeConnections();
    await server.close();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
      'a message still going up from disk does not hand out its file as '
      'empty bytes', () async {
    final (file, _) = await writeTestFile(folder, 'pending.bin', 9 * mib);
    final server = await LocalUploadServer.start()
      ..holdAfter = 1 * mib;
    final transport = LocalUploadTransport(server);
    final (mx, room) =
        await streamClient('stream_pending', transport, encrypted: false);

    final (send, processed) = await attachByPath(file);
    final sending = sendMatrixFile(room, processed);
    await server.held.first;
    final pending =
        (await mx.database.getEventById(send.transactionId!, room))!;
    Object? given;
    try {
      given = await pending.downloadAndDecryptAttachment();
    } catch (error) {
      given = error;
    }
    server.release();
    print('pending from disk: asked for its file, got ${given.runtimeType}');
    expect(given, isNot(isA<matrix.MatrixFile>()));
    expect(await sending, isNotNull);
    await mx.dispose(closeDatabase: true);
    transport.closeConnections();
    await server.close();
  });

  test(
      "a file over the server's limit is refused before it is read: 0 bytes "
      'read, nothing uploaded', () async {
    final (file, _) = await writeTestFile(folder, 'over.bin', 20 * mib);
    final server = await LocalUploadServer.start();
    final transport = LocalUploadTransport(server)..uploadLimit = 10 * mib;
    final (mx, room) =
        await streamClient('stream_limit', transport, encrypted: false);

    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final id = await sendMatrixFile(room, processed);

    print('20 MB over a 10 MB limit: ${source.bytesRead} bytes read, '
        '${source.opens} openings, ${server.uploads.length} uploads, '
        '${transport.events.length} events');
    expect(id, isNull);
    expect(send.stage, AttachmentSendStage.failed);
    expect(source.bytesRead, 0);
    expect(source.opens, 0);
    expect(server.uploads, isEmpty);
    expect(transport.events, isEmpty);

    await mx.dispose(closeDatabase: true);
    transport.closeConnections();
    await server.close();
  });

  test(
      'the SDK refuses a source over the limit by its length, before '
      'listening to it, also when called by itself', () async {
    final (file, _) = await writeTestFile(folder, 'over2.bin', 9 * mib);
    final server = await LocalUploadServer.start();
    final transport = LocalUploadTransport(server)..uploadLimit = 1 * mib;
    final (mx, _) =
        await streamClient('stream_limit_sdk', transport, encrypted: false);
    final source = (await DiskFileSource.at(file.path))!;
    final read = source.read();

    Object? error;
    try {
      await mx.uploadContentStream(read.bytes, source.length);
    } catch (e) {
      error = e;
    }
    await read.close();
    expect(error, isA<matrix.FileTooBigMatrixException>());
    expect(source.bytesRead, 0);
    expect(source.opens, 0);
    expect(server.uploads, isEmpty);

    await mx.dispose(closeDatabase: true);
    transport.closeConnections();
    await server.close();
  });

  test(
      'a picture over the size limit attached by its path is read into '
      'memory for its preparation, not sent from disk', () async {
    final (big, _) =
        await writeTestFile(folder, 'big.png', streamFromDiskAbove + 1);
    final processed = (await matrixFilesForAttachment(
        PendingFileAttachment(
            path: big.path, name: 'big.png', mimeType: 'image/png'),
        preparer: _CannotDecode()))!;
    print('picture by path: from disk ${processed.file.source != null}, '
        '${processed.file.bytes.length} bytes in memory');
    expect(processed.file.source, isNull);
    expect(processed.file.bytes.length, streamFromDiskAbove + 1);
  });

  test(
      'only a file attached by its path over the size limit is sent from '
      'disk: a small one, one at the limit and one already read are sent '
      'from memory, as before', () async {
    final (small, _) = await writeTestFile(folder, 'small.bin', 1 * mib);
    final (big, _) =
        await writeTestFile(folder, 'big.bin', streamFromDiskAbove + 1);
    final (exact, _) =
        await writeTestFile(folder, 'exact.bin', streamFromDiskAbove);

    Future<matrix.MatrixFile> fileFor(File file, String mimeType) async =>
        (await matrixFilesForAttachment(PendingFileAttachment(
                path: file.path, name: 'a', mimeType: mimeType)))!
            .file;

    final smallFile = await fileFor(small, 'application/octet-stream');
    final exactFile = await fileFor(exact, 'application/octet-stream');
    final bigFile = await fileFor(big, 'application/octet-stream');
    final bigVideo = await fileFor(big, 'video/mp4');
    final fromBytes = (await matrixFilesForAttachment(PendingFileAttachment(
            data: await big.readAsBytes(),
            name: 'a',
            mimeType: 'application/octet-stream')))!
        .file;

    print('from disk: small ${smallFile.source != null}, at the limit '
        '${exactFile.source != null}, over it ${bigFile.source != null} '
        '(video ${bigVideo.source != null}), already read '
        '${fromBytes.source != null}');
    expect(smallFile.source, isNull);
    expect(smallFile.bytes.length, 1 * mib);
    expect(exactFile.source, isNull);
    expect(bigFile.source, isA<DiskFileSource>());
    expect(bigFile.bytes, isEmpty);
    expect(bigFile.size, streamFromDiskAbove + 1);
    expect(bigFile.info['size'], streamFromDiskAbove + 1);
    expect(bigVideo, isA<matrix.MatrixVideoFile>());
    expect(bigVideo.source, isA<DiskFileSource>());
    expect(fromBytes.source, isNull);
  });
}
