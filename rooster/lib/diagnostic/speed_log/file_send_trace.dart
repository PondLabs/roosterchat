import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

/// The `file_send` span of one file sent from the composer, in the app's
/// [SpeedLog]: from the file being attached to the server's answer for its
/// event. See `docs/speed-log.md`.
///
/// The composer starts it at Send ([start]); the file's pending send
/// (`AttachmentSend`) reports the rest. The steps, each from Send unless
/// said otherwise:
///
/// - `attached`: from the file being attached to Send, with its `bytes`
///   when known;
/// - `preview_painted`: to the end of the first frame drawn after the local
///   picture was decoded (pictures and video posters only);
/// - `prepared`: to the files being handed to the Matrix SDK, with the
///   file's `bytes`, its `thumbnail_bytes`, `width` and `height`;
/// - `echo`: from the hand-over to the room's pending event entering the
///   timeline;
/// - `upload`: one per `POST /upload` (the file, its thumbnail, a new
///   attempt), from leaving to its response headers, with `bytes` sent,
///   `attempt` and `status`;
/// - `request`, then `retry`: the event's `PUT /send`, as in `text_send`;
/// - `confirmed`: to the SDK returning the event's id (or giving up).
///
/// Only fixed names and numbers: no file name, type, room, event or
/// transaction id. Requests come from the log by the span's id.
class FileSendTrace {
  FileSendTrace._(this.span, this._sendAt);

  final SpeedSpan span;

  /// Send, from the span's start.
  final Duration _sendAt;

  static SpeedLog get _log => SpeedLog.instance;

  /// Now, on the speed log's clock.
  static Duration now() => _log.now();

  /// The trace of a file attached at [attachedAt] (null when unknown) and
  /// sent at [sendPressed], both on the speed log's clock.
  static FileSendTrace start({
    required Duration sendPressed,
    Duration? attachedAt,
    int? bytes,
  }) {
    final from =
        attachedAt != null && attachedAt <= sendPressed ? attachedAt : null;
    final span =
        _log.startSpan(SpeedOperation.fileSend, startedAt: from ?? sendPressed);
    final sendAt = sendPressed - span.startedAt;
    if (from != null) {
      span.addStep(SpeedStep.attached, Duration.zero, sendAt,
          values: {if (bytes != null) SpeedValue.bytes: bytes});
    }
    return FileSendTrace._(span, sendAt);
  }

  Duration? _paintedAt;
  Duration? _handedOverAt;
  Duration? _echoAt;
  bool _expectsPreview = false;

  /// The local picture is shown (or will be): `preview_painted` is
  /// expected, and unavailable when no frame is seen.
  void showsPreview() => _expectsPreview = true;

  void previewPainted() {
    if (span.isFinished) return;
    _expectsPreview = true;
    _paintedAt ??= span.elapsed;
  }

  /// Handed to the SDK, with the sizes of what is uploaded.
  void handedOver(
      {required int bytes, int? thumbnailBytes, int? width, int? height}) {
    if (span.isFinished || _handedOverAt != null) return;
    final at = _handedOverAt = span.elapsed;
    span.addStep(SpeedStep.prepared, _sendAt, at - _sendAt, values: {
      SpeedValue.bytes: bytes,
      if (thumbnailBytes != null) SpeedValue.thumbnailBytes: thumbnailBytes,
      if (width != null) SpeedValue.width: width,
      if (height != null) SpeedValue.height: height,
    });
  }

  void echoed() {
    if (span.isFinished) return;
    _echoAt ??= span.elapsed;
  }

  /// Runs [body], the SDK's send, so its requests are linked to the span.
  R run<R>(R Function() body) => span.run(body);

  /// Adds the steps and closes the span: [ok] is false when the file did
  /// not reach the room, and [cancelled] when the user cancelled it.
  void finish({required bool ok, bool cancelled = false}) {
    if (span.isFinished) return;
    final end = span.elapsed;

    final painted = _paintedAt;
    if (painted != null) {
      span.addStep(SpeedStep.previewPainted, _sendAt,
          painted > _sendAt ? painted - _sendAt : Duration.zero);
    } else if (_expectsPreview) {
      span.addStep(SpeedStep.previewPainted, _sendAt, null);
    }

    final handedOver = _handedOverAt;
    if (handedOver != null) {
      final echo = _echoAt;
      span.addStep(
          SpeedStep.echo, handedOver, echo == null ? null : echo - handedOver);
    }

    for (final request in _log.requests.toList()) {
      if (request.operationId != span.id) continue;
      final values = {
        SpeedValue.attempt: request.attempt,
        if (request.status != null) SpeedValue.status: request.status!,
      };
      if (isUploadRequest(request)) {
        span.addStep(SpeedStep.upload, request.startedAt - span.startedAt,
            request.timeToHeaders,
            values: {SpeedValue.bytes: request.bytesUp, ...values});
      } else if (TextSendTrace.isSendRequest(request)) {
        span.addStep(request.attempt == 1 ? SpeedStep.request : SpeedStep.retry,
            request.startedAt - span.startedAt, request.timeToHeaders,
            values: {
              ...values,
              if (request.retryAfterMs != null)
                SpeedValue.retryAfterMs: request.retryAfterMs!,
            });
      }
    }

    span.addStep(SpeedStep.confirmed, _sendAt, end - _sendAt);
    span.finish(
        outcome: cancelled
            ? SpeedOutcome.cancelled
            : ok
                ? SpeedOutcome.ok
                : SpeedOutcome.failed);
  }

  /// Whether [request] uploads media (`POST /upload`).
  static bool isUploadRequest(RequestRecord request) =>
      request.method == 'POST' && request.route.endsWith('/upload');
}
