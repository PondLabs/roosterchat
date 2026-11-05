// The aim and the bursts. The aim lies on the turf: the slingshot's pull
// behind the egg, a power ring filling around it, the arrow ahead whose
// length and colour say how hard (green, yolk, comb red), and the dotted
// guide - the first stretch of the roll the engine's own physics predicts.
// The bursts are pooled sprites over a soft disc (splashes, sparkles,
// suction, poofs, dust, confetti) and a few expanding rings.
part of '../putt_world3d.dart';

/// The power's colour, bright all the way: a pale yolk for a tap,
/// sunflower, orange, red flat out (no muddy olive between).
int _powerHex(double power) {
  const stops = [
    // A pale yolk, not green or cream, at the soft end: it has to stand
    // off light and dark turf alike (with the ink outline round it).
    (0.0, 0xFFE07A),
    (0.42, 0xFFCC2E),
    (0.72, 0xFF8A2A),
    (1.0, 0xFF3D30),
  ];
  final p = power.clamp(0.0, 1.0);
  for (var i = 1; i < stops.length; i++) {
    final (at, hex) = stops[i];
    final (from, fromHex) = stops[i - 1];
    if (p <= at) return _mix(fromHex, hex, (p - from) / (at - from));
  }
  return stops.last.$2;
}

class _PuttAimView3D {
  _PuttAimView3D({required double eggRadius}) : _eggRadius = eggRadius {
    group = tjs.Group()
      ..name = 'aim'
      ..visible = false;
    _turned = tjs.Group()..name = 'aim-turned';
    group.add(_turned);

    ring = tjs.Mesh(
      tjg.RingGeometry(eggRadius * 2.0, eggRadius * 2.3, 48, 1),
      _unlit(_hexOf(PuttPalette.ink), opacity: 0.28, depthWrite: false),
    )
      ..name = 'aim-ring'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.035
      ..renderOrder = 4;
    group.add(ring);

    // The aim draws over the other eggs (no depth test, after them): an
    // egg in the way never hides where the putt goes. The viewer's own egg
    // draws after it, so the arrow comes out from under the egg.
    _arrowMaterial = _unlit(_powerHex(0.5),
        opacity: 0.95, depthWrite: false, depthTest: false);
    // A solid ink line round the arrow: it reads on light and dark turf.
    _outlineMaterial = _unlit(_hexOf(PuttPalette.ink),
        opacity: 0.9, depthWrite: false, depthTest: false);
    shaft = tjs.Mesh(tjs.BoxGeometry(1, 0.02, 0.46), _arrowMaterial)
      ..name = 'aim-shaft'
      ..position.y = 0.08
      ..renderOrder = 6;
    _shaftOutline = tjs.Mesh(tjs.BoxGeometry(1, 0.015, 0.74), _outlineMaterial)
      ..name = 'aim-shaft-outline'
      ..position.y = 0.07
      ..renderOrder = 5;
    // A white core down the shaft: the arrow reads on any turf.
    _core = tjs.Mesh(
      tjs.BoxGeometry(1, 0.02, 0.12),
      _unlit(0xFFFFFF, opacity: 0.85, depthWrite: false, depthTest: false),
    )
      ..name = 'aim-core'
      ..position.y = 0.09
      ..renderOrder = 7;
    head = tjs.Mesh(_triangle(1.15, 1.25), _arrowMaterial)
      ..name = 'aim-head'
      ..position.y = 0.082
      ..renderOrder = 6;
    _headOutline = tjs.Mesh(_triangle(1.6, 1.75), _outlineMaterial)
      ..name = 'aim-head-outline'
      ..position.y = 0.072
      ..renderOrder = 5;
    _turned
      ..add(_shaftOutline)
      ..add(_headOutline)
      ..add(shaft)
      ..add(_core)
      ..add(head);

    // Where the guide meets its first rail: a small ring on the turf.
    _bounceMark = tjs.Group()
      ..name = 'aim-bounce'
      ..visible = false;
    _bounceMark
      ..add(tjs.Mesh(
        tjg.RingGeometry(0.22, 0.38, 24, 1),
        _unlit(0xFFF8EE, opacity: 0.95, depthWrite: false, depthTest: false),
      )
        ..rotation.x = -math.pi / 2
        ..position.y = 0.06
        ..renderOrder = 7)
      ..add(tjs.Mesh(
        tjg.RingGeometry(0.16, 0.46, 24, 1),
        _unlit(_hexOf(PuttPalette.ink),
            opacity: 0.4, depthWrite: false, depthTest: false),
      )
        ..rotation.x = -math.pi / 2
        ..position.y = 0.055
        ..renderOrder = 6);
    group.add(_bounceMark);

    // Where a soft putt stops: an egg's footprint, drawn over the arrow.
    _restMark = tjs.Group()
      ..name = 'aim-rest'
      ..visible = false;
    _restMark
      ..add(tjs.Mesh(
        tjg.CircleGeometry(radius: eggRadius * 1.25, segments: 28),
        _unlit(_hexOf(PuttPalette.ink),
            opacity: 0.16, depthWrite: false, depthTest: false),
      )
        ..rotation.x = -math.pi / 2
        ..position.y = 0.05
        ..renderOrder = 8)
      ..add(tjs.Mesh(
        tjg.RingGeometry(eggRadius * 1.08, eggRadius * 1.62, 32, 1),
        _unlit(_hexOf(PuttPalette.ink),
            opacity: 0.5, depthWrite: false, depthTest: false),
      )
        ..rotation.x = -math.pi / 2
        ..position.y = 0.055
        ..renderOrder = 8)
      ..add(tjs.Mesh(
        tjg.RingGeometry(eggRadius * 1.2, eggRadius * 1.48, 32, 1),
        _unlit(0xFFF8EE, opacity: 0.95, depthWrite: false, depthTest: false),
      )
        ..rotation.x = -math.pi / 2
        ..position.y = 0.06
        ..renderOrder = 9);
    group.add(_restMark);

    for (var i = 0; i < _dotCount; i++) {
      // Each dot: cream over a soft ink ring, so it reads on light and dark
      // turf stripes alike.
      final dot = tjs.Group()
        ..name = 'aim-dot'
        ..visible = false;
      dot
        ..add(tjs.Mesh(
          _dotRingGeometry,
          _unlit(_hexOf(PuttPalette.ink),
              opacity: 0.45, depthWrite: false, depthTest: false),
        )
          ..name = 'aim-dot-ring'
          ..rotation.x = -math.pi / 2
          ..renderOrder = 5)
        ..add(tjs.Mesh(
          _dotGeometry,
          _unlit(0xFFF8EE, opacity: 0.95, depthWrite: false, depthTest: false),
        )
          ..name = 'aim-dot-fill'
          ..rotation.x = -math.pi / 2
          ..position.y = 0.004
          ..renderOrder = 6);
      _dots.add(dot);
      group.add(dot);
    }
    for (var i = 0; i < _traceCount; i++) {
      final dot = tjs.Mesh(_traceGeometry, _traceMaterial)
        ..name = 'aim-trace'
        ..rotation.x = -math.pi / 2
        ..renderOrder = 3
        ..visible = false;
      _traceDots.add(dot);
      group.add(dot);
    }
  }

