import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException, SocketException, TlsException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show currentUploadCancel;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:rooster/utils/network/xhr_upload_stub.dart'
    if (dart.library.js_interop) 'package:rooster/utils/network/xhr_upload_web.dart';

/// The HTTP client every request of an account goes through: it forwards
/// each request unchanged to [inner] and records it in the [SpeedLog] as a
/// [RequestRecord] (method, route template, host class, status, attempt,
/// bytes, time to headers, total, `retry_after_ms`, body hand-over).
///
/// - Native: the body is passed through as a stream of pieces of at most
///   [bodyPiece] bytes, never buffered, so a large upload is pulled only as
///   fast as the socket takes it and the count is what the transport has
///   consumed. Its last byte being consumed is the hand-over time.
/// - Web: a media upload goes through `XMLHttpRequest` instead of [inner]
///   (`fetch` reports no upload progress), with the bytes the request
///   already holds, or the `Blob` of a file sent from the browser's `File`
///   (`BlobBody`), the count from `upload.onprogress` and the hand-over
///   time from `upload.onload`. Other requests go through [inner], with the
///   hand-over unavailable.
///
/// A media upload runs under [UploadLimits] (no total limit; 30 s without
/// the connection taking a byte; after the last byte, the answer's wait)
/// and reports to the [UploadListener] of its zone ([runForUpload]), the
/// pending message it belongs to. When that message's send is cancelled
/// (`currentUploadCancel`, the SDK's zone value), the request is aborted,
/// on the web the `XMLHttpRequest`. It retries nothing: `matrix.Client`
/// wraps it in its own timeout client, which limits only the time between
/// pieces of the response body.
class SpeedHttpClient extends http.BaseClient {
  SpeedHttpClient({http.Client? inner, HostClassifier? hosts, SpeedLog? log})
      : _inner = inner ?? http.Client(),
        _hosts = hosts ?? HostClassifier(),
        _log = log ?? SpeedLog.instance;

  final http.Client _inner;
  final HostClassifier _hosts;
  final SpeedLog _log;

  /// A 429's body is read for `retry_after_ms`, a failed upload's for an
  /// `errcode`, up to this many bytes.
  static const _maxErrorBodyBytes = 4096;

  /// The largest piece a request body is handed to the transport in.
  static const bodyPiece = 64 * 1024;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Chosen by the API's words whatever the host's class, as before the
    // route of other hosts was reduced to placeholders.
    final isUpload = isMediaUploadRoute(routeTemplate(request.url));
    // A file sent from the browser's `File` goes as its `Blob`, made ready
    // first: encrypting it is not the connection taking no byte.
    final prepared =
        xhrUploadAvailable && isUpload ? await prepareXhrBody(request) : null;
    final hostClass = _hosts.classify(request.url);
    final span = SpeedLog.currentSpan;
    final entry = _Entry(
      log: _log,
      method: request.method,
      route: routeTemplate(request.url, hostClass),
      hostClass: hostClass,
      // The same request sent again counts as a new attempt; a different
      // one of the same route does not. Hashed by the span, never kept. A
      // body of unknown length cannot be told from another: attempt 1.
      attempt: request.contentLength == null
          ? 1
          : SpeedLog.nextAttempt(span,
              '${request.method} ${request.url} ${request.contentLength}'),
      operationId: span?.id,
    );

    final upload = isUpload
        ? _UploadWatch(request.contentLength, currentUploadListener,
            cancel: currentUploadCancel(), url: request.url)
        : null;
    final http.StreamedResponse response;
    try {
      if (xhrUploadAvailable && upload != null) {
        entry.bytesUp = request.contentLength ?? 0;
        response = await upload.limit(sendByXhr(
          request,
          onHeaders: entry.headersArrived,
          onUploadProgress: upload.sent,
          onUploadLoad: () {
            entry.handedOver('xhr_upload_onload');
            upload.handedOver();
          },
          abort: upload.aborted,
          prepared: prepared,
        ));
      } else {
        final sending =
            _inner.send(_ObservedRequest(request, entry, upload: upload));
        response = upload == null ? await sending : await upload.limit(sending);
      }
    } catch (error) {
      final name = speedErrorName(error);
      entry.finish(error: name);
      upload?.failed(name);
      rethrow;
    }

