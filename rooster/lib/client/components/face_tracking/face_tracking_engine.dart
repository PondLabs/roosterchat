import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'face_anchor.dart';
import 'face_tracker.dart';

/// The two eyes of a face, [rightEye] being the person's right eye.
typedef FaceEyes = ({Offset rightEye, Offset leftEye});

/// The part of a frame a detector looks at, and how: [source] (in whole
/// pixels of the frame, possibly reaching past its edges) scaled by [scale]
/// and drawn at the top left of a black picture of [input] pixels.
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

/// One frame of a video, held until it is cut for a detector.
abstract class FaceFrame {
  /// The frame's size, upright, in pixels.
  Size get size;

  /// Starts cutting [crop] out of this frame for the detector, and lets the
  /// frame go. The cut may take a while to be ready (a browser cuts on the
  /// GPU): the engine cuts the next frames while a detection runs.
  FaceCut cut(FaceCrop crop, {required bool readFrameCode});

  /// Lets the frame go without cutting it.
  void discard();
}

/// A [FaceCrop] cut out of a frame, waiting for the detector.
abstract class FaceCut {
  /// Looks for a face in it, and lets it go.
  Future<FaceDetection> detect();

  /// Lets it go without looking.
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
    // In whole pixels: the browser cuts frames on them.
    final side = math
        .max(smallestSquare, across.distance * squareInEyeDistances)
        .roundToDouble();
    final centre = (eyes.rightEye + eyes.leftEye) / 2 + down * squareDrop;
    return FaceCrop(
        Rect.fromLTWH((centre.dx - side / 2).roundToDouble(),
            (centre.dy - side / 2).roundToDouble(), side, side),
        followSide / side,
        const Size(followSide, followSide));
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
///
/// While one detection runs, the frames of the next trackers due are
/// grabbed and cut, up to [lookahead] frames on their way between grab and
/// answer, so each cut is ready when its turn comes. A tracker has up to [inFlight] frames on their way: the next
/// is cut around the face where it was last seen, without waiting for the
/// one before, so a slow trip to the GPU and back does not slow its rate.
/// Up to [asked] detections are asked for at once: the detector does them
/// one after the other, in order, without waiting for each answer to come
/// back before it hears of the next.
class FaceTrackingEngine {
  FaceTrackingEngine({
    this.rate = 15,
    this.lookahead = 16,
    this.inFlight = 2,
    this.asked = 4,
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatch();

  final int rate;
  final int lookahead;
  final int inFlight;
  final int asked;
  final Duration Function() _clock;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final _trackers = <_EngineTracker>[];

  /// Trackers whose frame is being grabbed and cut, in the order they will
  /// be detected in.
  final _queue = <(_EngineTracker, Future<_Cut?>)>[];

  /// The trackers of the detections asked for, once each per detection.
  final _detecting = <_EngineTracker>[];
  var _turn = 0;
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

  bool _waiting(_EngineTracker tracker) =>
      [..._detecting, for (final (queued, _) in _queue) queued]
          .where((other) => other == tracker)
          .length >=
      inFlight;

  /// Cuts the frames of the trackers due, up to [lookahead] ahead, and asks
  /// for the next detections; or waits for a tracker to be due.
  void _pump() {
    _wake?.cancel();
    _wake = null;
    final now = _clock();
    Duration? soonest;
    while (_queue.length + _detecting.length < lookahead) {
      _EngineTracker? due;
      for (var i = 0; i < _trackers.length; i++) {
        final index = (_turn + i) % _trackers.length;
        final tracker = _trackers[index];
        if (_waiting(tracker)) continue;
        final last = tracker._grabbed;
        final wait = last == null ? Duration.zero : last + _every - now;
        if (wait <= Duration.zero) {
          _turn = (index + 1) % _trackers.length;
          due = tracker;
          break;
        }
        if (soonest == null || wait < soonest) soonest = wait;
      }
      if (due == null) break;
      due._grabbed = now;
      _queue.add((due, due._cut()));
    }
    while (_detecting.length < asked && _queue.isNotEmpty) {
      final (tracker, cut) = _queue.removeAt(0);
      _detecting.add(tracker);
      cut.then(tracker._detect).whenComplete(() {
        _detecting.remove(tracker);
        _pump();
      });
    }
    if (soonest != null && _queue.length + _detecting.length < lookahead) {
      _wake = Timer(soonest, _pump);
    }
  }
}

typedef _Cut = (Size, FaceCrop, FaceCut);

class _EngineTracker implements FaceTracker {
  _EngineTracker(this._engine, this._source, this._readFrameCode);

  final FaceTrackingEngine _engine;
  final FaceFrameSource _source;
  final bool _readFrameCode;
  final _follow = FaceSearchAndFollow();
  final _observation = ValueNotifier<FaceObservation?>(null);

  /// When its last frame was grabbed: what its rate is kept by.
  Duration? _grabbed;
  var _disposed = false;
  var _reported = false;

  @override
  ValueListenable<FaceObservation?> get observation => _observation;

  /// Grabs its newest frame and starts cutting where the face is expected.
  Future<_Cut?> _cut() async {
    try {
      final frame = await _source.grab();
      if (frame == null) return null;
      if (_disposed) {
        frame.discard();
        return null;
      }
      final crop = _follow.next(frame.size);
      return (
        frame.size,
        crop,
        frame.cut(crop, readFrameCode: _readFrameCode),
      );
    } catch (error, stack) {
      _report(error, stack);
      return null;
    }
  }

  Future<void> _detect(_Cut? cut) async {
    if (cut == null) return;
    final (size, crop, pending) = cut;
    if (_disposed) {
      pending.discard();
      return;
    }
    try {
      final detection = await pending.detect();
      if (_disposed) return;
      _observation.value = FaceObservation(
        videoSize: size,
        anchor: _follow.found(crop, detection.eyes),
        frameCode: detection.frameCode,
      );
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Reported once: a detector that cannot load fails every frame.
  void _report(Object error, StackTrace stack) {
    if (_reported || _disposed) return;
    _reported = true;
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'face tracking',
      context: ErrorDescription('while looking for a face in a video'),
    ));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine._remove(this);
    _observation.dispose();
  }
}
