import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Whether uploads can go through `XMLHttpRequest` here: only on the web.
const bool xhrUploadAvailable = true;

/// Sends [request] through an `XMLHttpRequest`, whose `upload.onload` tells
/// when the browser has sent the whole body (`fetch` has no such event).
/// The body is the bytes the request already holds, handed over as they
/// are. [onHeaders] runs when the response headers arrive, [onUploadLoad]
/// when the body has gone. The response is whole when returned.
Future<http.StreamedResponse> sendByXhr(
  http.BaseRequest request, {
  required void Function() onHeaders,
  required void Function() onUploadLoad,
}) async {
  final Uint8List body = request is http.Request
      ? request.bodyBytes
      : await request.finalize().toBytes();
  final xhr = web.XMLHttpRequest()
    ..open(request.method, request.url.toString())
    ..responseType = 'arraybuffer';
  request.headers.forEach((name, value) => xhr.setRequestHeader(name, value));

  final done = Completer<http.StreamedResponse>();
  void fail(String why) {
    if (!done.isCompleted) {
      done.completeError(http.ClientException(why, request.url));
    }
  }

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
  xhr.onerror = ((web.Event _) => fail('XMLHttpRequest error.')).toJS;
  xhr.onabort = ((web.Event _) => fail('XMLHttpRequest aborted.')).toJS;
  if (request case http.Abortable(:final abortTrigger?)) {
    unawaited(abortTrigger.whenComplete(() => xhr.abort()));
  }

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
