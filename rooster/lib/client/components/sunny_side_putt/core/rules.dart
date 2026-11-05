// The host's game brain of Sunny Side Putt: a pure state machine with no
// rendering, no networking and no clock of its own. The host client ticks
// it (one tick = [PhysicsConfig.dt], 1/120 s), feeds it inputs as players
// send them, and broadcasts snapshots; everyone else reproduces the match
// from the latest snapshot plus the input journal.
//
// Shape of a match:
//   lobby (1-8 players join; the 9th onward queues as spectator)
//     -> per course, per hole: holePlay
//        - everyone strokes simultaneously, in the no-turn-order sense:
//          a player submits whenever their egg is at rest and it fires at
//          once, exactly at the aimed angle (the arrow's sway is the view's)
//        - the hole's timer runs the whole time (default 2 minutes), with
//          cues at 60/30/15/5 s and per-second in the last 15 s
//        - hole ends when all eggs are in the nest or the timer runs out;
//          anyone still on the green scores max(strokes, par + 2)
//      -> holeScoreboard -> next hole, next course (tournament), or a vote
//         for the next course (casual/barnyard); scores accumulate
//   -> matchOver (tournament) or until the host ends it (casual)
//
// Mid-join drops the player straight onto the current hole's tee; holes
// they missed score par. Leaving mid-hole stops their egg; at hole end they
// score max(strokes, par + 2) like any other timeout. Rejoining the same
// hole restores them at the tee, strokes kept.
//
// Host handoff: [toJson] serializes the ENTIRE engine state as plain JSON
// data (no live references), [fromJson] rebuilds it, and [replay] applies a
// journalled input list on top - the result must equal the original state
// bit for bit. Inputs are stamped with the tick they ran at, so replay
// interleaves them with the tick stream exactly as they arrived.
//
// Pure Dart - no Flutter imports, nothing random outside the seeded
// [GameRng], no wall clock (tick counts are the clock).
library;

import 'dart:math' as math;

import 'hole.dart';
import 'physics.dart';
import 'powerups.dart';
import 'rng.dart';
import 'vec.dart';

enum GameMode { casual, tournament, barnyardChaos }

enum PuttPhase {
  lobby,
  holePlay,
  holeScoreboard,
  awaitingNextCourse,
  matchOver
}

/// Golf terms for a hole's result relative to par; the UI localizes the
/// names, the core only classifies.
enum ScoreTerm {
  holeInOne,
  albatross,
  eagle,
  birdie,
  par,
  bogey,
  doubleBogey,
  tripleBogey,
  more;

  static ScoreTerm of(int strokes, int par) {
    if (strokes == 1) return ScoreTerm.holeInOne;
    final diff = strokes - par;
    if (diff <= -3) return ScoreTerm.albatross;
    if (diff == -2) return ScoreTerm.eagle;
    if (diff == -1) return ScoreTerm.birdie;
    if (diff == 0) return ScoreTerm.par;
    if (diff == 1) return ScoreTerm.bogey;
    if (diff == 2) return ScoreTerm.doubleBogey;
    if (diff == 3) return ScoreTerm.tripleBogey;
    return ScoreTerm.more;
  }
}

/// One course: an id and its holes. The match plays courses in order.
class CourseDef {
  final String id;
  final List<HoleDef> holes;

  const CourseDef({required this.id, required this.holes});
}

class PuttConfig {
  final GameMode mode;

  /// The match's course sequence up front: one course for casual and
  /// barnyard, 3/6/9 drawn courses for tournament. Casual votes add more
  /// at runtime via [startCourse], resolved against [catalog].
  final List<CourseDef> courses;

  /// All known courses, for casual's vote-next lookups. Defaults to the
  /// [courses] themselves.
  final Map<String, CourseDef> catalog;

  final int seed;
  final PhysicsConfig physics;
  final PowerUpRegistry powerUps;

  /// The per-hole time limit in seconds (the spec's 2 minutes).
  final int holeTimeLimitSeconds;

  /// How far the aim arrow sways either side of the pull (radians) at
  /// full power, held (a soft or quick putt holds still). The view draws
  /// the sway and fires the angle the arrow shows at release: the engine
  /// fires every shot exactly where it was aimed, so what the player sees
  /// is what goes. Hawk Eye holds the arrow still.
  final double wobbleMaxRadians;

  /// Players above this number join as spectators (the spec's 1-8).
  final int maxPlayers;

  /// The first course's hole the match opens on (0 = its first): the demo
  /// and practice start mid-course; a session always starts at 0.
  final int startHoleIndex;

  /// How long a hole's results stay up before the match moves on by
  /// itself (whole seconds); 0 waits for a Continue. A live session uses
  /// [puttScoreboardSeconds], so nobody stalls the call by looking away.
  final int scoreboardSeconds;

  // Not const: the default [powerUps] registry must be a fresh instance
  // per config, never the canonicalized const one (registering into a
  // const instance would leak across configs).
  PuttConfig({
    required this.mode,
    required this.courses,
    required this.seed,
    this.catalog = const {},
    PhysicsConfig? physics,
    PowerUpRegistry? powerUps,
    this.holeTimeLimitSeconds = 120,
    this.wobbleMaxRadians = 0.035,
    this.maxPlayers = 8,
    this.startHoleIndex = 0,
    this.scoreboardSeconds = 0,
  })  : physics = physics ?? const PhysicsConfig(),
        powerUps = powerUps ?? PowerUpRegistry();

  CourseDef? courseById(String id) =>
      catalog[id] ?? courses.where((c) => c.id == id).firstOrNull;

  String get fingerprint =>
      '${mode.name}|$seed|${courses.map((c) => c.id).join(',')}';
}

/// The results' pause in a live session: long enough to read the card and
/// see the last egg hatch, short enough to keep the call playing.
const int puttScoreboardSeconds = 8;

/// A player (or queued spectator) and their transient state.
class PuttPlayer {
  final String id;
  bool spectator;
  final PowerUpInventory inventory = PowerUpInventory();
  final NextShotModifiers nextShot = NextShotModifiers();
  int shields = 0;
  bool leftMidHole = false;

  PuttPlayer({required this.id, this.spectator = false});

