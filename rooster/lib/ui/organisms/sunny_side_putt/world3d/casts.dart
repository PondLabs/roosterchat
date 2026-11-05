// The power-ups' standing pieces on the green, the ones the particles
// cannot be: the Thieving Crow (a little black bird of merged primitives,
// inked like the other characters) flying its arc from the robbed egg to
// the thief's with the stolen power-up's icon in its beak, and the Nest
// Magnet's shimmer on the nest. Both are built once with the world and
// pooled; a frame only moves them (the crows ride [PuttWorldFrame.crows],
// the shimmer the eggs' magnet flags), and a new hole hides them. The
// casts' particles - kernels, wind, steam, swirls, shards - ride the fx
// pool (aim_fx.dart); the shell's bubble and the ghost's fade ride the
// eggs (actors.dart).
part of '../putt_world3d.dart';

/// The power-ups a crow can carry, by id: one loot icon each.
const List<String> _lootIds = [
  'hawk_eye',
  'nest_magnet',
  'ghost_egg',
  'chicken_hop',
  'rabbit_hole',
  'gust',
  'thick_shell',
  'strong_coffee',
  'nest_swap',
  'sprinkler',
  'corn_rain',
  'thieving_crow',
];

class _CastScenes {
  _CastScenes() {
    group = tjs.Group()..name = 'casts';
    // The loot's icons, painted by Flutter (a frame after they are asked
    // for), one texture per power-up for the world's life: a crow shows
    // the one it carries, no material ever changes its map.
    for (final id in _lootIds) {
      _loot[id] = _paintedTexture(
        96,
        96,
        0x000000,
        (canvas, size) => paintPuttPowerUpIcon(canvas, size, id),
        transparent: true,
      );
    }
    for (var i = 0; i < 2; i++) {
      final crow = _CrowView3D(_loot);
      _crows.add(crow);
      group
        ..add(crow.group)
        ..add(crow.loot);
    }
    group.add(_magnet.group);
  }

  late final tjs.Group group;
  final Map<String, tjs.DataTexture> _loot = {};
  final List<_CrowView3D> _crows = [];
  final _MagnetShimmer _magnet = _MagnetShimmer();

  /// One frame: the crows on their flights (the rest hidden), the nest's
  /// shimmer while an egg carries a magnet. [grow] sizes what must read
  /// from far off.
  void sync(
    PuttWorldFrame frame, {
    required HoleDef? hole,
    required _Ground ground,
    required double grow,
    required double dt,
  }) {
    for (var i = 0; i < _crows.length; i++) {
      final flight = i < frame.crows.length ? frame.crows[i] : null;
      _crows[i].sync(flight, frame.time, ground, grow);
    }
    PuttWorldEgg? pulled;
    for (final egg in frame.eggs) {
      if (egg.magnet) {
        pulled = egg;
        break;
      }
    }
    final nest = hole?.nest;
    _magnet.sync(
      pulled == null || nest == null ? null : nest,
      tint: pulled?.tint,
      floor: nest == null ? 0 : ground.at(nest.position),
      time: frame.time,
      dt: dt,
    );
  }

  /// A new hole: nothing of the last one's casts stays up.
  void clear() {
    for (final crow in _crows) {
      crow.hide();
    }
    _magnet.hide();
  }
}

// ---- the crow ---------------------------------------------------------------------------

