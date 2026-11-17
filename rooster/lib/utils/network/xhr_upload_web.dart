import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:web/web.dart' as web;

/// Whether uploads can go through `XMLHttpRequest` here: only on the web.
const bool xhrUploadAvailable = true;

/// A request body the browser holds as a `Blob`: a file the person picked,
/// or that file encrypted piece by piece into one. `XMLHttpRequest` sends
/// the `Blob` as it is, so no byte of it is read into memory here.
abstract interface class BlobBody {
  /// The `Blob` to send, once it is ready (an encrypted file: once every
  /// piece is encrypted). Throws when the file cannot be read.
  Future<web.Blob> blob();

  /// The browser sent every byte of it (`upload.onload`).
  void sent();
}

/// A request's body made ready before its request starts: the [BlobBody]
/// of a file sent from the browser's `File`, and its `Blob`.
class XhrBody {
  XhrBody._(this.body, this.blob);

  final BlobBody body;
  final web.Blob blob;
}

/// [request]'s `Blob`, when its body is a [BlobBody], else null. Awaited
/// before the request starts: an encrypted file is encrypted here, and
/// its time does not count as the connection taking no byte.
Future<XhrBody?> prepareXhrBody(http.BaseRequest request) async {
  if (request case matrix.FileSendRequest(:final BlobBody body)) {
    return XhrBody._(body, await body.blob());
  }
  return null;
}

/// Sends [request] through an `XMLHttpRequest`, whose `upload.onprogress`
/// counts what the browser has sent of the body and `upload.onload` tells
/// when it has sent all of it (`fetch` has neither). The body is the bytes
/// the request already holds, handed over as they are. [onHeaders] runs
/// when the response headers arrive, [onUploadProgress] with the bytes
/// sent so far, [onUploadLoad] when the body has gone. [abort], like the
/// request's own `abortTrigger`, aborts it. The response is whole when
/// returned. A [prepared] body goes as its `Blob`, never read here.
Future<http.StreamedResponse> sendByXhr(
  http.BaseRequest request, {
  required void Function() onHeaders,
  required void Function(int sentBytes) onUploadProgress,
  required void Function() onUploadLoad,
  Future<void>? abort,
  XhrBody? prepared,
}) async {
  final JSAny body = prepared?.blob ??
      (request is http.Request
              ? request.bodyBytes
              : await request.finalize().toBytes())
          .toJS;
  final xhr = web.XMLHttpRequest()
    ..open(request.method, request.url.toString())
    ..responseType = 'arraybuffer';
  request.headers.forEach((name, value) => xhr.setRequestHeader(name, value));

  final done = Completer<http.StreamedResponse>();
  void fail(http.ClientException error) {
    if (!done.isCompleted) done.completeError(error);
  }

  // A listener on the upload set before send(), or the browser fires none.
  xhr.upload.onprogress = ((web.ProgressEvent event) =>
      onUploadProgress(event.loaded.toInt())).toJS;
  xhr.upload.onload = ((web.Event _) {
    prepared?.body.sent();
    onUploadLoad();
  }).toJS;
  xhr.onreadystatechange = ((web.Event _) {
    if (xhr.readyState == web.XMLHttpRequest.HEADERS_RECEIVED) onHeaders();
  }).toJS;
  xhr.onload = ((web.Event _) {
    final buffer = xhr.response as JSArrayBuffer?;
    final bytes = buffer?.toDart.asUint8List() ?? Uint8List(0);
    done.complete(http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      xhr.status,
      contentLength: bytes.length,
      request: request,
      headers: _headers(xhr.getAllResponseHeaders()),
      reasonPhrase: xhr.statusText,
    ));
  }).toJS;
  xhr.onerror = ((web.Event _) =>
      fail(http.ClientException('XMLHttpRequest error.', request.url))).toJS;
  // As the fetch client does when the request's abortTrigger completes.
  xhr.onabort =
      ((web.Event _) => fail(http.RequestAbortedException(request.url))).toJS;
  if (request case http.Abortable(:final abortTrigger?)) {
    unawaited(abortTrigger.whenComplete(() => xhr.abort()));
  }
  if (abort != null) unawaited(abort.whenComplete(() => xhr.abort()));

  xhr.send(body);
  return done.future;
}

Map<String, String> _headers(String raw) {
  final headers = <String, String>{};
  for (final line in raw.split('\r\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final name = line.substring(0, colon).trim().toLowerCase();
    final value = line.substring(colon + 1).trim();
    headers.update(name, (old) => '$old, $value', ifAbsent: () => value);
  }
  return headers;
}