  Map<String, Object?> toJson() => {
        'id': id,
        'spectator': spectator,
        'shields': shields,
        'left': leftMidHole,
        'inventory': inventory.toJson(),
        'nextShot': nextShot.toJson(),
      };

  factory PuttPlayer.fromJson(Map<String, Object?> json) {
    final player = PuttPlayer(
      id: json['id'] as String,
      spectator: json['spectator'] == true,
    )
      ..shields = (json['shields'] as num?)?.toInt() ?? 0
      ..leftMidHole = json['left'] == true
      ..inventory.restore((json['inventory'] as List?) ?? const []);
    final mods = json['nextShot'];
    if (mods is Map) {
      player.nextShot
        ..noWobble = mods['noWobble'] == true
        ..powerMultiplier = (mods['powerMultiplier'] as num?)?.toDouble() ?? 1
        ..hop = mods['hop'] == true
        ..magnet = mods['magnet'] == true;
    }
    return player;
  }
}

// ---- events ----------------------------------------------------------------

/// What the engine reports as the match runs, in deterministic order. The
/// game view turns these into HUD changes and sounds.
sealed class PuttEvent {
  const PuttEvent();
}

class MatchStarted extends PuttEvent {
  final GameMode mode;
  final String courseId;

  const MatchStarted({required this.mode, required this.courseId});
}

class CourseStarted extends PuttEvent {
  final String courseId;
  final int courseIndex;

  const CourseStarted({required this.courseId, required this.courseIndex});
}

class HoleStarted extends PuttEvent {
  final String holeId;
  final int par;

  /// Index of this hole across all courses played so far.
  final int globalIndex;

  const HoleStarted(
      {required this.holeId, required this.par, required this.globalIndex});
}

class ShotApplied extends PuttEvent {
  final String playerId;
  final double aimedAngle;

  /// What actually fired: the aimed angle (the engine adds nothing).
  final double actualAngle;
  final double power;

  /// Strokes the player has taken in this hole so far, this shot included.
  final int strokes;

  /// The next-shot power-ups that rode this shot (and were spent on it):
  /// Hawk Eye held it straight, Strong Coffee multiplied its power (1 is
  /// none), Chicken Hop lifts it, Nest Magnet pulls it home. The view
  /// draws each for everyone.
  final bool steady;
  final double powerMultiplier;
  final bool hop;
  final bool magnet;

  const ShotApplied({
    required this.playerId,
    required this.aimedAngle,
    required this.actualAngle,
    required this.power,
    required this.strokes,
    this.steady = false,
    this.powerMultiplier = 1,
    this.hop = false,
    this.magnet = false,
  });
}

class PlayerHoled extends PuttEvent {
  final String playerId;
  final int strokes;

  const PlayerHoled({required this.playerId, required this.strokes});
}

class HoleEnded extends PuttEvent {
  final bool completed;
  final Map<String, int> strokes;
  final Map<String, ScoreTerm> terms;

  const HoleEnded(
      {required this.completed, required this.strokes, required this.terms});
}

class TimerCue extends PuttEvent {
  final int remainingSeconds;

  const TimerCue(this.remainingSeconds);
}

class TimerTick extends PuttEvent {
  final int remainingSeconds;

  const TimerTick(this.remainingSeconds);
}

class PlayerJoined extends PuttEvent {
  final String playerId;
  final bool asSpectator;

  const PlayerJoined({required this.playerId, required this.asSpectator});
}

class PlayerLeft extends PuttEvent {
  final String playerId;

  const PlayerLeft({required this.playerId});
}

/// A player sent a quick reaction ([puttReactions]).
class PlayerReacted extends PuttEvent {
  final String playerId;
  final String reaction;

  const PlayerReacted({required this.playerId, required this.reaction});
}

class SpectatorPromoted extends PuttEvent {
  final String playerId;

  const SpectatorPromoted({required this.playerId});
}

class PowerUpPicked extends PuttEvent {
  final String playerId;
  final String effectId;

  const PowerUpPicked({required this.playerId, required this.effectId});
}

class PowerUpDropped extends PuttEvent {
  final String playerId;

  const PowerUpDropped({required this.playerId});
}

/// A player cast a power-up. Comes first among a cast's events: then any
/// [ShieldBlocked] and [PowerUpStolen] as the effect runs, and its
/// [PowerUpHit] last.
class PowerUpUsed extends PuttEvent {
  final String playerId;
  final String effectId;

  /// What the caster aimed at (a spot, a player), for the effects that
  /// take a target.
  final PowerUpTarget? target;

  /// Where the caster's egg stood as it cast (null with no egg out on the
  /// green): a Rabbit Hole leaves from here.
  final Vec2? at;

  const PowerUpUsed(
      {required this.playerId, required this.effectId, this.target, this.at});
}

/// A shielded egg (Thick Shell) shrugged off a harmful cast; the shield is
/// spent.
class ShieldBlocked extends PuttEvent {
  final String playerId;
  final String effectId;
  final String casterId;

  const ShieldBlocked(
      {required this.playerId, required this.effectId, required this.casterId});
}

/// A cast took a power-up out of another player's hand (Thieving Crow);
/// the thief's own [PowerUpPicked] (or [PowerUpDropped]) follows.
class PowerUpStolen extends PuttEvent {
  final String thiefId;
  final String victimId;
  final String effectId;

  const PowerUpStolen(
      {required this.thiefId, required this.victimId, required this.effectId});
}

/// A cast's last word: the eggs it moved or changed, in player-id order
/// (the eggs Corn Rain nudged, the Gust and the Sprinkler pushed, both
/// eggs of a Nest Swap, the caster's own for a Rabbit Hole or a Ghost
/// Egg); empty when it touched no egg.
class PowerUpHit extends PuttEvent {
  final String casterId;
  final String effectId;
  final List<String> playerIds;

  const PowerUpHit(
      {required this.casterId,
      required this.effectId,
      required this.playerIds});
}

class AwaitingNextCourse extends PuttEvent {
  const AwaitingNextCourse();
}

class MatchEnded extends PuttEvent {
  final Map<String, int> totals;

  const MatchEnded({required this.totals});
}

// ---- inputs and the journal ---------------------------------------------------

sealed class EngineInput {
  const EngineInput();

