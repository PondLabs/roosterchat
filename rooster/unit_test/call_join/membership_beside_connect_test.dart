// Our call membership was written, and only then did the LiveKit connection
// start. Now the two start together, and the join waits for both to end
// before it is done or undone: a membership is only cleared once its write
// has settled, and nothing comes back after a join that failed or was hung
// up (issue #48).
import 'dart:async';

import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_membership_writes.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late Journal journal;
  late FakeHost host;

  setUp(() {
    journal = Journal();
    host = FakeHost(journal);
    // The sequence of each scenario, for the record.
    // ignore: avoid_print
    addTearDown(() => print('sequence: ${journal.entries.join(' > ')}'));
  });

  CallJoin<FakeLivekitRoom> join() => CallJoin(
      host: host,
      tokens: fakeTokenService(journal),
      log: SpeedLog(),
      remoteAudioWindow: const Duration(milliseconds: 1));

  /// Nothing of the join is left: no membership on the homeserver, no
  /// session, a disposed room and no microphone left capturing, also a
  /// while later.
  Future<void> nothingLeft(FakeLivekitRoom room) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(host.membership, isFalse, reason: 'no membership left behind');
    expect(journal.entries, isNot(contains('session')));
    expect(journal.entries, isNot(contains('microphone_published')));
    expect(room.disposed, isTrue);
    expect(room.microphones.every((m) => m.stopped), isTrue);
  }

  test('the membership write and the connection are in flight together',
      () async {
    host.membershipGate = Gate();
    host.room.connectGate = Gate();

    final joining = join().run();
    await settle();

    expect(journal.entries, containsAll(['membership_write', 'connect']),
        reason: 'both started');
    expect(journal.entries, isNot(contains('membership_written')));
    expect(journal.entries, isNot(contains('connected')),
        reason: 'neither has answered yet');

    host.membershipGate.open();
    host.room.connectGate.open();
    await joining;
    expect(host.membership, isTrue);
  });

  group('the microphone is published only once both succeeded', () {
    test('the connection first, the write after', () async {
      host.membershipGate = Gate();

      final joining = join().run();
      await settle();
      expect(journal.entries, contains('connected'));
      expect(journal.entries, isNot(contains('microphone_published')),
          reason: 'the membership is still being written');

      host.membershipGate.open();
      await joining;
      await settle();
      expect(
          journal.before('membership_written', 'microphone_published'), isTrue);
      expect(journal.before('connected', 'microphone_published'), isTrue);
    });

    test('the write first, the connection after', () async {
      host.room.connectGate = Gate();

      final joining = join().run();
      await settle();
      expect(journal.entries, contains('membership_written'));
      expect(journal.entries, isNot(contains('microphone_published')));

      host.room.connectGate.open();
      await joining;
      await settle();
      expect(
          journal.before('membership_written', 'microphone_published'), isTrue);
      expect(journal.before('connected', 'microphone_published'), isTrue);
    });
  });

  test(
      'a connection that fails at once, with the write ending 2 s later: '
      'the clear only goes after the write, and no membership is left',
      () async {
    host.membershipGate = Gate();
    host.room.connectError = StateError('no SFU');
    final room = host.room;

    var done = false;
    final joining = join().run().whenComplete(() => done = true);
    unawaited(joining.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(journal.entries, contains('connect'));
    expect(journal.entries, isNot(contains('membership_clear')),
        reason: 'the write is still in flight: a clear now could land first');
    expect(done, isFalse, reason: 'the join waits for the write to end');

    await Future<void>.delayed(const Duration(seconds: 1));
    host.membershipGate.open();
    await expectLater(joining, throwsStateError);

    expect(journal.before('membership_written', 'membership_clear'), isTrue);
    await nothingLeft(room);
  });

  test(
      'a write that fails while the connection succeeds: the room is let go, '
      'the microphone is not published, the join fails', () async {
    host.membershipError = StateError('M_FORBIDDEN');
    host.room.connectGate = Gate();
    final room = host.room;

    final joining = join().run();
    await settle();
    expect(room.disposed, isFalse,
        reason: 'the connection is waited for to its end');

    room.connectGate.open();
    await expectLater(joining, throwsStateError);

    expect(journal.before('connected', 'room_disposed'), isTrue);
    await nothingLeft(room);
  });

  group('a timeout', () {
    test('of the write, whose request still landed: it is cleared', () async {
      host.membershipError = TimeoutException('the answer never came');
      host.membershipLandsBeforeError = true;
      final room = host.room;

      await expectLater(join().run(), throwsA(isA<TimeoutException>()));

      expect(journal.before('membership_written', 'membership_clear'), isTrue);
      await nothingLeft(room);
    });

    test('of the connection: the membership written is cleared', () async {
      host.room.connectError = TimeoutException('no answer from the SFU');
      final room = host.room;

      await expectLater(join().run(), throwsA(isA<TimeoutException>()));

      expect(journal.before('membership_written', 'membership_clear'), isTrue);
      await nothingLeft(room);
    });
  });

  group('hanging up during the join', () {
    test(
        'while the write and the connection are in flight: both end, then '
        'everything is taken back and no session comes', () async {
      host.membershipGate = Gate();
      host.room.connectGate = Gate();
      final room = host.room;
      final hangUp = Completer<void>();

      final joining = join().run(hangUp: hangUp.future);
      await settle();
      expect(journal.entries, containsAll(['membership_write', 'connect']));

      hangUp.complete();
      await settle();
      expect(journal.entries, isNot(contains('membership_clear')),
          reason: 'the write has not ended');

      host.membershipGate.open();
      room.connectGate.open();
      await expectLater(joining, throwsA(isA<CallJoinHungUp>()));

      expect(journal.before('membership_written', 'membership_clear'), isTrue);
      expect(journal.before('connected', 'room_disposed'), isTrue);
      await nothingLeft(room);
    });

    test(
        'while the previous call hangs up: nothing is written, and a '
        "phone's browser does not open the microphone", () async {
      host.phoneBrowser = true;
      final hangUp = Completer<void>();
      final leaving = Gate();
      final room = host.room;

      final joining = join()
          .run(hangUp: hangUp.future, leavePrevious: () => leaving.passed);
      await settle();
      hangUp.complete();
      leaving.open();
      await expectLater(joining, throwsA(isA<CallJoinHungUp>()));

      expect(journal.entries, isNot(contains('microphone_open')),
          reason: 'no capture, nor its prompt, after the hang up');
      expect(journal.entries, isNot(contains('membership_write')));
      expect(journal.entries, isNot(contains('connect')));
      await nothingLeft(room);
    });

    test('while waiting for the previous clear: nothing is written', () async {
      final hangUp = Completer<void>();
      final clear = Completer<void>();
      final room = host.room;
      // The previous call's clear, still in flight after its hang up.
      CallMembershipWrites.clearing(host.membershipKey, clear.future);

      final joining = join().run(hangUp: hangUp.future);
      await settle();
      expect(journal.entries, contains('sfu_get'));
      hangUp.complete();
      clear.complete();
      await expectLater(joining, throwsA(isA<CallJoinHungUp>()));

      expect(journal.entries, isNot(contains('membership_write')));
      expect(journal.entries, isNot(contains('connect')));
      await nothingLeft(room);
    });
  });

  test(
      'hanging up and joining again at once: the new membership is written '
      'after the old one is cleared, and only the new session is left',
      () async {
    host.membershipGate = Gate();
    host.room.connectGate = Gate();
    final first = host.room;
    final hangUp = Completer<void>();

    final firstJoin = join().run(hangUp: hangUp.future);
    unawaited(firstJoin.then((_) {}, onError: (_) {}));
    await settle();
    expect(journal.entries, containsAll(['membership_write', 'connect']));

    // Hung up, and joined again before the first join has ended.
    hangUp.complete();
    final second = FakeLivekitRoom(journal);
    host.room = second;
    final secondJoin = join().run();
    await settle();
    expect(journal.count('membership_write'), 1,
        reason: 'the second write waits for the first join to be undone');

    host.membershipGate.open();
    first.connectGate.open();
    await expectLater(firstJoin, throwsA(isA<CallJoinHungUp>()));
    final session = await secondJoin;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(session, same(second));
    expect(journal.count('session'), 1);
    expect(journal.indexOf('membership_clear'),
        lessThan(journal.lastIndexOf('membership_write')),
        reason: 'the old clear cannot land on the new membership');
    expect(host.membership, isTrue, reason: 'the new membership stays');
    expect(first.disposed, isTrue);
    expect(second.disposed, isFalse);
  });

  test("a failed join's clear is one a quick rejoin waits for", () async {
    final clear = Completer<void>();
    host.room.connectError = StateError('no SFU');
    final key = CallMembershipWrites.joinKey(host.roomId, host.membershipKey);
    // Held in flight, as a slow homeserver would.
    host.clearMembershipOverride = () => clear.future;

    final failing = join().run();
    await expectLater(
        Future.any([
          failing.then((_) => 'ended', onError: (_) => 'ended'),
          Future<void>.delayed(const Duration(milliseconds: 50))
              .then((_) => 'waiting'),
        ]),
        completion('waiting'),
        reason: 'the join is undone before it reports');

    var settled = false;
    unawaited(CallMembershipWrites.settled(key).then((_) => settled = true));
    await settle();
    expect(settled, isFalse, reason: 'the clear is registered while in flight');

    clear.complete();
    await expectLater(failing, throwsStateError);
    await settle();
    expect(settled, isTrue);
  });

  test(
      "a join in another room does not wait for this room's join, which is "
      'still connecting', () async {
    host.room.connectGate = Gate();
    final joining = join().run();
    unawaited(joining.then((_) {}, onError: (_) {}));
    await settle();
    expect(journal.entries, contains('connect'));

    final otherJournal = Journal();
    // Same account and device: the same state key, in another room.
    final other = FakeHost(otherJournal)..roomId = '!other:example.org';
    final otherJoin = CallJoin(
            host: other,
            tokens: fakeTokenService(otherJournal),
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(otherJournal.entries, containsAll(['membership_write', 'connect']),
        reason: 'not held up by the join in the first room');
    await otherJoin;

    host.room.connectGate.open();
    await joining;
  });
}
