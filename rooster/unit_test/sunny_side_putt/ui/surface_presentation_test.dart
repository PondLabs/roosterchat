// What keeps the 3D view from flickering that can be checked without a
// GPU: the surface is resized only where its Flutter texture survives a
// resize, the camera's depth range leaves the turf's marks room over the
// turf, and on every surface that does not swap buffers Flutter is only
// ever given a whole frame, without the UI thread waiting on the GPU for
// the frame it has just drawn.
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
  int _names = 0;

  @override
  void finish() => calls.add('finish');

  @override
  void flush() => calls.add('flush');

  @override
  void blitFramebuffer(
    int srcX0,
    int srcY0,
    int srcX1,
    int srcY1,
    int dstX0,
    int dstY0,
    int dstX1,
    int dstY1,
    int mask,
    int filter,
  ) =>
      calls.add('blit ${srcX1}x$srcY1');

  @override
  Framebuffer createFramebuffer() => Framebuffer(++_names);

  @override
  Renderbuffer createRenderbuffer() => Renderbuffer(++_names);

  @override
  void bindFramebuffer(int target, Framebuffer? framebuffer) {}

  @override
  void bindRenderbuffer(int target, Renderbuffer? renderbuffer) {}

  @override
  void renderbufferStorage(
    int target,
    int internalformat,
    int width,
    int height,
  ) {}

  @override
  void framebufferRenderbuffer(
    int target,
    int attachment,
    int renderbuffertarget,
    Renderbuffer? renderbuffer,
  ) {}
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

/// A viewer over a recording GL and ANGLE: each [frame] runs one tick of
/// its present path and returns the calls it made, in order.
class _Viewer {
  _Viewer({
    required TargetPlatform platform,
    required bool hasEglSurface,
    bool hasSourceTexture = false,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    three = ThreeJS(onSetupComplete: () {}, setup: () {})
      ..angle = _RecordingAngle(calls)
      ..gl = _RecordingGl(calls)
      ..screenSize = const Size(320, 200)
      ..postProcessor = ([double? dt]) => calls.add('draw');
    texture = FlutterAngleTexture.fromSurface(
      three.angle!,
      1,
      hasEglSurface ? Pointer<Void>.fromAddress(1) : null,
      const AngleOptions(width: 320, height: 200, dpr: 1),
    );
    if (hasSourceTexture) three.sourceTexture = WebGLTexture(1);
  }

  final calls = <String>[];
  late final ThreeJS three;
  late final FlutterAngleTexture texture;

  Future<List<String>> frame() async {
    calls.clear();
    await three.render(tjs.Scene(), tjs.PerspectiveCamera(), texture);
    return List.of(calls);
  }
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

  group('Flutter is given only whole frames, without a wait on this one', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    /// A tick on a single-buffered texture: last tick's frame is copied
    /// over whole and finished (a blit, its draw long done), Flutter is
    /// told, and only then this tick's frame is drawn, into the viewer's
    /// own framebuffer, with a flush and no wait on it.
    const steady = [
      'activate',
      'blit 320x200',
      'finish',
      'present',
      'draw',
      'flush',
    ];

    /// The first frame (and the first after a resize) has nothing older to
    /// show meanwhile, so it alone is waited for.
    const fresh = [
      'activate',
      'draw',
      'flush',
      'blit 320x200',
      'finish',
      'present',
    ];

    /// The tick after a fresh frame: that frame is already shown, so there
    /// is nothing to copy over yet.
    const afterFresh = ['activate', 'draw', 'flush'];

    Future<void> expectDeferred(TargetPlatform platform, bool surface) async {
      final viewer = _Viewer(platform: platform, hasEglSurface: surface);
      expect(await viewer.frame(), fresh, reason: 'first frame');
      expect(await viewer.frame(), afterFresh, reason: 'second frame');
      for (var i = 0; i < 3; i++) {
        expect(await viewer.frame(), steady, reason: 'frame ${i + 3}');
      }
    }

    test('on Windows, whose surface producer is a client-buffer pbuffer',
        () async {
      // flutter_angle makes Windows' surface with
      // eglCreatePbufferFromClientBuffer(EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE):
      // a pbuffer is single-buffered, so eglSwapBuffers does nothing and
      // nothing orders ANGLE's draw against Flutter's read of the D3D11
      // shared texture on its raster thread. Drawn straight into it, the
      // compositor read frames still being drawn (a flicker); waited for
      // with glFinish, the UI thread sat out the GPU's whole frame on every
      // tick (a lower frame rate).
      await expectDeferred(TargetPlatform.windows, true);
    });

    test('on macOS, whose surface producer is an IOSurface pbuffer', () async {
      await expectDeferred(TargetPlatform.macOS, true);
    });

    test('on Linux, which shares one FBO with Flutter', () async {
      await expectDeferred(TargetPlatform.linux, false);
    });

    test('a resize shows its first frame at once, at the new size', () async {
      final viewer =
          _Viewer(platform: TargetPlatform.windows, hasEglSurface: true);
      await viewer.frame();
      await viewer.frame();
      viewer.texture.options =
          const AngleOptions(width: 400, height: 300, dpr: 1);
      // The old frame is not copied into the new surface (it is the wrong
      // size, and its framebuffer was reallocated): the new one is drawn
      // and shown.
      expect(await viewer.frame(), [
        'activate',
        'draw',
        'flush',
        'blit 400x300',
        'finish',
        'present',
      ]);
      expect(await viewer.frame(), afterFresh);
      expect(
        await viewer.frame(),
        [
          'activate',
          'blit 400x300',
          'finish',
          'present',
          'draw',
          'flush',
        ],
      );
    });

    test('not on Android, whose window surface really swaps buffers', () async {
      final viewer =
          _Viewer(platform: TargetPlatform.android, hasEglSurface: true);
      expect(await viewer.frame(), ['activate', 'draw', 'present']);
      expect(await viewer.frame(), ['activate', 'draw', 'present']);
    });

    test('not on the source-texture path, which already finished', () async {
      final viewer = _Viewer(
        platform: TargetPlatform.windows,
        hasEglSurface: true,
        hasSourceTexture: true,
      );
      expect(await viewer.frame(), ['draw', 'activate', 'present']);
    });
  });
}
