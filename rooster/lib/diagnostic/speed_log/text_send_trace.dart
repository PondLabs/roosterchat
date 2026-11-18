import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:matrix/encryption/utils/outbound_group_session.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/network/speed_http_client.dart'
    show speedErrorName;

/// The `text_send` span of one text message, in the app's [SpeedLog]: from
/// Send in the composer to the server's answer. See `docs/speed-log.md`.
///
/// The composer starts it ([forComposer]) and runs the room's send in it
/// ([send]); the room reports when it hands the text to the SDK ([sending])
/// and when the SDK returns ([sent]), each through [guard], so the
/// measurement can never stop the send. The steps:
///
/// - `send`: Send to the hand-over (the composer and the room's own work);
/// - `echo`: the hand-over to the local echo entering the timeline;
/// - `echo_painted`: the echo to the end of the next frame drawn,
///   unavailable when no frame can be observed;
/// - `queue_wait`: the echo to the room's earlier sends leaving the queue;
/// - `request`, then `retry` for each new attempt: one per `PUT /send` the
///   span made, from leaving to its response headers, with `attempt`,
///   `status` and a 429's `retry_after_ms`;
/// - `answer`: the last response headers to the SDK returning;
/// - `key_request`: one per key request the span made (`/keys/query`,
///   `/keys/claim`, `/sendToDevice`), like `request`;
/// - `outbound_session`, in an encrypted room: no duration, with
///   `session_created` (1 when no session was ready at the hand-over and
///   the send made one), `session_waited` (1 when no session was ready and
///   the message waited for the one a preparation still running made;
///   both 0 when one was ready or was loaded from this device) and
///   `key_requests` (how many).
///
/// Requests come from the log by the span's id, so the trace holds no URL;
/// the transaction id given to [sending] is only compared with the echo's
/// and dropped once the echo is seen or the span finishes.
class TextSendTrace {
  TextSendTrace._(this.span);

  /// Only for tests that replace what the room's calls do.
  TextSendTrace.forTest(this.span);

  final SpeedSpan span;

  static SpeedLog get _log => SpeedLog.instance;

  static final Object _key = Object();

  /// How long [nextFrameDrawn] waits for a frame before the step is
  /// unavailable (a hidden window draws none).
  static const frameTimeout = Duration(seconds: 2);

  /// Waits for the end of the next frame drawn; false when none can be
  /// observed. Only tests replace it.
  static Future<bool> Function() nextFrameDrawn = _schedulerFrame;

  /// The events entering [room]'s timeline, where the echo is looked for.
  /// Only tests replace it.
  static Stream<matrix.Event> Function(matrix.Room room) timelineEvents =
      _clientTimelineEvents;

  static Stream<matrix.Event> _clientTimelineEvents(matrix.Room room) =>
      room.client.onTimelineEvent.stream;

  /// The trace the current code runs in (see [send]).
  static TextSendTrace? get current => Zone.current[_key] as TextSendTrace?;

  /// Runs [measure], one of the room's calls into its trace, so that a
  /// failure in the speed log never stops the send: the error is dropped
  /// and the app's log gets a fixed line with its fixed name from
  /// [speedErrorName] (the message could hold the text being sent, and the
  /// runtime type reads `minified:xx` in a web release build).
  static void guard(void Function() measure) {
    try {
      measure();
    } catch (error) {
      Log.w('Speed log: a text send step was not timed '
          '(${speedErrorName(error)})');
    }
  }

  /// The moment Send is pressed, on the speed log's clock.
  static Duration now() => _log.now();

  /// The trace of a send that began at [sendPressed], or null when it is not
  /// a plain text message: the file send has its own span.
  static TextSendTrace? forComposer({
    required Duration sendPressed,
    required String message,
    required bool hasAttachments,
  }) {
    if (hasAttachments || message.trim().isEmpty) return null;
    return TextSendTrace._(
        _log.startSpan(SpeedOperation.textSend, startedAt: sendPressed));
  }

