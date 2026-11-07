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
import 'package:flutter/painting.dart' show ImageProvider;
import 'package:intl/intl.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
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

/// The version of the game's simulation: the physics and the courses'
/// data. Every client must step the same world, so a guest whose version
/// differs from the host's does not play (see
/// [PuttSessionController.outdated]). Bump it on ANY change to the physics
/// or to a course's data (geometry, boxes, pars, tuning).
const int puttPhysicsVersion = 2;

/// Every course this build ships, by id, as the engine takes them.
Map<String, CourseDef> _puttCatalog() => {
      for (final course in sunnySidePuttCourses)
        course.id: CourseDef(
            id: course.id, holes: [for (final hole in course.holes) hole.hole]),
    };

/// [puttCourseHash] of every course this build ships (a vote can pick any
/// of them, not only the launch's).
final int puttCatalogHash = puttCourseHash(_puttCatalog().values.toList());

/// A cheap fingerprint of [courses]: their holes' ids, pars, wall counts
/// and box ids (FNV-1a, the same on every platform). It catches course
/// data that changed without [puttPhysicsVersion] being bumped.
int puttCourseHash(List<CourseDef> courses) {
  final text = StringBuffer();
  for (final course in courses) {
    text.write('${course.id}{');
    for (final hole in course.holes) {
      text.write('${hole.id}:${hole.par}:${hole.walls.length}:');
      text.writeAll(hole.boxes.map((box) => box.id), ',');
      text.write(';');
    }
    text.write('}');
  }
  // The prime's multiply split (2^24 + 0x193) so no step passes 2^53: the
  // web's numbers give the same hash as native ints.
  var hash = 0x811c9dc5;
  for (final unit in text.toString().codeUnits) {
    hash ^= unit;
    hash = (((hash % 0x100) << 24) + hash * 0x193) % 0x100000000;
  }
  return hash;
}

/// Shown on the stage instead of the game to a guest whose simulation is
/// not the host's.
String labelPuttUpdateToPlay() => Intl.message("Update Rooster to play",
    name: "labelPuttUpdateToPlay",
    desc: "On the game's stage, to a player whose app runs a different "
        "version of the game than the host's: they cannot play until they "
        "update");