  Map<String, Object?> toJson();

  static EngineInput fromJson(Map<String, Object?> json) {
    final rawTarget = json['t'];
    final PowerUpTarget? target;
    if (rawTarget is Map) {
      target = rawTarget['k'] == 'player'
          ? PowerUpTarget.player(rawTarget['v'] as String)
          : PowerUpTarget.point(Vec2((rawTarget['x'] as num).toDouble(),
              (rawTarget['y'] as num).toDouble()));
    } else {
      target = null;
    }
    switch (json['k']) {
      case 'shot':
        return ShotInput(
            playerId: json['p'] as String,
            angle: (json['a'] as num).toDouble(),
            power: (json['w'] as num).toDouble());
      case 'powerUp':
        return PowerUpInput(
            playerId: json['p'] as String,
            effectId: json['e'] as String,
            target: target);
      case 'join':
        return JoinInput(playerId: json['p'] as String);
      case 'leave':
        return LeaveInput(playerId: json['p'] as String);
      case 'advance':
        return const AdvanceInput();
      case 'start':
        return const StartInput();
      case 'course':
        return StartCourseInput(courseId: json['c'] as String);
      case 'end':
        return const EndMatchInput();
      case 'react':
        return ReactInput(
            playerId: json['p'] as String, reaction: json['r'] as String);
    }
    throw ArgumentError.value(json, 'json', 'unknown input');
  }
}

class ShotInput extends EngineInput {
  final String playerId;
  final double angle;
  final double power;

  const ShotInput(
      {required this.playerId, required this.angle, required this.power});

  static ShotInput fromJson(Map<String, Object?> json) => ShotInput(
      playerId: json['p'] as String,
      angle: (json['a'] as num).toDouble(),
      power: (json['w'] as num).toDouble());

  @override
  Map<String, Object?> toJson() =>
      {'k': 'shot', 'p': playerId, 'a': angle, 'w': power};
}

class PowerUpInput extends EngineInput {
  final String playerId;
  final String effectId;
  final PowerUpTarget? target;

  const PowerUpInput(
      {required this.playerId, required this.effectId, this.target});

  @override
  Map<String, Object?> toJson() {
    final targetJson = target == null
        ? null
        : target!.isPlayer
            ? {'k': 'player', 'v': target!.playerId}
            : {
                'k': 'point',
                'x': target!.point!.x,
                'y': target!.point!.y,
              };
    return {'k': 'powerUp', 'p': playerId, 'e': effectId, 't': targetJson};
  }
}

class JoinInput extends EngineInput {
  final String playerId;

  const JoinInput({required this.playerId});

  @override
  Map<String, Object?> toJson() => {'k': 'join', 'p': playerId};
}

class LeaveInput extends EngineInput {
  final String playerId;

  const LeaveInput({required this.playerId});

  @override
  Map<String, Object?> toJson() => {'k': 'leave', 'p': playerId};
}

class AdvanceInput extends EngineInput {
  const AdvanceInput();

  @override
  Map<String, Object?> toJson() => {'k': 'advance'};
}

class StartInput extends EngineInput {
  const StartInput();

  @override
  Map<String, Object?> toJson() => {'k': 'start'};
}

class StartCourseInput extends EngineInput {
  final String courseId;

  const StartCourseInput({required this.courseId});

  @override
  Map<String, Object?> toJson() => {'k': 'course', 'c': courseId};
}

class EndMatchInput extends EngineInput {
  const EndMatchInput();

  @override
  Map<String, Object?> toJson() => {'k': 'end'};
}

/// The quick reactions a player (or a spectator) can send, by id.
const List<String> puttReactions = ['cheer', 'laugh', 'wow', 'fire', 'gg'];

/// A quick reaction: it changes nothing in the game, everyone sees it.
class ReactInput extends EngineInput {
  final String playerId;
  final String reaction;

  const ReactInput({required this.playerId, required this.reaction});

  @override
  Map<String, Object?> toJson() => {'k': 'react', 'p': playerId, 'r': reaction};
}

/// One accepted input, stamped with its place in the tick stream.
class JournalEntry {
  final int seq;
  final int atTick;
  final EngineInput input;

  const JournalEntry(
      {required this.seq, required this.atTick, required this.input});

  Map<String, Object?> toJson() =>
      {'seq': seq, 'at': atTick, 'in': input.toJson()};

  factory JournalEntry.fromJson(Map<String, Object?> json) => JournalEntry(
        seq: (json['seq'] as num).toInt(),
        atTick: (json['at'] as num).toInt(),
        input: EngineInput.fromJson(json['in'] as Map<String, Object?>),
      );
}

// ---- scoreboard -----------------------------------------------------------------

class ScoreRow {
  final String playerId;
  final int total;

  /// Total strokes minus the pars of the holes that produced them.
  final int relative;

  /// Strokes per global hole; null where the player did not play (yet).
  final List<int?> holeStrokes;

  const ScoreRow(
      {required this.playerId,
      required this.total,
      required this.relative,
      required this.holeStrokes});
}

// ---- the engine -----------------------------------------------------------------

class PuttEngine {
  final PuttConfig config;
  GameRng _rng;

  PuttPhase _phase = PuttPhase.lobby;

  int _tick = 0;
  int _courseIndex = 0;
  int _holeIndex = 0;
  int _holesCompleted = 0;
  int _timerTicks = 0;

  /// Ticks left in the results' pause (0: none running).
  int _scoreboardTicks = 0;

  /// Seconds left before the results move on by themselves; 0 when they
  /// wait for a Continue (or are not up).
  double get scoreboardSecondsLeft => _phase == PuttPhase.holeScoreboard
      ? _scoreboardTicks * config.physics.dt
      : 0;
  int _seq = 0;

  final List<CourseDef> _playedCourses;
  final Map<String, PuttPlayer> _players = {};
  final List<String> _spectatorQueue = [];
  final Map<String, List<int?>> _holeScores = {};
  final List<int> _holePars = [];
  final Set<String> _participants = {};
  final Map<String, int> _strokesThisHole = {};
  final Set<String> _holedThisHole = {};
  final Set<int> _cuesFired = {};
  final List<PuttEvent> _events = [];
  final List<JournalEntry> _journal = [];

