// The list behind the rail under the spaces (docs/whos-around-rail.md): the
// voice channels with people in them, across every room of every account,
// kept up to date from the same activity sessions the sidebar lists under
// a channel.
import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/utils/image_or_icon.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';

const _me = '@me:example.org';

class _Profile implements Profile {
  _Profile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  _Client(this.identifier);

  @override
  final String identifier;

  @override
  Profile? self = _Profile(_me);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A room's activities, told what to say rather than read from state.
class _Activities implements ActivitiesComponent {
  List<RoomActivitySession> sessions = [];

  final StreamController<void> _changed = StreamController.broadcast();

  @override
  List<RoomActivitySession> getSessions() => sessions;

  @override
  Stream<void> get onSessionsChanged => _changed.stream;

  void say(List<RoomActivitySession> sessions) {
    this.sessions = sessions;
    _changed.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.client, this.identifier, this.displayName,
      {this.roomType = RoomType.voipRoom});

  @override
  final Client client;

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  final RoomType roomType;

  final _Activities activities = _Activities();

  @override
  T? getComponent<T extends RoomComponent>() =>
      activities is T ? activities as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Space implements Space {
  _Space(this.client, this.identifier, this.displayName, this.roomIds);

  @override
  final Client client;

  @override
  final String identifier;

  @override
  final String displayName;

  final Set<String> roomIds;

  @override
  bool containsRoom(String identifier) => roomIds.contains(identifier);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.client, this.roomId);

  @override
  final Client client;

  @override
  final String roomId;

  @override
  VoipState get state => VoipState.connected;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RoomActivitySession _call(Set<String> people,
    {Map<String, bool> dj = const {},
    Map<String, Set<LiveMedia>> live = const {}}) {
  final session = RoomActivitySession(
      participants: people,
      application: 'm.call',
      icon: ImageOrIcon(icon: Icons.call),
      thirdparty: false);
  session.djPlaying.addAll(dj);
  session.liveMedia.addAll(live);
  return session;
}

RoomActivitySession _widget(Set<String> people) => RoomActivitySession(
    participants: people,
    application: 'io.element.widget',
    icon: ImageOrIcon(icon: Icons.widgets),
    thirdparty: true);

void main() {
  late ClientManager manager;
  late _Client client;

  setUp(() {
    manager = ClientManager();
    client = _Client('client');
  });

  /// The change notification is a microtask away.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  List<String> names(LiveVoiceChannels live) =>
      [for (final channel in live.channels) channel.room.displayName];

  _Room room(String name, {List<RoomActivitySession>? says}) {
    final room = _Room(client, '!${name.toLowerCase()}:example.org', name);
    if (says != null) room.activities.sessions = says;
    manager.rooms.add(room);
    return room;
  }

  test(
      'lists the channels with people in a call, the fuller ones first, by '
      'name among equals', () {
    room('Lounge', says: [
      _call({'@a:x', '@b:x'})
    ]);
    room('Games', says: [
      _call({'@a:x', '@b:x', '@c:x'})
    ]);
    // Nobody left in the call, a call-less room, and a widget's session.
    room('Empty', says: [_call({})]);
    room('Quiet');
    room('Board', says: [
      _widget({'@a:x'})
    ]);
    room('Arcade', says: [
      _call({'@x:x', '@y:x'})
    ]);

    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);

    expect(names(live), ['Games', 'Arcade', 'Lounge']);
  });

  test('our own call comes first, and we come first in it', () async {
    final lounge = room('Lounge', says: [
      _call({'@a:x', _me, '@b:x'})
    ]);
    room('Games', says: [
      _call({'@a:x', '@b:x', '@c:x'})
    ]);
    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);
    expect(names(live), ['Games', 'Lounge']);
    expect(live.channels.last.ours, isFalse);

    manager.callManager.currentSessions
        .add(_Session(client, lounge.identifier));
    // The real component says so itself when our session registers.
    lounge.activities.say(lounge.activities.sessions);
    await settle();

    expect(names(live), ['Lounge', 'Games']);
    expect(live.channels.first.ours, isTrue);
    expect(live.channels.first.participants, [_me, '@a:x', '@b:x']);
  });

