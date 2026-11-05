// The call-activity session of one call: who is in it, as the wire sees
// it. The host is authoritative: it holds the roster and the activity's
// state, answers joins and leases, and sends everyone a full snapshot
// (with a sequence number) on every change; everyone else holds the last
// snapshot it heard and asks the host for changes. A session dies with its
// call: only the room state event outlives it, written by the Matrix layer
// (the same shape as the DJ booth's queue, which state dies with the call).
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'call_activity_component.dart';
import 'call_activity_protocol.dart';
import 'call_activity_transport.dart';

/// The state of a session the host owns and everyone else follows. The
/// roster is keyed by LiveKit identity (one person may be in a call twice)
/// and carries matrix user ids for people outside the call; [game] holds
/// whatever the activity's own logic puts there, opaque to the framework.
class CallActivitySnapshot {
  const CallActivitySnapshot({
    required this.sessionId,
    required this.activityId,
    required this.hostUserId,
    required this.seq,
    this.players = const {},
    this.spectators = const {},
    this.game = const {},
  });

  /// Read back from a `state` message; null when it is not one.
  static CallActivitySnapshot? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final activity = json['activity'];
    final host = json['host'];
    final seq = json['seq'];
    if (id is! String || activity is! String) return null;
    if (host is! String || seq is! int) return null;
    Set<String> read(Object? field) => switch (field) {
          final List list => {
              for (final e in list)
                if (e is String) e
            },
          _ => const {},
        };
    return CallActivitySnapshot(
      sessionId: id,
      activityId: activity,
      hostUserId: host,
      seq: seq,
      players: read(json['players']),
      spectators: read(json['spectators']),
      game: switch (json['game']) {
        final Map game => Map<String, Object?>.from(game),
        _ => const {},
      },
    );
  }

  /// The session id, also the room state's [CallActivityRoomState] key.
  final String sessionId;

  /// The id of the activity running, a [CallActivity.id].
  final String activityId;

  /// The Matrix user id of the client hosting the session.
  final String hostUserId;

  /// Counts the snapshots the host has sent; refuse stale ones.
  final int seq;

  /// Everyone playing, by LiveKit identity.
  final Set<String> players;

  /// Everyone watching, by LiveKit identity.
  final Set<String> spectators;

  /// The activity's own state, opaque here.
  final Map<String, Object?> game;

  CallActivitySnapshot copyWith({
    Set<String>? players,
    Set<String>? spectators,
    Map<String, Object?>? game,
    int? seq,
  }) =>
      CallActivitySnapshot(
        sessionId: sessionId,
        activityId: activityId,
        hostUserId: hostUserId,
        seq: seq ?? this.seq,
        players: players ?? this.players,
        spectators: spectators ?? this.spectators,
        game: game ?? this.game,
      );

  Map<String, Object?> toJson() => {
        'id': sessionId,
        'activity': activityId,
        'host': hostUserId,
        'seq': seq,
        'players': players.toList(),
        'spectators': spectators.toList(),
        'game': game,
      };
}

/// What a client can do inside a call, sent as `caps` on arrival and on
/// request: the activities it knows, whether it can host a session, its
/// platform.
class CallActivityCaps {
  const CallActivityCaps({
    required this.userId,
    required this.activities,
    required this.canHost,
    this.platform = '',
  });

  final String userId;
  final Set<String> activities;
  final bool canHost;
  final String platform;
}

/// One activity session in one call, per `VoipSession`, host-authoritative.
///
/// [launch] writes the room state and takes the host seat; everyone else
/// [join]s as a player or a spectator, asking the host. The house is
/// re-dealt if the host vanishes: the next active player (lowest LiveKit
/// identity, the DJ booth's tie-break) claims the room with
/// [CallActivityMessageType.hostElected]; a host leaving on purpose can
/// hand its seat over with [handoffOffer], answered by `handoff-ack` or
/// `pfail`.
class CallActivitySession extends ChangeNotifier {
  CallActivitySession({
    required this.transport,
    required this.activity,
    required String selfUserId,
    this.now = DateTime.now,
  }) : _selfUserId = selfUserId {
    _subs.add(transport.incoming.listen((i) => _onIncoming(i)));
    _subs.add(transport.participantJoined.listen(_onParticipantJoined));
    _subs.add(transport.participantLeft.listen(_onParticipantLeft));
    _subs.add(transport.reconnected.listen((_) => _onReconnected()));
  }

