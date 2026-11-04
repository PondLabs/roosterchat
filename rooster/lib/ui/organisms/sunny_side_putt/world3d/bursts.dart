// The world's own bursts, the ones it sees for itself: straw flying off the
// nest when an egg drops in, a confetti column for the viewer's own sink,
// and a puff of turf where an egg slams into a rail. (The game's bursts -
// splashes, sparkles, the putt's dust, the confetti everyone sees - come in
// with each frame; these need no game event, the world notices them.)
// Particles fly in three dimensions under gravity, on two pools - soft
// puffs over the disc and hard-edged paper - so no sprite ever changes its
// texture in play.
part of '../putt_world3d.dart';

class _BurstParticle {
  _BurstParticle({
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.life,
    required this.size,
    required this.hex,
    required this.paper,
    this.gravity = 9,
    this.drag = 1.2,
    this.fade = true,
  });

  double x, y, z, vx, vy, vz;
  final double life;
  final double size;
  final int hex;
  final bool paper;
  final double gravity;
  final double drag;
  final bool fade;
  double age = 0;
}

class _Bursts {
  _Bursts() {
    group = tjs.Group()..name = 'bursts';
    for (var i = 0; i < 48; i++) {
      _soft.add(_sprite(soft: true));
    }
    for (var i = 0; i < 120; i++) {
      _paper.add(_sprite(soft: false));
    }
  }

  late final tjs.Group group;
  final List<tjs.Sprite> _soft = [];
  final List<tjs.Sprite> _paper = [];
  final List<_BurstParticle> _live = [];
  final _Rand _rand = _Rand(2718);

  tjs.Sprite _sprite({required bool soft}) {
    final sprite = tjs.Sprite(
      tjs.SpriteMaterial({
        if (soft) tjs.MaterialProperty.map: _EggView3D._shadowTexture,
        tjs.MaterialProperty.color: 0xFFFFFF,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.0,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = soft ? 'burst-puff' : 'burst-paper'
      ..visible = false
      ..renderOrder = 9;
    group.add(sprite);
    return sprite;
  }

  /// Straw flying off the nest's rim as an egg drops in.
  void straw(Vec2 at, double radius) {
    for (var i = 0; i < 26; i++) {
      final angle = _rand.range(0, math.pi * 2);
      final speed = _rand.range(1.5, 4.5);
      _live.add(_BurstParticle(
        x: at.x + math.cos(angle) * radius,
        y: 0.3,
        z: at.y + math.sin(angle) * radius,
        vx: math.cos(angle) * speed,
        vy: _rand.range(4, 8),
        vz: math.sin(angle) * speed,
        life: _rand.range(0.9, 1.4),
        size: _rand.range(0.16, 0.3),
        hex: _rand.chance(0.5) ? _Farm.straw : _Farm.strawLight,
        paper: true,
        gravity: 14,
        drag: 0.8,
      ));
    }
  }

  /// The viewer's own sink: a column of confetti shooting up out of the
  /// nest, big enough to read from the camera's height.
  void confettiColumn(Vec2 at) {
    const colors = [
      0xE8382A, // comb
      0xF89B17, // yolk
      0xFFF8EE, // cream
      0x2F9BE8,
      0x8CCB2E,
      0xE8508F,
    ];
    for (var i = 0; i < 90; i++) {
      final angle = _rand.range(0, math.pi * 2);
      final spread = _rand.range(0.4, 3.2);
      _live.add(_BurstParticle(
        x: at.x,
        y: 0.4,
        z: at.y,
        vx: math.cos(angle) * spread,
        vy: _rand.range(9, 16),
        vz: math.sin(angle) * spread,
        life: _rand.range(1.8, 2.6),
        size: _rand.range(0.32, 0.5),
        hex: colors[i % colors.length],
        paper: true,
        gravity: 9,
        drag: 1.6,
        fade: false,
      ));
    }
  }

  /// A rail hit: a little cloud of turf and dust where the egg met it.
  void puff(Vec2 at, double strength) {
    final count = (4 + strength * 6).round().clamp(4, 10);
    for (var i = 0; i < count; i++) {
      final angle = _rand.range(0, math.pi * 2);
      final speed = _rand.range(0.5, 1.6) * (0.6 + strength);
      _live.add(_BurstParticle(
        x: at.x,
        y: 0.25,
        z: at.y,
        vx: math.cos(angle) * speed,
        vy: _rand.range(0.6, 1.8),
        vz: math.sin(angle) * speed,
        life: _rand.range(0.35, 0.6),
        size: _rand.range(0.35, 0.6),
        hex: 0xF1E6CF,
        paper: false,
        gravity: 2,
        drag: 2.4,
      ));
    }
  }

  void update(double dt, double time) {
    for (final p in _live) {
      p.age += dt;
      final dragK = math.exp(-p.drag * dt);
      p.vx *= dragK;
      p.vz *= dragK;
      p.vy = p.vy * dragK - p.gravity * dt;
      // Paper flutters down slowly once it tops out.
      if (p.paper && p.vy < -2.4) p.vy = -2.4;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      if (p.y < 0.05) {
        p.y = 0.05;
        p.vx = 0;
        p.vz = 0;
        p.vy = 0;
      }
    }
    _live.removeWhere((p) => p.age >= p.life);
    var soft = 0;
    var paper = 0;
    for (final p in _live) {
      final sprite = p.paper
          ? (paper < _paper.length ? _paper[paper++] : null)
          : (soft < _soft.length ? _soft[soft++] : null);
      if (sprite == null) continue;
      final t = (p.age / p.life).clamp(0.0, 1.0);
      sprite.visible = true;
      sprite.position.setValues(p.x, p.y, p.z);
      final material = sprite.material;
      if (material is tjs.SpriteMaterial) {
        material.color = _lin(p.hex);
        material.opacity =
            p.fade ? (1 - t) * 0.9 : (t < 0.8 ? 1.0 : (1 - t) * 5);
        if (p.paper) material.rotation = p.age * 7 + p.x;
      }
      if (p.paper) {
        // A paper square tumbling: one axis breathes as it turns.
        final flip = math.sin(p.age * 14 + p.z * 3).abs();
        sprite.scale.setValues(p.size, p.size * (0.25 + 0.75 * flip), 1);
      } else {
        final grow = p.size * (0.6 + t * 1.2);
        sprite.scale.setValues(grow, grow, 1);
      }
    }
    for (var i = soft; i < _soft.length; i++) {
      _soft[i].visible = false;
    }
    for (var i = paper; i < _paper.length; i++) {
      _paper[i].visible = false;
    }
  }

  /// Hides everything (a new hole starts clean).
  void clear() {
    _live.clear();
    for (final sprite in [..._soft, ..._paper]) {
      sprite.visible = false;
    }
  }
}
