import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// The `media_show` span of one picture of a chat (an attachment, a video's
/// poster) shown at one level, its thumbnail or the full picture, in the
/// app's [SpeedLog]: from its load starting to the end of the first frame
/// drawn with it. See `docs/speed-log.md`.
///
/// The picture's image (`LODImageCompleter`) opens it and runs the load in
/// it ([run]); the loader reports what it found ([current]). The steps:
///
/// - `cache_hit`: the start to the bytes read from this device (the file
///   cache, or the account's own media), values `bytes` and `level`;
/// - `cache_miss`: the start to the device having nothing, value `level`;
/// - `download`: the miss to the bytes from the homeserver (after any new
///   attempts), value `bytes`; its requests are in the log under the span;
/// - `decode`: the bytes to the engine's decode;
/// - `first_paint`: the start to the end of the first frame drawn with the
///   picture, unavailable when nothing listens or no frame comes in 2 s.
///
/// `level` is 1 for the thumbnail (the sender's or the homeserver's), 2 for
/// the full picture. Only fixed names and numbers: no address, file name,
/// type or event id.
class MediaShowTrace {
  MediaShowTrace._(this.span, this._level);

  final SpeedSpan span;
  final int _level;
  bool _missed = false;
  bool _downloaded = false;

  static final Object _key = Object();

  /// How long [nextFrameDrawn] waits for a frame before `first_paint` is
  /// unavailable (a hidden window draws none).
  static const frameTimeout = Duration(seconds: 2);

  /// Waits for the end of the next frame drawn; false when none can be
  /// observed. Only tests replace it.
  static Future<bool> Function() nextFrameDrawn = _schedulerFrame;

  /// Opens the span of a picture's [thumbnail] or full picture.
  static MediaShowTrace start({required bool thumbnail}) => MediaShowTrace._(
      SpeedLog.instance.startSpan(SpeedOperation.mediaShow), thumbnail ? 1 : 2);

  /// The trace the current code loads for, if any.
  static MediaShowTrace? get current => Zone.current[_key] as MediaShowTrace?;

  /// Runs [load] in the trace: its requests are linked to the span, and
  /// the loader finds the trace as [current].
  Future<T> run<T>(Future<T> Function() load) =>
      span.run(() => runZoned(load, zoneValues: {_key: this}));

  /// The bytes were on this device.
  void cacheHit(int bytes) {
    if (span.isFinished) return;
    span.mark(SpeedStep.cacheHit,
        values: {SpeedValue.bytes: bytes, SpeedValue.level: _level});
  }

  /// Nothing on this device: the homeserver is asked.
  void cacheMiss() {
    if (span.isFinished || _missed) return;
    _missed = true;
    span.mark(SpeedStep.cacheMiss, values: {SpeedValue.level: _level});
  }

  /// The bytes came from the homeserver.
  void downloaded(int bytes) {
    if (span.isFinished || _downloaded) return;
    _downloaded = true;
    span.mark(SpeedStep.download, values: {SpeedValue.bytes: bytes});
  }

  void decoded() {
    if (span.isFinished) return;
    span.mark(SpeedStep.decode);
  }

  /// The picture was handed to the image's listeners ([painted]: there was
  /// one): `first_paint` once the next frame is drawn, and the span ends.
  Future<void> shown({required bool painted}) async {
    if (span.isFinished) return;
    if (painted && await nextFrameDrawn()) {
      span.addStep(SpeedStep.firstPaint, Duration.zero, span.elapsed);
    } else {
      span.unavailable(SpeedStep.firstPaint);
    }
    span.finish();
  }

  /// No picture: the load failed.
  void failed() => span.finish(outcome: SpeedOutcome.failed);

  /// No picture, and no failure (nothing to show at this level).
  void dropped() => span.finish(outcome: SpeedOutcome.cancelled);

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
