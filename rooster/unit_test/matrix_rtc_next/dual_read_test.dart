// Who is in a voice channel, whichever MatrixRTC format their client
// writes: the legacy `org.matrix.msc3401.call.member` state event, the
// newer `m.rtc.member` (MSC4143) in room state, or its unstable
// `org.matrix.msc4143.rtc.member` as a sticky event (MSC4354). A client
// writing several is listed once, in the channel's page, in the sidebar and
// in Who's around (both from MatrixActivitiesComponent.getSessions), and
// gets our call keys once; what has lapsed by the homeserver's clock is not
// listed.
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/matrix/components/room_activities/matrix_activities_component.dart';
import 'package:rooster/client/matrix/components/voip_room/call_key_distributor.dart';
import 'package:rooster/client/matrix/components/voip_room/call_key_messages.dart';
import 'package:rooster/client/matrix/components/voip_room/call_memberships.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:test/test.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';
const _dave = '@dave:example.org';
const _roomId = '!voice:example.org';
const _legacy = CallMemberships.legacyType;
const _unstable = 'org.matrix.msc4143.rtc.member';
const _stable = 'm.rtc.member';

class _Profile implements Profile {
  @override
  final String identifier = _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkClient implements matrix.Client {
  @override
  final String? deviceID = 'ME';
  @override
  final String? userID = _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  @override
  Profile? self = _Profile();

  final _SdkClient _sdk = _SdkClient();

  @override
  matrix.Client get matrixClient => _sdk;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  String get id => _roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements MatrixRoom {
  @override
  final String identifier = _roomId;
  final _SdkRoom _sdk = _SdkRoom();

  @override
  matrix.Room get matrixRoom => _sdk;

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Room room;
  late MatrixVoipRoomComponent voip;
  late MatrixActivitiesComponent activities;
  // The homeserver's time; this machine's clock is not asked.
  late DateTime serverTime;
  final joinedAt = DateTime(2026, 11, 23, 12);

  setUp(() {
    room = _Room();
    serverTime = joinedAt.add(const Duration(minutes: 1));
    final clock = HomeserverClock(localNow: () => serverTime);
    voip = MatrixVoipRoomComponent(_Client(), room, clock: clock);
    activities = MatrixActivitiesComponent(_Client(), room,
        callManager: ClientManager().callManager, clock: clock);
  });

  void legacy(String user, String device,
      {DateTime? at,
      bool left = false,
      Map<String, Object?> extra = const {}}) {
    final key = '_${user}_${device}_m.call';
    (room.matrixRoom.states[_legacy] ??= {})[key] = matrix.Event(
      type: _legacy,
      senderId: user,
      stateKey: key,
      eventId: '\$legacy-$user-$device-${at?.millisecondsSinceEpoch}',
      originServerTs: at ?? joinedAt,
      room: room.matrixRoom,
      content: left
          ? const {}
          : {
              'application': 'm.call',
              'call_id': '',
              'device_id': device,
              'scope': 'm.room',
              'expires': 4 * 3600 * 1000,
              ...extra,
            },
    );
  }

  Map<String, Object?> rtcContent(String user, String device,
          {bool left = false}) =>
      {
        'msc4354_sticky_key': '${user}_$device',
        'member': {'id': 'm-$device', 'user_id': user, 'device_id': device},
        if (!left) ...{
          'slot_id': 'm.call#',
          'application': {'type': 'm.call', 'm.call.id': ''},
          'rtc_transports': [
            {'type': 'livekit', 'livekit_service_url': 'https://sfu.test'},
          ],
          'versions': [],
        },
      };

  /// A sticky membership of the newer format, sticky for [duration].
  void sticky(String user, String device,
      {DateTime? at,
      Duration duration = const Duration(minutes: 2),
      bool left = false,
      String type = _unstable}) {
    room.matrixRoom.addStickyEvent(matrix.Event(
      type: type,
      senderId: user,
      eventId: '\$sticky-$user-$device-${at?.millisecondsSinceEpoch}',
      originServerTs: at ?? joinedAt,
      unsigned: {
        matrix.JoinedRoomUpdate.stickyDurationKey: duration.inMilliseconds,
      },
      room: room.matrixRoom,
      content: rtcContent(user, device, left: left),
    ));
  }

  /// The newer format kept as room state, with `expires`.
  void rtcState(String user, String device, {DateTime? at}) {
    final key = '_${user}_${device}_m.call';
    (room.matrixRoom.states[_stable] ??= {})[key] = matrix.Event(
      type: _stable,
      senderId: user,
      stateKey: key,
      eventId: '\$rtc-$user-$device',
      originServerTs: at ?? joinedAt,
      room: room.matrixRoom,
      content: {...rtcContent(user, device), 'expires': 4 * 3600 * 1000},
    );
  }

  /// Who the sidebar, Who's around and the channel's page list.
  List<String> channelPage() => voip.getCurrentParticipants();
  Set<String> sidebar() {
    final call = activities
        .getSessions()
        .where((s) => s.application == 'm.call')
        .toList();
    return call.isEmpty ? {} : call.single.participants;
  }

  /// Who gets our call keys, a device each.
  Set<CallMember> keyRecipients() => callMembersFromState(
        [
          for (final e in CallMemberships.of(room.matrixRoom, now: serverTime))
            (
              sender: e.senderId,
              content: e.content,
              sentAt: e is matrix.Event ? e.originServerTs : null,
            ),
        ],
        ownUserId: _me,
        ownDeviceId: 'ME',
        now: serverTime,
      ).keys.toSet();

  group('each format', () {
    test('is listed: legacy, m.rtc.member state, sticky rtc.member', () {
      legacy(_bob, 'BOB');
      rtcState(_carol, 'CAROL');
      sticky(_dave, 'DAVE');
      expect(channelPage(), unorderedEquals([_bob, _carol, _dave]));
      expect(sidebar(), {_bob, _carol, _dave});
      expect(keyRecipients(), {
        const CallMember(_bob, 'BOB'),
        const CallMember(_carol, 'CAROL'),
        const CallMember(_dave, 'DAVE'),
      });
    });

    test('the stable type as a sticky event too', () {
      sticky(_dave, 'DAVE', type: _stable);
      expect(channelPage(), [_dave]);
    });
  });

  group('all three at once for one device', () {
    setUp(() {
      legacy(_bob, 'BOB', extra: {
        'chat.commet.voice_state': ['muted'],
      });
      rtcState(_bob, 'BOB');
      sticky(_bob, 'BOB', at: joinedAt.add(const Duration(seconds: 30)));
      sticky(_bob, 'BOB', type: _stable);
    });

    test('list them once, everywhere', () {
      expect(
          CallMemberships.of(room.matrixRoom, now: serverTime), hasLength(1));
      expect(channelPage(), [_bob]);
      expect(sidebar(), {_bob});
      expect(keyRecipients(), {const CallMember(_bob, 'BOB')});
    });

    test('keep the legacy one, with its badges', () {
      final call = activities
          .getSessions()
          .singleWhere((s) => s.application == 'm.call');
      expect(call.voiceState[_bob], {VoiceState.muted});
    });
  });

  test('two devices of one person are two memberships, one person', () {
    legacy(_bob, 'PHONE');
    sticky(_bob, 'LAPTOP');
    expect(CallMemberships.of(room.matrixRoom, now: serverTime), hasLength(2));
    expect(channelPage(), [_bob]);
    expect(sidebar(), {_bob});
    expect(keyRecipients(), {
      const CallMember(_bob, 'PHONE'),
      const CallMember(_bob, 'LAPTOP'),
    });
  });

  group("by the homeserver's clock", () {
    test('a sticky membership counts while it is sticky, not after', () {
      sticky(_dave, 'DAVE');
      serverTime = joinedAt.add(const Duration(minutes: 1, seconds: 59));
      expect(channelPage(), [_dave]);
      expect(sidebar(), {_dave});
      serverTime = joinedAt.add(const Duration(minutes: 2, seconds: 1));
      expect(channelPage(), isEmpty);
      expect(sidebar(), isEmpty);
      expect(keyRecipients(), isEmpty);
    });

    test('a lapsed sticky one does not hide a live legacy one', () {
      legacy(_bob, 'BOB');
      sticky(_bob, 'BOB', at: joinedAt.add(const Duration(minutes: 5)));
      serverTime = joinedAt.add(const Duration(minutes: 10));
      expect(channelPage(), [_bob]);
      expect(sidebar(), {_bob});
    });

    test('a lapsed legacy one does not hide a live sticky one', () {
      legacy(_bob, 'BOB', extra: {'expires': 60000});
      sticky(_bob, 'BOB', at: joinedAt.add(const Duration(minutes: 2)));
      serverTime = joinedAt.add(const Duration(minutes: 3));
      expect(channelPage(), [_bob]);
    });
  });

  group('a leave', () {
    test(
        'of the legacy membership (the delayed leave of a client that died) '
        'takes down its older sticky one', () {
      sticky(_bob, 'BOB', at: joinedAt);
      legacy(_bob, 'BOB',
          at: joinedAt.add(const Duration(seconds: 15)), left: true);
      expect(channelPage(), isEmpty);
      expect(sidebar(), isEmpty);
    });

    test('of the sticky one takes down an older legacy one', () {
      legacy(_bob, 'BOB');
      sticky(_bob, 'BOB',
          at: joinedAt.add(const Duration(seconds: 10)), left: true);
      expect(channelPage(), isEmpty);
    });

    test('older than a join does not take it down', () {
      legacy(_bob, 'BOB', left: true);
      sticky(_bob, 'BOB', at: joinedAt.add(const Duration(seconds: 10)));
      expect(channelPage(), [_bob]);
    });
  });

  test('a sync with a sticky membership looks at the list again', () async {
    final changes = <void>[];
    final sub = voip.onParticipantsChanged.listen(changes.add);
    addTearDown(sub.cancel);
    voip.onSync(matrix.JoinedRoomUpdate(sticky: [
      matrix.MatrixEvent(
        type: _unstable,
        content: rtcContent(_dave, 'DAVE'),
        senderId: _dave,
        eventId: r'$s',
        originServerTs: joinedAt,
      ),
    ]));
    await Future<void>.delayed(Duration.zero);
    expect(changes, hasLength(1));
    expect(CallMemberships.touches(matrix.JoinedRoomUpdate()), isFalse);
  });

  // Review c1-1: a device in the voice call that also runs a widget activity
  // (its own legacy membership, another application) is in both.
  group('c1-1 two applications on one device', () {
    const whiteboard = 'io.example.whiteboard';

    void app(String user, String device, String application,
        {DateTime? at, bool left = false}) {
      final key = '_${user}_${device}_$application';
      (room.matrixRoom.states[_legacy] ??= {})[key] = matrix.Event(
        type: _legacy,
        senderId: user,
        stateKey: key,
        eventId: '\$app-$user-$device-$application',
        originServerTs: at ?? joinedAt,
        room: room.matrixRoom,
        content: left
            ? const {}
            : {
                'application': application,
                'call_id': '',
                'device_id': device,
                'scope': 'm.room',
                'expires': 4 * 3600 * 1000,
              },
      );
    }

    Set<String> applications() =>
        activities.getSessions().map((s) => s.application).toSet();

    test('widget membership written first: still in the voice call', () {
      app(_bob, 'BOB', whiteboard);
      legacy(_bob, 'BOB');
      expect(channelPage(), [_bob]);
      expect(sidebar(), {_bob});
      expect(applications(), {'m.call', whiteboard});
    });

    test('voice membership written first: the activity is still listed', () {
      legacy(_bob, 'BOB');
      app(_bob, 'BOB', whiteboard);
      expect(applications(), {'m.call', whiteboard});
    });

    test('an activity that ended does not take its device out of the call', () {
      sticky(_bob, 'BOB');
      legacy(_bob, 'BOB');
      app(_bob, 'BOB', whiteboard,
          at: joinedAt.add(const Duration(seconds: 30)), left: true);
      expect(sidebar(), {_bob});
      expect(applications(), {'m.call'});

      // Nor out of a call it is in by the newer format alone.
      room.matrixRoom.states[_legacy]!.remove('_${_bob}_BOB_m.call');
      expect(sidebar(), {_bob});
    });

    test('a newer format leave of the call leaves the activity alone', () {
      app(_bob, 'BOB', whiteboard);
      legacy(_bob, 'BOB');
      sticky(_bob, 'BOB',
          at: joinedAt.add(const Duration(seconds: 10)), left: true);
      expect(applications(), {whiteboard});
    });
  });
}
