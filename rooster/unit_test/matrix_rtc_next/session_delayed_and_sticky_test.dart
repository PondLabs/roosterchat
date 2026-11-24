// Our membership's delayed leave (MSC4140) goes through the stable API on a
// homeserver with Matrix v1.20, the unstable one before, and each leave is
// managed on the API it was armed with: one asked for on the other API is
// not found, and nothing would take us off the list if this client died.
// Where the homeserver has sticky events (MSC4354), and only there, our
// membership also goes out in the newer format (MSC4143), beside the legacy
// one and taken down with it.
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_memberships.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../noise_suppression/fakes.dart';
import 'session_fakes.dart';

const _unstable = '/client/unstable/org.matrix.msc4140/delayed_events/';
const _stable = '/client/v1/delayed_events/';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebrtcChannel webrtc;
  late LivekitRoom livekit;
  late FakeVoiceRoom room;
  late RecordingHomeserver homeserver;
  MatrixLivekitVoipSession? session;
  late DateTime serverTime;

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
    final participant = LocalParticipant();
    participant.publications.add(LocalPublication('TR_mic', mic, participant));
    livekit = LivekitRoom(participant);
    room = FakeVoiceRoom();
    homeserver = room.matrixRoom.client;
    serverTime = DateTime(2026, 11, 23, 12);
    session = null;
    // Our membership as the join wrote it.
    room.matrixRoom.states[CallMemberships.legacyType] = {
      ownKey: matrix.Event(
        type: CallMemberships.legacyType,
        content: {
          'application': 'm.call',
          'call_id': '',
          'device_id': 'DEVICE',
          'expires': MatrixCallMembership.lifetime.inMilliseconds,
          'scope': 'm.room',
          'foci_preferred': [
            {'type': 'livekit', 'livekit_service_url': 'https://sfu.test'},
          ],
        },
        senderId: me,
        stateKey: ownKey,
        eventId: r'$join',
        originServerTs: serverTime,
        room: room.matrixRoom,
      ),
    };
  });

  tearDown(() async {
    session?.state = VoipState.ended;
    UserIdleWatcher.instance.isAway.value = false;
    webrtc.uninstall();
  });

  Future<MatrixLivekitVoipSession> join() async {
    final joined = MatrixLivekitVoipSession(room, livekit,
        // ignore: invalid_use_of_visible_for_testing_member
        now: () => serverTime,
        // ignore: invalid_use_of_visible_for_testing_member
        serverNow: () => serverTime);
    session = joined;
    // ignore: invalid_use_of_visible_for_testing_member
    await joined.debugHeartbeat();
    return joined;
  }

  Future<void> stay(Duration by) async {
    serverTime = serverTime.add(by);
    // ignore: invalid_use_of_visible_for_testing_member
    await session!.debugHeartbeat();
    await pumpEventQueue();
  }

  /// LiveKit gone for five seconds: we step out of the member list.
  Future<void> loseLivekit(MatrixLivekitVoipSession call) async {
    livekit.connectionState = lk.ConnectionState.reconnecting;
    // ignore: invalid_use_of_visible_for_testing_member
    call.debugWatchConnection();
    serverTime = serverTime.add(const Duration(seconds: 5));
    // ignore: invalid_use_of_visible_for_testing_member
    call.debugWatchConnection();
    await pumpEventQueue();
  }

  matrix.RequestType? arm() =>
      homeserver.requests.firstWhere((r) => r.path.contains('/state/')).type;

  group('the delayed leave', () {
    test('uses /_matrix/client/v1/delayed_events from Matrix v1.20', () async {
      homeserver.versions = ['v1.11', 'v1.20'];
      final call = await join();
      expect(arm(), matrix.RequestType.PUT);
      final armed =
          homeserver.requests.firstWhere((r) => r.path.contains('/state/'));
      expect(armed.query, {'delay': '15000'});
      expect(call.heartbeatDelayId, 'delay-1');

      await stay(const Duration(seconds: 5));
      await loseLivekit(call);
      final actions = homeserver.delayedActions;
      expect(actions.map((r) => r.path), [
        '${_stable}delay-1',
        '${_stable}delay-1',
      ]);
      expect(actions.map((r) => r.body['action']), ['restart', 'send']);
    });

    test('uses the unstable API before Matrix v1.20', () async {
      homeserver.versions = ['v1.11', 'v1.19'];
      homeserver.features = {'org.matrix.msc4140': true};
      final call = await join();
      final armed =
          homeserver.requests.firstWhere((r) => r.path.contains('/state/'));
      expect(armed.query, {'org.matrix.msc4140.delay': '15000'});

      await stay(const Duration(seconds: 5));
      await loseLivekit(call);
      expect(homeserver.delayedActions.map((r) => r.path),
          everyElement(startsWith(_unstable)));
      expect(homeserver.delayedActions.map((r) => r.body['action']),
          ['restart', 'send']);
    });

    test(
        'armed on the unstable API by a homeserver that says v1.20 but does '
        'not know the stable one, is restarted and sent there', () async {
      homeserver.versions = ['v1.20'];
      homeserver.features = {'org.matrix.msc4140': true};
      homeserver.stableUnknown = true;
      final call = await join();
      expect(call.heartbeatDelayId, 'delay-1',
          reason: 'the call still has a delayed leave');

      await stay(const Duration(seconds: 5));
      await loseLivekit(call);
      expect(homeserver.delayedActions.map((r) => r.path), [
        '${_unstable}delay-1',
        '${_unstable}delay-1',
      ]);
      expect(homeserver.delayedActions.last.body['action'], 'send',
          reason: 'a client that drops off still leaves the list');
    });

    test('none at all where the homeserver has none', () async {
      final call = await join();
      expect(call.heartbeatDelayId, isNull);
      expect(homeserver.delayedActions, isEmpty);
    });
  });

  group('the sticky membership', () {
    test('is not sent where the homeserver has no sticky events', () async {
      homeserver.features = {'org.matrix.msc4140': true};
      await join();
      await stay(const Duration(minutes: 1));
      expect(homeserver.stickySends, isEmpty);
    });

    test(
        'goes out beside the legacy one, sticky for two minutes, again half '
        'a minute later, and down when we leave the list', () async {
      homeserver.features = {
        'org.matrix.msc4140': true,
        'org.matrix.msc4354': true,
      };
      final call = await join();

      final first = homeserver.stickySends.single;
      expect(first.type, matrix.RequestType.PUT);
      expect(
          first.path,
          startsWith('/client/v3/rooms/${Uri.encodeComponent(voiceRoomId)}'
              '/send/org.matrix.msc4143.rtc.member/'));
      expect(first.query, {'org.matrix.msc4354.sticky_duration_ms': '120000'});
      expect(first.body, {
        'slot_id': 'm.call#',
        'application': {'type': 'm.call', 'm.call.id': ''},
        'member': {'id': 'DEVICE', 'user_id': me, 'device_id': 'DEVICE'},
        'rtc_transports': [
          {'type': 'livekit', 'livekit_service_url': 'https://sfu.test'},
        ],
        'versions': [],
        'msc4354_sticky_key': ownKey,
      });

      await stay(const Duration(seconds: 25));
      expect(homeserver.stickySends, hasLength(1), reason: 'not yet');
      await stay(const Duration(seconds: 5));
      expect(homeserver.stickySends, hasLength(2));

      await loseLivekit(call);
      expect(
          homeserver.stickySends.last.body,
          {
            'member': {'id': 'DEVICE', 'user_id': me, 'device_id': 'DEVICE'},
            'msc4354_sticky_key': ownKey,
          },
          reason: 'a leave: no application');
      // The legacy membership's leave went out as before.
      expect(homeserver.delayedActions.last.body['action'], 'send');
    });

    test('is not sent once our legacy membership is gone', () async {
      homeserver.features = {'org.matrix.msc4354': true};
      room.matrixRoom.states[CallMemberships.legacyType]!.clear();
      await join();
      expect(homeserver.stickySends, isEmpty);
    });
  });
}
