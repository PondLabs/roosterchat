@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

import 'media_fakes.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock, void Function(List<FrameSample>) _) {}
  @override
  void cancel() {}
}

/// A homeserver on 127.0.0.1 that serves every download with [file] and
/// keeps the client port each download came from: one port is one
/// connection.
class _LocalServer {
  late final HttpServer _server;
  final List<int> downloadPorts = [];
  Uint8List file = Uint8List.fromList(List.generate(300000, (i) => i % 251));

  /// Sent without a content-length (chunked).
  bool chunked = false;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/_matrix/client/versions') {
        response.headers.contentType = ContentType.json;
        response.write('{"versions": ["v1.11"]}');
      } else if (request.uri.path.contains('/media/download/')) {
        downloadPorts.add(request.connectionInfo!.remotePort);
        if (chunked) {
          response.headers.chunkedTransferEncoding = true;
          for (var at = 0; at < file.length; at += 65536) {
            response.add(file.sublist(at, (at + 65536).clamp(0, file.length)));
            await response.flush();
          }
        } else {
          response.contentLength = file.length;
          response.add(file);
        }
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

/// A file attachment's download goes through the account's HTTP client:
/// counted in the speed log and over the account's kept-alive connection.
void main() {
  late _LocalServer server;
  late SpeedLog log;
  late matrix.Client client;

  setUp(() async {
    server = _LocalServer();
    await server.start();
    log = SpeedLog(frames: _NoFrames());
    client = mediaClient(
        SpeedHttpClient(
            log: log, hosts: HostClassifier(homeserver: () => server.uri)),
        server.uri);
  });

  tearDown(() async {
    await server.close();
  });

  Future<Uint8List?> download() {
    final room = matrix.Room(id: '!room:hs.example', client: client);
    final event = attachmentEvent(room,
        msgtype: matrix.MessageTypes.File,
        mimetype: 'application/octet-stream',
        size: server.file.length);
    return MxcFileProvider(client, event.attachmentMxcUrl!, event: event)
        .getFileData();
  }

  test('two downloads in a row: the account client, one connection', () async {
    final first = await download();
    final second = await download();

    expect(first, server.file);
    expect(second, server.file);
    final downloads = log.requests
        .toList()
        .where((r) => r.route.contains('/media/download/'))
        .toList();
    final ports = server.downloadPorts.toSet();
    // ignore: avoid_print
    print('downloads in the speed log: ${downloads.length}; '
        'requests the server saw: ${server.downloadPorts.length}; '
        'connections: ${ports.length}; '
        'bytes logged: ${downloads.map((r) => r.bytesDown).toList()}');
    expect(downloads, hasLength(2));
    expect(downloads.map((r) => r.status), [200, 200]);
    expect(downloads.map((r) => r.bytesDown),
        [server.file.length, server.file.length]);
    expect(ports, hasLength(1), reason: 'a new connection per download');
  });

  test('a download with no content-length comes whole', () async {
    server.chunked = true;
    expect(await download(), server.file);
  });

  test('progress reaches the file size', () async {
    final room = matrix.Room(id: '!room:hs.example', client: client);
    final event = attachmentEvent(room,
        msgtype: matrix.MessageTypes.File, size: server.file.length);
    final provider =
        MxcFileProvider(client, event.attachmentMxcUrl!, event: event);
    final progress = <int>[];
    final listening =
        provider.onProgressChanged!.listen((p) => progress.add(p.downloaded));
    await provider.getFileData();
    // The progress stream delivers after the add.
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();
    expect(progress, isNotEmpty);
    expect(progress.last, server.file.length);
  });
}
