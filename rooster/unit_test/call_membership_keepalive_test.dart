// Someone who stays in a voice channel for hours has to stay listed in it.
// A call membership lapses four hours after it was last written (MatrixRTC's
// window, counted from the join), and its owner is the one who pushes that
// out. We only did so from the delayed-leave heartbeat: on a homeserver
// without delayed events, or once that heartbeat had failed to start, nobody
// did, and four hours in the member vanished from everyone's list while
// still talking. It was also pushed out only in its last hour, by this
// machine's clock, so a clock an hour behind let it lapse first.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'noise_suppression/fakes.dart';

const _me = '@me:example.org';
const _ownKey = '_${_me}_DEVICE_m.call';

class _LocalPublication
    implements lk.LocalTrackPublication<lk.LocalAudioTrack> {
  _LocalPublication(this.sid, this.track, this.participant);

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

class _LocalParticipant implements lk.LocalParticipant {
  final List<_LocalPublication> publications = [];

  @override
  String get identity => '$_me:DEVICE';

  @override
  Map<String, lk.LocalTrackPublication> get trackPublications =>
      {for (final p in publications) p.sid: p};

  @override
  List<lk.LocalTrackPublication<lk.LocalAudioTrack>>
      get audioTrackPublications => publications;

  @override
  bool get isMuted => publications.firstOrNull?.muted ?? true;

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
    if (mic == null) return null;
    mic.muted = !enabled;
    mic.track?.mediaStreamTrack.enabled = enabled;
    return mic;
  }

  @override
  Future<void> publishData(List<int> data,
      {bool? reliable,
      List<String>? destinationIdentities,
      String? topic}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Someone in the LiveKit room who publishes nothing: a microphone that
/// would not open, or none at all.
class _RemoteParticipant implements lk.RemoteParticipant {
  _RemoteParticipant(this.identity);

  @override
  final String identity;

  @override
  bool get isSpeaking => false;

  @override
  Map<String, lk.RemoteTrackPublication> get trackPublications => const {};

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

  final Map<String, lk.RemoteParticipant> remote = {};

  @override
  lk.ConnectionState connectionState = lk.ConnectionState.connected;

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView(remote);

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

/// The homeserver, as far as our membership goes.
class _SdkClient implements matrix.Client {
  @override
  final String? deviceID = 'DEVICE';

  @override
  final String? userID = _me;

  /// Whether the homeserver has delayed events (MSC4140). Synapse ships
  /// without them.
  bool delayedEvents = false;

  /// How many of the next requests for the homeserver's versions fail.
  int versionsFailures = 0;
  int versionsAsked = 0;

  /// How many of the next delayed leaves fail to be scheduled.
  int armFailures = 0;

  /// Says it has delayed events, then refuses them, as matrix.org did from
  /// 2026-10-07 to clients that read /versions before.
  bool refusesDelayedEvents = false;
  int armAttempts = 0;

  /// How many of the next restarts of the delayed leave are lost, and how
  /// many were asked for.
  int restartsLost = 0;
  int restarts = 0;

  /// How many delayed leaves were sent rather than left to fire.
  int delayedLeavesSent = 0;

  /// Our membership as written, write by write.
  final List<Map<String, Object?>> membershipWrites = [];

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async {
    versionsAsked++;
    if (versionsFailures > 0) {
      versionsFailures--;
      throw Exception('offline');
    }
    return matrix.GetVersionsResponse(
        versions: const ['v1.11'],
        unstableFeatures: {if (delayedEvents) 'org.matrix.msc4140': true});
  }

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    expect(eventType, MatrixVoipRoomComponent.callMemberStateEvent);
    expect(stateKey, _ownKey);
    membershipWrites.add(body);
    return '\$written${membershipWrites.length}';
  }

  @override
  Future<Map<String, Object?>> request(matrix.RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) async {
    if (query?.containsKey('org.matrix.msc4140.delay') == true) {
      armAttempts++;
      if (refusesDelayedEvents) {
        throw matrix.MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Sending delayed events has been disallowed',
        });
      }
      if (armFailures > 0) {
        armFailures--;
        throw Exception('M_LIMIT_EXCEEDED');
      }
      return {'delay_id': 'delay-$armAttempts'};
    }
    if (data is String && data.contains('"send"')) delayedLeavesSent++;
    // Restarting, sending or cancelling a delayed leave.
    if (data is String && data.contains('restart')) {
      restarts++;
      if (restartsLost > 0) {
        restartsLost--;
        // Sent down a connection that died: no answer ever comes.
        return Completer<Map<String, Object?>>().future;
      }
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  @override
  final String id = '!room:example.org';

  @override
  final _SdkClient client = _SdkClient();

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile implements Profile {
  @override
  final String identifier = _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  final String identifier = _me;

  @override
  final Profile? self = _Profile();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatrixRoom implements MatrixRoom {
  @override
  final _SdkRoom matrixRoom = _SdkRoom();

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
  late _Room livekit;
  late _MatrixRoom room;
  late _SdkClient homeserver;
  MatrixLivekitVoipSession? session;

  // The homeserver's clock, which memberships lapse by, and this machine's.
  late DateTime serverTime;
  late DateTime localTime;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
  });

  setUp(() async {
    (webrtc = FakeWebrtcChannel()).install();
    final (mic, _) = await publishedMicrophone(
        const lk.AudioCaptureOptions(noiseSuppression: true));
    final participant = _LocalParticipant();
    participant.publications.add(_LocalPublication('TR_mic', mic, participant));
    livekit = _Room(participant);
    room = _MatrixRoom();
    homeserver = room.matrixRoom.client;
    serverTime = DateTime(2026, 9, 26, 12);
    // Three hours behind: going by it, every window was written three hours
    // short, and pushed out two hours after it had closed for everyone.
    localTime = serverTime.subtract(const Duration(hours: 3));
    session = null;
  });

  tearDown(() async {
    session?.state = VoipState.ended;
    UserIdleWatcher.instance.isAway.value = false;
    webrtc.uninstall();
  });

  /// Our membership as the join wrote it, [at] by the homeserver's clock.
  void joined(DateTime at) {
    room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
      _ownKey: matrix.Event(
        type: MatrixVoipRoomComponent.callMemberStateEvent,
        content: {
          'application': 'm.call',
          'call_id': '',
          'device_id': 'DEVICE',
          'expires': MatrixCallMembership.lifetime.inMilliseconds,
          'scope': 'm.room',
          'chat.commet.streams': <String>[],
        },
        senderId: _me,
        stateKey: _ownKey,
        eventId: r'$join',
        originServerTs: at,
        room: room.matrixRoom,
      ),
    };
  }

  /// Joins, then lets the initial heartbeat and state debounce settle before
  /// tests advance the simulated membership clocks by minutes or hours.
  Future<MatrixLivekitVoipSession> join() async {
    final joinedSession = MatrixLivekitVoipSession(room, livekit,
        // ignore: invalid_use_of_visible_for_testing_member
        now: () => localTime,
        // ignore: invalid_use_of_visible_for_testing_member
        serverNow: () => serverTime);
    session = joinedSession;
    // ignore: invalid_use_of_visible_for_testing_member
    await joinedSession.debugHeartbeat();
    await Future<void>.delayed(const Duration(seconds: 1));
    return joinedSession;
  }

  /// [by] of call, on both clocks, then a heartbeat.
  Future<void> stay(Duration by) async {
    serverTime = serverTime.add(by);
    localTime = localTime.add(by);
    // ignore: invalid_use_of_visible_for_testing_member
    await session!.debugHeartbeat();
    await pumpEventQueue();
  }

  DateTime? expiryOf(Map<String, Object?> written) =>
      MatrixCallMembership.expiresAt(written, serverTime);

  /// The homeserver sends our last write back over sync.
  void synced() {
    room.matrixRoom
            .states[MatrixVoipRoomComponent.callMemberStateEvent]![_ownKey] =
        matrix.Event(
      type: MatrixVoipRoomComponent.callMemberStateEvent,
      content: homeserver.membershipWrites.last,
      senderId: _me,
      stateKey: _ownKey,
      eventId: '\$written${homeserver.membershipWrites.length}',
      originServerTs: serverTime,
      room: room.matrixRoom,
    );
  }

  /// Long enough for the publisher's debounce and the gap it keeps between
  /// two writes (the rate limit is shared with messages).
  Future<void> settle() => Future<void>.delayed(const Duration(seconds: 3));

  group('on a homeserver without delayed events', () {
    test('deafening and undeafening publish the current voice state', () async {
      joined(serverTime);
      final call = await join();

      await call.setDeafened(true);
      // The join's heartbeat has just written: the publisher's rate limit.
      await Future<void>.delayed(const Duration(milliseconds: 2100));

      expect(call.isDeafened, isTrue);
      expect(
          MatrixCallMembership.voiceStateOf(homeserver.membershipWrites.last),
          {VoiceState.muted, VoiceState.deafened});
      expect(
          homeserver.membershipWrites.last[MatrixCallMembership.unguardedKey],
          isTrue);

      await call.setDeafened(false);
      // The second write respects the publisher's rate limit.
      await Future<void>.delayed(const Duration(milliseconds: 2100));

      expect(call.isDeafened, isFalse);
      expect(call.isMicrophoneMuted, isFalse);
      expect(
          MatrixCallMembership.voiceStateOf(homeserver.membershipWrites.last),
          isEmpty);
    });

    test('joining without a microphone publishes the initial mute', () async {
      joined(serverTime);
      (livekit.localParticipant! as _LocalParticipant).publications.clear();
      final call = await join();

      expect(call.isMicrophoneMuted, isTrue);
      // No track event or user toggle follows a denied microphone.
      expect(homeserver.membershipWrites, isNotEmpty,
          reason: 'people outside the call must see the initial mute');
      final write = homeserver.membershipWrites.single;
      expect(MatrixCallMembership.voiceStateOf(write), {VoiceState.muted});
      expect(write[MatrixCallMembership.unguardedKey], isTrue);
    });

    // Nothing clears it if we die: a window of hours kept someone whose
    // client had died listed for hours (matrix.org, 2026-10-07).
    test('the window the join wrote is cut to two minutes right away',
        () async {
      final joinedAt = serverTime;
      joined(joinedAt);
      await join();

      final write = homeserver.membershipWrites.single;
      expect(write['application'], 'm.call');
      expect(write['created_ts'], joinedAt.millisecondsSinceEpoch,
          reason: 'still the same join, to everyone reading it');
      expect(expiryOf(write),
          serverTime.add(MatrixCallMembership.unguardedLifetime));
    });

    test('and written again half a minute after each write', () async {
      final joinedAt = serverTime;
      joined(joinedAt);
      await join();
      synced();
      await settle();

      await stay(const Duration(seconds: 25));
      expect(homeserver.membershipWrites, hasLength(1),
          reason: 'more than ninety seconds of it are left');

      await stay(const Duration(seconds: 10));
      await settle();
      expect(homeserver.membershipWrites, hasLength(2));
      final second = homeserver.membershipWrites.last;
      expect(second['created_ts'], joinedAt.millisecondsSinceEpoch);
      expect(expiryOf(second),
          serverTime.add(MatrixCallMembership.unguardedLifetime));
    });

    // Away was only published with the delayed leave armed: here someone
    // away read as present (green) to everyone else in the channel.
    test('going away is published all the same', () async {
      joined(serverTime);
      await join();
      synced();
      UserIdleWatcher.instance.isAway.value = true;
      await stay(const Duration(seconds: 5));
      await settle();

      expect(homeserver.membershipWrites.map(MatrixCallMembership.isAway),
          contains(true));
    });

    // A mute, a stream and the DJ booth were too: with no delayed events
    // nobody outside the call ever saw who was muted or live in it.
    test('a mute is published all the same, and says nothing guards it',
        () async {
      joined(serverTime);
      await join();
      (livekit.localParticipant! as _LocalParticipant)
          .publications
          .single
          .muted = true;
      synced();
      // Any change to what we advertise writes all of it.
      UserIdleWatcher.instance.isAway.value = true;
      await stay(const Duration(seconds: 5));
      await settle();

      final write = homeserver.membershipWrites.last;
      expect(MatrixCallMembership.voiceStateOf(write), {VoiceState.muted});
      expect(write[MatrixCallMembership.unguardedKey], isTrue,
          reason: 'readers drop it once it stops being written');
    });

    test('with nothing to leave behind, it is not called unguarded', () async {
      joined(serverTime);
      await join();
      UserIdleWatcher.instance.isAway.value = true;
      await stay(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 1));

      final write = homeserver.membershipWrites.last;
      expect(MatrixCallMembership.voiceStateOf(write), isEmpty);
      expect(write[MatrixCallMembership.unguardedKey], isFalse);
    });

    test("the homeserver's time lagging behind ours does not cut it short",
        () async {
      // Just woken from a sleep, before a sync has said what time it is:
      // what we know of the homeserver's time lags behind.
      localTime = serverTime.add(const Duration(minutes: 61));
      joined(serverTime);
      await join();

      expect(expiryOf(homeserver.membershipWrites.single),
          localTime.add(MatrixCallMembership.unguardedLifetime));
    });

    test("this machine's clock being set back does not hold it up", () async {
      joined(serverTime);
      await join();
      synced();
      await settle();

      // Someone fixed a clock that ran three hours ahead.
      serverTime = serverTime.add(const Duration(seconds: 35));
      localTime = localTime.subtract(const Duration(hours: 3));
      // ignore: invalid_use_of_visible_for_testing_member
      await session!.debugHeartbeat();
      await settle();

      expect(homeserver.membershipWrites, hasLength(2));
      expect(expiryOf(homeserver.membershipWrites.last),
          serverTime.add(MatrixCallMembership.unguardedLifetime));
    });

    test(
        'LiveKit gone for 5 s clears our membership by hand, and it goes back '
        'up as soon as LiveKit is back', () async {
      joined(serverTime);
      final call = await join();
      synced();
      await settle();
      final writes = homeserver.membershipWrites.length;

      livekit.connectionState = lk.ConnectionState.reconnecting;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      localTime = localTime.add(const Duration(seconds: 5));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.membershipWrites, hasLength(writes + 1));
      expect(homeserver.membershipWrites.last, isEmpty, reason: 'cleared');

      // Nothing keeps it up while we are out of the call.
      await stay(const Duration(minutes: 1));
      expect(homeserver.membershipWrites, hasLength(writes + 1));

      livekit.connectionState = lk.ConnectionState.connected;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.membershipWrites, hasLength(writes + 2));
      final back = homeserver.membershipWrites.last;
      expect(back['application'], 'm.call');
      expect(expiryOf(back),
          serverTime.add(MatrixCallMembership.unguardedLifetime));
    });

    test('nothing asks the homeserver about delayed events again and again',
        () async {
      joined(serverTime);
      await join();
      for (var i = 0; i < 6; i++) {
        await stay(const Duration(seconds: 10));
      }

      expect(homeserver.versionsAsked, 1);
      expect(homeserver.armAttempts, 0);
    });
  });

  group('delayed events advertised, then refused', () {
    setUp(() {
      homeserver.delayedEvents = true;
      homeserver.refusesDelayedEvents = true;
    });

    test('is asked once, and the window is cut short as without them',
        () async {
      final joinedAt = serverTime;
      joined(joinedAt);
      final call = await join();
      for (var i = 0; i < 12; i++) {
        await stay(const Duration(seconds: 10));
      }

      expect(homeserver.armAttempts, 1);
      expect(call.heartbeatDelayId, isNull);
      expect(expiryOf(homeserver.membershipWrites.first),
          joinedAt.add(MatrixCallMembership.unguardedLifetime));
    });

    // Regression (2026-10-07): with no delayed leave, a membership kept a
    // window of hours, and people stayed listed for hours after their app
    // had died. Judged here as every reader judges it (the sidebar, the
    // channel's page, the online dot): by its `expires`.
    test(
        'someone in the call stays listed between writes, and is gone two '
        'minutes after their app dies, not hours', () async {
      joined(serverTime);
      await join();
      synced();
      await settle();

      for (var i = 0; i < 4; i++) {
        final writes = homeserver.membershipWrites.length;
        await stay(const Duration(seconds: 31));
        await settle();
        expect(homeserver.membershipWrites, hasLength(writes + 1),
            reason: 'written again half a minute after the last write');
        synced();
        // Until the next write is due, with room for one that is late.
        expect(
            MatrixCallMembership.isExpired(homeserver.membershipWrites.last,
                serverTime, serverTime.add(const Duration(seconds: 90))),
            isFalse,
            reason: 'still in the call: listed');
      }

      // The app dies here: what it wrote last is all anyone has.
      final last = homeserver.membershipWrites.last;
      final diedAt = serverTime;
      expect(
          MatrixCallMembership.isExpired(
              last, diedAt, diedAt.add(const Duration(minutes: 1))),
          isFalse);
      expect(
          MatrixCallMembership.isExpired(
              last, diedAt, diedAt.add(const Duration(minutes: 2, seconds: 1))),
          isTrue,
          reason: 'listed for hours after it died (2026-10-07)');
    });

    // Regression (2026-10-05, 2026-10-07): an app that lost LiveKit but kept
    // running kept its membership up, so it was listed in a call it was not
    // in, for hours (ggflores23, then Enzo in a browser tab).
    test(
        'an app that lost LiveKit but keeps running takes itself off the list '
        'within seconds, and stays off', () async {
      joined(serverTime);
      final call = await join();
      synced();
      await settle();
      final writes = homeserver.membershipWrites.length;

      livekit.connectionState = lk.ConnectionState.reconnecting;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      localTime = localTime.add(const Duration(seconds: 5));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.membershipWrites, hasLength(writes + 1));
      expect(homeserver.membershipWrites.last, isEmpty,
          reason: 'off the list five seconds after LiveKit went');

      // Minutes on with LiveKit still gone (the call is hung up after three):
      // nothing puts the membership back.
      for (var i = 0; i < 20; i++) {
        await stay(const Duration(seconds: 30));
      }
      await settle();
      expect(homeserver.membershipWrites.skip(writes), everyElement(isEmpty));
    });
  });

  group('with delayed events', () {
    setUp(() => homeserver.delayedEvents = true);

    test('our membership is pushed out an hour after it was written, too',
        () async {
      joined(serverTime.subtract(const Duration(minutes: 59)));
      await join();
      expect(session!.heartbeatDelayId, isNotNull);

      await stay(const Duration(minutes: 2));
      // Arming the delayed leave published what we advertise, which waits
      // a moment to settle; the push out goes with it.
      await Future<void>.delayed(const Duration(seconds: 1));

      final write = homeserver.membershipWrites.single;
      expect(expiryOf(write), serverTime.add(MatrixCallMembership.lifetime));
    });

    test('a mute goes out guarded by the delayed leave', () async {
      joined(serverTime);
      await join();
      expect(session!.heartbeatDelayId, isNotNull);
      (livekit.localParticipant! as _LocalParticipant)
          .publications
          .single
          .muted = true;
      UserIdleWatcher.instance.isAway.value = true;
      await stay(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 1));

      final write = homeserver.membershipWrites.last;
      expect(MatrixCallMembership.voiceStateOf(write), {VoiceState.muted});
      expect(write[MatrixCallMembership.unguardedKey], isFalse);
    });

    test('pushing it out keeps saying we are away', () async {
      UserIdleWatcher.instance.isAway.value = true;
      joined(serverTime.subtract(const Duration(hours: 1, minutes: 1)));
      await join();
      await Future<void>.delayed(const Duration(seconds: 1));

      final write = homeserver.membershipWrites.single;
      expect(MatrixCallMembership.isAway(write), isTrue);
      expect(expiryOf(write), serverTime.add(MatrixCallMembership.lifetime));
    });

    test('a delayed leave that could not be scheduled is tried again',
        () async {
      homeserver.armFailures = 1;
      joined(serverTime);
      await join();
      expect(session!.heartbeatDelayId, isNull);

      await stay(const Duration(seconds: 10));
      expect(homeserver.armAttempts, 1, reason: 'not straight away');

      await stay(const Duration(seconds: 30));
      expect(homeserver.armAttempts, 2);
      expect(session!.heartbeatDelayId, isNotNull);
    });

    test('one that keeps failing is tried less and less often', () async {
      homeserver.armFailures = 3;
      joined(serverTime);
      await join();
      await stay(const Duration(seconds: 30));
      expect(homeserver.armAttempts, 2);

      await stay(const Duration(seconds: 30));
      expect(homeserver.armAttempts, 2, reason: 'a minute after the second');
      await stay(const Duration(seconds: 30));
      expect(homeserver.armAttempts, 3);

      await stay(const Duration(minutes: 1, seconds: 50));
      expect(homeserver.armAttempts, 3, reason: 'two minutes after the third');
      await stay(const Duration(seconds: 10));
      expect(homeserver.armAttempts, 4);
      expect(session!.heartbeatDelayId, isNotNull);
    });

    test('a restart that was lost does not hold up the next heartbeat',
        () async {
      // ignore: invalid_use_of_visible_for_testing_member
      final timeout = MatrixLivekitVoipSession.restartTimeout;
      // ignore: invalid_use_of_visible_for_testing_member
      MatrixLivekitVoipSession.restartTimeout =
          const Duration(milliseconds: 100);
      // ignore: invalid_use_of_visible_for_testing_member
      addTearDown(() => MatrixLivekitVoipSession.restartTimeout = timeout);

      joined(serverTime);
      await join();
      expect(session!.heartbeatDelayId, isNotNull);

      // The next heartbeat's restart goes down a connection that died with
      // the network. It used to be waited for until the HTTP client gave up
      // (35 s), every heartbeat behind it skipped, and the delayed leave
      // (30 s) took our membership down while we were still in the call.
      homeserver.restartsLost = 1;
      // ignore: invalid_use_of_visible_for_testing_member
      unawaited(session!.debugHeartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Ten seconds on, the next one restarts it, well inside the 30 s.
      await stay(const Duration(seconds: 10))
          .timeout(const Duration(seconds: 2));
      expect(homeserver.restarts, 2);
      expect(session!.heartbeatDelayId, isNotNull);
    });

    test(
        'LiveKit gone for 5 s takes our membership down, and it goes back up '
        'as soon as LiveKit is back', () async {
      joined(serverTime.subtract(const Duration(minutes: 1)));
      final call = await join();
      expect(call.heartbeatDelayId, isNotNull);

      livekit.connectionState = lk.ConnectionState.reconnecting;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      localTime = localTime.add(const Duration(seconds: 4));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.delayedLeavesSent, 0, reason: 'a blip');

      localTime = localTime.add(const Duration(seconds: 1));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.delayedLeavesSent, 1);

      // The homeserver cleared it; nothing keeps it up or puts it back
      // while we are out of the call.
      room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
        _ownKey: matrix.Event(
          type: MatrixVoipRoomComponent.callMemberStateEvent,
          content: const {},
          senderId: _me,
          stateKey: _ownKey,
          eventId: r'$left',
          originServerTs: serverTime,
          room: room.matrixRoom,
        ),
      };
      final restarts = homeserver.restarts;
      final writes = homeserver.membershipWrites.length;
      await stay(const Duration(seconds: 20));
      expect(homeserver.restarts, restarts);
      expect(homeserver.membershipWrites, hasLength(writes));

      livekit.connectionState = lk.ConnectionState.connected;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(homeserver.armAttempts, 2, reason: 'a new delayed leave');
      expect(homeserver.membershipWrites, hasLength(writes + 1));
      expect(homeserver.membershipWrites.last['application'], 'm.call');
    });

    test('a homeserver that could not be asked is asked again', () async {
      homeserver.versionsFailures = 1;
      joined(serverTime);
      await join();
      expect(session!.heartbeatDelayId, isNull);

      await stay(const Duration(seconds: 40));
      expect(homeserver.versionsAsked, 2);
      expect(session!.heartbeatDelayId, isNotNull);
    });
  });

  group('who is connected', () {
    test('everyone in the LiveKit room, publishing or not', () async {
      livekit.remote['@bob:example.org:BOB'] =
          _RemoteParticipant('@bob:example.org:BOB');
      joined(serverTime);
      final call = await join();

      expect(call.connectedUserIds, {_me, '@bob:example.org'});
    });

    test('someone connecting or leaving is a change to the call', () async {
      joined(serverTime);
      final call = await join();
      final changes = <void>[];
      final sub = call.onStateChanged.listen(changes.add);
      addTearDown(sub.cancel);

      final bob = _RemoteParticipant('@bob:example.org:BOB');
      livekit.remote[bob.identity] = bob;
      call.onParticipantConnected(
          lk.ParticipantConnectedEvent(participant: bob));
      await pumpEventQueue();
      expect(changes, hasLength(1));
      expect(call.connectedUserIds, contains('@bob:example.org'));

      livekit.remote.remove(bob.identity);
      call.onParticipantDisconnected(
          lk.ParticipantDisconnectedEvent(participant: bob));
      await pumpEventQueue();
      expect(changes, hasLength(2));
      expect(call.connectedUserIds, {_me});
    });

    test('nobody, once the call has ended', () async {
      joined(serverTime);
      final call = await join();
      call.state = VoipState.ended;

      expect(call.connectedUserIds, isEmpty);
    });

    test('is everyone in the call once connected for 30 s, and says so',
        () async {
      joined(serverTime);
      final call = await join();
      final changes = <void>[];
      final sub = call.onStateChanged.listen(changes.add);
      addTearDown(sub.cancel);

      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      localTime = localTime.add(const Duration(seconds: 29));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      expect(call.rosterComplete, isFalse);

      localTime = localTime.add(const Duration(seconds: 1));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(call.rosterComplete, isTrue);
      expect(changes, hasLength(1), reason: 'the sidebar looks again');

      livekit.connectionState = lk.ConnectionState.reconnecting;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      expect(call.rosterComplete, isFalse);
    });
  });

  group('lost connection', () {
    test('a call LiveKit gave up on without saying so is hung up', () async {
      joined(serverTime);
      final call = await join();

      livekit.connectionState = lk.ConnectionState.reconnecting;
      localTime = localTime.add(const Duration(minutes: 2, seconds: 59));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();
      expect(call.state, isNot(VoipState.ended),
          reason: 'LiveKit may still be reconnecting');

      localTime = localTime.add(const Duration(seconds: 1));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue(times: 100);
      expect(call.state, VoipState.ended);
    });

    test('reconnecting in time keeps the call', () async {
      joined(serverTime);
      final call = await join();

      livekit.connectionState = lk.ConnectionState.reconnecting;
      localTime = localTime.add(const Duration(minutes: 2));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      livekit.connectionState = lk.ConnectionState.connected;
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      livekit.connectionState = lk.ConnectionState.reconnecting;
      localTime = localTime.add(const Duration(minutes: 2));
      // ignore: invalid_use_of_visible_for_testing_member
      call.debugWatchConnection();
      await pumpEventQueue();

      expect(call.state, isNot(VoipState.ended));
    });
  });
}
