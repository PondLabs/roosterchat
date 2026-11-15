// The state of a match of Cock-a-Doodle-Who? that everyone sees: the host
// keeps it and sends it in the session's game payload, the screens read it.
// Nothing here is a secret: the plaques' text is the custody's
// (secret/plaque_custody.dart), and who writes for whom stays out.
library;

import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_rules.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_settings.dart';

/// Where a match is.
enum MatchPhase {
  /// Waiting for the host to start; players join.
  lobby,

  /// Homemade: each player writes a teammate's plaque.
  writing,

  /// Deck: the cards are being drawn.
  dealing,

  /// Everyone looks at the others' plaques before the first question.
  /// Deck: a swap may be asked for until it ends.
  look,

  /// Turns: the player whose turn it is asks, the others answer.
  asking,

  /// Free hints to whoever has not guessed, before their plaques turn.
  rescue,

  /// The scoreboard between two rounds. Deck: the last-placed player picks
  /// the next theme.
  scores,

  /// The final result: standings and awards.
  finished,
}

/// A closed count of answers, kept for the screens until the next one.
class MatchTally {
  const MatchTally(this.asker, this.outcome, this.counts);

  static MatchTally? fromJson(Object? json) {
    if (json is! Map) return null;
    final asker = json['by'], counts = json['n'];
    final outcome =
        TallyOutcome.values.where((o) => o.name == json['is']).firstOrNull;
    if (asker is! String) return null;
    return MatchTally(asker, outcome, {
      for (final answer in MatchAnswer.values)
        if (counts is Map && counts[answer.key] is int)
          answer: counts[answer.key] as int,
    });
  }

  /// Who asked.
  final String asker;

  /// What it decided; null when the turn passed with nobody answering.
  final TallyOutcome? outcome;

  /// How many gave each answer.
  final Map<MatchAnswer, int> counts;

  Map<String, Object?> toJson() => {
        'by': asker,
        if (outcome != null) 'is': outcome!.name,
        'n': {
          for (final MapEntry(:key, :value) in counts.entries) key.key: value,
        },
      };
}

/// The match as the host last published it. The engine
/// (match_engine.dart) changes it; read it, do not write it.
class MatchState {
  MatchState({MatchSettings? settings})
      : settings = settings ?? MatchSettings();

  static MatchState fromJson(Map<String, Object?> json) {
    List<String> strings(Object? list) => [
          for (final e in list is List ? list : const [])
            if (e is String) e
        ];
    Map<String, T> map<T>(Object? json, T? Function(Object?) read) => {
          for (final MapEntry(:key, :value)
              in (json is Map ? json : const {}).entries)
            if (key is String)
              if (read(value) case final T v) key: v,
        };
    int? integer(Object? v) => v is int ? v : null;
    DeckTheme? theme(Object? key) =>
        DeckTheme.values.where((t) => t.key == key).firstOrNull;
    return MatchState(settings: MatchSettings.fromJson(json['set']))
      ..phase =
          MatchPhase.values.where((p) => p.name == json['ph']).firstOrNull ??
              MatchPhase.lobby
      ..round = integer(json['r']) ?? 0
      ..theme = theme(json['th'])
      ..order = strings(json['o'])
      ..guessed = map(json['gd'], integer)
      ..left = strings(json['lf']).toSet()
      ..swapped = strings(json['sw']).toSet()
      ..turn = integer(json['i']) ?? 0
      ..lap = integer(json['lap']) ?? 1
      ..question = integer(json['qn']) ?? 1
      ..questionId = integer(json['qid']) ?? 0
      ..answers = map(json['ans'], MatchAnswer.parse)
      ..deadline = integer(json['dl'])
      ..tallyDeadline = integer(json['tdl'])
      ..points = map(json['pts'], integer)
      ..roundPoints = map(json['rp'], integer)
      ..stats = map(json['st'], PlayerStats.fromJson)
      ..chooser = json['ch'] is String ? json['ch'] as String : null
      ..themePicked = json['nx'] is String
      ..nextTheme = theme(json['nx'])
      ..last = MatchTally.fromJson(json['last']);
  }