/// The Thieving Crow: a round black body, a head with a beak and bright
/// eyes, a fanned tail and two wings that beat on their own pivots, all
/// inked; forward is local +z. Its loot - every power-up's icon, one
/// showing - hangs in [loot], beside the bird rather than under it, so the
/// icons can face the camera.
class _CrowView3D {
  _CrowView3D(Map<String, tjs.DataTexture> textures) {
    group = tjs.Group()
      ..name = 'cast-crow'
      ..visible = false;
    _body = tjs.Group()..name = 'crow-body';
    group.add(_body);
    const black = 0x2B2833;
    const sheen = 0x3E3A4C;
    const beak = 0xF2B13A;
    final ink = _hexOf(PuttPalette.ink);
    final shape = _Merged()
      ..add(tjs.SphereGeometry(1, 18, 12),
          _place(0, 0, 0, sx: 0.34, sy: 0.31, sz: 0.56), black,
          baseShade: 0.82)
      ..add(tjs.SphereGeometry(1, 16, 12),
          _place(0, 0.17, 0.46, sx: 0.25, sy: 0.24, sz: 0.25), black)
      // The beak: a stout cone pointing ahead.
      ..add(tjg.ConeGeometry(0.1, 0.34, 10),
          _place(0, 0.13, 0.78, tilt: math.pi / 2), beak)
      // The tail: a flat fan behind.
      ..add(tjg.ConeGeometry(0.24, 0.5, 8),
          _place(0, 0.04, -0.62, tilt: math.pi / 2, sz: 0.3), sheen);
    for (final side in [-1.0, 1.0]) {
      shape
        ..add(tjs.SphereGeometry(0.085, 10, 8), _place(side * 0.14, 0.24, 0.62),
            0xFFFFFF)
        ..add(tjs.SphereGeometry(0.048, 8, 6), _place(side * 0.16, 0.25, 0.68),
            ink)
        // Little yolk feet tucked under.
        ..add(tjs.BoxGeometry(0.07, 0.05, 0.16), _place(side * 0.1, -0.3, 0.04),
            beak);
    }
    final bodyMesh = shape.mesh('crow-shape', flat: false, roughness: 0.55)!;
    _inkOutline(bodyMesh, 0.035);
    _body.add(bodyMesh);
    for (final side in [-1.0, 1.0]) {
      final pivot = tjs.Group()
        ..name = 'crow-wing'
        ..position.setValues(side * 0.27, 0.1, 0.04);
      final feathers = _Merged()
        ..add(tjs.SphereGeometry(1, 14, 8),
            _place(side * 0.42, 0, -0.06, sx: 0.46, sy: 0.07, sz: 0.27), sheen)
        ..add(
            tjs.SphereGeometry(1, 10, 6),
            _place(side * 0.72, -0.01, -0.12, sx: 0.2, sy: 0.05, sz: 0.17),
            black);
      final wing = feathers.mesh('crow-feathers', flat: false)!;
      _inkOutline(wing, 0.03);
      pivot.add(wing);
      _wings.add(pivot);
      _body.add(pivot);
    }
    group.traverse((object) {
      if (!object.name.endsWith('-outline')) object.castShadow = true;
    });

    loot = tjs.Group()..name = 'crow-loot';
    for (final entry in textures.entries) {
      final icon = _Billboard(map: entry.value, opacity: 1, fog: false)
        ..name = 'crow-loot/${entry.key}'
        ..visible = false
        ..renderOrder = 12;
      _icons[entry.key] = icon;
      loot.add(icon);
    }
  }

  late final tjs.Group group;
  late final tjs.Group _body;
  final List<tjs.Group> _wings = [];

  /// The loot icons, one per power-up, in a group of their own (unturned,
  /// so each faces the camera).
  late final tjs.Group loot;
  final Map<String, _Billboard> _icons = {};

  /// The share of the flight it swoops in to grab, and where it lets go.
  static const double grab = 0.16;
  static const double drop = 0.84;

  void hide() {
    group.visible = false;
    for (final icon in _icons.values) {
      icon.visible = false;
    }
  }

