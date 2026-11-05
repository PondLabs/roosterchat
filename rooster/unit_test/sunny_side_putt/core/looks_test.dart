// The players' looks in the engine: a look is two names on the wire with
// safe fallbacks, the join brings one, a LookInput changes it in any phase,
// the player's snapshot keeps it (an old snapshot without one loads in the
// default), the journal replays it on a handoff, and a look never moves
// the game.
library;

import 'dart:convert';

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _crown = PuttLook(pattern: EggPattern.stars, hat: HatchlingHat.crown);
const _bow = PuttLook(pattern: EggPattern.dots, hat: HatchlingHat.bow);

PuttConfig _config() => PuttConfig(
      mode: GameMode.casual,
      seed: 99,
      holeTimeLimitSeconds: 30,
      wobbleMaxRadians: 0,
      courses: [
        CourseDef(id: 'looks', holes: [
          for (final id in ['l0', 'l1'])
            boxHole(
                id: id,
                par: 2,
                width: 24,
                height: 16,
                tee: const Vec2(4, 8),
                nest: const Nest(Vec2(20, 8), 0.8),
                friction: 4),
        ]),
      ],
    );

/// Every egg on the green putts at the nest, then the green settles.
void _volley(PuttEngine engine) {
  for (final player in engine.players) {
    final ball = engine.world?.ball(player.id);
    if (ball == null || ball.holed || !ball.asleep) continue;
    final (angle, power) = puttFor(engine.currentHole!, ball.position);
    engine.submitShot(player.id, angle, power * 0.7);
  }
  for (var i = 0; i < 1200 && engine.phase == PuttPhase.holePlay; i++) {
    engine.tickForward();
    if (engine.world!.allSettled) break;
  }
}

