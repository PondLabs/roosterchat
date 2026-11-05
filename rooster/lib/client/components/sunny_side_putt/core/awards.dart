// A course's awards: what each player did over the course that the match
// already raises as it happens (an egg knocked, a kicker flight, a hole in
// one, a power-up stolen, a shield that held, a dunk), tallied by the
// engine from its own events, so every client that plays the journal
// agrees, and kept in its snapshot. At the course's end the awards card
// names who did the most of each (see [puttCourseAwards]).
//
// Pure Dart, like the rest of the core: no Flutter, no clock.
library;

import 'physics.dart';
import 'vec.dart';

/// One player's course so far.
class PuttCourseStats {
  /// Eggs at rest this player's rolling egg knocked ([BallKnocked]).
  int knocks = 0;

  /// The longest flight off a kicker, takeoff to first touchdown, in world
  /// units (an egg is two [PhysicsConfig.ballRadius] long).
  double longestFlight = 0;

  /// Holes sunk with the first stroke.
  int holesInOne = 0;

  /// Power-ups taken out of someone else's hand (Thieving Crow).
  int steals = 0;

  /// Harmful casts a Thick Shell shrugged off.
  int blocks = 0;

  /// Splashes, silo swallows and trips out of bounds: back to where the
  /// stroke started.
  int dunks = 0;

  PuttCourseStats();

  bool get isEmpty =>
      knocks == 0 &&
      longestFlight == 0 &&
      holesInOne == 0 &&
      steals == 0 &&
      blocks == 0 &&
      dunks == 0;

  Map<String, Object?> toJson() => {
        if (knocks > 0) 'k': knocks,
        if (longestFlight > 0) 'f': longestFlight,
        if (holesInOne > 0) 'a': holesInOne,
        if (steals > 0) 's': steals,
        if (blocks > 0) 'b': blocks,
        if (dunks > 0) 'd': dunks,
      };

  factory PuttCourseStats.fromJson(Map<String, Object?> json) =>
      PuttCourseStats()
        ..knocks = (json['k'] as num?)?.toInt() ?? 0
        ..longestFlight = (json['f'] as num?)?.toDouble() ?? 0
        ..holesInOne = (json['a'] as num?)?.toInt() ?? 0
        ..steals = (json['s'] as num?)?.toInt() ?? 0
        ..blocks = (json['b'] as num?)?.toInt() ?? 0
        ..dunks = (json['d'] as num?)?.toInt() ?? 0;
}

/// The engine's running count for the course on the green: cleared when a
/// course starts, fed as its holes play.
class PuttCourseTally {
  final Map<String, PuttCourseStats> _stats = {};

  /// Where each egg in the air left its kicker's lip, until it comes down.
  final Map<String, Vec2> _takeoffs = {};

  /// A player's course so far (empty for someone who did none of it).
  PuttCourseStats of(String playerId) => _stats[playerId] ?? PuttCourseStats();

  /// Everyone with something on the course, by player id.
  Map<String, PuttCourseStats> get all => Map.unmodifiable(_stats);

  PuttCourseStats _mine(String playerId) =>
      _stats.putIfAbsent(playerId, PuttCourseStats.new);

  /// A new course: nothing done yet.
  void clear() {
    _stats.clear();
    _takeoffs.clear();
  }

  /// A new hole: no egg is in the air.
  void newHole() => _takeoffs.clear();

  /// What the world reported this tick.
  void seeWorld(PhysicsEvent event) {
    switch (event) {
      case BallKnocked():
        _mine(event.byPlayerId).knocks++;
      case BallLaunched():
        _takeoffs[event.playerId] = event.at;
      case BallLanded():
        // A hard landing hops again and lands once more: the flight is
        // takeoff to the first touchdown, the hop after it is not one.
        final from = _takeoffs.remove(event.playerId);
        if (from == null) return;
        final flight = (event.at - from).length;
        final mine = _mine(event.playerId);
        if (flight > mine.longestFlight) mine.longestFlight = flight;
      case BallSplashed():
        _takeoffs.remove(event.playerId);
        _mine(event.playerId).dunks++;
      case BallSwallowed():
        _takeoffs.remove(event.playerId);
        _mine(event.playerId).dunks++;
      case BallOutOfBounds():
        _takeoffs.remove(event.playerId);
        _mine(event.playerId).dunks++;
      case BallTeleported():
        _takeoffs.remove(event.playerId);
      case BallCaptured():
        _takeoffs.remove(event.playerId);
      default:
        break;
    }
  }

