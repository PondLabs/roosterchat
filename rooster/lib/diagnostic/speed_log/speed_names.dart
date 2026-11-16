/// Every name the speed log's spans use, in one place: the operations (span
/// names), their steps, the numbers on steps and the outcomes. They are
/// fixed identifiers (`[a-z][a-z0-9_]*`), never text from a message, a file
/// or a person; `docs/speed-log.md` says what each one measures.
///
/// This is the fixed list: `SpeedSpan` writes a name that is not in the
/// `all` set of its class as [invalidSpeedName]. A new name is a constant
/// here and an entry in that class's `all`; when two branches each add
/// names, keep both sets of entries.
library;

/// What any name off the lists below is written as.
const invalidSpeedName = 'invalid_name';

/// Span names.
abstract final class SpeedOperation {
  /// A text message, from Send in the composer to the server's answer.
  static const textSend = 'text_send';

  /// One round of the sync loop, from its request to the next one.
  static const sync = 'sync';

  /// Preparing an attached picture to be sent (size, thumbnail, blurhash),
  /// from the request to the result (`ImagePreparer`).
  static const imagePrepare = 'image_prepare';

  /// A voice join, from the join starting to the microphone published and
  /// the first remote audio (see `call_join_trace.dart`).
  static const voiceJoin = 'voice_join';

  /// A file sent from the composer, from it being attached to the server's
  /// answer for its event (see `file_send_trace.dart`).
  static const fileSend = 'file_send';

  /// Every span name. With [invalidSpeedName], at most
  /// `SpeedLog.maxOperations` (the finished spans keep that many).
  static const all = {textSend, sync, imagePrepare, voiceJoin, fileSend};
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
  /// From the sync request to its response: the server's wait, the long
  /// poll included (up to 30 s when nothing happens).
  static const serverWait = 'server_wait';

  /// Handling the response: rooms, events, the database.
  static const processing = 'processing';

  /// Device keys, encryption and the to-device queue after processing.
  static const cleanUp = 'clean_up';

  /// What the client did with the response: processing and clean-up
  /// together, without the server's wait.
  static const clientWork = 'client_work';

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

  // file_send (echo, request and retry as in text_send)
  /// From the file being attached to Send.
  static const attached = 'attached';

  /// From Send to the first frame drawn with the local picture.
  static const previewPainted = 'preview_painted';

  /// From Send to the files being handed to the Matrix SDK.
  static const prepared = 'prepared';

  /// One `POST /upload`: from leaving to its response headers.
  static const upload = 'upload';

  /// From Send to the SDK returning the event's id, or giving up.
  static const confirmed = 'confirmed';

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

  /// Inside [connect], the attempt that ran last: from its start to the
  /// signal WebSocket open.
  static const connectWebsocket = 'connect_websocket';

  /// From the WebSocket open to the SFU's answer to the join, and LiveKit
  /// making the two media connections (peer connections) with it: it tells
  /// the answer once they are made.
  static const connectJoinResponse = 'connect_join_response';

  /// From the join answered to the media connection (the primary peer
  /// connection) connected.
  static const connectMedia = 'connect_media';

  /// The microphone's capture options (the DSP's bounded wait included).
  static const microphoneOptions = 'microphone_options';

  /// Opening the microphone capture during the connection.
  static const microphoneOpen = 'microphone_open';

  /// The SFU's region, unavailable when it reports none.
  static const sfuRegion = 'sfu_region';

  /// The SFU reported a region: when it became known, no duration. Its name
  /// is never kept: it is the server's text, and a self-hosted SFU can put
  /// anything there (a host name). LiveKit's client code names no regions
  /// (`region_url_provider.dart` takes them from the server), so there is
  /// no checked list of Cloud regions to keep by name.
  static const sfuRegionOther = 'sfu_region_other';

  /// From connected to the microphone published; unavailable when it was
  /// not.
  static const microphonePublished = 'microphone_published';

  /// From connected to someone else first heard; unavailable when nobody
  /// spoke in time.
  static const firstRemoteAudio = 'first_remote_audio';

  /// Every step name.
  static const all = {
    send,
    echo,
    echoPainted,
    queueWait,
    request,
    retry,
    answer,
    serverWait,
    processing,
    cleanUp,
    clientWork,
    nextRequest,
    error,
    header,
    decode,
    encode,
    attached,
    previewPainted,
    prepared,
    upload,
    confirmed,
    leavePrevious,
    outputDevice,
    foci,
    openIdToken,
    sfuToken,
    sfuLivekitCloud,
    sfuSelfHosted,
    microphoneEarly,
    prepareConnection,
    membershipClearWait,
    membershipWrite,
    connect,
    connectWebsocket,
    connectJoinResponse,
    connectMedia,
    microphoneOptions,
    microphoneOpen,
    sfuRegion,
    sfuRegionOther,
    microphonePublished,
    firstRemoteAudio,
  };
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

  /// The size in bytes of a picture's thumbnail.
  static const thumbnailBytes = 'thumbnail_bytes';

  /// Every name of a number on a step.
  static const all = {
    attempt,
    status,
    retryAfterMs,
    bytes,
    width,
    height,
    frames,
    thumbnailBytes,
  };
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

  /// Dropped before its end: a picture's preparation for an attachment
  /// removed before Send, or a file or text send the user cancelled
  /// before its event's request left.
  static const cancelled = 'cancelled';

  /// Every outcome.
  static const all = {ok, failed, incomplete, abandoned, cancelled};
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

  /// A media upload ended because the connection took no byte of its body
  /// for `UploadLimits.stall` (30 s).
  static const uploadStalled = 'upload_stalled';

  /// A media upload ended because no answer came in time after its last
  /// byte (`UploadLimits.answerWait`: at least 150 s, and at least the
  /// body's time at 100 kB/s).
  static const uploadNoAnswer = 'upload_no_answer';

  static const all = {
    aborted,
    cancelled,
    timeout,
    socket,
    tls,
    http,
    client,
    other,
    uploadStalled,
    uploadNoAnswer,
  };
}
