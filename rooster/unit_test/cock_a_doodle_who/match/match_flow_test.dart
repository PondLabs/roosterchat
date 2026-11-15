import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const no = MatchAnswer.no, gotIt = MatchAnswer.gotIt;

void main() {
  void play(int players, void Function(MatchSim m) body,
      {MatchSettings? settings, int seed = 1}) {
    fakeAsync((async) {
      final m = MatchSim(async, players, seed: seed);
      m.start(settings ?? MatchSettings());
      body(m);
      m.close();
    });
  }

  group('the lobby', () {
    test('needs two players to start', () {
      play(1, (m) {
        expect(m.host.hostStart(), isFalse);
        m.expectPhase(MatchPhase.lobby);
        m.add('p1');
        expect(m.host.hostStart(), isTrue);
      });
    });

    test('everyone sees the settings', () {
      play(2, settings: MatchSettings(rounds: 5, lapLimit: 6), (m) {
        expect(m['p1'].state.settings.rounds, 5);
        expect(m['p1'].state.settings.lapLimit, 6);
      });
    });
  });

  group('joining and leaving', () {
    test('who joins mid-round watches it and plays the next', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.toQuestions();
        final late = m.add('p9');
        expect(m.state.order, isNot(contains('p9')));
        expect(late.playsThisRound, isFalse);
        expect(m.state.responders, isNot(contains('p9')));
        late.answer(gotIt);
        m.run();
        expect(m.state.answers, isEmpty);
        // They see every plaque, their own included: they have none.
        for (final owner in m.state.order) {
          expect(late.plaqueOf(owner), isNotNull);
        }
        for (var i = 0; i < 2; i++) {
          m.answerAll(gotIt);
        }
        m.seconds(30);
        m.seconds(10);
        expect(m.state.round, 2);
        expect(m.state.order, contains('p9'));
        expect(late.playsThisRound, isTrue);
        expect(late.writingFor, isNotNull);
      });
    });

    test('who leaves has the plaque taken off and the turn skipped', () {
      play(4, (m) {
        m.host.hostStart();
        m.run();
        m.toQuestions();
        final [first, second, third, fourth] = m.state.order;
        final gone = second == m.sim.host.id ? third : second;
        m.vanish(gone);
        expect(m.state.left, {gone});
        expect(m.sim.host.custody.ledger.entries[gone]?.state,
            PlaqueState.retired);
        expect(m.state.responders, isNot(contains(gone)));
        m.answerAll(no);
        expect(
            m.asker,
            [first, second, third, fourth]
                .skip(1)
                .firstWhere((p) => p != gone));
      });
    });

    test('the one asking leaves: the turn passes', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.toQuestions();
        final order = m.state.order;
        final asking = order.firstWhere((p) => p != m.sim.host.id);
        while (m.asker != asking) {
          m.answerAll(no);
        }
        m.vanish(asking);
        m.expectPhase(MatchPhase.asking);
        expect(m.state.left, {asking});
        expect(m.asker, isNot(asking));
        expect(m.state.question, 1);
      });
    });

    for (final phase in [MatchPhase.look, MatchPhase.asking]) {
      test('fewer than two players in $phase: the final result', () {
        play(2, (m) {
          m.host.hostStart();
          m.run();
          m.writeAll();
          if (phase == MatchPhase.asking) m.seconds(10);
          m.expectPhase(phase);
          m.vanish('p1');
          m.expectPhase(MatchPhase.finished);
          expect(m.sim.host.custody.ledger.entries['p0']?.isOpen, isTrue);
        });
      });
    }

    test('a match let go twice is let go once', () {
      play(2, (m) {
        final extra = WhoMatch(
            session: m.sim['p1'].session, custody: m.sim['p1'].custody);
        extra.dispose();
        extra.dispose();
      });
    });
  });

  group('the host changes mid-round', () {
    test('the same phase, order, points and clock', () {
      play(4, (m) {
        m.host.hostStart();
        m.run();
        m.toQuestions();
        // p0 hosts: get to a turn of someone else, a guess made.
        m.answerAll(gotIt);
        m.answerAll(no);
        m.seconds(12);
        final before = m.state.toJson();
        final asker = m.asker!;
        final deadline = m.state.deadline!;
        expect(m.sim.host.id, 'p0');
        if (asker == 'p0') fail('the seed puts p0 on the turn');
        m.vanish('p0');
        expect(m.sim.host.id, isNot('p0'));
        final after = m.state;
        expect(after.phase, MatchPhase.asking);
        expect(after.order, before['o']);
        expect(after.points, before['pts']);
        expect(after.lap, before['lap']);
        expect(after.asker, asker);
        expect(after.left, {'p0'});
        expect((after.deadline! - deadline).abs(), lessThanOrEqualTo(2000));
        // The new host keeps the time: the turn passes when it was due.
        m.wait(Duration(milliseconds: deadline - m.now - 1));
        expect(m.asker, asker);
        m.seconds(0.001);
        expect(m.asker, isNot(asker));
        for (final match in m.matches.values) {
          expect(match.state.toJson(), m.state.toJson());
        }
      });
    });

    test('while writing: the plaques still come, the clock holds', () {
      play(4, (m) {
        m.host.hostStart();
        m.run();
        m.seconds(20);
        m.writeAll(silent: {'p0', 'p2'});
        m.vanish('p0');
        m.expectPhase(MatchPhase.writing);
        m.seconds(39.9);
        m.expectPhase(MatchPhase.writing);
        m.writeAll();
        m.seconds(0.1);
        m.expectPhase(MatchPhase.look);
        expect(m.sim.misplaced(), isEmpty);
        expect(m.ownLeaks(), isEmpty);
      });
    });
  });

  group('a whole match', () {
    /// Plays a round: in each turn, the [guesses]-th player of the order
    /// to ask guesses on their first question, the others hear no.
    void round(MatchSim m, {required int round}) {
      if (m.state.phase == MatchPhase.writing) m.writeAll();
      m.expectPhase(MatchPhase.look);
      expect(m.state.round, round);
      m.seconds(10);
      var turns = 0;
      while (m.state.phase == MatchPhase.asking) {
        // Every other turn is a guess, and the first lap is all no.
        final guess = turns >= m.state.order.length && turns.isEven;
        m.answerAll(guess ? gotIt : no);
        turns++;
      }
      m.expectPhase(MatchPhase.rescue);
      m.seconds(30);
    }

    void checkFinal(MatchSim m) {
      m.expectPhase(MatchPhase.finished);
      final state = m.state;
      final standings = state.standings;
      expect(standings.map((s) => s.player).toSet(), m.matches.keys.toSet());
      for (var i = 1; i < standings.length; i++) {
        expect(standings[i].points, lessThanOrEqualTo(standings[i - 1].points));
      }
      final total = state.points.values.fold(0, (a, b) => a + b);
      expect(total, greaterThan(0));
      expect(state.awards.fewestQuestions, isNotEmpty);
      expect(state.awards.mostNoes, isNotEmpty);
      for (final player in state.awards.fewestQuestions) {
        expect(state.stats[player]!.guessed, greaterThan(0));
      }
      for (final match in m.matches.values) {
        expect(match.state.toJson(), state.toJson());
      }
      expect(m.sim.leaks(), isEmpty);
    }

    test('Homemade, from the lobby to the final result', () {
      play(4, (m) {
        m.host.hostStart();
        m.run();
        for (var r = 1; r <= 3; r++) {
          round(m, round: r);
          if (r < 3) {
            m.expectPhase(MatchPhase.scores);
            m.seconds(10);
          }
        }
        checkFinal(m);
        m.host.hostPlayAgain();
        m.run();
        expect(m['p1'].state.phase, MatchPhase.lobby);
        expect(m['p1'].state.points, isEmpty);
      });
    });

    test('Deck, from the lobby to the final result', () {
      play(5,
          settings: MatchSettings(
              mode: MatchMode.deck, rounds: 2, theme: DeckTheme.animals), (m) {
        m.host.hostStart();
        m.run();
        round(m, round: 1);
        m.expectPhase(MatchPhase.scores);
        m[m.state.chooser!].chooseTheme(DeckTheme.objects);
        m.run();
        expect(m.state.theme, DeckTheme.objects);
        round(m, round: 2);
        checkFinal(m);
      });
    });
  });
}
