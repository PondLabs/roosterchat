// What keeps the 3D view from flickering that can be checked without a
// GPU: the surface is resized only where its Flutter texture survives a
// resize, the camera's depth range leaves the turf's marks room over the
// turf, and a frame is finished on the GPU before Flutter is told it is
// there on every surface that does not swap buffers.
library;

import 'dart:ffi' hide Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_angle/flutter_angle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_angle_renderer/three_viewer.dart';
import 'package:three_js_core/three_js_core.dart' as tjs;

import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

/// A GL context that records the calls the present path makes on it.
class _RecordingGl extends RenderingContext {
  _RecordingGl(this.calls)
      : super.create(LibOpenGLES(DynamicLibrary.process()), 1, 1);

  final List<String> calls;

  @override
  void finish() => calls.add('finish');
}

/// ANGLE that records the calls the present path makes on it, in the same
/// list as the GL context's, so their order is the thing under test.
class _RecordingAngle extends FlutterAngle {
  _RecordingAngle(this.calls);

  final List<String> calls;

  @override
  void activateTexture(FlutterAngleTexture texture) => calls.add('activate');

  @override
  Future<void> updateTexture(
    FlutterAngleTexture texture, [
    WebGLTexture? sourceTexture,
  ]) async =>
      calls.add('present');
}

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

  group('a frame is finished on the GPU before Flutter is told it is there',
      () {
    /// Runs one frame of the viewer's present path and returns the calls it
    /// made, in order.
    Future<List<String>> present({
      required TargetPlatform platform,
      required bool hasEglSurface,
      required bool hasSourceTexture,
    }) async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <String>[];
      final angle = _RecordingAngle(calls);
      final gl = _RecordingGl(calls);
      final three = ThreeJS(onSetupComplete: () {}, setup: () {})
        ..angle = angle
        ..gl = gl
        ..screenSize = const Size(320, 200)
        ..postProcessor = ([double? dt]) {};
      final texture = FlutterAngleTexture.fromSurface(
        angle,
        1,
        hasEglSurface ? Pointer<Void>.fromAddress(1) : null,
        const AngleOptions(width: 320, height: 200, dpr: 1),
      );
      if (hasSourceTexture) {
        three.sourceTexture = WebGLTexture(1);
      }
      await three.render(tjs.Scene(), tjs.PerspectiveCamera(), texture);
      return calls;
    }

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('on Windows, whose surface producer is a client-buffer pbuffer',
        () async {
      // flutter_angle makes Windows' surface with
      // eglCreatePbufferFromClientBuffer(EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE):
      // a pbuffer is single-buffered, so eglSwapBuffers does nothing and
      // nothing orders ANGLE's draw against Flutter's read of the D3D11
      // shared texture on its raster thread. Without the wait the
      // compositor reads a frame still being drawn: a flicker.
      expect(
        await present(
          platform: TargetPlatform.windows,
          hasEglSurface: true,
          hasSourceTexture: false,
        ),
        ['activate', 'finish', 'present'],
      );
    });

    test('on macOS, whose surface producer is an IOSurface pbuffer', () async {
      expect(
        await present(
          platform: TargetPlatform.macOS,
          hasEglSurface: true,
          hasSourceTexture: false,
        ),
        ['activate', 'finish', 'present'],
      );
    });

    test('on Linux, which shares one FBO with Flutter', () async {
      expect(
        await present(
          platform: TargetPlatform.linux,
          hasEglSurface: false,
          hasSourceTexture: false,
        ),
        ['activate', 'finish', 'present'],
      );
    });

    test('not on Android, whose window surface really swaps buffers', () async {
      expect(
        await present(
          platform: TargetPlatform.android,
          hasEglSurface: true,
          hasSourceTexture: false,
        ),
        ['activate', 'present'],
      );
    });

    test('not on the source-texture path, which already finished', () async {
      expect(
        await present(
          platform: TargetPlatform.windows,
          hasEglSurface: true,
          hasSourceTexture: true,
        ),
        ['activate', 'present'],
      );
    });
  });
}
