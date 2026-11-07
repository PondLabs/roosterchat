// What keeps the 3D view from flickering that can be checked without a
// GPU: the surface is resized only where its Flutter texture survives a
// resize, and the camera's depth range leaves the turf's marks room over
// the turf.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;

import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

void main() {
  test('the GL surface is resized only where its texture survives it', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // Linux's flutter_angle registers a new texture on resize, under an id
    // the view never learns (it then shows nothing); Android's does not
    // resize at all.
    for (final (platform, resizes) in [
      (TargetPlatform.linux, false),
      (TargetPlatform.android, false),
      (TargetPlatform.windows, true),
      (TargetPlatform.macOS, true),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(PuttThreeSurface.surfaceResizes, resizes, reason: '$platform');
    }
  });

  test('the depth range holds the sky and does not crush the near plane', () {
    final world = PuttWorld3D();
    addTearDown(world.dispose);
    final dome = world.scene.getObjectByName('sky-dome') as tjs.Mesh;
    dome.geometry!.computeBoundingSphere();
    final radius = dome.geometry!.boundingSphere!.radius;
    // The dome rides with the camera at ground level; the camera stands
    // up to the widest overview's distance off the ground.
    expect(world.camera.far, greaterThan(radius + world.rig.distanceMax));
    // 24-bit depth over this range still parts a mark lifted 0.025 off the
    // turf from the turf at the far end of a big table.
    expect(world.camera.far / world.camera.near, lessThanOrEqualTo(5000));
  });
}