  static const int _dotCount = 44;

  /// The last roll's trace: small dots in the viewer's colour, a shared
  /// material, under the guide.
  static const int _traceCount = 90;
  static final tjs.BufferGeometry _traceGeometry =
      tjg.CircleGeometry(radius: 0.09, segments: 10);
  final tjs.MeshBasicMaterial _traceMaterial =
      _unlit(0xFFF8EE, opacity: 0.5, depthWrite: false);
  final List<tjs.Mesh> _traceDots = [];
  int _traceHex = -1;

  static final tjs.BufferGeometry _dotGeometry =
      tjg.CircleGeometry(radius: 0.15, segments: 12);
  static final tjs.BufferGeometry _dotRingGeometry =
      tjg.CircleGeometry(radius: 0.25, segments: 12);

  late final tjs.Group group;
  late final tjs.Group _turned;
  late final tjs.Mesh ring;
  late final tjs.Mesh shaft;
  late final tjs.Mesh head;
  late final tjs.Mesh _shaftOutline;
  late final tjs.Mesh _headOutline;

  late final tjs.Mesh _core;
  late final tjs.Group _bounceMark;
  late final tjs.Group _restMark;
  late final tjs.MeshBasicMaterial _arrowMaterial;
  late final tjs.MeshBasicMaterial _outlineMaterial;
  final List<tjs.Group> _dots = [];

  tjs.Mesh? _fill;
  double _fillPower = -1;
  final double _eggRadius;

