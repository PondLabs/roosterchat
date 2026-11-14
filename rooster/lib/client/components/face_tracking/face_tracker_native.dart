import 'package:flutter/foundation.dart';

import 'face_tracker.dart';
import 'face_tracker_android.dart';
import 'face_tracker_linux.dart';
import 'face_tracker_macos.dart';
import 'face_tracker_windows.dart';

/// This device's face tracking, outside the browser.
FaceTrackerPlatform get faceTrackerPlatform => switch (defaultTargetPlatform) {
      TargetPlatform.android => androidFaceTracker,
      TargetPlatform.linux => linuxFaceTracker,
      TargetPlatform.macOS => macosFaceTracker,
      TargetPlatform.windows => windowsFaceTracker,
      // Rooster does not ship for iOS or Fuchsia.
      final other => UnavailableFaceTracker(other.name),
    };