  /// The world's own reports since the last [drainWorldEvents], for the
  /// view's sounds (see there).
  final List<PhysicsEvent> _worldEchoes = [];

  /// How many echoes an engine nobody drains keeps: the latest.
  static const int _worldEchoCap = 128;

  PhysicsWorld? _world;

  PuttEngine(this.config)
      : _rng = GameRng.seeded(config.seed),
        _playedCourses = List.of(config.courses);

  // ---- state accessors -----------------------------------------------------

  PuttPhase get phase => _phase;
  int get tick => _tick;
  int get timerTicksRemaining => _timerTicks;
  double get secondsRemaining => _timerTicks * config.physics.dt;

  HoleDef? get currentHole {
    if (_phase == PuttPhase.lobby) return null;
    if (_courseIndex >= _playedCourses.length) return null;
    final course = _playedCourses[_courseIndex];
    if (_holeIndex >= course.holes.length) return null;
    return course.holes[_holeIndex];
  }

  CourseDef? get currentCourse => _courseIndex < _playedCourses.length
      ? _playedCourses[_courseIndex]
      : null;

  PhysicsWorld? get world => _world;

  /// Players and queued spectators, in player-id order.
  List<PuttPlayer> get players {
    final ids = _players.keys.toList()..sort();
    return [for (final id in ids) _players[id]!];
  }

  PuttPlayer? player(String id) => _players[id];

  bool isSpectator(String playerId) =>
      _players[playerId]?.spectator ?? _spectatorQueue.contains(playerId);

  /// Strokes a player took in the running hole (0 before any).
  int strokesInHole(String playerId) => _strokesThisHole[playerId] ?? 0;

  /// Recorded strokes per global hole; null where not played.
  List<int?> holeStrokes(String playerId) =>
      List.unmodifiable(_holeScores[playerId] ?? const []);

  /// The scoreboard: players by rising total strokes, ties by player id.
  List<ScoreRow> scoreboard() {
    final rows = <ScoreRow>[];
    for (final id in _holeScores.keys.toList()..sort()) {
      final holes = _holeScores[id]!;
      var total = 0;
      var parSum = 0;
      for (var i = 0; i < holes.length && i < _holePars.length; i++) {
        final strokes = holes[i];
        if (strokes == null) continue;
        total += strokes;
        parSum += _holePars[i];
      }
      rows.add(ScoreRow(
          playerId: id,
          total: total,
          relative: total - parSum,
          holeStrokes: List.of(holes)));
    }
    rows.sort((a, b) {
      final byTotal = a.total.compareTo(b.total);
      return byTotal != 0 ? byTotal : a.playerId.compareTo(b.playerId);
    });
    return rows;
  }

  /// Total strokes per player, lowest wins.
  Map<String, int> get totals =>
      {for (final row in scoreboard()) row.playerId: row.total};

  // ---- inputs ----------------------------------------------------------------

  /// Starts the match from the lobby. Barnyard Chaos deals everyone two
  /// random power-ups here.
  bool start() => _accept(StartInput());

  bool submitShot(String playerId, double angle, double power) =>
      _accept(ShotInput(playerId: playerId, angle: angle, power: power));

  bool usePowerUp(String playerId, String effectId, [PowerUpTarget? target]) =>
      _accept(
          PowerUpInput(playerId: playerId, effectId: effectId, target: target));

  bool join(String playerId) => _accept(JoinInput(playerId: playerId));

  bool leave(String playerId) => _accept(LeaveInput(playerId: playerId));

  /// The host moves the match on: from the lobby (starts) or from a
  /// scoreboard (next hole, next course, or match end).
  bool advance() => _accept(const AdvanceInput());

  /// Casual/barnyard only: the vote settled, this course comes next.
  bool startCourse(String courseId) =>
      _accept(StartCourseInput(courseId: courseId));

  bool endMatch() => _accept(const EndMatchInput());

  /// One input, from the wire (a relayed journal entry the host made or a
  /// guest's own move). Same gate as every typed helper. Whether it took.
  bool apply(EngineInput input) => _accept(input);

  /// Advances exactly one physics tick. Only [PuttPhase.holePlay]
  /// simulates and runs its timer, but the tick count advances in every
  /// phase so the input journal stays aligned.
  void tickForward() {
    _tick++;
    if (_phase == PuttPhase.holeScoreboard && _scoreboardTicks > 0) {
      // The results' pause runs out: the match moves on by itself, at the
      // same tick on every engine that plays the journal.
      _scoreboardTicks--;
      if (_scoreboardTicks == 0) _advance();
      return;
    }
    if (_phase != PuttPhase.holePlay) return;
    final world = _world;
    if (world == null) return;

    _timerTicks--;
    _fireTimerCues();

    world.stepTick();
    _absorbWorldEvents();

    if (_everyoneDone) {
      _finishHole(completed: _allHoled);
      return;
    }
    if (_timerTicks <= 0) {
      _finishHole(completed: false);
    }
  }

  /// Bulk advance; tests and fast-forwarding use this.
  void advanceSeconds(double seconds) {
    final ticks = (seconds / config.physics.dt).round();
    for (var i = 0; i < ticks; i++) {
      tickForward();
    }
  }

  List<PuttEvent> drainEvents() {
    final drained = List.of(_events);
    _events.clear();
    return drained;
  }

  /// Events waiting for [drainEvents].
  int get pendingEventCount => _events.length;

  /// The world's own reports since the last call - an egg off a rail, a
  /// bumper, a hen or another egg, over a speed strip, off a ledge - in
  /// tick order, for the view's sounds. Echoes only: never journaled nor
  /// snapshotted, and nothing in the match reads them, so they cannot
  /// move the game.
  List<PhysicsEvent> drainWorldEvents() {
    final drained = List.of(_worldEchoes);
    _worldEchoes.clear();
    return drained;
  }

  /// Accepted inputs with a seq above [seq] - what a snapshot handoff
  /// replays. Journal entries only accumulate here; the HOST decides when
  /// to snapshot and calls [trimJournal].
  List<JournalEntry> journalSince(int seq) =>
      List.unmodifiable(_journal.where((entry) => entry.seq > seq));

  int get lastSeq => _seq;

