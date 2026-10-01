// An away friend went grey: the dots read getUserPresence once and then
// follow onPresenceChanged, and that stream passed on the homeserver's
// presence as is, undoing a call membership that says they are away.
import 'package:cockhouse/client/components/profile/profile_component.dart';
import 'package:cockhouse/client/components/user_presence/user_idle_watcher.dart';
import 'package:cockhouse/client/components/user_presence/user_presence_component.dart';
import 'package:cockhouse/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:cockhouse/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:cockhouse/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:cockhouse/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

const selfUserId = "@me:example.org";
const friendId = "@friend:example.org";

class FakeProfile implements Profile {
  @override
  final String identifier = selfUserId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkRoom implements matrix.Room {
  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkClient implements matrix.Client {
  final room = FakeSdkRoom();
  final presences = <String, matrix.CachedPresence>{};

  @override
  final onPresenceChanged = CachedStreamController<matrix.CachedPresence>();
  @override
  final onSync = CachedStreamController<matrix.SyncUpdate>();

  @override
  List<matrix.Room> get rooms => [room];

  @override
  Future<matrix.CachedPresence> fetchCurrentPresence(String userId,
          {bool fetchOnlyFromCached = false}) async =>
      presences[userId] ?? matrix.CachedPresence.neverSeen(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixClient implements MatrixClient {
  final sdk = FakeSdkClient();

  @override
  Profile? self = FakeProfile();

  @override
  matrix.Client get matrixClient => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMatrixClient client;
  late MatrixUserPresenceComponent component;
  late List<UserPresenceStatus> emitted;

  void inCall({required bool away}) {
    client.sdk.room.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
      "${friendId}_DEVICE": matrix.StrippedStateEvent(
        type: MatrixVoipRoomComponent.callMemberStateEvent,
        senderId: friendId,
        stateKey: "${friendId}_DEVICE",
        content: {
          "application": "m.call",
          MatrixCallMembership.awayKey: away,
        },
      ),
    };
  }

  matrix.CachedPresence offline() => matrix.CachedPresence(
      matrix.PresenceType.offline, null, null, null, friendId);

  setUp(() {
    client = FakeMatrixClient();
    component = MatrixUserPresenceComponent(client);
    UserIdleWatcher.instance.dispose();
    emitted = [];
    component.onPresenceChanged
        .where((e) => e.$1 == friendId)
        .listen((e) => emitted.add(e.$2.status));
  });

  test('a homeserver update does not turn a friend away in a call grey',
      () async {
    inCall(away: true);

    component.changed(offline());
    await pumpEventQueue();

    expect(emitted, [UserPresenceStatus.unavailable]);
  });

  test('their client rewriting the membership does not make them green',
      () async {
    inCall(away: true);

    component.sawUser(friendId, DateTime.now());
    await pumpEventQueue();

    expect(emitted, [UserPresenceStatus.unavailable]);
  });

  test('someone offline and in no call is still grey', () async {
    component.changed(offline());
    await pumpEventQueue();

    expect(emitted, [UserPresenceStatus.offline]);
  });

  test('an update is read the same way as the first look', () async {
    inCall(away: false);
    client.sdk.presences[friendId] = offline();

    component.changed(offline());
    await pumpEventQueue();

    expect(emitted, [UserPresenceStatus.online]);
    expect((await component.getUserPresence(friendId)).status,
        UserPresenceStatus.online);
  });
}
