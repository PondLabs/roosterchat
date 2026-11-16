import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Whether uploads can go through `XMLHttpRequest` here: only on the web.
const bool xhrUploadAvailable = true;

/// Sends [request] through an `XMLHttpRequest`, whose `upload.onprogress`
/// counts what the browser has sent of the body and `upload.onload` tells
/// when it has sent all of it (`fetch` has neither). The body is the bytes
/// the request already holds, handed over as they are. [onHeaders] runs
/// when the response headers arrive, [onUploadProgress] with the bytes
/// sent so far, [onUploadLoad] when the body has gone. [abort], like the
/// request's own `abortTrigger`, aborts it. The response is whole when
/// returned.
Future<http.StreamedResponse> sendByXhr(
  http.BaseRequest request, {
  required void Function() onHeaders,
  required void Function(int sentBytes) onUploadProgress,
  required void Function() onUploadLoad,
  Future<void>? abort,
}) async {
  final Uint8List body = request is http.Request
      ? request.bodyBytes
      : await request.finalize().toBytes();
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
  xhr.upload.onload = ((web.Event _) => onUploadLoad()).toJS;
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

  xhr.send(body.toJS);
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
