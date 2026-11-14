// The plaques' custody beyond the secret: the deck never deals a card
// twice, a plaque outlives its author, its holders and the host, the reveal
// gives the owner what was written, and the public record reads back as it
// was written.

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/secret/plaque_custody.dart';

import 'plaque_sim.dart';

/// A session of three Deck rounds with swaps, and in one seed out of three
/// a host that vanishes before the second. Returns the card of every plaque
/// that was on a forehead, by tag.
Future<Map<String, String>> _deckSession(int count, int seed) async {
  // Ten cards a theme: a theme runs out, and the draw has to leave it.
  final sim = Sim(count, seed: seed, deck: simDeck(perTheme: 10));
  await sim.start();
  final foreheads = <String, String>{};

  void record() {
    for (final MapEntry(key: owner, value: entry)
        in sim.host.custody.ledger.entries.entries) {
      if (entry.tag == null || entry.isOpen) continue;
      foreheads[entry.tag!] = sim.truth(owner)!.cardId!;
    }
    final inPlay = [for (final p in sim.players) sim.truth(p)?.cardId];
    expect(inPlay.toSet().length, inPlay.length,
        reason: 'seed $seed: a card twice in the round: $inPlay');
    expect(sim.misplaced(), isEmpty, reason: 'seed $seed');
  }

  for (var round = 1; round <= 3; round++) {
    if (round == 2 && seed % 3 == 0 && count > 2) {
      final gone = sim.host.id;
      await sim.vanish(gone);
      await sim.retire(gone);
    }
    final theme = DeckTheme.values[(seed + round) % DeckTheme.values.length];
    await sim.deckRound(DeckFilter(theme: theme));
    record();
    await sim.deal(sim.host.id, DeckFilter(theme: theme));
    record();
    await sim.deal(sim.players.last, DeckFilter(theme: theme));
    record();
    for (final owner in sim.players) {
      await sim.reveal(owner);
    }
  }
  expect(sim.leaks(), isEmpty, reason: 'seed $seed');
  await sim.close();
  return foreheads;
}

