@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:test/test.dart';

import '../upload_status/fakes.dart';

@JS('eval')
external JSAny? _eval(JSString code);

/// Counts, in the page, every `XMLHttpRequest.abort()` and every `load`
/// event of a request or of its upload.
void _countXhrEvents() => _eval('''(() => {
  window.xhrAborts = 0; window.xhrLoads = 0;
  const abort = XMLHttpRequest.prototype.abort;
  XMLHttpRequest.prototype.abort = function () {
    window.xhrAborts++; return abort.apply(this, arguments);
  };
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    this.addEventListener('load', () => window.xhrLoads++);
    this.upload.addEventListener('load', () => window.xhrLoads++);
    return send.apply(this, arguments);
  };
})()'''
    .toJS);

int _count(String name) => (_eval('window.$name'.toJS)! as JSNumber).toDartInt;

/// Every report of one upload, in order; [onStarted] runs when it starts.
class _Reports implements UploadListener {
  _Reports(this.onStarted);

  final void Function() onStarted;
  final List<String> seen = [];

  @override
  void uploadStarted(int bodyBytes) {
    seen.add('started');
    onStarted();
  }

  @override
  void uploadSent(int sentBytes) {
    if (seen.last != 'sent') seen.add('sent');
  }

  @override
  void uploadHandedOver() => seen.add('handed_over (upload.onload)');

  @override
  void uploadAnswered(int status, {required bool matrixError}) =>
      seen.add('answered (onload)');

  @override
  void uploadFailed(String error) => seen.add('failed $error');
}

void main() {
  test(
      'the cancel of a send aborts its XMLHttpRequest at once, and no load '
      'comes after', () async {
    _countXhrEvents();
    final origin = Uri.base.replace(path: '/', query: null, fragment: null);
    final client = SpeedHttpClient(
      hosts: HostClassifier(homeserver: () => origin),
      log: SpeedLog(frames: NoFrames()),
    );
    final cancel = Completer<void>();
    final clock = Stopwatch();
    // The user cancels as soon as the request has been sent off.
    final reports = _Reports(() {
      clock.start();
      cancel.complete();
    });

    Object? error;
    Duration? abortedAfter;
    try {
      await runForUpload(
          reports,
          () => matrix.runCancellableUpload(
              cancel.future,
              () => client.send(http.Request('POST',
                  origin.resolve('/_matrix/media/v3/upload?filename=a.bin'))
                ..headers['content-type'] = 'application/octet-stream'
                ..bodyBytes = Uint8List(32 * 1024 * 1024))));
    } catch (e) {
      error = e;
      abortedAfter = clock.elapsed;
    }
    // Time for a late load event, if one came.
    await Future<void>.delayed(const Duration(seconds: 1));
    client.close();

    final aborts = _count('xhrAborts');
    final loads = _count('xhrLoads');
    print('cancelled upload: ${error.runtimeType} after $abortedAfter; '
        'XMLHttpRequest.abort() calls $aborts, load events $loads; reports '
        '${reports.seen}');
    expect(aborts, 1);
    expect(loads, 0);
    expect(error, isA<http.RequestAbortedException>());
    expect(abortedAfter, lessThan(const Duration(seconds: 1)));
    expect(reports.seen, ['started', 'failed aborted']);
  });
}
