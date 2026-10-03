// The PWA on a phone: the people in a voice channel came out on the media
// volume while the volume keys moved the call volume, so nothing made them
// louder or quieter. Chrome on Android goes into its call mode when the
// microphone opens and leaves what was already playing where it was, and
// joining opened the microphone last. In a phone's browser it is opened
// before the room is connected.
import 'dart:async';

import 'package:rooster/client/matrix/components/voip_room/livekit_microphone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'noise_suppression/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebrtcChannel webrtc;

  setUp(() => (webrtc = FakeWebrtcChannel()).install());
  tearDown(() => webrtc.uninstall());

  Future<lk.AudioCaptureOptions> options() async =>
      const lk.AudioCaptureOptions(noiseSuppression: true);

  test("in a phone's browser the microphone is open before the room connects",
      () async {
    final early =
        await openMicrophoneBeforePlayback(needed: true, options: options);

    expect(webrtc.getUserMediaCalls, hasLength(1));
    expect(early.track, isNotNull);
    expect(early.retry, isFalse, reason: 'the room publishes this one');
  });

  test('everywhere else the room opens it once connected, as it always did',
      () async {
    final early =
        await openMicrophoneBeforePlayback(needed: false, options: options);

    expect(webrtc.getUserMediaCalls, isEmpty);
    expect(early.track, isNull);
    expect(early.retry, isTrue);
  });

  test('one that cannot be opened is not asked for a second time', () async {
    webrtc.failGetUserMedia = 1;

    final early =
        await openMicrophoneBeforePlayback(needed: true, options: options);

    expect(early.track, isNull);
    expect(early.retry, isFalse,
        reason: 'the prompt was just closed: unmuting asks again');
  });

  test('a prompt nobody answers does not keep the user out of the call',
      () async {
    final answered = Completer<void>();
    webrtc.onGetUserMedia = () => answered.future;

    final early = await openMicrophoneBeforePlayback(
        needed: true,
        options: options,
        limit: const Duration(milliseconds: 20));

    expect(early.track, isNull);
    expect(early.retry, isTrue, reason: 'the room opens its own');

    // Answered after all: that capture has no use any more.
    answered.complete();
    await pumpEventQueue();
    expect(webrtc.stoppedTracks, contains('mic-1'));
  });
}
