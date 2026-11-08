// The aim and the bursts. The aim is Putt Party's, and it is the same two
// things for every stroke, on every hole, from the first putt to the last:
// the pull - a band in the viewer's colour from the egg back to where the
// slingshot is drawn, a ring at its end - and the row of white chevrons
// ahead, one per level of the stroke, swinging the harder the putt. Nothing
// predicts the roll, marks a landing or traces the last putt: what the aim
// shows never depends on the hole, the power-ups or what came before.
// The bursts are pooled sprites over a soft disc (splashes, sparkles,
// suction, poofs, dust, confetti) and a few expanding rings.
part of '../putt_world3d.dart';

/// The levels a stroke is read in: the aim's row shows one chevron each.
const int puttPowerLevels = 8;

/// How many chevrons the aim's row shows for [power]: one per level of the
/// stroke, none for a pull that would not move the egg (its release is a
/// cancel, not a putt). Putt Party's own reading of a putt - the row's
/// length is the power, so a tap is one chevron and a full pull eight.
int puttPowerLevel(double power) {
  if (power <= 0) return 0;
  return (power.clamp(0.0, 1.0) * puttPowerLevels)
      .ceil()
      .clamp(1, puttPowerLevels);
}

/// One chevron of the row: how long and how wide (world units at the
/// standard egg), and the gap that follows it.
const double puttChevronLength = 0.42;
const double puttChevronWidth = 1.04;
const double puttChevronGap = 0.22;

/// The distance from one chevron's base to the next's.
const double puttChevronPitch = puttChevronLength + puttChevronGap;

/// Where the aim's row ends (world units from the egg's centre) for
/// [power]: the tip of its last chevron, or 0 for no row at all.
double puttRowLength(double power, {double eggRadius = 0.45}) {
  final level = puttPowerLevel(power);
  if (level == 0) return 0;
  final scale = eggRadius / 0.45;
  return eggRadius * 2.35 +
      ((level - 1) * puttChevronPitch + puttChevronLength) * scale;
}

class _PuttAimView3D {
  _PuttAimView3D({required double eggRadius}) : _eggRadius = eggRadius {
    group = tjs.Group()
      ..name = 'aim'
      ..visible = false;

    // The pull: drawn along the pull itself, so it never sways (the row
    // does). Over the other eggs like the row, under the viewer's own.
    _pulled = tjs.Group()..name = 'aim-pulled';
    group.add(_pulled);
    _bandFill =
        _unlit(0xFFFFFF, opacity: 0.96, depthWrite: false, depthTest: false);
    _bandInk = _unlit(_hexOf(PuttPalette.ink),
        opacity: 0.55, depthWrite: false, depthTest: false);
    // A unit band along -x, narrow at the egg and wider at the hand: its
    // length is a scale, so a pull never rebuilds it.
    band = tjs.Group()..name = 'aim-band';
    band
      ..add(tjs.Mesh(_strip(0.40, 0.58), _bandInk)
        ..name = 'aim-band-ink'
        ..renderOrder = 4)
      ..add(tjs.Mesh(_strip(0.26, 0.42), _bandFill)
        ..name = 'aim-band-fill'
        ..position.y = 0.006
        ..renderOrder = 5);
    _pulled.add(band);
    handle = tjs.Group()..name = 'aim-handle';
    handle
      ..add(tjs.Mesh(tjg.RingGeometry(0.30, 0.66, 32, 1), _bandInk)
        ..name = 'aim-handle-ink'
        ..rotation.x = -math.pi / 2
        ..renderOrder = 4)
      ..add(tjs.Mesh(tjg.RingGeometry(0.38, 0.58, 32, 1), _bandFill)
        ..name = 'aim-handle-fill'
        ..rotation.x = -math.pi / 2
        ..position.y = 0.006
        ..renderOrder = 5);
    _pulled.add(handle);

    // The row: white chevrons over a soft shadow (it reads on light and
    // dark turf alike), the same shape at every power. Transparent like
    // the band, so it sorts after it.
    _turned = tjs.Group()..name = 'aim-turned';
    group.add(_turned);
    _rowFill =
        _unlit(0xFFFFFF, opacity: 0.99, depthWrite: false, depthTest: false);
    _rowShade = _unlit(_hexOf(PuttPalette.ink),
        opacity: 0.6, depthWrite: false, depthTest: false);
    final fillGeometry = _triangle(puttChevronLength, puttChevronWidth);
    final shadeGeometry =
        _triangle(puttChevronLength + 0.12, puttChevronWidth + 0.16);
    for (var i = 0; i < puttPowerLevels; i++) {
      final chevron = tjs.Group()
        ..name = 'aim-chevron'
        ..visible = false;
      chevron
        ..add(tjs.Mesh(shadeGeometry, _rowShade)
          ..name = 'aim-chevron-shade'
          ..position.setValues(-0.1, 0.07, 0)
          ..renderOrder = 6)
        ..add(tjs.Mesh(fillGeometry, _rowFill)
          ..name = 'aim-chevron-fill'
          ..position.y = 0.08
          ..renderOrder = 7);
      _chevrons.add(chevron);
      _turned.add(chevron);
    }
  }