  /// The viewer's last roll on this hole, faint dots in their colour
  /// along each stretch (spaced wider on a long roll, so the pool covers
  /// all of it).
  void _syncTrace(PuttWorldAim aim, _Ground terrain, double floor) {
    var shown = 0;
    final trace = aim.trace;
    if (trace.isNotEmpty) {
      final tint = aim.traceTint;
      final hex = tint == null ? 0xFFF8EE : _mix(_hexOf(tint), 0xFFFFFF, 0.2);
      if (hex != _traceHex) {
        _traceHex = hex;
        _traceMaterial.color = _lin(hex);
      }
      var total = 0.0;
      for (final stretch in trace) {
        total += _pathLength(stretch);
      }
      final spacing = math.max(0.42, total / _traceCount);
      for (final stretch in trace) {
        var carried = 0.0;
        for (var i = 1; i < stretch.length && shown < _traceCount; i++) {
          final a = stretch[i - 1];
          final b = stretch[i];
          final segment = a.distanceTo(b);
          if (segment <= 1e-6) continue;
          var t = carried;
          while (t <= segment && shown < _traceCount) {
            final p = a + (b - a) * (t / segment);
            t += spacing;
            _traceDots[shown++]
              ..visible = true
              ..position.setValues(p.x - aim.origin.x,
                  terrain.at(p) - floor + 0.03, p.y - aim.origin.y);
          }
          carried = t - segment;
        }
      }
    }
    for (var i = shown; i < _traceDots.length; i++) {
      _traceDots[i].visible = false;
    }
  }

  /// A flat triangle pointing +x, [length] long and [width] wide, its base
  /// at x = 0.
  static tjs.BufferGeometry _triangle(double length, double width) {
    // Wound counter-clockwise seen from above, so the face looks up.
    final positions = <double>[
      0, 0, width / 2, //
      length, 0, 0,
      0, 0, -width / 2,
    ];
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
      ..setAttributeFromString(
          'normal',
          tjs.Float32BufferAttribute.fromList(
              [0, 1, 0, 0, 1, 0, 0, 1, 0], 3, false));
  }

