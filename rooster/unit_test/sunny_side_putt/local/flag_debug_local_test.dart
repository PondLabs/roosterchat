// LOCAL ONLY (not committed): prints the flag cloth's vertices.
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:rooster/client/components/sunny_side_putt/courses/coop.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

void main() {
  test('flag', () {
    final world = PuttWorld3D();
    world.buildHole(theCoopHoles.first.hole, eggRadius: 0.45, label: '1');
    world.applySnapshot(const PuttWorldFrame(time: 0));
    world.applySnapshot(const PuttWorldFrame(time: 0.03));
    tjs.Object3D? cloth;
    world.scene.traverse((o) {
      if (o.name == 'flag-cloth') cloth = o;
    });
    final pos = cloth!.geometry!.attributes['position'] as dynamic;
    for (var i = 0; i < pos.count; i += 13) {
      print('v$i ${pos.getX(i)} ${pos.getY(i)} ${pos.getZ(i)}');
    }
    print('parent rot ${cloth!.parent!.rotation.x} ${cloth!.parent!.rotation.y} ${cloth!.parent!.rotation.z}');
    print('cloth rot ${cloth!.rotation.x} ${cloth!.rotation.y} ${cloth!.rotation.z}');
  });
}
