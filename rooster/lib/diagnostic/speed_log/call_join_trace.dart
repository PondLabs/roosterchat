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
/// - `microphone_options`, `microphone_open`: the capture prepared during
///   the connection;
/// - `sfu_region_<region>`, or `sfu_region` unavailable when the SFU reports
///   none;
/// - `microphone_published`: from connected to the microphone published, or
///   unavailable when it was not (denied, no device, muted join);
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
  /// `first_remote_audio` to be timed.
  final Duration remoteAudioWindow;

  bool _microphoneSettled = false;
  bool _remoteSettled = false;
  StreamSubscription<void>? _remote;
  Timer? _remoteTimer;

  /// Runs [body] in the span: its requests are recorded with the span's id.
  Future<T> run<T>(Future<T> Function() body) => span.run(body);

  /// A step that lasts as long as [body].
  Future<T> time<T>(String step, Future<T> Function() body) =>
      span.time(step, body);

  /// Records the SFU's host class: LiveKit Cloud or anything else.
  void sfuHost({required bool livekitCloud}) => _instant(
      livekitCloud ? SpeedStep.sfuLivekitCloud : SpeedStep.sfuSelfHosted);

  /// The connection finished, in the SFU [region] (null when it reports
  /// none). Call [microphone] and [listenForRemoteAudio] right after: their
  /// steps count from here.
  void connected(String? region) {
    final name = region == null ? null : _regionStep(region);
    if (name == null) {
      span.unavailable(SpeedStep.sfuRegion);
    } else {
      _instant(name);
    }
  }

  /// The microphone is being published: [published] completes with whether
  /// it was. Not published is `microphone_published` unavailable.
  void microphone(Future<bool> published) {
    // A step is only added when its future completes: one that never does
    // adds nothing, and the step is written unavailable instead.
    final done = Completer<void>();
    span.time(SpeedStep.microphonePublished, () => done.future);
    published.then((ok) => ok, onError: (Object _) => false).then((ok) {
      if (ok) {
        done.complete();
      } else {
        span.unavailable(SpeedStep.microphonePublished);
      }
      _microphoneSettled = true;
      _finishWhenSettled();
    });
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

  static final RegExp _notIdentifier = RegExp(r'[^a-z0-9_]+');

  /// `sfu_region_<region>` as an identifier, or null when the region does
  /// not make one (it is the SFU's name for a data centre, such as `gru1`).
  static String? _regionStep(String region) {
    final cleaned = region.toLowerCase().replaceAll(_notIdentifier, '_');
    if (cleaned.isEmpty || cleaned.length > 28) return null;
    return '${SpeedStep.sfuRegionPrefix}$cleaned';
  }
}
