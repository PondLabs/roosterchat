// The aim and the bursts. The aim lies on the turf: the slingshot's pull
// behind the egg, a power ring filling around it, the arrow ahead whose
// length and colour say how hard (green, yolk, comb red), and the dotted
// guide - the first stretch of the roll the engine's own physics predicts.
// The bursts are pooled sprites over a soft disc (splashes, sparkles,
// suction, poofs, dust, confetti) and a few expanding rings.
part of '../putt_world3d.dart';

/// The power's colour: green for a tap, yolk midway, comb red flat out.
int _powerHex(double power) {
  const soft = 0x7BD35A;
  final mid = _hexOf(PuttPalette.yolk);
  final hard = _hexOf(PuttPalette.comb);
  final p = power.clamp(0.0, 1.0);
  return p < 0.55
      ? _mix(soft, mid, p / 0.55)
      : _mix(mid, hard, (p - 0.55) / 0.45);
}

class _PuttAimView3D {
  _PuttAimView3D({required double eggRadius}) : _eggRadius = eggRadius {
    group = tjs.Group()
      ..name = 'aim'
      ..visible = false;
    _turned = tjs.Group()..name = 'aim-turned';
    group.add(_turned);

    ghost = tjs.Mesh(
      tjs.BoxGeometry(1, 0.012, 0.08),
      _unlit(_Farm.trim, opacity: 0.55, depthWrite: false),
    )
      ..name = 'aim-ghost'
      ..position.y = 0.04
      ..renderOrder = 4;
    _turned.add(ghost);

    ring = tjs.Mesh(
      tjg.RingGeometry(eggRadius * 2.0, eggRadius * 2.3, 48, 1),
      _unlit(_hexOf(PuttPalette.ink), opacity: 0.28, depthWrite: false),
    )
      ..name = 'aim-ring'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.035
      ..renderOrder = 4;
    group.add(ring);

    _arrowMaterial = _unlit(_powerHex(0.5), opacity: 0.95, depthWrite: false);
    _outlineMaterial =
        _unlit(_hexOf(PuttPalette.ink), opacity: 0.55, depthWrite: false);
    shaft = tjs.Mesh(tjs.BoxGeometry(1, 0.02, 0.34), _arrowMaterial)
      ..name = 'aim-shaft'
      ..position.y = 0.06
      ..renderOrder = 6;
    _shaftOutline = tjs.Mesh(tjs.BoxGeometry(1, 0.015, 0.5), _outlineMaterial)
      ..name = 'aim-shaft-outline'
      ..position.y = 0.05
      ..renderOrder = 5;
    head = tjs.Mesh(_triangle(0.95, 1.0), _arrowMaterial)
      ..name = 'aim-head'
      ..position.y = 0.062
      ..renderOrder = 6;
    _headOutline = tjs.Mesh(_triangle(1.25, 1.3), _outlineMaterial)
      ..name = 'aim-head-outline'
      ..position.y = 0.052
      ..renderOrder = 5;
    _turned
      ..add(_shaftOutline)
      ..add(_headOutline)
      ..add(shaft)
      ..add(head);

    for (var i = 0; i < _dotCount; i++) {
      // Each dot: cream over a soft ink ring, so it reads on light and dark
      // turf stripes alike.
      final dot = tjs.Group()
        ..name = 'aim-dot'
        ..visible = false;
      dot
        ..add(tjs.Mesh(
          _dotRingGeometry,
          _unlit(_hexOf(PuttPalette.ink), opacity: 0.45, depthWrite: false),
        )
          ..name = 'aim-dot-ring'
          ..rotation.x = -math.pi / 2
          ..renderOrder = 5)
        ..add(tjs.Mesh(
          _dotGeometry,
          _unlit(0xFFF8EE, opacity: 0.95, depthWrite: false),
        )
          ..name = 'aim-dot-fill'
          ..rotation.x = -math.pi / 2
          ..position.y = 0.004
          ..renderOrder = 6);
      _dots.add(dot);
      group.add(dot);
    }
  }

  static const int _dotCount = 44;
  static final tjs.BufferGeometry _dotGeometry =
      tjg.CircleGeometry(radius: 0.12, segments: 12);
  static final tjs.BufferGeometry _dotRingGeometry =
      tjg.CircleGeometry(radius: 0.18, segments: 12);

  late final tjs.Group group;
  late final tjs.Group _turned;
  late final tjs.Mesh ghost;
  late final tjs.Mesh ring;
  late final tjs.Mesh shaft;
  late final tjs.Mesh head;
  late final tjs.Mesh _shaftOutline;
  late final tjs.Mesh _headOutline;
  late final tjs.MeshBasicMaterial _arrowMaterial;
  late final tjs.MeshBasicMaterial _outlineMaterial;
  final List<tjs.Group> _dots = [];