  /// Forgets journalled inputs up to [seq], after the host snapshotted
  /// (pass the snapshot's seq).
  void trimJournal(int seq) {
    _journal.removeWhere((entry) => entry.seq <= seq);
  }

  // ---- input application ------------------------------------------------------

  bool _accept(EngineInput input) {
    final applied = _applyInput(input);
    if (applied) {
      _seq++;
      _journal.add(JournalEntry(seq: _seq, atTick: _tick, input: input));
    }
    return applied;
  }

  bool _applyInput(EngineInput input) {
    switch (input) {
      case StartInput():
        return _start();
      case ShotInput():
        return _submitShot(input);
      case PowerUpInput():
        return _usePowerUp(input);
      case JoinInput():
        return _join(input.playerId);
      case LeaveInput():
        return _leave(input.playerId);
      case AdvanceInput():
        return _advance();
      case StartCourseInput():
        return _startCourse(input.courseId);
      case EndMatchInput():
        return _endMatch();
      case ReactInput():
        return _react(input);
    }
  }

  /// A reaction from someone in the match (playing or watching), of a
  /// known kind: the event, nothing else.
  bool _react(ReactInput input) {
    if (!puttReactions.contains(input.reaction)) return false;
    final known = _players.containsKey(input.playerId) ||
        _spectatorQueue.contains(input.playerId);
    if (!known) return false;
    _events
        .add(PlayerReacted(playerId: input.playerId, reaction: input.reaction));
    return true;
  }

  /// Sends a quick reaction (see [ReactInput]).
  bool react(String playerId, String reaction) =>
      _accept(ReactInput(playerId: playerId, reaction: reaction));

  void _appendCoursePars(CourseDef course) {
    _holePars.addAll([for (final hole in course.holes) hole.par]);
  }

  bool _start() {
    if (_phase != PuttPhase.lobby) return false;
    if (_players.values.where((p) => !p.spectator).isEmpty) return false;
    _events.add(
        MatchStarted(mode: config.mode, courseId: _playedCourses.first.id));
    _holePars.clear();
    _appendCoursePars(_playedCourses.first);
    _holeIndex = config.startHoleIndex
        .clamp(0, _playedCourses.first.holes.length - 1)
        .toInt();
    if (config.mode == GameMode.barnyardChaos) {
      for (final player in players) {
        if (player.spectator) continue;
        for (var i = 0; i < 2; i++) {
          _grantRandom(player.id);
        }
      }
    }
    _startHole();
    return true;
  }

  bool _submitShot(ShotInput input) {
    if (_phase != PuttPhase.holePlay) return false;
    final player = _players[input.playerId];
    if (player == null || player.spectator || player.leftMidHole) return false;
    final ball = _world?.ball(input.playerId);
    if (ball == null || ball.holed) return false;
    if (!ball.asleep) return false; // no striking a rolling egg
    _fireShot(input);
    return true;
  }

  /// Fires ONE player's stroke the moment they send it - no turn order, no
  /// waiting on the others (the hole timer is the only pace-keeper). Input
  /// order is journalled, so replays match whatever interleaving happened.
  void _fireShot(ShotInput input) {
    final world = _world!;
    final player = _players[input.playerId]!;
    final mods = player.nextShot;
    // Exactly where it was aimed: the sway is the view's, drawn on the
    // arrow and already in the angle it sent.
    final angle = input.angle;
    var power = input.power;
    power = (power * mods.powerMultiplier).clamp(0.0, 1.0);
    if (mods.hop) {
      world.setBallFlagUntilRest(input.playerId, PowerUpFlag.hop);
    }
    if (mods.magnet) {
      world.setBallFlagUntilRest(input.playerId, PowerUpFlag.magnet);
    }
    // What rode the shot, for the event (the view shows it to everyone).
    final steady = mods.noWobble;
    final multiplier = mods.powerMultiplier;
    final hop = mods.hop;
    final magnet = mods.magnet;
    mods.clear();
    world.applyShot(input.playerId, angle, power);
    _strokesThisHole[input.playerId] =
        (_strokesThisHole[input.playerId] ?? 0) + 1;
    _events.add(ShotApplied(
        playerId: input.playerId,
        aimedAngle: input.angle,
        actualAngle: angle,
        power: power,
        strokes: _strokesThisHole[input.playerId]!,
        steady: steady,
        powerMultiplier: multiplier,
        hop: hop,
        magnet: magnet));
  }

  bool _usePowerUp(PowerUpInput input) {
    if (_phase != PuttPhase.holePlay) return false;
    final player = _players[input.playerId];
    if (player == null || player.spectator) return false;
    if (!player.inventory.removeById(input.effectId)) return false;
    final egg = _world?.ball(input.playerId);
    _events.add(PowerUpUsed(
        playerId: input.playerId,
        effectId: input.effectId,
        target: input.target,
        at: egg == null || egg.holed ? null : egg.position));
    final effect = config.powerUps.byId(input.effectId);
    if (effect == null) return true; // consumed even when unknown upstream
    final context = _PowerUpContext(this, input);
    effect.apply(context);
    final touched = context.touched.toList()..sort();
    for (final id in touched) {
      _world?.evaluatePlacement(id);
    }
    _events.add(PowerUpHit(
        casterId: input.playerId,
        effectId: input.effectId,
        playerIds: touched));
    return true;
  }

  bool _join(String playerId) {
    final existing = _players[playerId];
    if (existing != null) {
      // A player who left mid-hole rejoins: back on the tee, strokes kept.
      if (existing.leftMidHole &&
          _phase == PuttPhase.holePlay &&
          _participants.contains(playerId)) {
        existing.leftMidHole = false;
        _world?.addBall(playerId);
        _events.add(PlayerJoined(playerId: playerId, asSpectator: false));
        return true;
      }
      return false;
    }
    final activeCount = _players.values.where((p) => !p.spectator).length;
    final asSpectator = activeCount >= config.maxPlayers;
    _players[playerId] = PuttPlayer(id: playerId, spectator: asSpectator);
    _creditMissedHoles(playerId);
    if (_phase == PuttPhase.holePlay) {
      // And a null slot for the hole in progress.
      final scores = _holeScores.putIfAbsent(playerId, () => []);
      while (scores.length <= _holesCompleted) {
        scores.add(null);
      }
    }
    if (asSpectator) {
      _spectatorQueue.add(playerId);
    } else if (_phase == PuttPhase.holePlay) {
      _world?.addBall(playerId);
      _participants.add(playerId);
      _strokesThisHole.putIfAbsent(playerId, () => 0);
    }
    _events.add(PlayerJoined(playerId: playerId, asSpectator: asSpectator));
    return true;
  }

