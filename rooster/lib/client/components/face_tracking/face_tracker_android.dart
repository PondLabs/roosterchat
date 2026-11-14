import 'face_tracker.dart';

/// Face tracking on Android: BlazeFace on LiteRT, fed by flutter-webrtc's
/// video renderer, with the camera's rotation undone
/// (docs/adr/0006-face-tracking.md). Not there yet.
const FaceTrackerPlatform androidFaceTracker =
    UnavailableFaceTracker('Android');
