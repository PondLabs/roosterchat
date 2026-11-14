import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/xhr_upload_stub.dart'
    if (dart.library.js_interop) 'package:rooster/utils/network/xhr_upload_web.dart';

/// The HTTP client every request of an account goes through: it forwards
/// each request unchanged to [inner] and records it in the [SpeedLog] as a
/// [RequestRecord] (method, route template, host class, status, attempt,
/// bytes, time to headers, total, `retry_after_ms`, body hand-over).
///
/// - Native: the body is passed through as the stream it is, never
///   buffered, so a large upload is pulled only as fast as the socket takes
///   it. Its last byte being consumed is the hand-over time.
/// - Web: a media upload goes through `XMLHttpRequest` instead of [inner]
///   (`fetch` reports no upload progress), with the bytes the request
///   already holds and the hand-over time from `upload.onload`. Other
///   requests go through [inner], with the hand-over unavailable.
///
/// It changes no timeout and retries nothing: `matrix.Client` wraps it in
/// its own timeout client, as it did the plain `http.Client`.
class SpeedHttpClient extends http.BaseClient {
  SpeedHttpClient({http.Client? inner, HostClassifier? hosts, SpeedLog? log})
      : _inner = inner ?? http.Client(),
        _hosts = hosts ?? HostClassifier(),
        _log = log ?? SpeedLog.instance;

  final http.Client _inner;
  final HostClassifier _hosts;
  final SpeedLog _log;

  /// A 429's body is read for `retry_after_ms` up to this many bytes.
  static const _maxRetryBodyBytes = 4096;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final route = routeTemplate(request.url);
    final span = SpeedLog.currentSpan;
    final entry = _Entry(
      log: _log,
      method: request.method,
      route: route,
      hostClass: _hosts.classify(request.url),
      attempt: SpeedLog.nextAttempt(span, '${request.method} $route'),
      operationId: span?.id,
    );

    final http.StreamedResponse response;
    try {
      if (xhrUploadAvailable && isMediaUploadRoute(route)) {
        entry.bytesUp = request.contentLength ?? 0;
        response = await sendByXhr(
          request,
          onHeaders: entry.headersArrived,
          onUploadLoad: () => entry.handedOver('xhr_upload_onload'),
        );
      } else {
        response = await _inner.send(_ObservedRequest(request, entry));
      }
    } catch (error) {
      entry.finish(error: error.runtimeType.toString());
      rethrow;
    }

    entry
      ..headersArrived()
      ..status = response.statusCode;
    if (response.statusCode == 429) {
      entry.retryAfterMs = _retryAfterHeader(response.headers['retry-after']);
    }
    final body = <int>[];
    return _replaceStream(
      response,
      _observe(
        response.stream,
        onData: (chunk) {
          entry.bytesDown += chunk.length;
          if (response.statusCode == 429 && body.length < _maxRetryBodyBytes) {
            body.addAll(chunk);
          }
        },
        onEnd: (error) {
          if (response.statusCode == 429) {
            entry.retryAfterMs = _retryAfterBody(body) ?? entry.retryAfterMs;
          }
          entry.finish(error: error);
        },
      ),
    );
  }

  @override
  void close() => _inner.close();

  static int? _retryAfterHeader(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    return seconds == null ? null : seconds * 1000;
  }

  static int? _retryAfterBody(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final ms = json is Map ? json['retry_after_ms'] : null;
      return ms is int ? ms : null;
    } catch (_) {
      return null;
    }
  }
}

/// A request being recorded.
class _Entry {
  _Entry({
    required this.log,
    required this.method,
    required this.route,
    required this.hostClass,
    required this.attempt,
    required this.operationId,
  }) : startedAt = log.now();

  final SpeedLog log;
  final String method;
  final String route;
  final HostClass hostClass;
  final int attempt;
  final String? operationId;
  final Duration startedAt;

  int? status;
  int bytesUp = 0;
  int bytesDown = 0;
  int? retryAfterMs;
  Duration? timeToHeaders;
  Duration? bodyHandedOver;
  String? handOverBoundary;
  bool _finished = false;

  Duration get _elapsed => log.now() - startedAt;

  void headersArrived() => timeToHeaders ??= _elapsed;

  void handedOver(String boundary) {
    bodyHandedOver = _elapsed;
    handOverBoundary = boundary;
  }

  void finish({String? error}) {
    if (_finished) return;
    _finished = true;
    log.recordRequest(RequestRecord(
      startedAt: startedAt,
      method: method,
      route: route,
      hostClass: hostClass,
      attempt: attempt,
      operationId: operationId,
      status: status,
      error: error,
      bytesUp: bytesUp,
      bytesDown: bytesDown,
      timeToHeaders: timeToHeaders,
      total: error == null ? _elapsed : null,
      retryAfterMs: retryAfterMs,
      bodyHandedOver: bodyHandedOver,
      handOverBoundary: handOverBoundary,
    ));
  }
}

/// [original] as the inner client sees it: the same method, URL, headers
/// and settings, with a body stream that counts what the transport pulls.
class _ObservedRequest extends http.BaseRequest implements http.Abortable {
  _ObservedRequest(this._original, this._entry)
      : super(_original.method, _original.url) {
    headers.addAll(_original.headers);
    contentLength = _original.contentLength;
    followRedirects = _original.followRedirects;
    maxRedirects = _original.maxRedirects;
    persistentConnection = _original.persistentConnection;
  }

  final http.BaseRequest _original;
  final _Entry _entry;

  @override
  Future<void>? get abortTrigger {
    final original = _original;
    return original is http.Abortable ? original.abortTrigger : null;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    // On the web a fetch reads the whole body before sending it: the end of
    // this stream is not a hand-over there.
    final boundary = xhrUploadAvailable ? null : 'transport';
    return http.ByteStream(_observe(
      _original.finalize(),
      onData: (chunk) => _entry.bytesUp += chunk.length,
      onEnd: (error) {
        if (error == null && boundary != null && _entry.bytesUp > 0) {
          _entry.handedOver(boundary);
        }
      },
    ));
  }
}

/// [source], passed through event by event with pause and cancel forwarded,
/// so it is pulled no faster than its listener takes it. [onEnd] runs once:
/// with null when it ends, the error's type when it fails, `cancelled` when
/// the listener stops early.
Stream<List<int>> _observe(
  Stream<List<int>> source, {
  required void Function(List<int> chunk) onData,
  required void Function(String? error) onEnd,
}) {
  late StreamSubscription<List<int>> subscription;
  var ended = false;
  void end(String? error) {
    if (ended) return;
    ended = true;
    onEnd(error);
  }

  late final StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        (chunk) {
          onData(chunk);
          controller.add(chunk);
        },
        onError: (Object error, StackTrace stack) {
          end(error.runtimeType.toString());
          controller.addError(error, stack);
        },
        onDone: () {
          end(null);
          controller.close();
        },
      );
    },
    onPause: () => subscription.pause(),
    onResume: () => subscription.resume(),
    onCancel: () {
      end('cancelled');
      return subscription.cancel();
    },
  );
  return controller.stream;
}

http.StreamedResponse _replaceStream(
        http.StreamedResponse base, Stream<List<int>> stream) =>
    http.StreamedResponse(
      http.ByteStream(stream),
      base.statusCode,
      contentLength: base.contentLength,
      request: base.request,
      headers: base.headers,
      isRedirect: base.isRedirect,
      persistentConnection: base.persistentConnection,
      reasonPhrase: base.reasonPhrase,
    );