  void sync(PuttWorldCrow? flight, double time, _Ground ground, double grow) {
    if (flight == null) {
      hide();
      return;
    }
    final p = flight.progress.clamp(0.0, 1.0);
    final from = flight.from;
    final to = flight.to;
    final span = from.distanceTo(to);
    final heading =
        span < 1e-3 ? const Vec2(0, 1) : (to - from) * (1 / math.max(span, 1));
    final arc = (2.2 + span * 0.16).clamp(2.0, 6.0);
    // Where it is and how high, through the three beats of the flight.
    Vec2 at;
    double lift;
    double size;
    double climb;
    if (p < grab) {
      // In over the robbed egg: down from above, the beak to the loot.
      final k = p / grab;
      at = from - heading * (0.6 * (1 - k));
      lift = 1.9 + 1.2 * (1 - k) * (1 - k);
      size = _easeOutBack(math.min(1, k * 1.6));
      climb = -0.6 * (1 - k);
    } else if (p < drop) {
      final k = (p - grab) / (drop - grab);
      final u = k * k * (3 - 2 * k);
      at = from + (to - from) * u;
      lift = 1.9 + arc * math.sin(math.pi * u);
      size = 1;
      climb = math.cos(math.pi * u) * arc * math.pi / math.max(span, 2) * 0.6;
    } else {
      // Over the thief's egg: the loot goes in, the crow climbs away.
      final k = (p - drop) / (1 - drop);
      at = to + heading * (1.4 * k * k);
      lift = 1.9 + 2.4 * k * k;
      size = 1 - k * k;
      climb = 0.5 + k;
    }
    final scale = math.max(size, 0.001) * 1.3 * grow;
    final floor = ground.at(at);
    group
      ..visible = size > 0.01
      ..position.setValues(at.x, floor + lift * grow, at.y)
      ..scale.setValues(scale, scale, scale);
    final yaw = math.atan2(heading.x, heading.y);
    group.rotation.y = yaw;
    _body.rotation.x = -math.atan(climb).clamp(-0.6, 0.6);
    // Wings beat hard on the way in and out, steadier in flight.
    final beat = p < grab || p > drop ? 22.0 : 15.0;
    final flap = math.sin(time * beat) * 0.75 + 0.15;
    _wings[0].rotation.z = flap;
    _wings[1].rotation.z = -flap;

    // The loot: from the robbed egg up to the beak, carried, then down
    // into the thief's egg.
    for (final entry in _icons.entries) {
      entry.value.visible = entry.key == flight.effectId;
    }
    final icon = _icons[flight.effectId];
    if (icon == null) return;
    // Held just under the beak's tip, so the beak still shows.
    final beakX = at.x + heading.x * 0.92 * scale;
    final beakZ = at.y + heading.y * 0.92 * scale;
    final beakY = floor + lift * grow - 0.3 * scale;
    double x = beakX, y = beakY, z = beakZ, iconSize = 1.05 * grow;
    if (p < grab) {
      final g = p / grab;
      final k = 1 - (1 - g) * (1 - g);
      final eggTop = ground.at(from) + 0.9;
      x = from.x + (beakX - from.x) * k;
      z = from.y + (beakZ - from.y) * k;
      y = eggTop + (beakY - eggTop) * k;
      iconSize *= 0.6 + 0.4 * k;
    } else if (p > drop) {
      final g = ((p - drop) / 0.5 / (1 - drop)).clamp(0.0, 1.0).toDouble();
      final k = g * g;
      final eggTop = ground.at(to) + 0.7;
      final start = to.x, startZ = to.y;
      x = beakX + (start - beakX) * k;
      z = beakZ + (startZ - beakZ) * k;
      y = beakY + (eggTop - beakY) * k;
      iconSize *= 1 - 0.7 * k;
      icon.visible = k < 1;
    }
    icon
      ..position.setValues(x, y, z)
      ..scale.setValues(iconSize, iconSize, 1);
    icon.look.opacity = 1;
  }
}

// ---- the nest magnet ----------------------------------------------------------------------

/// The Nest Magnet's shimmer on the nest while an egg carries one: a ring
/// round the straw that breathes, rings sent out from it like a pull, and
/// glints running round, in the magnet egg's colour warmed with yolk.
class _MagnetShimmer {
  _MagnetShimmer() {
    group = tjs.Group()
      ..name = 'cast-magnet'
      ..visible = false;
    _steady = tjs.Mesh(
      tjg.RingGeometry(1.0, 1.14, 56, 1),
      _unlit(0xFFFFFF, opacity: 0, depthWrite: false),
    )
      ..name = 'magnet-ring'
      ..rotation.x = -math.pi / 2
      ..renderOrder = 6;
    group.add(_steady);
    for (var i = 0; i < 2; i++) {
      final pulse = tjs.Mesh(
        tjg.RingGeometry(0.94, 1.0, 56, 1),
        _unlit(0xFFFFFF, opacity: 0, depthWrite: false),
      )
        ..name = 'magnet-pulse'
        ..rotation.x = -math.pi / 2
        ..renderOrder = 6;
      _pulses.add(pulse);
      group.add(pulse);
    }
    for (var i = 0; i < 6; i++) {
      final glint = _Billboard(
          map: _EggView3D._shadowTexture, blending: tjs.AdditiveBlending)
        ..name = 'magnet-glint'
        ..renderOrder = 9;
      _glints.add(glint);
      group.add(glint);
    }
  }

