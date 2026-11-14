@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(void Function(Duration frame) onFrame) {}
  @override
  void cancel() {}
}

/// A body handed over as a stream, as a large upload would be.
class _StreamedBodyRequest extends http.BaseRequest {
  _StreamedBodyRequest(super.method, super.url, this.body, int length) {
    contentLength = length;
  }

  final Stream<List<int>> body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}

/// The real transport, counting the body chunks it takes from our client.
class _TransportSpy extends http.BaseClient {
  _TransportSpy(this.onChunk);

  final void Function() onChunk;
  final http.Client _io = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final body = request.finalize().map((chunk) {
      onChunk();
      return chunk;
    });
    return _io.send(_StreamedBodyRequest(
        request.method, request.url, body, request.contentLength!)
      ..headers.addAll(request.headers));
  }

  @override
  void close() => _io.close();
}

void main() {
  late HttpServer server;
  late Uri base;
  late SpeedLog log;
  late SpeedHttpClient client;
  late Future<void> Function(HttpRequest request) handler;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) => handler(request));
    log = SpeedLog(frames: _NoFrames());
    client = SpeedHttpClient(
      hosts: HostClassifier(homeserver: () => base),
      log: log,
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('records an upload, with the time from its last byte to the answer',
      () async {
    const delay = Duration(milliseconds: 500);
    var received = 0;
    handler = (request) async {
      await for (final chunk in request) {
        received += chunk.length;
      }
      await Future<void>.delayed(delay);
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"content_uri":"mxc://hs/abc"}');
      await request.response.close();
    };

    final body = Uint8List(1024 * 1024);
    final request = http.Request(
        'POST', base.resolve('/_matrix/media/v3/upload?filename=cat.png'))
      ..headers['authorization'] = 'Bearer secret'
      ..bodyBytes = body;
    final response = await http.Response.fromStream(await client.send(request));

    expect(response.statusCode, 200);
    expect(received, body.length);
    final r = log.requests.toList().single;
    expect(r.method, 'POST');
    expect(r.route, '/_matrix/media/v3/upload');
    expect(r.hostClass, HostClass.homeserver);
    expect(r.status, 200);
    expect(r.attempt, 1);
    expect(r.bytesUp, body.length);
    expect(r.bytesDown, response.bodyBytes.length);
    expect(r.handOverBoundary, 'transport');
    expect(r.bodyHandedOver, isNotNull);
    expect(r.timeToHeaders, greaterThan(r.bodyHandedOver!));
    expect(r.total, greaterThanOrEqualTo(r.timeToHeaders!));
    final toAnswer = r.handedOverToAnswer!.inMilliseconds;
    expect(toAnswer, inInclusiveRange(400, 900));
    expect(
        r.uploadBytesPerSecond, closeTo(body.length / (toAnswer / 1000), 1e5));
    // The measurement, for the evidence log.
    print('handed_over=${r.bodyHandedOver!.inMilliseconds}ms '
        'headers=${r.timeToHeaders!.inMilliseconds}ms '
        'to_answer=${toAnswer}ms total=${r.total!.inMilliseconds}ms');
  });

  test('streams the body: never pulled more than a few chunks ahead', () async {
    const chunkSize = 64 * 1024;
    const chunks = 128;
    var serverBytes = 0;
    var pulled = 0;
    var takenByTransport = 0;
    var maxAheadOfTransport = 0;
    var maxAheadOfServer = 0;
    final releaseLast = Completer<void>();
    final serverGotAllButLast = Completer<void>();

    handler = (request) async {
      await for (final chunk in request) {
        serverBytes += chunk.length;
        if (serverBytes == (chunks - 1) * chunkSize) {
          serverGotAllButLast.complete();
        }
      }
      request.response.write('{}');
      await request.response.close();
    };

    Stream<List<int>> source() async* {
      for (var i = 0; i < chunks; i++) {
        if (i == chunks - 1) await releaseLast.future;
        pulled++;
        maxAheadOfTransport =
            max(maxAheadOfTransport, pulled - takenByTransport);
        maxAheadOfServer =
            max(maxAheadOfServer, pulled - serverBytes ~/ chunkSize);
        yield Uint8List(chunkSize);
      }
    }

    client = SpeedHttpClient(
      inner: _TransportSpy(() => takenByTransport++),
      hosts: HostClassifier(homeserver: () => base),
      log: log,
    );
    final sent = client.send(_StreamedBodyRequest(
      'POST',
      base.resolve('/_matrix/media/v3/upload'),
      source(),
      chunks * chunkSize,
    ));

    // The server has 127 chunks while the last one is still held: the body
    // went out as a stream, not after being gathered.
    await serverGotAllButLast.future.timeout(const Duration(seconds: 10));
    expect(pulled, chunks - 1, reason: 'the last chunk is still held');
    releaseLast.complete();
    final response = await http.Response.fromStream(await sent);

    expect(response.statusCode, 200);
    expect(serverBytes, chunks * chunkSize);
    expect(takenByTransport, chunks);
    // The measurement, for the evidence log. Ahead of the server, the gap is
    // the kernel's socket send buffer (net.ipv4.tcp_wmem, 4 MB here), which
    // the transport writes into without waiting for the server to read.
    print('most chunks pulled ahead: of the transport $maxAheadOfTransport, '
        'of the server $maxAheadOfServer (of $chunks)');
    expect(maxAheadOfTransport, lessThanOrEqualTo(2));
    expect(log.requests.toList().single.bytesUp, chunks * chunkSize);
  });

  test('a 429 records retry_after_ms', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 429
        ..write('{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":2500}');
      await request.response.close();
    };
    final response = await client.get(base.resolve('/_matrix/client/versions'));

    expect(response.statusCode, 429);
    final r = log.requests.toList().single;
    expect(r.status, 429);
    expect(r.retryAfterMs, 2500);
  });

  test('a request that gets no response records the error type only', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    await expectLater(
        client.get(Uri.parse('http://127.0.0.1:$port/_matrix/client/versions')),
        throwsA(anything));
    final r = log.requests.toList().single;
    expect(r.status, isNull);
    expect(r.error, isNotNull);
    expect(r.error, isNot(contains('127.0.0.1')));
    expect(r.hostClass, HostClass.other);
  });

  test('numbers repeated requests of a span as attempts', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    };
    final span = log.startSpan('text_send');
    await span.run(() async {
      for (var i = 0; i < 3; i++) {
        await client.put(
            base.resolve(
                '/_matrix/client/v3/rooms/!r:hs/send/m.room.message/t1'),
            body: '{}');
      }
    });
    await client.get(base.resolve('/_matrix/client/versions'));

    final records = log.requests.toList();
    expect(records.map((r) => r.attempt), [1, 2, 3, 1]);
    expect(records.take(3).map((r) => r.operationId), everyElement(span.id));
    expect(records.last.operationId, isNull);
    expect(jsonEncode(records.map((r) => r.route).toList()),
        isNot(contains('!r:hs')));
  });
}
