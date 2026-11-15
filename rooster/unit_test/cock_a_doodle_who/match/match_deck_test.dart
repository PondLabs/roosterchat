import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

void main() {
  /// A Deck match of [players], its first round dealt.
  void play(int players, void Function(MatchSim m) body,
      {MatchSettings? settings, int seed = 1}) {
    fakeAsync((async) {
      final m = MatchSim(async, players, seed: seed);
      m.start(settings ??
          MatchSettings(mode: MatchMode.deck, theme: DeckTheme.animals));
      m.host.hostStart();
      m.run();
      body(m);
      m.close();
    });
  }

  String card(MatchSim m, String owner) => m.sim.truth(owner)!.cardId!;

  test('the cards come from the theme and difficulties picked', () {
    play(6,
        settings: MatchSettings(
          mode: MatchMode.deck,
          theme: DeckTheme.places,
          difficulties: {CardDifficulty.hard},
        ), (m) {
      m.expectPhase(MatchPhase.look);
      expect(m.state.theme, DeckTheme.places);
      for (final owner in m.state.order) {
        final dealt = m.sim.deck.byId(card(m, owner))!;
        expect(dealt.theme, DeckTheme.places);
        expect(dealt.difficulty, CardDifficulty.hard);
      }
      expect(m.sim.misplaced(), isEmpty);
      expect(m.ownLeaks(), isEmpty);
    });
  });

  group('the swap', () {
    test('anyone may ask for a teammate\'s, once per plaque', () {
      play(4, (m) {
        final [a, b, c, _] = m.state.order;
        final before = card(m, b);
        m[a].askSwap(b);
        m.run();
        expect(m.state.swapped, {b});
        expect(card(m, b), isNot(before));
        expect(m.sim.deck.byId(card(m, b))!.theme, DeckTheme.animals);
        final swapped = card(m, b);
        m[c].askSwap(b);
        m.run();
        expect(card(m, b), swapped);
        expect(m.sim.misplaced(), isEmpty);
        expect(m.ownLeaks(), isEmpty);
      });
    });

    test('the host\'s own card too', () {
      play(3, (m) {
        final host = m.sim.host.id;
        final other = m.state.order.firstWhere((p) => p != host);
        final before = card(m, host);
        m[other].askSwap(host);
        m.run();
        expect(card(m, host), isNot(before));
        expect(m.sim.misplaced(), isEmpty);
        expect(m.ownLeaks(), isEmpty);
      });
    });

    test('nobody swaps their own', () {
      play(3, (m) {
        final [a, _, _] = m.state.order;
        final before = card(m, a);
        m[a].askSwap(a);
        m.run();
        expect(m.state.swapped, isEmpty);
        expect(card(m, a), before);
      });
    });

    test('not once the questions started', () {
      play(3, (m) {
        m.seconds(10);
        m.expectPhase(MatchPhase.asking);
        final [a, b, _] = m.state.order;
        final before = card(m, b);
        m[a].askSwap(b);
        m.run();
        expect(m.state.swapped, isEmpty);
        expect(card(m, b), before);
      });
    });

    test('not in Homemade', () {
      fakeAsync((async) {
        final m = MatchSim(async, 3)..start(MatchSettings());
        m.host.hostStart();
        m.run();
        m.writeAll();
        final [a, b, _] = m.state.order;
        m[a].askSwap(b);
        m.run();
        expect(m.state.swapped, isEmpty);
        m.close();
      });
    });
  });

  group('the next theme', () {
    /// Plays the round to its scoreboard: [winner] guesses at once.
    void toScores(MatchSim m) {
      m.seconds(10);
      m.answerAll(MatchAnswer.no);
      m.answerAll(MatchAnswer.gotIt);
      m.answerAll(MatchAnswer.gotIt);
      m.seconds(30);
      m.expectPhase(MatchPhase.scores);
    }

    test('is the last-placed player\'s to pick', () {
      play(3, (m) {
        final [a, b, c] = m.state.order;
        toScores(m);
        expect(m.state.points, {a: 0, b: 8, c: 8});
        expect(m.state.chooser, a);
        m[b].chooseTheme(DeckTheme.jobs);
        m.run();
        m.expectPhase(MatchPhase.scores);
        m[a].chooseTheme(DeckTheme.jobs);
        m.run();
        expect(m.state.round, 2);
        expect(m.state.theme, DeckTheme.jobs);
        m.expectPhase(MatchPhase.look);
        for (final owner in m.state.order) {
          expect(m.sim.deck.byId(card(m, owner))!.theme, DeckTheme.jobs);
        }
      });
    });

    test('Anything goes may be picked', () {
      play(3, (m) {
        toScores(m);
        m[m.state.chooser!].chooseTheme(null);
        m.run();
        expect(m.state.round, 2);
        expect(m.state.theme, isNull);
      });
    });

    test('is drawn when nobody picks in 20 s', () {
      final themes = <DeckTheme?>{};
      for (var seed = 1; seed <= 4; seed++) {
        play(3, seed: seed, (m) {
          toScores(m);
          m.seconds(19.9);
          expect(m.state.round, 1);
          m.seconds(0.1);
          expect(m.state.round, 2);
          expect(m.state.theme, isNotNull);
          themes.add(m.state.theme);
        });
      }
      expect(themes.length, greaterThan(1));
    });

    test('Homemade has no theme: the scoreboard lasts 10 s', () {
      fakeAsync((async) {
        final m = MatchSim(async, 2)..start(MatchSettings());
        m.host.hostStart();
        m.run();
        m.toQuestions();
        m.answerAll(MatchAnswer.gotIt);
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        expect(m.state.chooser, isNull);
        m.seconds(9.9);
        m.expectPhase(MatchPhase.scores);
        m.seconds(0.1);
        m.expectPhase(MatchPhase.writing);
        expect(m.state.round, 2);
        expect(m.state.theme, isNull);
        m.close();
      });
    });
  });
}
