// The fake media server of the Chrome tests in this folder: a Dart VM
// program on 127.0.0.1 that runs the test command given after it, with the
// server's address as `--dart-define=WEB_UPLOAD_SERVER=<url>`, and stops
// with it (its exit code is the command's). From `rooster/`, with the
// `test/` bridge of the "Chrome test" steps:
//
//   dart run unit_test/upload_stream/web_upload_server.dart \
//     flutter test --platform chrome --dart-define=PLATFORM=web \
//     test/web_file_send_test.dart
//
// `POST .../upload` reads the body as it arrives, counts it and hashes it
// (SHA-256), and answers an `mxc://` URI. Its query can ask for `keep=1`
// (keep the body), `drop=<n>` (close the connection after n bytes) or
// `hold=1` (stop reading, never answer). `GET /_test/uploads` lists what
// arrived; `POST /_test/decrypt` decrypts a kept body with the SDK's
// decryptor (vodozemac, from VODOZEMAC_LIB_DIR) and gives the SHA-256 of
// what came out. Every answer allows any origin: the test page is on
// another port.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:vodozemac/vodozemac.dart' as vod;

class _Upload {
  int bytes = 0;
  String? sha256Hex;
  bool complete = false;
  Uint8List? body;

  Map<String, Object?> toJson() =>
      {'bytes': bytes, 'sha256': sha256Hex, 'complete': complete};
}

final _uploads = <_Upload>[];
final _held = <HttpRequest>[];

Future<void> main(List<String> command) async {
  if (command.isEmpty) {
    stderr.writeln('usage: web_upload_server.dart <test command...>');
    exit(64);
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(_handle);
  final url = 'http://127.0.0.1:${server.port}';
  stdout.writeln('web_upload_server: $url');
  final process = await Process.start(command.first,
      [...command.skip(1), '--dart-define=WEB_UPLOAD_SERVER=$url'],
      runInShell: true);
  final out = process.stdout.pipe(stdout);
  final err = process.stderr.pipe(stderr);
  final code = await process.exitCode;
  await Future.wait([out, err]);
  for (final request in _held) {
    request.response.detachSocket().then((s) => s.destroy(), onError: (_) {});
  }
  await server.close(force: true);
  exit(code);
}

void _allow(HttpResponse response) => response.headers
  ..set('access-control-allow-origin', '*')
  ..set('access-control-allow-headers', 'authorization, content-type')
  ..set('access-control-allow-methods', 'GET, POST, PUT, OPTIONS');

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  _allow(response);
  try {
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
    } else if (request.uri.path.endsWith('/upload')) {
      if (!await _upload(request)) return;
    } else if (request.uri.path == '/_test/uploads') {
      response.write(jsonEncode([for (final u in _uploads) u.toJson()]));
    } else if (request.uri.path == '/_test/reset') {
      _uploads.clear();
    } else if (request.uri.path == '/_test/decrypt') {
      response.write(jsonEncode(await _decrypt(request)));
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  } catch (error) {
    stderr.writeln('web_upload_server: $error');
  }
}

/// Reads an upload. False when its connection was dropped or is held.
Future<bool> _upload(HttpRequest request) async {
  final query = request.uri.queryParameters;
  final keep = query['keep'] == '1';
  final drop = int.tryParse(query['drop'] ?? '');
  final upload = _Upload();
  _uploads.add(upload);
  if (query['hold'] == '1') {
    // Nothing read, no answer: the connection fills and the client waits.
    _held.add(request);
    return false;
  }
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  final body = BytesBuilder(copy: false);
  await for (final piece in request) {
    upload.bytes += piece.length;
    hash.add(piece);
    if (keep) body.add(piece);
    if (drop != null && upload.bytes >= drop) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return false;
    }
  }
  hash.close();
  upload
    ..sha256Hex = digest.value.toString()
    ..complete = true
    ..body = keep ? body.takeBytes() : null;
  request.response.headers.contentType = ContentType.json;
  request.response
      .write(jsonEncode({'content_uri': 'mxc://127.0.0.1/${_uploads.length}'}));
  return true;
}

/// Decrypts the kept body of upload `index` with the key, iv and hash
/// asked, as the SDK decrypts a file: null when the hash does not match.
Future<Map<String, Object?>> _decrypt(HttpRequest request) async {
  final ask = jsonDecode(await utf8.decodeStream(request)) as Map;
  final dir = Platform.environment['VODOZEMAC_LIB_DIR'];
  if (dir == null) return {'error': 'VODOZEMAC_LIB_DIR is not set'};
  if (!vod.isInitialized()) {
    var path = dir.replaceAll(r'\', '/');
    if (!path.startsWith('/')) path = '/$path';
    await vod.init(libraryPath: path.endsWith('/') ? path : '$path/');
  }
  final body = _uploads[ask['index'] as int].body!;
  final clear = await matrix.decryptFileImplementation(matrix.EncryptedFile(
    data: body,
    k: ask['k'] as String,
    iv: ask['iv'] as String,
    sha256: ask['sha256'] as String,
  ));
  return {
    'decrypted': clear != null,
    'sha256': clear == null ? null : sha256.convert(clear).toString(),
  };
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
