@TestOn('browser')
library;

import 'dart:async';

import 'package:rooster/client/matrix/media/browser_file_source.dart';
import 'package:rooster/client/matrix/media/browser_files_web.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:test/test.dart';

import 'web_fakes.dart';

/// Picks a 50 MB file from a fake dialog, as the app does on the web
/// (`pickFileAttachments`), makes the SDK's file of it, and uploads it as
/// the SDK does (a `FileSendRequest` with a read of its source) through our
/// HTTP client (`XMLHttpRequest`) to the fake server
/// (`web_upload_server.dart`). Checks that no read of the page took the
/// whole file and that the server got its bytes, and prints the peak of
/// the JS heap over its start and the longest task of the page's thread.
///
/// Before the file was sent from the browser's `File`, the same test read
/// it from the picker's stream into memory and sent those bytes: the heap
/// grew by twice the file (`docs/speed-log.md`).
void main() {
  test(
      'web: a 50 MB file goes up as its File, never read whole; heap and '
      'longest task', () async {
    const bytes = 50 * mib;
    eval('''
      window.__longest = 0; window.__longtasks = 0;
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          window.__longtasks++;
          window.__longest = Math.max(window.__longest, entry.duration);
        }
      }).observe({type: 'longtask'});
      0''');
    // The picked file lives in the browser's blob store, as one on disk.
    final (file, sha256Hex) = await pageFile(bytes);
    pickBrowserFiles = () async => [file];
    await resetServer();
    countBlobReads();
    // Let the page settle, and the array that made the file go.
    await Future<void>.delayed(const Duration(seconds: 2));
    eval('''
      window.__heapStart = performance.memory.usedJSHeapSize;
      window.__heapPeak = window.__heapStart;
      window.__samples = 0;
      window.__sampler = setInterval(() => {
        window.__samples++;
        window.__heapPeak =
            Math.max(window.__heapPeak, performance.memory.usedJSHeapSize);
      }, 10);
      window.__longest = 0; window.__longtasks = 0;
      0''');
    var longestGap = Duration.zero;
    var last = DateTime.now();
    final ticks = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      if (now.difference(last) > longestGap) longestGap = now.difference(last);
      last = now;
    });
    final watch = Stopwatch()..start();

    final admitted = await pickFileAttachments(
        maxBytes: () async => null, onRefused: (_, __) {}, web: true);
    final read = watch.elapsedMilliseconds;
    final processed = (await matrixFilesForAttachment(admitted.single))!;
    final source = processed.file.source! as BrowserFileSource;
    final reading = source.read();
    final reports = Reports();
    final response = await uploadRead(reading, source.length, reports: reports);
    await reading.close();
    watch.stop();
    ticks.cancel();
    // A last sample after the upload, then the observer's last entries.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    eval('clearInterval(window.__sampler); 0');

    final heapStart = jsNumber('window.__heapStart');
    final heapPeak = jsNumber('window.__heapPeak');
    final reads = blobReads();
    final received = (await serverUploads()).single;
    print('WEB_MEASURE mb=50 '
        'heap_start_mb=${(heapStart / mib).toStringAsFixed(1)} '
        'heap_peak_mb=${(heapPeak / mib).toStringAsFixed(1)} '
        'heap_growth_mb=${((heapPeak - heapStart) / mib).toStringAsFixed(1)} '
        'heap_samples=${jsNumber('window.__samples').toInt()} '
        'longest_task_ms=${jsNumber('window.__longest').toStringAsFixed(0)} '
        'long_tasks=${jsNumber('window.__longtasks').toInt()} '
        'longest_timer_gap_ms=${longestGap.inMilliseconds} '
        'read_ms=$read total_ms=${watch.elapsedMilliseconds} '
        'from_file=${processed.file.source != null} '
        'bytes_in_memory=${processed.file.bytes.length} '
        'blob_reads=${reads.length} blob_read_bytes=${reads.fold(0, (a, b) => a + b)} '
        'whole_file_reads=${reads.where((r) => r >= bytes).length} '
        'sent=${reports.sent} status=${response.statusCode} '
        'server_bytes=${received['bytes']} '
        'server_sha256_matches=${received['sha256'] == sha256Hex}');
    expect(admitted.single.data, isNull);
    expect(processed.file.bytes, isEmpty);
    expect(reads.where((r) => r >= bytes), isEmpty,
        reason: 'no arrayBuffer() (or other read) of the whole file');
    expect(source.bytesRead, 1, reason: 'one byte, to know it is readable');
    expect(response.statusCode, 200);
    expect(reading.complete, isTrue);
    expect(reports.sent, bytes);
    expect(received['bytes'], bytes);
    expect(received['sha256'], sha256Hex);
  }, skip: skipWithoutServer, timeout: const Timeout(Duration(minutes: 3)));

  // The test page runs the development compiler, whose pointycastle is
  // about 35 times slower than a release build's: the heap is what this
  // measures here, the cipher's time is measured on a release build.
  test(
      'web, encrypted room: a 16 MiB file is encrypted in pieces into a '
      'Blob; heap', () async {
    const bytes = 16 * mib;
    final (file, _) = await pageFile(bytes);
    final source = BrowserFileSource(file);
    await resetServer();
    await Future<void>.delayed(const Duration(seconds: 2));
    eval('''
      window.__heapStart = performance.memory.usedJSHeapSize;
      window.__heapPeak = window.__heapStart;
      window.__sampler = setInterval(() => {
        window.__heapPeak =
            Math.max(window.__heapPeak, performance.memory.usedJSHeapSize);
      }, 10);
      0''');
    final watch = Stopwatch()..start();
    final reading = source.readEncrypted();
    final response = await uploadRead(reading, bytes);
    await reading.close();
    watch.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    eval('clearInterval(window.__sampler); 0');
    final growth =
        jsNumber('window.__heapPeak') - jsNumber('window.__heapStart');
    final received = (await serverUploads()).single;
    print('WEB_MEASURE_ENCRYPTED mib=16 '
        'heap_growth_mb=${(growth / mib).toStringAsFixed(1)} '
        'largest_read_kib=${source.largestRead ~/ 1024} '
        'total_ms=${watch.elapsedMilliseconds} '
        'server_bytes=${received['bytes']}');
    expect(response.statusCode, 200);
    expect(reading.complete, isTrue);
    expect(received['bytes'], bytes);
    expect(growth, lessThan(bytes / 2),
        reason: 'the file is never held whole, encrypted or not');
  }, skip: skipWithoutServer, timeout: const Timeout(Duration(minutes: 3)));
}
