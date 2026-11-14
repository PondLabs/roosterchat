import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/face_tracking/face_anchor.dart';
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/face_tracking/face_tracking_engine.dart';

typedef _Eyes = ({Offset rightEye, Offset leftEye});

const _frameSize = Size(640, 480);

/// A face looking at the camera, eyes 60 pixels apart, drifting right.
_Eyes _face(Duration t) {
  final x = 260 + t.inMilliseconds / 50;
  return (rightEye: Offset(x, 200), leftEye: Offset(x + 60, 200));
}

/// A test video: where the face is at each moment, or null while it is out
/// of the picture. Its frames are what a detector would see: the face is
/// found when both eyes are inside the crop it was asked to look at.
class _Video implements FaceFrameSource {
  _Video(this.engine, this.faceAt);

  final _Engine engine;
  final _Eyes? Function(Duration t) faceAt;
  bool onScreen = true;
  int grabs = 0;
  final crops = <FaceCrop>[];

  @override
  Future<FaceFrame?> grab() async {
    grabs++;
    if (!onScreen) return null;
    return _Frame(this, faceAt(engine.now()), grabs);
  }
}

class _Frame implements FaceFrame {
  _Frame(this.video, this.eyes, this.code);

  final _Video video;
  final _Eyes? eyes;
  final int code;

  @override
  Size get size => _frameSize;

  @override
  Future<FaceDetection> detect(FaceCrop crop,
      {required bool readFrameCode}) async {
    final engine = video.engine;
    expect(engine.inFlight, 0, reason: 'one detection at a time');
    engine.inFlight++;
    video.crops.add(crop);
    await Future<void>.delayed(engine.detectTime);
    engine.inFlight--;
    if (engine.fail) throw StateError('the worker died');
    final eyes = this.eyes;
    final seen = eyes != null &&
        crop.source.contains(eyes.rightEye) &&
        crop.source.contains(eyes.leftEye);
    Offset toInput(Offset p) => (p - crop.source.topLeft) * crop.scale;
    return FaceDetection(
      eyes: seen
          ? (rightEye: toInput(eyes.rightEye), leftEye: toInput(eyes.leftEye))
          : null,
      frameCode: readFrameCode ? code : null,
    );
  }

  @override
  void discard() {}
}

class _Engine {
  _Engine(this.async) : engine = FaceTrackingEngine(clock: () => async.elapsed);

  final FakeAsync async;
  final FaceTrackingEngine engine;
  Duration detectTime = const Duration(milliseconds: 6);
  int inFlight = 0;
  bool fail = false;

  Duration now() => async.elapsed;

  /// Starts a tracker on a video, keeping every observation with its time.
  (_Video, FaceTracker, List<(Duration, FaceObservation)>) track(
      _Eyes? Function(Duration t) faceAt,
      {bool readFrameCode = false,
      bool onScreen = true}) {
    final video = _Video(this, faceAt)..onScreen = onScreen;
    final tracker = engine.track(video, readFrameCode: readFrameCode);
    final seen = <(Duration, FaceObservation)>[];
    tracker.observation.addListener(
        () => seen.add((async.elapsed, tracker.observation.value!)));
    return (video, tracker, seen);
  }
}

