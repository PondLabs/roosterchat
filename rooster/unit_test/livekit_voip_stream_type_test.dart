import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:test/test.dart';

void main() {
  group("MatrixLivekitVoipStream.typeOf", () {
    test("microphone audio is an audio stream", () {
      expect(
          MatrixLivekitVoipStream.typeOf(
              lk.TrackType.AUDIO, lk.TrackSource.microphone),
          VoipStreamType.audio);
    });

    test("screen share audio is a screenshareAudio stream, not audio", () {
      expect(
          MatrixLivekitVoipStream.typeOf(
              lk.TrackType.AUDIO, lk.TrackSource.screenShareAudio),
          VoipStreamType.screenshareAudio);
    });

    test("screen share video is a screenshare stream", () {
      expect(
          MatrixLivekitVoipStream.typeOf(
              lk.TrackType.VIDEO, lk.TrackSource.screenShareVideo),
          VoipStreamType.screenshare);
    });

    // The DJ's music keeps Commet's wire name: a listener whose build does
    // not know the name plays the music at the DJ's voice volume, and the
    // music slider does nothing (the rename changed it for two days).
    test("the DJ booth publishes its music under Commet's name", () {
      expect(MatrixLivekitVoipStream.musicTrackName, 'commet-dj-music');
    });

    test("the DJ's music is music under either name", () {
      for (final name in ['commet-dj-music', 'rooster-dj-music']) {
        expect(
            MatrixLivekitVoipStream.typeOf(
                lk.TrackType.AUDIO, lk.TrackSource.unknown,
                name: name),
            VoipStreamType.music,
            reason: name);
      }
    });

    test("camera video is a video stream", () {
      expect(
          MatrixLivekitVoipStream.typeOf(
              lk.TrackType.VIDEO, lk.TrackSource.camera),
          VoipStreamType.video);
    });
  });
}
