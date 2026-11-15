import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const yes = MatchAnswer.yes, no = MatchAnswer.no;
const sortOf = MatchAnswer.sortOf, gotIt = MatchAnswer.gotIt;

void main() {
  /// A Homemade match of [players] at its first question.
  void play(int players, void Function(MatchSim m) body,
      {MatchSettings? settings, int seed = 1}) {
    fakeAsync((async) {
      final m = MatchSim(async, players, seed: seed);
      m.start(settings ?? MatchSettings());
      m.host.hostStart();
      m.run();
      m.toQuestions();
      body(m);
      m.close();
    });
  }

  group('the round', () {
    test('turns in a drawn order that holds for the whole round', () {
      final orders = <String>{};
      for (var seed = 1; seed <= 6; seed++) {
        play(4, seed: seed, (m) {
          final order = [...m.state.order];
          expect(order.toSet(), m.matches.keys.toSet());
          expect(m.asker, order.first);
          expect(m.state.lap, 1);
          for (var turn = 0; turn < 6; turn++) {
            expect(m.asker, order[turn % 4]);
            m.answerAll(no);
          }
          expect(m.state.order, order);
          expect(m.state.lap, 2);
          orders.add(order.join());
        });
      }
      expect(orders.length, greaterThan(1));
    });

    test('every client sees the same match', () {
      play(3, (m) {
        m.answerAll(yes);
        for (final match in m.matches.values) {
          expect(match.state.toJson(), m.state.toJson());
        }
      });
    });
  });

  group('the count', () {
    test('closes 5 s after the first answer', () {
      play(4, (m) {
        final asker = m.asker!;
        final first = m.state.responders.first;
        m[first].answer(yes);
        m.run();
        expect(m.state.tallyDeadline, m.now + 5000);
        m.seconds(4.9);
        expect(m.state.question, 1);
        expect(m.state.answers, {first: yes});
        m.seconds(0.1);
        expect(m.state.last?.outcome, TallyOutcome.yes);
        expect(m.state.last?.counts, {yes: 1});
        expect(m.asker, asker);
        expect(m.state.question, 2);
      });
    });

    test('a later answer does not give the count more time', () {
      play(4, (m) {
        final [a, b, _] = m.state.responders;
        m[a].answer(no);
        m.run();
        final closes = m.now + 5000;
        m.seconds(3);
        m[b].answer(no);
        m.run();
        expect(m.state.tallyDeadline, closes);
        m.seconds(2);
        expect(m.state.last?.counts, {no: 2});
      });
    });

    test('one got it of two who could answer is a yes', () {
      play(3, (m) {
        final asker = m.asker!;
        m[m.state.responders.first].answer(gotIt);
        m.seconds(5);
        expect(m.state.last?.outcome, TallyOutcome.yes);
        expect(m.state.guessed, isEmpty);
        expect(m.asker, asker);
      });
    });

    test('closes when everyone answered', () {
      play(4, (m) {
        m.answerAll(no, by: (id) => id == m.state.responders.last ? yes : no);
        expect(m.state.last?.counts, {no: 2, yes: 1});
        expect(m.state.last?.outcome, TallyOutcome.no);
      });
    });

    test('the one asking does not answer; an answer counts once', () {
      play(3, (m) {
        final asker = m.asker!;
        final other = m.state.responders.first;
        m[asker].answer(gotIt);
        m[other].answer(no);
        m[other].answer(yes);
        m.run();
        expect(m.state.answers, {other: yes});
      });
    });

    test('an answer for an earlier question does not count', () {
      play(3, (m) {
        final id = m.state.questionId;
        m.answerAll(yes);
        expect(m.state.question, 2);
        final late = m.state.responders.first;
        m.sim[late].session
            .sendTo([m.sim.host.id], {'who': 'answer', 'a': 'no', 'q': id});
        m.run();
        expect(m.state.answers, isEmpty);
      });
    });

    test('one got it among three answering is a yes', () {
      play(4, (m) {
        final asker = m.asker!;
        final [a, b, c] = m.state.responders;
        m.answerAll(no, by: (id) => {a: gotIt, b: no, c: sortOf}[id]);
        expect(m.state.last?.outcome, TallyOutcome.yes);
        expect(m.asker, asker);
        expect(m.state.guessed, isEmpty);
      });
    });

    test('two got it among three is the guess', () {
      play(4, (m) {
        final asker = m.asker!;
        final [a, b, c] = m.state.responders;
        m.answerAll(no, by: (id) => {a: gotIt, b: gotIt, c: no}[id]);
        expect(m.state.last?.outcome, TallyOutcome.gotIt);
        expect(m.state.guessed, {asker: 1});
      });
    });
  });

  group('the turn', () {
    test('yes asks again, three questions at most', () {
      play(3, (m) {
        final [first, second, _] = m.state.order;
        m.answerAll(yes);
        m.answerAll(sortOf);
        expect(m.asker, first);
        expect(m.state.question, 3);
        m.answerAll(yes);
        expect(m.asker, second);
        expect(m.state.question, 1);
      });
    });

    test('no passes the turn', () {
      play(3, (m) {
        final [_, second, _] = m.state.order;
        m.answerAll(no);
        expect(m.asker, second);
      });
    });

    test('nobody answering in the question time passes the turn', () {
      play(3, (m) {
        final [first, second, _] = m.state.order;
        expect(m.state.deadline, m.now + 30000);
        m.seconds(29.9);
        expect(m.asker, first);
        m.seconds(0.1);
        expect(m.asker, second);
        expect(m.state.last?.asker, first);
        expect(m.state.last?.outcome, isNull);
        expect(m.state.stats[first]?.asked, 0);
      });
    });

    test('a first answer near the end still gets its 5 s', () {
      play(3, (m) {
        final [first, ...] = m.state.order;
        m.seconds(28);
        m[m.state.responders.first].answer(yes);
        m.seconds(4.9);
        expect(m.asker, first);
        expect(m.state.question, 1);
        m.seconds(0.1);
        expect(m.state.question, 2);
      });
    });

    test('without a clock, the host skips the turn', () {
      play(3, settings: MatchSettings(secondsPerQuestion: null), (m) {
        final [first, second, _] = m.state.order;
        expect(m.state.deadline, isNull);
        m.seconds(600);
        expect(m.asker, first);
        m.host.hostSkipTurn();
        m.run();
        expect(m.asker, second);
      });
    });

    test('with a clock, there is no skipping', () {
      play(3, (m) {
        final first = m.asker;
        m.host.hostSkipTurn();
        m.run();
        expect(m.asker, first);
      });
    });
  });

  group('the guess', () {
    test('turns the plaque for its owner, with its author', () {
      play(3, (m) {
        final asker = m.asker!;
        expect(m[asker].plaqueOf(asker), isNull);
        m.answerAll(gotIt);
        final plaque = m[asker].plaqueOf(asker);
        expect(plaque?.text, startsWith('for $asker by '));
        expect(plaque?.author, isNotNull);
        expect(plaque?.author, isNot(asker));
        expect(m.ownLeaks(), isEmpty);
      });
    });

    test('the owner asks no more and keeps answering', () {
      play(4, (m) {
        final [first, second, third, fourth] = m.state.order;
        m.answerAll(gotIt);
        expect(m.state.active, [second, third, fourth]);
        expect(m.asker, second);
        expect(m.state.responders, contains(first));
        m.answerAll(no);
        m.answerAll(no);
        m.answerAll(no);
        expect(m.asker, second);
        expect(m.state.lap, 2);
      });
    });

    test('points: the lap limit, less the lap, plus one', () {
      play(3, (m) {
        final [first, second, third] = m.state.order;
        m.answerAll(gotIt);
        expect(m.state.roundPoints, {first: 8});
        m.answerAll(no); // second
        m.answerAll(no); // third
        expect(m.state.lap, 2);
        m.answerAll(gotIt); // second, in lap 2
        expect(m.state.roundPoints, {first: 8, second: 7});
        expect(m.state.points, {first: 8, second: 7, third: 0});
        m.expectPhase(MatchPhase.rescue);
        m.seconds(30);
        expect(m.state.roundPoints[third], isNull);
        expect(m.state.points[third], 0);
      });
    });

    test('the points of a guess in the last lap', () {
      play(2, settings: MatchSettings(lapLimit: 4), (m) {
        final [first, _] = m.state.order;
        for (var turn = 0; turn < 6; turn++) {
          m.answerAll(no);
        }
        expect(m.state.lap, 4);
        expect(m.asker, first);
        m.answerAll(gotIt);
        expect(m.state.roundPoints, {first: 1});
      });
    });
  });

  group('the rescue', () {
    test('one player left: 30 s, then the plaque turns', () {
      play(3, (m) {
        final [first, second, third] = m.state.order;
        m.answerAll(gotIt);
        m.answerAll(gotIt);
        expect(m.state.guessed.keys, {first, second});
        m.expectPhase(MatchPhase.rescue);
        expect(m.state.active, [third]);
        expect(m.state.deadline, m.now + 30000);
        expect(m[third].plaqueOf(third), isNull);
        m.seconds(29.9);
        m.expectPhase(MatchPhase.rescue);
        m.seconds(0.1);
        m.expectPhase(MatchPhase.scores);
        expect(m[third].plaqueOf(third), isNotNull);
        expect(m.sim.host.custody.ledger.entries[third]?.state,
            PlaqueState.revealed);
      });
    });

    test('at the lap limit, for everyone who has not guessed', () {
      play(3, settings: MatchSettings(lapLimit: 4), (m) {
        final [first, second, third] = m.state.order;
        m.answerAll(gotIt);
        for (var turn = 0; turn < 7; turn++) {
          m.expectPhase(MatchPhase.asking);
          m.answerAll(no);
        }
        // Laps 1 to 4 asked: second and third, four turns each, less one.
        expect(m.state.lap, 4);
        expect(m.asker, third);
        m.answerAll(no);
        m.expectPhase(MatchPhase.rescue);
        expect(m.state.active, [second, third]);
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        for (final owner in [second, third]) {
          expect(m[owner].plaqueOf(owner), isNotNull);
        }
        expect(m.state.roundPoints, {first: 4});
      });
    });
  });
}