void main() {
  group('a look', () {
    test('rides the wire as two names and comes back the same', () {
      for (final pattern in EggPattern.values) {
        for (final hat in HatchlingHat.values) {
          final look = PuttLook(pattern: pattern, hat: hat);
          final wire = jsonDecode(jsonEncode(look.toJson()));
          expect(PuttLook.fromJson(wire), look);
          expect(PuttLook.decode(look.encode()), look);
        }
      }
    });

    test('anything it cannot read is the default, part by part', () {
      expect(PuttLook.fromJson(null), PuttLook.standard);
      expect(PuttLook.fromJson('stars'), PuttLook.standard);
      expect(PuttLook.fromJson({'p': 'plaid', 'h': 'crown'}),
          const PuttLook(hat: HatchlingHat.crown));
      expect(PuttLook.fromJson({'p': 'hearts', 'h': 7}),
          const PuttLook(pattern: EggPattern.hearts));
      expect(PuttLook.decode(null), PuttLook.standard);
      expect(PuttLook.decode(''), PuttLook.standard);
      expect(
          PuttLook.decode('waves'), const PuttLook(pattern: EggPattern.waves));
      expect(PuttLook.decode('top-hat/bow'),
          const PuttLook(hat: HatchlingHat.bow));
    });

    test('the default is the zig-zag band and a bare chick', () {
      expect(PuttLook.standard.pattern, EggPattern.zigzag);
      expect(PuttLook.standard.hat, HatchlingHat.none);
      expect(PuttLook.standard.isStandard, isTrue);
      expect(_crown.isStandard, isFalse);
      expect(_crown.copyWith(hat: HatchlingHat.bow),
          const PuttLook(pattern: EggPattern.stars, hat: HatchlingHat.bow));
    });
  });

  group('in the engine', () {
    test('a join brings its look; a join without one wears the default', () {
      final engine = PuttEngine(_config());
      expect(engine.join('ana', look: _crown), isTrue);
      expect(engine.join('bea'), isTrue);
      expect(engine.player('ana')!.look, _crown);
      expect(engine.player('bea')!.look, PuttLook.standard);
    });

    test('a look input changes it in any phase, for anyone in the match', () {
      final engine = PuttEngine(_config())..join('ana');
      // In the lobby.
      expect(engine.setLook('ana', _bow), isTrue);
      engine.start();
      // Mid-hole.
      expect(engine.setLook('ana', _crown), isTrue);
      final events = engine.drainEvents().whereType<PlayerLookChanged>();
      expect(events.map((e) => e.look), [_bow, _crown]);
      expect(events.every((e) => e.playerId == 'ana'), isTrue);
      expect(engine.player('ana')!.look, _crown);
      // The same look again is no change, and nobody else's is taken.
      final seq = engine.lastSeq;
      expect(engine.setLook('ana', _crown), isFalse);
      expect(engine.setLook('nobody', _bow), isFalse);
      expect(engine.lastSeq, seq, reason: 'nothing more in the journal');
      // Between holes, too (the clock ends this one).
      engine.advanceSeconds(31);
      expect(engine.phase, PuttPhase.holeScoreboard);
      expect(engine.setLook('ana', _bow), isTrue);
    });

    test('a spectator dresses too, for the seat to come', () {
      final engine = PuttEngine(PuttConfig(
          mode: GameMode.casual,
          seed: 1,
          maxPlayers: 1,
          courses: _config().courses))
        ..join('ana')
        ..join('bea');
      expect(engine.isSpectator('bea'), isTrue);
      expect(engine.setLook('bea', _bow), isTrue);
      expect(engine.player('bea')!.look, _bow);
    });

    test('the join and the look input ride the wire', () {
      const join = JoinInput(playerId: 'ana', look: _crown);
      final back = EngineInput.fromJson(
          jsonDecode(jsonEncode(join.toJson())) as Map<String, Object?>);
      expect((back as JoinInput).look, _crown);
      // A join from before looks, or with the default, carries none.
      expect(
          const JoinInput(playerId: 'ana').toJson().containsKey('l'), isFalse);
      expect(
          (EngineInput.fromJson({'k': 'join', 'p': 'ana'}) as JoinInput).look,
          PuttLook.standard);
      const look = LookInput(playerId: 'ana', look: _bow);
      final again = EngineInput.fromJson(
          jsonDecode(jsonEncode(look.toJson())) as Map<String, Object?>);
      expect(again, isA<LookInput>());
      expect((again as LookInput).playerId, 'ana');
      expect(again.look, _bow);
    });

    test('the snapshot keeps every look, and round-trips exactly', () {
      final engine = PuttEngine(_config())
        ..join('ana', look: _crown)
        ..join('bea')
        ..start();
      engine.setLook('bea', _bow);
      _volley(engine);
      final before = engine.toJson();
      final json = jsonDecode(jsonEncode(before)) as Map<String, Object?>;
      final rebuilt = PuttEngine.fromJson(json, config: engine.config);
      expect(rebuilt.toJson(), before);
      expect(rebuilt.player('ana')!.look, _crown);
      expect(rebuilt.player('bea')!.look, _bow);
    });

    test('a snapshot from before looks loads, everyone in the default', () {
      final engine = PuttEngine(_config())
        ..join('ana', look: _crown)
        ..start();
      final json = jsonDecode(jsonEncode(engine.toJson())) as Map;
      for (final player in json['players'] as List) {
        (player as Map).remove('look');
      }
      final old = PuttEngine.fromJson(json.cast<String, Object?>(),
          config: engine.config);
      expect(old.player('ana')!.look, PuttLook.standard);
      expect(old.phase, PuttPhase.holePlay, reason: 'and the match plays on');
    });

    test('a handoff replays the looks from the journal', () {
      final engine = PuttEngine(_config())
        ..join('ana')
        ..join('bea', look: _bow)
        ..start();
      final snapshotSeq = engine.lastSeq;
      final snapshot = engine.toJson();
      engine.setLook('ana', _crown);
      _volley(engine);
      engine.join('cid', look: _bow);
      engine.setLook('bea', PuttLook.standard);
      final journal =
          engine.journalSince(snapshotSeq).map((e) => e.toJson()).toList();
      final handoff = PuttEngine.replay(
        jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>,
        [
          for (final entry in journal)
            jsonDecode(jsonEncode(entry)) as Map<String, Object?>,
        ],
        config: engine.config,
        untilTick: engine.tick,
      );
      expect(handoff.toJson(), engine.toJson());
      expect(handoff.player('ana')!.look, _crown);
      expect(handoff.player('bea')!.look, PuttLook.standard);
      expect(handoff.player('cid')!.look, _bow);
    });

    test('a look never moves the game', () {
      PuttEngine play({required bool dressUp}) {
        final engine = PuttEngine(_config())
          ..join('ana', look: dressUp ? _crown : PuttLook.standard)
          ..join('bea')
          ..start();
        for (var round = 0; round < 6; round++) {
          if (dressUp) {
            engine.setLook('bea', round.isEven ? _bow : _crown);
          }
          _volley(engine);
        }
        return engine;
      }

      final plain = play(dressUp: false);
      final dressed = play(dressUp: true);
      final a = plain.toJson();
      final b = dressed.toJson();
      for (final key in a.keys) {
        if (key == 'players' || key == 'seq') continue;
        expect(jsonEncode(b[key]), jsonEncode(a[key]),
            reason: '$key differs with looks on');
      }
      expect(plain.scoreboard().map((r) => r.total),
          dressed.scoreboard().map((r) => r.total));
    });
  });
}