  final CallActivityTransport transport;
  final CallActivity activity;
  final DateTime Function() now;

  final String _selfUserId;

  /// Our own matrix user id (caps send it; the roster carries user ids).
  String get selfUserId => _selfUserId;

  CallActivitySnapshot _snapshot = CallActivitySnapshot(
    sessionId: '',
    activityId: '',
    hostUserId: '',
    seq: 0,
  );

  int _seq = 0;
  bool _hosting = false;
  bool _disposed = false;
  Timer? _handoffTimeoutSub;
  final List<StreamSubscription> _subs = [];
  final StreamController<Map<String, Object?>> _inputs =
      StreamController.broadcast();
  final StreamController<Map<String, Object?>> _relayed =
      StreamController.broadcast();
  final Map<String, CallActivityCaps> _caps = {};
  final assembler = CallPartAssembler();

  /// Everything goes out in order, so snapshots arrive in the order made.
  Future<void> _outbox = Future.value();

  /// The latest state the host (or we, hosting) hold. Empty session id
  /// while we know none, i.e. before launch or `announce`.
  CallActivitySnapshot get snapshot => _snapshot;
  bool get isHost => _hosting;
  bool get hasSession => _snapshot.sessionId.isNotEmpty;
  String get selfIdentity => transport.selfIdentity;
  String? get hostIdentity => _hosts.isEmpty ? null : _host;
  String _host = '';
  final Set<String> _hosts = <String>{};
  bool get stageOpen => hasSession;
  int get seq => _snapshot.seq;

  /// Our own role, computed from the roster.
  CallActivityRole get role {
    if (_hosting) return CallActivityRole.host;
    if (!hasSession) return CallActivityRole.spectator;
    if (_snapshot.players.contains(selfIdentity))
      return CallActivityRole.player;
    return CallActivityRole.spectator;
  }

  /// Matrix user ids seen in caps, by identity.
  String? userIdOf(String identity) =>
      identity == selfIdentity ? selfUserId : _caps[identity]?.userId;

  /// Live inputs from players, seen on the host; nobody else hears them.
  Stream<Map<String, Object?>> get inputs => _inputs.stream;

  /// What [identity] told the room about its client.
  CallActivityCaps? capsOf(String identity) =>
      identity == selfIdentity ? _selfCaps : _caps[identity];

  late final CallActivityCaps _selfCaps = CallActivityCaps(
    userId: selfUserId,
    activities: {activity.id},
    canHost: true,
    platform: '',
  );

  /// Whether [identity] may be handed the session, i.e. has said it can.
  bool canHandoffTo(String identity) =>
      transport.isPresent(identity) && (capsOf(identity)?.canHost ?? false);

  // -------------------------------------------------------------- outgoing

  Future<void> _send(
    Map<String, Object?> message, [
    List<String>? to,
  ]) {
    final sent =
        _outbox.then((_) => transport.send(message, to: to), onError: (_) {});
    _outbox = sent.catchError((_) {});
    return sent;
  }

  Future<void> sendState({List<String>? to}) async {
    if (!_hosting) return;
    _sendStateNow(to);
  }

  /// How the host's fast lane arrives at everyone else: the opaque
  /// messages [hostAnnounce] sent. The activity's own layer listens here.
  Stream<Map<String, Object?>> get relayed => _relayed.stream;

