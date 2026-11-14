import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

void main() {
  const cards = [
    {
      'id': 'cat',
      'theme': 'animals',
      'kind': 'animal',
      'reach': 'world',
      'difficulty': 'easy',
    },
    {
      'id': 'xuxa',
      'theme': 'celebrities',
      'kind': 'person',
      'reach': 'br',
      'difficulty': 'medium',
    },
  ];
  const texts = {
    'en': [
      {'id': 'cat', 'name': 'Cat', 'caption': 'a pet that purrs'},
      {'id': 'xuxa', 'name': 'Xuxa', 'caption': 'Brazilian TV host'},
    ],
    'pt': [
      {
        'id': 'cat',
        'name': 'Gato',
        'caption': 'bicho de estimação que ronrona'
      },
    ],
  };

  group('a card', () {
    test('has an id, a theme, a kind, a reach and a difficulty', () {
      final deck = Deck.parse(cards: cards, texts: texts);
      final xuxa = deck.byId('xuxa')!;
      expect(xuxa.id, 'xuxa');
      expect(xuxa.theme, DeckTheme.celebrities);
      expect(xuxa.kind, PlaqueKind.person);
      expect(xuxa.reach, CardReach.br);
      expect(xuxa.difficulty, CardDifficulty.medium);
      expect(deck.cards, hasLength(2));
    });

    test(
        'knows the eight themes, the eight kinds, both reaches and the '
        'three difficulties by their data names', () {
      expect(DeckTheme.values.map((t) => t.key), [
        'celebrities',
        'characters',
        'animals',
        'food_and_drink',
        'objects',
        'places',
        'jobs',
        'mishaps',
      ]);
      expect(PlaqueKind.values.map((k) => k.key), [
        'person',
        'character',
        'animal',
        'object',
        'place',
        'food',
        'event',
        'other',
      ]);
      expect(CardReach.values.map((r) => r.key), ['world', 'br']);
      expect(
          CardDifficulty.values.map((d) => d.key), ['easy', 'medium', 'hard']);
    });

    test('the cultural themes are the ones a regional pack adds to', () {
      expect(DeckTheme.values.where((t) => t.cultural), [
        DeckTheme.celebrities,
        DeckTheme.characters,
        DeckTheme.foodAndDrink,
        DeckTheme.places,
      ]);
    });
  });

  group('the name and caption', () {
    final deck = Deck.parse(cards: cards, texts: texts);
    final cat = deck.byId('cat')!;
    final xuxa = deck.byId('xuxa')!;

    test('come in the language asked for', () {
      expect(cat.name('pt'), 'Gato');
      expect(cat.caption('pt'), 'bicho de estimação que ronrona');
      expect(cat.name('en'), 'Cat');
      expect(cat.caption('en'), 'a pet that purrs');
    });

    test('a regional code reads its language', () {
      expect(cat.name('pt_BR'), 'Gato');
      expect(cat.name('pt-BR'), 'Gato');
    });

    test('fall back to English for a language the deck does not have', () {
      expect(cat.name('de'), 'Cat');
      expect(cat.caption('de'), 'a pet that purrs');
    });

    test('fall back to English for a card missing in that language', () {
      expect(xuxa.name('pt'), 'Xuxa');
      expect(xuxa.caption('pt'), 'Brazilian TV host');
    });
  });
}
