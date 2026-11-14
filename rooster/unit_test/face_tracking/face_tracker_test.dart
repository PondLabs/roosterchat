// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_android.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_linux.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_macos.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_native.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_windows.dart';

class _Track extends Fake implements MediaStreamTrack {}

class _Tracker extends Fake implements FaceTracker {}

class _Platform implements FaceTrackerPlatform {
  final tracker = _Tracker();
  FaceVideoSource? started;
  bool? readFrameCode;

  @override
  bool get isSupported => true;

  @override
  FaceTracker start(FaceVideoSource source, {required bool readFrameCode}) {
    started = source;
    this.readFrameCode = readFrameCode;
    return tracker;
  }
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    FaceTracker.debugPlatform = null;
  });

  final platforms = {
    TargetPlatform.android: androidFaceTracker,
    TargetPlatform.linux: linuxFaceTracker,
    TargetPlatform.macOS: macosFaceTracker,
    TargetPlatform.windows: windowsFaceTracker,
  };

  for (final MapEntry(key: platform, value: own) in platforms.entries) {
    test('${platform.name} answers with its own file, unavailable so far', () {
      debugDefaultTargetPlatformOverride = platform;

      expect(faceTrackerPlatform, same(own));
      for (final other in platforms.values.where((other) => other != own)) {
        expect(faceTrackerPlatform, isNot(same(other)));
      }
      expect(own.isSupported, isFalse);
      expect(FaceTracker.isSupported, isFalse);
      expect(
        () => FaceTracker.start(FaceVideoSource(_Track())),
        throwsUnsupportedError,
      );
    });
  }

  // The browser's file tracks faces and only compiles for the web: it is
  // measured in Chrome with the demonstration (tools/face_tracking/).
  test('every platform file stands for a platform of its own', () {
    final names = platforms.values
        .map((platform) => (platform as UnavailableFaceTracker).platform);

    expect(names, ['Android', 'Linux', 'macOS', 'Windows']);
  });

  test('a platform Rooster does not ship for does not track', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(FaceTracker.isSupported, isFalse);
  });

  test('FaceTracker answers for the platform, and starts its tracker', () {
    final platform = _Platform();
    FaceTracker.debugPlatform = platform;
    final source = FaceVideoSource(_Track(), mirrored: true);

    expect(FaceTracker.isSupported, isTrue);
    expect(
        FaceTracker.start(source, readFrameCode: true), same(platform.tracker));
    expect(platform.started, same(source));
    expect(platform.readFrameCode, isTrue);
  });
}
