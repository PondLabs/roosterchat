import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'face_anchor.dart';
import 'face_tracker.dart';

/// The two eyes of a face, [rightEye] being the person's right eye.
typedef FaceEyes = ({Offset rightEye, Offset leftEye});

/// The part of a frame a detector looks at, and how: [source] (in pixels of
/// the frame, possibly reaching past its edges) scaled by [scale] and drawn
/// at the top left of a black picture of [input] pixels.
class FaceCrop {
  const FaceCrop(this.source, this.scale, this.input);

  final Rect source;

  /// Pixels of the detector's input per pixel of the frame.
  final double scale;

  final Size input;

  /// A point of the detector's input, in pixels of the frame.
  Offset toFrame(Offset point) => source.topLeft + point / scale;

  @override
  String toString() => 'FaceCrop($source x$scale in $input)';
}

/// What a detector found in a [FaceCrop]: the eyes, in pixels of its input,
/// and the frame code when asked for one.
class FaceDetection {
  const FaceDetection({this.eyes, this.frameCode});

  final FaceEyes? eyes;
  final int? frameCode;
}

/// One frame of a video, held until a detector has looked at it.
abstract class FaceFrame {
  /// The frame's size, upright, in pixels.
  Size get size;

  /// Looks for a face in [crop] of this frame, and lets the frame go.
  Future<FaceDetection> detect(FaceCrop crop, {required bool readFrameCode});

  /// Lets the frame go without looking at it.
  void discard();
}

/// Where a tracker gets the frames of its video.
abstract class FaceFrameSource {
  /// The newest frame of the video, or null when no frame can be had: the
  /// video is not on screen, or has not started.
  Future<FaceFrame?> grab();
}

/// How a face is followed from frame to frame
/// (docs/adr/0006-face-tracking.md): while none is known, the whole frame,
/// shrunk; once one is, a square around it, 5 eye distances wide and 0.35
/// eye distances below the eyes. When the square comes back empty the face
/// is gone, and the next frame is a search again.
class FaceSearchAndFollow {
  /// The longer side of a searched frame, in the detector's input.
  static const searchSide = 320.0;

  /// The side of the followed square, in the detector's input.
  static const followSide = 128.0;

  static const squareInEyeDistances = 5.0;
  static const squareDrop = 0.35;

  /// The smallest square looked at, in pixels of the frame.
  static const smallestSquare = 48.0;

  /// YuNet's input sides are multiples of its largest stride.
  static const _grid = 32;

  FaceEyes? _eyes;

  /// Where to look in the next frame, of [frameSize].
  FaceCrop next(Size frameSize) {
    final eyes = _eyes;
    if (eyes == null) {
      final scale = searchSide / math.max(frameSize.width, frameSize.height);
      double fit(double side) => (side * scale / _grid).ceil() * _grid * 1.0;
      return FaceCrop(Offset.zero & frameSize, scale,
          Size(fit(frameSize.width), fit(frameSize.height)));
    }
    final across = eyes.leftEye - eyes.rightEye;
    final down = Offset(-across.dy, across.dx);
    final side =
        math.max(smallestSquare, across.distance * squareInEyeDistances);
    final centre = (eyes.rightEye + eyes.leftEye) / 2 + down * squareDrop;
    return FaceCrop(Rect.fromCenter(center: centre, width: side, height: side),
        followSide / side, const Size(followSide, followSide));
  }

  /// What the detector found in [crop], its eyes in pixels of the input:
  /// the anchor in the frame, or null when it found nothing.
  FaceAnchor? found(FaceCrop crop, FaceEyes? eyes) {
    if (eyes == null) {
      _eyes = null;
      return null;
    }
    final inFrame = (
      rightEye: crop.toFrame(eyes.rightEye),
      leftEye: crop.toFrame(eyes.leftEye),
    );
    _eyes = inFrame;
    return FaceAnchor.fromEyes(
        rightEye: inFrame.rightEye, leftEye: inFrame.leftEye);
  }
}

/// One detector serving every tracker of the app, in turn: each at most
/// [rate] times a second, always on its newest frame, so eight videos cost
/// eight detections and not eight detectors.
class FaceTrackingEngine {
  FaceTrackingEngine({this.rate = 15, Duration Function()? clock})
      : _clock = clock ?? _stopwatch();

  final int rate;
  final Duration Function() _clock;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final _trackers = <_EngineTracker>[];
  var _turn = 0;
  var _busy = false;
  Timer? _wake;

  Duration get _every => Duration(microseconds: 1000000 ~/ rate);

  /// How many trackers it serves.
  int get trackers => _trackers.length;

  /// Starts following the face in the frames of [source].
  FaceTracker track(FaceFrameSource source, {required bool readFrameCode}) {
    final tracker = _EngineTracker(this, source, readFrameCode);
    _trackers.add(tracker);
    _pump();
    return tracker;
  }

  void _remove(_EngineTracker tracker) {
    final index = _trackers.indexOf(tracker);
    if (index < 0) return;
    _trackers.removeAt(index);
    if (index < _turn) _turn--;
    if (_trackers.isEmpty) {
      _wake?.cancel();
      _wake = null;
    }
  }

  /// Starts the next detection that is due, or waits for one to be.
  void _pump() {
    if (_busy || _trackers.isEmpty) return;
    _wake?.cancel();
    _wake = null;
    final now = _clock();
    Duration? soonest;
    for (var i = 0; i < _trackers.length; i++) {
      final index = (_turn + i) % _trackers.length;
      final tracker = _trackers[index];
      final last = tracker._lastStart;
      final wait = last == null ? Duration.zero : last + _every - now;
      if (wait <= Duration.zero) {
        _turn = (index + 1) % _trackers.length;
        tracker._lastStart = now;
        _busy = true;
        tracker._detect().whenComplete(() {
          _busy = false;
          _pump();
        });
        return;
      }
      if (soonest == null || wait < soonest) soonest = wait;
    }
    _wake = Timer(soonest!, _pump);
  }
}

class _EngineTracker implements FaceTracker {
  _EngineTracker(this._engine, this._source, this._readFrameCode);

  final FaceTrackingEngine _engine;
  final FaceFrameSource _source;
  final bool _readFrameCode;
  final _follow = FaceSearchAndFollow();
  final _observation = ValueNotifier<FaceObservation?>(null);
  Duration? _lastStart;
  var _disposed = false;
  var _reported = false;

  @override
  ValueListenable<FaceObservation?> get observation => _observation;

  Future<void> _detect() async {
    try {
      final frame = await _source.grab();
      if (frame == null) return;
      if (_disposed) {
        frame.discard();
        return;
      }
      final crop = _follow.next(frame.size);
      final detection = await frame.detect(crop, readFrameCode: _readFrameCode);
      if (_disposed) return;
      _observation.value = FaceObservation(
        videoSize: frame.size,
        anchor: _follow.found(crop, detection.eyes),
        frameCode: detection.frameCode,
      );
    } catch (error, stack) {
      // Reported once: a detector that cannot load fails every frame.
      if (_reported || _disposed) return;
      _reported = true;
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'face tracking',
        context: ErrorDescription('while looking for a face in a video'),
      ));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine._remove(this);
    _observation.dispose();
  }
}
