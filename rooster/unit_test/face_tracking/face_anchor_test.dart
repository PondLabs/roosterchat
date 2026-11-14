import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/face_tracking/face_anchor.dart';

void main() {
  // A face looking at the camera in a 640x480 video: eyes 80 pixels apart.
  const rightEye = Offset(280, 200);
  const leftEye = Offset(360, 200);
  const video = Size(640, 480);

  Matcher near(Offset offset) => within<Offset>(
        distance: 1e-9,
        from: offset,
        distanceFunction: (a, b) => (a - b).distance,
      );

  group('the anchor from the eyes', () {
    test('sits on the forehead, as wide as the forehead, level', () {
      final anchor = FaceAnchor.fromEyes(rightEye: rightEye, leftEye: leftEye);

      expect(anchor.center, near(const Offset(320, 200 - 0.58 * 80)));
      expect(anchor.width, closeTo(2.2 * 80, 1e-9));
      expect(anchor.angle, closeTo(0, 1e-9));
    });

    test('grows with the face', () {
      final anchor = FaceAnchor.fromEyes(
        rightEye: const Offset(240, 200),
        leftEye: const Offset(400, 200),
      );

      expect(anchor.center, near(const Offset(320, 200 - 0.58 * 160)));
      expect(anchor.width, closeTo(2.2 * 160, 1e-9));
    });

    test('tilts with the head, and stays above the eyes along the tilt', () {
      // The head tilted 30 degrees clockwise on screen, eyes still 80 apart.
      const tilt = math.pi / 6;
      final half = Offset(math.cos(tilt), math.sin(tilt)) * 40;
      const middle = Offset(320, 200);
      final anchor = FaceAnchor.fromEyes(
        rightEye: middle - half,
        leftEye: middle + half,
      );

      expect(anchor.angle, closeTo(tilt, 1e-9));
      expect(anchor.width, closeTo(2.2 * 80, 1e-9));
      expect(
        anchor.center,
        near(middle + Offset(math.sin(tilt), -math.cos(tilt)) * (0.58 * 80)),
      );
    });
  });

  group('a frame that arrives turned', () {
    final upright = FaceAnchor.fromEyes(rightEye: rightEye, leftEye: leftEye);

    // The same face as the decoder hands it over when the frame has to be
    // turned clockwise by this much to be upright.
    final turned = {
      90: (
        const Size(480, 640),
        const Offset(200, 360),
        const Offset(200, 280)
      ),
      180: (
        const Size(640, 480),
        const Offset(360, 280),
        const Offset(280, 280)
      ),
      270: (
        const Size(480, 640),
        const Offset(280, 280),
        const Offset(280, 360)
      ),
    };

    for (final MapEntry(key: rotation, value: (frame, right, left))
        in turned.entries) {
      test('by $rotation degrees gives the anchor of the upright face', () {
        final anchor = FaceAnchor.fromEyes(
          rightEye: FaceAnchor.uprightPoint(right, frame, rotation),
          leftEye: FaceAnchor.uprightPoint(left, frame, rotation),
        );

        expect(FaceAnchor.uprightSize(frame, rotation), video);
        expect(anchor.center, near(upright.center));
        expect(anchor.width, closeTo(upright.width, 1e-9));
        expect(anchor.angle, closeTo(upright.angle, 1e-9));
      });
    }

    test('by nothing is left alone', () {
      expect(FaceAnchor.uprightPoint(rightEye, video, 0), rightEye);
      expect(FaceAnchor.uprightSize(video, 0), video);
    });
  });

  group('the anchor where the video is shown', () {
    const anchor = FaceAnchor(center: Offset(160, 120), width: 176, angle: 0.3);

    test('cropped by BoxFit.cover', () {
      // 640x480 covering 300x300: drawn 400x300, 50 pixels cut off each side.
      final shown =
          anchor.inBox(videoSize: video, boxSize: const Size(300, 300));

      expect(shown.center, near(const Offset(50, 75)));
      expect(shown.width, closeTo(176 * 0.625, 1e-9));
      expect(shown.angle, closeTo(0.3, 1e-9));
    });

    test('cropped by BoxFit.cover in a tall box, out of the box on one side',
        () {
      // 640x480 covering 150x480: drawn 640x480, 245 pixels cut off each side.
      final shown =
          anchor.inBox(videoSize: video, boxSize: const Size(150, 480));

      expect(shown.center, near(const Offset(160 - 245, 120)));
      expect(shown.width, closeTo(176, 1e-9));
    });

    test('letterboxed by BoxFit.contain', () {
      // 640x480 inside 300x300: drawn 300x225, 37.5 pixels of bar above.
      final shown = anchor.inBox(
        videoSize: video,
        boxSize: const Size(300, 300),
        fit: BoxFit.contain,
      );

      expect(shown.center, near(const Offset(75, 37.5 + 56.25)));
      expect(shown.width, closeTo(176 * 0.46875, 1e-9));
      expect(shown.angle, closeTo(0.3, 1e-9));
    });

    test('mirrored: the other side of the box, tilted the other way', () {
      final shown = anchor.inBox(
        videoSize: video,
        boxSize: const Size(300, 300),
        mirrored: true,
      );

      expect(shown.center, near(const Offset(250, 75)));
      expect(shown.width, closeTo(176 * 0.625, 1e-9));
      expect(shown.angle, closeTo(-0.3, 1e-9));
    });

    test('stretched by BoxFit.fill: the tilt and the width stretch too', () {
      const diagonal = FaceAnchor(
        center: Offset(320, 240),
        width: 100,
        angle: math.pi / 4,
      );
      final shown = diagonal.inBox(
        videoSize: video,
        boxSize: const Size(1280, 480),
        fit: BoxFit.fill,
      );

      expect(shown.center, near(const Offset(640, 240)));
      expect(shown.angle, closeTo(math.atan2(1, 2), 1e-9));
      expect(shown.width, closeTo(100 * math.sqrt(2.5), 1e-9));
    });
  });
}
