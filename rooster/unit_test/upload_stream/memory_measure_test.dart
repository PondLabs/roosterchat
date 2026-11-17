@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/disk_file_source_io.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../upload_loop/encrypted_fakes.dart' show decryptSent;
import 'stream_fakes.dart';

/// A measurement, not a check: sends a file of `UPLOAD_STREAM_MEASURE_MB`
/// megabytes from disk to a server on 127.0.0.1 (in an encrypted room with
/// `UPLOAD_STREAM_MEASURE_ENCRYPTED=1`), and prints the process's peak
/// memory and the longest the isolate that draws the UI went without
/// running a timer. One size per run: the peak is the process's.
void main() {
  final megabytes =
      int.tryParse(Platform.environment['UPLOAD_STREAM_MEASURE_MB'] ?? '');
  final encrypted =
      Platform.environment['UPLOAD_STREAM_MEASURE_ENCRYPTED'] == '1';

  test('memory and main-isolate gaps while a file goes up from disk',
      skip: megabytes == null
          ? 'UPLOAD_STREAM_MEASURE_MB is not set: a measurement'
          : encrypted
              ? skipWithoutVodozemac
              : false, () async {
    if (encrypted) await initVodozemac();
    final folder = await testFolder();
    try {
      final (file, hash) =
          await writeTestFile(folder, 'measure.bin', megabytes! * mib);
      final server = await LocalUploadServer.start();
      final transport = LocalUploadTransport(server);
      final (mx, room) =
          await streamClient('measure', transport, encrypted: encrypted);
      final (send, processed) = await attachByPath(file);
      // A 1 MB file goes from disk too here, as the 200 MB one does.
      processed.file.source ??= await DiskFileSource.at(file.path);

      final rssBefore = ProcessInfo.maxRss;
      var longestGap = Duration.zero;
      var last = DateTime.now();
      final ticks = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final now = DateTime.now();
        final gap = now.difference(last);
        if (gap > longestGap) longestGap = gap;
        last = now;
      });
      final watch = Stopwatch()..start();
      final id = await sendMatrixFile(room, processed);
      watch.stop();
      ticks.cancel();

      final upload = server.uploads.single;
      final event = transport.events.single;
      // Encrypted: what the server got has the hash the event carries.
      final bool sameBytes;
      if (encrypted) {
        final sent = await decryptSent(mx, room, event);
        final hashes = (sent.content['file'] as Map)['hashes'] as Map;
        final got = base64
            .encode(List.generate(
                32,
                (i) => int.parse(upload.sha256Hex!.substring(i * 2, i * 2 + 2),
                    radix: 16)))
            .replaceAll('=', '');
        sameBytes = hashes['sha256'] == got;
      } else {
        sameBytes = upload.sha256Hex == hash;
      }
      print('MEASURE mb=$megabytes encrypted=$encrypted '
          'peak_rss_before_mb=${(rssBefore / mib).toStringAsFixed(1)} '
          'peak_rss_mb=${(ProcessInfo.maxRss / mib).toStringAsFixed(1)} '
          'rss_now_mb=${(ProcessInfo.currentRss / mib).toStringAsFixed(1)} '
          'longest_main_isolate_gap_ms=${longestGap.inMilliseconds} '
          'encrypted_bytes=${sourceOf(processed).encryptedBytes} '
          'encrypted_in=${sourceOf(processed).encryptedIn} '
          'seconds=${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} '
          'server_bytes=${upload.bytes} same_bytes=$sameBytes '
          'event=${event.type}');
      expect(id, isNotNull);
      expect(send.stage, AttachmentSendStage.sent);
      expect(sameBytes, isTrue);
      await mx.dispose(closeDatabase: true);
      transport.closeConnections();
      await server.close();
    } finally {
      await removeFolder(folder);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
