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
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/matrix/components/matrix_sync_listener.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';

import 'livekit_call_activity_transport.dart';

class MatrixCallActivityComponent
    extends RoomComponent<MatrixClient, MatrixRoom>
    implements CallActivityRoomState, MatrixRoomSyncListener, NeedsClose {
  MatrixCallActivityComponent(super.client, super.room,
      {CallManager? callManager,
      HomeserverClock? clock,
      CallActivityTransport? Function()? ownCallTransport})
      : _injectedCallManager = callManager,
        _clock = clock ?? HomeserverClock.instance,
        _injectedOwnCallTransport = ownCallTransport;

  static const stateEventType = 'chat.commet.call_activity';

  /// How long a session's state lives on its own: a match is minutes, but
  /// a host's client may die before it could clear. Visibility is bounded
  /// anyway: a session only shows while the call that holds it is alive.
  static const expires = Duration(hours: 6);

  /// How far ahead of our clock a session's `created` may be (clock skew
  /// between clients); further is a forgery meant to never expire.
  static const createdSkew = Duration(minutes: 1);

  /// How long a session seeded from the room state counts as live before
  /// anyone on the wire has spoken for it: its host may still be in the
  /// call under an identity we have not heard from, or a re-host is under
  /// way.
  static const seedGrace = Duration(seconds: 5);

  /// Injected for tests; otherwise resolved lazily from the global
  /// [clientManager], which is still null while rooms are first loaded.
  final CallManager? _injectedCallManager;
  final HomeserverClock _clock;

  /// Injected for tests: a fresh transport on our call in this room, null
  /// when we are not in it. Otherwise LiveKit's.
  final CallActivityTransport? Function()? _injectedOwnCallTransport;

  CallManager? get _callManager =>
      _injectedCallManager ?? clientManager?.callManager;

  final Map<String, CallActivitySession> _sessionById = {};
  final Map<CallActivitySession, CallActivityTransport> _transportOf = {};
  final Map<CallActivitySession, String> _lastSessionIdOf = {};
  final Map<CallActivitySession, VoidCallback> _listenersOf = {};
  final Map<CallActivitySession, DateTime> _seededAt = {};

  /// The last event under each state key that its owner sent: an event
  /// over it from anyone else (a forgery, or a clear by someone who is not
  /// the session's host) is ignored and this one stands.
  final Map<String, matrix.StrippedStateEvent> _ownedState = {};
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

  /// Whether [senderId] owns [stateKey]: the session id under it is one
  /// of the sender's own LiveKit identities ("@alice:server:DEVICE").
  static bool ownsStateKey(String senderId, String stateKey) =>
      stateKey.startsWith('_') &&
      sessionIdOf(stateKey).startsWith('$senderId:');

  /// The sessions this room shows, from the state alone: expired state is
  /// dropped, and so is any event not sent by the host it names under its
  /// own key (anyone may write this state in a voice channel). Everyone
  /// (in the call or not) reads this the same way.
  List<({String sessionId, String activityId, String hostUserId})>
      visibleSessions() {
    final state = room.matrixRoom.states[stateEventType] ?? const {};
    for (final entry in state.entries) {
      if (ownsStateKey(entry.value.senderId, entry.key)) {
        _ownedState[entry.key] = entry.value;
      }
    }
    _ownedState.removeWhere((key, _) => !state.containsKey(key));
    final nowMs = _clock.now().millisecondsSinceEpoch;
    final result =
        <({String sessionId, String activityId, String hostUserId})>[];
    for (final MapEntry(key: key, value: event) in _ownedState.entries) {
      if (event.content.isEmpty) continue;
      final activityId = event.content.tryGet<String>('activity');
      final host = event.content.tryGet<String>('host');
      if (activityId == null || host != event.senderId) continue;
      final int created = switch (event.content['created']) {
        final int ms => ms,
        // This fork's events carry their server time as a DateTime.
        _ => event is matrix.Event
            ? event.originServerTs.millisecondsSinceEpoch
            : 0,
      };
      if (created - nowMs > createdSkew.inMilliseconds) continue;
      final windowJson = event.content['expires'];
      final window = windowJson is int
          ? windowJson.clamp(0, expires.inMilliseconds)
          : expires.inMilliseconds;
      if (nowMs - created > window) continue;
      result.add((
        sessionId: sessionIdOf(key),
        activityId: activityId,
        hostUserId: event.senderId,
      ));
    }
    return result;
  }

  /// Fires when the set of live sessions (or who is in them) changes:
  /// the call's view mounts its stage off it, the room list shows who is
  /// playing.
  Stream<void> get onChanged => _changes.stream;
  final StreamController<void> _changes = StreamController.broadcast();

  // --------------------------------------------------------- live sessions

  /// The session this client follows (or hosts) by room-state id, if any.
  CallActivitySession? sessionOf(String sessionId) => _sessionById[sessionId];

  /// The room-state sessions that still have someone in our call to play
  /// them: a session whose host left without clearing its state (it lives
  /// up to [expires]) and nobody else holds is dropped, so it neither
  /// shows a Join that goes nowhere nor stops a launch.
  List<({String sessionId, String activityId, String hostUserId})>
      liveSessions() => [
            for (final entry in visibleSessions())
              if (_sessionById[entry.sessionId] case final session?
                  when !_orphaned(session))
                entry,
          ];

  /// Nobody but us is left in [session]: not its host, no player, no
  /// spectator (a session seeded from stale state has only its id, the
  /// original host's identity, to go on, and is given [seedGrace] for
  /// someone on the wire to speak for it).
  bool _orphaned(CallActivitySession session) {
    if (session.isHost) return false;
    final transport = _transportOf[session];
    if (transport == null) return true;
    final seededAt = _seededAt[session];
    if (session.hostIdentity == null &&
        seededAt != null &&
        _clock.now().difference(seededAt) < seedGrace) {
      return false;
    }
    final snapshot = session.snapshot;
    return !{
      snapshot.sessionId,
      if (session.hostIdentity case final host?) host,
      ...snapshot.players,
      ...snapshot.spectators,
    }.any((id) => id != transport.selfIdentity && transport.isPresent(id));
  }

  /// Launches [activity] in our live call in this room: the host takes the
  /// seat, the state is written. Null when we are not in the call (or it
  /// is not a LiveKit call), or a session is already running. Throws
  /// [CallActivityLaunchException] when the room refuses its state: the
  /// others in the call find the session through it, so a launch without
  /// it is undone.
  Future<CallActivitySession?> launch(CallActivity activity) async {
    for (final session in _sessionById.values.toList()) {
      if (!_orphaned(session)) return null;
      await _untrack(session);
      session.dispose();
    }
    if (!room.matrixRoom.canChangeState(stateEventType)) {
      throw const CallActivityLaunchException.notAllowed();
    }
    final transport = _ownCallTransport();
    if (transport == null) return null;
    final session = CallActivitySession(
      activity: activity,
      selfUserId: client.self?.identifier ?? '',
      transport: transport,
    );
    await session.launch();
    final sessionId = session.snapshot.sessionId;
    _track(session, transport);
    try {
      await write(
        sessionId: sessionId,
        activityId: activity.id,
        hostUserId: client.self?.identifier ?? '',
        createdAtMs: _clock.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      // Undone, or the session we could not announce blocks every launch
      // after it in this room.
      await _untrack(session);
      await session.end();
      session.dispose();
      throw CallActivityLaunchException(e);
    }
    return session;
  }

  /// A transport on our call in this room, the seat the session's wire
  /// lives on; null when we are not in it (or it carries no LiveKit).
  CallActivityTransport? _ownCallTransport() {
    if (_injectedOwnCallTransport case final inject?) return inject();
    final call = _callManager?.getCallInRoom(client, room.identifier);
    return call is MatrixLivekitVoipSession
        ? LivekitCallActivityTransport(call.livekitRoom)
        : null;
  }

  /// When our call is in a room whose state carries a live session we do
  /// not follow yet, follow it: build the session from the state (the
  /// game binds to it and hears the wire from then on). Sessions whose
  /// state is gone are dropped, unless we host them: the host clears its
  /// state when it ends, not before.
  void _followState() {
    _watchCallManager();
    final transport = _ownCallTransport();
    if (transport == null) {
      // Out of the call (we left it, or the connection took it down): its
      // activity is not ours to follow any more, and a session left
      // running here kept the game alive after the call it belonged to
      // was gone. The session goes with the call.
      _dropAllSessions();
      return;
    }
    final visible = visibleSessions();
    for (final entry in visible) {
      if (_sessionById.containsKey(entry.sessionId)) continue;
      final activity = CallActivityRegistry.byId(entry.activityId);
      if (activity == null) continue;
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
      _seededAt[session] = _clock.now();
      _track(session, transport);
    }
    final liveIds = {for (final s in visible) s.sessionId};
    for (final entry in _sessionById.entries.toList()) {
      if (liveIds.contains(entry.key) || entry.value.isHost) continue;
      _untrack(entry.value);
    }
  }

  /// How long a session gets to say goodbye before we stop waiting on it:
  /// the call it lived on is gone, and its transport may never answer.
  static const leaveTimeout = Duration(seconds: 2);

  /// Every session we follow, gone: the call that held them is over.
  ///
  /// Each is told we are out first, so the host drops us from its roster
  /// now rather than when LiveKit gets round to reporting us gone (a
  /// connection that dropped can take a while, and until then the host
  /// played for a player who was not there). A host leaving last ends the
  /// session, and its room state goes with it.
  void _dropAllSessions() {
    for (final session in _sessionById.values.toList()) {
      unawaited(_dropSession(session));
    }
  }

  /// One session of a call that is over: told we are out, then gone.
  Future<void> _dropSession(CallActivitySession session) async {
    try {
      await session.leave().timeout(leaveTimeout);
    } catch (e, s) {
      Log.onError(e, s, content: 'call activity: could not leave the call');
    }
    await _untrack(session);
    session.dispose();
  }

  void _track(CallActivitySession session, CallActivityTransport transport) {
    _sessionById[session.snapshot.sessionId] = session;
    _transportOf[session] = transport;
    _lastSessionIdOf[session] = session.snapshot.sessionId;
    _listenersOf[session] = _onSessionChanged;
    session.addListener(_onSessionChanged);
    _changes.add(null);
    // A host that launched before we listened: launch() notifies before
    // _track attaches the listener, and a host alone in its session gets no
    // other notification, so this is the only chance to remember it. Without
    // it the clear when it leaves has nothing to go on.
    if (session.isHost) _everHostedByUs.add(session);
    // A launch has its host in already: the session told nobody yet.
    _noteRosters();
  }

  Future<void> _untrack(CallActivitySession session) async {
    final listener = _listenersOf.remove(session);
    if (listener != null) session.removeListener(listener);
    _rosterOf.remove(session);
    _changes.add(null);
    _sessionById.remove(_lastSessionIdOf[session]);
    _lastSessionIdOf.remove(session);
    _seededAt.remove(session);
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
    _noteRosters();
    for (final session in List.of(_sessionById.values)) {
      if (session.isHost) _everHostedByUs.add(session);
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
  }

  // ---------------------------------------------------------------- roster

  /// Who is in each session we follow (players and spectators, by LiveKit
  /// identity), as last heard. Absent until its first state is.
  final Map<CallActivitySession, Set<String>> _rosterOf = {};

  /// How long the roster has to keep still before its sound plays: a
  /// snapshot, a handoff or several people joining at once is one sound.
  static const rosterSoundDelay = Duration(milliseconds: 300);
  Timer? _rosterSoundTimer;
  bool _someoneJoined = false;
  bool _someoneLeft = false;

  /// Who is in [session] now; null while we know of it but not yet who is
  /// in it (seeded from the room, or announced before its first state): a
  /// session always has someone in it, its host ends it when the last one
  /// leaves.
  static Set<String>? rosterOf(CallActivitySession session) {
    if (!session.hasSession) return const {};
    final roster = {
      ...session.snapshot.players,
      ...session.snapshot.spectators,
    };
    return roster.isEmpty ? null : roster;
  }

  /// Whether going from [before] to [now] has someone joining and someone
  /// leaving. The first roster heard ([before] null) is who was already
  /// playing: only our own place in it ([self]) is news.
  static ({bool joined, bool left}) rosterChange(
          Set<String>? before, Set<String> now, String self) =>
      before == null
          ? (joined: now.contains(self), left: false)
          : (
              joined: now.difference(before).isNotEmpty,
              left: before.difference(now).isNotEmpty,
            );

  /// A join or a leave is heard in the call and shown in the room list: the
  /// list is told, and the sound is played once things settle.
  void _noteRosters() {
    // The room is going: who leaves it now is no news to announce.
    if (_closed) return;
    var changed = false;
    for (final session in _transportOf.keys) {
      final now = rosterOf(session);
      if (now == null) continue;
      final before = _rosterOf[session];
      if (before != null && setEquals(before, now)) continue;
      _rosterOf[session] = now;
      changed = true;
      final change = rosterChange(before, now, session.selfIdentity);
      _someoneJoined |= change.joined;
      _someoneLeft |= change.left;
    }
    if (!changed) return;
    _changes.add(null);
    if (!_someoneJoined && !_someoneLeft) return;
    if (_callManager == null) {
      // Nothing to play it on: not kept for a later, unrelated change.
      _someoneJoined = _someoneLeft = false;
      return;
    }
    _rosterSoundTimer?.cancel();
    _rosterSoundTimer = Timer(rosterSoundDelay, _playRosterSound);
  }

  /// Between the join sound and the leave sound when both happened: the
  /// cue player plays one sound at a time, and the join's notes are over
  /// by then.
  static const rosterSoundGap = Duration(milliseconds: 400);
  Timer? _leaveSoundTimer;

  void _playRosterSound() {
    if (_closed) return;
    final joined = _someoneJoined;
    final left = _someoneLeft;
    _someoneJoined = _someoneLeft = false;
    final callManager = _callManager;
    // Only the call we are in: hung up meanwhile, it was the leave sound.
    if (callManager?.getCallInRoom(client, room.identifier) == null) return;
    if (joined) callManager!.activityJoinedSound();
    if (!left) return;
    if (!joined) return callManager!.activityLeftSound();
    _leaveSoundTimer = Timer(rosterSoundGap, () {
      if (callManager!.getCallInRoom(client, room.identifier) == null) return;
      callManager.activityLeftSound();
    });
  }

  /// The room is closing: nothing of its activity outlives it, and the
  /// roster it drops on the way out is not announced.
  bool _closed = false;

  @override
  void close() {
    _closed = true;
    _rosterSoundTimer?.cancel();
    _leaveSoundTimer?.cancel();
    for (final sub in _callManagerSubs) {
      sub.cancel();
    }
    _callManagerSubs.clear();
    // The room is going: nothing of its activity outlives it.
    _dropAllSessions();
  }

  // ----------------------------------------------------------- watch calls

  void _watchCallManager() {
    if (_watchingCallManager) return;
    final callManager = _callManager;
    if (callManager == null) return;
    _watchingCallManager = true;
    _callManagerSubs.add(callManager.currentSessions.onAdd.listen((session) {
      if (!_isOurCall(session)) return;
      // A call we just joined: whatever we followed before was another
      // call's (we left and came back), and its transport is dead.
      _dropAllSessions();
      _followState();
    }));
    _callManagerSubs.add(callManager.currentSessions.onRemove.listen((session) {
      if (!_isOurCall(session)) return;
      _followState();
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

/// A launch the room refused: [cause] is what the homeserver said, null
/// when we may not write the activity's state there at all.
class CallActivityLaunchException implements Exception {
  const CallActivityLaunchException(this.cause);
  const CallActivityLaunchException.notAllowed() : cause = null;

  final Object? cause;

  bool get notAllowed => cause == null;

  @override
  String toString() => 'CallActivityLaunchException: ${cause ?? 'not allowed'}';
}
