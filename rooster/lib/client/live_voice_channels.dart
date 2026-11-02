// The voice channels with people in them right now, in every space of every
// account: what the rail under the spaces shows (docs/whos-around-rail.md).
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';

/// A voice channel with people in it right now.
class LiveVoiceChannel {
  const LiveVoiceChannel({
    required this.room,
    this.space,
    required this.participants,
    required this.liveMedia,
    required this.djPlaying,
    required this.ours,
  });

  final Room room;

  /// The space whose sidebar lists the channel, if any.
  final Space? space;

  /// Who is in it, ourselves first when we are.
  final List<String> participants;

  /// What each participant publishes, for those who reported it.
  final Map<String, Set<LiveMedia>> liveMedia;

  /// The DJ in the call's booth, and whether their music plays.
  final Map<String, bool> djPlaying;

  /// We are in this call.
  final bool ours;

  String? get dj => djPlaying.keys.firstOrNull;

  bool get musicPlaying => djPlaying.values.any((playing) => playing);

  /// Someone is sharing their screen or camera.
  bool get someoneLive => liveMedia.values.any((media) => media.isNotEmpty);

  /// What everyone in the channel publishes, screen shares first.
  Set<LiveMedia> get media => {for (final media in liveMedia.values) ...media};

  LiveVoiceChannel withSpace(Space? space) => LiveVoiceChannel(
        room: room,
        space: space,
        participants: participants,
        liveMedia: liveMedia,
        djPlaying: djPlaying,
        ours: ours,
      );

  /// The same people, badges and call as [other], in the same room.
  bool sameAs(LiveVoiceChannel other) {
    const equal = DeepCollectionEquality();
    return identical(room, other.room) &&
        ours == other.ours &&
        equal.equals(participants, other.participants) &&
        equal.equals(liveMedia, other.liveMedia) &&
        equal.equals(djPlaying, other.djPlaying);
  }
}

/// What the rail reads: the live channels, and every voice channel there is
/// to pull up a chair in when it is quiet.
abstract class LiveVoiceChannelsSource {
  /// Our own call first, then the fuller channels, then by name.
  List<LiveVoiceChannel> get channels;

  /// Every voice channel of every account, by space and then by name, with
  /// the ones outside any space last.
  List<Room> get voiceChannels;

  /// Fires once per batch of changes, after [channels] has changed.
  Stream<void> get onChanged;

  /// The space whose sidebar lists [room], if any.
  Space? spaceOf(Room room);
}

class LiveVoiceChannels implements LiveVoiceChannelsSource {
  LiveVoiceChannels(this.clientManager) {
    for (final room in clientManager.rooms) {
      _watch(room);
    }
    _subs = [
      clientManager.rooms.onAdd.listen((room) {
        _watch(room);
        _changed();
      }),
      clientManager.rooms.onRemove.listen(_forget),
      // A room's space can arrive after the room, and the list names it.
      clientManager.onSpaceAdded.listen((_) => _changed()),
      clientManager.onSpaceRemoved.listen((_) => _changed()),
      clientManager.onSpaceChildUpdated.stream.listen((_) => _changed()),
    ];
    _channels = _sorted();
  }

  final ClientManager clientManager;

  late final List<StreamSubscription> _subs;
  final Map<Room, StreamSubscription> _roomSubs = {};
  final Map<Room, ActivitiesComponent> _activities = {};
  final Map<Room, LiveVoiceChannel> _live = {};
  final StreamController<void> _onChanged = StreamController.broadcast();

  List<LiveVoiceChannel> _channels = const [];
  bool _notifyScheduled = false;
  bool _dirty = false;
  bool _disposed = false;

