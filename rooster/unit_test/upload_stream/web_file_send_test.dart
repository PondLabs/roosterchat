@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/media/browser_file_source.dart';
import 'package:rooster/client/matrix/media/browser_files_web.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/ui/organisms/chat/dropped_files.dart';
import 'package:rooster/utils/clipboard/pasted_files_web.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'web_fakes.dart';

/// [hex] (a SHA-256 from the server) as an event's unpadded base64.
String _base64(String hex) => base64.encode([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ]).replaceAll('=', '');

/// A file of [bytes] whose reads fail with the browser's NotReadableError,
/// as a picked file that was changed or deleted since, once `window.__gone`
/// is true. [gone] sets it from the start.
Future<web.File> _fileThatGoes(int bytes, {bool gone = false}) async {
  final (file, _) = await pageFile(bytes);
  eval('window.__gone = $gone; 0');
  (file as JSObject).setProperty('slice'.toJS, eval('''(function () {
        const piece = Blob.prototype.slice.apply(this, arguments);
        const read = piece.arrayBuffer;
        piece.arrayBuffer = function () {
          return window.__gone
              ? Promise.reject(new DOMException('gone', 'NotReadableError'))
              : read.apply(this, arguments);
        };
        return piece;
      })'''));
  return file;
}

void main() =>
    group('a file sent from the browser', _tests, skip: skipWithoutServer);

