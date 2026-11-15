// An independent inspection of the plaque secret under the match rules. It
// does not rely on the simulator's leaks(): after every move it reads each
// message delivered since the last one and each client's public state, and
// checks them against the plaques that are still on foreheads once the move
// is over.

import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import 'match_sim.dart';

const _secretPhases = {
  MatchPhase.writing,
  MatchPhase.dealing,
  MatchPhase.look,
  MatchPhase.asking,
  MatchPhase.rescue,
};

class Inspector {
  Inspector(this.m);

  final MatchSim m;
  int read = 0;
  int checked = 0;
  int reveals = 0;

  /// The owners whose plaque is still a secret now, with what must not
  /// reach them: the text and, for a card, its id.
  Map<String, List<String>> _secrets() {
    final s = m.state;
    if (!_secretPhases.contains(s.phase)) return const {};
    return {
      for (final owner in s.active)
        if (m.sim.truth(owner) case final plaque?)
          owner: [plaque.text, if (plaque.cardId != null) plaque.cardId!],
    };
  }

  /// After a move: nothing delivered during it tells a still-secret owner
  /// their plaque, no client reads its own, the ledger keeps it closed, and
  /// no public state carries any plaque's text.
  void after(String move) {
    final secrets = _secrets();
    final delivered = m.sim.call.delivered;
    for (; read < delivered.length; read++) {
      final d = delivered[read];
      final mine = secrets[d.to];
      if (mine == null) continue;
      final text = jsonEncode(d.message);
      for (final secret in mine) {
        checked++;
        if (text.contains(secret)) {
          fail('after $move: ${d.to} was sent "$secret" by ${d.from}: $text');
        }
      }
    }
    final ledger = m.sim.host.custody.ledger;
    for (final owner in secrets.keys) {
      expect(ledger.entries[owner]?.isOpen, isFalse,
          reason: 'after $move: $owner has not guessed, the plaque is closed');
      if (m.matches.containsKey(owner)) {
        expect(m[owner].plaqueOf(owner), isNull,
            reason: 'after $move: $owner reads their own plaque');
      }
    }
    // Who guessed reads their plaque (the host may get it a moment later).
    for (final owner in m.state.guessed.keys) {
      if (!m.matches.containsKey(owner)) continue;
      expect(ledger.entries[owner]?.state, PlaqueState.revealed,
          reason: 'after $move: $owner guessed, the plaque is revealed');
      if (m[owner].plaqueOf(owner) != null) reveals++;
    }
    final texts = {
      for (final owner in ledger.entries.keys)
        if (m.sim.truth(owner) case final plaque?) ...[
          plaque.text,
          if (plaque.cardId != null) plaque.cardId!,
        ],
    };
    for (final match in m.matches.values) {
      final wire = jsonEncode(match.state.toJson());
      for (final text in texts) {
        expect(wire.contains(text), isFalse,
            reason: 'after $move: the public state carries "$text"');
      }
    }
  }
}

/// What the inspection did over the matches of one test.
int checked = 0, reveals = 0;

void sane() {
  // The inspection did read messages to owners with a secret, and saw
  // plaques revealed to their owners.
  expect(checked, greaterThan(150));
  expect(reveals, greaterThan(0));
  checked = 0;
  reveals = 0;
}

void whole(MatchMode mode, int players, int seed, {bool churn = false}) {
  fakeAsync((async) {
    final m = MatchSim(async, players, seed: seed);
    m.start(MatchSettings(
        mode: mode, rounds: 2, lapLimit: 4, secondsPerQuestion: 15));
    final look = Inspector(m);
    final rnd = Random(seed * 17 + players);
    m.host.hostStart();
    m.run();
    look.after('start');
    var guard = 0, joined = 0, churned = false;
    while (m.state.phase != MatchPhase.finished) {
      if (++guard > 4000) fail('the match never ended');
      final phase = m.state.phase;
      switch (phase) {
        case MatchPhase.writing:
          for (final MapEntry(key: id, value: match) in m.matches.entries) {
            final owner = match.writingFor;
            if (owner == null || rnd.nextInt(5) == 0) continue;
            match.write('SECRET-$owner-r${m.state.round}-by-$id',
                PlaqueKind.values[rnd.nextInt(PlaqueKind.values.length)]);
          }
          m.run();
          if (m.state.phase == MatchPhase.writing) m.seconds(60);
        case MatchPhase.dealing:
          m.seconds(1);
        case MatchPhase.look:
          if (mode == MatchMode.deck) {
            final o = m.state.order;
            m[o[rnd.nextInt(o.length)]].askSwap(o[rnd.nextInt(o.length)]);
            m.run();
            look.after('swap');
          }
          m.seconds(10);
        case MatchPhase.asking:
          if (churn && !churned && m.state.lap == 2 && players > 2) {
            churned = true;
            final gone = m.state.order
                .lastWhere((p) => p != m.sim.host.id && p != m.asker);
            m.vanish(gone);
            look.after('leave');
            m.add('q${joined++}');
            look.after('join');
            continue;
          }
          if (churn && churned && joined == 1 && m.state.lap == 3) {
            // The host goes too: someone else takes the seat mid-round.
            joined++;
            m.vanish(m.sim.host.id);
            look.after('host gone');
            continue;
          }
          if (rnd.nextInt(10) == 0) {
            m.seconds(15);
          } else {
            for (final id in [...m.state.responders]) {
              if (rnd.nextInt(6) == 0) continue;
              m[id].answer(MatchAnswer.values[rnd.nextInt(4)]);
            }
            m.run();
            if (m.state.answers.isNotEmpty) m.seconds(5);
          }
        case MatchPhase.rescue:
          m.seconds(15);
          look.after('rescue half way');
          m.seconds(15);
        case MatchPhase.scores:
          if (mode == MatchMode.deck && rnd.nextBool()) {
            m[m.state.chooser!].chooseTheme(DeckTheme.objects);
            m.run();
          } else {
            m.seconds(20);
          }
        case MatchPhase.lobby:
        case MatchPhase.finished:
          fail('unexpected $phase');
      }
      look.after('$phase');
    }
    checked += look.checked;
    reveals += look.reveals;
    m.close();
  });
}

void main() {
  for (final mode in MatchMode.values) {
    for (final players in [2, 3, 5, 8]) {
      test('secret: whole ${mode.key} matches, $players players, 8 seeds', () {
        for (var seed = 1; seed <= 8; seed++) {
          whole(mode, players, seed);
        }
        sane();
      });
    }
    for (final players in [4, 8]) {
      test(
          'secret: whole ${mode.key} matches with a leaver, a joiner and a '
          'new host, $players players, 8 seeds', () {
        for (var seed = 1; seed <= 8; seed++) {
          whole(mode, players, seed, churn: true);
        }
        sane();
      });
    }
  }
}
