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

  /// A voice join, from the join starting to the microphone published and
  /// the first remote audio (see `call_join_trace.dart`).
  static const voiceJoin = 'voice_join';
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

  // voice_join (timed steps may overlap: the join runs some side by side)
  /// The call being left hanging up.
  static const leavePrevious = 'leave_previous';

  /// The picked speakers handed to WebRTC.
  static const outputDevice = 'output_device';

  /// Finding the call's token service (the well-known).
  static const foci = 'foci';

  /// The OpenID token from the homeserver.
  static const openIdToken = 'openid_token';

  /// `POST /sfu/get` to the call token service.
  static const sfuToken = 'sfu_token';

  /// The SFU is LiveKit Cloud: when that became known, no duration.
  static const sfuLivekitCloud = 'sfu_livekit_cloud';

  /// The SFU is not LiveKit Cloud: when that became known, no duration.
  static const sfuSelfHosted = 'sfu_self_hosted';

  /// A phone's browser opening the microphone before the membership.
  static const microphoneEarly = 'microphone_early';

  /// LiveKit's DNS, TLS and region warm-up, when awaited or finished.
  static const prepareConnection = 'prepare_connection';

  /// Waiting for the previous call's clear of our membership.
  static const membershipClearWait = 'membership_clear_wait';

  /// Writing our call membership.
  static const membershipWrite = 'membership_write';

  /// The LiveKit connection.
  static const connect = 'connect';

  /// The microphone's capture options (the DSP's bounded wait included).
  static const microphoneOptions = 'microphone_options';

  /// Opening the microphone capture during the connection.
  static const microphoneOpen = 'microphone_open';

  /// The SFU's region, unavailable when it reports none; a known region is
  /// [sfuRegionPrefix] and its name, with no duration.
  static const sfuRegion = 'sfu_region';
  static const sfuRegionPrefix = 'sfu_region_';

  /// From connected to the microphone published; unavailable when it was
  /// not.
  static const microphonePublished = 'microphone_published';

  /// From connected to someone else first heard; unavailable when nobody
  /// spoke in time.
  static const firstRemoteAudio = 'first_remote_audio';
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
