// With no GL to draw with (a machine without it, CI's virtual display), the
// green's surface falls back to its plain panel and the world still moves
// every frame: the camera fitted and following, the eggs and the tags
// riding it, the aim's ray through the camera - only the drawing is gone.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_art.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';

void main() {
  setUp(() => PuttThreeSurface.debugGpuSupported = true);
  tearDown(() => PuttThreeSurface.debugGpuSupported = null);

  testWidgets('a GL start that fails leaves the world moving, not drawn',
      (tester) async {
    // The GL plugin refuses, as on a machine without the GL it needs (left
    // alone, the test runner never answers it at all).
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_angle'),
        (call) async => throw PlatformException(code: 'no-gl'));
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_angle'), null));
    final hole = stubHole(id: 'fallback', width: 30, height: 20);
    final world = PuttWorld3D(viewport: const ui.Size(800, 600))
      ..buildHole(hole, eggRadius: 0.45);
    const egg = Vec2(10, 10);
    var frames = 0;
    var failed = false;
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: PuttThreeSurface(
          world: world,
          buildFrame: () => PuttWorldFrame(time: frames / 60, eggs: [
            PuttWorldEgg(
              playerId: 'me',
              position: egg,
              velocity: Vec2.zero,
              tint: PuttPalette.tintForIndex(0),
              radius: 0.45,
              mine: true,
            ),
          ]),
          onFailed: () => failed = true,
          onFrame: () => frames++,
        ),
      ),
    ));
    // The start fails a beat in (its plugin is missing here).
    for (var i = 0; i < 20 && !failed; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failed, isTrue, reason: 'no GL here');
    final before = frames;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames, greaterThan(before + 5), reason: 'the world still moves');
    // The camera was fitted to the view: the egg lands on the screen.
    final pixel = world.projectToWorld(egg);
    expect(pixel.dx, inInclusiveRange(0, 800));
    expect(pixel.dy, inInclusiveRange(0, 600));
    expect(world.eggOf('me'), isNotNull, reason: 'the eggs follow the frames');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
