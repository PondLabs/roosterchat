// An independent review's reproductions (second round), kept as regression
// tests. K<n> names the case; each states what criterion 14 asks for: the
// same clock, within 2 s, after a host change.

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

/// The time [id]'s screen would show as left of the phase.
int left(MatchSim m, String id) => m[id].state.deadline! - m[id].hostNow;

/// Runs until [phase] is over, in steps of 100 ms; the seconds it took.
double until(MatchSim m, MatchPhase phase, {double most = 400}) {
  var took = 0.0;
  while (m.state.phase == phase && took < most) {
    m.seconds(0.1);
    took += 0.1;
  }
  return took;
}

const skews = [
  ('30 s ahead', Duration(seconds: 30)),
  ('30 s behind', Duration(seconds: -30)),
  ('3 h ahead', Duration(hours: 3)),
  ('3 h behind', Duration(hours: -3)),
];

void main() {
  group('K7 who joins mid-round', () {
    test('K7a reads the time that is left of the look', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.expectPhase(MatchPhase.look);
        m.seconds(8);
        m.add('p9');
        expect((left(m, 'p9') - 2000).abs(), lessThanOrEqualTo(2000),
            reason: 'p9 reads ${left(m, 'p9')} ms left of the look, 2000 are');
      });
    });

    test('K7b reads the time that is left of the rescue', () {
      play(3, settings: MatchSettings(lapLimit: 4, rounds: 2), (m) {
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.seconds(10);
        while (m.state.phase == MatchPhase.asking) {
          m.answerAll(no);
        }
        m.expectPhase(MatchPhase.rescue);
        m.seconds(25);
        m.add('p9');
        expect((left(m, 'p9') - 5000).abs(), lessThanOrEqualTo(2000),
            reason: 'p9 reads ${left(m, 'p9')} ms left, 5000 are');
      });
    });

    test('K7c takes the seat: the look ends when it was due (same clocks)', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.expectPhase(MatchPhase.look);
        m.seconds(8);
        m.add('a0'); // sorts first: the next host
        m.vanish('p0');
        expect(m.sim.host.id, 'a0');
        m.expectPhase(MatchPhase.look);
        final took = until(m, MatchPhase.look);
        expect((took - 2).abs(), lessThanOrEqualTo(2),
            reason: 'the look ended $took s after the change, 2 were left');
      });
    });

    test('K7d takes the seat mid-rescue (same clocks)', () {
      play(3, settings: MatchSettings(lapLimit: 4, rounds: 2), (m) {
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.seconds(10);
        while (m.state.phase == MatchPhase.asking) {
          m.answerAll(no);
        }
        m.expectPhase(MatchPhase.rescue);
        m.seconds(25);
        m.add('a0');
        m.vanish('p0');
        expect(m.sim.host.id, 'a0');
        final took = until(m, MatchPhase.rescue);
        expect((took - 5).abs(), lessThanOrEqualTo(2),
            reason: 'the rescue ended $took s after the change, 5 were left');
      });
    });

    test('K7e takes the seat mid-question, clock on (same clocks)', () {
      play(3, (m) {
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.seconds(10);
        m.expectPhase(MatchPhase.asking);
        while (m.asker == 'p0') {
          m.answerAll(no);
        }
        final question = m.state.questionId;
        m.seconds(25); // 5 s of the question left
        m.add('a0');
        m.vanish('p0');
        expect(m.sim.host.id, 'a0');
        var took = 0.0;
        while (m.state.questionId == question && took < 120) {
          m.seconds(0.1);
          took += 0.1;
        }
        expect((took - 5).abs(), lessThanOrEqualTo(2),
            reason: 'the turn passed $took s after the change, 5 were left');
      });
    });
  });

  group('K8 a clock that goes back', () {
    test('K8a the host\'s clock goes back 20 s mid-look', () {
      fakeAsync((async) {
        final m = MatchSim(async, 3);
        m.start(MatchSettings());
        var back = Duration.zero;
        // p0 hosts: give it a clock we can move.
        m.matches.remove('p0')!.dispose();
        final app = m.sim['p0'];
        final clock = async.getClock(DateTime.utc(2026, 11, 15, 20));
        m.matches['p0'] = WhoMatch(
          session: app.session,
          custody: app.custody,
          random: Random(app.seed),
          now: steadyClock(
              wall: () => clock.now().subtract(back),
              elapsed: () => async.elapsed),
        );
        m.run();
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.expectPhase(MatchPhase.look);
        m.seconds(4);
        back = const Duration(seconds: 20);
        final took = until(m, MatchPhase.look);
        expect((took - 6).abs(), lessThanOrEqualTo(2),
            reason: 'the look ended $took s after the clock went back');
        m.close();
      });
    });

    test('K8b a player\'s clock goes back 20 s, then they take the seat', () {
      fakeAsync((async) {
        final m = MatchSim(async, 3);
        m.start(MatchSettings());
        var back = Duration.zero;
        m.matches.remove('p1')!.dispose();
        final app = m.sim['p1'];
        final clock = async.getClock(DateTime.utc(2026, 11, 15, 20));
        m.matches['p1'] = WhoMatch(
          session: app.session,
          custody: app.custody,
          random: Random(app.seed),
          now: steadyClock(
              wall: () => clock.now().subtract(back),
              elapsed: () => async.elapsed),
        );
        m.run();
        m.host.hostStart();
        m.run();
        m.writeAll();
        m.expectPhase(MatchPhase.look);
        m.seconds(4);
        back = const Duration(seconds: 20);
        m.vanish('p0');
        expect(m.sim.host.id, 'p1');
        final took = until(m, MatchPhase.look);
        expect((took - 6).abs(), lessThanOrEqualTo(2),
            reason: 'the look ended $took s after the change, 6 were left');
        m.close();
      });
    });
  });
}