  late final tjs.Group group;
  late final tjs.Mesh _steady;
  final List<tjs.Mesh> _pulses = [];
  final List<_Billboard> _glints = [];

  /// How strongly it shows (eases in and out, so it never blinks).
  double _shown = 0;
  Nest? _nest;
  double _floor = 0;
  int _tintHex = 0xFFFFFF;

  void hide() {
    _shown = 0;
    _nest = null;
    group.visible = false;
  }

  void sync(Nest? nest,
      {ui.Color? tint,
      double floor = 0,
      required double time,
      required double dt}) {
    if (nest != null) {
      _nest = nest;
      _floor = floor;
      if (tint != null) {
        _tintHex = _mix(_hexOf(tint), _hexOf(PuttPalette.yolk), 0.35);
      }
    }
    final target = nest == null ? 0.0 : 1.0;
    _shown += (target - _shown) * math.min(1.0, dt * 6);
    final shownNest = _nest;
    if (shownNest == null || _shown < 0.02) {
      group.visible = false;
      if (nest == null && _shown < 0.02) _nest = null;
      return;
    }
    group.visible = true;
    final r = shownNest.radius * 1.45;
    final at = shownNest.position;
    group.position.setValues(at.x, _floor + 0.09, at.y);
    final color = _lin(_tintHex);
    final breathe = 0.5 + 0.5 * math.sin(time * 5.2);
    _steady
      ..scale.setValues(r * (1 + breathe * 0.04), r * (1 + breathe * 0.04), 1);
    _steady.material?.color = color;
    _steady.material?.opacity = _shown * (0.55 + 0.35 * breathe);
    for (var i = 0; i < _pulses.length; i++) {
      // Rings drawn in toward the nest: each starts wide and closes on it.
      final k = (time * 0.9 + i / _pulses.length) % 1.0;
      final s = r * (2.3 - 1.3 * k);
      _pulses[i].scale.setValues(s, s, 1);
      _pulses[i].material?.color = color;
      _pulses[i].material?.opacity = _shown * 0.7 * math.sin(math.pi * k);
    }
    for (var i = 0; i < _glints.length; i++) {
      final angle = time * 2.1 + i * math.pi * 2 / _glints.length;
      final glint = _glints[i];
      glint.position.setValues(
          math.cos(angle) * r * 1.02, 0.25, math.sin(angle) * r * 1.02);
      final twinkle = 0.5 + 0.5 * math.sin(time * 9 + i * 1.7);
      final size = 0.32 + 0.22 * twinkle;
      glint.scale.setValues(size, size, 1);
      glint.look
        ..color = color
        ..opacity = _shown * (0.45 + 0.5 * twinkle);
    }
  }
}

/// An overshooting ease out (the crow's pop in), 0 to 1.
double _easeOutBack(double t) {
  const c = 1.70158;
  final k = t - 1;
  return 1 + (c + 1) * k * k * k + c * k * k;
}

// ---- the casts' textures ----------------------------------------------------------------------

