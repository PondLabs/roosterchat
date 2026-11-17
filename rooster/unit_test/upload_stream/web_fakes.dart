// What the Chrome tests of this folder share: the fake server's address
// (see `web_upload_server.dart`), files made in the page, a count of every
// read of a Blob's bytes, and the upload as the SDK sends it.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:web/web.dart' as web;

import '../upload_status/fakes.dart' show NoFrames;

@JS('eval')
external JSAny? _eval(JSString code);

JSAny? eval(String code) => _eval(code.toJS);

num jsNumber(String code) => (eval(code)! as JSNumber).toDartDouble;

const mib = 1024 * 1024;

/// The fake server, given by `web_upload_server.dart`; empty when the test
/// runs without it.
const serverUrl = String.fromEnvironment('WEB_UPLOAD_SERVER');

const skipWithoutServer = serverUrl == ''
    ? 'needs the fake server: run it through web_upload_server.dart'
    : false;

final server = Uri.parse(serverUrl);

/// A file of [bytes] made in the page, held by the browser's blob store as
/// a picked file is, and the SHA-256 (hex) of its bytes. Each byte follows
/// a pattern that differs between any two pieces.
Future<(web.File, String)> pageFile(int bytes,
    {String name = 'big.bin', int seed = 1}) async {
  final made = eval('''(async () => {
    const data = new Uint8Array($bytes);
    for (let i = 0; i < data.length; i++) {
      data[i] = (i * 31 + (i >> 10) * 7 + (i >> 20) * 13 + $seed) & 255;
    }
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', data));
    return [new File([data], '$name'),
        Array.from(hash, (b) => b.toString(16).padStart(2, '0')).join('')];
  })()''')! as JSPromise<JSArray<JSAny>>;
  final result = (await made.toDart).toDart;
  return (result[0] as web.File, (result[1] as JSString).toDart);
}

/// Counts, from now on, every read of a Blob's bytes into the page
/// (`arrayBuffer`, `text`, `stream`, `bytes`, `FileReader`), by size.
void countBlobReads() => eval('''(() => {
  window.__blobReads = [];
  if (window.__blobReadsPatched) return;
  window.__blobReadsPatched = true;
  for (const name of ['arrayBuffer', 'text', 'stream', 'bytes']) {
    const original = Blob.prototype[name];
    if (!original) continue;
    Blob.prototype[name] = function () {
      window.__blobReads.push(this.size);
      return original.apply(this, arguments);
    };
  }
  for (const name of ['readAsArrayBuffer', 'readAsBinaryString',
      'readAsDataURL', 'readAsText']) {
    const original = FileReader.prototype[name];
    FileReader.prototype[name] = function (blob) {
      window.__blobReads.push(blob.size);
      return original.apply(this, arguments);
    };
  }
})()''');

/// The sizes of the reads [countBlobReads] counted.
List<int> blobReads() => [
      for (final size
          in (eval('window.__blobReads')! as JSArray<JSNumber>).toDart)
        size.toDartInt
    ];

/// What the fake server received, upload by upload.
Future<List<Map<String, dynamic>>> serverUploads() async {
  final response = await http.get(server.resolve('/_test/uploads'));
  return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
}

Future<void> resetServer() => http.post(server.resolve('/_test/reset'));

/// Upload [index] decrypted by the SDK's decryptor on the server, with
/// [encryption]'s key, iv and hash: the SHA-256 (hex) of what came out, or
/// null when it did not decrypt.
Future<String?> serverDecrypt(
    int index, matrix.EncryptedFile encryption) async {
  final response = await http.post(server.resolve('/_test/decrypt'),
      body: jsonEncode({
        'index': index,
        'k': encryption.k,
        'iv': encryption.iv,
        'sha256': encryption.sha256,
      }));
  final answer = jsonDecode(response.body) as Map;
  if (answer['error'] != null) throw StateError(answer['error'] as String);
  return answer['sha256'] as String?;
}

/// Counts what an upload reports.
class Reports implements UploadListener {
  int sent = 0;
  final List<String> seen = [];

  @override
  void uploadStarted(int bodyBytes) => seen.add('started');

  @override
  void uploadSent(int sentBytes) {
    sent = sentBytes;
    if (seen.last != 'sent') seen.add('sent');
  }

  @override
  void uploadHandedOver() => seen.add('handed_over');

  @override
  void uploadAnswered(int status, {required bool matrixError}) =>
      seen.add('answered $status');

  @override
  void uploadFailed(String error) => seen.add('failed $error');
}

/// Uploads [read] as the SDK does (`Client.uploadContentStream`: a
/// `FileSendRequest` with the read's bytes as its body) through our HTTP
/// client, to the fake server, with [query] added to its URL. [cancel]
/// cancels it as the SDK's cancel of the message does.
Future<http.Response> uploadRead(matrix.FileSendRead read, int length,
    {Reports? reports,
    Map<String, String> query = const {},
    Future<void>? cancel}) async {
  final client = SpeedHttpClient(
    hosts: HostClassifier(homeserver: () => server),
    log: SpeedLog(frames: NoFrames()),
  );
  final url = server
      .resolve('/_matrix/media/v3/upload')
      .replace(queryParameters: {'filename': 'crypt', ...query});
  try {
    Future<http.StreamedResponse> send() =>
        client.send(matrix.FileSendRequest('POST', url, read.bytes, length)
          ..headers['content-type'] = 'application/octet-stream');
    final response = await runForUpload(
        reports ?? Reports(),
        () => cancel == null
            ? send()
            : matrix.runCancellableUpload(cancel, send));
    return await http.Response.fromStream(response);
  } finally {
    client.close();
  }
}
