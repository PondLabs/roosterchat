// LOCAL ONLY (not committed): prints the lawn texture's average colour.
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;
import 'package:rooster/client/components/sunny_side_putt/courses/corn_maze.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

void main() {
  for (final entry in theCornMazeHoles.take(3)) {
    test('lawn ${entry.hole.id}', () {
      final world = PuttWorld3D();
      world.buildHole(entry.hole, eggRadius: 0.45, label: '1');
      final lawn = world.holeGroup('ground')!.children.single as tjs.Mesh;
      final texture = lawn.material!.map! as tjs.DataTexture;
      final data = texture.image.data as dynamic;
      var r = 0, g = 0, b = 0;
      final n = data.length ~/ 4;
      for (var i = 0; i < data.length; i += 4) {
        r += data[i] as int;
        g += data[i + 1] as int;
        b += data[i + 2] as int;
      }
      print('${entry.hole.id} ${texture.image.width}x${texture.image.height} avg ${r ~/ n} ${g ~/ n} ${b ~/ n} bounds ${entry.hole.bounds.width}x${entry.hole.bounds.height} garden=${world.holeGroup('garden') != null}');
      world.dispose();
    });
  }
}
