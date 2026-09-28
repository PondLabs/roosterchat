// Leaving every call before the app closes or restarts (CallManager
// .leaveAllCalls): each call is hung up, or declined when it was only
// ringing, one that fails does not hold the others or the app back, and the
// leave sound is waited for.
import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:commet/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session implements VoipSession {
  _Session(this.calls, this.name, this.state, {this.failsToLeave = false});

  final CallManager calls;
  final String name;
  final bool failsToLeave;
  final List<String> did = [];

  @override
  VoipState state;
  @override
  bool get isDeafened => false;
  @override
  Stream<VoipState> get onConnectionStateChanged => const Stream.empty();

  @override
  Future<void> hangUpCall() async {
    did.add('hang up');
    if (failsToLeave) throw StateError('the server is gone');
    state = VoipState.ended;
    calls.onSessionEnded(this);
  }

  @override
  Future<void> declineCall() async {
    did.add('decline');
    state = VoipState.ended;
    calls.onSessionEnded(this);
  }

  @override
  String toString() => name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CallManager calls;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
    calls = CallManager(ClientManager());
  });

  // ignore: invalid_use_of_visible_for_testing_member
  tearDown(() => AudioProcessingManager.debugInstance = null);

  test('every call is hung up, and one ringing is declined', () async {
    final voice = _Session(calls, 'voice', VoipState.connected);
    final ringing = _Session(calls, 'ringing', VoipState.incoming);
    calls.currentSessions.addAll([voice, ringing]);

    await calls.leaveAllCalls();

    expect(voice.did, ['hang up']);
    expect(ringing.did, ['decline']);
    expect(calls.currentSessions, isEmpty);
  });

  test('a call that fails to leave does not keep the others in', () async {
    final stuck =
        _Session(calls, 'stuck', VoipState.connected, failsToLeave: true);
    final voice = _Session(calls, 'voice', VoipState.connected);
    calls.currentSessions.addAll([stuck, voice]);

    await calls.leaveAllCalls();

    expect(stuck.did, ['hang up']);
    expect(voice.did, ['hang up']);
    expect(calls.currentSessions, [stuck]);
  });

  test('with no call there is nothing to wait for', () async {
    final watch = Stopwatch()..start();
    await calls.leaveAllCalls();
    expect(watch.elapsed, lessThan(CallManager.leaveSoundLength));
  });
}