/// Shown on the stage instead of the game when the host's app runs an
/// older version of the game than ours.
String labelPuttHostUpdateToPlay() =>
    Intl.message("The host needs to update Rooster to play",
        name: "labelPuttHostUpdateToPlay",
        desc: "On the game's stage, to a player whose app runs a newer "
            "version of the game than the host's: nobody can play with them "
            "until the host updates");

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
    this.avatarOf,
    this.onEnded,
    this.physicsVersion = puttPhysicsVersion,
  }) {
    session.addListener(_onSessionChanged);
    _subs.add(session.relayed.listen(_onRelayed));
    _subs.add(session.inputs.listen(_onHostInput));
    // A session already under way (the call's view built again, a rejoin):
    // its match comes back from the session's last state at once - the
    // host's too, which goes on hosting from there. A host waiting for its
    // own was stuck on the stage's "Loading" for good.
    if (session.snapshot.sessionId.isNotEmpty) _adoptFromSnapshot();
  }

  final CallActivitySession session;

  /// A call identity's display name (the roster and scores show names).
  final String Function(String identity) nameOf;

  /// A call identity's avatar, when it has one (the name tags show it).
  final ImageProvider? Function(String identity)? avatarOf;

  /// The session is over (empty snapshot): the stage should go.
  final VoidCallback? onEnded;

  /// The simulation version this client runs: [puttPhysicsVersion], or
  /// another in a test playing an older or newer client.
  final int physicsVersion;

  /// How often the host streams full state, and how many beats it skips
  /// while the green sleeps: motion gets every beat, stillness every few.
  static const _beat = Duration(milliseconds: 500);
  static const _idleBeatsPerState = 4;

  /// The match, when this client has one: the host from its launch, a
  /// guest from the first payload. Null on a guest waiting for one, or
  /// [outdated].
  PuttMatch? match;

  /// The session's game runs another simulation than ours (another
  /// [puttPhysicsVersion], other course data): we do not simulate it,
  /// the stage says to update instead.
  bool outdated = false;

  /// When [outdated]: the host's game is the older one (ours is newer),
  /// so it is the host who should update.
  bool hostOutdated = false;

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
    final catalog = _puttCatalog();
    final draw = options.mode == GameMode.tournament
        ? sunnySidePuttCourses.where(
            (c) => c.availability.contains(CourseAvailability.tournament))
        : options.mode == GameMode.barnyardChaos
            ? sunnySidePuttCourses.where((c) =>
                c.availability.contains(CourseAvailability.barnyardChaos))
            : sunnySidePuttCourses.where(
                (c) => c.availability.contains(CourseAvailability.casual));
    final pool = draw.toList();
    final random = math.Random();
    final count = options.mode == GameMode.tournament
        ? (options.tournamentCount ?? 3).clamp(1, pool.length)
        : 1;
    final picked = <SunnySidePuttCourse>[];
    final chosen = pool.where((c) => c.id == options.courseId).toList();
    if (options.mode != GameMode.tournament && chosen.isNotEmpty) {
      pool
        ..clear()
        ..add(chosen.first);
    }
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
      powerUps: puttLaunchPowerUps(),
      scoreboardSeconds: puttScoreboardSeconds,
    );
  }

  /// The launcher's start: the session's host seat taken (idempotent when
  /// the room already launched this session), a fresh engine, the first
  /// payload out.
  Future<void> hostStart(PuttConfig config) async {
    await session.launch();
    match?.dispose();
    match = PuttMatch(
        config: config,
        localPlayerId: selfId,
        nameOf: nameOf,
        avatarOf: avatarOf);
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
        'physics': physicsVersion,
        'courseHash': puttCatalogHash,
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
    final awake =
        match.engine.world?.balls.any((ball) => !ball.asleep) ?? false;
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
  /// the payload rebuilds the whole engine in place. A host taking its
  /// session back plays from it as the authority: its moves go straight into
  /// its own engine, and its beat streams on from there.
  void _adoptFromSnapshot() {
    final game = session.snapshot.game;
    final rawEngine = game['engine'];
    final rawConfig = game['config'];
    if (rawEngine is! Map || rawConfig is! Map) return;
    final courseIds = (rawConfig['courses'] as List).cast<String>();
    final catalog = _puttCatalog();
    // Another version's world (an older host sends no version at all) would
    // step differently here: watch the stage's notice instead of a match
    // that drifts from the host's.
    final courses = [for (final id in courseIds) catalog[id]];
    final theirs = rawConfig['physics'];
    final skewed = theirs != physicsVersion ||
        courses.contains(null) ||
        rawConfig['courseHash'] != puttCatalogHash;
    if (skewed) {
      match?.dispose();
      match = null;
      // Not seated where we cannot play: our egg would never putt (every
      // hole running its full timer), and hosting we would freeze everyone.
      // Off to the spectators (never elected), or out of the seat so the
      // others re-elect.
      if (session.isHost) {
        unawaited(session.leave());
      } else if (joined) {
        unawaited(session.join(asPlayer: false));
      }
      final older = theirs is! num || theirs < physicsVersion;
      if (!outdated || hostOutdated != older) {
        outdated = true;
        hostOutdated = older;
        notifyListeners();
      }
      return;
    }
    outdated = false;
    hostOutdated = false;
    final mode = GameMode.values.byName(rawConfig['mode'] as String);
    final seed = (rawConfig['seed'] as num).toInt();
    final config = PuttConfig(
      mode: mode,
      seed: seed,
      catalog: catalog,
      powerUps: puttLaunchPowerUps(),
      scoreboardSeconds: puttScoreboardSeconds,
      courses: courses.whereType<CourseDef>().toList(),
    );
    final engine = PuttEngine(config);
    engine.restoreFrom(Map<String, Object?>.from(rawEngine));
    match?.dispose();
    match = PuttMatch(
      config: config,
      engine: engine,
      localPlayerId: selfId,
      remoteMove: session.isHost ? null : _sendMove,
      displayNames: {
        for (final p in engine.players) p.id: nameOf(p.id),
      },
      nameOf: nameOf,
      avatarOf: avatarOf,
    );
    _journalSeq = engine.lastSeq;
    _startTicker();
    notifyListeners();
  }

  void _sendMove(EngineInput input) =>
      session.sendInput(input.toJson()).catchError((_) {});

  /// The host's relayed moves: the accepted inputs, in journal order. A
  /// guest's own shot and power-up are already in (it fired them
  /// optimistically), so those it skips; joins, leaves and looks (its own
  /// too: the same look again changes nothing) it takes from the host like
  /// everything else. A move this version cannot read (a newer client's
  /// kind) is passed over; the next snapshot carries what it did.
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
      final JournalEntry entry;
      try {
        entry = JournalEntry.fromJson((raw).cast<String, Object?>());
      } on Object {
        continue;
      }
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
  /// it when the green is quiet). A move this version cannot read (a newer
  /// client's kind) is dropped.
  void _onHostInput(Map<String, Object?> message) {
    final match = this.match;
    if (match == null || !session.isHost) return;
    final json = Map<String, Object?>.from(message)..remove('t');
    final EngineInput input;
    try {
      input = EngineInput.fromJson(json);
    } on Object {
      return;
    }
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
    // The seat moved (our host left and we took over, or the other way):
    // our moves go straight into our engine while we host, and to the host
    // while we follow. A new host still sending to the host - itself - had
    // its own votes and reactions dropped, the game stuck at "Course done".
    match?.remoteMove = session.isHost ? null : _sendMove;
    if (session.isHost) {
      // Hosting without a match (handed the seat before the first payload
      // came, or a view built again): the session's last state is the truth.
      if (match == null) _adoptFromSnapshot();
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
    match!.engine.restoreFrom(Map<String, Object?>.from(rawEngine));
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

/// The twelve launch power-ups, in a registry of their own for each match:
/// the host and every guest build the same one, so the "?" boxes grant
/// (and the seeded draws run) alike everywhere.
PowerUpRegistry puttLaunchPowerUps() {
  final registry = PowerUpRegistry();
  registerBuiltinEffects(registry);
  return registry;
}
