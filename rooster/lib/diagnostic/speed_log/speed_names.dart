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

  /// Preparing an attached picture to be sent (size, thumbnail, blurhash),
  /// from the request to the result (`ImagePreparer`).
  static const imagePrepare = 'image_prepare';
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

  // image_prepare (queue_wait: waiting for one of the two preparation slots)
  /// Reading the size and orientation from the file header.
  static const header = 'header';

  /// The one engine decode, at thumbnail size or smaller.
  static const decode = 'decode';

  /// The thumbnail and blurhash, in the background (native) or by the
  /// browser's canvas (web).
  static const encode = 'encode';
}

/// Names of the numbers on steps.
abstract final class SpeedValue {
  static const attempt = 'attempt';
  static const status = 'status';
  static const retryAfterMs = 'retry_after_ms';

  /// A size in bytes (the file, a thumbnail).
  static const bytes = 'bytes';

  /// A picture's size in pixels.
  static const width = 'width';
  static const height = 'height';

  /// How many frames a decoded picture has (more than 1: animated).
  static const frames = 'frames';
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
