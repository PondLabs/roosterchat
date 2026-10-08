// The rail under the spaces as the user sees it (docs/whos-around-rail.md):
// a bubble per voice channel, the ones with people in them first with their
// faces, the quiet ones dimmed; "+N" past eight of them; nothing without a
// voice channel anywhere.
import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/side_navigation_bar/whos_around_rail.dart';
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

class _Room implements Room {
  _Room(this.client, this.identifier, this.displayName);

  @override
  final Client client;

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  ImageProvider? get avatar => null;

  @override
  Member getMemberOrFallback(String id) => _Member(id, _names[id] ?? id);

  @override
  Future<Member> fetchMember(String id) async => getMemberOrFallback(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

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

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = _Client('client');
    source = _Source();
    opened = [];
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
            width: 70,
            height: 700,
            // Loosely, as the space column holds it.
            child: Align(
              alignment: Alignment.topCenter,
              child: WhosAroundRail(
                source: source,
                width: 70,
                filterClient: filterClient,
                onOpen: opened.add,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder bubble(Room room) =>
      find.byKey(ValueKey("whos-around-client-${room.identifier}"));

  Finder quietBubble(Room room) =>
      find.byKey(ValueKey("whos-around-quiet-client-${room.identifier}"));

  testWidgets('a bubble per channel with people in it, with their initials',
      (tester) async {
    final lounge = room('Lounge');
    final games = room('Games');
    source.channels = [
      _live(lounge, ['@alice:example.org', '@bob:example.org']),
      _live(games, ['@carol:example.org']),
    ];
    source.voiceChannels = [lounge, games];
    await show(tester);

    expect(bubble(lounge), findsOneWidget);
    expect(bubble(games), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    // A channel with people in it is not also listed as quiet.
    expect(quietBubble(lounge), findsNothing);
    expect(quietBubble(games), findsNothing);
  });

  testWidgets("a fuller channel's fourth cell counts the rest", (tester) async {
    final lounge = room('Lounge');
    source.channels = [
      _live(lounge, _names.keys.toList(), dj: {'@alice:example.org': true}),
    ];
    await show(tester);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    // Six in the channel: three faces and the three others counted.
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('D'), findsNothing);
  });

  testWidgets('tapping a bubble opens its channel', (tester) async {
    final lounge = room('Lounge');
    source.channels = [
      _live(lounge, ['@alice:example.org'])
    ];
    await show(tester);

    await tester.tap(bubble(lounge));
    await tester.pump();

    expect(opened, [lounge]);
  });

  testWidgets(
      'the quiet channels show dimmed after the live ones, by their initial, '
      'and open on tap', (tester) async {
    final lounge = room('Lounge');
    final games = room('Games');
    final solo = room('Solo');
    source.channels = [
      _live(games, ['@alice:example.org'])
    ];
    source.voiceChannels = [lounge, games, solo];
    await show(tester);

    expect(bubble(games), findsOneWidget);
    expect(quietBubble(lounge), findsOneWidget);
    expect(quietBubble(solo), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    // Live first.
    expect(tester.getTopLeft(bubble(games)).dy,
        lessThan(tester.getTopLeft(quietBubble(lounge)).dy));
    expect(tester.getTopLeft(quietBubble(lounge)).dy,
        lessThan(tester.getTopLeft(quietBubble(solo)).dy));

    await tester.tap(quietBubble(solo));
    await tester.pump();

    expect(opened, [solo]);
  });

  testWidgets(
      'more than eight channels fold into +N, which lists who is around and '
      'then the quiet ones', (tester) async {
    final liveRooms = [
      for (final name in ['Lounge', 'Games']) room(name)
    ];
    final quietRooms = [
      for (final name in [
        'Music',
        'Movies',
        'Study',
        'Gym',
        'Kitchen',
        'Garage',
        'Attic'
      ])
        room(name)
    ];
    final house = _Space(client, 'House');
    source.channels = [
      for (final room in liveRooms) _live(room, ['@alice:example.org'])
    ];
    source.voiceChannels = [...liveRooms, ...quietRooms];
    for (final room in quietRooms) {
      source.spaces[room] = house;
    }
    await show(tester);

    // Nine channels: seven bubbles and the count of the other two.
    for (final room in liveRooms) {
      expect(bubble(room), findsOneWidget);
    }
    for (final room in quietRooms.take(5)) {
      expect(quietBubble(room), findsOneWidget);
    }
    for (final room in quietRooms.skip(5)) {
      expect(quietBubble(room), findsNothing);
    }
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(find.text('+2'));
    await tester.pump();

    expect(find.text(WhosAroundRail.labelWhosAround), findsOneWidget);
    expect(find.text(WhosAroundRail.labelPullUpAChair), findsOneWidget);
    for (final room in liveRooms) {
      expect(find.text(room.displayName), findsOneWidget);
    }
    expect(find.text(WhosAroundRail.labelPeopleInChannel(1)),
        findsNWidgets(liveRooms.length));
    expect(find.text('House'), findsWidgets);
    // The list builds its rows as they scroll into view.
    for (final room in quietRooms) {
      await tester.scrollUntilVisible(find.text(room.displayName), 60,
          scrollable: find.byType(Scrollable).last);
      expect(find.text(room.displayName), findsOneWidget);
    }

    await tester.tap(find.text('Attic'));
    await tester.pump();

    expect(opened, [quietRooms.last]);
    expect(find.text(WhosAroundRail.labelWhosAround), findsNothing);
  });

  testWidgets('nothing at all without a voice channel anywhere',
      (tester) async {
    await show(tester);

    expect(find.byType(Tooltip), findsNothing);
    expect(tester.getSize(find.byType(WhosAroundRail)), Size.zero);
  });

  testWidgets(
      'follows the source: a quiet channel lights up when someone comes in, '
      'and dims again when they leave', (tester) async {
    final lounge = room('Lounge');
    source.voiceChannels = [lounge];
    await show(tester);
    expect(quietBubble(lounge), findsOneWidget);
    expect(bubble(lounge), findsNothing);

    source.channels = [
      _live(lounge, ['@alice:example.org'])
    ];
    source.change();
    await tester.pump();

    expect(bubble(lounge), findsOneWidget);
    expect(quietBubble(lounge), findsNothing);
    expect(find.text('A'), findsOneWidget);

    source.channels = [];
    source.change();
    await tester.pump();

    expect(bubble(lounge), findsNothing);
    expect(quietBubble(lounge), findsOneWidget);
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

    expect(bubble(lounge), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(find.text('Q'), findsNothing);
  });
}