  /// [playerId] sank their egg on its [strokes]th stroke.
  void holed(String playerId, int strokes) {
    if (strokes == 1) _mine(playerId).holesInOne++;
  }

  /// [thiefId] took a power-up out of someone else's hand.
  void stole(String thiefId) => _mine(thiefId).steals++;

  /// [playerId]'s shield stopped a harmful cast.
  void blocked(String playerId) => _mine(playerId).blocks++;

  Map<String, Object?> toJson() => {
        'stats': {
          for (final id in _stats.keys.toList()..sort())
            if (!_stats[id]!.isEmpty) id: _stats[id]!.toJson(),
        },
        'air': {
          for (final id in _takeoffs.keys.toList()..sort())
            id: [_takeoffs[id]!.x, _takeoffs[id]!.y],
        },
      };

  /// Takes [json]'s state ([toJson]'s); a snapshot from before the tally
  /// (null) is a course with nothing done yet.
  void restore(Object? json) {
    clear();
    if (json is! Map) return;
    final stats = json['stats'];
    if (stats is Map) {
      for (final entry in stats.entries) {
        _stats[entry.key as String] = PuttCourseStats.fromJson(
            (entry.value as Map).cast<String, Object?>());
      }
    }
    final air = json['air'];
    if (air is Map) {
      for (final entry in air.entries) {
        final at = entry.value as List;
        _takeoffs[entry.key as String] =
            Vec2((at[0] as num).toDouble(), (at[1] as num).toDouble());
      }
    }
  }
}

/// The awards a course can give, in the order the card lists them.
enum PuttAwardKind {
  /// Most holes in one.
  ace,

  /// Most eggs knocked.
  bowlingBall,

  /// The longest kicker flight.
  highFlyer,

  /// Most power-ups stolen.
  stickyFingers,

  /// Most harmful casts shrugged off.
  hardBoiled,

  /// Most dunks (water, the silo, out of bounds): the booby prize.
  makingASplash;

  /// What [stats] did toward this award (0: nothing).
  double figureOf(PuttCourseStats stats) => switch (this) {
        PuttAwardKind.ace => stats.holesInOne.toDouble(),
        PuttAwardKind.bowlingBall => stats.knocks.toDouble(),
        PuttAwardKind.highFlyer => stats.longestFlight,
        PuttAwardKind.stickyFingers => stats.steals.toDouble(),
        PuttAwardKind.hardBoiled => stats.blocks.toDouble(),
        PuttAwardKind.makingASplash => stats.dunks.toDouble(),
      };
}

/// One award: who earned it and the figure it was for (a count, or the
/// flight's length in world units).
class PuttAward {
  final PuttAwardKind kind;
  final String playerId;
  final double figure;

  const PuttAward(
      {required this.kind, required this.playerId, required this.figure});

  @override
  bool operator ==(Object other) =>
      other is PuttAward &&
      other.kind == kind &&
      other.playerId == playerId &&
      other.figure == figure;

  @override
  int get hashCode => Object.hash(kind, playerId, figure);

  @override
  String toString() => 'PuttAward(${kind.name}, $playerId, $figure)';
}

/// The awards [stats] earned, at most [max], in [PuttAwardKind]'s order:
/// each goes to whoever of [standing] (the players who can win one, best
/// card first) did the most of it; a tie goes to the better card. An
/// award nobody earned is left out, so the card never says "nobody".
List<PuttAward> puttCourseAwards(
  Map<String, PuttCourseStats> stats, {
  required List<String> standing,
  int max = 4,
}) {
  final awards = <PuttAward>[];
  for (final kind in PuttAwardKind.values) {
    if (awards.length >= max) break;
    String? best;
    var bestFigure = 0.0;
    for (final id in standing) {
      final mine = stats[id];
      if (mine == null) continue;
      final figure = kind.figureOf(mine);
      if (figure > bestFigure) {
        best = id;
        bestFigure = figure;
      }
    }
    if (best != null) {
      awards.add(PuttAward(kind: kind, playerId: best, figure: bestFigure));
    }
  }
  return awards;
}
