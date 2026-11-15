// The rules of Cock-a-Doodle-Who? that need no session: who writes for
// whom, what a count of answers decides, the points of a guess, the
// standings and the awards. The match's engine (match_engine.dart) plays
// them over the session.
library;

import 'dart:math';

/// How long each part of a round lasts.
abstract final class MatchTimes {
  /// Homemade: to write a teammate's plaque.
  static const writing = Duration(seconds: 60);

  /// To look at everyone's plaques before the first question.
  static const look = Duration(seconds: 10);

  /// From the first answer to a question until the count closes.
  static const answers = Duration(seconds: 5);

  /// The rescue: free hints to whoever has not guessed yet.
  static const rescue = Duration(seconds: 30);

  /// Deck: for the last-placed player to pick the next round's theme.
  static const themeChoice = Duration(seconds: 20);

  /// Homemade: the scoreboard between two rounds.
  static const scores = Duration(seconds: 10);
}

/// The most questions a player asks in one turn.
const maxQuestionsPerTurn = 3;

/// The longest text an author may write on a plaque.
const maxPlaqueText = 40;

/// An answer to the owner's question.
enum MatchAnswer {
  yes('yes'),
  no('no'),
  sortOf('sortOf'),
  gotIt('gotIt');

  const MatchAnswer(this.key);

  /// Its name on the wire.
  final String key;

  static MatchAnswer? parse(Object? key) =>
      values.where((a) => a.key == key).firstOrNull;
}

/// What a closed count of answers decides.
enum TallyOutcome {
  /// The owner guessed: the plaque is revealed.
  gotIt,

  /// Yes (sort of and a tie count as yes): the owner asks again.
  yes,

  /// No: the turn passes.
  no,
}

/// What [answers] decide, when [responders] players could answer.
///
/// Got it wins with more than half of the answers given, and with at least
/// two of them when two or more could answer. Otherwise yes, sort of and
/// got it together against no: a tie is yes. Null when nobody answered.
TallyOutcome? tallyOutcome(Iterable<MatchAnswer> answers,
    {required int responders}) {
  final given = answers.toList();
  if (given.isEmpty) return null;
  final gotIt = given.where((a) => a == MatchAnswer.gotIt).length;
  final no = given.where((a) => a == MatchAnswer.no).length;
  if (gotIt * 2 > given.length && (responders < 2 || gotIt >= 2)) {
    return TallyOutcome.gotIt;
  }
  return given.length - no >= no ? TallyOutcome.yes : TallyOutcome.no;
}

/// Homemade: who writes whose plaque, author to owner. Each of [players]
/// writes exactly one plaque, never their own, and each gets exactly one
/// author: a random derangement, drawn with [random].
Map<String, String> drawWriters(List<String> players, Random random) {
  if (players.length < 2) return const {};
  final owners = [...players];
  do {
    owners.shuffle(random);
  } while ([for (var i = 0; i < players.length; i++) i]
      .any((i) => owners[i] == players[i]));
  return {for (var i = 0; i < players.length; i++) players[i]: owners[i]};
}

/// The points of a plaque guessed in [lap] (from 1): the lap limit minus
/// the lap, plus one. With a limit of 8, a guess in the first lap is worth
/// 8 and one in the last lap 1.
int lapPoints({required int lapLimit, required int lap}) =>
    max(0, lapLimit - lap + 1);

/// The text an author may put on a plaque, trimmed: from 1 to
/// [maxPlaqueText] characters (Unicode code points). Null when [raw] is
/// empty or longer.
String? plaqueText(String raw) {
  final text = raw.trim();
  final length = text.runes.length;
  return length < 1 || length > maxPlaqueText ? null : text;
}

/// What a player did in the match, for the awards.
class PlayerStats {
  const PlayerStats({this.asked = 0, this.guessed = 0, this.noes = 0});

  static PlayerStats fromJson(Object? json) {
    int read(String key) => json is Map && json[key] is int ? json[key] : 0;
    return PlayerStats(asked: read('q'), guessed: read('g'), noes: read('n'));
  }

  /// Questions asked whose count closed.
  final int asked;

  /// Plaques guessed (in a turn, not in the rescue).
  final int guessed;

  /// Questions whose count closed on no.
  final int noes;

  PlayerStats add({int asked = 0, int guessed = 0, int noes = 0}) =>
      PlayerStats(
        asked: this.asked + asked,
        guessed: this.guessed + guessed,
        noes: this.noes + noes,
      );

  Map<String, Object?> toJson() => {'q': asked, 'g': guessed, 'n': noes};
}

/// One line of the standings.
class MatchStanding {
  const MatchStanding(this.player, this.points, this.place);

  final String player;
  final int points;

  /// From 1; players with the same points share a place.
  final int place;
}

/// The standings by [points], most first. Equal points share a place
/// (1, 2, 2, 4); within a place, by identity, so every client lists alike.
List<MatchStanding> matchStandings(Map<String, int> points) {
  final sorted = points.entries.toList()
    ..sort((a, b) => a.value != b.value
        ? b.value.compareTo(a.value)
        : a.key.compareTo(b.key));
  return [
    for (var i = 0; i < sorted.length; i++)
      MatchStanding(
        sorted[i].key,
        sorted[i].value,
        1 + sorted.indexWhere((e) => e.value == sorted[i].value),
      ),
  ];
}

/// The awards of the final result. A tie gives the award to everyone tied.
class MatchAwards {
  const MatchAwards({required this.fewestQuestions, required this.mostNoes});

  /// Bullseye: the fewest questions per plaque guessed, among the players
  /// who guessed one. Empty when nobody did.
  final Set<String> fewestQuestions;

  /// Wild guesser: the most questions answered no. Empty when no question
  /// was.
  final Set<String> mostNoes;
}

/// The awards from each player's [stats].
MatchAwards matchAwards(Map<String, PlayerStats> stats) {
  Set<String> best(Iterable<String> players, num Function(String) score,
      {required bool lowest}) {
    final list = players.toList();
    if (list.isEmpty) return const {};
    final scores = list.map(score);
    final top = lowest ? scores.reduce(min) : scores.reduce(max);
    return {
      for (final player in list)
        if (score(player) == top) player,
    };
  }

  return MatchAwards(
    fewestQuestions: best(
      stats.keys.where((p) => stats[p]!.guessed > 0),
      (p) => stats[p]!.asked / stats[p]!.guessed,
      lowest: true,
    ),
    mostNoes: best(
        stats.keys.where((p) => stats[p]!.noes > 0), (p) => stats[p]!.noes,
        lowest: false),
  );
}
