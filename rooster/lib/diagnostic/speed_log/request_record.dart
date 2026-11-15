import 'package:rooster/diagnostic/speed_log/host_class.dart';

/// One HTTP request as the speed log keeps it: never the URL, the host, a
/// header or a body, only what [routeTemplate] and [HostClass] leave.
///
/// Times are on the speed log's monotonic clock: [startedAt] counts from the
/// log's start, the durations from [startedAt].
class RequestRecord {
  const RequestRecord({
    required this.startedAt,
    required this.method,
    required this.route,
    required this.hostClass,
    required this.attempt,
    this.operationId,
    this.status,
    this.error,
    this.bytesUp = 0,
    this.bytesDown = 0,
    this.timeToHeaders,
    this.total,
    this.retryAfterMs,
    this.bodyHandedOver,
    this.handOverBoundary,
  });

  final Duration startedAt;

  /// `GET`, `PUT`...
  final String method;

  /// From `routeTemplate`, such as `/_matrix/media/v3/upload`.
  final String route;
  final HostClass hostClass;

  /// 1 for the first request of this method and route in its span, 2 for the
  /// next... Always 1 outside a span.
  final int attempt;

  /// The id of the span the request was made in, if any.
  final String? operationId;

  /// The HTTP status, null when no response came.
  final int? status;

  /// The type of the error when no response came or its body failed
  /// (`SocketException`, `TimeoutException`), or `cancelled` when the body
  /// was abandoned. Never the error's message, which can hold the URL.
  final String? error;

  final int bytesUp;
  final int bytesDown;

  final Duration? timeToHeaders;

  /// Until the response body ended; null if it never did.
  final Duration? total;

  /// From a 429's `retry_after_ms` or its `Retry-After` header.
  final int? retryAfterMs;

  /// When the last byte of the request body was handed over: consumed by the
  /// HTTP transport on native (not proof it left the machine yet), the
  /// `upload.onload` event of the `XMLHttpRequest` on the web. Null where it
  /// cannot be observed (a `fetch` on the web) or there was no body.
  final Duration? bodyHandedOver;

  /// Which of the boundaries above [bodyHandedOver] is: `transport` or
  /// `xhr_upload_onload`.
  final String? handOverBoundary;

  /// From the hand-over to the response headers: the server's time to
  /// receive the rest of the body and answer.
  Duration? get handedOverToAnswer =>
      bodyHandedOver == null || timeToHeaders == null
          ? null
          : timeToHeaders! - bodyHandedOver!;

  /// [bytesUp] over [handedOverToAnswer]: the rate the upload really went at
  /// when the transport buffers the body locally.
  double? get uploadBytesPerSecond {
    final window = handedOverToAnswer;
    if (window == null || bytesUp == 0 || window <= Duration.zero) return null;
    return bytesUp / (window.inMicroseconds / Duration.microsecondsPerSecond);
  }
}
