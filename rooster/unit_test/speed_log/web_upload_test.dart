@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

@JS('eval')
external JSAny? _eval(JSString code);

class _NoFrames implements FrameSource {
  @override
  void listen(void Function(Duration frame) onFrame) {}
  @override
  void cancel() {}
}

/// Counts the bodies sent through `XMLHttpRequest.prototype.send`.
void _spyOnXhr() => _eval('''
  window.__xhrSends = [];
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body) {
    window.__xhrSends.push(body ? body.byteLength : 0);
    return send.call(this, body);
  };
'''
    .toJS);

List<int> _xhrSends() => (globalContext['__xhrSends'] as JSArray<JSNumber>)
    .toDart
    .map((n) => n.toDartInt)
    .toList();

void main() {
  test('a media upload goes out through XMLHttpRequest, timed by upload.onload',
      () async {
    _spyOnXhr();
    // The page that runs this test: a local server, the same origin.
    final origin = Uri.base.replace(path: '/', query: null, fragment: null);
    final log = SpeedLog(frames: _NoFrames());
    final client = SpeedHttpClient(
      hosts: HostClassifier(homeserver: () => origin),
      log: log,
    );

    final body = Uint8List(1024 * 1024);
    final upload = http.Request(
        'POST', origin.resolve('/_matrix/media/v3/upload?filename=cat.png'))
      ..headers['content-type'] = 'application/octet-stream'
      ..bodyBytes = body;
    final response = await client.send(upload);
    await response.stream.drain<void>();

    expect(_xhrSends(), [body.length]);
    final r = log.requests.toList().single;
    expect(r.route, '/_matrix/media/v3/upload');
    expect(r.hostClass, HostClass.homeserver);
    expect(r.status, response.statusCode);
    expect(r.bytesUp, body.length);
    expect(r.handOverBoundary, 'xhr_upload_onload');
    expect(r.bodyHandedOver, isNotNull);
    expect(r.timeToHeaders, isNotNull);
    expect(r.total, greaterThanOrEqualTo(r.bodyHandedOver!));

    // Any other request goes through the usual fetch client, unchanged.
    await client.get(origin.resolve('/_matrix/client/versions'));
    expect(_xhrSends(), [body.length]);
    final other = log.requests.toList().last;
    expect(other.route, '/_matrix/client/versions');
    expect(other.bodyHandedOver, isNull);

    // The report, for the evidence log.
    print(buildSpeedReport(log));
    client.close();
  });
}