void main() {
  group('FaceSearchAndFollow', () {
    test('searches the whole frame, its longer side shrunk to 320', () {
      final crop = FaceSearchAndFollow().next(_frameSize);

      expect(crop.source, Offset.zero & _frameSize);
      expect(crop.scale, 0.5);
      // YuNet's grid needs sides in multiples of 32: the rest is black.
      expect(crop.input, const Size(320, 256));
    });

    test('a portrait frame is searched upright too', () {
      final crop = FaceSearchAndFollow().next(const Size(720, 1280));

      expect(crop.scale, 0.25);
      expect(crop.input, const Size(192, 320));
    });

    test('follows a face found with a square around it', () {
      final follow = FaceSearchAndFollow();
      final search = follow.next(_frameSize);
      final anchor = follow.found(search, (
        rightEye: const Offset(150, 100),
        leftEye: const Offset(180, 100),
      ));

      // Eyes 60 pixels apart in the frame, at (300, 200) and (360, 200).
      expect(
        anchor,
        FaceAnchor.fromEyes(
          rightEye: const Offset(300, 200),
          leftEye: const Offset(360, 200),
        ),
      );
      final square = follow.next(_frameSize);
      expect(square.input, const Size(128, 128));
      expect(square.source.width, closeTo(300, 1e-9));
      expect(square.source.height, closeTo(300, 1e-9));
      // Centred 0.35 eye distances below the middle of the eyes.
      expect(square.source.center.dx, closeTo(330, 1e-9));
      expect(square.source.center.dy, closeTo(221, 1e-9));
      expect(square.scale, closeTo(128 / 300, 1e-12));
    });

    test('the square turns with a tilted head', () {
      final follow = FaceSearchAndFollow();
      follow.found(follow.next(_frameSize), (
        rightEye: const Offset(150, 100),
        leftEye: const Offset(150, 130),
      ));

      // Eyes one above the other, the face turned a quarter clockwise:
      // "below the eyes" is to the left of the picture.
      expect(follow.next(_frameSize).source.center.dx, closeTo(279, 1e-9));
      expect(follow.next(_frameSize).source.center.dy, closeTo(230, 1e-9));
    });

    test('a point of the square comes back to the frame', () {
      final follow = FaceSearchAndFollow();
      follow.found(follow.next(_frameSize),
          (rightEye: const Offset(150, 100), leftEye: const Offset(180, 100)));
      final square = follow.next(_frameSize);

      expect(square.toFrame(Offset.zero), square.source.topLeft);
      expect(square.toFrame(const Offset(128, 128)).dx,
          closeTo(square.source.right, 1e-9));
    });

    test('an empty square means no face, and the next frame is a search', () {
      final follow = FaceSearchAndFollow();
      follow.found(follow.next(_frameSize),
          (rightEye: const Offset(150, 100), leftEye: const Offset(180, 100)));

      expect(follow.found(follow.next(_frameSize), null), isNull);
      expect(follow.next(_frameSize).source, Offset.zero & _frameSize);
    });

    test('a tiny face still gets a square a detector can see', () {
      final follow = FaceSearchAndFollow();
      follow.found(follow.next(_frameSize),
          (rightEye: const Offset(150, 100), leftEye: const Offset(152, 100)));

      expect(follow.next(_frameSize).source.width,
          FaceSearchAndFollow.smallestSquare);
    });
  });

  group('FaceTrackingEngine', () {
    test('puts the anchor on the face, from the frame it analysed', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final (_, tracker, seen) = engine.track(_face, readFrameCode: true);

        async.elapse(const Duration(seconds: 1));

        expect(seen, isNotEmpty);
        final observation = tracker.observation.value!;
        expect(observation.videoSize, _frameSize);
        expect(observation.frameCode, isNotNull);
        final anchor = observation.anchor!;
        // The face drifts 20 pixels a second: within a pixel of its place
        // when the frame was grabbed, one detection ago.
        final eyes = _face(seen.last.$1 - engine.detectTime);
        final expected =
            FaceAnchor.fromEyes(rightEye: eyes.rightEye, leftEye: eyes.leftEye);
        expect((anchor.center - expected.center).distance, lessThan(1e-6));
        expect(anchor.width, closeTo(expected.width, 1e-6));
        tracker.dispose();
      });
    });

    test('follows the face once found: only the first frame is a search', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final (video, tracker, _) = engine.track(_face);

        async.elapse(const Duration(seconds: 1));

        expect(video.crops.first.input, const Size(320, 256));
        expect(video.crops.skip(1).map((c) => c.input).toSet(),
            {const Size(128, 128)});
        tracker.dispose();
      });
    });

    test(
        'says "no face" within half a second of the face leaving, and '
        'anchors again when it comes back', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        const left = Duration(seconds: 2), back = Duration(seconds: 3);
        final (_, tracker, seen) =
            engine.track((t) => t >= left && t < back ? null : _face(t));

        async.elapse(const Duration(seconds: 4));

        final gone = seen.firstWhere((s) => s.$1 > left && s.$2.anchor == null);
        expect(gone.$1 - left,
            lessThanOrEqualTo(const Duration(milliseconds: 500)));
        expect(
            seen.where((s) => s.$1 > gone.$1 && s.$1 < back),
            everyElement(predicate<(Duration, FaceObservation)>(
                (s) => s.$2.anchor == null)));
        final again =
            seen.firstWhere((s) => s.$1 > back && s.$2.anchor != null);
        expect(again.$1 - back,
            lessThanOrEqualTo(const Duration(milliseconds: 500)));
        expect(
            seen.where((s) => s.$1 > again.$1),
            everyElement(predicate<(Duration, FaceObservation)>(
                (s) => s.$2.anchor != null)));
        tracker.dispose();
      });
    });

    test('a face that never comes is "no face", over and over', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final (video, tracker, seen) = engine.track((_) => null);

        async.elapse(const Duration(seconds: 1));

        expect(seen.length, greaterThanOrEqualTo(10));
        expect(seen.map((s) => s.$2.anchor), everyElement(isNull));
        expect(video.crops.map((c) => c.input).toSet(), {const Size(320, 256)});
        tracker.dispose();
      });
    });

    test('one engine serves eight videos, each at 10 to 15 frames a second',
        () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final runs = [for (var i = 0; i < 8; i++) engine.track(_face)];

        async.elapse(const Duration(seconds: 3));

        for (final (_, tracker, seen) in runs) {
          final perSecond = seen.length / 3;
          expect(perSecond, inInclusiveRange(10, 15));
          tracker.dispose();
        }
      });
    });

    test('a slow detector shares itself fairly', () {
      fakeAsync((async) {
        final engine = _Engine(async)
          ..detectTime = const Duration(milliseconds: 40);
        final runs = [for (var i = 0; i < 4; i++) engine.track(_face)];

        async.elapse(const Duration(seconds: 4));

        final counts = [for (final (_, _, seen) in runs) seen.length];
        // 25 detections a second, shared out among four.
        expect(counts.reduce((a, b) => a + b), inInclusiveRange(98, 101));
        expect(
            counts.reduce((a, b) => a > b ? a : b) -
                counts.reduce((a, b) => a < b ? a : b),
            lessThanOrEqualTo(1));
        for (final (_, tracker, _) in runs) {
          tracker.dispose();
        }
      });
    });

    test('grabs the newest frame only when it is its turn', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final (video, tracker, _) = engine.track(_face);

        async.elapse(const Duration(seconds: 1));

        expect(video.grabs, video.crops.length);
        expect(video.grabs, inInclusiveRange(14, 16));
        tracker.dispose();
      });
    });

    test('a video not on screen is not tracked, until it is', () {
      fakeAsync((async) {
        final engine = _Engine(async);
        final (video, tracker, seen) = engine.track(_face, onScreen: false);

        async.elapse(const Duration(seconds: 1));
        expect(seen, isEmpty);
        expect(video.crops, isEmpty);

        video.onScreen = true;
        async.elapse(const Duration(seconds: 1));
        expect(seen, isNotEmpty);
        tracker.dispose();
      });
    });

    test('a tracker disposed stops looking, even mid-detection', () {
      fakeAsync((async) {
        final engine = _Engine(async)
          ..detectTime = const Duration(milliseconds: 40);
        final (video, tracker, seen) = engine.track(_face);

        async.elapse(const Duration(milliseconds: 20));
        tracker.dispose();
        async.elapse(const Duration(seconds: 1));

        expect(seen, isEmpty);
        expect(video.grabs, 1);
        expect(engine.engine.trackers, 0);
      });
    });

    test('a detector that fails is reported once, and tried again', () {
      fakeAsync((async) {
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);
        final engine = _Engine(async)..fail = true;
        final (video, tracker, seen) = engine.track(_face);

        async.elapse(const Duration(seconds: 1));
        expect(errors, hasLength(1));
        expect(seen, isEmpty);

        engine.fail = false;
        async.elapse(const Duration(seconds: 1));
        expect(seen, isNotEmpty);
        expect(video.grabs, greaterThan(20));
        tracker.dispose();
      });
    });
  });
}
