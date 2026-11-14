import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;

import 'face_anchor.dart';
import 'face_tracker_platform.dart';

/// The video a [FaceTracker] looks at: a WebRTC video track, ours or
/// someone else's. A camera `VoipStream` hands one out
/// (docs/adr/0006-face-tracking.md).
class FaceVideoSource {
  const FaceVideoSource(this.track, {this.mirrored = false});

  final MediaStreamTrack track;

  /// Whether the app shows this video mirrored, as it does our own camera:
  /// what `FaceAnchor.inBox` needs to know.
  final bool mirrored;
}

/// What a tracker found in one frame of a video.
class FaceObservation {
  const FaceObservation({
    required this.videoSize,
    this.anchor,
    this.frameCode,
  });

  /// The size of the frame, upright, in pixels: what [anchor] is in.
  final Size videoSize;

  /// Where the plaque goes in that frame, or null when it has no face.
  final FaceAnchor? anchor;

  /// The frame code burned into the test videos
  /// (tools/face_tracking/frame_code.py), read from the very frame that was
  /// analysed. Only when the tracker was started with `readFrameCode`.
  final int? frameCode;
}

/// Follows one face in one video, on this device: no frame and nothing
/// about a face leaves it, or is kept (R4.6).
///
/// Whoever shows a video tracks it, so a plaque is drawn over the very
/// picture it was worked out from. A tracker costs a detection several
/// times a second: [dispose] it when the video leaves the screen.
abstract class FaceTracker {
  /// Whether this device tracks faces. Where it does not, the game is not
  /// offered: there is no plaque without a face to put it on.
  static bool get isSupported => _platform.isSupported;

  /// Starts following the face in [source]. With [readFrameCode] every
  /// observation carries the frame code of its frame, for measuring against
  /// the test videos. Throws [UnsupportedError] where not [isSupported].
  static FaceTracker start(
    FaceVideoSource source, {
    bool readFrameCode = false,
  }) =>
      _platform.start(source, readFrameCode: readFrameCode);

  /// Stands in for this device's tracking in a test.
  @visibleForTesting
  static FaceTrackerPlatform? debugPlatform;

  static FaceTrackerPlatform get _platform =>
      debugPlatform ?? faceTrackerPlatform;

  /// The latest frame analysed: null until the first one. Its anchor is
  /// null as soon as a frame has no face, and back when one does.
  ValueListenable<FaceObservation?> get observation;

  void dispose();
}

/// How one platform tracks faces. Each platform has its own file next to
/// this one, and a platform's task only touches its own.
abstract class FaceTrackerPlatform {
  bool get isSupported;

  FaceTracker start(FaceVideoSource source, {required bool readFrameCode});
}

/// A platform that does not track faces, or not yet.
class UnavailableFaceTracker implements FaceTrackerPlatform {
  const UnavailableFaceTracker();

  @override
  bool get isSupported => false;

  @override
  FaceTracker start(FaceVideoSource source, {required bool readFrameCode}) =>
      throw UnsupportedError('This device does not track faces');
}
