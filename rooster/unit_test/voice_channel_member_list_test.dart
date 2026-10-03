import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/matrix/components/room_activities/matrix_activities_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

// Issue #10: after joining a voice channel our own user was missing from the
// sidebar list because the sync with our call membership can arrive before
// the LiveKit session is registered with CallManager. These tests drive the
// component through its public seams: getSessions() and onSessionsChanged.

const selfUserId = "@me:example.org";
const selfDeviceId = "DEVICEA";
const otherUserId = "@other:example.org";
const roomId = "!voice:example.org";

class FakeProfile implements Profile {
  @override
  final String identifier;
  FakeProfile(this.identifier);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkClient implements matrix.Client {
  @override
  final String? deviceID;
  @override
  final String? userID;
  FakeSdkClient(this.deviceID, this.userID);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixClient implements MatrixClient {
  @override
  Profile? self = FakeProfile(selfUserId);

  final FakeSdkClient _sdk = FakeSdkClient(selfDeviceId, selfUserId);

  @override
  matrix.Client get matrixClient => _sdk;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkRoom implements matrix.Room {
  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  String get id => roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixRoom implements MatrixRoom {
  @override
  final String identifier;
  final FakeSdkRoom _sdk = FakeSdkRoom();

  FakeMatrixRoom(this.identifier);

  @override
  matrix.Room get matrixRoom => _sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoipSession implements VoipSession, CallRoster {
  @override
  final Client client;
  @override
  final String roomId;
  @override
  final String sessionId;

  FakeVoipSession(this.client, this.roomId, this.sessionId);

  @override
  final List<VoipStream> streams = [];

  /// Who is connected to the call, streams or not.
  final Set<String> connected = {};

  @override
  Set<String> get connectedUserIds => connected;

  final StreamController<void> _stateChanged =
      StreamController.broadcast(sync: true);

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  void connect(String userId) {
    connected.add(userId);
    _stateChanged.add(null);
  }

  void publish(String userId, VoipStreamType type,
      {bool muted = false, bool deafened = false}) {
    streams.add(
        FakeVoipStream(userId, type, isMuted: muted, isDeafened: deafened));
    _stateChanged.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoipStream implements VoipStream {
  @override
  final String streamUserId;
  @override
  final VoipStreamType type;
  @override
  final bool isMuted;
  @override
  final bool isDeafened;

  FakeVoipStream(this.streamUserId, this.type,
      {this.isMuted = false, this.isDeafened = false});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

matrix.StrippedStateEvent callMembership(String userId, String deviceId) {
  return matrix.StrippedStateEvent(
    type: MatrixActivitiesComponent.callMemberStateEvent,
    senderId: userId,
    stateKey: "_${userId}_${deviceId}_m.call",
    content: {
      "application": "m.call",
      "call_id": "",
      "device_id": deviceId,
      "scope": "m.room",
    },
  );
}

/// A membership as it arrives from sync: a full event with a timestamp.
matrix.Event callMemberEvent(
  FakeMatrixRoom room,
  String userId,
  String deviceId, {
  List<Object?>? streams,
  List<Object?>? voiceState,
  DateTime? sentAt,
  Map<String, Object?> extra = const {},
}) {
  return matrix.Event(
    type: MatrixActivitiesComponent.callMemberStateEvent,
    eventId: "\$member-$userId-$deviceId",
    senderId: userId,
    stateKey: "_${userId}_${deviceId}_m.call",
    originServerTs: sentAt ?? DateTime.now(),
    room: room.matrixRoom,
    content: {
      "application": "m.call",
      "call_id": "",
      "device_id": deviceId,
      "scope": "m.room",
      "expires": 14400000,
      if (streams != null) "chat.commet.streams": streams,
      if (voiceState != null) "chat.commet.voice_state": voiceState,
      ...extra,
    },
  );
}

const homeserver = "example.org";

/// The homeserver's time: three hours behind this machine's clock.
DateTime serverNow() => DateTime.now().subtract(const Duration(hours: 3));

/// A sync the homeserver answered at [at], by its clock.
matrix.SyncUpdate syncFromHomeserver(DateTime at) {
  return matrix.SyncUpdate(
    nextBatch: "next",
    rooms: matrix.RoomsUpdate(join: {
      roomId: matrix.JoinedRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [
          matrix.MatrixEvent(
            type: "m.room.message",
            content: const {"body": "hi"},
            senderId: otherUserId,
            eventId: r"$message",
            originServerTs: at,
            unsigned: const {"age": 0},
          ),
        ]),
      ),
    }),
  );
}

RoomActivitySession callSession(MatrixActivitiesComponent component) =>
    component.getSessions().singleWhere((s) => s.application == "m.call");

Set<String> callParticipants(MatrixActivitiesComponent component) {
  final call =
      component.getSessions().where((s) => s.application == "m.call").toList();
  if (call.isEmpty) return {};
  return call.single.participants;
}

void main() {
  late FakeMatrixClient client;
  late FakeMatrixRoom room;
  late ClientManager clientManager;
  late MatrixActivitiesComponent component;

  setUp(() {
    client = FakeMatrixClient();
    room = FakeMatrixRoom(roomId);
    clientManager = ClientManager();
    component = MatrixActivitiesComponent(client, room,
        callManager: clientManager.callManager);

    // Membership sync has arrived for both users, but our LiveKit session is
    // not registered with CallManager yet.
    final selfMembership = callMembership(selfUserId, selfDeviceId);
    final otherMembership = callMembership(otherUserId, "DEVICEB");
    room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
      selfMembership.stateKey!: selfMembership,
      otherMembership.stateKey!: otherMembership,
    };
  });

  group("Voice channel member list", () {
    test("own membership is hidden while no call session is registered", () {
      expect(callParticipants(component), equals({otherUserId}));
    });

    test(
        "own user appears and the list refreshes once the call session is registered",
        () async {
      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      clientManager.callManager.currentSessions
          .add(FakeVoipSession(client, roomId, "session-1"));
      await Future<void>.delayed(Duration.zero);

      expect(changes, hasLength(1));
      expect(callParticipants(component), equals({selfUserId, otherUserId}));
    });

    test("leaving the call refreshes the list and hides own stale membership",
        () async {
      final session = FakeVoipSession(client, roomId, "session-1");
      clientManager.callManager.currentSessions.add(session);

      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      clientManager.callManager.currentSessions.remove(session);
      await Future<void>.delayed(Duration.zero);

      expect(changes, hasLength(1));
      expect(callParticipants(component), equals({otherUserId}));
    });

    test("sessions in other rooms do not refresh this room's list", () async {
      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      clientManager.callManager.currentSessions
          .add(FakeVoipSession(client, "!elsewhere:example.org", "session-2"));
      await Future<void>.delayed(Duration.zero);

      expect(changes, isEmpty);
      expect(callParticipants(component), equals({otherUserId}));
    });

    test(
        "someone connected to our call stays listed after their membership "
        "lapses", () {
      // Their delayed leave fired, clearing the membership, but they are
      // still in the LiveKit room with us.
      final selfMembership = callMembership(selfUserId, selfDeviceId);
      room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
        selfMembership.stateKey!: selfMembership,
      };
      final session = FakeVoipSession(client, roomId, "session-1")
        ..publish(selfUserId, VoipStreamType.audio)
        ..publish(otherUserId, VoipStreamType.audio);
      clientManager.callManager.currentSessions.add(session);

      expect(callParticipants(component), equals({selfUserId, otherUserId}));
    });

    test("our call is listed even with no membership state at all", () {
      room.matrixRoom.states
          .remove(MatrixActivitiesComponent.callMemberStateEvent);
      final session = FakeVoipSession(client, roomId, "session-1")
        ..publish(selfUserId, VoipStreamType.audio)
        ..publish(otherUserId, VoipStreamType.audio);
      clientManager.callManager.currentSessions.add(session);

      expect(callParticipants(component), equals({selfUserId, otherUserId}));
    });

    test("with no membership state and nobody connected, nothing is listed",
        () {
      room.matrixRoom.states
          .remove(MatrixActivitiesComponent.callMemberStateEvent);
      clientManager.callManager.currentSessions
          .add(FakeVoipSession(client, roomId, "session-1"));

      expect(component.getSessions(), isEmpty);
    });
  });

  group("Live badges (issue #9)", () {
    const thirdUserId = "@third:example.org";

    void setMemberships(List<matrix.StrippedStateEvent> memberships) {
      room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
        for (final m in memberships) m.stateKey!: m,
      };
    }

    test("a member who reports a screen share is live", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", streams: ["screen"]),
      ]);

      expect(callSession(component).liveMedia[otherUserId], {LiveMedia.screen});
    });

    test("a member's devices are combined", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "PHONE", streams: ["camera"]),
        callMemberEvent(room, otherUserId, "LAPTOP", streams: ["screen"]),
      ]);

