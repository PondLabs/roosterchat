// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';

class _MediaTrack extends Fake implements rtc.MediaStreamTrack {
  _MediaTrack([this.settings = const {}]);

  final Map<String, dynamic> settings;

  @override
  Map<String, dynamic> getSettings() => settings;
}

class _RemoteVideo extends Fake implements RemoteVideoTrack {
  _RemoteVideo(this.source);

  @override
  final TrackSource source;

  @override
  final rtc.MediaStreamTrack mediaStreamTrack = _MediaTrack();
}

class _LocalCamera extends Fake implements LocalVideoTrack {
  _LocalCamera(String facingMode)
      : mediaStreamTrack = _MediaTrack({'facingMode': facingMode});

  @override
  final TrackSource source = TrackSource.camera;

  @override
  final rtc.MediaStreamTrack mediaStreamTrack;
}

class _Publication extends Fake implements RemoteTrackPublication<RemoteTrack> {
  _Publication(this.kind, this.source, [this.track]);

  @override
  final String sid = 'TR_bob';

  @override
  final TrackType kind;

  @override
  final TrackSource source;

  @override
  final String name = 'camera';

  @override
  RemoteTrack? track;
}

class _LocalPublication extends Fake
    implements LocalTrackPublication<LocalTrack> {
  _LocalPublication(this.track);

  @override
  final String sid = 'TR_me';

  @override
  final TrackType kind = TrackType.VIDEO;

  @override
  final TrackSource source = TrackSource.camera;

  @override
  final String name = 'camera';

  @override
  final LocalTrack track;
}

class _Platform implements FaceTrackerPlatform {
  final started = <FaceVideoSource>[];

  @override
  bool get isSupported => true;

  @override
  FaceTracker start(FaceVideoSource source, {required bool readFrameCode}) {
    started.add(source);
    return _Tracker();
  }
}

class _Tracker extends Fake implements FaceTracker {}

void main() {
  final streams = <MatrixLivekitVoipStream>[];

  MatrixLivekitVoipStream stream(TrackPublication publication) {
    final stream = MatrixLivekitVoipStream(
      publication,
      '@bob:example.org',
      setTrackVolume: (_, __) async {},
    );
    streams.add(stream);
    return stream;
  }

  tearDown(() async {
    FaceTracker.debugPlatform = null;
    for (final stream in streams) {
      await stream.dispose();
    }
    streams.clear();
  });

  test('a tracker starts on the track of someone\'s camera', () {
    final camera = _RemoteVideo(TrackSource.camera);
    final platform = _Platform();
    FaceTracker.debugPlatform = platform;

    final VoipStream call =
        stream(_Publication(TrackType.VIDEO, TrackSource.camera, camera));
    final source = (call as FaceTrackableStream).faceVideoSource!;
    FaceTracker.start(source);

    expect(platform.started.single.track, same(camera.mediaStreamTrack));
    expect(platform.started.single.mirrored, isFalse);
  });

  test('our own front camera is followed as it is shown: mirrored', () {
    final source =
        stream(_LocalPublication(_LocalCamera('user'))).faceVideoSource!;

    expect(source.mirrored, isTrue);
  });

  test('a rear camera is not mirrored', () {
    final source =
        stream(_LocalPublication(_LocalCamera('environment'))).faceVideoSource!;

    expect(source.mirrored, isFalse);
  });

  test('a camera not subscribed yet has nothing to follow, until it is', () {
    final publication = _Publication(TrackType.VIDEO, TrackSource.camera);
    final camera = stream(publication);

    expect(camera.faceVideoSource, isNull);

    publication.track = _RemoteVideo(TrackSource.camera);
    expect(camera.faceVideoSource?.track,
        same(publication.track!.mediaStreamTrack));
  });

  test('a screen share has no face to follow', () {
    final share = _Publication(TrackType.VIDEO, TrackSource.screenShareVideo,
        _RemoteVideo(TrackSource.screenShareVideo));

    expect(stream(share).faceVideoSource, isNull);
  });

  test('a voice has no face to follow', () {
    final voice = _Publication(TrackType.AUDIO, TrackSource.microphone);

    expect(stream(voice).faceVideoSource, isNull);
  });

  test('LiveKit mirrors exactly what the stream calls mirrored', () {
    expect(shouldMirrorVideoTrack(_LocalCamera('user')), isTrue);
    expect(shouldMirrorVideoTrack(_LocalCamera('environment')), isFalse);
    expect(shouldMirrorVideoTrack(_RemoteVideo(TrackSource.camera)), isFalse);
    expect(
      shouldMirrorVideoTrack(_RemoteVideo(TrackSource.camera),
          mirrorMode: VideoViewMirrorMode.mirror),
      isTrue,
    );
    expect(
      shouldMirrorVideoTrack(_RemoteVideo(TrackSource.screenShareVideo),
          mirrorMode: VideoViewMirrorMode.mirror),
      isFalse,
    );
  });
}
