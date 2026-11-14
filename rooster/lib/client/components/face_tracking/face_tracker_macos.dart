import 'face_tracker.dart';

/// Face tracking on macOS: Apple's Vision framework, fed by flutter-webrtc's
/// video renderer (docs/adr/0006-face-tracking.md). Not there yet.
const FaceTrackerPlatform macosFaceTracker = UnavailableFaceTracker();
