@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/clipboard/pasted_files_web.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'fakes.dart';

@JS('eval')
external JSAny? _eval(JSString code);

/// Every report of one upload, in order.
class _Reports implements UploadListener {
  final List<String> seen = [];
  final List<int> sent = [];
  int? body;

  @override
  void uploadStarted(int bodyBytes) {
    body = bodyBytes;
    seen.add('started');
  }

  @override
  void uploadSent(int sentBytes) {
    sent.add(sentBytes);
    if (seen.last != 'sent') seen.add('sent');
  }

  @override
  void uploadHandedOver() => seen.add('handed_over');

  @override
  void uploadAnswered(int status, {required bool matrixError}) =>
      seen.add('answered');

  @override
  void uploadFailed(String error) => seen.add('failed $error');
}

void main() {
  test(
      'a media upload counts its bytes from upload.onprogress, then waits '
      'for the server after upload.onload', () async {
    // The page that runs this test: a local server, the same origin.
    final origin = Uri.base.replace(path: '/', query: null, fragment: null);
    final client = SpeedHttpClient(
      hosts: HostClassifier(homeserver: () => origin),
      log: SpeedLog(frames: NoFrames()),
    );
    final reports = _Reports();
    final body = Uint8List(4 * 1024 * 1024);

    final response = await runForUpload(
        reports,
        () => client.send(http.Request(
            'POST', origin.resolve('/_matrix/media/v3/upload?filename=a.bin'))
          ..headers['content-type'] = 'application/octet-stream'
          ..bodyBytes = body));
    await response.stream.drain<void>();
    client.close();

    print('reports: ${reports.seen}, counts: ${reports.sent}');
    expect(reports.body, body.length);
    expect(reports.seen, ['started', 'sent', 'handed_over', 'answered']);
    expect(reports.sent, isNotEmpty);
    expect(reports.sent.last, body.length,
        reason: 'the last progress event counts the whole body');
    expect(reports.sent, orderedEquals([...reports.sent]..sort()));
  });

  test(
      "a pasted file over the limit is refused by File.size, before "
      'arrayBuffer() reads it', () async {
    // A File-shaped object that counts the reads of its bytes.
    final big = _eval('''({
      size: 60000000, name: 'big.png', type: 'image/png', reads: 0,
      arrayBuffer() { this.reads++; return Promise.resolve(new ArrayBuffer(8)); }
    })'''
        .toJS)! as JSObject;
    final small = web.File(
        [
          Uint8List.fromList([1, 2, 3]).toJS
        ].toJS,
        'small.png',
        web.FilePropertyBag(type: 'image/png'));
    final refused = <int>[];

    final read = await readPastedFiles([big as web.File, small],
        maxBytes: 50000000, onRefused: (bytes, _) => refused.add(bytes));

    expect((big['reads'] as JSNumber).toDartInt, 0);
    expect(refused, [60000000]);
    expect(read.single.data, [1, 2, 3]);
    expect(read.single.name, 'small.png');
  });
}