  bool _leave(String playerId) {
    final player = _players[playerId];
    if (player == null) {
      if (_spectatorQueue.remove(playerId)) {
        _events.add(PlayerLeft(playerId: playerId));
        return true;
      }
      return false;
    }
    if (_phase == PuttPhase.holePlay &&
        _participants.contains(playerId) &&
        !player.leftMidHole &&
        !_holedThisHole.contains(playerId)) {
      _world?.removeBall(playerId);
      player.leftMidHole = true;
    }
    _players.remove(playerId);
    _events.add(PlayerLeft(playerId: playerId));
    return true;
  }

  bool _advance() {
    switch (_phase) {
      case PuttPhase.lobby:
        return _start();
      case PuttPhase.holeScoreboard:
        final course = currentCourse;
        if (course == null) return false;
        _scoreboardTicks = 0;
        _holeIndex++;
        if (_holeIndex < course.holes.length) {
          _startHole();
          return true;
        }
        if (config.mode == GameMode.tournament) {
          if (_courseIndex + 1 < _playedCourses.length) {
            _courseIndex++;
            _holeIndex = 0;
            _appendCoursePars(_playedCourses[_courseIndex]);
            _startHole();
            return true;
          }
          _finishMatch();
          return true;
        }
        _phase = PuttPhase.awaitingNextCourse;
        _events.add(const AwaitingNextCourse());
        return true;
      default:
        return false;
    }
  }

  bool _startCourse(String courseId) {
    if (_phase != PuttPhase.awaitingNextCourse) return false;
    final course = config.courseById(courseId);
    if (course == null || course.holes.isEmpty) return false;
    _playedCourses.add(course);
    _courseIndex = _playedCourses.length - 1;
    _holeIndex = 0;
    _appendCoursePars(course);
    _events.add(CourseStarted(courseId: course.id, courseIndex: _courseIndex));
    _startHole();
    return true;
  }

  bool _endMatch() {
    if (_phase == PuttPhase.matchOver) return false;
    _finishMatch();
    return true;
  }

  void _finishMatch() {
    _phase = PuttPhase.matchOver;
    _events.add(MatchEnded(totals: totals));
  }

  // ---- hole lifecycle -------------------------------------------------------

  /// Everyone's egg is either in the nest or gone (left mid-hole): nothing
  /// left to play; the hole ends.
  bool get _everyoneDone => _participants.every((id) =>
      _holedThisHole.contains(id) ||
      _players[id] == null ||
      _players[id]!.leftMidHole);

  bool get _allHoled =>
      _participants.isNotEmpty && _participants.every(_holedThisHole.contains);

  void _startHole() {
    // Free slots go to the spectator queue, from the new hole's tee.
    while (true) {
      final activeCount = _players.values.where((p) => !p.spectator).length;
      if (activeCount >= config.maxPlayers || _spectatorQueue.isEmpty) break;
      final next = _spectatorQueue.removeAt(0);
      final player = _players[next];
      if (player == null) continue;
      player.spectator = false;
      _creditMissedHoles(next);
      _events.add(SpectatorPromoted(playerId: next));
    }

    _phase = PuttPhase.holePlay;
    final hole = currentHole!;
    for (final player in _players.values) {
      // A null slot for the hole about to be played (or watched).
      final scores = _holeScores.putIfAbsent(player.id, () => []);
      while (scores.length <= _holesCompleted) {
        scores.add(null);
      }
    }
    final activeIds = [
      for (final player in players)
        if (!player.spectator) player.id,
    ];
    _world =
        PhysicsWorld(hole: hole, config: config.physics, playerIds: activeIds);
    _participants
      ..clear()
      ..addAll(activeIds);
    _strokesThisHole.clear();
    _holedThisHole.clear();
    for (final player in _players.values) {
      player.leftMidHole = false;
    }
    _timerTicks = (config.holeTimeLimitSeconds / config.physics.dt).round();
    _cuesFired.clear();
    _events.add(HoleStarted(
        holeId: hole.id, par: hole.par, globalIndex: _holesCompleted));
  }

  void _finishHole({required bool completed}) {
    final par = currentHole?.par ?? 0;
    final strokes = <String, int>{};
    final terms = <String, ScoreTerm>{};
    for (final id in _participants.toList()..sort()) {
      final taken = _strokesThisHole[id] ?? 0;
      final scored =
          _holedThisHole.contains(id) ? taken : math.max(taken, par + 2);
      strokes[id] = scored;
      terms[id] = ScoreTerm.of(scored, par);
      final scores = _holeScores.putIfAbsent(id, () => []);
      while (scores.length <= _holesCompleted) {
        scores.add(null);
      }
      scores[_holesCompleted] = scored;
    }
    _holesCompleted++;
    _phase = PuttPhase.holeScoreboard;
    _scoreboardTicks = (config.scoreboardSeconds / config.physics.dt).round();
    _events
        .add(HoleEnded(completed: completed, strokes: strokes, terms: terms));
  }

  void _fireTimerCues() {
    final ticksPerSecond = (1 / config.physics.dt).round();
    for (final cue in const [60, 30, 15, 5]) {
      final mark = cue * ticksPerSecond;
      if (_timerTicks == mark && _cuesFired.add(mark)) {
        _events.add(TimerCue(cue));
      }
    }
    // The final-warning stream: one event per second for the last 15 s
    // (after the 15 s cue): 14, 13, ... 1.
    if (_timerTicks > 0 &&
        _timerTicks < 15 * ticksPerSecond &&
        _timerTicks % ticksPerSecond == 0) {
      _events.add(TimerTick(_timerTicks ~/ ticksPerSecond));
    }
  }

