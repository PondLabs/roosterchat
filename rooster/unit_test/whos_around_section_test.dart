// The top of the Home screen's list as the user sees it
// (docs/whos-around.md): the voice channels with people in them, with a
// button to join them; the quiet ones under "Pull up a chair"; nothing
// without a voice channel anywhere, or with the setting off.
import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/home_screen/whos_around_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _names = {
  '@alice:example.org': 'Alice',
  '@bob:example.org': 'Bob',
  '@carol:example.org': 'Carol',
  '@dave:example.org': 'Dave',
  '@erin:example.org': 'Erin',
  '@frank:example.org': 'Frank',
};

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

class _Client implements Client {
  _Client(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A channel we can join.
class _Voip implements VoipRoomComponent {
  @override
  bool get canJoinCall => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.client, this.identifier, this.displayName);

  @override
  final Client client;

  @override
  final String identifier;

  @override
  final String displayName;

  final _Voip voip = _Voip();

  @override
  ImageProvider? get avatar => null;

  @override
  Member getMemberOrFallback(String id) => _Member(id, _names[id] ?? id);

  @override
  Future<Member> fetchMember(String id) async => getMemberOrFallback(id);

  @override
  T? getComponent<T extends RoomComponent>() => voip is T ? voip as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Space implements Space {
  _Space(this.client, this.displayName);

  @override
  final Client client;

  @override
  final String displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source implements LiveVoiceChannelsSource {
  @override
  List<LiveVoiceChannel> channels = [];

  @override
  List<Room> voiceChannels = [];

  final Map<Room, Space?> spaces = {};

  final StreamController<void> _changed =
      StreamController.broadcast(sync: true);

  @override
  Stream<void> get onChanged => _changed.stream;

  @override
  Space? spaceOf(Room room) => spaces[room];

  void change() => _changed.add(null);
}

LiveVoiceChannel _live(Room room, List<String> people,
        {bool ours = false, Space? space, Map<String, bool> dj = const {}}) =>
    LiveVoiceChannel(
        room: room,
        space: space,
        participants: people,
        liveMedia: const {},
        djPlaying: dj,
        ours: ours);

void main() {
  late _Client client;
  late _Source source;
  late List<Room> opened;
  late List<Room> joined;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = _Client('client');
    source = _Source();
    opened = [];
    joined = [];
  });

  _Room room(String name) =>
      _Room(client, '!${name.toLowerCase()}:example.org', name);

  Future<void> show(WidgetTester tester, {Client? filterClient}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: WhosAroundSection(
                source: source,
                filterClient: filterClient,
                onOpen: opened.add,
                onJoin: joined.add,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder row(Room room) =>
      find.byKey(ValueKey("whos-around-client-${room.identifier}"));

  Finder quietRow(Room room) =>
      find.byKey(ValueKey("whos-around-quiet-client-${room.identifier}"));

  testWidgets(
      'lists the channels with people in them, with their initials, how '
      'many, the space, and a button to join them', (tester) async {
    final lounge = room('Lounge');
    final games = room('Games');
    final house = _Space(client, 'House');
    source.channels = [
      _live(lounge, ['@alice:example.org', '@bob:example.org'], space: house),
      _live(games, ['@carol:example.org']),
    ];
    source.voiceChannels = [lounge, games];
    await show(tester);

    expect(find.text(WhosAroundSection.labelWhosAround), findsOneWidget);
    expect(row(lounge), findsOneWidget);
    expect(row(games), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('House · 2 people'), findsOneWidget);
    expect(find.text('1 person'), findsOneWidget);
    // A channel with people in it is not also listed as quiet.
    expect(find.text(WhosAroundSection.labelPullUpAChair), findsNothing);
    expect(quietRow(lounge), findsNothing);

    await tester.tap(find.descendant(
        of: row(games), matching: find.text(WhosAroundSection.labelJoinCall)));
    await tester.pump();
    expect(joined, [games]);

    await tester.tap(find.text('Lounge'));
    await tester.pump();
    expect(opened, [lounge]);
  });

  testWidgets('the call we are in says so instead of offering to join',
      (tester) async {
    final lounge = room('Lounge');
    source.channels = [
      _live(lounge, ['@me:example.org', '@alice:example.org'], ours: true)
    ];
    await show(tester);

    expect(find.text(WhosAroundSection.labelYouAreInHere), findsOneWidget);
    expect(find.text(WhosAroundSection.labelJoinCall), findsNothing);
  });

  testWidgets("a fuller channel's fourth cell counts the rest", (tester) async {
    final lounge = room('Lounge');
    source.channels = [
      _live(lounge, _names.keys.toList(), dj: {'@alice:example.org': true}),
    ];
    await show(tester);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('D'), findsNothing);
    expect(find.text('6 people'), findsOneWidget);
  });

  testWidgets(
      'the quiet channels follow under "Pull up a chair", five at a time, '
      'and open on tap', (tester) async {
    final rooms = [
      for (final name in [
        'Lounge',
        'Games',
        'Music',
        'Movies',
        'Study',
        'Gym',
        'Attic'
      ])
        room(name)
    ];
    final house = _Space(client, 'House');
    source.voiceChannels = rooms;
    for (final room in rooms) {
      source.spaces[room] = house;
    }
    await show(tester);

    expect(find.text(WhosAroundSection.labelWhosAround), findsNothing);
    expect(find.text(WhosAroundSection.labelPullUpAChair), findsOneWidget);
    for (final room in rooms.take(5)) {
      expect(quietRow(room), findsOneWidget);
    }
    for (final room in rooms.skip(5)) {
      expect(quietRow(room), findsNothing);
    }
    expect(find.text(WhosAroundSection.labelMoreChannels(2)), findsOneWidget);
    expect(find.text(WhosAroundSection.labelJoinCall), findsNothing);

    await tester.tap(find.text(WhosAroundSection.labelMoreChannels(2)));
    await tester.pump();

    for (final room in rooms) {
      expect(quietRow(room), findsOneWidget);
    }
    expect(find.text(WhosAroundSection.labelMoreChannels(2)), findsNothing);

    await tester.tap(find.text('Attic'));
    await tester.pump();
    expect(opened, [rooms.last]);
  });

  testWidgets('nothing without a voice channel anywhere', (tester) async {
    await show(tester);

    expect(tester.getSize(find.byType(WhosAroundSection)).height, 0);
  });

  testWidgets('nothing with the setting off', (tester) async {
    final lounge = room('Lounge');
    source.channels = [
      _live(lounge, ['@alice:example.org'])
    ];
    await preferences.showWhosAround.set(false);
    await show(tester);

    expect(tester.getSize(find.byType(WhosAroundSection)).height, 0);

    await preferences.showWhosAround.set(true);
    // The change reaches the section's listener a microtask later.
    await tester.pumpAndSettle();

    expect(row(lounge), findsOneWidget);
  });

  testWidgets(
      'follows the source: a quiet channel moves up when someone comes in, '
      'and back when they leave', (tester) async {
    final lounge = room('Lounge');
    source.voiceChannels = [lounge];
    await show(tester);
    expect(quietRow(lounge), findsOneWidget);
    expect(row(lounge), findsNothing);

    source.channels = [
      _live(lounge, ['@alice:example.org'])
    ];
    source.change();
    await tester.pump();

    expect(row(lounge), findsOneWidget);
    expect(quietRow(lounge), findsNothing);
    expect(find.text('A'), findsOneWidget);

    source.channels = [];
    source.change();
    await tester.pump();

    expect(row(lounge), findsNothing);
    expect(quietRow(lounge), findsOneWidget);
  });

  testWidgets("lists one account's channels while accounts are not mixed",
      (tester) async {
    final other = _Client('other');
    final lounge = room('Lounge');
    final theirs = _Room(other, '!theirs:example.org', 'Theirs');
    final theirQuiet = _Room(other, '!quiet:example.org', 'Quiet');
    source.channels = [
      _live(lounge, ['@alice:example.org']),
      _live(theirs, ['@bob:example.org']),
    ];
    source.voiceChannels = [lounge, theirs, theirQuiet];
    await show(tester, filterClient: client);

    expect(row(lounge), findsOneWidget);
    expect(find.text('Theirs'), findsNothing);
    expect(find.text('Quiet'), findsNothing);
  });
}
