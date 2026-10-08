// The voice channel's row in the sidebar, as the user sees it: every name in
// the channel under it. People who had been in it for a while were missing
// (the channel looked empty, or had only whoever came in last), because
// their memberships were read against this machine's clock, hours ahead of
// the homeserver's here.
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voice_channel_status/voice_channel_status_component.dart';
import 'package:rooster/client/matrix/components/room_activities/matrix_activities_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/permissions.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/room_text_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const _roomId = '!hangout:example.org';
const _me = '@me:example.org';

final _names = {
  '@alice:example.org': 'Alice',
  '@bob:example.org': 'Bob',
  '@carol:example.org': 'Carol',
  // A full channel.
  for (var i = 1; i <= 12; i++) '@guest$i:example.org': 'Guest $i',
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

class _Permissions extends Permissions {}

class _Status implements VoiceChannelStatusComponent {
  _Status(this.status, {this.canSetStatus = true});

  @override
  final String? status;

  @override
  final bool canSetStatus;

  @override
  Stream<void> get onChanged => const Stream.empty();

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

  RoomComponent? status;

  final Set<String> fetched = {};

  @override
  T? getComponent<T extends RoomComponent>() {
    for (final component in [activities, status]) {
      if (component is T) return component;
    }
    return null;
  }

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
  Permissions get permissions => _Permissions();

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
      {required Duration joinedAgo,
      String deviceId = 'DEVICE',
      Duration? writtenAgo,
      Map<String, Object?> says = const {}}) {
    final joined = _serverNow().subtract(joinedAgo);
    final written =
        writtenAgo == null ? joined : _serverNow().subtract(writtenAgo);
    final key = '_${userId}_${deviceId}_m.call';
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
        'device_id': deviceId,
        'scope': 'm.room',
        // Written again: the window runs four hours past then, from the join.
        if (writtenAgo != null) 'created_ts': joined.millisecondsSinceEpoch,
        'expires': (written.difference(joined) + const Duration(hours: 4))
            .inMilliseconds,
        ...says,
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

  // Asked for with a screenshot of the list: who is live, muted or
  // deafened showed only to people already in the call. On a homeserver
  // without delayed events their clients never published it.
  testWidgets('who is live, on camera, muted or deafened shows before joining',
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    const unguarded = {'chat.commet.unguarded': true};
    member('@alice:example.org', joinedAgo: const Duration(minutes: 30), says: {
      ...unguarded,
      'chat.commet.streams': ['screen'],
      'chat.commet.voice_state': ['muted'],
    });
    member('@bob:example.org', joinedAgo: const Duration(minutes: 20), says: {
      ...unguarded,
      'chat.commet.streams': ['camera'],
      'chat.commet.voice_state': ['muted', 'deafened'],
    });
    member('@carol:example.org', joinedAgo: const Duration(minutes: 10));

    await show(tester);

    // Their own row: the channel's button is around all of them.
    Finder inRow(String name, Finder what) => find.descendant(
        of: find
            .ancestor(
                of: find.text(name), matching: find.byType(tiamat.TextButton))
            .first,
        matching: what);

    expect(inRow('Alice', find.text('LIVE')), findsOneWidget);
    expect(inRow('Alice', find.byIcon(Icons.mic_off_rounded)), findsOneWidget);
    expect(inRow('Bob', find.byIcon(Icons.videocam_rounded)), findsOneWidget);
    expect(
        inRow('Bob', find.byIcon(Icons.headset_off_rounded)), findsOneWidget);
    expect(inRow('Carol', find.byType(Icon)), findsNothing);
    expect(inRow('Carol', find.text('LIVE')), findsNothing);
    await done(tester, list);
  });

  for (final oldFirst in [true, false]) {
    testWidgets(
        'an older device cannot hide a deafened member (old first: $oldFirst)',
        (tester) async {
      final clock = HomeserverClock()
        ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
      final list = listFor(clock);
      void oldDevice() => member('@bob:example.org',
          deviceId: 'OLD',
          joinedAgo: const Duration(minutes: 30),
          // A heartbeat rewrites the old device more recently than the new
          // device's deafen. Its join is still the older one.
          writtenAgo: Duration.zero,
          says: {'chat.commet.voice_state': <String>[]});
      void currentDevice() => member('@bob:example.org',
              deviceId: 'CURRENT',
              joinedAgo: const Duration(minutes: 5),
              writtenAgo: const Duration(seconds: 30),
              says: {
                'chat.commet.voice_state': ['muted', 'deafened'],
              });
      if (oldFirst) {
        oldDevice();
        currentDevice();
      } else {
        currentDevice();
        oldDevice();
      }

      await show(tester);

      expect(find.text('Bob'), findsOneWidget);
      expect(find.byIcon(Icons.headset_off_rounded), findsOneWidget);
      await done(tester, list);
    });
  }

  testWidgets('deafen changes refresh an open sidebar before joining',
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    member('@bob:example.org', joinedAgo: const Duration(minutes: 5));
    await show(tester);
    expect(find.byIcon(Icons.headset_off_rounded), findsNothing);
    matrix.Event currentMembership() =>
        room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent]![
            '_@bob:example.org_DEVICE_m.call'] as matrix.Event;

    member('@bob:example.org',
        joinedAgo: const Duration(minutes: 5),
        writtenAgo: Duration.zero,
        says: {
          'chat.commet.voice_state': ['muted', 'deafened'],
        });
    list.onSync(matrix.JoinedRoomUpdate(state: [
      currentMembership(),
    ]));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.headset_off_rounded), findsOneWidget);

    member('@bob:example.org',
        joinedAgo: const Duration(minutes: 5),
        writtenAgo: Duration.zero,
        says: {'chat.commet.voice_state': <String>[]});
    list.onSync(matrix.JoinedRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [currentMembership()])));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.headset_off_rounded), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    await done(tester, list);
  });

  group('a channel with more people than the list has rows for', () {
    void guests(int count, {int? live}) {
      for (var i = 1; i <= count; i++) {
        member('@guest$i:example.org',
            joinedAgo: Duration(minutes: 60 - i),
            says: {
              if (i == live) 'chat.commet.streams': ['screen'],
            });
      }
    }

    testWidgets('lists everyone while they fit', (tester) async {
      final clock = HomeserverClock()
        ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
      final list = listFor(clock);
      guests(RoomTextButton.maxVisibleMembers);

      await show(tester);

      for (var i = 1; i <= RoomTextButton.maxVisibleMembers; i++) {
        expect(find.text('Guest $i'), findsOneWidget);
      }
      expect(find.textContaining('more'), findsNothing);
      await done(tester, list);
    });

    testWidgets('shows the first of them, and the rest behind "and N more"',
        (tester) async {
      final clock = HomeserverClock()
        ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
      final list = listFor(clock);
      guests(12);

      await show(tester);

      for (var i = 1; i <= 7; i++) {
        expect(find.text('Guest $i'), findsOneWidget);
      }
      for (var i = 8; i <= 12; i++) {
        expect(find.text('Guest $i'), findsNothing);
      }
      expect(find.text('and 5 more'), findsOneWidget);

      await tester.tap(find.text('and 5 more'));
      await tester.pump();
      await tester.pump();

      // Nobody is left out: the rest are a tap away, by name.
      for (var i = 1; i <= 12; i++) {
        expect(find.text('Guest $i'), findsOneWidget);
      }

      // And it closes again.
      await tester.tapAt(const Offset(700, 500));
      await tester.pump();
      expect(find.text('Guest 12'), findsNothing);
      await done(tester, list);
    });

    testWidgets('keeps whoever is live among the ones shown', (tester) async {
      final clock = HomeserverClock()
        ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
      final list = listFor(clock);
      guests(12, live: 11);

      await show(tester);

      expect(find.text('Guest 11'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      // Everyone else keeps their place; the last of the seven makes room.
      expect(find.text('Guest 6'), findsOneWidget);
      expect(find.text('Guest 7'), findsNothing);
      expect(find.text('and 5 more'), findsOneWidget);
      await done(tester, list);
    });
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

  testWidgets("a voice channel's status shows under its name, to everyone",
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    room.status = _Status('Movie night', canSetStatus: false);
    hangout();

    await show(tester);

    expect(find.text('Movie night'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    await done(tester, list);
  });

  testWidgets('outside the call there is nothing to set a status with',
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    room.status = _Status(null);
    hangout();

    await show(tester);

    expect(find.text('Set a channel status'), findsNothing);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    await done(tester, list);
  });

  testWidgets("the channel's buttons show under the pointer, not before",
      (tester) async {
    final clock = HomeserverClock()
      ..readSync(_syncAt(_serverNow()), homeserver: 'example.org');
    final list = listFor(clock);
    hangout();

    await show(tester);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Hangout')));
    await tester.pump();

    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    // Over someone in the channel: those are the channel's, not theirs.
    await mouse.moveTo(tester.getCenter(find.text('Alice')));
    await tester.pump();
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
    await done(tester, list);
  });
}
