import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'face_anchor.dart';
import 'face_tracker.dart';

/// The reference points of a test video: where the eyes and the middle of
/// the forehead are in each frame, from a source that is none of the
/// detectors being judged (tools/face_tracking/README.md).
class FaceReference {
  FaceReference(this.videoSize, this.fps, this.frames);

  /// Reads a `<video>.reference.json`.
  factory FaceReference.fromJson(Map<String, dynamic> json) {
    final size = Size(
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    );
    Offset point(dynamic xy) => Offset(
          (xy[0] as num) * size.width,
          (xy[1] as num) * size.height,
        );
    return FaceReference(size, (json['fps'] as num).toDouble(), [
      for (final frame in json['frames'] as List)
        if (frame['face'] case final Map face)
          (
            rightEye: point(face['rightEye']),
            leftEye: point(face['leftEye']),
            forehead: point(face['forehead']),
          )
        else
          null,
    ]);
  }

  final Size videoSize;
  final double fps;

  /// One entry per frame, by frame code: null where the frame has no face.
  final List<({Offset rightEye, Offset leftEye, Offset forehead})?> frames;

  /// The anchor a perfect tracker gives for a frame, moved [shift] eye
  /// distances along the line of the eyes.
  FaceAnchor? anchorAt(int frameCode, {double shift = 0}) {
    final face = frames[frameCode % frames.length];
    if (face == null) return null;
    final eyes = face.leftEye - face.rightEye;
    return FaceAnchor(
      center: face.forehead + eyes * shift,
      width: eyes.distance * FaceAnchor.widthInEyeDistances,
      angle: eyes.direction,
    );
  }
}

/// A tracker that detects nothing: it repeats the reference points of the
/// frame on screen. What the demonstration and the measuring tool are
/// checked with: it scores 100%, and 0% with a [shift] of half an eye
/// distance.
class ReplayFaceTracker implements FaceTracker {
  ReplayFaceTracker(
    this.reference,
    this.currentFrame, {
    this.shift = 0,
    Duration every = const Duration(milliseconds: 66),
  }) {
    _timer = Timer.periodic(every, (_) => tick());
  }

  final FaceReference reference;

  /// The frame code of the frame on screen, or null when none is.
  final int? Function() currentFrame;

  final double shift;

  late final Timer _timer;
  final _observation = ValueNotifier<FaceObservation?>(null);

  @override
  ValueListenable<FaceObservation?> get observation => _observation;

  /// Looks at the frame on screen once: what the timer does.
  @visibleForTesting
  void tick() {
    final code = currentFrame();
    if (code == null) return;
    _observation.value = FaceObservation(
      videoSize: reference.videoSize,
      anchor: reference.anchorAt(code, shift: shift),
      frameCode: code,
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _observation.dispose();
  }
}