  test(
      'a channel joins the list when someone comes in and leaves it when the '
      'last one goes, one change each', () async {
    final quiet = room('Quiet');
    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);
    final changes = <void>[];
    live.onChanged.listen(changes.add);
    expect(live.channels, isEmpty);

    quiet.activities.say([
      _call({'@a:x'})
    ]);
    // Said again with nothing new: not a change.
    quiet.activities.say([
      _call({'@a:x'})
    ]);
    await settle();
    expect(changes, hasLength(1));
    expect(names(live), ['Quiet']);

    // Badges are what the bubble shows: a DJ starting is a change.
    quiet.activities.say([
      _call({'@a:x'}, dj: {'@a:x': true})
    ]);
    await settle();
    expect(changes, hasLength(2));
    expect(live.channels.single.dj, '@a:x');
    expect(live.channels.single.musicPlaying, isTrue);

    quiet.activities.say([_call({})]);
    await settle();
    expect(changes, hasLength(3));
    expect(live.channels, isEmpty);
  });

  test('a room that arrives later is watched, and one that goes is dropped',
      () async {
    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);
    final changes = <void>[];
    live.onChanged.listen(changes.add);

    final lounge = room('Lounge', says: [
      _call({'@a:x'})
    ]);
    await settle();
    expect(names(live), ['Lounge']);
    expect(changes, hasLength(1));

    lounge.activities.say([
      _call({'@a:x', '@b:x'})
    ]);
    await settle();
    expect(live.channels.single.participants, hasLength(2));
    expect(changes, hasLength(2));

    manager.rooms.remove(lounge);
    await settle();
    expect(live.channels, isEmpty);
    expect(changes, hasLength(3));

    // Gone: whatever it says now is nobody's business.
    lounge.activities.say([
      _call({'@a:x', '@b:x', '@c:x'})
    ]);
    await settle();
    expect(live.channels, isEmpty);
    expect(changes, hasLength(3));
  });

  test('names the space that lists the channel, even one that arrives later',
      () async {
    final lounge = room('Lounge', says: [
      _call({'@a:x'})
    ]);
    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);
    expect(live.channels.single.space, isNull);

    final house =
        _Space(client, '!house:example.org', 'House', {lounge.identifier});
    manager.spaces.add(house);
    await settle();

    expect(live.channels.single.space, same(house));
    expect(live.spaceOf(lounge), same(house));
  });

  test(
      'the voice channels to pull up a chair in go by space, then by name, '
      'with the ones outside any space last', () {
    final zulu = room('Zulu');
    final alpha = room('Alpha');
    final beta = room('Beta');
    room('Solo');
    room('Chat', says: null).activities.sessions = [];
    final text = _Room(client, '!text:example.org', 'Text',
        roomType: RoomType.defaultRoom);
    manager.rooms.add(text);
    manager.spaces.add(_Space(client, '!house:example.org', 'House',
        {zulu.identifier, alpha.identifier}));
    manager.spaces
        .add(_Space(client, '!attic:example.org', 'Attic', {beta.identifier}));

    final live = LiveVoiceChannels(manager);
    addTearDown(live.dispose);

    expect([for (final room in live.voiceChannels) room.displayName],
        ['Beta', 'Alpha', 'Zulu', 'Chat', 'Solo']);
  });

  test('nothing changes after dispose', () async {
    final lounge = room('Lounge');
    final live = LiveVoiceChannels(manager);
    final changes = <void>[];
    live.onChanged.listen(changes.add);
    live.dispose();

    lounge.activities.say([
      _call({'@a:x'})
    ]);
    room('Games', says: [
      _call({'@b:x'})
    ]);
    await settle();

    expect(changes, isEmpty);
    expect(live.channels, isEmpty);
  });
}
