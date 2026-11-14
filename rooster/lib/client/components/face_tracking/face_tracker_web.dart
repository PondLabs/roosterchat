import 'face_tracker.dart';

/// Face tracking in the browser: YuNet on ONNX Runtime Web in a worker,
/// reading the video element the renderer already has
/// (docs/adr/0006-face-tracking.md). Not there yet.
const FaceTrackerPlatform webFaceTracker = UnavailableFaceTracker();

/// This device's face tracking: in a browser, the browser's.
FaceTrackerPlatform get faceTrackerPlatform => webFaceTracker;
