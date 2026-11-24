// Review c2-1: a heartbeat whose restart of the delayed leave is lost and
// whose sticky send (due every 30 s) is lost too takes restartTimeout +
// stickyTimeout = 8 s, longer than the 5 s heartbeat interval. The tick
// that falls inside it is swallowed (_beat returns the beat in flight), so
// the delayed leave is next restarted 10 s after the lost one: 15 s after
// the last restart that arrived, the whole delayed leave window. Without
// the sticky send in the beat, the next restart goes out 5 s later.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

/// Records when each request was made; restarts and sticky sends made in
/// [lostWindow] never get an answer.
class _Homeserver extends RecordingHomeserver {
  _Homeserver(this.elapsed);
  final Duration Function() elapsed;
  final List<(Duration, String)> log = [];
  bool Function(Duration at)? lostWindow;

  @override
  Future<Map<String, Object?>> request(matrix.RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) {
    final at = elapsed();
    final kind = action.contains('/send/')
        ? 'sticky'
        : action.contains('delayed_events')
            ? 'restart'
            : 'other';
    log.add((at, kind));
    if (kind != 'other' && (lostWindow?.call(at) ?? false)) {
      requests.add((type: type, path: action, query: query, body: const {}));
      return Completer<Map<String, Object?>>().future;
    }
    return super.request(type, action,
        data: data, contentType: contentType, query: query);
  }
}

class _SdkRoom extends FakeSdkRoom {
  _SdkRoom(this.client);
  @override
  final _Homeserver client;
}

class _VoiceRoom extends FakeVoiceRoom {
  _VoiceRoom(this.matrixRoom);
  @override
  final _SdkRoom matrixRoom;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
  });

  for (final sticky in [false, true]) {
    test(
        'c2-1 sticky ${sticky ? "on" : "off"}: after a lost restart the '
        'next one goes out 5 s later', () async {
      final webrtc = FakeWebrtcChannel()..install();
      addTearDown(webrtc.uninstall);
      final (mic, _) = await publishedMicrophone(
          const lk.AudioCaptureOptions(noiseSuppression: true));
      final participant = LocalParticipant();
      participant.publications
          .add(LocalPublication('TR_mic', mic, participant));
      final livekit = LivekitRoom(participant);

      fakeAsync((async) {
        final start = DateTime(2026, 11, 23, 12);
        final homeserver = _Homeserver(() => async.elapsed);
        homeserver.features = {
          'org.matrix.msc4140': true,
          if (sticky) 'org.matrix.msc4354': true,
        };
        final room = _VoiceRoom(_SdkRoom(homeserver));
        room.matrixRoom.states[CallMemberships.legacyType] = {
          ownKey: matrix.Event(
            type: CallMemberships.legacyType,
            content: {
              'application': 'm.call',
              'call_id': '',
              'device_id': 'DEVICE',
              'expires': MatrixCallMembership.lifetime.inMilliseconds,
              'scope': 'm.room',
              'foci_preferred': [],
            },
            senderId: me,
            stateKey: ownKey,
            eventId: r'$join',
            originServerTs: start,
            room: room.matrixRoom,
          ),
        };
        final session = MatrixLivekitVoipSession(room, livekit,
            // ignore: invalid_use_of_visible_for_testing_member
            now: () => start.add(async.elapsed),
            // ignore: invalid_use_of_visible_for_testing_member
            serverNow: () => start.add(async.elapsed));
        // The heartbeat at 30 s (when the sticky one is due again) loses, for
        // the five seconds of a flaky network, both of its requests.
        homeserver.lostWindow = (at) =>
            at >= const Duration(seconds: 30) &&
            at < const Duration(seconds: 35);
        unawaited(session.startHeartbeat());
        async.elapse(const Duration(seconds: 45));

        final restarts = [
          for (final (at, kind) in homeserver.log)
            if (kind == 'restart') at.inSeconds
        ];
        // ignore: avoid_print
        print('sticky=$sticky restarts at $restarts, log ${homeserver.log}');
        final lost = restarts.indexOf(30);
        expect(lost, isNot(-1));
        expect(restarts[lost + 1], 35,
            reason: 'the last restart that arrived was at 25 s, and the '
                'delayed leave fires 15 s after it, at 40 s');
        if (sticky) {
          // One at a time: the send of 34 s is still unanswered at 35 s,
          // and that heartbeat does not start another beside it.
          expect([
            for (final (at, kind) in homeserver.log)
              if (kind == 'sticky') at.inSeconds
          ], [
            0,
            34
          ]);
        }
        session.state = VoipState.ended;
        UserIdleWatcher.instance.isAway.value = false;
      });
    });
  }
}