  /// The settings the host started the match with.
  MatchSettings settings;

  MatchPhase phase = MatchPhase.lobby;

  /// The round being played, from 1; 0 before the first.
  int round = 0;

  /// Deck: this round's theme, null for Anything goes.
  DeckTheme? theme;

  /// The round's players in the order of their turns, drawn when the round
  /// starts and kept until it ends. Who joins mid-round is not in it and
  /// plays the next one.
  List<String> order = [];

  /// Who guessed their plaque this round, and in which lap.
  Map<String, int> guessed = {};

  /// The round's players who left: their plaque is taken off and their
  /// turn skipped.
  Set<String> left = {};

  /// Deck: the owners whose plaque was swapped this round (once each).
  Set<String> swapped = {};

  /// The index in [order] of whose turn it is.
  int turn = 0;

  /// The lap of the round, from 1.
  int lap = 1;

  /// The question of the turn, from 1 to [maxQuestionsPerTurn].
  int question = 1;

  /// Counts the questions of the match: an answer names the question it is
  /// for, so one that arrives late does not count for the next.
  int questionId = 0;

  /// The answers given to the current question, by who gave them.
  Map<String, MatchAnswer> answers = {};

  /// When the phase's time is up, in milliseconds since the epoch on the
  /// host's clock: the writing, the look, the question, the rescue or the
  /// scoreboard. Null when it has no time (a question without a clock).
  int? deadline;

  /// When the count of the current question closes: 5 seconds after its
  /// first answer. Null before that.
  int? tallyDeadline;

  /// Each player's points in the match.
  Map<String, int> points = {};

  /// Each player's points in this round.
  Map<String, int> roundPoints = {};

  /// What each player did in the match, for the awards.
  Map<String, PlayerStats> stats = {};

  /// Deck, on the scoreboard: who picks the next theme.
  String? chooser;

  /// Deck, on the scoreboard: whether the theme was picked, and which
  /// ([nextTheme] null for Anything goes).
  bool themePicked = false;
  DeckTheme? nextTheme;

  /// The last count that closed.
  MatchTally? last;

  /// Whose turn it is, while [phase] is [MatchPhase.asking].
  String? get asker =>
      phase == MatchPhase.asking && turn < order.length ? order[turn] : null;

  /// The round's players still asking: neither guessed nor gone.
  List<String> get active => [
        for (final player in order)
          if (!guessed.containsKey(player) && !left.contains(player)) player,
      ];

  /// Who may answer the current question: the round's players still here
  /// but the one asking. Those who guessed keep answering.
  List<String> get responders => [
        for (final player in order)
          if (!left.contains(player) && player != asker) player,
      ];

  /// How many gave each answer to the current question.
  Map<MatchAnswer, int> get counts => {
        for (final answer in MatchAnswer.values)
          answer: answers.values.where((a) => a == answer).length,
      };

  /// The standings by [points].
  List<MatchStanding> get standings => matchStandings(points);

  /// The awards of the match so far.
  MatchAwards get awards => matchAwards(stats);

  Map<String, Object?> toJson() => {
        'set': settings.toJson(),
        'ph': phase.name,
        'r': round,
        if (theme != null) 'th': theme!.key,
        'o': order,
        'gd': guessed,
        'lf': left.toList(),
        'sw': swapped.toList(),
        'i': turn,
        'lap': lap,
        'qn': question,
        'qid': questionId,
        'ans': {
          for (final MapEntry(:key, :value) in answers.entries) key: value.key,
        },
        if (deadline != null) 'dl': deadline,
        if (tallyDeadline != null) 'tdl': tallyDeadline,
        'pts': points,
        'rp': roundPoints,
        'st': {
          for (final MapEntry(:key, :value) in stats.entries)
            key: value.toJson(),
        },
        if (chooser != null) 'ch': chooser,
        if (themePicked) 'nx': nextTheme?.key ?? 'any',
        if (last != null) 'last': last!.toJson(),
      };
}