  /// The host's fast lane: an opaque message to everyone in the call. The
  /// session moves it unopened (it stays under the packet limit); a
  /// non-host's call is dropped.
  Future<void> hostAnnounce(Map<String, Object?> message) async {
    if (!_hosting) return;
    await _send({'t': CallActivityMessageType.relay, 'm': message});
  }

  /// The host publishes what the activity's own state [payload] is; the
  /// snapshot now carries it, and the next [sendState] delivers it. Only
  /// the host's word counts: everyone else's call is a no-op.
  void hostGamePayload(Map<String, Object?> payload) {
    if (!_hosting) return;
    _snapshot = _snapshot.copyWith(game: payload);
  }

  Future<void> _sendStateNow(List<String>? to) async {
    final next = _snapshot.copyWith(seq: ++_seq);
    _snapshot = next;
    final json = {'t': CallActivityMessageType.state, ...next.toJson()};
    for (final packet in CallActivityProtocol.split(json) ?? const []) {
      await _send(packet, to);
    }
  }

  // ------------------------------------------------------------ lifecycle

  /// Launch a session for [activity]: become the host, announce.
  Future<void> launch({String? sessionId}) async {
    if (_hosting || hasSession) return;
    _hosting = true;
    _host = selfIdentity;
    _hosts.add(selfIdentity);
    _snapshot = CallActivitySnapshot(
      sessionId: sessionId ?? selfIdentity,
      activityId: activity.id,
      hostUserId: selfUserId,
      seq: 0,
      players: {selfIdentity},
    );
    await _send({
      't': CallActivityMessageType.announce,
      'id': _snapshot.sessionId,
      'activity': _snapshot.activityId,
      'host': selfIdentity,
      'host_uid': selfUserId,
      'seq': 0,
    });
    await sendState();
    notifyListeners();
  }

  /// Tells the host what [input] the player made (a shot, a power-up
  /// order, in the activity's own language). Only the host acts on it, so
  /// only the host receives it; the answer rides the next [sendState].
  Future<void> sendInput(Map<String, Object?> input) async => _send(
      {'t': CallActivityMessageType.input, ...input},
      _host.isNotEmpty ? [_host] : null);

  /// Learns of a session from its room state (a client entering the call
  /// after the launch starts here): the ids and the host, so [join] knows
  /// what to ask for. The first state from the host fills the rest in.
  void seedFromRoom({
    required String sessionId,
    required String activityId,
    required String hostUserId,
  }) {
    if (_hosting || hasSession) return;
    _snapshot = CallActivitySnapshot(
      sessionId: sessionId,
      activityId: activityId,
      hostUserId: hostUserId,
      seq: 0,
    );
    notifyListeners();
  }

  /// Ask the host to take us in as a player (or spectator).
  Future<void> join({bool asPlayer = true}) async {
    if (_hosting || !hasSession) return;
    await _send({
      't': CallActivityMessageType.join,
      'id': _snapshot.sessionId,
      'as': (asPlayer ? CallActivityRole.player : CallActivityRole.spectator)
          .wire,
    });
  }

  /// Tell the room we are out. A host leaving with people still in the
  /// call hands the seat over (the followers re-elect, as if it had
  /// vanished); the last one out ends the session.
  Future<void> leave() async {
    await _send({'t': CallActivityMessageType.leave});
    if (_hosting) {
      final remaining = [
        ..._snapshot.players,
        ..._snapshot.spectators,
      ].where((id) => id != selfIdentity && transport.isPresent(id));
      if (remaining.isNotEmpty) {
        _hosting = false;
        _host = '';
        _hosts.clear();
        notifyListeners();
        return;
      }
      await _endHosting(bye: true);
    }
    _leaveLocally(selfIdentity);
    notifyListeners();
  }

  /// End the session we host, telling everyone.
  Future<void> end() async {
    if (!_hosting) return;
    await _endHosting(bye: true);
    notifyListeners();
  }