  /// Shows the aim for this frame, or hides the group. The fill arc's
  /// geometry rebuilds only when the power moved enough to see.
  void sync(PuttWorldAim? aim, double time, [_Ground? ground]) {
    if (aim == null) {
      group.visible = false;
      return;
    }
    group.visible = true;
    final terrain = ground ?? _Ground();
    final floor = terrain.at(aim.origin);
    group.position.setValues(aim.origin.x, floor + 0.01, aim.origin.y);
    // The game's y-down angle reads a negative world turn about y; on a
    // slope the arrow also pitches with the ground along the shot.
    final slope = terrain.slopeAt(aim.origin);
    final along = slope.x * math.cos(aim.angle) + slope.y * math.sin(aim.angle);
    if (along.abs() < 1e-6) {
      _turned.rotation.set(0, -aim.angle, 0);
    } else {
      _turned.quaternion.setFrom(tjs.Quaternion()
          .setFromAxisAngle(tjs.Vector3(0, 1, 0), -aim.angle)
          .multiply(tjs.Quaternion()
              .setFromAxisAngle(tjs.Vector3(0, 0, 1), math.atan(along))));
    }

    final scale = aim.eggRadius / _eggRadius;
    var length = (1.4 + aim.power * 5.2) * scale;
    final start = aim.eggRadius * 2.35;
    // A soft putt's arrow ends where the egg stops, not past it, and the
    // spot is marked over it.
    final rest = aim.rest;
    _restMark.visible = rest != null;
    if (rest != null) {
      length = math.min(
          length, math.max(0.3, _pathLength(aim.preview) - start - 1.15));
      final breathe = 1 + 0.06 * math.sin(time * 4.2);
      _restMark
        ..position.setValues(rest.x - aim.origin.x, terrain.at(rest) - floor,
            rest.y - aim.origin.y)
        ..scale.setValues(scale * breathe, 1, scale * breathe);
    }
    shaft.scale.x = length;
    shaft.position.x = start + length / 2;
    _core.scale.x = math.max(length - 0.3, 0.05);
    _core.position.x = start + length / 2 - 0.1;
    _shaftOutline.scale.x = length + 0.14;
    _shaftOutline.position.x = start + length / 2 - 0.05;
    head.position.x = start + length;
    _headOutline.position.x = start + length - 0.16;
    _arrowMaterial.color = _lin(_powerHex(aim.power));
    // The guide takes over where the arrow's head ends.
    final tip = start + length + 1.15;

    if ((aim.power - _fillPower).abs() > 0.015) {
      _fillPower = aim.power;
      final oldFill = _fill;
      if (oldFill != null) {
        group.remove(oldFill);
        oldFill.geometry?.dispose();
        oldFill.material?.dispose();
      }
      final sweep = math.max(aim.power * 2 * math.pi, 0.05);
      final fill = tjs.Mesh(
        tjg.RingGeometry(
            aim.eggRadius * 1.98,
            aim.eggRadius * 2.32,
            (48 * math.max(aim.power, 0.05)).ceil().clamp(3, 48).toInt(),
            1,
            math.pi / 2,
            sweep),
        _unlit(_powerHex(aim.power), opacity: 0.95, depthWrite: false),
      )
        ..name = 'aim-fill'
        ..rotation.x = -math.pi / 2
        ..position.y = 0.04
        ..renderOrder = 5;
      group.add(fill);
      _fill = fill;
    }

    _syncTrace(aim, terrain, floor);

    // The dotted guide along the predicted roll, from the arrow's tip on,
    // fading toward its end; a ring where it first meets a rail.
    final points = aim.preview;
    var shown = 0;
    _bounceMark.visible = false;
    final bounce = _firstBounce(points);
    if (bounce != null) {
      _bounceMark
        ..visible = true
        ..position.setValues(bounce.x - aim.origin.x,
            terrain.at(bounce) - floor, bounce.y - aim.origin.y);
    }
    if (points.length >= 2) {
      const spacing = 0.62;
      var carried = spacing * 0.6;
      // The dots trail off over the guide's own length: its end reads as
      // the guide giving out, not as a wall (a soft putt's end has its
      // resting mark instead).
      final expected = math.max(1.0, (_pathLength(points) - tip) / spacing);
      for (var i = 1; i < points.length && shown < _dotCount; i++) {
        final a = points[i - 1];
        final b = points[i];
        final segment = a.distanceTo(b);
        if (segment <= 1e-6) continue;
        var t = carried;
        while (t <= segment && shown < _dotCount) {
          final p = a + (b - a) * (t / segment);
          t += spacing;
          // Under the arrow the guide would only clutter it.
          if (p.distanceTo(aim.origin) < tip) continue;
          final dot = _dots[shown];
          dot.visible = true;
          dot.position.setValues(p.x - aim.origin.x,
              terrain.at(p) - floor + 0.05, p.y - aim.origin.y);
          final left =
              math.pow((1 - shown / expected).clamp(0.0, 1.0), 0.7).toDouble();
          final fade = rest != null ? math.max(left, 0.6) : left;
          dot.children[0].material?.opacity = 0.12 + 0.73 * fade;
          dot.children[1].material?.opacity = 0.18 + 0.82 * fade;
          final s = 0.75 + 0.55 * fade;
          dot.scale.setValues(s, 1, s);
          shown++;
        }
        carried = t - segment;
      }
    }
    for (var i = shown; i < _dots.length; i++) {
      _dots[i].visible = false;
    }
  }

  /// How far the guide runs along its points.
  static double _pathLength(List<Vec2> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += points[i - 1].distanceTo(points[i]);
    }
    return length;
  }

  /// The guide's first sharp turn (a rail's bounce), if it has one.
  static Vec2? _firstBounce(List<Vec2> points) {
    for (var i = 1; i + 1 < points.length; i++) {
      final a = points[i] - points[i - 1];
      final b = points[i + 1] - points[i];
      if (a.length < 1e-6 || b.length < 1e-6) continue;
      if (a.dot(b) / (a.length * b.length) < 0.96) return points[i];
    }
    return null;
  }

  /// Frees the fill's geometry (the shared material belongs to the world).
  void dispose() {
    _fill?.geometry?.dispose();
    _fill?.material?.dispose();
    group.dispose();
  }
}

// ---- fx -------------------------------------------------------------------------------------

