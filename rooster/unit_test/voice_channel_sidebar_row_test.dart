// The voice channel's row in the sidebar, as the user sees it: every name in
// the channel under it. People who had been in it for a while were missing
// (the channel looked empty, or had only whoever came in last), because
// their memberships were read against this machine's clock, hours ahead of
// the homeserver's here.
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/matrix/components/room_activities/matrix_activities_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/room_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _roomId = '!hangout:example.org';
const _me = '@me:example.org';

const _names = {
  '@alice:example.org': 'Alice',
  '@bob:example.org': 'Bob',
  '@carol:example.org': 'Carol',
};

/// The homeserver's time: three hours behind this machine's clock, as a
/// Windows clock reading a dual boot's UTC hardware clock as local time
/// runs in Brazil.
DateTime _serverNow() => DateTime.now().subtract(const Duration(hours: 3));

/// A sync the homeserver answered at [at], by its clock.
matrix.SyncUpdate _syncAt(DateTime at) => matrix.SyncUpdate(
      nextBatch: 'next',
      rooms: matrix.RoomsUpdate(join: {
        _roomId: matrix.JoinedRoomUpdate(
          timeline: matrix.TimelineUpdate(events: [
            matrix.MatrixEvent(
              type: 'm.room.message',
              content: const {'body': 'hi'},
              senderId: '@carol:example.org',
              eventId: r'$hi',
              originServerTs: at,
              unsigned: const {'age': 0},
            ),
          ]),
        ),
      }),
    );

class _Profile implements Profile {
  @override
  final String identifier = _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkClient implements matrix.Client {
  @override
  final String? deviceID = 'DEVICE';

  @override
  final String? userID = _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  @override
  Profile? self = _Profile();

  @override
  final matrix.Client matrixClient = _SdkClient();

  @override
  String get identifier => 'client';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  @override
  final String id = _roomId;

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  _Member(this.identifier, this.displayName);

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A voice channel. A member is known by name only once asked for, as with
/// the members a homeserver lazy loads.
class _Room implements MatrixRoom {
  _Room(this.client);

  @override
  final _Client client;

  @override
  final String identifier = _roomId;

  @override
  final _SdkRoom matrixRoom = _SdkRoom();

  late RoomComponent activities;

  final Set<String> fetched = {};

  @override
  T? getComponent<T extends RoomComponent>() =>
      activities is T ? activities as T : null;

  @override
  Member getMemberOrFallback(String id) =>
      _Member(id, fetched.contains(id) ? _names[id]! : id);

  @override
  Future<Member> fetchMember(String id) async {
    fetched.add(id);
    return getMemberOrFallback(id);
  }

  @override
  String get displayName => 'Hangout';

  @override
  IconData get icon => Icons.volume_up;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  bool get isFavorite => false;

  @override
  bool get isSpecialRoomType => true;

  @override
  int get notificationCount => 0;

  @override
  int get highlightedNotificationCount => 0;

  @override
  int get displayNotificationCount => 0;

  @override
  int get displayHighlightedNotificationCount => 0;

  @override
  Stream<void> get onUpdate => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Room room;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    room = _Room(_Client());
  });

  MatrixActivitiesComponent listFor(HomeserverClock clock) {
    final activities = MatrixActivitiesComponent(room.client, room,
        callManager: ClientManager().callManager, clock: clock);
    room.activities = activities;
    return activities;
  }

  void member(String userId,
      {required Duration joinedAgo, Duration? writtenAgo}) {
    final joined = _serverNow().subtract(joinedAgo);
    final written =
        writtenAgo == null ? joined : _serverNow().subtract(writtenAgo);
    final key = '_${userId}_DEVICE_m.call';
    (room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] ??=
        {})[key] = matrix.Event(
      type: MatrixActivitiesComponent.callMemberStateEvent,
      eventId: '\$$key',
      senderId: userId,
      stateKey: key,
      originServerTs: written,
      room: room.matrixRoom,
      content: {
        'application': 'm.call',
        'call_id': '',
        'device_id': 'DEVICE',
        'scope': 'm.room',
        // Written again: the window runs four hours past then, from the join.
        if (writtenAgo != null) 'created_ts': joined.millisecondsSinceEpoch,
        'expires': (written.difference(joined) + const Duration(hours: 4))
            .inMilliseconds,
      },
    );
  }

  /// Alice has been in for five hours, and wrote her membership again an
  /// hour ago; Bob came two hours ago, Carol ten minutes ago.
  void hangout() {
    member('@alice:example.org',
        joinedAgo: const Duration(hours: 5),
        writtenAgo: const Duration(hours: 1));
    member('@bob:example.org', joinedAgo: const Duration(hours: 2));
    member('@carol:example.org', joinedAgo: const Duration(minutes: 10));
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: RoomTextButton(room)),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Leaves no timer behind: the list's is set for the next membership to
  /// lapse, hours away.
  Future<void> done(WidgetTester tester, MatrixActivitiesComponent list) async {
    await tester.pumpWidget(const SizedBox());
    room.matrixRoom.states.clear();
    list.getSessions();
  }

  testWidgets('everyone in the channel is under it, however long they are in',
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    hangout();

    await show(tester);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    await done(tester, list);
  });

  testWidgets(
      'people in it for hours are under it, by name, as soon as a sync '
      'says what time it is', (tester) async {
    // Just started: nothing has said what time it is yet, and this
    // machine's clock has Alice's and Bob's windows closed.
    final clock = HomeserverClock();
    final list = listFor(clock);
    hangout();

    await show(tester);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.textContaining('alice'), findsNothing);
    expect(find.textContaining('bob'), findsNothing);

    clock.readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    await tester.pump();
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    await done(tester, list);
  });
}