  Future<void> _endHosting({required bool bye}) async {
    _hosting = false;
    _hosts.clear();
    _seq = 0;
    if (bye) await _send({'t': CallActivityMessageType.bye});
    _snapshot = CallActivitySnapshot(
        sessionId: '', activityId: '', hostUserId: '', seq: 0);
  }

  /// Offer the session to another player ([identity]); they acknowledge,
  /// and the room follows them from then on. `pfail` from them, or their
  /// leaving, keeps the seat with us.
  Future<void> handoffOffer(String identity) async {
    if (!_hosting || identity == selfIdentity) return;
    if (!canHandoffTo(identity)) return;
    _pendingHandoff.add(identity);
    await _send({
      't': CallActivityMessageType.handoffOffer,
      'to': identity,
    });
    _handoffTimeoutSub?.cancel();
    _handoffTimeoutSub = Timer(_handoffTimeout, () {
      if (_pendingHandoff.remove(identity)) _failHandoff(identity);
    });
  }

  static const _handoffTimeout = Duration(seconds: 10);

  /// Reject an offer addressed to us.

  Future<void> _failHandoff(String target) async {
    await _send({'t': CallActivityMessageType.pfail, 'who': target});
    notifyListeners();
  }

  Future<void> _acceptHandoffTo(String target) async {
    _hosting = false;
    _host = target;
    await _send({
      't': CallActivityMessageType.hostElected,
      'host': target,
      'seq': _snapshot.seq,
    });
    notifyListeners();
  }

  // ------------------------------------------------------------- incoming

  void _onIncoming(CallActivityIncoming incoming) {
    if (_disposed) return;
    final sender = incoming.sender;
    if (sender == selfIdentity) return;
    var message = incoming.message;
    if (message['t'] == CallActivityMessageType.part) {
      final whole = assembler.add(sender, message, now: now());
      if (whole == null) return;
      message = whole;
    }
    switch (message['t']) {
      case CallActivityMessageType.hello:
        _send({
          't': CallActivityMessageType.caps,
          'u': selfUserId,
          'acts': [activity.id],
          'host': true,
        }, [
          sender
        ]);
        if (hasSession || _hosting) {
          _send(
            {
              't': CallActivityMessageType.announce,
              'id': _snapshot.sessionId,
              'activity': _snapshot.activityId,
              'host': _host,
              'host_uid': _snapshot.hostUserId,
              'seq': _snapshot.seq,
            },
            [sender],
          );
        }
      case CallActivityMessageType.caps:
        _caps[sender] = CallActivityCaps(
          userId: message['u'] as String? ?? '',
          activities: {
            for (final a in (message['acts'] as List? ?? const [])) a as String,
          },
          canHost: message['host'] == true,
        );
        notifyListeners();
      case CallActivityMessageType.announce:
        _onAnnounce(sender, message);
      case CallActivityMessageType.state:
        _onState(sender, message);
      case CallActivityMessageType.join:
        _onJoin(sender, message);
        // The snapshot moved (a seat taken): whoever watches the session
        // (the activity's own bridge) hears it now, like every other move.
        notifyListeners();
      case CallActivityMessageType.leave:
        _leave(sender);
        notifyListeners();
      case CallActivityMessageType.bye:
        _endLocalSession();
        notifyListeners();
      case CallActivityMessageType.handoffOffer:
        if (message['to'] != selfIdentity) return;
        // The framework needs nothing from the target but presence: the
        // game state rides in the last snapshot. A target that knows the
        // activity accepts; one that can host but does not know it still
        // accepts (it follows snapshots), like a joining spectator.
        _send(
            {'t': CallActivityMessageType.handoffAck, 'to': sender}, [sender]);
        notifyListeners();
      case CallActivityMessageType.handoffAck:
        if (!_hosting) return;
        if (!_pendingHandoff.remove(sender)) return;
        _handoffTimeoutSub?.cancel();
        _acceptHandoffTo(sender);
      case CallActivityMessageType.pfail:
        final who = message['who'];
        if (who is! String) return;
        if (_pendingHandoff.remove(who) || who == sender) {
          _handoffTimeoutSub?.cancel();
          notifyListeners();
        }
      case CallActivityMessageType.hostElected:
        final host = message['host'];
        if (host is! String) return;
        // Who may move the seat: the host itself (its handoff), anyone
        // when we knew none, anyone when our known host is gone (the
        // recovery election), and otherwise only a claim that sorts
        // before the host we know (ties broken, split-brain bounded).
        final trusted = (_host.isNotEmpty && sender == _host) ||
            _host.isEmpty ||
            !transport.isPresent(_host);
        if (trusted || host.compareTo(_host) < 0) {
          _host = host;
          _hosts
            ..clear()
            ..add(host);
          if (host == selfIdentity) _hosting = true;
          notifyListeners();
        }
      case CallActivityMessageType.inputLease:
        if (message['to'] == selfIdentity) notifyListeners();
      case CallActivityMessageType.input:
        if (!isHost) return;
        _inputs.add(message);
      case CallActivityMessageType.relay:
        if (sender != _host && _host.isNotEmpty) return;
        final payload = message['m'];
        if (payload is Map<String, Object?>) _relayed.add(payload);
    }
  }