  /// Runs [body], the room's send, in [trace] (when there is one) and
  /// finishes the span when it completes. [body]'s error is passed on
  /// unchanged, as if it had not been traced. The future returned completes
  /// once the span is finished and never fails.
  static Future<void> send(
      TextSendTrace? trace, Future<Object?> Function() body) {
    if (trace == null) {
      body();
      return Future.value();
    }
    final finished = Completer<void>();
    final future =
        trace.span.run(() => runZoned(body, zoneValues: {_key: trace}));
    unawaited(future.then((_) => trace.finish().whenComplete(finished.complete),
        onError: (Object error, StackTrace stack) {
      trace._failed = true;
      trace.finish().whenComplete(finished.complete);
      Error.throwWithStackTrace(error, stack);
    }));
    return finished.future;
  }

  /// The room handed the text, kept until the span finishes to read its
  /// outbound session once more; the session's id is never kept.
  matrix.Room? _room;

  /// The room's outbound session at the hand-over, compared by identity.
  Object? _sessionAtHandOver;

  /// When the speed log started (its first request), on the wall clock a
  /// session's creation time is written on: a session made before it was
  /// loaded from this device's storage.
  DateTime? _logStartedWall;

  Duration? _handedOver;
  Duration? _echoAt;
  Duration? _paintedAt;
  Duration? _queueFreeAt;
  Duration? _answeredAt;
  Future<void>? _painting;
  StreamSubscription<matrix.Event>? _echo;
  bool _failed = false;
  bool _cancelled = false;

  /// Whether the preparation running at the hand-over readied the
  /// session: null when none was running, or until it ends.
  bool? _preparationReadied;

  /// [room] is handed the text with the transaction id [txid], while
  /// [preparation] (the room's preparation of its session, true once it
  /// readied it) runs, when one does. Only the first call counts.
  void sending(matrix.Room room, String txid, {Future<bool>? preparation}) {
    if (_handedOver != null || span.isFinished) return;
    preparation?.then((readied) => _preparationReadied = readied);
    final handedOver = _handedOver = span.elapsed;
    span.addStep(SpeedStep.send, Duration.zero, handedOver);
    if (room.encrypted) {
      _room = room;
      _logStartedWall = DateTime.now().subtract(_log.now());
      _sessionAtHandOver = _outboundSession(room);
    }

    // Our send waits behind the room's earlier ones (the SDK's queue).
    final ahead = [for (final waiting in room.sendingQueue) waiting.future];
    Future.wait(ahead).then((_) => _queueFreeAt = span.elapsed);

    _echo = timelineEvents(room).listen((event) {
      if (event.roomId != room.id || event.eventId != txid) return;
      _echo?.cancel();
      _echo = null;
      _echoAt = span.elapsed;
      _painting = nextFrameDrawn().then((drawn) {
        if (drawn) _paintedAt = span.elapsed;
      });
    });
  }

  /// The SDK returned the send: [ok] is false when it gave up.
  void sent({required bool ok}) {
    _answeredAt ??= span.elapsed;
    if (!ok) _failed = true;
  }

  /// The user cancelled the send before its request left.
  void cancelled() => _cancelled = true;

  /// Adds the steps and closes the span, once the echo's frame is drawn or
  /// [frameTimeout] has passed.
  Future<void> finish() async {
    await _painting;
    // Before anything else: a span closed from outside (too many open)
    // still stops looking for its echo.
    await _echo?.cancel();
    _echo = null;
    if (span.isFinished) return;
    _addSteps();
    span.finish(
        outcome: _cancelled
            ? SpeedOutcome.cancelled
            : _failed || _answeredAt == null
                ? SpeedOutcome.failed
                : SpeedOutcome.ok);
  }

