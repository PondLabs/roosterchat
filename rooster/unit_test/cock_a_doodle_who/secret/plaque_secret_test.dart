// The plaque secret itself: in simulated matches of 2, 3 and 8 clients, in
// both modes, no client is delivered its own plaque before it is public -
// not the text, not the card, not a seed - through the dealing, a swap, the
// writing time running out, a change of host and someone joining mid-round.
// Every message delivered to every client is read; the host owns a plaque
// like everyone else.

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/secret/plaque_custody.dart';

import 'plaque_sim.dart';

const _animals = DeckFilter(theme: DeckTheme.animals);

/// The steps both modes share after the first dealing: someone joins
/// mid-round, the host vanishes, the elected host deals again, everything
/// is revealed, and a second round is played under the new host.
Future<void> _restOfTheMatch(Sim sim, {required bool deck}) async {
  // Someone joins mid-round (the ninth as a spectator): they watch with
  // every plaque of the round, and have none.
  final late = await sim.add('q0');
  expect(sim.misplaced(), isEmpty);
  expect(sim.host.custody.ledger.entries.containsKey(late.id), isFalse);
  for (final owner in sim.host.custody.ledger.entries.keys) {
    expect(late.custody.plaqueOf(owner), isNotNull,
        reason: 'who joins mid-round sees $owner\'s plaque');
  }

  // The host vanishes: p1 is elected and carries on from the state it last
  // heard, which does not hold p1's own plaque.
  await sim.vanish('p0');
  expect(sim.host.id, 'p1');
  expect(sim.host.custody.plaqueOf('p1'), isNull);
  await sim.retire('p0');
  expect(sim.misplaced(), isEmpty);

  // The new host deals: its own card (drawn by another client) and, with
  // someone else left, theirs.
  await sim.deal('p1', _animals);
  if (sim.players.contains('p2')) await sim.deal('p2', _animals);
  expect(sim.misplaced(), isEmpty);
  expect(sim.host.custody.plaqueOf('p1'), isNull);

  // The reveal: each owner now has what was written.
  for (final owner in sim.players) {
    if (!sim.host.custody.ledger.entries.containsKey(owner)) continue;
    final truth = sim.truth(owner)!;
    await sim.reveal(owner);
    expect(sim[owner].custody.plaqueOf(owner)?.text, truth.text);
  }

  // A second round, under the host that took over.
  if (deck) {
    await sim.deckRound(_animals);
  } else {
    await sim.homemadeRound();
  }
  expect(sim.misplaced(), isEmpty);
  expect(sim.host.custody.ledger.entries.keys, sim.players);
}

void main() {
  for (final count in [2, 3, 8]) {
    test('Deck, $count clients: nobody is sent their own card', () async {
      final sim = Sim(count, seed: count);
      addTearDown(sim.close);
      await sim.start();

      // The dealing: every player has a card, the host too.
      await sim.deckRound(_animals);
      expect(sim.misplaced(), isEmpty);
      expect(sim.host.custody.ledger.entries.keys, sim.players);
      expect(sim.host.custody.plaqueOf('p0'), isNull);

      // The swap, of the host's card and of someone else's.
      final before = {for (final p in sim.players) p: sim.truth(p)!.cardId};
      await sim.deal('p0', _animals);
      await sim.deal('p1', _animals);
      expect(sim.misplaced(), isEmpty);
      expect(sim.truth('p0')!.cardId, isNot(before['p0']));
      expect(sim.truth('p1')!.cardId, isNot(before['p1']));

      await _restOfTheMatch(sim, deck: true);

      expect(sim.leaks(), isEmpty);
      expect(sim.inspected, greaterThan(count * 10));
    });

    test('Homemade, $count clients: nobody is sent their own plaque', () async {
      final sim = Sim(count, seed: 100 + count);
      addTearDown(sim.close);
      await sim.start();

      // The writing: the last player (who writes for the host) and p0 (who
      // writes for p1) run out of time.
      final last = sim.players.last;
      await sim.homemadeRound(silent: {last, 'p0'});
      final ledger = sim.host.custody.ledger;
      expect(ledger.entries['p0']!.state, PlaqueState.pending);
      expect(ledger.entries['p1']!.state, PlaqueState.pending);

      // The time is up: both get a card of the deck instead.
      await sim.deal('p0');
      await sim.deal('p1');
      expect(sim.misplaced(), isEmpty);
      expect(sim.truth('p0')!.cardId, isNotNull);
      expect(sim.truth('p1')!.cardId, isNotNull);
      expect(sim.host.custody.plaqueOf('p0'), isNull);
      if (count > 2) {
        expect(sim.truth('p2')!.author, 'p1');
        expect(sim.truth('p2')!.text, 'homemade for p2 by p1 in 1');
      }

      await _restOfTheMatch(sim, deck: false);

      expect(sim.leaks(), isEmpty);
      expect(sim.inspected, greaterThan(count * 10));
    });
  }

  test('the inspection finds a plaque sent to its owner', () async {
    final sim = Sim(3);
    addTearDown(sim.close);
    await sim.start();
    await sim.deckRound();

    // What a broken client would do: p2 forwards p1's plaque to p1.
    final tag = sim.host.custody.ledger.entries['p1']!.tag;
    await sim['p2'].session.sendTo([
      'p1'
    ], {
      'plaque': 'put',
      'tag': tag,
      'o': 'p1',
      'r': 1,
      'v': 1,
      'p': sim.truth('p1')!.toJson(),
    });
    await sim.settle();

    expect(sim.leaks(), isNotEmpty);
    expect(sim['p1'].custody.plaqueOf('p1'), isNull,
        reason: 'a client does not keep its own plaque even when sent it');
  });

  test('a holder answers the owner\'s request only once the plaque is public',
      () async {
    final sim = Sim(3);
    addTearDown(sim.close);
    await sim.start();
    await sim.homemadeRound();
    final tag = sim.host.custody.ledger.entries['p2']!.tag;

    // The owner knows its plaque's tag from the ledger, and asks for it.
    await sim['p2'].session.sendTo(['p0', 'p1'], {'plaque': 'ask', 'tag': tag});
    await sim.settle();
    expect(sim.leaks(), isEmpty, reason: 'nobody answered');

    // Someone else's request is answered at once.
    final received = <Object?>[];
    sim['p1'].session.direct.listen((d) => received.add(d.message['plaque']));
    await sim['p1'].session.sendTo(['p0'], {'plaque': 'ask', 'tag': tag});
    await sim.settle();
    expect(received, ['put']);
  });
}