  void _onAnnounce(String sender, Map<String, Object?> message) {
    final id = message['id'];
    final sessionActivity = message['activity'];
    if (id is! String || sessionActivity is! String) return;
    if (sessionActivity != activity.id) return;
    // The session we are hosting beats any stale announce of the same id.
    if (_hosting && _snapshot.sessionId == id) return;
    if (_snapshot.sessionId == id) {
      final seq = message['seq'];
      if (seq is int && seq < _snapshot.seq) return;
    }
    final hostUid = message['host_uid'];
    _host = message['host'] is String ? message['host'] as String : sender;
    _hosts
      ..clear()
      ..add(_host);
    _snapshot = CallActivitySnapshot(
      sessionId: id,
      activityId: sessionActivity,
      hostUserId: hostUid is String ? hostUid : userIdOf(_host) ?? '',
      seq: message['seq'] is int ? message['seq'] as int : 0,
      players: {if (_snapshot.sessionId == id) ..._snapshot.players},
      spectators: _snapshot.sessionId == id ? _snapshot.spectators : const {},
    );
    notifyListeners();
  }

  void _onState(String sender, Map<String, Object?> message) {
    final snap = CallActivitySnapshot.fromJson(message);
    if (snap == null) return;
    if (sender != _host && _host.isNotEmpty) return;
    if (_snapshot.sessionId == snap.sessionId && snap.seq < _snapshot.seq) {
      return;
    }
    _snapshot = snap;
    if (_host.isEmpty) {
      // First state heard: its sender is the host we follow (the room
      // state's host user id names who, the wire names where).
      _host = sender;
      _hosts
        ..clear()
        ..add(sender);
    }
    notifyListeners();
  }

  void _onJoin(String sender, Map<Object?, Object?> message) {
    if (!_hosting) return;
    final asRole = CallActivityRole.parse(message['as']);
    if (asRole == null || asRole == CallActivityRole.host) return;
    if (_snapshot.sessionId.isEmpty) return;
    final players = {..._snapshot.players};
    final spectators = {..._snapshot.spectators};
    spectators.remove(sender);
    if (asRole == CallActivityRole.player) {
      if (players.contains(sender)) return;
      final room = snapshotMaxPlayers();
      if (room <= players.length) {
        // The ninth player becomes a spectator (spec: spectator queue).
        spectators.add(sender);
      } else {
        players.add(sender);
      }
    } else {
      players.remove(sender);
      spectators.add(sender);
    }
    _snapshot = _snapshot.copyWith(players: players, spectators: spectators);
    _send({
      't': CallActivityMessageType.joined,
      'id': sender,
      'as': message['as']
    }, [
      sender
    ]);
    sendState();
  }