  tjs.Mesh? _fill;
  double _fillPower = -1;
  final double _eggRadius;

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
  void sync(PuttWorldAim? aim, double time) {
    if (aim == null) {
      group.visible = false;
      return;
    }
    group.visible = true;
    group.position.setValues(aim.origin.x, 0.01, aim.origin.y);
    // The game's y-down angle reads a negative world turn about y.
    _turned.rotation.y = -aim.angle;

    final scale = aim.eggRadius / _eggRadius;
    final length = (1.4 + aim.power * 5.2) * scale;
    final start = aim.eggRadius * 2.35;
    shaft.scale.x = length;
    shaft.position.x = start + length / 2;
    _shaftOutline.scale.x = length + 0.14;
    _shaftOutline.position.x = start + length / 2 - 0.05;
    head.position.x = start + length;
    _headOutline.position.x = start + length - 0.12;
    _arrowMaterial.color = _lin(_powerHex(aim.power));

    final pull = math.min(aim.dragLength, 7.0) * scale;
    ghost.scale.x = math.max(pull, 0.001);
    ghost.position.x = -pull / 2;

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

    // The dotted guide along the predicted roll, fading toward its end.
    final points = aim.preview;
    var shown = 0;
    if (points.length >= 2) {
      const spacing = 0.62;
      var carried = spacing * 0.6;
      for (var i = 1; i < points.length && shown < _dotCount; i++) {
        final a = points[i - 1];
        final b = points[i];
        final segment = a.distanceTo(b);
        if (segment <= 1e-6) continue;
        var t = carried;
        while (t <= segment && shown < _dotCount) {
          final p = a + (b - a) * (t / segment);
          final dot = _dots[shown];
          dot.visible = true;
          dot.position.setValues(p.x - aim.origin.x, 0.05, p.y - aim.origin.y);
          final fade = 1 - shown / _dotCount;
          dot.children[0].material?.opacity = 0.12 + 0.33 * fade;
          dot.children[1].material?.opacity = 0.25 + 0.7 * fade;
          final s = 0.75 + 0.35 * fade;
          dot.scale.setValues(s, 1, s);
          shown++;
          t += spacing;
        }
        carried = t - segment;
      }
    }
    for (var i = shown; i < _dots.length; i++) {
      _dots[i].visible = false;
    }
  }

  /// Frees the fill's geometry (the shared material belongs to the world).
  void dispose() {
    _fill?.geometry?.dispose();
    _fill?.material?.dispose();
    group.dispose();
  }
}

// ---- fx -------------------------------------------------------------------------------------

/// The bursts as pooled sprites over a soft disc, tinted and faded per
/// frame, plus a few rings for the nest's shockwave.
class _PuttFxPool {
  static const int poolSize = 120;
  static const int ringCount = 4;

  final List<tjs.Sprite> _sprites = [];
  final List<tjs.Mesh> _rings = [];
  tjs.DataTexture? _disc;

  /// The pool's one texture (world-owned): the world's dispose kills it
  /// via its owned list; a fresh pool stamps a new disc.
  tjs.DataTexture get texture => _disc ??= _discTexture(size: 32, hardness: 2);

  void reset(tjs.Group parent) {
    for (final sprite in [..._sprites]) {
      parent.remove(sprite);
      sprite.material?.map = null;
      sprite.material?.dispose();
      sprite.dispose();
    }
    _sprites.clear();
    for (final ring in [..._rings]) {
      parent.remove(ring);
      ring.dispose();
    }
    _rings.clear();
    final discTexture = texture;
    for (var i = 0; i < poolSize; i++) {
      final sprite = tjs.Sprite(
        tjs.SpriteMaterial({
          tjs.MaterialProperty.map: discTexture,
          tjs.MaterialProperty.color: 0xFFFFFF,
          tjs.MaterialProperty.transparent: true,
          tjs.MaterialProperty.opacity: 0.0,
          tjs.MaterialProperty.depthWrite: false,
        }),
      )
        ..name = 'fx'
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

  /// Places this frame's fx onto the pooled sprites; the rest hide.
  void apply(PuttWorldFrame frame) {
    var active = 0;
    var rings = 0;
    for (final fx in frame.fxs) {
      final progress = fx.progress.clamp(0.0, 1.0);
      final color = fx.color ?? PuttPalette.yolk;
      if (fx.kind == PuttWorldFxKind.ring) {
        if (rings >= _rings.length) continue;
        final ring = _rings[rings++];
        ring.visible = true;
        final radius = fx.size * (0.3 + progress * 1.4);
        ring.scale.setValues(radius, radius, 1);
        ring.position.setValues(fx.at.x, 0.08, fx.at.y);
        ring.material?.color = _linOf(color);
        ring.material?.opacity = (1 - progress) * 0.85;
        continue;
      }
      if (active >= _sprites.length) continue;
      final sprite = _sprites[active++];
      sprite.visible = true;

      Vec2 at = fx.at;
      double lift;
      double width;
      double height;
      var opacity = (1 - progress) * 0.85;
      double rotation = 0;
      switch (fx.kind) {
        case PuttWorldFxKind.droplet:
          lift = 0.7 * math.sin(progress * math.pi);
          width = height = fx.size * (0.6 + 0.5 * progress);
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
      }
      if (fx.height != null && fx.kind != PuttWorldFxKind.confetti) {
        lift = fx.height!;
      }
      sprite.position.setValues(at.x, lift, at.y);
      sprite.scale.setValues(width, height, 1);
      final material = sprite.material;
      if (material is tjs.SpriteMaterial) {
        material.color = _linOf(color);
        material.opacity = opacity.clamp(0.0, 1.0);
        material.rotation = rotation;
        // Confetti is paper (hard edges): no soft disc for it.
        final wantsDisc = fx.kind != PuttWorldFxKind.confetti;
        if ((material.map != null) != wantsDisc) {
          material.map = wantsDisc ? texture : null;
          material.needsUpdate = true;
        }
      }
    }
    for (var i = active; i < _sprites.length; i++) {
      _sprites[i]
        ..visible = false
        ..scale.setValues(0.001, 0.001, 1);
    }
    for (var i = rings; i < _rings.length; i++) {
      _rings[i].visible = false;
    }
  }
}