void _tests() {
  setUp(() async {
    await resetServer();
    countBlobReads();
  });

  test(
      'a picked file over the server limit is refused by its File.size, '
      'unread', () async {
    final (file, _) = await pageFile(20 * mib);
    pickBrowserFiles = () async => [file];
    countBlobReads();
    final refused = <(int, int)>[];

    final attached = await pickFileAttachments(
        maxBytes: () async => 10 * mib,
        onRefused: (bytes, max) => refused.add((bytes, max)),
        web: true);

    expect(attached, isEmpty);
    expect(refused, [(20 * mib, 10 * mib)]);
    expect(blobReads(), isEmpty, reason: 'no byte of it read');
  });

  test(
      'pasted and dropped files over 8 MiB go as their File, unread; a '
      'small file and a picture are read, as before', () async {
    final (big, bigHash) = await pageFile(9 * mib);
    final (small, _) = await pageFile(mib, name: 'small.bin');
    final (photo, _) = await pageFile(9 * mib, name: 'photo.png');
    countBlobReads();

    final pasted =
        await readPastedFiles([big, small, photo], maxBytes: 10 * mib);
    expect(pasted[0].data, isNull);
    expect(pasted[0].source, isA<BrowserFileSource>());
    expect(pasted[0].size, 9 * mib);
    expect(pasted[1].data, hasLength(mib));
    expect(pasted[2].data, hasLength(9 * mib));

    countBlobReads();
    final url = web.URL.createObjectURL(big);
    final [dropped] = await attachmentsFromDroppedFiles(
        [XFile(url, name: 'big.bin', length: 9 * mib)],
        inBrowser: true);
    expect(dropped.data, isNull);
    expect(dropped.size, 9 * mib);
    expect(blobReads(), isEmpty);

    // What was dropped is the file: its bytes reach the server.
    final read = dropped.source!.read();
    final response = await uploadRead(read, 9 * mib);
    await read.close();
    expect(response.statusCode, 200);
    expect((await serverUploads()).single['sha256'], bigHash);
    expect(blobReads(), [1]);
  });

  group('limits and cancel, on a File', () {
    final stall = UploadLimits.stall;
    tearDown(() => UploadLimits.stall = stall);

    test(
        'the count goes up with upload.onprogress to the file size, then '
        'the answer is waited for', () async {
      final (file, hash) = await pageFile(16 * mib);
      final read = BrowserFileSource(file).read();
      final reports = Reports();
      final response = await uploadRead(read, 16 * mib, reports: reports);
      await read.close();
      expect(response.statusCode, 200);
      expect(reports.sent, 16 * mib);
      expect(reports.seen, ['started', 'sent', 'handed_over', 'answered 200']);
      expect((await serverUploads()).single['sha256'], hash);
    });

    test('a connection that takes no byte for the stall limit ends it',
        () async {
      UploadLimits.stall = const Duration(seconds: 2);
      final (file, _) = await pageFile(48 * mib);
      final read = BrowserFileSource(file).read();
      final reports = Reports();
      Object? error;
      try {
        await uploadRead(read, 48 * mib,
            reports: reports, query: {'hold': '1'});
      } catch (e) {
        error = e;
      }
      await read.close();
      expect(error, isA<UploadTimeoutException>());
      expect(reports.seen.last, 'failed upload_stalled');
      expect(reports.sent, lessThan(48 * mib));
      expect(read.failure, isNull,
          reason: 'the file is still there: a new attempt may go');
    });

    test('a cancel aborts the XMLHttpRequest at once', () async {
      final (file, _) = await pageFile(48 * mib);
      final read = BrowserFileSource(file).read();
      final reports = Reports();
      final cancel = Completer<void>();
      Timer(const Duration(milliseconds: 500), cancel.complete);
      final clock = Stopwatch()..start();
      Object? error;
      try {
        await uploadRead(read, 48 * mib,
            reports: reports, query: {'hold': '1'}, cancel: cancel.future);
      } catch (e) {
        error = e;
      }
      await read.close();
      expect(error, isA<http.RequestAbortedException>());
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
      expect(reports.seen.last, 'failed aborted');
      expect(read.complete, isFalse);
    });
  });

  group('a file that changed since it was picked', () {
    test(
        'unreadable when its send starts: it fails as changed, and nothing '
        'goes up, in the clear or encrypted', () async {
      final source = BrowserFileSource(await _fileThatGoes(mib, gone: true));
      for (final read in [source.read(), source.readEncrypted()]) {
        Object? error;
        try {
          await uploadRead(read, mib);
        } catch (e) {
          error = e;
        }
        await read.close();
        expect(error, isA<matrix.FileSourceChangedException>());
        expect(read.failure, isA<matrix.FileSourceChangedException>());
        expect(read.complete, isFalse);
      }
      expect(await serverUploads(), isEmpty);
    });

    test(
        'a send cut once it is unreadable says it changed; one cut while it '
        'is readable does not, and its new attempt reads the File again',
        () async {
      final source = BrowserFileSource(await _fileThatGoes(16 * mib));

      final cut = source.read();
      await expectLater(uploadRead(cut, 16 * mib, query: {'drop': '$mib'}),
          throwsA(isA<http.ClientException>()));
      await cut.close();
      expect(cut.failure, isNull, reason: 'a network failure: tried again');

      final again = source.read();
      final response = await uploadRead(again, 16 * mib);
      await again.close();
      expect(response.statusCode, 200);
      expect(again.complete, isTrue);
      final uploads = await serverUploads();
      expect(uploads.last['bytes'], 16 * mib);
      expect(uploads.last['complete'], isTrue);

      final gone = source.read();
      await expectLater(uploadRead(gone, 16 * mib, query: {'drop': '$mib'}),
          throwsA(isA<http.ClientException>()));
      eval('window.__gone = true; 0');
      // The SDK closes the read, then asks it why the request failed.
      await gone.close();
      expect(gone.failure, isA<matrix.FileSourceChangedException>());
      expect(gone.complete, isFalse);
    });
  });

  test(
      'an empty file goes up complete, in the clear and encrypted: the '
      'browser fires no upload.onload for an empty body', () async {
    final (file, hash) = await pageFile(0, name: 'empty.bin');
    final source = BrowserFileSource(file);
    for (final read in [source.read(), source.readEncrypted()]) {
      final response = await uploadRead(read, 0, query: {'keep': '1'})
          .timeout(const Duration(seconds: 10));
      expect(response.statusCode, 200);
      expect(read.complete, isTrue);
      await read.close();
    }
    final uploads = await serverUploads();
    expect([for (final u in uploads) u['bytes']], [0, 0]);
    expect(uploads[0]['sha256'], hash);
  });

  group('encrypted', () {
    // Not a multiple of a piece nor of an AES block.
    const bytes = mib + 5;

    test(
        'each attempt encrypts the File in pieces with a new key; what went '
        'up decrypts to the file with the SDK, and no read took it whole',
        () async {
      final (file, hash) = await pageFile(bytes);
      final source = BrowserFileSource(file);
      countBlobReads();
      final keys = <matrix.EncryptedFile>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        final read = source.readEncrypted();
        final response = await uploadRead(read, bytes, query: {'keep': '1'});
        await read.close();
        expect(response.statusCode, 200);
        expect(read.complete, isTrue);
        final encryption = read.encryption!;
        keys.add(encryption);
        final upload = (await serverUploads())[attempt];
        expect(upload['bytes'], bytes);
        expect(upload['sha256'], isNot(hash), reason: 'never in the clear');
        expect(_base64(upload['sha256'] as String), encryption.sha256,
            reason: "the event's hash is that of what went up");
        expect(await serverDecrypt(attempt, encryption), hash);
        final iv = base64.decode(base64.normalize(encryption.iv));
        expect(iv.sublist(8), Uint8List(8), reason: 'the counter at zero');
      }
      expect(keys[0].k, isNot(keys[1].k));
      expect(keys[0].iv, isNot(keys[1].iv));
      expect(source.largestRead, BrowserFileSource.piece);
      expect(blobReads().every((r) => r <= BrowserFileSource.piece), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a cancel while it is encrypted stops the reads; nothing goes up',
        () async {
      final (file, _) = await pageFile(4 * mib);
      final source = BrowserFileSource(file);
      final read = source.readEncrypted();
      final cancel = Completer<void>();
      final upload = uploadRead(read, 4 * mib, cancel: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // As the SDK does on a cancel: the attempt ends, its read is closed.
      cancel.complete();
      await read.close();
      await expectLater(upload, throwsA(anything));
      final readThen = source.bytesRead;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(source.bytesRead, readThen, reason: 'no read after the close');
      expect(source.bytesRead, lessThan(4 * mib));
      expect(await serverUploads(), isEmpty);
    });
  });
}