  int snapshotMaxPlayers() => activity.maxPlayers;

  void _leave(String identity) {
    if (!_hosting) {
      _leaveLocally(identity);
      if (identity == _host && _host.isNotEmpty) {
        // Our host left politely: re-elect among the present, like when a
        // host vanishes without a word.
        _host = '';
        _hosts.clear();
        _electHostAfterLoss();
        return;
      }
      notifyListeners();
      return;
    }
    final players = {..._snapshot.players}..remove(identity);
    final spectators = {..._snapshot.spectators}..remove(identity);
    _snapshot = _snapshot.copyWith(players: players, spectators: spectators);
    if (players.isEmpty && spectators.isEmpty) {
      _endHosting(bye: true);
    }
  }

  void _leaveLocally(String identity) {
    if (!hasSession) return;
    final players = {..._snapshot.players}..remove(identity);
    final spectators = {..._snapshot.spectators}..remove(identity);
    _snapshot = _snapshot.copyWith(players: players, spectators: spectators);
  }

  void _endLocalSession() {
    _hosting = false;
    _host = '';
    _hosts.clear();
    _seq = 0;
    _snapshot = CallActivitySnapshot(
        sessionId: '', activityId: '', hostUserId: '', seq: 0);
  }

  // ------------------------------------------------------------- presence

  /// The identities whose `hello`/caps we have, in deterministic order
  /// (identity sort), present right now. Used by host election.
  List<String> get presentPlayers {
    final identities = SplayTreeSet<String>();
    for (final p in _snapshot.players) {
      if (transport.isPresent(p)) identities.add(p);
    }
    return identities.toList(growable: false);
  }

  void _onParticipantJoined(String identity) {
    if (identity == selfIdentity) return;
    // A hello from them follows; nothing to do yet.
    notifyListeners();
  }

  void _onParticipantLeft(String identity) {
    if (_disposed) return;
    final wasKnown = _snapshot.players.contains(identity) ||
        _snapshot.spectators.contains(identity);
    _caps.remove(identity);
    _leaveLocally(identity);
    if (identity != _host) {
      if (wasLostByHost(identity)) return;
      notifyListeners();
      return;
    }
    if (_hosting) {
      // Our own transport dropped us as host? Impossible (self left);
      // ignore.
      return;
    }
    _electHostAfterLoss();
    if (!wasKnown) notifyListeners();
  }

  bool wasLostByHost(String identity) => !_hosting && _host == identity;

  void _onReconnected() {
    if (_hosting) {
      sendState();
    } else {
      _send({'t': CallActivityMessageType.hello});
    }
  }

  /// The host vanished without bye: the present player with the lowest
  /// identity claims the session (the DJ booth's tie-break), everyone else
  /// follows on `hostElected`. If it is us, host on.
  void _electHostAfterLoss() {
    if (_hosting || !hasSession) return;
    final candidates = presentPlayers;
    if (candidates.isEmpty) {
      _host = '';
      _hosts.clear();
      notifyListeners();
      return;
    }
    final next = candidates.first;
    if (next != selfIdentity) {
      _host = next;
      _hosts
        ..clear()
        ..add(next);
      notifyListeners();
      return;
    }
    _becomeHostByElection();
  }

  Future<void> _becomeHostByElection() async {
    await _send({
      't': CallActivityMessageType.hostElected,
      'host': selfIdentity,
      'seq': _snapshot.seq,
    });
    _hosting = true;
    _host = selfIdentity;
    _hosts
      ..clear()
      ..add(selfIdentity);
    sendState();
    notifyListeners();
  }

  Set<String> get _pendingHandoff => _pendingHandoffSet;
  final Set<String> _pendingHandoffSet = {};

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _handoffTimeoutSub?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _inputs.close();
    _relayed.close();
    super.dispose();
  }

  bool get isDisposed => _disposed;
}
