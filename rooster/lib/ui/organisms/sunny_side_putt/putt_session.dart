// The live Sunny Side Putt session on the call's stage: it owns the
// [PuttMatch] the view renders and keeps it in step with the
// [CallActivitySession] over the wire, host-authoritative — no server
// beyond the call itself.
//
// The host's engine is the truth: every accepted move fells into the
// engine's journal, which the host streams through the session's fast
// lane while the balls are in motion (and the full snapshot covers the
// rest). Guests re-lay those moves into their own engine, their own
// shots land optimistically, and the snapshots resync everyone to the
// host's truth. A client's player id is its call identity, the same key
// the session's roster uses, so the two never disagree about who plays.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';

import 'putt_launch_options.dart';
import 'putt_match.dart';

/// The launch options a launcher picks (the launch sheet's outcome) live
/// in putt_launch_options.dart, with their sheet.

/// The game's activity descriptor, registered the first time a call view
/// (or its picker) asks. Titles proper stay in English by design.
final CallActivity _descriptor = CallActivity(
  id: 'chat.commet.putt',
  displayName: () => 'Sunny Side Putt',
  icon: () => null,
  minPlayers: 1,
  maxPlayers: 8,
);

/// Registers the game's activity descriptor; harmless twice.
void registerSunnySidePutt() {
  if (CallActivityRegistry.byId(_descriptor.id) != null) return;
  CallActivityRegistry.register(_descriptor);
}

/// The stage-facing controller of a live session: one per joined client.
class PuttSessionController extends ChangeNotifier {
  PuttSessionController({
    required this.session,
    required this.nameOf,
    this.onEnded,
  }) {
    session.addListener(_onSessionChanged);
    _subs.add(session.relayed.listen(_onRelayed));
    _subs.add(session.inputs.listen(_onHostInput));
  }

  final CallActivitySession session;

  /// A call identity's display name (the roster and scores show names).
  final String Function(String identity) nameOf;

  /// The session is over (empty snapshot): the stage should go.
  final VoidCallback? onEnded;

  /// How often the host streams full state, and how many beats it skips
  /// while the green sleeps: motion gets every beat, stillness every few.
  static const _beat = Duration(milliseconds: 500);
  static const _idleBeatsPerState = 4;

  /// The match, when this client has one: the host from its launch, a
  /// guest from the first payload. Null on a guest waiting for one.
  PuttMatch? match;

  int _journalSeq = 0;
  int _beats = 0;
  bool _endedFired = false;
  final List<StreamSubscription> _subs = [];
  Timer? _ticker;

  /// The identity this client plays under (the roster's currency).
  String get selfId => session.selfIdentity;

  /// Whether the client counts as playing (its identity is on the tee).
  bool get joined => session.snapshot.players.contains(selfId);

  // ------------------------------------------------------------ launch side

  /// What the sheet picked becomes the match everyone will share: a course
  /// (or a tournament's hand of them) drawn from the launcher catalog, a
  /// fresh seed — the whole config travels in the session's payload, so
  /// every client rebuilds the exact same engine from it.
  static PuttConfig buildConfig(PuttLaunchOptions options) {
    final catalog = {
      for (final course in sunnySidePuttCourses)
        course.id: CourseDef(
            id: course.id,
            holes: [for (final hole in course.holes) hole.hole]),
    };
    final draw = options.mode == GameMode.tournament
        ? sunnySidePuttCourses
            .where((c) => c.availability.contains(CourseAvailability.tournament))
        : options.mode == GameMode.barnyardChaos
            ? sunnySidePuttCourses.where(
                (c) => c.availability.contains(CourseAvailability.barnyardChaos))
            : sunnySidePuttCourses
                .where((c) => c.availability.contains(CourseAvailability.casual));
    final pool = draw.toList();
    final random = math.Random();
    final count = options.mode == GameMode.tournament
        ? (options.tournamentCount ?? 3).clamp(1, pool.length)
        : 1;
    final picked = <SunnySidePuttCourse>[];
    for (var i = 0; i < count && pool.isNotEmpty; i++) {
      picked.add(pool.removeAt(random.nextInt(pool.length)));
    }
    return PuttConfig(
      mode: options.mode,
      courses: [
        for (final course in picked)
          CourseDef(
              id: course.id,
              holes: [for (final hole in course.holes) hole.hole]),
      ],
      catalog: catalog,
      seed: random.nextInt(1 << 31),
    );
  }

  /// The launcher's start: the session's host seat taken (idempotent when
  /// the room already launched this session), a fresh engine, the first
  /// payload out.
  Future<void> hostStart(PuttConfig config) async {
    await session.launch();
    match?.dispose();
    match = PuttMatch(config: config, localPlayerId: selfId);
    match!.boot();
    _startTicker();
    _publish();
    notifyListeners();
  }

  Map<String, Object?> _payload() {
    final match = this.match!;
    return {
      'config': {
        'mode': match.config.mode.name,
        'seed': match.config.seed,
        'courses': [for (final c in match.config.courses) c.id],
      },
      'engine': match.engine.toJson(),
    };
  }

  void _publish() {
    final match = this.match;
    if (match == null) return;
    session.hostGamePayload(_payload());
    session.sendState();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(_beat, (_) => _onBeat());
  }

  /// The host's beat: relay the journal's fresh moves, and stream a full
  /// snapshot when the green is busy (or after a few quiet beats).
  void _onBeat() {
    final match = this.match;
    if (match == null || !session.isHost) return;
    _relayJournal();
    final awake = match.engine.world?.balls.any((ball) => !ball.asleep) ?? false;
    if (awake || ++_beats >= _idleBeatsPerState) {
      _beats = 0;
      _publish();
    }
  }

