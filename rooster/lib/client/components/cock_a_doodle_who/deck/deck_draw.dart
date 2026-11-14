// Drawing cards from the deck for the plaques of a round.
library;

import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

/// What the host picked for the Deck mode: which cards a draw may give.
class DeckFilter {
  /// The defaults are Anything goes, the World pack and every difficulty.
  const DeckFilter({
    this.theme,
    Set<CardReach> packs = const {CardReach.world},
    this.difficulties = const {},
  }) : _packs = packs;

  /// The theme, or null for Anything goes: all eight themes together.
  final DeckTheme? theme;

  final Set<CardReach> _packs;

  /// The packs that are on. [CardReach.world] always is, whatever was
  /// passed; a regional card comes only with its pack on.
  Set<CardReach> get packs => {CardReach.world, ..._packs};

  /// The difficulties picked; empty is every difficulty.
  final Set<CardDifficulty> difficulties;

  /// Whether [card] is of the theme and in a pack that is on (the
  /// difficulty aside, which a draw relaxes when it must).
  bool admits(DeckCard card) =>
      (theme == null || card.theme == theme) &&
      (card.reach == CardReach.world || _packs.contains(card.reach));

  /// The difficulties a draw takes after relaxing [step] times: those
  /// picked and the ones up to [step] levels away from any of them.
  Set<CardDifficulty> _relaxed(int step) => difficulties.isEmpty
      ? CardDifficulty.values.toSet()
      : {
          for (final difficulty in CardDifficulty.values)
            if (difficulties
                .any((d) => (d.index - difficulty.index).abs() <= step))
              difficulty,
        };
}

/// Drawing from a [Deck].
extension DeckDraw on Deck {
  /// Draws [count] different cards that [filter] admits, none of them in
  /// [used] (the ids the session has dealt so far; add the ones drawn
  /// before the next draw).
  ///
  /// When the cards of the picked difficulties run out, the draw takes the
  /// nearest difficulty next (medium after easy, then hard), and only once
  /// every card of the theme and packs is used does it give a used card
  /// again. It gives fewer than [count] only when the theme and packs have
  /// fewer cards in all.
  ///
  /// [nextInt] returns a number from 0 to just below its argument; pass the
  /// game's seeded generator so that every client draws alike.
  List<DeckCard> draw(
    DeckFilter filter, {
    required Set<String> used,
    required int Function(int max) nextInt,
    int count = 1,
  }) {
    final candidates = cards.where(filter.admits).toList();
    final hand = <DeckCard>[];
    final inHand = <String>{};

    List<DeckCard> pool() {
      for (var step = 0; step < CardDifficulty.values.length; step++) {
        final difficulties = filter._relaxed(step);
        final fresh = [
          for (final card in candidates)
            if (!used.contains(card.id) &&
                !inHand.contains(card.id) &&
                difficulties.contains(card.difficulty))
              card,
        ];
        if (fresh.isNotEmpty) return fresh;
      }
      return [
        for (final card in candidates)
          if (!inHand.contains(card.id)) card,
      ];
    }

    while (hand.length < count) {
      final from = pool();
      if (from.isEmpty) break;
      final card = from[nextInt(from.length)];
      hand.add(card);
      inHand.add(card.id);
    }
    return hand;
  }
}
