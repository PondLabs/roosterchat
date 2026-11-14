// Reading the deck: the cards' data files, checked, into [Deck].
//
// The data lives in assets/cock_a_doodle_who/deck/:
//
// - `cards.json`, a list of what does not depend on language:
//   `{"id": "lionel_messi", "theme": "celebrities", "kind": "person",
//   "reach": "world", "difficulty": "easy"}`;
// - `text/<language>.json` for each of [deckLanguages], a list of
//   `{"id": "lionel_messi", "name": "Lionel Messi",
//   "caption": "Argentine footballer"}`.
//
// Lists and not maps, so that an id written twice is caught rather than the
// second one silently winning.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck_card.dart';

export 'deck_card.dart';
export 'deck_draw.dart';

/// The languages the deck ships in. Every card has a name and a caption in
/// each; adding a language is adding its `text/<code>.json` and its code
/// here.
const deckLanguages = ['en', 'pt'];

/// Where the deck's data files are in the app's assets.
const deckAssetDir = 'assets/cock_a_doodle_who/deck';

/// All the cards of the game.
class Deck {
  Deck(List<DeckCard> cards)
      : cards = List.unmodifiable(cards),
        _byId = {for (final card in cards) card.id: card};

  /// Every card, in the order of the data file.
  final List<DeckCard> cards;
  final Map<String, DeckCard> _byId;

  /// The card with [id], or null when the deck has none (an id from a newer
  /// version of the game).
  DeckCard? byId(String id) => _byId[id];

  /// Builds the deck from the decoded data files: [cards] is `cards.json`,
  /// [texts] maps a language code to its `text/<code>.json`.
  ///
  /// Throws a [FormatException] for anything it cannot read: a missing
  /// field, an unknown theme, kind, reach or difficulty, an id written
  /// twice, or a card without its English text (the fallback of every
  /// other language). A card missing in another language reads in English;
  /// text over the length limits is kept. [check] reports those too.
  factory Deck.parse({
    required List<Object?> cards,
    required Map<String, List<Object?>> texts,
  }) {
    final textsById = <String, Map<String, CardText>>{};
    for (final MapEntry(key: language, value: entries) in texts.entries) {
      for (final entry in entries) {
        final map = _map(entry, '$language text');
        final id = _string(map, 'id');
        final byLanguage = textsById.putIfAbsent(id, () => {});
        if (byLanguage.containsKey(language)) {
          throw FormatException('"$id" is written twice in $language');
        }
        byLanguage[language] = CardText(
          name: _string(map, 'name'),
          caption: _string(map, 'caption'),
        );
      }
    }

    final parsed = <DeckCard>[];
    final ids = <String>{};
    for (final entry in cards) {
      final map = _map(entry, 'card');
      final id = _string(map, 'id');
      if (!ids.add(id)) throw FormatException('"$id" is in the deck twice');
      final cardTexts = textsById[id] ?? const {};
      if (!cardTexts.containsKey(deckSourceLanguage)) {
        throw FormatException('"$id" has no $deckSourceLanguage text');
      }
      parsed.add(DeckCard(
        id: id,
        theme: _enum(map, 'theme', DeckTheme.values, (t) => t.key),
        kind: _enum(map, 'kind', PlaqueKind.values, (k) => k.key),
        reach: _enum(map, 'reach', CardReach.values, (r) => r.key),
        difficulty:
            _enum(map, 'difficulty', CardDifficulty.values, (d) => d.key),
        texts: Map.unmodifiable(cardTexts),
      ));
    }
    return Deck(parsed);
  }

  /// Everything wrong with the deck's data, one line each, empty when the
  /// deck is sound: what [Deck.parse] refuses, plus a card missing in one of
  /// [languages], a name over [CardText.maxName] characters, a caption over
  /// [CardText.maxCaption] and text for a card the deck does not have.
  static List<String> check({
    required List<Object?> cards,
    required Map<String, List<Object?>> texts,
    List<String> languages = deckLanguages,
  }) {
    final Deck deck;
    try {
      deck = Deck.parse(cards: cards, texts: texts);
    } on FormatException catch (error) {
      return [error.message];
    } on TypeError catch (error) {
      return ['$error'];
    }

    final problems = <String>[];
    for (final language in languages) {
      if (!texts.containsKey(language)) problems.add('no $language texts');
    }
    for (final card in deck.cards) {
      for (final language in languages) {
        if (!card.texts.containsKey(language)) {
          problems.add('"${card.id}" has no $language text');
        }
      }
      for (final MapEntry(key: language, value: text) in card.texts.entries) {
        if (text.name.runes.length > CardText.maxName) {
          problems.add('"${card.id}" has a $language name longer than '
              '${CardText.maxName}: "${text.name}"');
        }
        if (text.caption.runes.length > CardText.maxCaption) {
          problems.add('"${card.id}" has a $language caption longer than '
              '${CardText.maxCaption}: "${text.caption}"');
        }
        if (text.name.trim().isEmpty || text.caption.trim().isEmpty) {
          problems.add('"${card.id}" has an empty $language name or caption');
        }
      }
    }
    for (final MapEntry(key: language, value: entries) in texts.entries) {
      for (final entry in entries) {
        final id = (entry as Map)['id'];
        if (deck.byId('$id') == null) {
          problems.add('$language has text for "$id", which is no card');
        }
      }
    }
    return problems;
  }
}

/// Reads the deck from the app's assets ([rootBundle] unless [bundle] is
/// given). Throws a [FormatException] when the data cannot be read; see
/// [Deck.parse].
Future<Deck> loadDeck([AssetBundle? bundle]) async {
  final assets = bundle ?? rootBundle;
  Future<List<Object?>> read(String path) async =>
      jsonDecode(await assets.loadString('$deckAssetDir/$path'))
          as List<Object?>;

  return Deck.parse(
    cards: await read('cards.json'),
    texts: {
      for (final language in deckLanguages)
        language: await read('text/$language.json'),
    },
  );
}

Map<Object?, Object?> _map(Object? entry, String what) {
  if (entry is Map) return entry;
  throw FormatException('a $what is not an object: $entry');
}

String _string(Map<Object?, Object?> map, String field) {
  final value = map[field];
  if (value is String) return value;
  throw FormatException('"${map['id']}" has no $field');
}

T _enum<T>(Map<Object?, Object?> map, String field, List<T> values,
    String Function(T) key) {
  final value = _string(map, field);
  for (final candidate in values) {
    if (key(candidate) == value) return candidate;
  }
  throw FormatException('"${map['id']}" has an unknown $field "$value"');
}