    upload?.answering();
    entry
      ..headersArrived()
      ..status = response.statusCode;
    if (response.statusCode == 429) {
      entry.retryAfterMs = _retryAfterHeader(response.headers['retry-after']);
    }
    final keepBody = response.statusCode == 429 ||
        (upload != null && response.statusCode >= 300);
    final body = <int>[];
    return _replaceStream(
      response,
      _observe(
        response.stream,
        onData: (chunk) {
          entry.bytesDown += chunk.length;
          if (keepBody && body.length < _maxErrorBodyBytes) {
            body.addAll(chunk);
          }
        },
        onEnd: (error) {
          if (response.statusCode == 429) {
            entry.retryAfterMs = _retryAfterBody(body) ?? entry.retryAfterMs;
          }
          entry.finish(error: error);
          if (error != null) {
            upload?.failed(error);
          } else {
            upload?.answered(response.statusCode,
                matrixError: isMatrixErrorBody(body));
          }
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

/// The fixed name of [error] in the speed log (see [SpeedError]).
String speedErrorName(Object error) => switch (error) {
      UploadTimeoutException(:final limit) => limit,
      http.RequestAbortedException() => SpeedError.aborted,
      TimeoutException() => SpeedError.timeout,
      SocketException() => SpeedError.socket,
      TlsException() => SpeedError.tls,
      HttpException() => SpeedError.http,
      http.ClientException() => SpeedError.client,
      _ => SpeedError.other,
    };

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

/// One media upload: its time limits and what it tells its listener. Every
/// report after its end is ignored, so the listener hears of each request
/// once: answered, or failed with the limit or error that ended it.
class _UploadWatch {
  _UploadWatch(this._bodyBytes, this._listener,
      {Future<void>? cancel, required Uri url}) {
    _listener?.uploadStarted(_bodyBytes ?? 0);
    // Connecting counts as not taking a byte.
    _arm(UploadLimits.stall, SpeedError.uploadStalled);
    // The send it belongs to was cancelled: the request is aborted, and
    // ends as aborted even if an answer still comes.
    cancel?.then((_) {
      if (_ended) return;
      failed(SpeedError.aborted);
      _stop(http.RequestAbortedException(url));
    });
  }

  final int? _bodyBytes;
  final UploadListener? _listener;
  final _abort = Completer<void>();
  final _limited = Completer<Never>();
  Timer? _timer;
  int _sent = 0;
  bool _handedOver = false;
  bool _ended = false;

  /// Completes when a limit ends the upload, or its send is cancelled: the
  /// transport's request is aborted then.
  Future<void> get aborted => _abort.future;

  /// Aborts the transport's request, and the upload fails with [error].
  void _stop(Object error) {
    if (!_abort.isCompleted) _abort.complete();
    if (!_limited.isCompleted) _limited.completeError(error);
  }

  /// [sending], or the limit's [UploadTimeoutException] if one ends the
  /// upload first. A response that comes after that is let go.
  Future<http.StreamedResponse> limit(Future<http.StreamedResponse> sending) {
    sending.then(
      (response) {
        if (_abort.isCompleted) response.stream.listen(null).cancel();
      },
      onError: (Object _) {},
    );
    return Future.any([sending, _limited.future]);
  }

  /// The connection has taken [bytes] of the body.
  void sent(int bytes) {
    if (_ended || _handedOver) return;
    _sent = bytes;
    _listener?.uploadSent(bytes);
    _arm(UploadLimits.stall, SpeedError.uploadStalled);
  }

  /// The last byte was handed over: the answer is waited for.
  void handedOver() {
    if (_ended || _handedOver) return;
    _handedOver = true;
    _listener?.uploadHandedOver();
    _arm(UploadLimits.answerWait(math.max(_bodyBytes ?? 0, _sent)),
        SpeedError.uploadNoAnswer);
  }

  /// The response headers arrived: no limit on reading the answer (the
  /// SDK's timeout client has its own).
  void answering() {
    _timer?.cancel();
    _timer = null;
  }

  void answered(int status, {required bool matrixError}) {
    if (_end()) _listener?.uploadAnswered(status, matrixError: matrixError);
  }

  void failed(String error) {
    if (_end()) _listener?.uploadFailed(error);
  }

  bool _end() {
    _timer?.cancel();
    if (_ended) return false;
    return _ended = true;
  }

  void _arm(Duration limit, String name) {
    _timer?.cancel();
    _timer = Timer(limit, () {
      failed(name);
      _stop(UploadTimeoutException(name, limit));
    });
  }
}

/// [original] as the inner client sees it: the same method, URL, headers
/// and settings, with a body stream in pieces that counts what the
/// transport pulls. A media upload's [upload] hears of the count and can
/// abort the request.
class _ObservedRequest extends http.BaseRequest implements http.Abortable {
  _ObservedRequest(this._original, this._entry, {_UploadWatch? upload})
      : _upload = upload,
        super(_original.method, _original.url) {
    headers.addAll(_original.headers);
    contentLength = _original.contentLength;
    followRedirects = _original.followRedirects;
    maxRedirects = _original.maxRedirects;
    persistentConnection = _original.persistentConnection;
  }

  final http.BaseRequest _original;
  final _Entry _entry;
  final _UploadWatch? _upload;

  @override
  Future<void>? get abortTrigger {
    final original = _original;
    final trigger = original is http.Abortable ? original.abortTrigger : null;
    final limit = _upload?.aborted;
    if (limit == null) return trigger;
    return trigger == null ? limit : Future.any([trigger, limit]);
  }

  @override
  http.ByteStream finalize() {
    final body = _original.finalize();
    // Some requests write their headers and length while finalizing: a
    // MultipartRequest sets its content-type and boundary there.
    headers.addAll(_original.headers);
    contentLength = _original.contentLength;
    super.finalize();
    // On the web a fetch reads the whole body before sending it: the end of
    // this stream is not a hand-over there.
    final boundary = xhrUploadAvailable ? null : 'transport';
    return http.ByteStream(_observe(
      _inPieces(body),
      onData: (chunk) {
        _entry.bytesUp += chunk.length;
        _upload?.sent(_entry.bytesUp);
      },
      onEnd: (error) {
        if (error == null && boundary != null) {
          if (_entry.bytesUp > 0) _entry.handedOver(boundary);
          _upload?.handedOver();
        }
      },
    ));
  }
}

/// [body] in pieces of at most [SpeedHttpClient.bodyPiece] bytes, each made
/// only when the listener asks for it: a body held as one large list (a
/// `Request`'s bytes) is taken as fast as the transport sends it, not in
/// one go.
Stream<List<int>> _inPieces(Stream<List<int>> body) async* {
  const piece = SpeedHttpClient.bodyPiece;
  await for (final chunk in body) {
    if (chunk.length <= piece) {
      yield chunk;
      continue;
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    for (var start = 0; start < bytes.length; start += piece) {
      yield Uint8List.sublistView(
          bytes, start, math.min(start + piece, bytes.length));
    }
  }
}

/// [source], passed through event by event with pause and cancel forwarded,
/// so it is pulled no faster than its listener takes it. [onEnd] runs once:
/// with null when it ends, the error's name when it fails, `cancelled` when
/// the listener stops early.
Stream<List<int>> _observe(
  Stream<List<int>> source, {
  required void Function(List<int> chunk) onData,
  required void Function(String? error) onEnd,
}) {
  late StreamSubscription<List<int>> subscription;
  var ended = false;
  var sourceDone = false;
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
          end(speedErrorName(error));
          controller.addError(error, stack);
        },
        onDone: () {
          sourceDone = true;
          end(null);
          controller.close();
        },
      );
    },
    onPause: () => subscription.pause(),
    onResume: () => subscription.resume(),
    onCancel: () {
      end(SpeedError.cancelled);
      // A source that ended has nothing to cancel, and the done event would
      // otherwise wait for that cancel's future.
      return sourceDone ? null : subscription.cancel();
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
