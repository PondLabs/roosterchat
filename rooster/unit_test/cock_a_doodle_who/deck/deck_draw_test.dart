import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

DeckCard card(String id, DeckTheme theme,
        {CardReach reach = CardReach.world,
        CardDifficulty difficulty = CardDifficulty.easy}) =>
    DeckCard(
      id: id,
      theme: theme,
      kind: PlaqueKind.other,
      reach: reach,
      difficulty: difficulty,
      texts: const {'en': CardText(name: 'n', caption: 'c')},
    );

void main() {
  // Each theme: two easy, one medium and one hard World card, and two
  // Brazil cards in the cultural ones.
  final deck = Deck([
    for (final theme in DeckTheme.values) ...[
      card('${theme.key}_e1', theme),
      card('${theme.key}_e2', theme),
      card('${theme.key}_m1', theme, difficulty: CardDifficulty.medium),
      card('${theme.key}_h1', theme, difficulty: CardDifficulty.hard),
      if (theme.cultural) ...[
        card('${theme.key}_br1', theme, reach: CardReach.br),
        card('${theme.key}_br2', theme,
            reach: CardReach.br, difficulty: CardDifficulty.hard),
      ],
    ],
  ]);
  final random = Random(7);
  int nextInt(int max) => random.nextInt(max);

  List<DeckCard> draw(DeckFilter filter, Set<String> used, {int count = 1}) =>
      deck.draw(filter, used: used, nextInt: nextInt, count: count);

  /// Draws one at a time, as a match does, until [times] cards are out.
  List<String> drawEach(DeckFilter filter, int times) {
    final used = <String>{};
    return [
      for (var i = 0; i < times; i++)
        (draw(filter, used).single.id..also(used.add)),
    ];
  }

  group('the draw', () {
    test('never gives a card already used while the filter has others', () {
      for (var round = 0; round < 20; round++) {
        final ids = drawEach(const DeckFilter(theme: DeckTheme.animals), 4);
        expect(ids.toSet(), hasLength(4), reason: '$ids');
      }
    });

    test('gives different cards in one draw of several', () {
      final hand = draw(const DeckFilter(), {}, count: 20);
      expect(hand.map((c) => c.id).toSet(), hasLength(20));
    });

    test('keeps to the theme', () {
      final hand = draw(const DeckFilter(theme: DeckTheme.jobs), {}, count: 4);
      expect(hand.map((c) => c.theme).toSet(), {DeckTheme.jobs});
    });

    test('Anything goes draws from all eight themes', () {
      final themes =
          draw(const DeckFilter(), {}, count: 32).map((c) => c.theme).toSet();
      expect(themes, DeckTheme.values.toSet());
    });

    test('keeps to the difficulties picked', () {
      final hand = draw(
          const DeckFilter(difficulties: {CardDifficulty.hard}), {},
          count: 8);
      expect(hand.map((c) => c.difficulty).toSet(), {CardDifficulty.hard});
    });

    test('with the filter used up, takes the nearest difficulty first', () {
      const filter = DeckFilter(
          theme: DeckTheme.animals, difficulties: {CardDifficulty.easy});
      final ids = drawEach(filter, 4);
      expect(ids.take(2).toSet(), {'animals_e1', 'animals_e2'});
      expect(ids[2], 'animals_m1');
      expect(ids[3], 'animals_h1');
    });

    test('repeats a card only once the theme and packs have no other', () {
      const filter = DeckFilter(
          theme: DeckTheme.animals, difficulties: {CardDifficulty.hard});
      final used = {'animals_e1', 'animals_e2', 'animals_m1', 'animals_h1'};
      final again = draw(filter, used).single;
      expect(used, contains(again.id));
    });

    test('a hand never holds the same card twice, even repeating', () {
      final used = {'animals_e1', 'animals_e2', 'animals_m1'};
      final hand =
          draw(const DeckFilter(theme: DeckTheme.animals), used, count: 4);
      expect(hand.map((c) => c.id).toSet(), hasLength(4));
      expect(hand.first.id, 'animals_h1');
    });

    test('gives fewer cards only when the theme and packs have fewer', () {
      expect(draw(const DeckFilter(theme: DeckTheme.animals), {}, count: 9),
          hasLength(4));
      expect(
          Deck(const []).draw(const DeckFilter(), used: {}, nextInt: nextInt),
          isEmpty);
    });

    test('follows the random numbers it is given', () {
      List<String> run(int seed) {
        final random = Random(seed);
        return deck
            .draw(const DeckFilter(),
                used: {}, nextInt: random.nextInt, count: 10)
            .map((c) => c.id)
            .toList();
      }

      expect(run(3), run(3));
    });
  });

  group('the packs', () {
    test('Brazil cards come only with the Brazil pack on', () {
      final world =
          draw(const DeckFilter(theme: DeckTheme.places), {}, count: 9);
      expect(world.map((c) => c.reach).toSet(), {CardReach.world});
      expect(world, hasLength(4));

      final both = draw(
          const DeckFilter(
              theme: DeckTheme.places, packs: {CardReach.world, CardReach.br}),
          {},
          count: 9);
      expect(both, hasLength(6));
      expect(both.map((c) => c.reach).toSet(), {CardReach.world, CardReach.br});
    });

    test('World is always on, even when left out', () {
      final hand = draw(
          const DeckFilter(theme: DeckTheme.places, packs: {CardReach.br}), {},
          count: 9);
      expect(hand.where((c) => c.reach == CardReach.world), hasLength(4));
      expect(const DeckFilter(packs: {}).packs, {CardReach.world});
    });
  });
}

extension<T> on T {
  T also(void Function(T) action) {
    action(this);
    return this;
  }
}
