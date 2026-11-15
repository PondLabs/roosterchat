// An independent review's reproductions of what it found, kept as
// regression tests: each test states what the plan asks for.

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const yes = MatchAnswer.yes, no = MatchAnswer.no, gotIt = MatchAnswer.gotIt;

void play(int players, void Function(MatchSim m) body,
    {MatchSettings? settings, int seed = 1}) {
  fakeAsync((async) {
    final m = MatchSim(async, players, seed: seed);
    m.start(settings ?? MatchSettings());
    body(m);
    m.close();
  });
}

void toAsking(MatchSim m) {
  m.host.hostStart();
  m.run();
  if (m.state.phase == MatchPhase.writing) m.writeAll();
  m.expectPhase(MatchPhase.look);
  m.seconds(10);
  m.expectPhase(MatchPhase.asking);
}

/// Gives [id] a match whose machine clock is [ahead] of the others'.
void skew(MatchSim m, String id, Duration ahead) {
  m.matches[id]!.dispose();
  m.matches[id] = WhoMatch(
    session: m.sim[id].session,
    custody: m.sim[id].custody,
    random: Random(7),
    now: () =>
        DateTime.fromMillisecondsSinceEpoch(m.now + ahead.inMilliseconds),
  );
  m.run();
}

void main() {
  group('A1 an open count reaches every client', () {
    test('A1a the others see the answers and the 5 s of an open count', () {
      play(5, (m) {
        toAsking(m);
        final r = m.state.responders.where((p) => p != m.sim.host.id).toList();
        m[r[0]].answer(no);
        m.run();
        m.seconds(2);
        expect(m.state.answers, {r[0]: no}); // the host has it
        for (final id in m.matches.keys) {
          expect(m[id].state.answers, {r[0]: no},
              reason: '$id sees the answer');
          expect(m[id].state.tallyDeadline, m.state.tallyDeadline,
              reason: '$id sees when the count closes');
        }
      });
    });

    test('A1b a new host mid-count keeps the answers given and their 5 s', () {
      play(5, (m) {
        toAsking(m);
        m.answerAll(gotIt);
        while (m.asker == 'p0') {
          m.answerAll(no);
        }
        final asker = m.asker!;
        m.seconds(7);
        final r = m.state.responders.where((p) => p != 'p0').toList();
        m[r[0]].answer(no);
        m.run();
        m.seconds(2);
        final closes = m.state.tallyDeadline;
        m.vanish('p0');
        expect(m.sim.host.id, 'p1');
        expect(m.asker, asker);
        expect(m.state.answers, {r[0]: no});
        expect(m.state.tallyDeadline, closes);
        m.seconds(3);
        expect(m.state.last?.counts, {no: 1});
        expect(m.asker, isNot(asker));
      });
    });

    test('A1c the others see a plaque was swapped, during the look', () {
      play(4,
          settings: MatchSettings(mode: MatchMode.deck, theme: DeckTheme.jobs),
          (m) {
        m.host.hostStart();
        m.run();
        m.expectPhase(MatchPhase.look);
        final [a, b, ...] = m.state.order;
        m[a].askSwap(b);
        m.run();
        m.seconds(1);
        expect(m.state.swapped, {b});
        for (final id in m.matches.keys) {
          expect(m[id].state.swapped, {b}, reason: '$id sees the swap');
        }
      });
    });
  });

  group('A2 a new host whose machine clock differs', () {
    for (final (name, ahead) in [
      ('3 h ahead', const Duration(hours: 3)),
      ('3 h behind', Duration(hours: -3)),
      ('30 s ahead', const Duration(seconds: 30)),
    ]) {
      test('A2 $name: the look still ends when it was due (2 s tolerance)', () {
        play(4, (m) {
          skew(m, 'p1', ahead);
          m.host.hostStart();
          m.run();
          m.writeAll();
          m.expectPhase(MatchPhase.look);
          m.seconds(4); // 6 s of the look left
          m.vanish('p0');
          expect(m.sim.host.id, 'p1');
          m.seconds(3.9);
          expect(m.state.phase, MatchPhase.look,
              reason: '2.1 s before the look was due');
          m.seconds(4.2);
          expect(m.state.phase, MatchPhase.asking,
              reason: '2.1 s after the look was due');
        });
      });
    }
  });

  group('A3 play again', () {
    test('A3 a second one-round Homemade match: everyone can write', () {
      play(3, settings: MatchSettings(rounds: 1), (m) {
        toAsking(m);
        while (m.state.phase == MatchPhase.asking) {
          m.answerAll(gotIt);
        }
        m.seconds(30);
        m.expectPhase(MatchPhase.finished);
        m.host.hostPlayAgain();
        m.run();
        m.expectPhase(MatchPhase.lobby);
        expect(m.host.hostStart(), isTrue);
        m.run();
        m.expectPhase(MatchPhase.writing);
        for (final id in m.matches.keys) {
          expect(m[id].writingFor, isNotNull,
              reason: '$id has a plaque to write');
          expect(m[id].write('again', PlaqueKind.object), WriteResult.sent,
              reason: '$id writes it');
        }
      });
    });
  });

  group('A4 the count after its only answerer left', () {
    test('A4 the next first answer gets its own 5 s', () {
      play(6, (m) {
        toAsking(m);
        final r = m.state.responders.where((p) => p != m.sim.host.id).toList();
        m[r[0]].answer(yes);
        m.run();
        m.seconds(1);
        m.vanish(r[0]);
        expect(m.state.answers, isEmpty);
        m.seconds(6);
        m.expectPhase(MatchPhase.asking);
        final others = m.state.responders;
        expect(others.length, greaterThanOrEqualTo(3));
        m[others[0]].answer(no);
        m.run();
        // One of four answered, a moment ago: the count is still open.
        expect(m.state.answers, {others[0]: no});
        expect(m.state.question, 1);
        expect(m.state.tallyDeadline, m.now + 5000);
      });
    });
  });

  group('A5 nobody left to answer', () {
    test('A5 without a clock, the last one asking goes to the rescue', () {
      play(3, settings: MatchSettings(secondsPerQuestion: null), (m) {
        toAsking(m);
        while (m.asker != 'p0') {
          m.answerAll(no);
        }
        m.vanish('p1');
        m.add('p9'); // watches: two are present, the match goes on
        m.vanish('p2');
        expect(m.state.active, ['p0']);
        // One player has not guessed: the rescue starts at once.
        expect(m.state.phase, MatchPhase.rescue,
            reason: 'one player has not guessed, nobody can answer');
      });
    });
  });

  group('A6 who picks the next theme', () {
    test('A6 is someone of the standings, not who only watched', () {
      play(3,
          settings: MatchSettings(mode: MatchMode.deck, theme: DeckTheme.jobs),
          (m) {
        toAsking(m);
        m.add('a9'); // joins mid-round: watches
        final [_, _, c] = m.state.order;
        m.answerAll(gotIt);
        m.answerAll(gotIt);
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        expect(m.state.standings.map((s) => s.player), isNot(contains('a9')));
        expect(m.state.chooser, c);
      });
    });
  });

  group('A7 the lap the state shows', () {
    test('A7 never goes past the lap limit', () {
      play(3, settings: MatchSettings(lapLimit: 4), (m) {
        toAsking(m);
        while (m.state.phase == MatchPhase.asking) {
          m.answerAll(no);
        }
        m.expectPhase(MatchPhase.rescue);
        expect(m.state.lap, lessThanOrEqualTo(4));
      });
    });
  });
}
