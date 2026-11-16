// The join hands the session over once connected and publishes the
// microphone after, when its capture opens. A mute or unmute pressed in
// between went to LiveKit with no microphone published: an unmute opened a
// second capture, and the join then published its own beside it. The
// session's mute and deafen now wait for the join's microphone.
//
// The real MatrixLivekitVoipSession, made by MatrixLivekitBackend as the
// join makes it, over fakes of LiveKit and Matrix (as in
// voice_health/livekit_session_voice_health_test.dart): no WebSocket, no
// WebRTC.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../noise_suppression/fakes.dart';

class _Publication implements lk.LocalTrackPublication<lk.LocalAudioTrack> {
  _Publication(this.sid, this.track, this.participant);

  @override
  final lk.LocalParticipant participant;

  @override
  final String sid;

  @override
  lk.LocalAudioTrack? track;

  @override
  lk.TrackSource get source => lk.TrackSource.microphone;

  @override
  bool muted = false;

  @override
  lk.TrackType get kind => lk.TrackType.AUDIO;

  @override
  String get name => source.name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// LiveKit's local participant, as far as the microphone goes: enabling a
/// microphone with none published opens a new capture, as LiveKit does.
class _Participant implements lk.LocalParticipant {
  final List<_Publication> publications = [];

  /// Captures opened by `setMicrophoneEnabled` (not by the join).
  int capturesOpened = 0;

  @override
  String get identity => '@me:example.org:DEVICE';

  @override
  Map<String, lk.LocalTrackPublication> get trackPublications =>
      {for (final p in publications) p.sid: p};

  @override
  List<lk.LocalTrackPublication<lk.LocalAudioTrack>>
      get audioTrackPublications => publications;

  @override
  bool isCameraEnabled() => false;

  @override
  bool isScreenShareEnabled() => false;

  @override
  lk.LocalTrackPublication? getTrackPublicationBySource(
          lk.TrackSource source) =>
      publications.firstWhereOrNull((p) => p.source == source);

  @override
  Future<lk.LocalTrackPublication?> setMicrophoneEnabled(bool enabled,
      {lk.AudioCaptureOptions? audioCaptureOptions}) async {
    final mic = publications.firstOrNull;
    if (mic != null) {
      mic.muted = !enabled;
      return mic;
    }
    if (!enabled) return null;
    capturesOpened++;
    return publish(await lk.LocalAudioTrack.create(audioCaptureOptions));
  }

  /// What the join's publish does.
  _Publication publish(lk.LocalAudioTrack track) {
    final publication =
        _Publication('TR_mic_${publications.length}', track, this);
    publications.add(publication);
    return publication;
  }

