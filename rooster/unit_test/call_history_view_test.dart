// The call history: fetched from the homeserver a page at a time, newest
// first, and shown a day at a time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_history_loader.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/ui/organisms/voice_activity/voice_activity_view.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const roomId = '!voice:example.org';
const alice = '@alice:example.org';
const bob = '@bob:example.org';

/// A homeserver holding [events] (oldest first) for one room's /messages.
/// Tokens are positions in [events].
class FakeHomeserver implements matrix.Client {
  FakeHomeserver(this.events);

  final List<matrix.MatrixEvent> events;
  final List<(matrix.Direction, String?)> requests = [];

  // One loader each: they are kept per account and room.
  @override
  final String? userID = '@me${_homeservers++}:example.org';

  @override
  Future<matrix.GetRoomEventsResponse> getRoomEvents(
    String roomId,
    matrix.Direction dir, {
    String? from,
    String? to,
    int? limit,
    String? filter,
  }) async {
    requests.add((dir, from));
    final n = limit ?? 10;
    if (dir == matrix.Direction.b) {
      final top = from == null ? events.length : int.parse(from);
      final bottom = (top - n).clamp(0, top);
      return matrix.GetRoomEventsResponse(
        start: '$top',
        end: bottom == 0 && top == bottom ? null : '$bottom',
        chunk: events.sublist(bottom, top).reversed.toList(),
      );
    }
    final start = int.parse(from!);
    final stop = (start + n).clamp(start, events.length);
    return matrix.GetRoomEventsResponse(
      start: '$start',
      end: stop == start ? null : '$stop',
      chunk: events.sublist(start, stop),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkRoom implements matrix.Room {
  FakeSdkRoom(this.client);
  @override
  final FakeHomeserver client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMember implements Member {
  FakeMember(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => identifier.substring(1).split(':').first;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoiceRoom implements MatrixRoom {
  FakeVoiceRoom(FakeHomeserver homeserver)
      : matrixRoom = FakeSdkRoom(homeserver);

  @override
  final FakeSdkRoom matrixRoom;
  @override
  String get identifier => roomId;
  @override
  String get displayName => 'canal de voz';
  @override
  Member getMemberOrFallback(String id) => FakeMember(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _ids = 0;
int _homeservers = 0;

/// A write of [user]'s membership at [sent], from a join at [joined] (or
/// [sent]), or their leave.
matrix.MatrixEvent membership(String user, DateTime sent,
    {DateTime? joined, bool leave = false}) {
  final joinedAt = joined ?? sent;
  return matrix.MatrixEvent(
    type: MatrixVoipRoomComponent.callMemberStateEvent,
    eventId: '\$e${_ids++}',
    senderId: user,
    stateKey: '_${user}_D1_m.call',
    originServerTs: sent,
    content: leave
        ? {}
        : {
            'application': 'm.call',
            'device_id': 'D1',
            'created_ts': joinedAt.millisecondsSinceEpoch,
            'expires': sent.difference(joinedAt).inMilliseconds + 120000,
          },
  );
}

void main() {
  group('the loader', () {
    test('pages back only as far as asked, newest first', () async {
      final now = DateTime.now();
      final events = [
        for (var h = 48; h > 0; h--)
          membership(alice, now.subtract(Duration(hours: h))),
      ];
      final homeserver = FakeHomeserver(events);
      final loader = CallHistoryLoader(homeserver, roomId);
      // ignore: invalid_use_of_visible_for_testing_member
      CallHistoryLoader.debugPageSize = 10;
      addTearDown(() {
        // ignore: invalid_use_of_visible_for_testing_member
        CallHistoryLoader.debugPageSize = null;
      });

      await loader.load(now.subtract(const Duration(hours: 15)));
      expect(loader.records, hasLength(20), reason: 'two pages of ten');
      expect(homeserver.requests, hasLength(2));

      await loader.load(now.subtract(const Duration(hours: 30)));
      expect(loader.records, hasLength(30), reason: "a third page");
    });

    test('opened again, it picks up what was written since, and no more',
        () async {
      final now = DateTime.now();
      final events = [
        membership(alice, now.subtract(const Duration(minutes: 10))),
        membership(alice, now.subtract(const Duration(minutes: 9))),
      ];
      final homeserver = FakeHomeserver(events);
      final loader = CallHistoryLoader(homeserver, roomId);
      final since = now.subtract(const Duration(hours: 1));

      await loader.load(since);
      expect(loader.records, hasLength(2));

      events.add(membership(bob, now));
      homeserver.requests.clear();
      await loader.load(since);

      expect(loader.records.map((r) => r.sender), [alice, alice, bob]);
      expect(
          homeserver.requests.every((r) => r.$1 == matrix.Direction.f), isTrue,
          reason: 'what was fetched before is not fetched again');
    });
  });

  group('the page', () {
    Future<void> show(WidgetTester tester, FakeHomeserver homeserver) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceActivityView(rooms: [FakeVoiceRoom(homeserver)]),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets("shows who was in voice today, for how long, and the call",
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Early enough in the day for any time the test runs at.
      final start = today.add(const Duration(minutes: 1));
      final homeserver = FakeHomeserver([
        membership(alice, start),
        membership(bob, start.add(const Duration(minutes: 10))),
        membership(bob, start.add(const Duration(minutes: 30)), leave: true),
        membership(alice, start.add(const Duration(minutes: 61)), leave: true),
      ]);
      if (now.isBefore(start.add(const Duration(minutes: 62)))) {
        markTestSkipped('needs the call to be over by now');
        return;
      }

      await show(tester, homeserver);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Who was in voice'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('1h 1m'), findsWidgets);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('20m'), findsOneWidget);
      expect(find.textContaining('1 call'), findsOneWidget);
      expect(find.textContaining('up to 2 at once'), findsOneWidget);
    });

    testWidgets('says so on a day with nobody in voice', (tester) async {
      await show(tester, FakeHomeserver([]));

      expect(find.text('Nobody was in voice this day'), findsOneWidget);
    });
  });

  test('durations read as hours and minutes', () {
    expect(formatCallDuration(const Duration(seconds: 30)), '<1m');
    expect(formatCallDuration(const Duration(minutes: 45)), '45m');
    expect(formatCallDuration(const Duration(hours: 2)), '2h');
    expect(formatCallDuration(const Duration(hours: 3, minutes: 26)), '3h 26m');
  });
}
