/// Every name the speed log's spans use, in one place: the operations (span
/// names), their steps, the numbers on steps and the outcomes. They are
/// fixed identifiers (`[a-z][a-z0-9_]*`), never text from a message, a file
/// or a person; `docs/speed-log.md` says what each one measures.
library;

/// Span names.
abstract final class SpeedOperation {
  /// A text message, from Send in the composer to the server's answer.
  static const textSend = 'text_send';

  /// One round of the sync loop, from its request to the next one.
  static const sync = 'sync';
}

/// Step names.
abstract final class SpeedStep {
  // text_send
  /// From Send to the room handing the text to the Matrix SDK.
  static const send = 'send';

  /// From the hand-over to the local echo entering the timeline.
  static const echo = 'echo';

  /// From the echo entering the timeline to the end of the next frame drawn.
  static const echoPainted = 'echo_painted';

  /// From the echo to the room's earlier sends leaving the queue.
  static const queueWait = 'queue_wait';

  /// The first `PUT /send`: from leaving to its response headers.
  static const request = 'request';

  /// The same `PUT /send` sent again (after a 429 or an error).
  static const retry = 'retry';

  /// From the last response headers to the SDK returning the send.
  static const answer = 'answer';

  // sync
  /// From the sync request to its response (the long poll included).
  static const response = 'response';

  /// Handling the response: rooms, events, the database.
  static const processing = 'processing';

  /// Device keys, encryption and the to-device queue after processing.
  static const cleanUp = 'clean_up';

  /// From the end of the round to the next sync request leaving.
  static const nextRequest = 'next_request';

  /// The round failed: from the last step to the error being reported.
  static const error = 'error';
}

/// Names of the numbers on steps.
abstract final class SpeedValue {
  static const attempt = 'attempt';
  static const status = 'status';
  static const retryAfterMs = 'retry_after_ms';
}

/// Span outcomes.
abstract final class SpeedOutcome {
  static const ok = 'ok';
  static const failed = 'failed';

  /// A sync round that ended without cleaning up (dropped by the SDK).
  static const incomplete = 'incomplete';

  /// Closed without its end being seen (too many open spans, the client
  /// disposed).
  static const abandoned = 'abandoned';
}

/// What a request's `error=` says: the kind of failure, by a fixed name.
/// Never the error's message (it can hold the URL) nor its runtime type
/// (shortened to `minified:xx` in a web release build).
abstract final class SpeedError {
  /// Its `abortTrigger` completed (`RequestAbortedException`).
  static const aborted = 'aborted';

  /// The response body was abandoned before its end.
  static const cancelled = 'cancelled';

  /// A `TimeoutException`.
  static const timeout = 'timeout';

  /// A `SocketException`: no connection, or it broke.
  static const socket = 'socket';

  /// A `TlsException`, such as a failed handshake.
  static const tls = 'tls';

  /// A `dart:io` `HttpException`: the response could not be read.
  static const http = 'http';

  /// Any other `ClientException` of the `http` package (the web's network
  /// errors among them).
  static const client = 'client';

  /// Anything else.
  static const other = 'other';

  static const all = {
    aborted,
    cancelled,
    timeout,
    socket,
    tls,
    http,
    client,
    other,
  };
}