/// The pools' group: it keeps only its shown children's world matrices up
/// to date. The pools hold some 550 sprites, nearly all hidden, and the
/// scene's matrix pass walked every one of them every frame. A child
/// shown again gets its matrix on the next pass (the face-camera pass
/// marks it, and the scene's pass forces every shown one).
class _ShownChildrenGroup extends tjs.Group {
  @override
  void updateMatrixWorld([bool force = false]) {
    if (matrixAutoUpdate) updateMatrix();
    if (matrixWorldNeedsUpdate || force) {
      final parent = this.parent;
      if (parent == null) {
        matrixWorld.setFrom(matrix);
      } else {
        matrixWorld.multiply2(parent.matrixWorld, matrix);
      }
      matrixWorldNeedsUpdate = false;
      force = true;
    }
    for (final child in children) {
      if (child.visible) child.updateMatrixWorld(force);
    }
  }
}

/// The bursts as pooled sprites over a soft disc, tinted and faded per
/// frame, plus a few rings for the nest's shockwave and the casts.
class _PuttFxPool {
  /// Soft sprites (over the disc), paper ones (confetti, shards, feathers:
  /// hard-edged), water drops (a crisp disc), corn kernels and wind streaks
  /// (their own drawings): five pools, so no sprite ever has its texture
  /// swapped while in play.
  static const int poolSize = 150;
  static const int paperSize = 110;
  static const int dropSize = 96;
  static const int kernelSize = 120;
  static const int streakSize = 70;
  static const int ringCount = 8;

  final List<_Billboard> _sprites = [];
  final List<_Billboard> _paper = [];
  final List<_Billboard> _drops = [];
  final List<_Billboard> _kernels = [];
  final List<_Billboard> _streaks = [];
  final List<tjs.Mesh> _rings = [];
  tjs.DataTexture? _disc;
  tjs.DataTexture? _drop;
  tjs.DataTexture? _kernel;
  tjs.DataTexture? _streak;

  /// The pool's soft disc (world-owned): the world's dispose kills it via
  /// its owned list; a fresh pool stamps a new disc.
  tjs.DataTexture get texture => _disc ??= _discTexture(size: 32, hardness: 2);

  /// The water drops' disc: solid to a crisp edge, so a splash reads as
  /// drops from the overview too (world-owned like [texture]).
  tjs.DataTexture get dropTexture => _drop ??= _crispDiscTexture(size: 32);

  /// The corn kernel's drawing and the wind's line, world-owned like the
  /// disc.
  tjs.DataTexture get kernelTexture => _kernel ??= _kernelTexture();
  tjs.DataTexture get streakTexture => _streak ??= _streakTexture();

  void reset(tjs.Group parent) {
    for (final sprite in [
      ..._sprites,
      ..._paper,
      ..._drops,
      ..._kernels,
      ..._streaks,
    ]) {
      parent.remove(sprite);
      sprite.material?.map = null;
      sprite.material?.dispose();
      sprite.dispose();
    }
    _sprites.clear();
    _paper.clear();
    _drops.clear();
    final dropTexture = this.dropTexture;
    for (var i = 0; i < dropSize; i++) {
      final sprite = _Billboard(map: dropTexture)
        ..name = 'fx-drop'
        // Placed only while shown: the face-camera pass updates its matrix.
        ..matrixAutoUpdate = false
        ..visible = false
        ..renderOrder = 8;
      parent.add(sprite);
      _drops.add(sprite);
    }
    _kernels.clear();
    _streaks.clear();
    final streak = streakTexture;
    for (var i = 0; i < streakSize; i++) {
      final sprite = _Billboard(map: streak)
        ..name = 'fx-streak'
        // Placed only while shown: the face-camera pass updates its matrix.
        ..matrixAutoUpdate = false
        ..visible = false
        ..renderOrder = 8;
      parent.add(sprite);
      _streaks.add(sprite);
    }
    for (var i = 0; i < paperSize; i++) {
      final sprite = _Billboard(map: _paperTexture)
        ..name = 'fx-paper'
        // Placed only while shown: the face-camera pass updates its matrix.
        ..matrixAutoUpdate = false
        ..visible = false
        ..renderOrder = 8;
      parent.add(sprite);
      _paper.add(sprite);
    }
    final kernel = kernelTexture;
    for (var i = 0; i < kernelSize; i++) {
      final sprite = _Billboard(map: kernel)
        ..name = 'fx-kernel'
        // Placed only while shown: the face-camera pass updates its matrix.
        ..matrixAutoUpdate = false
        ..visible = false
        ..renderOrder = 8;
      parent.add(sprite);
      _kernels.add(sprite);
    }
    for (final ring in [..._rings]) {
      parent.remove(ring);
      ring.dispose();
    }
    _rings.clear();
    final discTexture = texture;
    for (var i = 0; i < poolSize; i++) {
      final sprite = _Billboard(map: discTexture)
        ..name = 'fx'
        // Placed only while shown: the face-camera pass updates its matrix.
        ..matrixAutoUpdate = false
        ..visible = false
        ..renderOrder = 8;
      parent.add(sprite);
      _sprites.add(sprite);
    }
    for (var i = 0; i < ringCount; i++) {
      final ring = tjs.Mesh(
        tjg.RingGeometry(0.86, 1.0, 40, 1),
        _unlit(0xFFFFFF, opacity: 0, depthWrite: false),
      )
        ..name = 'fx-ring'
        ..rotation.x = -math.pi / 2
        ..visible = false
        ..renderOrder = 7;
      parent.add(ring);
      _rings.add(ring);
    }
  }

