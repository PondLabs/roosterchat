// The cards of Cock-a-Doodle-Who?'s Deck mode. A card is the game's own
// entry - a name and a caption per language, a kind, a reach and a
// difficulty - that becomes a player's plaque when it is dealt. The cards
// are data per language (assets/cock_a_doodle_who/deck/), not translated
// messages: the deck is curated by culture, and a card known in one region
// is not known elsewhere in any language.
library;

/// A theme of the Deck mode: the subject the host picks the cards from.
/// "Anything goes" is not a theme of its own but all eight together (see
/// [DeckFilter.theme]).
enum DeckTheme {
  celebrities('celebrities', cultural: true),
  characters('characters', cultural: true),
  animals('animals'),
  foodAndDrink('food_and_drink', cultural: true),
  objects('objects'),
  places('places', cultural: true),
  jobs('jobs'),
  mishaps('mishaps');

  const DeckTheme(this.key, {this.cultural = false});

  /// Its name in the deck's data files.
  final String key;

  /// Whether a regional pack adds cards to it. Animals, objects, jobs and
  /// mishaps are the same everywhere, so only the World pack has them.
  final bool cultural;
}

/// What the owner knows about a plaque before asking: the kind of thing
/// written on it. Shared by both modes - a Homemade plaque's author picks
/// one too.
enum PlaqueKind {
  person('person'),
  character('character'),
  animal('animal'),
  object('object'),
  place('place'),
  food('food'),
  event('event'),
  other('other');

  const PlaqueKind(this.key);

  /// Its name in the deck's data files and on the wire.
  final String key;
}

/// Where a card is known. Each reach is a pack: [world] is always on, the
/// regional ones are the host's choice.
enum CardReach {
  /// Known across continents and languages.
  world('world'),

  /// Known in Brazil.
  br('br');

  const CardReach(this.key);

  /// Its name in the deck's data files.
  final String key;
}

/// How hard a card is to guess, from the easiest to the hardest.
enum CardDifficulty {
  easy('easy'),
  medium('medium'),
  hard('hard');

  const CardDifficulty(this.key);

  /// Its name in the deck's data files.
  final String key;
}

/// The language the deck falls back to when a card is missing in the one
/// asked for. Every card has it.
const deckSourceLanguage = 'en';

/// The name and caption of a card in one language.
class CardText {
  const CardText({required this.name, required this.caption});

  /// What is written on the plaque. At most [CardText.maxName] characters.
  final String name;

  /// The short line that tells the people answering what the card is, like
  /// "Argentine footballer". At most [CardText.maxCaption] characters.
  final String caption;

  static const maxName = 40;
  static const maxCaption = 60;
}

/// One card of the deck.
class DeckCard {
  const DeckCard({
    required this.id,
    required this.theme,
    required this.kind,
    required this.reach,
    required this.difficulty,
    required this.texts,
  });

  /// Unique in the deck, the same in every language; what the game sends
  /// and remembers (which cards a session has used).
  final String id;
  final DeckTheme theme;
  final PlaqueKind kind;
  final CardReach reach;
  final CardDifficulty difficulty;

  /// The name and caption by language code (`en`, `pt`).
  final Map<String, CardText> texts;

  /// The text in [language] (an app language code such as `pt`, or a tag
  /// such as `pt-BR`, which reads `pt`), else in English.
  CardText text(String language) {
    final code = language.replaceAll('-', '_');
    return texts[code] ??
        texts[code.split('_').first] ??
        texts[deckSourceLanguage]!;
  }

  /// The name in [language], else in English.
  String name(String language) => text(language).name;

  /// The caption in [language], else in English.
  String caption(String language) => text(language).caption;

  @override
  String toString() => 'DeckCard($id)';
}