  late final tjs.Group group;
  late final tjs.Group _turned;
  late final tjs.Group _pulled;

  /// The pull's band and the ring at its end (tests read them).
  late final tjs.Group band;
  late final tjs.Group handle;
  late final tjs.MeshBasicMaterial _bandFill;
  late final tjs.MeshBasicMaterial _bandInk;
  int _bandHex = -1;

  /// The row's chevrons, one per level of the stroke (the first [level]
  /// shown); all of them share the row's two materials.
  final List<tjs.Group> _chevrons = [];
  late final tjs.MeshBasicMaterial _rowFill;
  late final tjs.MeshBasicMaterial _rowShade;
  final double _eggRadius;

  /// A flat strip from x = 0 to x = -1, [near] wide at 0 and [far] wide
  /// at -1, facing up.
  static tjs.BufferGeometry _strip(double near, double far) {
    final positions = <double>[
      0, 0, -near / 2, //
      0, 0, near / 2,
      -1, 0, far / 2,
      -1, 0, -far / 2,
    ];
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
      // Wound to face up.
      ..setIndex([0, 2, 1, 0, 3, 2]);
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

  /// [angle] (the game's, y down) as a turn about y, pitched with the
  /// ground along it on a slope.
  static void _turn(tjs.Object3D object, double angle, Vec2 slope) {
    final along = slope.x * math.cos(angle) + slope.y * math.sin(angle);
    if (along.abs() < 1e-6) {
      object.rotation.set(0, -angle, 0);
      return;
    }
    object.quaternion.setFrom(tjs.Quaternion()
        .setFromAxisAngle(tjs.Vector3(0, 1, 0), -angle)
        .multiply(tjs.Quaternion()
            .setFromAxisAngle(tjs.Vector3(0, 0, 1), math.atan(along))));
  }

  /// Shows the aim for this frame, or hides the group.
  void sync(PuttWorldAim? aim, [_Ground? ground]) {
    if (aim == null) {
      group.visible = false;
      return;
    }
    group.visible = true;
    final terrain = ground ?? _Ground();
    final floor = terrain.at(aim.origin);
    group.position.setValues(aim.origin.x, floor + 0.01, aim.origin.y);
    final slope = terrain.slopeAt(aim.origin);
    _turn(_turned, aim.angle, slope);
    _turn(_pulled, aim.pullAngle ?? aim.angle, slope);
    final scale = aim.eggRadius / _eggRadius;

    // The pull: from the egg's edge back to the hand, as long as the pull.
    final start = aim.eggRadius * 1.1;
    final reach = aim.dragLength;
    final shown = reach > start + 0.2;
    band.visible = shown;
    handle.visible = shown;
    if (shown) {
      band
        ..position.x = -start
        ..scale.setValues(reach - start, 1, scale);
      handle
        ..position.x = -reach
        ..scale.setValues(scale, 1, scale);
    }
    final tint = aim.tint;
    // The viewer's colour, lifted toward white: a band, not a second egg.
    final hex = tint == null ? 0xFFF8EE : _mix(_hexOf(tint), 0xFFFFFF, 0.35);
    if (hex != _bandHex) {
      _bandHex = hex;
      _bandFill.color = _lin(hex);
    }

    // The row: one chevron per level of the stroke, the same shape at every
    // power, so the aim never changes form under the player's hand. A pull
    // that would not move the egg draws none (its release is a cancel).
    final level = puttPowerLevel(aim.power);
    final first = aim.eggRadius * 2.35;
    final pitch = puttChevronPitch * scale;
    _turned.visible = level > 0;
    for (var i = 0; i < _chevrons.length; i++) {
      final chevron = _chevrons[i];
      chevron.visible = i < level;
      if (i >= level) continue;
      chevron
        ..position.x = first + i * pitch
        ..scale.setValues(scale, 1, scale);
    }
  }

  void dispose() {
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
          // Stout enough to read from the overview (a pixel or two was
          // lost on the lawn).
          height = fx.size * (0.32 + 0.12 * swell);
          opacity = math.min(1.0, swell * 1.6) * 0.92;
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
