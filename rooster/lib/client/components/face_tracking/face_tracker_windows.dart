import 'face_tracker.dart';

/// Face tracking on Windows: the same engine and frame tap as Linux
/// (docs/adr/0006-face-tracking.md). Not there yet.
const FaceTrackerPlatform windowsFaceTracker =
    UnavailableFaceTracker('Windows');
