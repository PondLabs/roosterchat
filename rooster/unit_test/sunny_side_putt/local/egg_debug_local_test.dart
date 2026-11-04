// LOCAL ONLY (not committed): checks an egg stays finite through retints.
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/coop.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_art.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

void main() {
  test('egg stays finite', () {
    final world = PuttWorld3D();
    final hole = theCoopHoles[2].hole;
    world.buildHole(hole, eggRadius: 0.45, label: '3');
    for (var i = 0; i < 200; i++) {
      final tint = PuttPalette.tintForIndex(i < 3 ? 3 : 0);
      world.applySnapshot(PuttWorldFrame(time: i / 60, eggs: [
        PuttWorldEgg(playerId: 'me', position: hole.tee, velocity: Vec2.zero, tint: tint, radius: 0.45, mine: true),
      ]));
    }
    final egg = world.eggOf('me')!;
    print('pos ${egg.position.x} ${egg.position.y} ${egg.position.z} q ${egg.quaternion.x} ${egg.quaternion.y} ${egg.quaternion.z} ${egg.quaternion.w} visible ${egg.visible} scale ${egg.scale.x}');
    for (final c in egg.children) {
      print('child ${c.name} visible ${c.visible} pos ${c.position.y}');
    }
  });
}