void main() {
  group('the deck', () {
    for (final count in [2, 3, 8]) {
      test('$count clients, 200 seeds: no card twice in a round or a session',
          () async {
        for (var seed = 1; seed <= 200; seed++) {
          final foreheads = await _deckSession(count, seed);
          // Three rounds, each with every player's card and two swaps.
          expect(foreheads.length, greaterThanOrEqualTo(3 * 2 + 6));
          expect(foreheads.values.toSet().length, foreheads.length,
              reason: 'seed $seed: a card twice in the session: $foreheads');
        }
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });

  group('a plaque can still be revealed to its owner', () {
    for (final count in [3, 8]) {
      test('$count clients: after its author left', () async {
        final sim = Sim(count);
        addTearDown(sim.close);
        await sim.start();
        await sim.homemadeRound();
        final author = sim.players.last;

        // The author of the host's plaque leaves the game.
        await sim[author].session.leave();
        await sim.settle();
        await sim.retire(author);
        await sim.reveal('p0');
        await sim.reveal('p1');

        final hosts = sim['p0'].custody.plaqueOf('p0')!;
        expect(hosts.text, 'homemade for p0 by $author in 1');
        expect(hosts.author, author);
        expect(hosts.kind, PlaqueKind.person);
        final other = sim['p1'].custody.plaqueOf('p1')!;
        expect(other.text, 'homemade for p1 by p0 in 1');
        expect(other.author, 'p0');
        expect(sim.leaks(), isEmpty);
      });

      test('$count clients: after everyone who held it but one left', () async {
        final sim = Sim(count);
        addTearDown(sim.close);
        await sim.start();
        await sim.deckRound();
        final truth = sim.truth('p0')!;
        final last = sim.players.last;

        // p1 drew the host's card. It goes, and so does everyone but one.
        for (final id in sim.players) {
          if (id == 'p0' || id == last) continue;
          await sim.vanish(id);
          await sim.retire(id);
        }
        await sim.reveal('p0');

        final revealed = sim['p0'].custody.plaqueOf('p0')!;
        expect(revealed.cardId, truth.cardId);
        expect(revealed.text, truth.text);
        expect(revealed.caption, truth.caption);
        expect(revealed.author, isNull);
        expect(sim.leaks(), isEmpty);
      });

      test('$count clients: after the host changed', () async {
        final sim = Sim(count);
        addTearDown(sim.close);
        await sim.start();
        await sim.homemadeRound();
        final truths = {for (final p in sim.players) p: sim.truth(p)!};

        await sim.vanish('p0');
        await sim.retire('p0');
        expect(sim.host.id, 'p1');

        for (final owner in sim.players) {
          await sim.reveal(owner);
          final revealed = sim[owner].custody.plaqueOf(owner)!;
          expect(revealed.text, truths[owner]!.text);
          expect(revealed.author, truths[owner]!.author);
        }
        // The new host's plaque was written by the host that left.
        expect(sim['p1'].custody.plaqueOf('p1')!.author, 'p0');
        expect(sim.leaks(), isEmpty);
      });
    }
  });

  group('asking for a plaque', () {
    /// Someone in the session whose client holds no plaque: a spectator
    /// that sorts before every player, so it is asked first.
    Future<CallActivitySession> silentSpectator(Sim sim) async {
      final session = CallActivitySession(
          activity: whoActivity,
          selfUserId: '@a0:example.org',
          transport: sim.call.join('a0'));
      await sim.settle();
      await session.join(asPlayer: false);
      await sim.settle();
      return session;
    }

    test('a request nobody answers goes to the next holder', () async {
      final sim = Sim(3, retryEvery: const Duration(milliseconds: 30));
      addTearDown(sim.close);
      await sim.start();
      final silent = await silentSpectator(sim);
      addTearDown(silent.dispose);
      await sim.deckRound();
      final truth = sim.truth('p0')!;

      await sim.reveal('p0');
      expect(sim['p0'].custody.plaqueOf('p0'), isNull,
          reason: 'the first one asked says nothing');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sim.settle();

      expect(sim['p0'].custody.plaqueOf('p0')?.cardId, truth.cardId);
    });

    test('a holder that does not have it says so, and the next one is asked',
        () async {
      final sim = Sim(3);
      addTearDown(sim.close);
      await sim.start();
      final silent = await silentSpectator(sim);
      addTearDown(silent.dispose);
      silent.direct.listen((d) {
        if (d.message['plaque'] != 'ask') return;
        silent.sendTo([d.sender], {'plaque': 'nak', 'tag': d.message['tag']});
      });
      await sim.deckRound();
      final truth = sim.truth('p0')!;

      await sim.reveal('p0');

      expect(sim['p0'].custody.plaqueOf('p0')?.cardId, truth.cardId);
    });
  });

  test('a plaque written after its time ran out is refused', () async {
    final sim = Sim(3);
    addTearDown(sim.close);
    await sim.start();
    await sim.homemadeRound(silent: {'p0'});
    await sim.deal('p1');
    final card = sim.truth('p1')!;

    expect(sim['p0'].custody.write('p1', kind: PlaqueKind.animal, text: 'late'),
        isFalse);
    expect(sim['p0'].custody.write('p0', kind: PlaqueKind.animal, text: 'me'),
        isFalse,
        reason: 'nobody writes their own');
    await sim.settle();

    expect(sim.truth('p1')!.cardId, card.cardId);
    sim['p0'].custody.dispose();
    sim['p0'].custody.dispose();
  });

  group('the public record', () {
    test('reads back as it was written', () {
      final ledger = PlaqueLedger(
        round: 2,
        salt: 'salt',
        used: {'card-a'},
        owed: {'tag-0'},
        entries: {
          'p0': const PlaqueEntry(
            version: 2,
            state: PlaqueState.pending,
            deal: PlaqueDeal(
              DeckFilter(
                theme: DeckTheme.foodAndDrink,
                packs: {CardReach.br},
                difficulties: {CardDifficulty.hard},
              ),
              dealer: 'p1',
            ),
          ),
          'p1': const PlaqueEntry(
              version: 1,
              state: PlaqueState.dealt,
              tag: 'tag-1',
              kind: PlaqueKind.place,
              pool: 1),
          'p2': const PlaqueEntry(
            version: 1,
            state: PlaqueState.revealed,
            tag: 'tag-2',
            kind: PlaqueKind.person,
            plaque:
                Plaque(kind: PlaqueKind.person, text: 'Grandma', author: 'p0'),
          ),
        },
      );

      final read = PlaqueLedger.fromJson(ledger.toJson());

      expect(read.toJson(), ledger.toJson());
      expect(read.entries['p0']!.deal!.filter.theme, DeckTheme.foodAndDrink);
      expect(read.entries['p0']!.deal!.filter.packs,
          {CardReach.world, CardReach.br});
      expect(read.entries['p2']!.plaque!.author, 'p0');
      expect(read.isOpen('tag-0'), isTrue);
      expect(read.isOpen('tag-1'), isFalse);
      expect(read.isOpen('tag-2'), isTrue);
    });

    test('splits the deck in two halves that change with the round', () {
      final ids = [for (final card in simDeck().cards) card.id];
      final first = [for (final id in ids) plaquePool('round-1', id)];
      final second = [for (final id in ids) plaquePool('round-2', id)];

      expect(first.toSet(), {0, 1});
      expect(first.where((p) => p == 1).length, inInclusiveRange(120, 200));
      expect(second, isNot(first));
      expect([for (final id in ids) plaquePool('round-1', id)], first);
    });

    test('a card reads in the language asked for, when the deck has it', () {
      final deck = Deck([
        const DeckCard(
          id: 'cat',
          theme: DeckTheme.animals,
          kind: PlaqueKind.animal,
          reach: CardReach.world,
          difficulty: CardDifficulty.easy,
          texts: {
            'en': CardText(name: 'Cat', caption: 'Pet'),
            'pt': CardText(name: 'Gato', caption: 'Bicho de casa'),
          },
        ),
      ]);
      final plaque = Plaque.fromJson(Plaque.card(deck.cards.single).toJson())!;

      expect(plaque.text, 'Cat');
      expect(plaque.textIn(deck, 'pt'), 'Gato');
      expect(plaque.captionIn(deck, 'pt'), 'Bicho de casa');
      expect(plaque.textIn(Deck(const []), 'pt'), 'Cat');
    });
  });
}