  void _addSteps() {
    final handedOver = _handedOver;
    if (handedOver == null) return;
    final echoAt = _echoAt;
    span.addStep(SpeedStep.echo, handedOver,
        echoAt == null ? null : echoAt - handedOver);
    final paintedAt = _paintedAt;
    span.addStep(SpeedStep.echoPainted, echoAt ?? handedOver,
        echoAt == null || paintedAt == null ? null : paintedAt - echoAt);

    final queuedAt = echoAt ?? handedOver;
    final queueFreeAt = _queueFreeAt;
    span.addStep(
        SpeedStep.queueWait,
        queuedAt,
        queueFreeAt == null
            ? null
            : (queueFreeAt > queuedAt
                ? queueFreeAt - queuedAt
                : Duration.zero));

    RequestRecord? last;
    for (final request in _log.requests.toList()) {
      if (request.operationId != span.id || !isSendRequest(request)) continue;
      last = request;
      span.addStep(request.attempt == 1 ? SpeedStep.request : SpeedStep.retry,
          request.startedAt - span.startedAt, request.timeToHeaders,
          values: {
            SpeedValue.attempt: request.attempt,
            if (request.status != null) SpeedValue.status: request.status!,
            if (request.retryAfterMs != null)
              SpeedValue.retryAfterMs: request.retryAfterMs!,
          });
    }

    final answeredAt = _answeredAt;
    final headers = last?.timeToHeaders;
    if (last == null || headers == null || answeredAt == null) {
      span.unavailable(SpeedStep.answer);
    } else {
      final from = last.startedAt - span.startedAt + headers;
      span.addStep(SpeedStep.answer, from,
          answeredAt > from ? answeredAt - from : Duration.zero);
    }

    _addKeySteps(handedOver);
  }

  /// The key requests the span made, and in an encrypted room whether its
  /// session was made for this send.
  void _addKeySteps(Duration handedOver) {
    var keyRequests = 0;
    for (final request in _log.requests.toList()) {
      if (request.operationId != span.id || !isKeyRequest(request)) continue;
      keyRequests++;
      span.addStep(SpeedStep.keyRequest, request.startedAt - span.startedAt,
          request.timeToHeaders,
          values: {
            SpeedValue.attempt: request.attempt,
            if (request.status != null) SpeedValue.status: request.status!,
          });
    }

    final room = _room;
    final atHandOver = _sessionAtHandOver;
    _room = null;
    _sessionAtHandOver = null;
    if (room == null) return;
    // Like the room's calls ([guard]): reading the session never fails
    // the span.
    final bool created;
    try {
      final session = _outboundSession(room);
      created = session != null &&
          !identical(session, atHandOver) &&
          !session.creationTime.isBefore(_logStartedWall!);
    } catch (error) {
      Log.w('Speed log: the session of a text send was not read '
          '(${speedErrorName(error)})');
      return;
    }
    // Made by the preparation that was running, not by the send: the
    // message only waited for it.
    final waited = created && _preparationReadied == true;
    span.addStep(SpeedStep.outboundSession, handedOver, Duration.zero, values: {
      SpeedValue.sessionCreated: created && !waited ? 1 : 0,
      SpeedValue.sessionWaited: waited ? 1 : 0,
      SpeedValue.keyRequests: keyRequests,
    });
  }

  /// [room]'s outbound session as the SDK holds it in memory, if any.
  static OutboundGroupSession? _outboundSession(matrix.Room room) =>
      room.client.encryption?.keyManager.getOutboundGroupSession(room.id);

  /// Whether [request] is one of the key requests a send in an encrypted
  /// room can make: device keys, one-time keys, or room keys sent to
  /// devices.
  static bool isKeyRequest(RequestRecord request) =>
      (request.method == 'POST' &&
          (request.route.endsWith('/keys/query') ||
              request.route.endsWith('/keys/claim'))) ||
      (request.method == 'PUT' &&
          request.route.endsWith('/sendToDevice/{eventType}/{txnId}'));

  /// Whether [request] sends a room event (`PUT /send`).
  static bool isSendRequest(RequestRecord request) =>
      request.method == 'PUT' &&
      request.route.endsWith('/send/{eventType}/{txnId}');

  static Future<bool> _schedulerFrame() async {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      return false;
    }
    try {
      await binding.endOfFrame.timeout(frameTimeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}