  void _creditMissedHoles(String playerId) {
    final scores = _holeScores.putIfAbsent(playerId, () => []);
    for (var i = 0; i < _holesCompleted && i < _holePars.length; i++) {
      if (scores.length <= i) {
        scores.add(_holePars[i]);
      } else if (scores[i] == null) {
        // A slot the player never filled (they watched as a spectator):
        // missed holes score par. Real strokes stay untouched.
        scores[i] = _holePars[i];
      }
    }
  }

  void _grantRandom(String playerId) {
    final effectId = config.powerUps.randomGrantable(_rng);
    if (effectId == null) return;
    final player = _players[playerId];
    if (player == null) return;
    if (player.inventory.add(effectId)) {
      _events.add(PowerUpPicked(playerId: playerId, effectId: effectId));
    } else {
      _events.add(PowerUpDropped(playerId: playerId));
    }
  }

  void _absorbWorldEvents() {
    final world = _world;
    if (world == null) return;
    for (final event in world.drainEvents()) {
      _worldEchoes.add(event);
      switch (event) {
        case BallCaptured():
          _holedThisHole.add(event.playerId);
          _events.add(PlayerHoled(
              playerId: event.playerId,
              strokes: _strokesThisHole[event.playerId] ?? 0));
        case BallPickedBox():
          final picks = config.mode == GameMode.barnyardChaos ? 2 : 1;
          for (var i = 0; i < picks; i++) {
            _grantRandom(event.playerId);
          }
        default:
          break;
      }
    }
    if (_worldEchoes.length > _worldEchoCap) {
      _worldEchoes.removeRange(0, _worldEchoes.length - _worldEchoCap);
    }
  }

  // ---- serialization --------------------------------------------------------

  Map<String, Object?> toJson() => {
        'v': 1,
        'fingerprint': config.fingerprint,
        'phase': _phase.name,
        'tick': _tick,
        'courseIndex': _courseIndex,
        'holeIndex': _holeIndex,
        'holesCompleted': _holesCompleted,
        'timerTicks': _timerTicks,
        'scoreboardTicks': _scoreboardTicks,
        'seq': _seq,
        'rng': _rng.toList(),
        'playedCourses': [for (final course in _playedCourses) course.id],
        'players': [for (final player in players) player.toJson()],
        'spectatorQueue': List.of(_spectatorQueue)..sort(),
        'holePars': List.of(_holePars),
        'holeScores': {
          for (final id in _holeScores.keys.toList()..sort())
            id: List.of(_holeScores[id]!),
        },
        'participants': _participants.toList()..sort(),
        'strokesThisHole': {
          for (final id in _strokesThisHole.keys.toList()..sort())
            id: _strokesThisHole[id],
        },
        'holedThisHole': _holedThisHole.toList()..sort(),
        'cuesFired': _cuesFired.toList()..sort(),
        'world': _world?.toJson(),
      };

  /// Rebuilds an engine from a snapshot. [config] must be the one the
  /// snapshot came from (same mode, seed and course ids) - static content
  /// rides in code, state rides in the snapshot.
  factory PuttEngine.fromJson(Map<String, Object?> json,
      {required PuttConfig config}) {
    final engine = PuttEngine(config);
    engine.restoreFrom(json);
    return engine;
  }

  /// Replaces this engine's state with [json]'s, the snapshot
  /// [toJson] made. [config] must be the one the snapshot came from (same
  /// mode, seed and course ids) - the fingerprint decides. Guests resnapshot
  /// with this so their local simulation never drifts far from the host's
  /// truth; [PuttEngine.fromJson] lands on the same loader.
  void restoreFrom(Map<String, Object?> json) {
    final fingerprint = json['fingerprint'];
    if (fingerprint != null && fingerprint != config.fingerprint) {
      throw ArgumentError('snapshot was made with a different config');
    }
    final playedCourses = <CourseDef>[];
    for (final id
        in ((json['playedCourses'] as List?) ?? const []).cast<String>()) {
      final course = config.courseById(id);
      if (course == null) {
        throw ArgumentError('snapshot references unknown course $id');
      }
      playedCourses.add(course);
    }
    _rng = GameRng.fromList((json['rng'] as List).cast<num>().toList());
    _phase = PuttPhase.values.byName(json['phase'] as String);
    _tick = (json['tick'] as num).toInt();
    _courseIndex = (json['courseIndex'] as num).toInt();
    _holeIndex = (json['holeIndex'] as num).toInt();
    _holesCompleted = (json['holesCompleted'] as num).toInt();
    _timerTicks = (json['timerTicks'] as num).toInt();
    _scoreboardTicks = (json['scoreboardTicks'] as num?)?.toInt() ?? 0;
    _seq = (json['seq'] as num).toInt();
    _playedCourses
      ..clear()
      ..addAll(playedCourses);
    _players.clear();
    for (final raw in (json['players'] as List?) ?? const []) {
      final player = PuttPlayer.fromJson((raw as Map).cast<String, Object?>());
      _players[player.id] = player;
    }
    _spectatorQueue
      ..clear()
      ..addAll(((json['spectatorQueue'] as List?) ?? const []).cast<String>());
    _holePars
      ..clear()
      ..addAll([
        for (final par in (json['holePars'] as List?) ?? const [])
          (par as num).toInt(),
      ]);
    final holeScores = json['holeScores'] as Map? ?? {};
    _holeScores.clear();
    for (final entry in holeScores.entries) {
      _holeScores[entry.key as String] = [
        for (final value in (entry.value as List))
          value == null ? null : (value as num).toInt(),
      ];
    }
    _participants
      ..clear()
      ..addAll(((json['participants'] as List?) ?? const []).cast<String>());
    final strokes = json['strokesThisHole'] as Map? ?? {};
    _strokesThisHole.clear();
    for (final entry in strokes.entries) {
      _strokesThisHole[entry.key as String] = (entry.value as num).toInt();
    }
    _holedThisHole
      ..clear()
      ..addAll(((json['holedThisHole'] as List?) ?? const []).cast<String>());
    _cuesFired
      ..clear()
      ..addAll([
        for (final mark in (json['cuesFired'] as List?) ?? const [])
          (mark as num).toInt(),
      ]);
    _events.clear();
    _journal.clear();
    final worldJson = json['world'];
    if (worldJson != null) {
      _world = PhysicsWorld.restore(
          hole: currentHole!,
          config: config.physics,
          state: (worldJson as Map).cast<String, Object?>());
    } else {
      _world = null;
    }
  }