      expect(callSession(component).liveMedia[otherUserId],
          {LiveMedia.screen, LiveMedia.camera});
    });

    test("streams in stripped state, which never expires, are ignored", () {
      final stripped = callMembership(otherUserId, "DEVICEB")
        ..content["chat.commet.streams"] = ["screen"];
      setMemberships([stripped]);

      expect(callParticipants(component), {otherUserId});
      expect(callSession(component).liveMedia[otherUserId], isNull);
    });

    test("an expired membership is not listed, counted from its join time", () {
      // Rewritten a minute ago, but joined five hours ago with a 4 h window.
      final joined = DateTime.now().subtract(const Duration(hours: 5));
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            streams: ["screen"],
            sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
            extra: {"created_ts": joined.millisecondsSinceEpoch}),
      ]);

      expect(callParticipants(component), isEmpty);
    });

    test("a membership drops off the list when it lapses, with no event",
        () async {
      // Their client died without leaving: nothing ever arrives over sync.
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", extra: {"expires": 50}),
        callMemberEvent(room, thirdUserId, "DEVICEC"),
      ]);
      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      expect(callParticipants(component), {otherUserId, thirdUserId});
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(changes, hasLength(1));
      expect(callParticipants(component), {thirdUserId});
    });

    test("in our call, LiveKit decides who is live", () {
      setMemberships([
        callMemberEvent(room, selfUserId, selfDeviceId, streams: []),
        // Stopped sharing a moment ago; the membership hasn't caught up.
        callMemberEvent(room, otherUserId, "DEVICEB", streams: ["screen"]),
        // Not in our LiveKit room (e.g. another SFU): state is all we have.
        callMemberEvent(room, thirdUserId, "DEVICEC", streams: ["camera"]),
      ]);
      final session = FakeVoipSession(client, roomId, "session-1")
        ..publish(otherUserId, VoipStreamType.audio)
        ..publish(selfUserId, VoipStreamType.screenshare)
        ..publish(selfUserId, VoipStreamType.video);
      clientManager.callManager.currentSessions.add(session);

      final live = callSession(component).liveMedia;
      expect(live[selfUserId], {LiveMedia.screen, LiveMedia.camera});
      expect(live[otherUserId], isEmpty);
      expect(live[thirdUserId], {LiveMedia.camera});
    });

    test("the list refreshes when a stream in our call starts", () async {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", streams: []),
      ]);
      final session = FakeVoipSession(client, roomId, "session-1");
      clientManager.callManager.currentSessions.add(session);

      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      session.publish(otherUserId, VoipStreamType.screenshare);
      await Future<void>.delayed(Duration.zero);

      expect(changes, isNotEmpty);
      expect(callSession(component).liveMedia[otherUserId], {LiveMedia.screen});
    });

    test("a membership that arrives as state refreshes the list", () async {
      // A limited sync delivers state changes outside the timeline.
      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      component.onSync(matrix.JoinedRoomUpdate(state: [
        matrix.MatrixEvent(
          type: MatrixActivitiesComponent.callMemberStateEvent,
          content: const {},
          senderId: otherUserId,
          stateKey: "_${otherUserId}_DEVICEB_m.call",
          eventId: r"$left",
          originServerTs: DateTime.now(),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);

      expect(changes, hasLength(1));
    });
  });

  // A client with no delayed leave (a homeserver without delayed events)
  // publishes its streams and its mute all the same, marked as unguarded:
  // if it dies they are only believed for as long as it would have taken to
  // write them again.
  group("Badges of a member without a delayed leave", () {
    const unguarded = {"chat.commet.unguarded": true};

    void setMemberships(List<matrix.StrippedStateEvent> memberships) {
      room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
        for (final m in memberships) m.stateKey!: m,
      };
    }

    test("show to people outside the call while they are kept written", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            streams: ["screen", "camera"],
            voiceState: ["muted", "deafened"],
            sentAt: DateTime.now().subtract(const Duration(minutes: 61)),
            extra: unguarded),
      ]);

      final call = callSession(component);
      expect(call.liveMedia[otherUserId], {LiveMedia.screen, LiveMedia.camera});
      expect(call.voiceState[otherUserId],
          {VoiceState.muted, VoiceState.deafened});
    });

    test("are dropped once nobody has written them for ninety minutes", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            streams: ["screen"],
            voiceState: ["muted"],
            sentAt: DateTime.now().subtract(const Duration(minutes: 91)),
            extra: {
              ...unguarded,
              "chat.commet.dj": {"playing": true}
            }),
      ]);

      final call = callSession(component);
      expect(call.participants, {otherUserId},
          reason: "still in the call until the membership itself lapses");
      expect(call.liveMedia[otherUserId], isNull);
      expect(call.voiceState[otherUserId], isNull);
      expect(call.djPlaying[otherUserId], isNull);
    });

    test("stay for one whose delayed leave guards them, however old", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            streams: ["screen"],
            sentAt: DateTime.now().subtract(const Duration(hours: 3))),
      ]);

      expect(callSession(component).liveMedia[otherUserId], {LiveMedia.screen});
    });

    test("go when they turn stale, with no event", () async {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            streams: ["screen"],
            sentAt: DateTime.now().subtract(
                MatrixCallMembership.unguardedStateLifetime -
                    const Duration(milliseconds: 50)),
            extra: unguarded),
      ]);
      final changes = <void>[];
      final sub = component.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      expect(callSession(component).liveMedia[otherUserId], {LiveMedia.screen});
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(changes, hasLength(1));
      expect(callSession(component).liveMedia[otherUserId], isNull);
      expect(callParticipants(component), {otherUserId});
    });
  });

  group("Muted and deafened icons", () {
    const thirdUserId = "@third:example.org";

    void setMemberships(List<matrix.StrippedStateEvent> memberships) {
      room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
        for (final m in memberships) m.stateKey!: m,
      };
    }

    test("a member who reports being muted is muted", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", voiceState: ["muted"]),
      ]);

      expect(
          callSession(component).voiceState[otherUserId], {VoiceState.muted});
    });

    test("a deafened member reads as muted too", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", voiceState: ["deafened"]),
      ]);

      expect(callSession(component).voiceState[otherUserId],
          {VoiceState.muted, VoiceState.deafened});
    });

    test("a member who reports being unmuted has an empty state, not null", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", voiceState: []),
      ]);

      expect(callSession(component).voiceState[otherUserId], isEmpty);
    });

    test("a client that says nothing about it gets no icon", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", streams: ["screen"]),
      ]);

      expect(callSession(component).voiceState[otherUserId], isNull);
    });

    test("in our call, LiveKit decides who is muted", () {
      setMemberships([
        // Unmuted a moment ago; the membership hasn't caught up.
        callMemberEvent(room, otherUserId, "DEVICEB", voiceState: ["muted"]),
        callMemberEvent(room, selfUserId, selfDeviceId, voiceState: []),
        // Not in our LiveKit room: state is all we have.
        callMemberEvent(room, thirdUserId, "DEVICEC",
            voiceState: ["muted", "deafened"]),
      ]);
      final session = FakeVoipSession(client, roomId, "session-1")
        ..publish(otherUserId, VoipStreamType.audio)
        ..publish(selfUserId, VoipStreamType.audio,
            muted: true, deafened: true);
      clientManager.callManager.currentSessions.add(session);

      final voice = callSession(component).voiceState;
      expect(voice[otherUserId], isEmpty);
      expect(voice[selfUserId], {VoiceState.muted, VoiceState.deafened});
      expect(voice[thirdUserId], {VoiceState.muted, VoiceState.deafened});
    });

    test("only the microphone counts: a muted camera is not a muted member",
        () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB", voiceState: []),
      ]);
      final session = FakeVoipSession(client, roomId, "session-1")
        ..publish(otherUserId, VoipStreamType.audio)
        ..publish(otherUserId, VoipStreamType.video, muted: true);
      clientManager.callManager.currentSessions.add(session);

      expect(callSession(component).voiceState[otherUserId], isEmpty);
    });
  });

  // People who had been in a voice channel for a while vanished from it,
  // leaving it looking empty while they were still talking in it. Their
  // memberships lapse by the homeserver's clock, and were read against this
  // machine's, which can be hours ahead: a Windows clock reading a dual
  // boot's UTC hardware clock as local time runs three hours ahead, in
  // Brazil. Here this machine's clock is the real one, and the homeserver's
  // three hours behind it.
  group("Members in the call for hours", () {
    const thirdUserId = "@third:example.org";

    late HomeserverClock clock;
    late MatrixActivitiesComponent sidebar;

    setUp(() {
      clock = HomeserverClock();
      clock.readSync(syncFromHomeserver(serverNow()), homeserver: homeserver);
      sidebar = MatrixActivitiesComponent(client, room,
          callManager: clientManager.callManager, clock: clock);
    });

    void setMemberships(List<matrix.StrippedStateEvent> memberships) {
      room.matrixRoom.states[MatrixActivitiesComponent.callMemberStateEvent] = {
        for (final m in memberships) m.stateKey!: m,
      };
    }

    test("someone who joined two hours ago is listed on a clock that is ahead",
        () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 2))),
      ]);

      expect(callParticipants(sidebar), {otherUserId});
    });

    test("someone who joined five hours ago and keeps it up is listed", () {
      // Written again an hour ago, the window pushed four hours past then.
      final joined = serverNow().subtract(const Duration(hours: 5));
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 1)),
            extra: {
              "created_ts": joined.millisecondsSinceEpoch,
              "expires": const Duration(hours: 8).inMilliseconds,
            }),
        callMemberEvent(room, thirdUserId, "DEVICEC",
            sentAt: serverNow().subtract(const Duration(minutes: 5))),
      ]);

      expect(callParticipants(sidebar), {otherUserId, thirdUserId});
    });

    test("a membership that lapsed by the homeserver's clock is dropped", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 5))),
      ]);

      expect(callParticipants(sidebar), isEmpty);
    });

    test("the list is looked at again when one lapses, not before", () async {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow(), extra: {"expires": 60}),
        callMemberEvent(room, thirdUserId, "DEVICEC", sentAt: serverNow()),
      ]);
      final changes = <void>[];
      final sub = sidebar.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      expect(callParticipants(sidebar), {otherUserId, thirdUserId});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(changes, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(changes, hasLength(1));
      expect(callParticipants(sidebar), {thirdUserId});
    });

    test("the list is put right as soon as a sync says what time it is",
        () async {
      // Just started: nothing has said what time it is yet.
      final unread = HomeserverClock();
      final justStarted = MatrixActivitiesComponent(client, room,
          callManager: clientManager.callManager, clock: unread);
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 2))),
      ]);
      final changes = <void>[];
      final sub = justStarted.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);
      // By this machine's clock their window closed an hour ago.
      expect(callParticipants(justStarted), isEmpty);

      unread.readSync(syncFromHomeserver(serverNow()), homeserver: homeserver);
      await Future<void>.delayed(Duration.zero);

      expect(changes, hasLength(1),
          reason: "nothing else might come by for an hour");
      expect(callParticipants(justStarted), {otherUserId});
    });

    test(
        "in our call, someone connected who publishes nothing and has no "
        "membership is listed", () {
      // Their microphone would not open, and their membership lapsed.
      final selfMembership = callMembership(selfUserId, selfDeviceId);
      setMemberships([selfMembership]);
      final session = FakeVoipSession(client, roomId, "session-1")
        ..connected.addAll({selfUserId, otherUserId})
        ..publish(selfUserId, VoipStreamType.audio);
      clientManager.callManager.currentSessions.add(session);

      expect(callParticipants(sidebar), {selfUserId, otherUserId});
    });

    test("in our call, the list is looked at again when someone connects",
        () async {
      final session = FakeVoipSession(client, roomId, "session-1");
      clientManager.callManager.currentSessions.add(session);
      final changes = <void>[];
      final sub = sidebar.onSessionsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      session.connect(thirdUserId);
      await Future<void>.delayed(Duration.zero);

      expect(changes, isNotEmpty);
      expect(callParticipants(sidebar), contains(thirdUserId));
    });
  });

  // The voice channel's own page, before joining, shows everyone in it.
  group("Voice channel page", () {
    const thirdUserId = "@third:example.org";

    late HomeserverClock clock;
    late MatrixVoipRoomComponent voip;

    setUp(() {
      clock = HomeserverClock();
      clock.readSync(syncFromHomeserver(serverNow()), homeserver: homeserver);
      voip = MatrixVoipRoomComponent(client, room, clock: clock);
    });

    void setMemberships(List<matrix.StrippedStateEvent> memberships) {
      room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
        for (final m in memberships) m.stateKey!: m,
      };
    }

    test("lists someone in the call for hours on a clock that is ahead", () {
      final joined = serverNow().subtract(const Duration(hours: 6));
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 2))),
        callMemberEvent(room, thirdUserId, "DEVICEC",
            sentAt: serverNow().subtract(const Duration(minutes: 50)),
            extra: {
              "created_ts": joined.millisecondsSinceEpoch,
              "expires": const Duration(hours: 9).inMilliseconds,
            }),
      ]);

      expect(voip.getCurrentParticipants(), [otherUserId, thirdUserId]);
    });

    test("does not list a membership that lapsed", () {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 4, minutes: 1))),
      ]);

      expect(voip.getCurrentParticipants(), isEmpty);
    });

    test("is looked at again when a membership lapses, not before", () async {
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow(), extra: {"expires": 60}),
      ]);
      final changes = <void>[];
      final sub = voip.onParticipantsChanged.listen(changes.add);
      addTearDown(sub.cancel);

      expect(voip.getCurrentParticipants(), [otherUserId]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(changes, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(changes, hasLength(1));
      expect(voip.getCurrentParticipants(), isEmpty);
    });

    test("is put right as soon as a sync says what time it is", () async {
      final unread = HomeserverClock();
      final justStarted = MatrixVoipRoomComponent(client, room, clock: unread);
      setMemberships([
        callMemberEvent(room, otherUserId, "DEVICEB",
            sentAt: serverNow().subtract(const Duration(hours: 2))),
      ]);
      final changes = <void>[];
      final sub = justStarted.onParticipantsChanged.listen(changes.add);
      addTearDown(sub.cancel);
      expect(justStarted.getCurrentParticipants(), isEmpty);

      unread.readSync(syncFromHomeserver(serverNow()), homeserver: homeserver);
      await Future<void>.delayed(Duration.zero);

      expect(changes, hasLength(1));
      expect(justStarted.getCurrentParticipants(), [otherUserId]);
    });
  });
}
