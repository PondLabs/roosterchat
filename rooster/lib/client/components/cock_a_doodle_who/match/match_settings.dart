// How a match of Cock-a-Doodle-Who? is played: the mode and the host's
// settings, as the launcher picks them and the match's state carries them.
library;

import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

/// Where the plaques come from.
enum MatchMode {
  /// Each player writes a teammate's plaque, drawn in secret.
  homemade('homemade'),

  /// The plaques are cards of the deck.
  deck('deck');

  const MatchMode(this.key);

  /// Its name on the wire.
  final String key;
}

/// The host's settings for a match. Values outside a setting's range are
/// clamped into it, so a match never runs on settings the launcher could
/// not offer.
class MatchSettings {
  /// [rounds] from 1 to 5, [secondsPerQuestion] from 15 to 60 or null for
  /// no clock, [lapLimit] from 4 to 12.
  MatchSettings({
    this.mode = MatchMode.homemade,
    int rounds = defaultRounds,
    int? secondsPerQuestion = defaultSecondsPerQuestion,
    int lapLimit = defaultLapLimit,
    this.theme,
    Set<CardReach> packs = const {CardReach.world},
    Set<CardDifficulty> difficulties = const {},
  })  : rounds = rounds.clamp(minRounds, maxRounds),
        secondsPerQuestion = secondsPerQuestion?.clamp(
            minSecondsPerQuestion, maxSecondsPerQuestion),
        lapLimit = lapLimit.clamp(minLapLimit, maxLapLimit),
        packs = Set.unmodifiable({CardReach.world, ...packs}),
        difficulties = Set.unmodifiable(difficulties);

  static const minRounds = 1, maxRounds = 5, defaultRounds = 3;
  static const minSecondsPerQuestion = 15, maxSecondsPerQuestion = 60;
  static const defaultSecondsPerQuestion = 30;
  static const minLapLimit = 4, maxLapLimit = 12, defaultLapLimit = 8;

  static MatchSettings fromJson(Object? json) {
    if (json is! Map) return MatchSettings();
    T? byKey<T>(List<T> values, String Function(T) key, Object? wanted) =>
        values.where((v) => key(v) == wanted).firstOrNull;
    Set<T> keys<T>(Object? list, List<T> values, String Function(T) key) => {
          for (final k in list is List ? list : const [])
            if (byKey(values, key, k) case final value?) value,
        };
    final rounds = json['rounds'], seconds = json['seconds'];
    final laps = json['laps'];
    return MatchSettings(
      mode: byKey(MatchMode.values, (m) => m.key, json['mode']) ??
          MatchMode.homemade,
      rounds: rounds is int ? rounds : defaultRounds,
      secondsPerQuestion: seconds is int ? seconds : null,
      lapLimit: laps is int ? laps : defaultLapLimit,
      theme: byKey(DeckTheme.values, (t) => t.key, json['theme']),
      packs: keys(json['packs'], CardReach.values, (r) => r.key),
      difficulties: keys(json['levels'], CardDifficulty.values, (d) => d.key),
    );
  }

  final MatchMode mode;

  /// How many rounds the match has.
  final int rounds;

  /// How long a question waits for its first answer before the turn
  /// passes. Null: no clock, and the host may skip a turn instead.
  final int? secondsPerQuestion;

  /// How many laps a round has at most; also the points of a plaque
  /// guessed in the first lap.
  final int lapLimit;

  /// Deck: the theme of the first round, null for Anything goes. The later
  /// rounds' themes are the last-placed player's choice.
  final DeckTheme? theme;

  /// The packs that are on, [CardReach.world] always. In Homemade, the
  /// card given to a plaque nobody wrote comes from these.
  final Set<CardReach> packs;

  /// Deck: the difficulties picked; empty is every difficulty.
  final Set<CardDifficulty> difficulties;

  /// The cards a round with [theme] draws from.
  DeckFilter filter(DeckTheme? theme) =>
      DeckFilter(theme: theme, packs: packs, difficulties: difficulties);

  Map<String, Object?> toJson() => {
        'mode': mode.key,
        'rounds': rounds,
        if (secondsPerQuestion != null) 'seconds': secondsPerQuestion,
        'laps': lapLimit,
        if (theme != null) 'theme': theme!.key,
        'packs': [for (final pack in packs) pack.key],
        'levels': [for (final level in difficulties) level.key],
      };
}
