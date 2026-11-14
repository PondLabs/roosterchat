import 'face_tracker.dart';

/// Face tracking on Linux: YuNet on tract, in Rooster's Rust library, fed
/// by flutter-webrtc's video renderer (docs/adr/0006-face-tracking.md). Not
/// there yet.
const FaceTrackerPlatform linuxFaceTracker = UnavailableFaceTracker('Linux');
