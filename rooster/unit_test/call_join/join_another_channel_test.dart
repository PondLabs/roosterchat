// Joining a voice channel while the join of another one still runs. The
// older join used to go on: it got in after the newer one, and its session
// starting left the newer call (the call manager's backstop), so the user
// ended up in the channel they had walked out of. The newer join now hangs
// the older one up as it starts (CallManager.joinStarted).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// One voice channel: its component, and the Matrix side of its joins.
class _Channel {
  _Channel(String roomId, FakeMatrixClient client, CallManager calls)
      : journal = Journal() {
    host = FakeHost(journal)..roomId = roomId;
    voip = MatrixVoipRoomComponent(
        client, FakeMatrixRoom(roomId, client.matrixClient));
    voip.backend = FakeBackend(
        SessionHost(host, client, calls: calls), fakeTokenService(journal));
  }

  final Journal journal;
  late final FakeHost host;
  late final MatrixVoipRoomComponent voip;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CallManager calls;
  late FakeMatrixClient client;
  var rooms = 0;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
    // The components reach the call manager through the app's.
    clientManager = ClientManager();
    calls = clientManager!.callManager;
    client = FakeMatrixClient(FakeSdkClient());
  });

  tearDown(() {
    clientManager = null;
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = null;
  });

  _Channel channel() =>
      _Channel('!voice-${rooms++}:example.org', client, calls);

  /// Ends every session left, so each join gives its claim back.
  Future<void> leaveAll() async {
    for (final session in calls.currentSessions.toList()) {
      await session.hangUpCall();
    }
  }

  test(
      "joining B while A's join still connects: A's join is hung up, B stays, "
      'and only B has a membership and a session', () async {
    final a = channel();
    final b = channel();
    a.host.room.connectGate = Gate();
    final joiningA = a.voip.joinCall();
    unawaited(joiningA.then((_) {}, onError: (_) {}));
    await settle();
    expect(a.journal.entries, containsAll(['membership_written', 'connect']));

    final sessionB = await b.voip.joinCall();
    expect(sessionB, isNotNull);

    // A's connection answers only now, after B got in.
    a.host.room.connectGate.open();
    await expectLater(joiningA, throwsA(isA<CallJoinHungUp>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(a.host.membership, isFalse, reason: 'A took its membership back');
    expect(a.journal.entries, isNot(contains('session')));
    expect(a.host.room.disposed, isTrue);
    expect(b.host.membership, isTrue);
    expect(sessionB!.state, VoipState.connected);
    expect(calls.currentSessions, [sessionB]);
    expect(b.voip.currentSession, same(sessionB));
    expect(a.voip.currentSession, isNull);
    await leaveAll();
  });

  test('A, then B, then A again: only the last one is left', () async {
    final a = channel();
    final b = channel();
    a.host.room.connectGate = Gate();
    b.host.room.connectGate = Gate();
    final first = a.voip.joinCall();
    unawaited(first.then((_) {}, onError: (_) {}));
    await settle();
    final second = b.voip.joinCall();
    unawaited(second.then((_) {}, onError: (_) {}));
    await settle();

    final secondRoomOfA = FakeLivekitRoom(a.journal);
    final firstRoomOfA = a.host.room;
    a.host.room = secondRoomOfA;
    final third = a.voip.joinCall();
    expect(third, isNot(same(first)), reason: 'the first join was hung up');
    firstRoomOfA.connectGate.open();
    b.host.room.connectGate.open();

    final session = await third;
    await expectLater(first, throwsA(isA<CallJoinHungUp>()));
    await expectLater(second, throwsA(isA<CallJoinHungUp>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls.currentSessions, [session]);
    expect(b.host.membership, isFalse);
    expect(a.host.membership, isTrue, reason: "the third join's");
    await leaveAll();
  });

  test(
      'leaving the call while a join still connects hangs the join up: its '
      'membership is taken back, and no session comes of it', () async {
    final a = channel();
    a.host.room.connectGate = Gate();
    final joining = a.voip.joinCall();
    unawaited(joining.then((_) {}, onError: (_) {}));
    await settle();
    expect(a.host.membership, isTrue, reason: 'written beside the connect');

    await calls.disconnect();
    a.host.room.connectGate.open();
    await expectLater(joining, throwsA(isA<CallJoinHungUp>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(a.host.membership, isFalse);
    expect(a.journal.entries, isNot(contains('session')));
    expect(a.host.room.disposed, isTrue);
    expect(calls.currentSessions, isEmpty);
    expect(a.voip.currentSession, isNull);
  });

  test(
      "T3.2's INVERSE 8 by a switch of voice channel: A's write is still in "
      'flight when B is joined; A again, past the 10 s, gets in and is '
      'left; then the old write lands: no membership, no session', () {
    fakeAsync((async) {
      // Made in the clock's zone, so their gates run on it.
      final a = channel();
      final b = channel();
      final oldWrite = Gate();
      a.host.membershipGate = oldWrite;
      Object? firstError;
      a.voip.joinCall().then<void>((_) {}, onError: (Object e) {
        firstError = e;
      });
      async.elapse(const Duration(milliseconds: 10));
      expect(a.journal.entries, containsAll(['membership_write', 'connected']));

      // Joining B hangs A's join up; its write is still in flight.
      VoipSession? sessionB;
      b.voip.joinCall().then<void>((s) => sessionB = s);
      async.elapse(const Duration(milliseconds: 100));
      expect(sessionB, isNotNull);
      expect(firstError, isNull, reason: 'A waits for its write');

      // Back to A: a new join, which leaves B and waits for the old one.
      a.host.membershipGate = Gate()..open();
      a.host.room = FakeLivekitRoom(a.journal);
      VoipSession? sessionA;
      a.voip.joinCall().then<void>((s) => sessionA = s);
      async.elapse(const Duration(seconds: 9));
      expect(sessionA, isNull, reason: 'waits for the old join, 10 s at most');
      async.elapse(const Duration(seconds: 2));
      expect(sessionA, isNotNull);
      expect(sessionB!.state, VoipState.ended);
      expect(b.host.membership, isFalse);
      expect(a.host.membership, isTrue);

      sessionA!.hangUpCall();
      async.elapse(const Duration(milliseconds: 100));
      expect(a.host.membership, isFalse);

      oldWrite.open();
      async.elapse(const Duration(milliseconds: 100));
      expect(firstError, isA<CallJoinHungUp>());
      expect(a.journal.lastIndexOf('membership_clear'),
          greaterThan(a.journal.lastIndexOf('membership_written')),
          reason: 'the old join cleared its late write');
      expect(a.host.membership, isFalse, reason: 'no membership, no session');
      expect(a.journal.count('session'), 1);
      expect(calls.currentSessions, isEmpty);
    });
  });

  test("a join of the same channel is not hung up: it is the same join",
      () async {
    final a = channel();
    a.host.room.connectGate = Gate();
    final first = a.voip.joinCall();
    final again = a.voip.joinCall();
    expect(again, same(first));
    a.host.room.connectGate.open();
    expect(await first, isNotNull);
    await leaveAll();
  });

  test("another account's join is left alone where accounts are two people",
      () async {
    // ignore: invalid_use_of_visible_for_testing_member
    calls.accountsAreSeparatePeople = true;
    final a = channel();
    final otherClient = FakeMatrixClient(FakeSdkClient());
    final b = _Channel('!voice-${rooms++}:example.org', otherClient, calls);
    a.host.room.connectGate = Gate();
    final joiningA = a.voip.joinCall();
    await settle();

    await b.voip.joinCall();
    a.host.room.connectGate.open();
    expect(await joiningA, isNotNull);
    expect(calls.currentSessions, hasLength(2));
    await leaveAll();
  });
}
