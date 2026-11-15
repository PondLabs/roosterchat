@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
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

/// A body handed over as a stream whose length is not known.
class _UnsizedRequest extends http.BaseRequest {
  _UnsizedRequest(super.method, super.url, this.body);

  final List<int> body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream.fromBytes(body);
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

/// An error type the speed log knows nothing about.
class _OddFailure implements Exception {}

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

  test('a MultipartRequest arrives with its content-type, as without us',
      () async {
    final seen = <String?>[];
    handler = (request) async {
      seen.add(request.headers.value('content-type'));
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    };
    // The multipart content-type, with its boundary, is set in finalize().
    http.MultipartRequest multipart() =>
        http.MultipartRequest('POST', base.resolve('/_matrix/media/v3/upload'))
          ..fields['a'] = 'b';

    final plain = http.Client();
    await (await plain.send(multipart())).stream.drain<void>();
    plain.close();
    await (await client.send(multipart())).stream.drain<void>();

    expect(seen[0], startsWith('multipart/form-data; boundary='));
    expect(seen[1], startsWith('multipart/form-data; boundary='));
    expect(log.requests.toList().single.bytesUp, greaterThan(0));
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

  test('an error is written as a fixed name, never its runtime type', () async {
    final url = Uri.parse('https://secret-host.example/_matrix/client/v3/sync');
    final cases = <Object, String>{
      http.RequestAbortedException(url): SpeedError.aborted,
      http.ClientException('secret', url): SpeedError.client,
      TimeoutException('secret'): SpeedError.timeout,
      const SocketException('secret'): SpeedError.socket,
      const HandshakeException('secret'): SpeedError.tls,
      const TlsException('secret'): SpeedError.tls,
      const HttpException('secret'): SpeedError.http,
      _OddFailure(): SpeedError.other,
      StateError('secret'): SpeedError.other,
    };
    for (final thrown in cases.keys) {
      final failing = SpeedHttpClient(
          inner: MockClient((_) async => throw thrown), log: log);
      await expectLater(failing.get(url), throwsA(same(thrown)));
    }
    // An error in the middle of a response body.
    final cut = SpeedHttpClient(
      inner: MockClient.streaming((request, body) async =>
          http.StreamedResponse(
              Stream.error(const SocketException('secret')), 200)),
      log: log,
    );
    await expectLater(cut.get(url), throwsA(isA<SocketException>()));

    expect(log.requests.toList().map((r) => r.error),
        [...cases.values, SpeedError.socket]);
    expect(log.requests.toList().map((r) => r.error),
        everyElement(isIn(SpeedError.all)));
    final report = buildSpeedReport(log);
    expect(report, contains('error=other'));
    for (final type in ['_OddFailure', 'StateError', 'Exception', 'secret']) {
      expect(report, isNot(contains(type)), reason: type);
    }
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

  test('different requests of one route are each attempt 1', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    };
    final span = log.startSpan('text_send');
    await span.run(() async {
      // The file, then its thumbnail: two uploads, no retry.
      await client.post(
          base.resolve('/_matrix/media/v3/upload?filename=photo.jpg'),
          body: Uint8List(2048));
      await client.post(
          base.resolve('/_matrix/media/v3/upload?filename=thumb.jpg'),
          body: Uint8List(128));
      // Two to-device messages with different transaction ids.
      await client.put(
          base.resolve('/_matrix/client/v3/sendToDevice/m.room.encrypted/t1'),
          body: '{}');
      await client.put(
          base.resolve('/_matrix/client/v3/sendToDevice/m.room.encrypted/t2'),
          body: '{}');
    });
    span.finish();
    expect(log.requests.toList().map((r) => r.attempt), [1, 1, 1, 1]);
  });

  test('an open span remembers a bounded number of requests', () async {
    final quick = SpeedHttpClient(
      inner: MockClient((_) async => http.Response('{}', 200)),
      hosts: HostClassifier(homeserver: () => base),
      log: log,
    );
    Uri sync(int i) => base.resolve('/_matrix/client/v3/sync?since=s$i');
    final span = log.startSpan('sync');
    await span.run(() async {
      for (var i = 0; i < 5000; i++) {
        await quick.get(sync(i));
      }
      // Remembered before the cap: still counted. Past it: attempt 1.
      await quick.get(sync(0));
      await quick.get(sync(4999));
    });

    expect(span.rememberedRequests, SpeedLog.maxRememberedRequests);
    final attempts = log.requests.toList().map((r) => r.attempt).toList();
    expect(attempts.sublist(attempts.length - 2), [2, 1]);
    expect(attempts.sublist(0, attempts.length - 2), everyElement(1));
    span.finish();
    expect(span.rememberedRequests, 0);
  });

  test('a body of unknown length is attempt 1 each time', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    };
    final url = base.resolve('/_matrix/media/v3/upload');
    final span = log.startSpan('text_send');
    await span.run(() async {
      // Two different files to one URL: with no length, nothing tells them
      // from a retry.
      for (final body in [
        [1, 2, 3],
        List.filled(9000, 7),
      ]) {
        final response = await client.send(_UnsizedRequest('POST', url, body));
        await response.stream.drain<void>();
      }
    });

    final records = log.requests.toList();
    expect(records.map((r) => r.bytesUp), [3, 9000]);
    expect(records.map((r) => r.attempt), [1, 1]);
    expect(span.rememberedRequests, 0);
    span.finish();
  });

  test(
      'the same request sent again is attempt 2, and the span forgets it '
      'when it finishes', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    };
    final span = log.startSpan('text_send');
    Future<void> upload() =>
        client.post(base.resolve('/_matrix/media/v3/upload?filename=photo.jpg'),
            body: Uint8List(2048));
    Future<void> toDevice() => client.put(
        base.resolve('/_matrix/client/v3/sendToDevice/m.room.encrypted/t1'),
        body: '{}');
    await span.run(() async {
      await upload();
      await toDevice();
      await upload();
      await toDevice();
    });
    expect(log.requests.toList().map((r) => r.attempt), [1, 1, 2, 2]);
    expect(span.rememberedRequests, 2);

    span.finish();
    expect(span.rememberedRequests, 0);
    // A request still running in the finished span's zone counts as 1.
    await span.run(upload);
    expect(log.requests.toList().last.attempt, 1);
    expect(span.rememberedRequests, 0);
  });
}
