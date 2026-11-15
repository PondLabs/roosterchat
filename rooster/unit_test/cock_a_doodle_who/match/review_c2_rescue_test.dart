// An independent review's reproduction (second round), kept as a
// regression test. K10: a count that is open when a leaver makes the asker
// the last player still asking.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const no = MatchAnswer.no, gotIt = MatchAnswer.gotIt;

void main() {
  test('K10 two of two said got it, the fourth player leaves: it is a guess',
      () {
    var played = 0;
    for (var seed = 1; seed <= 12; seed++) {
      fakeAsync((async) {
        final m = MatchSim(async, 4, seed: seed);
        m.start(MatchSettings());
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.seconds(10);
        m.expectPhase(MatchPhase.asking);
        // The first two of the order guess in lap 1.
        m.answerAll(gotIt);
        m.answerAll(gotIt);
        final [a, b, c, d] = m.state.order;
        expect(m.state.guessed.keys, {a, b});
        expect(m.asker, c);
        if (d == m.sim.host.id || c == m.sim.host.id) {
          m.close();
          return; // keep the host out of it: this case is not a host change
        }
        played++;
        m[a].answer(gotIt);
        m[b].answer(gotIt);
        m.run();
        expect(m.state.answers, {a: gotIt, b: gotIt});
        m.expectPhase(MatchPhase.asking); // d has not answered: count open
        m.seconds(1);
        m.vanish(d);
        // Everyone still here answered, and both said got it.
        expect(m.state.guessed.keys, {a, b, c},
            reason: 'seed $seed: $c had 2 got it of 2 answers when $d left');
        expect(m.state.roundPoints[c], 8, reason: 'seed $seed');
        m.close();
      });
    }
    expect(played, greaterThan(0));
  });
}