  @override
  List<LiveVoiceChannel> get channels => _channels;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  List<Room> get voiceChannels {
    final rooms = clientManager.rooms
        .where((room) => room.roomType == RoomType.voipRoom)
        .toList();
    final spaces = {for (final room in rooms) room: spaceOf(room)};
    int compare(Room a, Room b) {
      final spaceA = spaces[a];
      final spaceB = spaces[b];
      if ((spaceA == null) != (spaceB == null)) return spaceA == null ? 1 : -1;
      if (spaceA != null && spaceB != null && spaceA != spaceB) {
        final bySpace = spaceA.displayName
            .toLowerCase()
            .compareTo(spaceB.displayName.toLowerCase());
        if (bySpace != 0) return bySpace;
        return spaceA.identifier.compareTo(spaceB.identifier);
      }
      final byName =
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      return byName != 0 ? byName : a.identifier.compareTo(b.identifier);
    }

    return rooms..sort(compare);
  }

  @override
  Space? spaceOf(Room room) => clientManager.spaces.firstWhereOrNull((space) =>
      space.client == room.client && space.containsRoom(room.identifier));

  void _watch(Room room) {
    final activities = room.getComponent<ActivitiesComponent>();
    if (activities == null || _roomSubs.containsKey(room)) return;
    _activities[room] = activities;
    _roomSubs[room] =
        activities.onSessionsChanged.listen((_) => _refresh(room));
    _refresh(room, notify: false);
  }

  void _forget(Room room) {
    _roomSubs.remove(room)?.cancel();
    _activities.remove(room);
    if (_live.remove(room) != null) {
      _dirty = true;
      _changed();
    }
  }

  /// Reads [room]'s call again, and says so if it changed.
  void _refresh(Room room, {bool notify = true}) {
    final activities = _activities[room];
    if (activities == null) return;
    final call = activities
        .getSessions()
        .firstWhereOrNull((session) => !session.thirdparty);
    final previous = _live[room];
    if (call == null || call.participants.isEmpty) {
      if (previous == null) return;
      _live.remove(room);
    } else {
      final next = LiveVoiceChannel(
        room: room,
        participants: _usFirst(room, call.participants),
        liveMedia: {
          for (final entry in call.liveMedia.entries)
            if (entry.value.isNotEmpty) entry.key: Set.of(entry.value)
        },
        djPlaying: Map.of(call.djPlaying),
        ours: _inCall(room),
      );
      if (previous != null && previous.sameAs(next)) return;
      _live[room] = next;
    }
    _dirty = true;
    if (notify) _changed();
  }

  List<String> _usFirst(Room room, Set<String> participants) {
    final self = room.client.self?.identifier;
    return [
      if (self != null && participants.contains(self)) self,
      for (final participant in participants)
        if (participant != self) participant,
    ];
  }

  bool _inCall(Room room) =>
      clientManager.callManager.currentSessions.any((session) =>
          session.roomId == room.identifier &&
          session.client == room.client &&
          session.state != VoipState.ended);

  List<LiveVoiceChannel> _sorted() {
    final channels = [
      for (final channel in _live.values)
        channel.withSpace(spaceOf(channel.room))
    ];
    channels.sort((a, b) {
      if (a.ours != b.ours) return a.ours ? -1 : 1;
      final byCount = b.participants.length.compareTo(a.participants.length);
      if (byCount != 0) return byCount;
      final byName = a.room.displayName
          .toLowerCase()
          .compareTo(b.room.displayName.toLowerCase());
      if (byName != 0) return byName;
      return a.room.identifier.compareTo(b.room.identifier);
    });
    return channels;
  }

  static bool _sameList(List<LiveVoiceChannel> a, List<LiveVoiceChannel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].room, b[i].room) ||
          !identical(a[i].space, b[i].space)) {
        return false;
      }
    }
    return true;
  }

  /// One notification per batch of changes: a sync touches many rooms at
  /// once, and the rail needs rebuilding once.
  void _changed() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_disposed) return;
      final before = _channels;
      _channels = _sorted();
      final changed = _dirty || !_sameList(before, _channels);
      _dirty = false;
      if (changed) _onChanged.add(null);
    });
  }

  void dispose() {
    _disposed = true;
    for (final sub in _subs) {
      sub.cancel();
    }
    for (final sub in _roomSubs.values) {
      sub.cancel();
    }
    _roomSubs.clear();
    _activities.clear();
    _onChanged.close();
  }
}
