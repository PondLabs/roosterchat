// The game builds a hole a step per frame (the turf off the UI isolate),
// so no frame holds for the whole build: the steps report their progress
// and land on the very scene the all-at-once build makes.
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;

import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

/// Every object's name and vertex count, depth first.
List<String> outline(tjs.Object3D root) {
  final out = <String>[];
  root.traverse((object) {
    final count = object is tjs.Mesh
        ? object.geometry?.attributes['position']?.count
        : null;
    out.add('${object.name}:${count ?? '-'}');
  });
  return out;
}

void main() {
  testWidgets('a stepped build reports its steps and matches buildHole',
      (tester) async {
    // One hole per course corner (each builds its own farm).
    for (final course in sunnySidePuttCourses) {
      final hole = course.holes.first.hole;
      final whole = PuttWorld3D(viewport: const ui.Size(800, 600))
        ..buildHole(hole, eggRadius: 0.45);
      final stepped = PuttWorld3D(viewport: const ui.Size(800, 600));
      final progress = <(int, int)>[];
      var done = false;
      stepped
          .buildHoleInSteps(hole,
              eggRadius: 0.45, onProgress: (d, t) => progress.add((d, t)))
          .then((_) => done = true);
      expect(stepped.buildingHole, hole.id);
      while (!done) {
        // The turf comes back from another isolate: real time must pass.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(stepped.buildingHole, isNull);
      final total = progress.first.$2;
      expect(progress, [for (var i = 1; i <= total; i++) (i, total)]);
      expect(outline(stepped.scene), outline(whole.scene),
          reason: '${hole.id} builds the same scene either way');
      whole.dispose();
      stepped.dispose();
    }
  });

  testWidgets('a stale build of the same hole (A, B, A) adds nothing',
      (tester) async {
    final a = sunnySidePuttCourses.first.holes[0].hole;
    final b = sunnySidePuttCourses.first.holes[1].hole;
    final whole = PuttWorld3D(viewport: const ui.Size(800, 600))
      ..buildHole(a, eggRadius: 0.45);
    final world = PuttWorld3D(viewport: const ui.Size(800, 600));
    var finished = 0;
    var done = false;
    // The first A is still awaiting its turf when B, then A again, start.
    world.buildHoleInSteps(a, eggRadius: 0.45).then((_) => finished++);
    world.buildHoleInSteps(b, eggRadius: 0.45).then((_) => finished++);
    world.buildHoleInSteps(a, eggRadius: 0.45).then((_) => done = true);
    while (!done) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
      if (!done) {
        expect(world.buildingHole, a.id,
            reason: 'only the current build clears the loading state');
      }
    }
    // Let the abandoned builds run out too.
    for (var i = 0; i < 10 && finished < 2; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(world.buildingHole, isNull);
    expect(outline(world.scene), outline(whole.scene),
        reason: 'the stale build of A adds no meshes of its own');
    whole.dispose();
    world.dispose();
  });
}
