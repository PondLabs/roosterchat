import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

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

  group('writing', () {
    test('each player writes one teammate, chosen in secret', () {
      play(4, (m) {
        expect(m.host.hostStart(), isTrue);
        m.run();
        m.expectPhase(MatchPhase.writing);
        final owners = {
          for (final id in m.matches.keys) id: m[id].writingFor,
        };
        expect(owners.values.nonNulls.toSet(), m.matches.keys.toSet());
        for (final MapEntry(key: author, value: owner) in owners.entries) {
          expect(owner, isNot(author));
        }
        // Nobody but the author and the host is told who writes for whom.
        final told = m.sim.call.delivered.where((d) =>
            d.message['t'] == 'direct' &&
            (d.message['m'] as Map)['who'] == 'write');
        for (final message in told) {
          expect((message.message['m'] as Map)['o'], owners[message.to]);
        }
      });
    });

    test('text from 1 to 40 characters and a kind, once', () {
      play(2, (m) {
        m.host.hostStart();
        m.run();
        final author = m['p1'];
        expect(author.write('', PlaqueKind.animal), WriteResult.badText);
        expect(author.write('   ', PlaqueKind.animal), WriteResult.badText);
        expect(author.write('x' * 41, PlaqueKind.animal), WriteResult.badText);
        expect(author.write(' Capybara ', PlaqueKind.animal), WriteResult.sent);
        expect(author.write('Dog', PlaqueKind.animal), WriteResult.closed);
        m.run();
        expect(m.sim.truth('p0')?.text, 'Capybara');
        expect(m.sim.truth('p0')?.kind, PlaqueKind.animal);
        expect(m.sim.truth('p0')?.author, 'p1');
      });
    });

    test('everyone wrote: ten seconds to look, then the questions', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.seconds(20);
        m.writeAll();
        m.expectPhase(MatchPhase.look);
        expect(m.state.deadline, m.now + 10000);
        m.seconds(9.9);
        m.expectPhase(MatchPhase.look);
        m.seconds(0.1);
        m.expectPhase(MatchPhase.asking);
        expect(m.sim.misplaced(), isEmpty);
        expect(m.ownLeaks(), isEmpty);
      });
    });

    test('a plaque not written in 60 s is a card of Anything goes', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        final silent = m.matches.keys.first;
        final owner = m[silent].writingFor!;
        m.writeAll(silent: {silent});
        m.seconds(59.9);
        m.expectPhase(MatchPhase.writing);
        expect(m.sim.truth(owner), isNull);
        m.seconds(0.1);
        m.expectPhase(MatchPhase.look);
        expect(m.sim.truth(owner)?.cardId, isNotNull);
        expect(
            m[silent].write('too late', PlaqueKind.other), WriteResult.closed);
        // The others are as their authors wrote them.
        for (final other in m.state.order.where((o) => o != owner)) {
          expect(m.sim.truth(other)?.author, isNotNull);
        }
        expect(m.sim.misplaced(), isEmpty);
      });
    });

    test('the late card comes from the packs that are on, any theme', () {
      play(2, settings: MatchSettings(packs: {CardReach.br}), (m) {
        m.host.hostStart();
        m.run();
        m.seconds(60);
        m.expectPhase(MatchPhase.look);
        final orders = [
          for (final (_, message, _) in m.sim.call.log)
            if (message['t'] == 'state')
              for (final entry
                  in ((message['parts'] as Map?)?['plaques'] as Map? ??
                              const {})['of']
                          ?.values ??
                      const [])
                if ((entry as Map)['deal'] != null) entry['deal'] as Map,
        ];
        expect(orders, isNotEmpty);
        for (final order in orders) {
          expect(order['packs'], containsAll(['world', 'br']));
          expect(order['theme'], isNull);
        }
        expect(m.sim.truth('p0')?.cardId, isNotNull);
        expect(m.sim.truth('p1')?.cardId, isNotNull);
      });
    });
  });
}
