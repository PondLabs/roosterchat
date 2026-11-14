import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

/// The deck's data files as they ship, read from disk.
({List<Object?> cards, Map<String, List<Object?>> texts}) readFiles() {
  List<Object?> read(String path) =>
      jsonDecode(File('$deckAssetDir/$path').readAsStringSync())
          as List<Object?>;
  return (
    cards: read('cards.json'),
    texts: {
      for (final language in deckLanguages)
        language: read('text/$language.json'),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the deck shipped has no problems', () {
    final files = readFiles();
    expect(Deck.check(cards: files.cards, texts: files.texts), isEmpty);
  });

  test('every language of the deck has a file, and no other file is there', () {
    final files = Directory('$deckAssetDir/text')
        .listSync()
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(files, {for (final language in deckLanguages) '$language.json'});
    expect(deckLanguages, contains(deckSourceLanguage));
  });

  group('the starter deck', () {
    final files = readFiles();
    final deck = Deck.parse(cards: files.cards, texts: files.texts);

    test('has at least 10 World cards in every theme', () {
      for (final theme in DeckTheme.values) {
        final world = deck.cards
            .where((c) => c.theme == theme && c.reach == CardReach.world);
        expect(world.length, greaterThanOrEqualTo(10), reason: theme.key);
      }
    });

    test(
        'has at least 3 Brazil cards in every cultural theme, and none '
        'in the others', () {
      for (final theme in DeckTheme.values) {
        final brazil = deck.cards
            .where((c) => c.theme == theme && c.reach == CardReach.br);
        if (theme.cultural) {
          expect(brazil.length, greaterThanOrEqualTo(3), reason: theme.key);
        } else {
          expect(brazil, isEmpty, reason: theme.key);
        }
      }
    });

    test('has every card in English and in Portuguese', () {
      for (final card in deck.cards) {
        expect(card.texts.keys, containsAll(['en', 'pt']), reason: card.id);
      }
    });
  });

  test('the app reads the deck from its assets', () async {
    final deck = await loadDeck();
    expect(deck.cards.length, readFiles().cards.length);
    expect(deck.byId('cat')!.name('pt'), 'Gato');
  });
}