  /// Host handoff determinism: rebuild from [snapshot], replay the journal
  /// entries that came after it (each stamped with the tick it ran at) and
  /// fast-forward to [untilTick] (default: the journal's furthest stamp,
  /// else the snapshot's own tick). The result must equal the original
  /// engine's state at that tick, bit for bit.
  static PuttEngine replay(
      Map<String, Object?> snapshot, List<Map<String, Object?>> journal,
      {required PuttConfig config, int? untilTick}) {
    final engine = PuttEngine.fromJson(snapshot, config: config);
    final snapshotTick = (snapshot['tick'] as num).toInt();
    final entries = [
      for (final raw in journal) JournalEntry.fromJson(raw),
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    var targetTick = untilTick ?? snapshotTick;
    for (final entry in entries) {
      if (entry.atTick > targetTick) targetTick = entry.atTick;
    }
    for (final entry in entries) {
      while (engine._tick < entry.atTick.clamp(0, targetTick)) {
        engine.tickForward();
      }
      if (!engine._applyInput(entry.input)) {
        throw StateError('journal replay rejected seq ${entry.seq}');
      }
      // Adopt the original's sequence numbering, so the replayed host's
      // next journal slice starts where the old one left off.
      engine._seq = entry.seq;
    }
    while (engine._tick < targetTick) {
      engine.tickForward();
    }
    // What the replay's ticks bumped into already happened; no echoes.
    engine._worldEchoes.clear();
    return engine;
  }
}

/// The engine's view of itself for one effect cast. The caster id travels
/// with it so effects can honor the hard no-self-harm rule; the engine
/// already removed the caster (and shielded players) from [targetBalls].
class _PowerUpContext implements PowerUpContext {
  final PuttEngine _engine;
  final PowerUpInput _input;
  final Set<String> touched = {};

  _PowerUpContext(this._engine, this._input);

  @override
  String get casterId => _input.playerId;

  @override
  PowerUpTarget? get target => _input.target;

  @override
  int get tick => _engine._world?.tick ?? 0;

  @override
  double get tickSeconds => _engine.config.physics.dt;

  @override
  GameRng get rng => _engine._rng;

  @override
  List<BallView> get targetBalls {
    final effect = _engine.config.powerUps.byId(_input.effectId);
    final harmful = effect?.harmful ?? false;
    final result = <BallView>[];
    for (final player in _engine.players) {
      if (player.spectator || player.leftMidHole) continue;
      if (player.id == casterId) continue; // hard rule: never the caster
      final ball = _engine._world?.ball(player.id);
      if (ball == null || ball.holed) continue;
      if (harmful && player.shields > 0) {
        player.shields--;
        _engine._events.add(ShieldBlocked(
            playerId: player.id,
            effectId: _input.effectId,
            casterId: casterId));
        continue;
      }
      result.add(BallView(
          playerId: player.id,
          position: ball.position,
          velocity: ball.velocity,
          holed: ball.holed));
    }
    return result;
  }

  @override
  BallView? ballOf(String playerId) {
    final ball = _engine._world?.ball(playerId);
    if (ball == null || ball.holed) return null;
    return BallView(
        playerId: playerId,
        position: ball.position,
        velocity: ball.velocity,
        holed: ball.holed);
  }

  void _touched(String playerId) => touched.add(playerId);

  @override
  void impulseBall(String playerId, Vec2 deltaVelocity) {
    _engine._world?.impulseBall(playerId, deltaVelocity);
    _touched(playerId);
  }

  @override
  void nudgeBall(String playerId, double maxSpeed) {
    _engine._world?.nudgeBall(playerId, maxSpeed, _engine._rng);
    _touched(playerId);
  }

  @override
  void teleportBall(String playerId, Vec2 to) {
    _engine._world?.teleportBall(playerId, to);
    _touched(playerId);
  }

  @override
  void swapBalls(String playerIdA, String playerIdB) {
    _engine._world?.swapBalls(playerIdA, playerIdB);
    touched
      ..add(playerIdA)
      ..add(playerIdB);
  }

  @override
  void setBallFlagFor(String playerId, PowerUpFlag flag, int durationTicks) {
    _engine._world?.setBallFlagFor(playerId, flag, durationTicks);
    _touched(playerId);
  }

  @override
  NextShotModifiers nextShotOf(String playerId) {
    final player = _engine._players[playerId] ?? _engine._players[casterId];
    return player?.nextShot ?? NextShotModifiers();
  }

  @override
  bool givePowerUp(String playerId, String effectId) {
    final player = _engine._players[playerId];
    if (player == null) return false;
    final added = player.inventory.add(effectId);
    if (added) {
      _engine._events
          .add(PowerUpPicked(playerId: playerId, effectId: effectId));
    } else {
      _engine._events.add(PowerUpDropped(playerId: playerId));
    }
    return added;
  }

  @override
  String? takePowerUp(String playerId) {
    final taken = _engine._players[playerId]?.inventory.takeFirst();
    if (taken != null && playerId != casterId) {
      _engine._events.add(PowerUpStolen(
          thiefId: casterId, victimId: playerId, effectId: taken));
    }
    return taken;
  }

  @override
  void removePowerUp(String playerId, String effectId) {
    _engine._players[playerId]?.inventory.removeById(effectId);
  }

  @override
  bool hasPowerUp(String playerId, String effectId) =>
      _engine._players[playerId]?.inventory.contains(effectId) ?? false;

  @override
  void addShield(String playerId) {
    final player = _engine._players[playerId];
    if (player != null) player.shields++;
  }

  @override
  bool shieldStops(String playerId) {
    if (playerId == casterId) return false;
    final effect = _engine.config.powerUps.byId(_input.effectId);
    if (!(effect?.harmful ?? false)) return false;
    final player = _engine._players[playerId];
    if (player == null || player.shields <= 0) return false;
    player.shields--;
    _engine._events.add(ShieldBlocked(
        playerId: playerId, effectId: _input.effectId, casterId: casterId));
    return true;
  }
}
