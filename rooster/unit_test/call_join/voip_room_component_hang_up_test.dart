// Hanging up a voice channel's join from its component: the join in flight
// is told, a join asked for afterwards is a new one, and a session that
// arrives once the join was hung up is hung up instead of kept.
import 'dart:async';

import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:test/test.dart';

class _Client implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements MatrixRoom {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A backend whose joins end when the test says so.
class _Backend implements MatrixLivekitBackend {
  final joins = <Completer<VoipSession?>>[];
  final hangUps = <Future<void>?>[];

  @override
  Future<VoipSession?> join(
      {Future<void> Function()? leavePrevious, Future<void>? hangUp}) {
    final join = Completer<VoipSession?>();
    joins.add(join);
    hangUps.add(hangUp);
    return join.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  var hungUp = false;

  @override
  Future<void> hangUpCall() async => hungUp = true;

  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MatrixVoipRoomComponent voip;
  late _Backend backend;

  setUp(() {
    voip = MatrixVoipRoomComponent(_Client(), _Room());
    backend = _Backend();
    voip.backend = backend;
  });

  test('hanging up tells the join in flight, and the next join is a new one',
      () async {
    final first = voip.joinCall();
    unawaited(first.then((_) {}, onError: (_) {}));
    var told = false;
    unawaited(backend.hangUps.single!.then((_) => told = true));

    voip.hangUpJoin();
    await Future<void>.delayed(Duration.zero);
    expect(told, isTrue);

    final second = voip.joinCall();
    expect(second, isNot(same(first)));
    expect(backend.joins, hasLength(2));

    final session = _Session();
    backend.joins.last.complete(session);
    expect(await second, same(session));
    expect(voip.currentSession, same(session));
  });

  test('a session that arrives after the hang up is hung up, not kept',
      () async {
    final joining = voip.joinCall();
    voip.hangUpJoin();

    final late = _Session();
    backend.joins.single.complete(late);

    await expectLater(joining, throwsA(isA<CallJoinHungUp>()));
    expect(late.hungUp, isTrue);
    expect(voip.currentSession, isNull);
  });

  test('without a join in flight, hanging up does nothing', () async {
    voip.hangUpJoin();
    final session = _Session();
    final joining = voip.joinCall();
    backend.joins.single.complete(session);

    expect(await joining, same(session));
    expect(session.hungUp, isFalse);
  });
}