  @override
  Future<void> publishData(List<int> data,
      {bool? reliable,
      List<String>? destinationIdentities,
      String? topic}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Someone else in the call, speaking into their microphone.
class _RemotePublication
    implements lk.RemoteTrackPublication<lk.RemoteAudioTrack> {
  _RemotePublication(this.participant);

  @override
  final lk.RemoteParticipant participant;

  @override
  final String sid = 'TR_bob_mic';

  @override
  final lk.TrackType kind = lk.TrackType.AUDIO;

  @override
  final lk.TrackSource source = lk.TrackSource.microphone;

  @override
  final String name = 'microphone';

  @override
  final bool muted = false;

  @override
  final bool subscribed = true;

  @override
  final lk.RemoteAudioTrack? track = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RemoteParticipant implements lk.RemoteParticipant {
  @override
  final String identity = '@bob:example.org:BOB';

  @override
  late final Map<String, lk.RemoteTrackPublication> trackPublications = {
    'TR_bob_mic': _RemotePublication(this)
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Listener implements lk.EventsListener<lk.RoomEvent> {
  @override
  Future<void> Function() on<E>(FutureOr<void> Function(E) then,
          {bool Function(E)? filter}) =>
      () async {};

  @override
  Future<bool> dispose() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements lk.Room {
  _Room(this.localParticipant);

  @override
  final lk.LocalParticipant? localParticipant;

  @override
  lk.ConnectionState connectionState = lk.ConnectionState.connected;

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView({'@bob:example.org:BOB': _RemoteParticipant()});

  @override
  lk.EventsListener<lk.RoomEvent> createListener({bool synchronized = false}) =>
      _Listener();

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> dispose() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatrixSdkClient implements matrix.Client {
  @override
  final String? deviceID = 'DEVICE';

  @override
  final String? userID = '@me:example.org';

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async =>
      matrix.GetVersionsResponse(versions: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatrixSdkRoom implements matrix.Room {
  @override
  final String id = '!room:example.org';

  @override
  final matrix.Client client = _MatrixSdkClient();

  @override
  final Map<String, Map<String, matrix.Event>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile implements Profile {
  @override
  final String identifier = '@me:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  final String identifier = '@me:example.org';

  @override
  final Profile? self = _Profile();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatrixRoom implements MatrixRoom {
  @override
  final matrix.Room matrixRoom = _MatrixSdkRoom();

  @override
  final Client client = _Client();

  @override
  final String identifier = '!room:example.org';

  @override
  final String displayName = 'Voice';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebrtcChannel webrtc;
  late _Participant participant;
  late Completer<bool> published;
  late MatrixLivekitVoipSession session;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
  });

  setUp(() {
    (webrtc = FakeWebrtcChannel()).install();
    participant = _Participant();
    published = Completer();
    // What the join hands over while the microphone is still opening, made
    // the way the join makes it.
    session = MatrixLivekitBackend(_MatrixRoom())
        .createSession(LkJoinRoom(_Room(participant)), published.future);
  });

  tearDown(() {
    session.state = VoipState.ended;
    webrtc.uninstall();
  });

  /// The join's microphone opens and is published.
  Future<void> joinPublishes() async {
    participant.publish(await lk.LocalAudioTrack.create(
        const lk.AudioCaptureOptions(noiseSuppression: true)));
    published.complete(true);
  }

  /// Bob's stream: someone else in the call.
  MatrixLivekitVoipStream others() => session.streams
      .whereType<MatrixLivekitVoipStream>()
      .singleWhere((s) => s.userId == '@bob:example.org');

  test('an unmute while the microphone opens publishes one microphone',
      () async {
    expect(session.isMicrophoneMuted, isTrue,
        reason: 'nothing is published yet, so it shows muted');

    final toggle = session.setMicrophoneMute(false);
    await pumpEventQueue();
    expect(participant.publications, isEmpty,
        reason: 'the unmute waits for the join');

    await joinPublishes();
    await toggle;

    expect(participant.publications, hasLength(1));
    expect(participant.capturesOpened, 0, reason: 'no second capture');
    expect(session.isMicrophoneMuted, isFalse);
  });

  test("a mute while the microphone opens mutes the join's microphone",
      () async {
    final toggle = session.setMicrophoneMute(true);
    await pumpEventQueue();

    await joinPublishes();
    await toggle;

    expect(participant.publications, hasLength(1));
    expect(participant.publications.single.muted, isTrue,
        reason: 'the mute is not lost to the publish after it');
  });

  test('a deafen while the microphone opens acts on it once published',
      () async {
    final deafen = session.setDeafened(true);
    await pumpEventQueue();
    expect(participant.publications, isEmpty);

    await joinPublishes();
    await deafen;

    expect(participant.publications, hasLength(1));
    expect(participant.publications.single.muted, isTrue);
    expect(participant.capturesOpened, 0);

    // The mute from before deafening is the microphone's once published
    // (open), not the "muted" shown while nothing was published yet.
    await session.setDeafened(false);
    expect(session.isDeafened, isFalse);
    expect(participant.publications.single.muted, isFalse,
        reason: 'undeafening opens the microphone the join published');
  });

  test(
      'a microphone that never opens: deafening takes at once, the mute '
      'waits for it', () async {
    expect(others().listenerDeafened, isFalse);

    var deafenDone = false;
    unawaited(session.setDeafened(true).then((_) => deafenDone = true));
    var muteDone = false;
    unawaited(session.setMicrophoneMute(true).then((_) => muteDone = true));
    await pumpEventQueue();

    expect(session.isDeafened, isTrue, reason: 'the button shows it now');
    expect(others().listenerDeafened, isTrue,
        reason: 'the others are silent now');
    expect(muteDone, isFalse, reason: 'the mute still waits');
    expect(deafenDone, isFalse);
    expect(participant.publications, isEmpty);
    expect(participant.capturesOpened, 0);

    // Undeafening while it still waits brings the others back at once.
    unawaited(session.setDeafened(false));
    await pumpEventQueue();
    expect(session.isDeafened, isFalse);
    expect(others().listenerDeafened, isFalse);

    await joinPublishes();
    await pumpEventQueue();
    expect(muteDone, isTrue, reason: 'the mute went through once it opened');
    expect(deafenDone, isTrue);
    expect(session.isDeafened, isFalse, reason: 'the last thing asked for');
    expect(participant.publications, hasLength(1));
    expect(participant.capturesOpened, 0);
  });

  test('a microphone future that fails: mute and deafen still work', () async {
    published.completeError(StateError('the publish failed'));

    await session.setMicrophoneMute(true);
    await session.setDeafened(true);
    expect(session.isDeafened, isTrue);
    await session.setDeafened(false);
    expect(session.isDeafened, isFalse);
  });

  test('a join that published nothing still lets the mute through', () async {
    published.complete(false);

    await session.setMicrophoneMute(false);

    expect(participant.capturesOpened, 1,
        reason: 'unmuting opens the microphone the join could not');
  });
}
