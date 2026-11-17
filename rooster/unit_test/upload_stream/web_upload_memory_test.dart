@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../upload_status/fakes.dart' show NoFrames;

@JS('eval')
external JSAny? _eval(JSString code);

num _number(String code) => (_eval(code.toJS)! as JSNumber).toDartDouble;

const _mib = 1024 * 1024;

/// [file] as the picker's `readStream` gives it on the web: slices read one
/// after the other.
Stream<List<int>> _readStream(web.Blob file) async* {
  for (var start = 0; start < file.size; start += _mib) {
    final end = start + _mib < file.size ? start + _mib : file.size;
    final buffer = await file.slice(start, end).arrayBuffer().toDart;
    yield buffer.toDart.asUint8List();
  }
}

/// Counts what the upload reports.
class _Listener implements UploadListener {
  int sent = 0;
  bool answered = false;

  @override
  void uploadStarted(int bodyBytes) {}

  @override
  void uploadSent(int sentBytes) => sent = sentBytes;

  @override
  void uploadHandedOver() {}

  @override
  void uploadAnswered(int status, {required bool matrixError}) =>
      answered = true;

  @override
  void uploadFailed(String error) {}
}

/// A measurement of the browser's bound, not a limit: the web sends a file
/// from the bytes it was read into, so its memory grows by the file. Picks
/// a 50 MB file as the app admits it (read from its stream into memory),
/// makes the SDK's file of it, and uploads it through our HTTP client
/// (`XMLHttpRequest`) to the test page's own server. Prints the peak of the
/// JS heap over its start and the longest task of the page's thread.
void main() {
  test('web: a 50 MB file is read and uploaded; heap and longest task',
      () async {
    const bytes = 50 * _mib;
    _eval('''
      window.__longest = 0; window.__longtasks = 0;
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          window.__longtasks++;
          window.__longest = Math.max(window.__longest, entry.duration);
        }
      }).observe({type: 'longtask'});
      0'''
        .toJS);
    // The picked file lives in the browser's blob store, as one on disk.
    final file = _eval('''(() => {
      const data = new Uint8Array($bytes);
      for (let i = 0; i < data.length; i += 4096) data[i] = i & 255;
      return new File([data], 'big.bin', {type: 'application/octet-stream'});
    })()'''
        .toJS)! as web.File;
    // Let the page settle, and the array that made the file go.
    await Future<void>.delayed(const Duration(seconds: 2));
    _eval('''
      window.__heapStart = performance.memory.usedJSHeapSize;
      window.__heapPeak = window.__heapStart;
      window.__samples = 0;
      window.__sampler = setInterval(() => {
        window.__samples++;
        window.__heapPeak =
            Math.max(window.__heapPeak, performance.memory.usedJSHeapSize);
      }, 10);
      window.__longest = 0; window.__longtasks = 0;
      0'''
        .toJS);
    var longestGap = Duration.zero;
    var last = DateTime.now();
    final ticks = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      if (now.difference(last) > longestGap) longestGap = now.difference(last);
      last = now;
    });
    final watch = Stopwatch()..start();

    final admitted = await admitPickedFiles([
      PlatformFile(name: 'big.bin', size: bytes, readStream: _readStream(file))
    ], maxBytes: null, onRefused: (_, __) {}, web: true);
    final read = watch.elapsedMilliseconds;
    final processed = (await matrixFilesForAttachment(admitted.single))!;
    final origin = Uri.base.replace(path: '/', query: null, fragment: null);
    final client = SpeedHttpClient(
      hosts: HostClassifier(homeserver: () => origin),
      log: SpeedLog(frames: NoFrames()),
    );
    final listener = _Listener();
    final response = await runForUpload(
        listener,
        () => client.send(http.Request(
            'POST', origin.resolve('/_matrix/media/v3/upload?filename=big.bin'))
          ..headers['content-type'] = 'application/octet-stream'
          ..bodyBytes = processed.file.bytes));
    await response.stream.drain<void>();
    client.close();
    watch.stop();
    ticks.cancel();
    // A last sample after the upload, then the observer's last entries.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _eval('clearInterval(window.__sampler); 0'.toJS);

    final heapStart = _number('window.__heapStart');
    final heapPeak = _number('window.__heapPeak');
    print('WEB_MEASURE mb=50 '
        'heap_start_mb=${(heapStart / _mib).toStringAsFixed(1)} '
        'heap_peak_mb=${(heapPeak / _mib).toStringAsFixed(1)} '
        'heap_growth_mb=${((heapPeak - heapStart) / _mib).toStringAsFixed(1)} '
        'heap_samples=${_number('window.__samples').toInt()} '
        'longest_task_ms=${_number('window.__longest').toStringAsFixed(0)} '
        'long_tasks=${_number('window.__longtasks').toInt()} '
        'longest_timer_gap_ms=${longestGap.inMilliseconds} '
        'read_ms=$read total_ms=${watch.elapsedMilliseconds} '
        'from_disk=${processed.file.source != null} '
        'bytes_in_memory=${processed.file.bytes.length} '
        'sent=${listener.sent} answered=${listener.answered}');
    expect(processed.file.source, isNull,
        reason: 'the web has no paths: the file goes from memory');
    expect(processed.file.bytes.length, bytes);
    expect(listener.sent, bytes);
    expect(listener.answered, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
