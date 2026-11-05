// A name tag wears its picture only while its egg draws small (the
// opening's wide shot, the whole-hole view): a name three eggs wide
// covered the green. Up close it shows the name again.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart'
    show puttLaunchPowerUps;
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

void main() {
  test('a tag shows its picture only while its egg draws small', () {
    final course = CourseDef(
        id: 'tags', holes: [stubHole(id: 't0', width: 34, height: 22)]);
    final match = PuttMatch(
      config: PuttConfig(
        mode: GameMode.casual,
        courses: [course],
        seed: 3,
        powerUps: puttLaunchPowerUps(),
      ),
      displayNames: const {'me': 'Gabriel', 'p2': 'Maya'},
      seatedPlayerIds: const ['p2'],
    )..boot();
    final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
    final world = game.world3d;
    // A tick, so the eggs' drawn places are their own.
    match.update(1 / 60);
    // The camera close over Maya's egg, at a distance under the far rule's.
    world.rig
      ..target = match.engine.world!.ball('p2')!.position
      ..distance = 20;

    PuttTagLike maya(Size viewport) {
      world.setViewport(viewport);
      world.rig.applyTo(world.camera);
      final tag = game.tagsForFrame().singleWhere((t) => t.playerId == 'p2');
      return (compact: tag.compact, name: tag.name);
    }

    expect(maya(const Size(320, 200)).compact, isTrue,
        reason: 'on a small screen the egg is a few pixels tall');
    final close = maya(const Size(2560, 1600));
    expect(close.compact, isFalse, reason: 'big on the screen: the name');
    expect(close.name, 'Maya');

    // By the nest, big or not: the target of every putt stays clear.
    final nest = match.hole!.nest.position;
    match.engine.world!.ball('p2')!.position = nest + const Vec2(1.5, 0);
    match
      ..update(1 / 60)
      ..update(1 / 60);
    world.rig.target = nest;
    expect(maya(const Size(2560, 1600)).compact, isTrue);
  });
}

typedef PuttTagLike = ({bool compact, String name});
