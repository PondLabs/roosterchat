import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../face_tracker.dart';

/// A test video playing as a WebRTC video track, for the demonstration.
/// Outside the browser a track fed by a file comes with the first native
/// tracker (docs/adr/0006-face-tracking.md).
class DemoVideo {
  DemoVideo._(this.renderer, this.source);

  static Future<DemoVideo> open(String url) =>
      throw UnsupportedError('No video track from a file on this platform');

  final RTCVideoRenderer renderer;
  final FaceVideoSource source;

  /// How far into the video the frame on screen is, in seconds.
  double get seconds => 0;

  void dispose() {}
}

/// Reads a text file of the test media.
Future<String> readDemoText(String url) =>
    throw UnsupportedError('No test media on this platform');

/// Hands the run's record to whoever drives the demonstration.
void publishDemoLog(String Function() read) {}

/// Lets whoever drives the demonstration start the tracking.
void publishDemoStart(void Function() start) {}
