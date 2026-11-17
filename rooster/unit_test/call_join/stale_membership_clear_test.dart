// A voice channel's page clears a call membership this device left behind
// (the app closed mid-call) when it opens. During a join that clear could
// erase the membership the join had just written: it now goes through
// CallMembershipWrites, so a join's write waits for it, and it leaves alone
// a membership a join of the room holds.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_membership_writes.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _me = '@me:example.org';
const _device = 'DEVICE';

/// The homeserver's call memberships, by state key: both the page's clear
/// and the join's write land here.
class _Homeserver {
  final Map<String, Map<String, Object?>> memberships = {};
  final List<String> requests = [];

  /// Holds the next clear in flight until completed, when set.
  Completer<void>? clearGate;

  bool holds(String stateKey) => memberships[stateKey]?.isNotEmpty ?? false;
}

/// A join's Matrix side whose membership write lands on [server].
class _Host extends FakeHost {
  _Host(super.journal, this.server);
  final _Homeserver server;

  @override
  Future<void> writeMembership(List<Uri> foci) async {
    server.requests.add('write');
    await super.writeMembership(foci);
    server.memberships[membershipKey] = {'device_id': _device};
  }

  @override
  Future<void> clearMembership() async {
    server.requests.add('clear');
    await super.clearMembership();
    server.memberships[membershipKey] = {};
  }
}

