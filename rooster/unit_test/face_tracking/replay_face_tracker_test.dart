// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/face_tracking/face_tracking_log.dart';
import 'package:rooster/client/components/face_tracking/replay_face_tracker.dart';

void main() {
  // Three frames of a 640x480 video: a face, no face, the face further right.
  final reference = FaceReference.fromJson(jsonDecode('''
    {"video": "clip.mp4", "width": 640, "height": 480, "fps": 30, "frames": [
      {"code": 0, "face": {"rightEye": [0.4375, 0.5], "leftEye": [0.5625, 0.5],
                           "forehead": [0.5, 0.4], "yaw": 0, "inFrame": true}},
      {"code": 1, "face": null},
      {"code": 2, "face": {"rightEye": [0.5375, 0.5], "leftEye": [0.6625, 0.5],
                           "forehead": [0.6, 0.4], "yaw": 0, "inFrame": true}}
    ]}
  '''));

  test('the reference is read in pixels of the video', () {
    expect(reference.videoSize, const Size(640, 480));
    expect(reference.fps, 30);
    expect(reference.frames[0]!.rightEye, const Offset(280, 240));
    expect(reference.frames[0]!.forehead, const Offset(320, 192));
    expect(reference.frames[1], isNull);
  });

  test('the replayed anchor is the reference forehead, sized by the eyes', () {
    final anchor = reference.anchorAt(0)!;

    expect(anchor.center, const Offset(320, 192));
    expect(anchor.width, closeTo(2.2 * 80, 1e-9));
    expect(anchor.angle, closeTo(0, 1e-9));
    expect(reference.anchorAt(1), isNull);
    expect(reference.anchorAt(3)!.center, anchor.center, reason: 'it loops');
  });

  test('a shift moves the anchor along the line of the eyes', () {
    expect(reference.anchorAt(0, shift: 0.5)!.center, const Offset(360, 192));
  });

  test('the replay tracker reports the frame on screen', () {
    int? onScreen;
    final tracker = ReplayFaceTracker(reference, () => onScreen);
    addTearDown(tracker.dispose);

    tracker.tick();
    expect(tracker.observation.value, isNull, reason: 'no frame on screen yet');

    onScreen = 2;
    tracker.tick();
    expect(tracker.observation.value!.frameCode, 2);
    expect(tracker.observation.value!.videoSize, const Size(640, 480));
    expect(tracker.observation.value!.anchor!.center, const Offset(384, 192));

    onScreen = 1;
    tracker.tick();
    expect(tracker.observation.value!.frameCode, 1);
    expect(tracker.observation.value!.anchor, isNull, reason: 'no face');
  });

  test('the replay tracker looks again on its own, until disposed', () async {
    var looks = 0;
    final tracker = ReplayFaceTracker(
      reference,
      () => looks++,
      every: const Duration(milliseconds: 5),
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(looks, greaterThan(2));
    expect(tracker.observation.value, isNotNull);

    tracker.dispose();
    final atDispose = looks;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(looks, atDispose);
  });

  group('the log of a run', () {
    test('has an anchor as fractions of the video, by frame code', () {
      final log = FaceTrackingLog()
        ..anchor(
          'clip',
          FaceObservation(
            videoSize: reference.videoSize,
            anchor: reference.anchorAt(0),
            frameCode: 0,
          ),
        )
        ..anchor(
          'clip',
          FaceObservation(videoSize: reference.videoSize, frameCode: 1),
          tile: 3,
        )
        ..frame();

      final lines = const LineSplitter()
          .convert(log.toJsonLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

      expect(lines, hasLength(3));
      expect(lines[0], containsPair('type', 'anchor'));
      expect(lines[0], containsPair('video', 'clip'));
      expect(lines[0], containsPair('tile', 0));
      expect(lines[0], containsPair('code', 0));
      expect(lines[0]['face']['x'], closeTo(0.5, 1e-9));
      expect(lines[0]['face']['y'], closeTo(0.4, 1e-9));
      expect(lines[0]['face']['width'], closeTo(2.2 * 80 / 640, 1e-9));
      expect(lines[0]['face']['angle'], closeTo(0, 1e-9));
      expect(lines[1], containsPair('code', 1));
      expect(lines[1], containsPair('tile', 3));
      expect(lines[1], containsPair('face', null));
      expect(lines[2], containsPair('type', 'frame'));
      expect(lines[2]['t'], greaterThanOrEqualTo(lines[0]['t'] as num));
    });

    test('leaves out a frame without a frame code', () {
      final log = FaceTrackingLog()
        ..anchor('clip', FaceObservation(videoSize: reference.videoSize));

      expect(log.toJsonLines(), isEmpty);
    });
  });
}
