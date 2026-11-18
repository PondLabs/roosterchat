import 'dart:async';

import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// The `voice_join` span of one voice join, in a [SpeedLog]: from the join
/// starting to the microphone published and the first remote audio.
///
/// Its steps, each with its start and duration (timed steps may overlap,
/// because the join runs some of them side by side):
///
/// - `leave_previous`: the call being left hanging up, beside the rest;
/// - `output_device`: the picked speakers handed to WebRTC;
/// - `foci`: finding the call's token service (the well-known);
/// - `openid_token`: the OpenID token from the homeserver;
/// - `sfu_token`: `POST /sfu/get` to the token service;
/// - `sfu_livekit_cloud` or `sfu_self_hosted`: the SFU's host class, at the
///   moment it is known (no duration of its own);
/// - `microphone_early`: a phone's browser opening the microphone first;
/// - `prepare_connection`: LiveKit's DNS, TLS and region warm-up, when it is
///   awaited or finishes;
/// - `membership_clear_wait`: waiting for the previous call's clear;
/// - `membership_write`, `connect`;
/// - `connect_websocket`, `connect_join_response`, `connect_media`: inside
///   `connect`, the attempt that ran last ([connectSteps]);
/// - `microphone_options`, `microphone_open`: the capture prepared during
///   the connection;
/// - `sfu_region_other` when the SFU reports a region (its name is not
///   kept), or `sfu_region` unavailable when it reports none;
/// - `microphone_published`: from connected to the microphone published, or
///   unavailable when it was not (denied, no device) or not within
///   [remoteAudioWindow];
/// - `first_remote_audio`: from connected to someone else first heard,
///   unavailable when nobody spoke within [remoteAudioWindow].
///
/// The span holds no URL, id, name or token: requests made inside [run] are
/// linked to it by its id, with their route template and host class only.
class CallJoinTrace {
  CallJoinTrace(SpeedLog log,
      {this.remoteAudioWindow = const Duration(seconds: 30)})
      : span = log.startSpan(spanName);

  static const spanName = SpeedOperation.voiceJoin;

  final SpeedSpan span;

  /// How long after connecting someone has to speak for
  /// `first_remote_audio` to be timed, and the microphone has to be
  /// published for `microphone_published` (a permission prompt nobody
  /// answers must not keep the span open).
  final Duration remoteAudioWindow;

  bool _microphoneSettled = false;
  bool _remoteSettled = false;
  StreamSubscription<void>? _remote;
  Timer? _remoteTimer;
  Timer? _microphoneTimer;

  /// Runs [body] in the span: its requests are recorded with the span's id.
  Future<T> run<T>(Future<T> Function() body) => span.run(body);

  /// A step that lasts as long as [body].
  Future<T> time<T>(String step, Future<T> Function() body) =>
      span.time(step, body);

  /// The moments of one LiveKit connection attempt, for [connectSteps].
  ConnectAttempt connectAttempt() => ConnectAttempt._(span);

  /// The connect in three steps, from [attempt]: the WebSocket, the join's
  /// answer and the media connection. A step whose moments did not both
  /// come (a room that reports none, a connection that failed first) is
  /// unavailable.
  void connectSteps(ConnectAttempt attempt) {
    void step(String name, Duration? from, Duration? to) {
      if (from == null || to == null || to < from) {
        span.unavailable(name);
      } else {
        span.addStep(name, from, to - from);
      }
    }

    step(SpeedStep.connectWebsocket, attempt._started, attempt._websocket);
    step(SpeedStep.connectJoinResponse, attempt._websocket, attempt._joined);
    step(SpeedStep.connectMedia, attempt._joined, attempt._media);
  }

  /// Records the SFU's host class: LiveKit Cloud or anything else.
  void sfuHost({required bool livekitCloud}) => _instant(
      livekitCloud ? SpeedStep.sfuLivekitCloud : SpeedStep.sfuSelfHosted);

  /// The connection finished, in the SFU [region] (null when it reports
  /// none). Call [microphone] and [listenForRemoteAudio] right after: their
  /// steps count from here.
  void connected(String? region) {
    if (region == null || region.isEmpty) {
      span.unavailable(SpeedStep.sfuRegion);
    } else {
      // Never the region's own text (see SpeedStep.sfuRegionOther).
      _instant(SpeedStep.sfuRegionOther);
    }
  }

  /// The microphone is being published: [published] completes with whether
  /// it was. Not published is `microphone_published` unavailable.
  void microphone(Future<bool> published) {
    // A step is only added when its future completes: one that never does
    // adds nothing, and the step is written unavailable instead.
    final done = Completer<void>();
    span.time(SpeedStep.microphonePublished, () => done.future);
    void settle(bool ok) {
      if (_microphoneSettled) return;
      _microphoneSettled = true;
      _microphoneTimer?.cancel();
      if (ok) {
        done.complete();
      } else {
        span.unavailable(SpeedStep.microphonePublished);
      }
      _finishWhenSettled();
    }

    published.then((ok) => ok, onError: (Object _) => false).then(settle);
    _microphoneTimer = Timer(remoteAudioWindow, () => settle(false));
  }

  /// Waits for someone else to be heard ([speaking]), for
  /// [remoteAudioWindow] at most.
  void listenForRemoteAudio(Stream<void> speaking) {
    final heard = Completer<void>();
    span.time(SpeedStep.firstRemoteAudio, () => heard.future);
    _remote = speaking.listen((_) {
      if (_remoteSettled) return;
      heard.complete();
      _settleRemote();
    });
    _remoteTimer = Timer(remoteAudioWindow, () {
      if (_remoteSettled) return;
      span.unavailable(SpeedStep.firstRemoteAudio);
      _settleRemote();
    });
  }

  /// The join failed: the span ends with what it had.
  void failed() {
    _remote?.cancel();
    _remoteTimer?.cancel();
    _microphoneTimer?.cancel();
    span.finish(outcome: SpeedOutcome.failed);
  }

  void _settleRemote() {
    _remoteSettled = true;
    _remote?.cancel();
    _remoteTimer?.cancel();
    // After the step above is added, which happens a microtask later.
    scheduleMicrotask(_finishWhenSettled);
  }

  void _finishWhenSettled() {
    if (_microphoneSettled && _remoteSettled) {
      // The steps of futures completed just now are added a microtask later.
      Future(span.finish);
    }
  }

  /// A step with no duration of its own: when something became known.
  void _instant(String step) => span.time(step, () async {});
}

/// When each part of one LiveKit connection attempt was done, on the span's
/// clock ([CallJoinTrace.connectAttempt]): told by LiveKit as it goes.
class ConnectAttempt {
  ConnectAttempt._(this._span) : _started = _span.elapsed;

  final SpeedSpan _span;
  Duration _started;
  Duration? _websocket;
  Duration? _joined;
  Duration? _media;

  /// The attempt starts again (LiveKit trying another region): what the
  /// earlier one reported is dropped.
  void started() {
    _started = _span.elapsed;
    _websocket = null;
    _joined = null;
    _media = null;
  }

  void websocketOpen() => _websocket = _span.elapsed;

  void joinAnswered() => _joined = _span.elapsed;

  void mediaConnected() => _media = _span.elapsed;
}