  void _relayJournal() {
    final entries = match!.engine.journalSince(_journalSeq);
    if (entries.isEmpty) return;
    _journalSeq = match!.engine.lastSeq;
    session.hostAnnounce({
      'j': [for (final entry in entries) entry.toJson()],
    });
  }

  // ------------------------------------------------------------- follow side

  /// A guest's first look at the match, and then its resyncs, land here:
  /// the payload rebuilds the whole engine in place.
  void _adoptFromSnapshot() {
    final game = session.snapshot.game;
    final rawEngine = game['engine'];
    final rawConfig = game['config'];
    if (rawEngine is! Map || rawConfig is! Map) return;
    final mode = GameMode.values.byName(rawConfig['mode'] as String);
    final seed = (rawConfig['seed'] as num).toInt();
    final courseIds = (rawConfig['courses'] as List).cast<String>();
    final catalog = {
      for (final course in sunnySidePuttCourses)
        course.id: CourseDef(
            id: course.id,
            holes: [for (final hole in course.holes) hole.hole]),
    };
    final config = PuttConfig(
      mode: mode,
      seed: seed,
      catalog: catalog,
      courses: [
        for (final id in courseIds)
          catalog[id] ??
              (throw ArgumentError('snapshot names unknown course $id')),
      ],
    );
    final engine = PuttEngine(config);
    engine.restoreFrom(Map<String, Object?>.from(rawEngine));
    match?.dispose();
    match = PuttMatch(
      config: config,
      engine: engine,
      localPlayerId: selfId,
      remoteMove: (input) =>
          session.sendInput(input.toJson()).catchError((_) {}),
      displayNames: {
        for (final p in engine.players) p.id: nameOf(p.id),
      },
    );
    _journalSeq = engine.lastSeq;
    _startTicker();
    notifyListeners();
  }

  /// The host's relayed moves: the accepted inputs, in journal order. A
  /// guest's own shot and power-up are already in (it fired them
  /// optimistically), so those it skips; joins and leaves it takes from
  /// the host like everything else.
  void _onRelayed(Map<String, Object?> message) {
    final match = this.match;
    if (match == null || session.isHost) {
      // Our own relay echoes back at us when we host; the journal already
      // has everything.
      return;
    }
    final entries = message['j'];
    if (entries is! List) return;
    for (final raw in entries) {
      if (raw is! Map) continue;
      final entry = JournalEntry.fromJson((raw).cast<String, Object?>());
      if (entry.seq <= _journalSeq) continue;
      _journalSeq = entry.seq;
      final input = entry.input;
      final mine = switch (input) {
        ShotInput(:final playerId) => playerId == selfId,
        PowerUpInput(:final playerId) => playerId == selfId,
        _ => false,
      };
      if (mine) continue;
      match.engine.apply(input);
    }
  }

  // ----------------------------------------------------------------- events

  /// A player's move arrived at the host: into the engine, then on to the
  /// others (the journal does the relaying on the next beat - this beats
  /// it when the green is quiet).
  void _onHostInput(Map<String, Object?> message) {
    final match = this.match;
    if (match == null || !session.isHost) return;
    final json = Map<String, Object?>.from(message)..remove('t');
    final input = EngineInput.fromJson(json);
    match.engine.apply(input);
    _relayJournal();
    match.notifyListeners();
  }

  /// Everything the session says: the match's birth to the guest, the
  /// resyncs, the end, and the host's own roster keeping in step.
  void _onSessionChanged() {
    if (session.snapshot.sessionId.isEmpty) {
      if (!_endedFired && !session.isHost) {
        _endedFired = true;
        _stopTicker();
        onEnded?.call();
      }
      notifyListeners();
      return;
    }
    if (session.isHost) {
      if (match != null) _adoptRoster();
      return;
    }
    if (match == null) {
      _adoptFromSnapshot();
      return;
    }
    _resnapshot();
  }

  /// The host keeps the engine's roster in step with the session's: who
  /// joined the activity plays, who left is out; the journal logs both,
  /// so the guests follow.
  void _adoptRoster() {
    final match = this.match;
    if (match == null) return;
    final engine = match.engine;
    final players = session.snapshot.players;
    final seated = {for (final p in engine.players) p.id: p};
    for (final id in players) {
      if (!seated.containsKey(id) && !engine.isSpectator(id)) {
        engine.join(id);
      }
    }
    for (final id in seated.keys) {
      if (id != selfId && !players.contains(id)) {
        engine.leave(id);
      }
    }
  }

  /// The guest's periodic truth: the engine rebuilds from the payload.
  void _resnapshot() {
    final game = session.snapshot.game;
    final rawEngine = game['engine'];
    if (rawEngine is! Map) return;
    match!.engine
        .restoreFrom(Map<String, Object?>.from(rawEngine));
    _journalSeq = match!.engine.lastSeq;
    match!.notifyListeners();
  }

  /// The player asks out: the session knows first, the engine follows the
  /// host's roster diff (or, hosting, the next player takes over).
  Future<void> leave() async {
    await session.leave();
  }

  /// Test seams: the adopt and roster paths, driven by hand (production
  /// calls them from the session's own notifications). Deliberately not
  /// @visibleForTesting: this repo's tests live in `unit_test/`, which the
  /// lint does not recognize as a test location.
  void adoptForTest() => _adoptFromSnapshot();

  void adoptRosterForTest() => _adoptRoster();

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    session.removeListener(_onSessionChanged);
    for (final sub in _subs) {
      sub.cancel();
    }
    match?.dispose();
    match = null;
    super.dispose();
  }
}