/// A corn kernel, drawn in its own colours: a plump drop of bright corn
/// yellow, broad near its crown and pointed at its foot, with a pale foot,
/// a shine down one side and a dark gold edge, on clear.
tjs.DataTexture _kernelTexture() {
  const size = 48;
  final bitmap = _Bitmap(size, size)..fill(0x000000, 0);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // u across (-1..1), v along the kernel from its foot (0) to its
      // crown (1).
      final u = (x + 0.5) / size * 2 - 1;
      final v = (y + 0.5) / size;
      final halfWidth = 0.8 *
          math.sqrt(math.sin(math.pi * v).clamp(0.0, 1.0)) *
          (0.5 + 0.5 * v);
      if (halfWidth <= 0.02) continue;
      final across = u.abs() / halfWidth;
      if (across > 1) continue;
      final edge = across > 0.8 || v < 0.06 || v > 0.95;
      var colour = 0xFFD43B;
      if (v < 0.28) colour = 0xFFF0C2;
      if (u < -0.12 && u > -0.4 && v > 0.42 && v < 0.82) colour = 0xFFF3A6;
      bitmap.set(x, y, edge ? 0x9A6410 : colour);
    }
  }
  return bitmap.texture(srgb: true);
}

/// A soap-bubble disc in its own colours: a faint sky film inside, a rim
/// deepening to a clear blue, a thin dark-blue line round it (the bubble
/// holds its own on light turf, like the inked characters), and a crescent
/// of white shine on the upper left with a glint dot.
tjs.DataTexture _bubbleTexture() {
  const size = 96;
  const film = 0xD8F4FF;
  const rim = 0x5CC8F2;
  const line = 0x1C6A96;
  final bitmap = _Bitmap(size, size)..fill(film, 0);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x + 0.5) / size * 2 - 1;
      final dy = (y + 0.5) / size * 2 - 1;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 1) continue;
      var colour = film;
      var alpha = 0.2;
      if (d > 0.68) {
        // The rim: deeper and denser toward the edge.
        final k = ((d - 0.68) / 0.24).clamp(0.0, 1.0);
        colour = _mix(film, rim, k);
        alpha = 0.2 + 0.62 * k * k;
      }
      if (d > 0.92) {
        // The line round it, soft at its outer edge.
        colour = line;
        alpha = 0.9 * ((1 - d) / 0.08).clamp(0.0, 1.0);
      }
      // The shine: a crescent hugging the upper left (the texture's rows
      // run bottom-up, so up is +y here), and a dot.
      final angle = math.atan2(dy, dx);
      final upLeft = math.cos(angle - 2.36);
      if (upLeft > 0.5 && d > 0.58 && d < 0.84) {
        final band = 1 - ((d - 0.71) / 0.13).abs();
        final shine = band * ((upLeft - 0.5) / 0.5);
        if (shine > 0) {
          colour = _mix(colour, 0xFFFFFF, shine.clamp(0.0, 1.0));
          alpha = math.max(alpha, 0.95 * shine);
        }
      }
      final gx = dx - 0.36;
      final gy = dy + 0.4;
      final glint = math.sqrt(gx * gx + gy * gy);
      if (glint < 0.1) {
        colour = 0xFFFFFF;
        alpha = math.max(alpha, 0.9 * (1 - glint / 0.1));
      }
      bitmap.set(x, y, colour, (alpha.clamp(0.0, 1.0) * 255).round());
    }
  }
  return bitmap.texture();
}

/// A wind streak: a crisp white line, thin and full in its middle, its
/// tail drawn out long and its head rounded, on clear.
tjs.DataTexture _streakTexture() {
  const width = 64;
  const height = 16;
  final bitmap = _Bitmap(width, height)..fill(0xFFFFFF, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final u = (x + 0.5) / width; // tail (0) to head (1)
      final v = ((y + 0.5) / height) * 2 - 1;
      // Thickest near the head, tapering to nothing at the tail.
      final thickness = 0.85 * math.pow(u, 0.7).toDouble();
      final head =
          u > 0.9 ? math.sqrt(math.max(0, 1 - ((u - 0.9) / 0.1))) : 1.0;
      final half = thickness * head;
      if (half <= 0.02) continue;
      final across = v.abs() / half;
      if (across > 1) continue;
      final alpha = (1 - across * across) * math.min(1.0, u * 2.2);
      bitmap.set(x, y, 0xFFFFFF, (alpha.clamp(0.0, 1.0) * 255).round());
    }
  }
  return bitmap.texture(srgb: false);
}
