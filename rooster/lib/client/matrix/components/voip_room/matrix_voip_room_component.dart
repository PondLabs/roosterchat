import 'dart:async';

import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/components/matrix_sync_listener.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:matrix/matrix.dart';

class MatrixVoipRoomComponent
    implements
        VoipRoomComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  static const callMemberStateEvent = "org.matrix.msc3401.call.member";

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  late MatrixLivekitBackend backend;

  VoipSession? currentSession;

  /// The homeserver's time, which memberships lapse by (see
  /// [HomeserverClock]).
  final HomeserverClock _clock;

  MatrixVoipRoomComponent(this.client, this.room, {HomeserverClock? clock})
      : _clock = clock ?? HomeserverClock.instance {
    backend = MatrixLivekitBackend(room);
  }

  static bool isVoipRoom(MatrixRoom room) {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        "org.matrix.msc3417.call";
  }

  StreamController _onParticipantsChanged = StreamController.broadcast();

  /// Recomputes the list when the next membership in it lapses (see
  /// [getCurrentParticipants]).
  late final MembershipLapseTimer _lapseTimer = MembershipLapseTimer(
      () => _onParticipantsChanged.add(()),
      now: _clock.now);

  StreamSubscription? _clockSub;

  @override
  onSync(JoinedRoomUpdate update) {
    // A limited sync delivers state changes in `state`, not the timeline: a
    // leave that came in one was missed, and the member stayed listed.
    final events = [...?update.state, ...?update.timeline?.events];
    if (events.any((event) => event.type == callMemberStateEvent)) {
      _onParticipantsChanged.add(());
      // Joined again from another device? This one leaves. On the next
      // turn, once the sync is in the room state; the heartbeat checks too.
      final session = currentSession;
      if (session is MatrixLivekitVoipSession) {
        Future(session.leaveIfSuperseded);
      }
    }
  }

  bool get _hasActiveSession =>
      currentSession != null && currentSession!.state != VoipState.ended;

  /// True when [entry] is a call membership written by this very device.
  bool _isOwnDeviceMembership(StrippedStateEvent entry) {
    if (entry.senderId != client.matrixClient.userID) return false;
    final deviceId = entry.content.tryGet<String>("device_id");
    return deviceId == client.matrixClient.deviceID;
  }

  @override
  List<String> getCurrentParticipants() {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      _lapseTimer.cancel();
      return [];
    }

    final now = _clock.now();
    final expiries = <DateTime?>[];
    List<String> participants = List.empty(growable: true);
    for (var pair in state.entries) {
      if (pair.value.content.isEmpty) {
        continue;
      }

      final entry = pair.value;
      final sentAt = entry is Event ? entry.originServerTs : null;
      if (MatrixCallMembership.isExpired(entry.content, sentAt, now)) {
        continue;
      }

      // A membership left behind by this device (the app was closed or
      // crashed mid-call) is stale: we are only in the call if we hold a live
      // session right now.
      if (_isOwnDeviceMembership(pair.value) && !_hasActiveSession) {
        continue;
      }

      expiries.add(MatrixCallMembership.expiresAt(entry.content, sentAt));

      final sender = pair.value.senderId;
      if (participants.contains(sender)) {
        continue;
      }

      participants.add(sender);
    }

    // Nothing arrives over sync when a membership lapses, so look again then.
    _lapseTimer.schedule(MatrixCallMembership.nextExpiry(expiries, now));

    return participants;
  }

  @override
  Future<void> clearStaleOwnMembership() async {
    if (_hasActiveSession) return;

    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) return;

    final stale = [
      for (var entry in state.entries)
        if (entry.value.content.isNotEmpty &&
            _isOwnDeviceMembership(entry.value))
          entry.key,
    ];

    if (stale.isEmpty) return;

    if (!canJoinCall) {
      // Without permission to write the state event we can't clean up, the
      // local filter in getCurrentParticipants still hides it for us.
      return;
    }

    Log.i(
        "Clearing ${stale.length} stale call membership(s) in ${room.identifier}");

    await Future.wait([
      for (var stateKey in stale)
        client.matrixClient.setRoomStateWithKey(
          room.identifier,
          callMemberStateEvent,
          stateKey,
          {},
        ),
    ]);
  }

  @override
  Stream<void> get onParticipantsChanged {
    // Worked out by the time as it was: looked at again when a sync puts
    // that right.
    _clockSub ??= _clock.onCorrected.listen((_) {
      _lapseTimer.cancel();
      _onParticipantsChanged.add(());
    });
    return _onParticipantsChanged.stream;
  }

  /// A join in progress: a second ask while one runs gets the same one.
  /// Two views of one room (or a silent-join request racing a click) made
  /// two LiveKit sessions whose membership writes overwrote each other.
  Future<VoipSession?>? _joining;

  @override
  Future<VoipSession?> joinCall() {
    final joining = _joining;
    if (joining != null) return joining;
    final join = _joinCall();
    _joining = join;
    join.whenComplete(() {
      if (identical(_joining, join)) _joining = null;
    });
    return join;
  }

  Future<VoipSession?> _joinCall() async {
    // Leaving is memoised, so this only waits for a hang up already running:
    // two overlapping sessions fought over the membership state (issue #48).
    await currentSession?.hangUpCall();

    // One voice channel at a time. Walking into another room's channel
    // leaves the one being stood in, and before the join rather than after,
    // so the two are never both live and never both claim a membership.
    await clientManager?.callManager
        .leaveOtherCalls(client: client, roomId: room.identifier);

    currentSession = await backend.join();
    currentSession?.onStateChanged.listen(onStateChanged);
    return currentSession;
  }

  @override
  Future<String?> getCallServerUrl() async {
    final url = await backend.getFociUrl();
    return url.firstOrNull?.authority.toString();
  }

  void onStateChanged(void event) {
    final state = currentSession?.state;
    print("Got call state: ${state}");

    if (state == VoipState.ended) {
      currentSession = null;
    }
  }

  @override
  bool get canJoinCall => room.matrixRoom.canChangeState(
        MatrixVoipRoomComponent.callMemberStateEvent,
      );

  @override
  Future<void> clearAllCallMembershipStatus() async {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      return;
    }

    var futures = [
      for (var entry in state.entries)
        if (entry.value.senderId == client.matrixClient.userID)
          client.matrixClient.setRoomStateWithKey(
            room.identifier,
            MatrixVoipRoomComponent.callMemberStateEvent,
            entry.key,
            {},
          ),
    ];

    await Future.wait(futures);
  }
}