  /// Places this frame's fx onto the pooled sprites; the rest hide. The
  /// [camera] (last frame's) turns the wind's streaks along their run on
  /// screen.
  void apply(PuttWorldFrame frame,
      {double scale = 1, _Ground? ground, tjs.PerspectiveCamera? camera}) {
    var active = 0;
    var paper = 0;
    var drops = 0;
    var kernels = 0;
    var streaks = 0;
    var rings = 0;
    for (final fx in frame.fxs) {
      final progress = fx.progress.clamp(0.0, 1.0);
      final color = fx.color ?? PuttPalette.yolk;
      if (fx.kind == PuttWorldFxKind.ring) {
        if (rings >= _rings.length) continue;
        final ring = _rings[rings++];
        ring.visible = true;
        var radius = fx.size * (0.3 + progress * 1.4) * math.sqrt(scale);
        final reach = fx.reach;
        if (reach != null) radius = math.min(radius, reach);
        ring.scale.setValues(radius, radius, 1);
        ring.position
            .setValues(fx.at.x, (ground?.at(fx.at) ?? 0) + 0.08, fx.at.y);
        ring.material?.color = _linOf(color);
        ring.material?.opacity = (1 - progress) * 0.85;
        continue;
      }
      final _Billboard sprite;
      if (fx.kind == PuttWorldFxKind.confetti ||
          fx.kind == PuttWorldFxKind.shard ||
          fx.kind == PuttWorldFxKind.feather) {
        if (paper >= _paper.length) continue;
        sprite = _paper[paper++];
      } else if (fx.kind == PuttWorldFxKind.droplet) {
        if (drops >= _drops.length) continue;
        sprite = _drops[drops++];
      } else if (fx.kind == PuttWorldFxKind.kernel) {
        if (kernels >= _kernels.length) continue;
        sprite = _kernels[kernels++];
      } else if (fx.kind == PuttWorldFxKind.streak) {
        if (streaks >= _streaks.length) continue;
        sprite = _streaks[streaks++];
      } else {
        if (active >= _sprites.length) continue;
        sprite = _sprites[active++];
      }
      sprite.visible = true;

      Vec2 at = fx.at;
      double lift;
      double width;
      double height;
      var opacity = (1 - progress) * 0.85;
      double rotation = 0;
      switch (fx.kind) {
        case PuttWorldFxKind.droplet:
          lift = 1.7 * math.sin(progress * math.pi);
          width = height = fx.size * (0.75 + 0.35 * progress);
          // Whole drops until late in their flight, then gone quickly.
          opacity = progress < 0.6 ? 1 : (1 - progress) / 0.4;
        case PuttWorldFxKind.sparkle:
          lift = 0.45 + 0.6 * math.sin(progress * math.pi);
          width = height =
              fx.size * (0.5 + 1.2 * math.sin(progress * math.pi).abs());
          opacity = (1 - progress) * 0.95;
        case PuttWorldFxKind.suction:
          final toward = fx.toward ?? fx.at;
          at = fx.at + (toward - fx.at) * (progress * progress);
          lift = 0.15;
          width = height = math.max(fx.size * (1 - progress), 0.02);
        case PuttWorldFxKind.poof:
          lift = 0.15 + progress * 0.3;
          width = height = math.max(fx.size * (1 + progress * 1.2), 0.02);
          opacity = (1 - progress) * 0.7;
        case PuttWorldFxKind.dust:
          lift = 0.12 + progress * 0.35;
          width = height = math.max(fx.size * (0.6 + progress * 1.4), 0.02);
          opacity = (1 - progress) * 0.5;
        case PuttWorldFxKind.confetti:
          lift = fx.height ?? 1.0;
          // A paper square flipping: one axis breathes as it tumbles.
          final flip = math.sin(progress * 22 + fx.at.x * 3).abs();
          width = fx.size;
          height = fx.size * (0.25 + 0.75 * flip);
          rotation = progress * 9 + fx.at.y;
          opacity = progress < 0.75 ? 1 : (1 - progress) * 4;
        case PuttWorldFxKind.ring:
          lift = 0; // handled above
          width = height = 0;
        case PuttWorldFxKind.kernel:
          // A kernel tumbling down and bouncing (its height rides in).
          lift = fx.height ?? 0.1;
          width = fx.size * 0.85;
          height = fx.size;
          rotation = progress * 11 + fx.at.x * 3;
          opacity = progress < 0.8 ? 1 : (1 - progress) * 5;
        case PuttWorldFxKind.streak:
          // The wind: a long thin wisp, swelling in and thinning out,
          // turned along its run on screen.
          lift = fx.height ?? 0.55;
          final swell = math.sin(progress * math.pi);
          width = fx.size * (3.2 + 2.4 * swell);
          height = fx.size * (0.18 + 0.08 * swell);
          opacity = math.min(1.0, swell * 1.4) * 0.8;
          final toward = fx.toward;
          if (camera != null && toward != null) {
            final y = (ground?.at(at) ?? 0) + lift;
            final a = tjs.Vector3(at.x, y, at.y).project(camera);
            final b = tjs.Vector3(toward.x, y, toward.y).project(camera);
            rotation = math.atan2(b.y - a.y, (b.x - a.x) * camera.aspect);
          }
        case PuttWorldFxKind.steam:
          lift = (fx.height ?? 0.6) + progress * 1.2;
          width = height = math.max(fx.size * (0.55 + progress * 1.5), 0.02);
          opacity = math.sin(progress * math.pi) * 0.6;
        case PuttWorldFxKind.swirl:
          lift = fx.height ?? (0.25 + progress * 1.3);
          width = height = math.max(fx.size * (1 - 0.55 * progress), 0.02);
          opacity = (1 - progress) * 0.95;
        case PuttWorldFxKind.shard:
          // A bit of popped shell, glinting as it turns.
          lift = fx.height ?? 0.3;
          final turn = math.sin(progress * 19 + fx.at.y * 5).abs();
          width = fx.size;
          height = fx.size * (0.3 + 0.7 * turn);
          rotation = progress * 13 + fx.at.x;
          opacity = progress < 0.7 ? 0.95 : (1 - progress) / 0.3 * 0.95;
        case PuttWorldFxKind.feather:
          // A feather rocking as it drifts down.
          lift = fx.height ?? 0.6;
          width = fx.size * 0.42;
          height = fx.size;
          rotation = math.sin(progress * 8 + fx.at.x * 2) * 0.9;
          opacity = progress < 0.75 ? 1 : (1 - progress) * 4;
        case PuttWorldFxKind.glint:
          lift = fx.height ?? 0.22;
          final pulse = math.sin(progress * math.pi);
          width = height = math.max(fx.size * (0.5 + 0.9 * pulse), 0.02);
          opacity = pulse;
      }
      if (fx.height != null &&
          fx.kind != PuttWorldFxKind.confetti &&
          fx.kind != PuttWorldFxKind.steam &&
          fx.kind != PuttWorldFxKind.streak) {
        lift = fx.height!;
      }
      sprite.position.setValues(at.x, (ground?.at(at) ?? 0) + lift, at.y);
      // What must read from the play camera's distance grows with it.
      final grow = switch (fx.kind) {
        PuttWorldFxKind.suction ||
        PuttWorldFxKind.dust ||
        PuttWorldFxKind.ring =>
          1.0,
        _ => scale,
      };
      sprite.scale.setValues(width * grow, height * grow, 1);
      sprite.look
        ..color = _linOf(color)
        ..opacity = opacity.clamp(0.0, 1.0);
      sprite.roll = rotation;
    }
    for (var i = active; i < _sprites.length; i++) {
      _sprites[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = paper; i < _paper.length; i++) {
      _paper[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = drops; i < _drops.length; i++) {
      _drops[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = kernels; i < _kernels.length; i++) {
      _kernels[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = streaks; i < _streaks.length; i++) {
      _streaks[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = rings; i < _rings.length; i++) {
      _rings[i].visible = false;
    }
  }
}
