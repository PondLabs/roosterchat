// An independent review's cases, one group per acceptance criterion: each
// test name starts with the criterion it proves (C<n>).

import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const yes = MatchAnswer.yes, no = MatchAnswer.no;
const sortOf = MatchAnswer.sortOf, gotIt = MatchAnswer.gotIt;

/// The reviewer's oracle for criterion 6, written from the task's text.
TallyOutcome? oracle(List<MatchAnswer> given, int responders) {
  if (given.isEmpty) return null;
  var g = 0, n = 0, y = 0, s = 0;
  for (final a in given) {
    switch (a) {
      case MatchAnswer.gotIt:
        g++;
      case MatchAnswer.no:
        n++;
      case MatchAnswer.yes:
        y++;
      case MatchAnswer.sortOf:
        s++;
    }
  }
  final moreThanHalf = g > given.length / 2;
  final enough = responders >= 2 ? g >= 2 : true;
  if (moreThanHalf && enough) return TallyOutcome.gotIt;
  return (y + s + g) >= n ? TallyOutcome.yes : TallyOutcome.no;
}

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

void main() {
  group('C1', () {
    test('C1 derangement for 2 to 8 players and 200 seeds', () {
      for (var n = 2; n <= 8; n++) {
        final players = [for (var i = 0; i < n; i++) 'p$i'];
        for (var seed = 0; seed < 200; seed++) {
          final w = drawWriters(players, Random(seed));
          expect(w.keys.toSet(), players.toSet(), reason: 'n=$n seed=$seed');
          expect(w.values.toSet(), players.toSet(), reason: 'n=$n seed=$seed');
          expect(w.length, n);
          for (final e in w.entries) {
            expect(e.key, isNot(e.value), reason: 'n=$n seed=$seed');
          }
        }
      }
    });

    test('C1 in the engine: the plaques written match a derangement', () {
      for (final n in [2, 3, 8]) {
        for (var seed = 1; seed <= 5; seed++) {
          play(n, seed: seed, (m) {
            m.host.hostStart();
            m.run();
            final owners = {
              for (final id in m.matches.keys) id: m[id].writingFor
            };
            expect(owners.values.toSet(), m.matches.keys.toSet());
            owners.forEach((a, o) => expect(o, isNot(a)));
            m.writeAll();
            for (final e in owners.entries) {
              expect(m.sim.truth(e.value!)?.author, e.key);
            }
          });
        }
      }
    });
  });

  group('C2', () {
    test('C2 text limits: 1, 40, 41 code points, spaces, emoji', () {
      expect(plaqueText('a'), 'a');
      expect(plaqueText('x' * 40), 'x' * 40);
      expect(plaqueText('x' * 41), isNull);
      expect(plaqueText('  ${'x' * 40}  '), 'x' * 40);
      expect(plaqueText(''), isNull);
      expect(plaqueText(' \n\t '), isNull);
      expect(plaqueText('é' * 40), 'é' * 40);
      expect(plaqueText('😀' * 40), '😀' * 40);
      expect(plaqueText('😀' * 41), isNull);
    });

    test('C2 a 41-character text never reaches the custody or the wire', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        final long = 'L' * 41;
        for (final match in m.matches.values) {
          expect(match.write(long, PlaqueKind.person), WriteResult.badText);
        }
        m.run();
        final wire =
            jsonEncode([for (final d in m.sim.call.delivered) d.message]);
        expect(wire.contains(long), isFalse);
        m.expectPhase(MatchPhase.writing);
        // Still open: a good text goes.
        expect(m['p1'].write('x' * 40, PlaqueKind.food), WriteResult.sent);
      });
    });

    test('C2 nobody writes: at 60 s every plaque is a deck card', () {
      play(3, settings: MatchSettings(packs: {CardReach.br}), (m) {
        m.host.hostStart();
        m.run();
        m.seconds(59.9);
        m.expectPhase(MatchPhase.writing);
        m.seconds(0.1);
        m.expectPhase(MatchPhase.look);
        for (final o in m.state.order) {
          final p = m.sim.truth(o)!;
          expect(p.cardId, isNotNull);
          expect(p.author, isNull);
        }
      });
    });
  });

  group('C3', () {
    test('C3 cards follow theme and difficulty; swap once, before questions',
        () {
      for (final theme in [DeckTheme.jobs, DeckTheme.celebrities]) {
        play(5,
            settings: MatchSettings(
                mode: MatchMode.deck,
                theme: theme,
                difficulties: {CardDifficulty.easy}), (m) {
          m.host.hostStart();
          m.run();
          m.expectPhase(MatchPhase.look);
          for (final o in m.state.order) {
            final c = m.sim.deck.byId(m.sim.truth(o)!.cardId!)!;
            expect(c.theme, theme);
            expect(c.difficulty, CardDifficulty.easy);
          }
          final [a, b, c, ...] = m.state.order;
          final before = m.sim.truth(b)!.cardId;
          m[a].askSwap(b);
          m.run();
          final swapped = m.sim.truth(b)!.cardId;
          expect(swapped, isNot(before));
          expect(m.sim.deck.byId(swapped!)!.theme, theme);
          m[c].askSwap(b);
          m[a].askSwap(b);
          m.run();
          expect(m.sim.truth(b)!.cardId, swapped);
          m.seconds(10);
          m.expectPhase(MatchPhase.asking);
          final cBefore = m.sim.truth(c)!.cardId;
          m[a].askSwap(c);
          m.run();
          expect(m.sim.truth(c)!.cardId, cBefore);
          expect(m.state.swapped, {b});
        });
      }
    });
  });

  group('C4', () {
    test('C4 10 s look; the order holds over laps and differs by seed', () {
      final seen = <String>{};
      for (var seed = 1; seed <= 8; seed++) {
        play(5, seed: seed, (m) {
          m.host.hostStart();
          m.run();
          m.writeAll();
          m.expectPhase(MatchPhase.look);
          expect(m.state.deadline, m.now + 10000);
          m.seconds(9.999);
          m.expectPhase(MatchPhase.look);
          m.seconds(0.001);
          m.expectPhase(MatchPhase.asking);
          final order = [...m.state.order];
          for (var t = 0; t < 15; t++) {
            expect(m.asker, order[t % 5]);
            expect(m.state.lap, 1 + t ~/ 5);
            m.answerAll(no);
          }
          expect(m.state.order, order);
          seen.add(order.join(','));
        });
      }
      expect(seen.length, greaterThan(2));
    });
  });

  group('C5', () {
    test('C5 the asker and a spectator do not count; all answered closes', () {
      play(4, (m) {
        toAsking(m);
        final asker = m.asker!;
        final watcher = m.add('p9');
        expect(m.state.responders.toSet(),
            m.state.order.toSet().difference({asker}));
        m[asker].answer(no);
        watcher.answer(no);
        m.run();
        expect(m.state.answers, isEmpty);
        expect(m.state.tallyDeadline, isNull);
        final r = m.state.responders;
        m[r[0]].answer(yes);
        m[r[1]].answer(yes);
        m.run();
        expect(m.state.last, isNull);
        m[r[2]].answer(no);
        m.run();
        expect(m.state.last?.counts, {yes: 2, no: 1});
        expect(m.state.question, 2);
      });
    });

    test('C5 5 s from the first answer, to the millisecond', () {
      play(8, (m) {
        toAsking(m);
        m.seconds(3);
        final r = m.state.responders;
        m[r[0]].answer(no);
        m.run();
        final t0 = m.now;
        expect(m.state.tallyDeadline, t0 + 5000);
        m.seconds(2);
        m[r[1]].answer(no);
        m[r[0]].answer(yes); // replaces
        m.run();
        expect(m.state.tallyDeadline, t0 + 5000);
        m.wait(const Duration(milliseconds: 2999));
        expect(m.state.last, isNull);
        m.wait(const Duration(milliseconds: 1));
        expect(m.state.last?.counts, {yes: 1, no: 1});
        expect(m.state.last?.outcome, TallyOutcome.yes);
      });
    });

    test('C5 an answer after the count closed counts for nothing', () {
      play(4, (m) {
        toAsking(m);
        final asker = m.asker!;
        final r = m.state.responders;
        final qid = m.state.questionId;
        m[r[0]].answer(yes);
        m.seconds(5);
        expect(m.state.questionId, qid + 1);
        // r[1] answers the closed question (its client still showed it).
        m.sim[r[1]].session
            .sendTo([m.sim.host.id], {'who': 'answer', 'a': 'gotIt', 'q': qid});
        m.run();
        expect(m.state.answers, isEmpty);
        expect(m.state.tallyDeadline, isNull);
        expect(m.asker, asker);
      });
    });

    test('C5 a responder leaves mid-count: their answer is dropped', () {
      play(4, (m) {
        toAsking(m);
        final r = m.state.responders.where((p) => p != m.sim.host.id).toList();
        final others = m.state.responders.where((p) => p != r[0]).toList();
        m[r[0]].answer(gotIt);
        m[others[0]].answer(no);
        m.run();
        m.vanish(r[0]);
        expect(m.state.answers.keys, [others[0]]);
        m[others[1]].answer(no);
        m.run();
        expect(m.state.last?.counts, {no: 2});
        expect(m.state.last?.outcome, TallyOutcome.no);
      });
    });
  });

  group('C6', () {
    test('C6 every multiset of answers for 1 to 7 responders', () {
      var cases = 0;
      for (var responders = 1; responders <= 7; responders++) {
        for (var g = 0; g <= responders; g++) {
          for (var n = 0; g + n <= responders; n++) {
            for (var y = 0; g + n + y <= responders; y++) {
              for (var s = 0; g + n + y + s <= responders; s++) {
                final given = [
                  ...List.filled(g, gotIt),
                  ...List.filled(n, no),
                  ...List.filled(y, yes),
                  ...List.filled(s, sortOf),
                ];
                expect(tallyOutcome(given, responders: responders),
                    oracle(given, responders),
                    reason: 'r=$responders g=$g n=$n y=$y s=$s');
                cases++;
              }
            }
          }
        }
      }
      expect(cases, greaterThan(500));
    });

    test('C6 the table agreed with the user', () {
      TallyOutcome? t(List<MatchAnswer> a, int r) =>
          tallyOutcome(a, responders: r);
      expect(t([], 3), isNull);
      // One responder (two players): one got it is the guess.
      expect(t([gotIt], 1), TallyOutcome.gotIt);
      expect(t([no], 1), TallyOutcome.no);
      expect(t([sortOf], 1), TallyOutcome.yes);
      // Two or more could answer: one got it is never enough.
      expect(t([gotIt], 2), TallyOutcome.yes);
      expect(t([gotIt], 3), TallyOutcome.yes);
      expect(t([gotIt, gotIt], 3), TallyOutcome.gotIt);
      expect(t([gotIt, gotIt, no], 3), TallyOutcome.gotIt);
      // Exactly half is not more than half.
      expect(t([gotIt, gotIt, no, no], 4), TallyOutcome.yes);
      expect(t([gotIt, gotIt, yes, sortOf], 4), TallyOutcome.yes);
      expect(t([gotIt, gotIt, gotIt, no, no], 5), TallyOutcome.gotIt);
      // Ties are yes; got it counts on the yes side when it loses.
      expect(t([yes, no], 2), TallyOutcome.yes);
      expect(t([sortOf, no], 2), TallyOutcome.yes);
      expect(t([gotIt, no], 2), TallyOutcome.yes);
      expect(t([gotIt, no, no], 3), TallyOutcome.no);
      expect(t([yes, sortOf, gotIt, no, no, no], 6), TallyOutcome.yes);
      expect(t([yes, sortOf, no, no, no], 5), TallyOutcome.no);
    });

    test('C6 in the engine: 2 players, one got it is the guess', () {
      play(2, (m) {
        toAsking(m);
        final asker = m.asker!;
        m.answerAll(gotIt);
        expect(m.state.guessed, {asker: 1});
        expect(m.state.last?.outcome, TallyOutcome.gotIt);
      });
    });

    test('C6 in the engine: got it by 2 of 2 given among 7 is the guess', () {
      play(8, (m) {
        toAsking(m);
        final asker = m.asker!;
        final r = m.state.responders;
        m[r[0]].answer(gotIt);
        m[r[1]].answer(gotIt);
        m.seconds(5);
        expect(m.state.guessed, {asker: 1});
      });
    });

    test('C6 in the engine: 3 got it and 3 no among 7 is a yes', () {
      play(8, (m) {
        toAsking(m);
        final asker = m.asker!;
        final r = m.state.responders;
        for (var i = 0; i < 6; i++) {
          m[r[i]].answer(i < 3 ? gotIt : no);
        }
        m.seconds(5);
        expect(m.state.last?.outcome, TallyOutcome.yes);
        expect(m.state.guessed, isEmpty);
        expect(m.asker, asker);
        expect(m.state.question, 2);
      });
    });
  });

  group('C7', () {
    test(
        'C7 three yes in a row pass the turn; silence passes; no skip on clock',
        () {
      play(4, settings: MatchSettings(secondsPerQuestion: 15), (m) {
        toAsking(m);
        final order = m.state.order;
        expect(m.state.deadline, m.now + 15000);
        m.answerAll(yes);
        expect((m.asker, m.state.question), (order[0], 2));
        expect(m.state.deadline, m.now + 15000);
        m.answerAll(sortOf);
        expect((m.asker, m.state.question), (order[0], 3));
        m.answerAll(yes);
        expect((m.asker, m.state.question), (order[1], 1));
        m.host.hostSkipTurn();
        m.run();
        expect(m.asker, order[1]);
        m.seconds(14.999);
        expect(m.asker, order[1]);
        m.seconds(0.001);
        expect(m.asker, order[2]);
        expect(m.state.last?.outcome, isNull);
      });
    });

    test('C7 without a clock only the host skips', () {
      play(3, settings: MatchSettings(secondsPerQuestion: null), (m) {
        toAsking(m);
        final order = m.state.order;
        m.seconds(3600);
        expect(m.asker, order[0]);
        final other = m.matches.keys.firstWhere((p) => p != m.sim.host.id);
        m[other].hostSkipTurn();
        m.run();
        expect(m.asker, order[0]);
        m.host.hostSkipTurn();
        m.run();
        expect(m.asker, order[1]);
      });
    });
  });

  group('C8', () {
    test('C8 the guess reveals to the owner with the author; host included',
        () {
      play(3, (m) {
        toAsking(m);
        // Play until the host is the one asking, then the host guesses.
        while (m.asker != m.sim.host.id) {
          m.answerAll(no);
        }
        final host = m.sim.host.id;
        expect(m[host].plaqueOf(host), isNull);
        m.answerAll(gotIt);
        // The rules moved on at once, whatever the host's plaque did.
        expect(m.state.guessed.keys, [host]);
        expect(m.asker, isNot(host));
        m.run();
        final plaque = m[host].plaqueOf(host);
        expect(plaque?.text, startsWith('for $host by '));
        expect(plaque?.author, isNot(host));
        expect(plaque?.author, isNotNull);
        expect(m.state.responders, contains(host));
        expect(m.state.active, isNot(contains(host)));
        // The host answers the next question.
        m[host].answer(no);
        m.run();
        expect(m.state.answers[host], no);
      });
    });
  });

  group('C9 C10', () {
    for (final limit in [4, 8, 12]) {
      test('C9 C10 limit $limit: points per lap, zero in the rescue', () {
        play(4, settings: MatchSettings(lapLimit: limit), (m) {
          toAsking(m);
          final [a, b, c, d] = m.state.order;
          // a guesses in lap 1.
          m.answerAll(gotIt);
          expect(m.state.roundPoints[a], limit);
          // b guesses in the last lap, c and d never.
          while (!(m.state.lap == limit && m.asker == b)) {
            m.expectPhase(MatchPhase.asking);
            m.answerAll(no);
          }
          m.answerAll(gotIt);
          expect(m.state.roundPoints[b], 1);
          expect(m.state.guessed, {a: 1, b: limit});
          m.answerAll(no); // c
          m.expectPhase(MatchPhase.asking);
          m.answerAll(no); // d, the last turn of the last lap
          m.expectPhase(MatchPhase.rescue);
          expect(m.state.deadline, m.now + 30000);
          expect(m.state.active, [c, d]);
          // A got it in the rescue counts for nothing.
          m[a].answer(gotIt);
          m[b].answer(gotIt);
          m.run();
          expect(m[c].plaqueOf(c), isNull);
          m.seconds(29.999);
          m.expectPhase(MatchPhase.rescue);
          m.seconds(0.001);
          m.expectPhase(MatchPhase.scores);
          expect(m[c].plaqueOf(c), isNotNull);
          expect(m[d].plaqueOf(d), isNotNull);
          expect(m.state.points, {a: limit, b: 1, c: 0, d: 0});
          expect(m.state.roundPoints, {a: limit, b: 1});
        });
      });
    }

    test('C10 lapPoints for every limit and lap', () {
      for (var limit = 4; limit <= 12; limit++) {
        for (var lap = 1; lap <= limit; lap++) {
          expect(lapPoints(lapLimit: limit, lap: lap), limit - lap + 1);
        }
        expect(lapPoints(lapLimit: limit, lap: 1), limit);
        expect(lapPoints(lapLimit: limit, lap: limit), 1);
      }
    });

    test('C9 one player left starts the rescue at once', () {
      play(4, (m) {
        toAsking(m);
        final [_, _, _, d] = m.state.order;
        m.answerAll(gotIt);
        m.answerAll(gotIt);
        m.expectPhase(MatchPhase.asking);
        m.answerAll(gotIt);
        m.expectPhase(MatchPhase.rescue);
        expect(m.state.active, [d]);
        m.seconds(30);
        expect(
            m.sim.host.custody.ledger.entries[d]?.state, PlaqueState.revealed);
        expect(m.state.points[d], 0);
      });
    });
  });

  group('C11', () {
    test('C11 standings and awards from a played match', () {
      play(3, settings: MatchSettings(rounds: 1), (m) {
        toAsking(m);
        final [a, b, c] = m.state.order;
        m.answerAll(no); // a: 1 asked, 1 no
        m.answerAll(yes); // b q1 yes
        m.answerAll(gotIt); // b q2 guess: 2 asked
        m.answerAll(no); // c: 1 no
        m.answerAll(no); // a: 2 no (lap 2)
        m.answerAll(no); // c: 2 no
        m.answerAll(gotIt); // a guesses lap 3: 3 asked
        m.expectPhase(MatchPhase.rescue);
        m.seconds(30);
        m.expectPhase(MatchPhase.finished);
        expect(m.state.points, {a: 6, b: 8, c: 0});
        final st = m.state.standings;
        expect([for (final s in st) (s.player, s.points, s.place)],
            [(b, 8, 1), (a, 6, 2), (c, 0, 3)]);
        expect(m.state.awards.fewestQuestions, {b});
        expect(m.state.awards.mostNoes, {a, c});
        expect(m.state.stats[c]!.guessed, 0);
      });
    });

    test('C11 the total adds the rounds', () {
      play(3, settings: MatchSettings(rounds: 3), (m) {
        m.host.hostStart();
        m.run();
        final total = <String, int>{};
        for (var round = 1; round <= 3; round++) {
          m.writeAll();
          m.seconds(10);
          m.expectPhase(MatchPhase.asking);
          final [a, b, c] = m.state.order;
          m.answerAll(gotIt); // a, lap 1: 8
          m.answerAll(no); // b
          m.answerAll(no); // c
          m.answerAll(gotIt); // b, lap 2: 7
          m.expectPhase(MatchPhase.rescue);
          total[a] = (total[a] ?? 0) + 8;
          total[b] = (total[b] ?? 0) + 7;
          total[c] = total[c] ?? 0;
          m.seconds(30);
          expect(m.state.roundPoints, {a: 8, b: 7});
          expect(m.state.points, total);
          if (round < 3) m.seconds(10);
        }
        m.expectPhase(MatchPhase.finished);
        expect(total.values.reduce((x, y) => x + y), 45);
        final st = m.state.standings;
        expect({for (final s in st) s.player: s.points}, total);
        for (var i = 1; i < st.length; i++) {
          expect(st[i].points, lessThanOrEqualTo(st[i - 1].points));
        }
      });
    });

    test('C11 awards: only who guessed; ties share', () {
      final a = matchAwards({
        'x': const PlayerStats(asked: 1, guessed: 0, noes: 0),
        'y': const PlayerStats(asked: 6, guessed: 2, noes: 3),
        'z': const PlayerStats(asked: 3, guessed: 1, noes: 3),
        'w': const PlayerStats(asked: 9, guessed: 1, noes: 1),
      });
      expect(a.fewestQuestions, {'y', 'z'});
      expect(a.mostNoes, {'y', 'z'});
      final none = matchAwards({'x': const PlayerStats(asked: 4)});
      expect(none.fewestQuestions, isEmpty);
      expect(none.mostNoes, isEmpty);
    });
  });

  group('C12', () {
    test('C12 last place picks; 20 s then a draw; Homemade has none', () {
      play(3,
          settings: MatchSettings(mode: MatchMode.deck, theme: DeckTheme.jobs),
          (m) {
        toAsking(m);
        final [a, b, c] = m.state.order;
        m.answerAll(gotIt);
        m.answerAll(no);
        m.answerAll(no);
        m.answerAll(gotIt); // b lap 2
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        expect(m.state.chooser, c);
        expect(m.state.deadline, m.now + 20000);
        m[a].chooseTheme(DeckTheme.mishaps);
        m[b].chooseTheme(DeckTheme.mishaps);
        m.run();
        m.expectPhase(MatchPhase.scores);
        m.seconds(19.999);
        m.expectPhase(MatchPhase.scores);
        m.seconds(0.001);
        expect(m.state.round, 2);
        expect(m.state.theme, isNotNull);
      });
      play(3, (m) {
        toAsking(m);
        m.answerAll(gotIt);
        m.answerAll(gotIt);
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        expect(m.state.chooser, isNull);
        expect(m.state.theme, isNull);
        for (final match in m.matches.values) {
          match.chooseTheme(DeckTheme.jobs);
        }
        m.run();
        m.expectPhase(MatchPhase.scores);
        expect(m.state.theme, isNull);
      });
    });
  });

  group('C13', () {
    test('C13 joiner watches then plays; leaver retired and skipped', () {
      play(4, settings: MatchSettings(rounds: 2), (m) {
        toAsking(m);
        final order = [...m.state.order];
        final late = m.add('p8');
        expect(late.playsThisRound, isFalse);
        expect(late.writingFor, isNull);
        for (final o in order) {
          expect(late.plaqueOf(o), isNotNull);
        }
        final gone = order.lastWhere((p) => p != m.sim.host.id);
        m.vanish(gone);
        expect(m.sim.host.custody.ledger.entries[gone]?.state,
            PlaqueState.retired);
        final asked = <String>[];
        for (var t = 0; t < 6; t++) {
          asked.add(m.asker!);
          m.answerAll(no);
        }
        expect(asked, isNot(contains(gone)));
        expect(asked, isNot(contains('p8')));
        while (m.state.phase == MatchPhase.asking) {
          m.answerAll(gotIt);
        }
        m.seconds(30);
        m.expectPhase(MatchPhase.scores);
        m.seconds(10);
        expect(m.state.round, 2);
        expect(m.state.order.toSet(), {...order, 'p8'}..remove(gone));
        expect(late.writingFor, isNotNull);
      });
    });

    for (final phase in MatchPhase.values) {
      if (phase == MatchPhase.lobby || phase == MatchPhase.finished) continue;
      if (phase == MatchPhase.dealing) continue;
      test('C13 fewer than 2 players in $phase: the final result', () {
        play(2, settings: MatchSettings(rounds: 3), (m) {
          m.host.hostStart();
          m.run();
          if (phase != MatchPhase.writing) {
            m.writeAll();
            if (phase != MatchPhase.look) {
              m.seconds(10);
              if (phase != MatchPhase.asking) {
                m.answerAll(gotIt);
                if (phase == MatchPhase.scores) m.seconds(30);
              }
            }
          }
          m.expectPhase(phase);
          m.vanish('p1');
          m.expectPhase(MatchPhase.finished);
        });
      });
    }
  });

  group('C14', () {
    test('C14 new host mid-turn: phase, order, points, turn and clock', () {
      play(5, (m) {
        toAsking(m);
        m.answerAll(gotIt);
        while (m.asker == 'p0') {
          m.answerAll(no);
        }
        final asker = m.asker!;
        m.seconds(7);
        final before = MatchState.fromJson(
            jsonDecode(jsonEncode(m.state.toJson())) as Map<String, Object?>);
        expect(m.sim.host.id, 'p0');
        m.vanish('p0');
        expect(m.sim.host.id, 'p1');
        final after = m.state;
        expect(after.phase, before.phase);
        expect(after.order, before.order);
        expect(after.points, before.points);
        expect(after.guessed, before.guessed);
        expect(after.lap, before.lap);
        expect(after.turn, before.turn);
        expect(after.question, before.question);
        expect(after.asker, asker);
        expect(after.left, {'p0'});
        expect(after.deadline, before.deadline);
        m.wait(Duration(milliseconds: before.deadline! - m.now - 1));
        expect(m.asker, asker);
        m.wait(const Duration(milliseconds: 1));
        expect(m.asker, isNot(asker));
        for (final match in m.matches.values) {
          expect(match.state.toJson(), m.state.toJson());
        }
      });
    });

    for (final phase in [
      MatchPhase.look,
      MatchPhase.rescue,
      MatchPhase.scores
    ]) {
      test('C14 new host in $phase: the deadline holds', () {
        play(4, (m) {
          m.host.hostStart();
          m.run();
          m.writeAll();
          if (phase != MatchPhase.look) {
            m.seconds(10);
            final rounds = phase == MatchPhase.rescue ? 3 : 3;
            for (var i = 0; i < rounds; i++) {
              m.answerAll(gotIt);
            }
            if (phase == MatchPhase.scores) m.seconds(30);
          }
          m.expectPhase(phase);
          m.seconds(4);
          final deadline = m.state.deadline!;
          final points = {...m.state.points};
          final round = m.state.round;
          m.vanish('p0');
          expect(m.sim.host.id, 'p1');
          m.expectPhase(phase);
          expect(m.state.deadline, deadline);
          expect(m.state.points, points);
          m.wait(Duration(milliseconds: deadline - m.now - 1));
          m.expectPhase(phase);
          expect(m.state.round, round);
          m.wait(const Duration(milliseconds: 1));
          expect(m.state.phase, isNot(phase));
        });
      });
    }
  });

  group('C15', () {
    test('C15 ranges, defaults and no clock; they survive the wire', () {
      final d = MatchSettings();
      expect((d.rounds, d.secondsPerQuestion, d.lapLimit), (3, 30, 8));
      for (final (given, want) in [(0, 1), (1, 1), (5, 5), (6, 5), (-3, 1)]) {
        expect(MatchSettings(rounds: given).rounds, want);
      }
      for (final (given, want) in [(14, 15), (15, 15), (60, 60), (61, 60)]) {
        expect(
            MatchSettings(secondsPerQuestion: given).secondsPerQuestion, want);
      }
      expect(
          MatchSettings(secondsPerQuestion: null).secondsPerQuestion, isNull);
      for (final (given, want) in [(3, 4), (4, 4), (12, 12), (13, 12)]) {
        expect(MatchSettings(lapLimit: given).lapLimit, want);
      }
      final wire = MatchSettings.fromJson(jsonDecode(jsonEncode(
          MatchSettings(rounds: 9, secondsPerQuestion: null, lapLimit: 2)
              .toJson())));
      expect(
          (wire.rounds, wire.secondsPerQuestion, wire.lapLimit), (5, null, 4));
      // A host cannot be made to run out-of-range settings from the wire.
      final forged = MatchSettings.fromJson(
          {'rounds': 99, 'seconds': 1, 'laps': 99, 'mode': 'deck'});
      expect((forged.rounds, forged.secondsPerQuestion, forged.lapLimit),
          (5, 15, 12));
    });
  });

  group('C16', () {
    /// A whole match with random answers, and people leaving and joining.
    void whole(MatchMode mode, int players, int seed, {bool churn = false}) {
      play(players,
          seed: seed,
          settings: MatchSettings(
              mode: mode, rounds: 2, lapLimit: 4, secondsPerQuestion: 15), (m) {
        final rnd = Random(seed * 31 + players);
        m.host.hostStart();
        m.run();
        var guard = 0, joined = 0;
        var churned = false;
        while (m.state.phase != MatchPhase.finished) {
          if (++guard > 4000)
            fail('the match never ended: ${m.state.toJson()}');
          switch (m.state.phase) {
            case MatchPhase.writing:
              m.writeAll(silent: {if (rnd.nextBool()) m.matches.keys.last});
              if (m.state.phase == MatchPhase.writing) m.seconds(60);
            case MatchPhase.dealing:
              m.seconds(1);
            case MatchPhase.look:
              if (mode == MatchMode.deck) {
                final o = m.state.order;
                m[o[0]].askSwap(o[1]);
                m.run();
              }
              m.seconds(10);
            case MatchPhase.asking:
              if (churn && !churned && m.state.lap == 2 && players > 2) {
                churned = true;
                final gone = m.state.order
                    .lastWhere((p) => p != m.sim.host.id && p != m.asker);
                m.vanish(gone);
                m.add('q${joined++}');
                continue;
              }
              final pick = rnd.nextInt(10);
              if (pick == 0) {
                m.seconds(15); // silence
              } else {
                for (final id in [...m.state.responders]) {
                  final a = MatchAnswer.values[rnd.nextInt(4)];
                  if (rnd.nextInt(6) != 0) m[id].answer(a);
                }
                m.run();
                if (m.state.answers.isNotEmpty) m.seconds(5);
                if (m.state.answers.isEmpty &&
                    m.state.phase == MatchPhase.asking &&
                    m.state.tallyDeadline == null) {
                  // nobody answered this time
                }
              }
            case MatchPhase.rescue:
              m.seconds(30);
            case MatchPhase.scores:
              if (mode == MatchMode.deck && rnd.nextBool()) {
                m[m.state.chooser!].chooseTheme(DeckTheme.objects);
                m.run();
              } else {
                m.seconds(20);
              }
            case MatchPhase.lobby:
            case MatchPhase.finished:
              fail('unexpected ${m.state.phase}');
          }
          // No state published carries a plaque's text or card.
          expect(m.ownLeaks(), isEmpty);
        }
        expect(m.state.round, 2);
        final s = m.state;
        // Points are consistent with the laps recorded.
        for (final e in s.roundPoints.entries) {
          expect(e.value, inInclusiveRange(1, 4));
        }
        for (final p in s.points.values) {
          expect(p, inInclusiveRange(0, 8));
        }
        final st = s.standings;
        for (var i = 1; i < st.length; i++) {
          expect(st[i].points, lessThanOrEqualTo(st[i - 1].points));
        }
        for (final w in s.awards.fewestQuestions) {
          expect(s.stats[w]!.guessed, greaterThan(0));
        }
        for (final match in m.matches.values) {
          expect(match.state.toJson(), s.toJson());
        }
        expect(m.sim.leaks(), isEmpty,
            reason: 'mode=$mode players=$players seed=$seed');
        expect(m.sim.inspected, greaterThan(20));
        // The public state never names a plaque's text.
        final wire = jsonEncode(s.toJson());
        expect(wire.contains('for p'), isFalse);
        expect(wire.contains('card-'), isFalse);
      });
    }

    for (final mode in MatchMode.values) {
      for (final players in [2, 3, 8]) {
        test('C16 whole ${mode.key} matches, $players players, 6 seeds', () {
          for (var seed = 1; seed <= 6; seed++) {
            whole(mode, players, seed);
          }
        });
      }
      for (final players in [3, 8]) {
        test(
            'C16 whole ${mode.key} matches with a leaver and a joiner, '
            '$players players, 6 seeds', () {
          for (var seed = 1; seed <= 6; seed++) {
            whole(mode, players, seed, churn: true);
          }
        });
      }
    }
  });
}
