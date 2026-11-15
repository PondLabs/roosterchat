// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
import 'package:rooster/client/components/face_tracking/face_anchor.dart';
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_linux.dart';
import 'package:rooster/client/components/face_tracking/face_tracker_native.dart';

class _Track extends Fake implements MediaStreamTrack {
  @override
  String? get id => 'track-1';
}

/// An engine that records what it is asked, and answers [latest].
class _Native implements FaceTrackingNative {
  _Native({this.starts = true});

  final bool starts;
  final calls = <String>[];
  NativeObservation latest = const NativeObservation(seq: 0);
  int _next = 40;

  @override
  Future<bool> start() async {
    calls.add('start');
    return starts;
  }

  @override
  int newTracker({required bool readFrameCode}) {
    calls.add('new $readFrameCode');
    return _next++;
  }

  @override
  void freeTracker(int handle) => calls.add('free $handle');

  @override
  NativeObservation poll(int handle) {
    calls.add('poll $handle');
    return latest;
  }

  @override
  Future<void> tap(String trackId, int handle) async =>
      calls.add('tap $trackId $handle');

  @override
  Future<void> untap(int handle) async => calls.add('untap $handle');
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LinuxFaceTracker.debugNative = null;
  });

  test('Linux tracks faces when its library is there, and not without it', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final native = _Native();

    LinuxFaceTracker.debugNative = () => native;
    expect(faceTrackerPlatform, same(linuxFaceTracker));
    expect(FaceTracker.isSupported, isTrue);
    expect(
        FaceTracker.start(FaceVideoSource(_Track())), isA<NativeFaceTracker>());

    LinuxFaceTracker.debugNative = () => null;
    expect(FaceTracker.isSupported, isFalse);
    expect(() => FaceTracker.start(FaceVideoSource(_Track())),
        throwsUnsupportedError);
  });

  test('a tracker starts the engine, then taps its video track', () async {
    final native = _Native();
    final tracker = NativeFaceTracker(native, FaceVideoSource(_Track()),
        readFrameCode: true);
    await tracker.ready;

    expect(native.calls, ['start', 'new true', 'tap track-1 40']);
    tracker.dispose();
  });

  test('each new observation of the engine is passed on, once', () async {
    final native = _Native();
    final tracker = NativeFaceTracker(native, FaceVideoSource(_Track()),
        readFrameCode: true);
    await tracker.ready;
    final seen = <FaceObservation?>[];
    tracker.observation.addListener(() => seen.add(tracker.observation.value));

    tracker.poll();
    expect(seen, isEmpty, reason: 'nothing analysed yet');

    native.latest = const NativeObservation(
      seq: 1,
      framesDelivered: 3,
      width: 640,
      height: 480,
      found: true,
      frameCode: 57,
      rightEye: Offset(280, 200),
      leftEye: Offset(360, 200),
    );
    tracker.poll();
    tracker.poll();
    expect(seen, hasLength(1));
    expect(tracker.framesDelivered, 3);
    final first = seen.single!;
    expect(first.videoSize, const Size(640, 480));
    expect(first.frameCode, 57);
    expect(
      first.anchor,
      FaceAnchor.fromEyes(
          rightEye: const Offset(280, 200), leftEye: const Offset(360, 200)),
    );

    native.latest =
        const NativeObservation(seq: 2, width: 640, height: 480, frameCode: 58);
    tracker.poll();
    expect(seen, hasLength(2));
    expect(seen.last!.anchor, isNull, reason: 'no face in that frame');
    expect(seen.last!.frameCode, 58);
    tracker.dispose();
  });

  test('the frame code is passed on only when asked for', () {
    const latest =
        NativeObservation(seq: 1, width: 640, height: 480, frameCode: 9);
    expect(
        NativeFaceTracker.observationOf(latest, readFrameCode: false).frameCode,
        isNull);
    expect(
        NativeFaceTracker.observationOf(latest, readFrameCode: true).frameCode,
        9);
    expect(
        NativeFaceTracker.observationOf(
                const NativeObservation(seq: 1, frameCode: -1),
                readFrameCode: true)
            .frameCode,
        isNull);
  });

  test('a tracker lets go of its track before its handle is freed', () async {
    final native = _Native();
    final tracker = NativeFaceTracker(native, FaceVideoSource(_Track()),
        readFrameCode: false);
    await tracker.ready;
    native.calls.clear();

    tracker.dispose();
    await pumpEventQueue();

    expect(native.calls, ['untap 40', 'free 40']);
    tracker.poll();
    expect(native.calls, ['untap 40', 'free 40'], reason: 'polls no more');
  });

  test('a tracker disposed while starting never taps, and frees nothing',
      () async {
    final native = _Native();
    final tracker = NativeFaceTracker(native, FaceVideoSource(_Track()),
        readFrameCode: false);
    tracker.dispose();
    await pumpEventQueue();

    expect(native.calls, ['start']);
  });

  test('when the engine cannot start, no tracker is made', () async {
    final native = _Native(starts: false);
    final tracker = NativeFaceTracker(native, FaceVideoSource(_Track()),
        readFrameCode: false);
    await tracker.ready;
    tracker.dispose();
    await pumpEventQueue();

    expect(native.calls, ['start']);
    expect(tracker.observation.value, isNull);
  });
}