void main() {
  late _Homeserver server;
  late matrix.Room sdkRoom;
  late MatrixVoipRoomComponent voip;
  late Journal journal;
  late _Host host;
  var rooms = 0;

  setUp(() {
    server = _Homeserver();
    // A room of its own per test: what CallMembershipWrites holds is
    // shared by every test of the file.
    final roomId = '!stale-${rooms++}:example.org';
    final sdk = FakeSdkClient()
      ..setState = (stateKey, body) async {
        server.requests.add(body.isEmpty ? 'clear' : 'write');
        if (body.isEmpty) {
          final gate = server.clearGate;
          server.clearGate = null;
          await gate?.future;
        }
        server.memberships[stateKey] = body;
      };
    final room = FakeMatrixRoom(roomId, sdk);
    sdkRoom = room.matrixRoom;
    voip = MatrixVoipRoomComponent(FakeMatrixClient(sdk), room);
    journal = Journal();
    host = _Host(journal, server)..roomId = roomId;
    // The join's own room is ended at the end, so its claim is given back.
    addTearDown(() {
      if (!host.room.ended.isCompleted) host.room.ended.complete();
    });
  });

  /// What a sync puts in the room's state: our membership at [stateKey],
  /// as this device wrote it.
  void synced(String stateKey) {
    sdkRoom.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
      stateKey: matrix.StrippedStateEvent(
          type: MatrixVoipRoomComponent.callMemberStateEvent,
          stateKey: stateKey,
          senderId: _me,
          content: {'device_id': _device, 'application': 'm.call'}),
    };
  }

  CallJoin<FakeLivekitRoom> join() => CallJoin(
      host: host,
      tokens: fakeTokenService(journal),
      log: SpeedLog(),
      remoteAudioWindow: const Duration(milliseconds: 1));

  test(
      'a membership left behind is cleared when the page opens, and a join '
      'started meanwhile writes only once that clear has landed', () async {
    synced(host.membershipKey);
    server.memberships[host.membershipKey] = {'device_id': _device};
    final clear = server.clearGate = Completer<void>();

    final clearing = voip.clearStaleOwnMembership();
    await settle();
    expect(server.requests, ['clear'], reason: 'the clear is in flight');

    final joining = join().run();
    unawaited(joining.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(journal.entries, isNot(contains('membership_write')),
        reason: 'the write waits for the clear');

    clear.complete();
    await clearing;
    await joining;
    expect(server.requests, ['clear', 'write']);
    expect(server.holds(host.membershipKey), isTrue,
        reason: 'the new membership is not erased');
  });

  test(
      'the page opened while a join is connecting does not clear the '
      'membership that join has just written', () async {
    host.room.connectGate = Gate();
    final joining = join().run();
    unawaited(joining.then((_) {}, onError: (_) {}));
    await settle();
    expect(journal.entries, contains('membership_written'));
    // The sync brings our fresh membership into the room's state, and the
    // join has no session yet.
    synced(host.membershipKey);

    await voip.clearStaleOwnMembership();
    expect(server.requests, ['write'], reason: 'no clear was sent');

    host.room.connectGate.open();
    await joining;
    expect(server.holds(host.membershipKey), isTrue);
  });

  test('once the join has given its membership back, the page clears it',
      () async {
    host.room.connectGate = Gate();
    host.room.connectError = StateError('no SFU');
    final joining = join().run();
    unawaited(joining.then((_) {}, onError: (_) {}));
    await settle();
    host.room.connectGate.open();
    await expectLater(joining, throwsStateError);
    // A sync from before the join's own clear still lists the membership.
    synced(host.membershipKey);

    await voip.clearStaleOwnMembership();
    expect(server.requests, ['write', 'clear', 'clear'],
        reason: "the join's own clear, then the page's");
  });

  group('clears of one state key, in flight together', () {
    const key = '_@me:example.org_CHAINED_m.call';

    test('a later write waits for the slow one, not only the latest', () async {
      final slow = Completer<void>();
      final quick = Completer<void>();
      CallMembershipWrites.clearing(key, slow.future);
      CallMembershipWrites.clearing(key, quick.future);
      var settled = false;
      unawaited(CallMembershipWrites.settled(key).then((_) => settled = true));

      quick.complete();
      await settle();
      expect(settled, isFalse, reason: 'the slow clear is still in flight');

      slow.complete();
      await settle();
      expect(settled, isTrue);
    });

    test('a clear registered while a write waits is waited for too', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      CallMembershipWrites.clearing(key, first.future);
      var settled = false;
      unawaited(CallMembershipWrites.settled(key).then((_) => settled = true));
      await settle();

      CallMembershipWrites.clearing(key, second.future);
      first.complete();
      await settle();
      expect(settled, isFalse);

      second.complete();
      await settle();
      expect(settled, isTrue);
    });

    test(
        'a clear that never lands holds up only the writes of its own 10 s, '
        'not those after a later clear', () {
      fakeAsync((async) {
        const stuckKey = '_@me:example.org_STUCK_m.call';
        CallMembershipWrites.clearing(stuckKey, Completer<void>().future);
        async.elapse(const Duration(seconds: 11));

        final later = Completer<void>();
        CallMembershipWrites.clearing(stuckKey, later.future);
        later.complete();
        var settled = false;
        CallMembershipWrites.settled(stuckKey).then((_) => settled = true);
        async.elapse(const Duration(milliseconds: 100));
        expect(settled, isTrue, reason: 'the stuck clear had its 10 s');
      });
    });

    /// A clear of our membership that lands 15 s after it was sent, and a
    /// join started [joinAfter] after it. Whether the join, in the call at
    /// the end, kept its membership.
    bool keptPastLateClear(FakeAsync async, Duration joinAfter) {
      final journal = Journal();
      final host = FakeHost(journal)..roomId = '!late-${joinAfter.inSeconds}';
      final landed = Completer<void>();
      CallMembershipWrites.clearing(host.membershipKey, landed.future);
      Timer(const Duration(seconds: 15), () {
        host.membership = false;
        landed.complete();
      });
      async.elapse(joinAfter);
      Object? session;
      CallJoin<FakeLivekitRoom>(
              host: host,
              tokens: fakeTokenService(journal),
              log: SpeedLog(),
              remoteAudioWindow: const Duration(milliseconds: 1))
          .run()
          .then((s) => session = s);
      async.elapse(const Duration(seconds: 30));
      expect(session, isNotNull);
      final kept = host.membership;
      host.room.ended.complete();
      async.elapse(const Duration(seconds: 1));
      return kept;
    }

    test(
        'a clear that lands 15 s after it was sent: a join started 9 s or '
        '11 s after it writes once it has landed, and keeps its membership',
        () {
      fakeAsync((async) {
        expect(keptPastLateClear(async, const Duration(seconds: 9)), isTrue);
      });
      fakeAsync((async) {
        expect(keptPastLateClear(async, const Duration(seconds: 11)), isTrue);
      });
    });

    test('a clear that fails still orders the writes, and does not fail them',
        () async {
      final failing = Completer<void>();
      CallMembershipWrites.clearing(key, failing.future).ignore();
      final waiting = CallMembershipWrites.settled(key);
      failing.completeError(StateError('the homeserver is gone'));
      await expectLater(waiting, completes);
    });
  });
}
