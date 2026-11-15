import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_rules.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_settings.dart';

void main() {
  group('who writes for whom', () {
    test('everyone writes one teammate, nobody their own, each gets one', () {
      for (var count = 2; count <= 8; count++) {
        final players = [for (var i = 0; i < count; i++) 'p$i'];
        for (var seed = 0; seed < 200; seed++) {
          final writers = drawWriters(players, Random(seed));
          expect(writers.keys.toSet(), players.toSet(),
              reason: '$count players, seed $seed: every author');
          expect(writers.values.toSet(), players.toSet(),
              reason: '$count players, seed $seed: every owner once');
          for (final MapEntry(key: author, value: owner) in writers.entries) {
            expect(author, isNot(owner),
                reason: '$count players, seed $seed: $author writes own');
          }
        }
      }
    });

    test('with four players, pairs that swap come up too', () {
      final players = ['a', 'b', 'c', 'd'];
      final swapped = [
        for (var seed = 0; seed < 200; seed++)
          drawWriters(players, Random(seed))
      ].where((w) => w[w['a']!] == 'a');
      expect(swapped, isNotEmpty);
    });
  });

  group('what a count decides', () {
    const yes = MatchAnswer.yes, no = MatchAnswer.no;
    const sortOf = MatchAnswer.sortOf, gotIt = MatchAnswer.gotIt;
    TallyOutcome? outcome(List<MatchAnswer> answers, [int? responders]) =>
        tallyOutcome(answers, responders: responders ?? answers.length);

    test('nobody answered: no outcome', () {
      expect(outcome([], 3), isNull);
    });

    test('got it wins with more than half of the answers given', () {
      expect(outcome([gotIt, gotIt, no]), TallyOutcome.gotIt);
      expect(outcome([gotIt, gotIt, no, yes]), isNot(TallyOutcome.gotIt));
      expect(outcome([gotIt, gotIt, gotIt, no, yes]), TallyOutcome.gotIt);
    });

    test('got it needs two when two or more can answer', () {
      expect(outcome([gotIt], 1), TallyOutcome.gotIt);
      expect(outcome([gotIt], 2), TallyOutcome.yes);
      expect(outcome([gotIt, gotIt], 2), TallyOutcome.gotIt);
      expect(outcome([gotIt, gotIt], 5), TallyOutcome.gotIt);
    });

    test('sort of and got it count as yes, and a tie is yes', () {
      expect(outcome([yes, no]), TallyOutcome.yes);
      expect(outcome([sortOf, no]), TallyOutcome.yes);
      expect(outcome([gotIt, no], 2), TallyOutcome.yes);
      expect(outcome([sortOf, gotIt, no, no]), TallyOutcome.yes);
      expect(outcome([sortOf, no, no]), TallyOutcome.no);
      expect(outcome([no]), TallyOutcome.no);
    });
  });

  test('points: the lap limit minus the lap of the guess, plus one', () {
    expect(lapPoints(lapLimit: 8, lap: 1), 8);
    expect(lapPoints(lapLimit: 8, lap: 8), 1);
    expect(lapPoints(lapLimit: 4, lap: 2), 3);
    expect(lapPoints(lapLimit: 12, lap: 1), 12);
  });

  test('a plaque takes from 1 to 40 characters, trimmed', () {
    expect(plaqueText(''), isNull);
    expect(plaqueText('   '), isNull);
    expect(plaqueText(' Pelé '), 'Pelé');
    expect(plaqueText('x' * 40), 'x' * 40);
    expect(plaqueText('x' * 41), isNull);
    expect(plaqueText('ç' * 40), 'ç' * 40);
  });

  test('standings by points, ties share a place', () {
    final list = matchStandings({'c': 5, 'a': 8, 'b': 5, 'd': 0});
    expect([
      for (final s in list) (s.player, s.points, s.place)
    ], [
      ('a', 8, 1),
      ('b', 5, 2),
      ('c', 5, 2),
      ('d', 0, 4),
    ]);
  });

  group('awards', () {
    test('fewest questions per plaque guessed, among who guessed', () {
      final result = matchAwards({
        'a': const PlayerStats(asked: 6, guessed: 2), // 3 per plaque
        'b': const PlayerStats(asked: 4, guessed: 1), // 4
        'c': const PlayerStats(asked: 1), // guessed nothing
      });
      expect(result.fewestQuestions, {'a'});
    });

    test('most questions answered no; ties share it', () {
      final result = matchAwards({
        'a': const PlayerStats(asked: 6, noes: 3),
        'b': const PlayerStats(asked: 4, noes: 3),
        'c': const PlayerStats(asked: 4, noes: 1),
      });
      expect(result.mostNoes, {'a', 'b'});
      expect(result.fewestQuestions, isEmpty);
    });

    test('no award when nobody qualifies', () {
      final result = matchAwards({'a': const PlayerStats(asked: 2)});
      expect(result.fewestQuestions, isEmpty);
      expect(result.mostNoes, isEmpty);
    });
  });

  group('settings', () {
    test('the defaults: 3 rounds, 30 seconds, 8 laps', () {
      final settings = MatchSettings();
      expect(settings.rounds, 3);
      expect(settings.secondsPerQuestion, 30);
      expect(settings.lapLimit, 8);
    });

    test('values are clamped into their ranges', () {
      expect(MatchSettings(rounds: 0).rounds, 1);
      expect(MatchSettings(rounds: 9).rounds, 5);
      expect(MatchSettings(secondsPerQuestion: 5).secondsPerQuestion, 15);
      expect(MatchSettings(secondsPerQuestion: 90).secondsPerQuestion, 60);
      expect(
          MatchSettings(secondsPerQuestion: null).secondsPerQuestion, isNull);
      expect(MatchSettings(lapLimit: 2).lapLimit, 4);
      expect(MatchSettings(lapLimit: 20).lapLimit, 12);
    });

    test('they travel as JSON, the clamp included', () {
      final settings = MatchSettings(
        mode: MatchMode.deck,
        rounds: 5,
        secondsPerQuestion: null,
        lapLimit: 12,
        theme: DeckTheme.animals,
        packs: {CardReach.br},
        difficulties: {CardDifficulty.hard},
      );
      final back = MatchSettings.fromJson(settings.toJson());
      expect(back.toJson(), settings.toJson());
      expect(back.packs, {CardReach.world, CardReach.br});
      expect(
          MatchSettings.fromJson({'rounds': 99, 'laps': 1}).toJson(),
          MatchSettings(rounds: 5, lapLimit: 4, secondsPerQuestion: null)
              .toJson());
    });
  });
}
