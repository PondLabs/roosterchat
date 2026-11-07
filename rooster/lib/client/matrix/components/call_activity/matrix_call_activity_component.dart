// The Matrix side of call activities: the session's room state
// (chat.commet.call_activity, one event per session whose state key is the
// session id), the lift from a live call to a [CallActivitySession] over
// LiveKit, and launching. A session dies with its call: the host's session
// ending clears the state event, and a session whose state is expired is
// not surfaced (the room list reads the state; the game itself only runs
// inside the call).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/matrix_sync_listener.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';

import 'livekit_call_activity_transport.dart';

class MatrixCallActivityComponent
    extends RoomComponent<MatrixClient, MatrixRoom>
    implements CallActivityRoomState, MatrixRoomSyncListener {
  MatrixCallActivityComponent(super.client, super.room,
      {CallManager? callManager,
      HomeserverClock? clock,
      CallActivityTransport? Function(VoipSession call)? transportFor})
      : _injectedCallManager = callManager,
        _clock = clock ?? HomeserverClock.instance,
        _transportFor = transportFor ?? _livekitTransportFor;

  static const stateEventType = 'chat.commet.call_activity';

  /// How long a session's state lives on its own: a match is minutes, but
  /// a host's client may die before it could clear. Visibility is bounded
  /// anyway: a session only shows while the call that holds it is alive.
  static const expires = Duration(hours: 6);

  /// Injected for tests; otherwise resolved lazily from the global
  /// [clientManager], which is still null while rooms are first loaded.
  final CallManager? _injectedCallManager;
  final HomeserverClock _clock;

  /// The wire a session in [call] talks over: LiveKit's data channel, or
  /// none for a call without LiveKit. Injected for tests.
  final CallActivityTransport? Function(VoipSession call) _transportFor;

  static CallActivityTransport? _livekitTransportFor(VoipSession call) =>
      call is MatrixLivekitVoipSession
          ? LivekitCallActivityTransport(call.livekitRoom)
          : null;

  CallManager? get _callManager =>
      _injectedCallManager ?? clientManager?.callManager;

  final Map<String, CallActivitySession> _sessionById = {};
  final Map<CallActivitySession, CallActivityTransport> _transportOf = {};
  final Map<CallActivitySession, String> _lastSessionIdOf = {};
  final Map<CallActivitySession, VoidCallback> _listenersOf = {};
  final List<StreamSubscription> _callManagerSubs = [];
  bool _watchingCallManager = false;

  // ------------------------------------------------------------- room state

  /// The state key a session's event lives under: its id behind an
  /// underscore. The id is the host's LiveKit identity ("@alice:server:
  /// DEVICE"), and Synapse refuses any state key that starts with "@" but
  /// is not exactly the sender's user id ("You are not allowed to set
  /// others state"); MatrixRTC's memberships step round it the same way.
  static String stateKeyOf(String sessionId) => '_$sessionId';

  /// The session id under [stateKey] (a key without the underscore is
  /// taken as it is).
  static String sessionIdOf(String stateKey) =>
      stateKey.startsWith('_') ? stateKey.substring(1) : stateKey;

  @override
  Future<void> write({
    required String sessionId,
    required String activityId,
    required String hostUserId,
    required int createdAtMs,
  }) async {
    await room.matrixRoom.client.setRoomStateWithKey(
        room.identifier, stateEventType, stateKeyOf(sessionId), {
      'activity': activityId,
      'host': hostUserId,
      'created': createdAtMs,
      'expires': expires.inMilliseconds,
    });
  }

  @override
  Future<void> clear(String sessionId) async {
    await room.matrixRoom.client.setRoomStateWithKey(
        room.identifier, stateEventType, stateKeyOf(sessionId), {});
  }

  /// The sessions this room shows, from the state alone: expired state is
  /// dropped. Everyone (in the call or not) reads this the same way.
  List<({String sessionId, String activityId, String hostUserId})>
      visibleSessions() {
    final state = room.matrixRoom.states[stateEventType] ?? const {};
    final nowMs = _clock.now().millisecondsSinceEpoch;
    final result =
        <({String sessionId, String activityId, String hostUserId})>[];
    for (final entry in state.entries) {
      if (entry.value.content.isEmpty) continue;
      final activityId = entry.value.content.tryGet<String>('activity');
      final host = entry.value.content.tryGet<String>('host');
      if (activityId == null || host == null) continue;
      final int created = switch (entry.value.content['created']) {
        final int ms => ms,
        // This fork's events carry their server time as a DateTime.
        _ => entry.value is matrix.Event
            ? (entry.value as matrix.Event)
                .originServerTs
                .millisecondsSinceEpoch
            : 0,
      };
      final windowJson = entry.value.content['expires'];
      final window = windowJson is int ? windowJson : expires.inMilliseconds;
      if (nowMs - created > window) continue;
      result.add((
        sessionId: sessionIdOf(entry.key),
        activityId: activityId,
        hostUserId: host,
      ));
    }
    return result;
  }

  /// The sessions the call's shelf and pill offer: visible, and with a
  /// host in the call (ourselves, or one we have heard from). A state whose
  /// host is gone without clearing it (its app died) names a session
  /// nobody runs: offered as one to join, it did nothing, and the shelf had
  /// no Launch for as long as the state lasted.
  List<({String sessionId, String activityId, String hostUserId})>
      liveSessions() => [
            for (final entry in visibleSessions())
              if (_isLive(_sessionById[entry.sessionId])) entry,
          ];

  static bool _isLive(CallActivitySession? session) =>
      session != null && (session.isHost || session.hostIdentity != null);

  /// Fires when the set of live sessions (or who is in them) changes:
  /// the call's view mounts its stage off it.
  Stream<void> get onChanged {
    _watchCallManager();
    return _changes.stream;
  }

  final StreamController<void> _changes = StreamController.broadcast();

  // --------------------------------------------------------- live sessions

  /// The session this client follows (or hosts) by room-state id, if any.
  CallActivitySession? sessionOf(String sessionId) => _sessionById[sessionId];

  /// Launches [activity] in our live call in this room: the host takes the
  /// seat, the state is written. Null when we are not in the call (or it
  /// is not a LiveKit call), or a session is already running. A session
  /// nobody hosts (see [liveSessions]) does not count, and goes.
  Future<CallActivitySession?> launch(CallActivity activity) async {
    _watchCallManager();
    if (_sessionById.values.any(_isLive)) return null;
    final call = _ownCall();
    final transport = call == null ? null : _transportFor(call);
    if (transport == null) return null;
    for (final stale in List.of(_transportOf.keys)) {
      await _untrack(stale);
    }
    final session = CallActivitySession(
      activity: activity,
      selfUserId: client.self?.identifier ?? '',
      transport: transport,
    );
    await session.launch();
    final sessionId = session.snapshot.sessionId;
    _track(session, transport);
    await write(
      sessionId: sessionId,
      activityId: activity.id,
      hostUserId: client.self?.identifier ?? '',
      createdAtMs: _clock.now().millisecondsSinceEpoch,
    );
    return session;
  }

  /// The call session of this room that we are in, the seat the session's
  /// wire lives on.
  VoipSession? _ownCall() =>
      _callManager?.getCallInRoom(client, room.identifier);

  /// When our call is in a room whose state carries a live session we do
  /// not follow yet, follow it: build the session from the state (the
  /// game binds to it and hears the wire from then on). Sessions whose
  /// state is gone are dropped, unless we host them: the host clears its
  /// state when it ends, not before.
  void _followState() {
    _watchCallManager();
    final call = _ownCall();
    final visible = visibleSessions();
    if (call != null) {
      final knownIds = <String>{};
      for (final entry in visible) {
        knownIds.add(entry.sessionId);
        if (_sessionById.containsKey(entry.sessionId)) continue;
        final activity = CallActivityRegistry.byId(entry.activityId);
        if (activity == null) continue;
        final transport = _transportFor(call);
        if (transport == null) continue;
        final session = CallActivitySession(
          activity: activity,
          selfUserId: client.self?.identifier ?? '',
          transport: transport,
        );
        session.seedFromRoom(
          sessionId: entry.sessionId,
          activityId: entry.activityId,
          hostUserId: entry.hostUserId,
        );
        _track(session, transport);
      }
    }
    final liveIds = {for (final s in visible) s.sessionId};
    for (final entry in _sessionById.entries.toList()) {
      if (liveIds.contains(entry.key) || entry.value.isHost) continue;
      _untrack(entry.value);
    }
  }

  void _track(CallActivitySession session, CallActivityTransport transport) {
    _sessionById[session.snapshot.sessionId] = session;
    _transportOf[session] = transport;
    _identityOf[session] = session.selfIdentity;
    _liveOf[session] = _isLive(session);
    // A host that launched before we listened: launch() notifies before
    // _track attaches the listener, and a host alone in its session gets no
    // other notification, so this is the only chance to remember it. Without
    // it the clear when it leaves has nothing to go on.
    if (session.isHost) _everHostedByUs.add(session);
    _lastSessionIdOf[session] = session.snapshot.sessionId;
    _listenersOf[session] = _onSessionChanged;
    session.addListener(_onSessionChanged);
    _changes.add(null);
  }

  Future<void> _untrack(CallActivitySession session) async {
    final listener = _listenersOf.remove(session);
    if (listener != null) session.removeListener(listener);
    _changes.add(null);
    final id = _lastSessionIdOf[session];
    if (identical(_sessionById[id], session)) _sessionById.remove(id);
    _lastSessionIdOf.remove(session);
    _identityOf.remove(session);
    _liveOf.remove(session);
    _everHostedByUs.remove(session);
    final transport = _transportOf.remove(session);
    await transport?.dispose();
  }

  /// The host's own session ending (left the call, ended the activity)
  /// clears the room state; everyone else only folds their bookkeeping.
  /// Who we have seen hosting this session: the room state's clear is the
  /// host's job, but the session's [isHost] flag falls BEFORE the notify
  /// that ends a session (the same notification), so the host at the end
  /// is remembered from before — a re-hosted client that leaves last
  /// still cleans up after itself.
  final Set<CallActivitySession> _everHostedByUs = {};

  void _onSessionChanged() {
    var changed = false;
    for (final session in List.of(_sessionById.values)) {
      if (session.isHost) _everHostedByUs.add(session);
      // Whether it is one to offer moved (its host heard from, gone, or
      // the session over): the call's pill and shelf follow.
      final live = _isLive(session);
      if (_liveOf[session] != live) {
        _liveOf[session] = live;
        changed = true;
      }
      final previous = _lastSessionIdOf[session] ?? '';
      final current = session.snapshot.sessionId;
      if (previous == current) continue;
      _sessionById.remove(previous);
      _lastSessionIdOf[session] = current;
      if (current.isEmpty) {
        if (previous.isNotEmpty && _everHostedByUs.contains(session)) {
          clear(previous).catchError((_) {});
        }
      } else {
        _sessionById[current] = session;
      }
    }
    if (changed) _changes.add(null);
  }

  /// Our own LiveKit identity in each session, from when it was tracked:
  /// once the call is torn down the transport no longer knows it.
  final Map<CallActivitySession, String> _identityOf = {};

  /// Whether each session was one to offer, last we looked.
  final Map<CallActivitySession, bool> _liveOf = {};

  /// Our call in this room is gone (hung up, dropped, taken over by
  /// another device), and every session we followed or hosted in it with
  /// it: they were bound to its wire. One we hosted with nobody else in it
  /// is over, and its room state goes; one others are in goes on without
  /// us (they elect a host among themselves, and whoever ends it last
  /// clears the state). Rejoining starts afresh from the room state.
  ///
  /// Nothing did this before: the host's session outlived its call, its
  /// state stayed for six hours, the shelf offered it as one to join, and
  /// it blocked launching another.
  Future<void> _leaveCall() async {
    for (final session in List.of(_transportOf.keys)) {
      final id = _lastSessionIdOf[session] ?? '';
      final self = _identityOf[session] ?? '';
      final others = {
        ...session.snapshot.players,
        ...session.snapshot.spectators,
      }..remove(self);
      // isHost falls before the notify that ends a session, so a host that
      // left the activity first is only known from _everHostedByUs.
      final hosting = session.isHost || _everHostedByUs.contains(session);
      // Not disposed: the call's view may still hold it for a moment.
      await _untrack(session);
      if (id.isNotEmpty && hosting && others.isEmpty) {
        await clear(id).catchError((Object _) {});
      }
    }
  }

  // ----------------------------------------------------------- watch calls

  void _watchCallManager() {
    if (_watchingCallManager) return;
    final callManager = _callManager;
    if (callManager == null) return;
    _watchingCallManager = true;
    _callManagerSubs.add(callManager.currentSessions.onAdd.listen((session) {
      if (!_isOurCall(session)) return;
      _followState();
    }));
    _callManagerSubs.add(callManager.currentSessions.onRemove.listen((session) {
      if (!_isOurCall(session)) return;
      _leaveCall();
    }));
  }

  bool _isOurCall(session) =>
      session.client == client && session.roomId == room.identifier;

  // ------------------------------------------------------------- sync hook

  @override
  onSync(matrix.JoinedRoomUpdate update) {
    final events = [...?update.state, ...?update.timeline?.events];
    if (events.any((event) => event.type == stateEventType)) {
      _followState();
    }
  }
}
