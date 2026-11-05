// Each course is its own corner of the farm, at its own hour: the Coop on
// a clear morning, the Corn Maze under the midday sun, the Pond on a soft
// afternoon, Farm Road at golden hour, the Barn at dusk with its lanterns
// lit. A theme carries the sky, the sun and its fill, the haze, the
// turf's two greens, the meadow's, the rails' style and the landmarks
// around the green. The hole's id names its course (`coop_`, `maze_`,
// `pond_`, `road_`, `barn_`); anything else - the stub holes, the tests'
// - gets the Coop's morning.
part of '../putt_world3d.dart';

enum _ThemeKind { coop, maze, pond, road, barn }

/// How the rails are built: timber, a corn hedge, dry stone, road
/// barriers, or the barn's red boards.
enum _RailStyle { wood, hedge, stone, barrier, barnBoard }

class _Theme {
  const _Theme({
    required this.kind,
    required this.skyTop,
    required this.skyMid,
    required this.horizon,
    required this.sun,
    required this.sunIntensity,
    required this.sunFrom,
    required this.hemiSky,
    required this.hemiGround,
    required this.hemiIntensity,
    required this.exposure,
    required this.rails,
    required this.turfLight,
    required this.turfDark,
    required this.turfFringe,
    required this.meadow,
    required this.meadowDeep,
    required this.meadowDry,
    required this.hillFar,
    this.clouds = 0xFFFFFF,
    this.eggGlow = 0x2A2622,
    this.rim = 0x000000,
    this.rimIntensity = 0,
    this.rimFrom = (-20.0, 18.0, -40.0),
  });

  final _ThemeKind kind;

  // The sky dome, top to horizon (the haze takes the horizon's colour).
  final int skyTop;
  final int skyMid;
  final int horizon;
  final int clouds;

  // The sun: colour, strength, and where it stands from the green's
  // centre (x, height, z); the hemisphere's fill.
  final int sun;
  final double sunIntensity;
  final (double, double, double) sunFrom;
  final int hemiSky;
  final int hemiGround;
  final double hemiIntensity;

  /// The tone mapper's exposure for this light.
  final double exposure;

  final _RailStyle rails;
  final int turfLight;
  final int turfDark;
  final int turfFringe;
  final int meadow;
  final int meadowDeep;
  final int meadowDry;
  final int hillFar;

  /// The eggs' shells' own light, times their paint: a whisper by day,
  /// at dusk enough that the shells stay white and the bands glow.
  final int eggGlow;

  /// A rim light from behind the green (the far side from the camera), no
  /// shadow: at dusk a cool edge that sets the turf, the rails and the
  /// eggs apart from the meadow. Off by day.
  final int rim;
  final double rimIntensity;
  final (double, double, double) rimFrom;

  static _Theme of(String holeId) {
    final prefix = holeId.split('_').first;
    switch (prefix) {
      case 'maze':
        return maze;
      case 'pond':
        return pond;
      case 'road':
        return road;
      case 'barn':
        return barn;
      default:
        return coop;
    }
  }

  /// A clear spring morning.
  static const coop = _Theme(
    kind: _ThemeKind.coop,
    skyTop: 0x4E9FE3,
    skyMid: 0x8CC6F0,
    horizon: 0xFCE7C4,
    sun: 0xFFF0D8,
    sunIntensity: 1.32,
    sunFrom: (-26, 42, 20),
    hemiSky: 0xD6ECFF,
    hemiGround: 0x9DB86A,
    hemiIntensity: 0.62,
    exposure: 1.0,
    rails: _RailStyle.wood,
    turfLight: 0x73BE3A,
    turfDark: 0x60B130,
    turfFringe: 0x4B9A26,
    meadow: 0x8FC25C,
    meadowDeep: 0x71AB4E,
    meadowDry: 0xB2CB6B,
    hillFar: 0xA3C87F,
  );

  /// High noon over the corn: a bright sun, short shadows, golden fields.
  static const maze = _Theme(
    kind: _ThemeKind.maze,
    skyTop: 0x3C8FDC,
    skyMid: 0x84C2F2,
    horizon: 0xF7EDCB,
    sun: 0xFFF7E8,
    sunIntensity: 1.26,
    sunFrom: (-12, 52, 14),
    hemiSky: 0xDCEFFF,
    hemiGround: 0x8A9A50,
    hemiIntensity: 0.56,
    exposure: 0.88,
    rails: _RailStyle.hedge,
    turfLight: 0x7CBB37,
    turfDark: 0x68AB2D,
    turfFringe: 0x4F9223,
    // The meadow round the maze stays a field's green under the high sun.
    meadow: 0x8BA951,
    meadowDeep: 0x729346,
    meadowDry: 0xA4A65D,
    hillFar: 0x96AC72,
  );

  /// A soft afternoon by the water, the light from the other side.
  static const pond = _Theme(
    kind: _ThemeKind.pond,
    skyTop: 0x5BA5E2,
    skyMid: 0xA5D2F1,
    horizon: 0xE9F0E6,
    sun: 0xFFF3E0,
    sunIntensity: 1.2,
    sunFrom: (26, 38, 22),
    hemiSky: 0xD3EAFF,
    hemiGround: 0x7DAE6A,
    hemiIntensity: 0.7,
    exposure: 1.02,
    rails: _RailStyle.stone,
    turfLight: 0x6CBB3E,
    turfDark: 0x5AAB35,
    turfFringe: 0x45922A,
    meadow: 0x7DB85C,
    meadowDeep: 0x609F4D,
    meadowDry: 0xA2C46C,
    hillFar: 0x9AC485,
  );

  /// Golden hour on the farm road: a low sun from the west, long
  /// shadows, a peach sky.
  static const road = _Theme(
    kind: _ThemeKind.road,
    skyTop: 0x5A7FC4,
    skyMid: 0xF4A86E,
    horizon: 0xFFC98A,
    clouds: 0xFFD9BC,
    sun: 0xFFB463,
    sunIntensity: 1.3,
    sunFrom: (-48, 15, 10),
    // A cool fill from the evening sky keeps the greens green; the gold
    // is in the sun, the sky and the long shadows.
    hemiSky: 0xC9CDEB,
    hemiGround: 0x6E7A48,
    hemiIntensity: 0.56,
    exposure: 1.0,
    rails: _RailStyle.barrier,
    turfLight: 0x6AB836,
    turfDark: 0x57A72E,
    turfFringe: 0x428E24,
    meadow: 0x92B85A,
    meadowDeep: 0x76A34F,
    meadowDry: 0xC6B86C,
    hillFar: 0xB4B383,
  );

  /// Dusk at the barn: the sun nearly down, the sky deepening, lanterns
  /// glowing warm along the yard.
  static const barn = _Theme(
    kind: _ThemeKind.barn,
    skyTop: 0x243F7C,
    skyMid: 0xC97B6C,
    horizon: 0xFFB27A,
    clouds: 0xE9AE9A,
    sun: 0xFF8E4E,
    sunIntensity: 0.62,
    sunFrom: (34, 11, 8),
    hemiSky: 0x8C9BD6,
    hemiGround: 0x4F5238,
    hemiIntensity: 0.7,
    exposure: 0.95,
    rails: _RailStyle.barnBoard,
    turfLight: 0x6FB447,
    turfDark: 0x5EA23E,
    turfFringe: 0x4A8A31,
    meadow: 0x6E9E52,
    meadowDeep: 0x548A48,
    meadowDry: 0x92A464,
    hillFar: 0x8E9E78,
    eggGlow: 0x8C8274,
    // The blue hour behind the green, edging what the low sun misses.
    rim: 0x8EA2FF,
    rimIntensity: 0.6,
    rimFrom: (-22, 16, -42),
  );
}

// ---- the rails' surfaces -----------------------------------------------------------

/// The rail body's and cap's materials for a style; textures tile along
/// the rail (the timber box's UVs run in world units).
(tjs.MeshStandardMaterial, tjs.MeshStandardMaterial) _railMaterials(
    _RailStyle style) {
  switch (style) {
    case _RailStyle.wood:
      final grain = _woodGrainTexture();
      return (
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(_Farm.wood),
          tjs.MaterialProperty.map: grain,
          tjs.MaterialProperty.roughness: 0.78,
          tjs.MaterialProperty.metalness: 0.0,
        }),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(_Farm.woodTop),
          tjs.MaterialProperty.map: grain,
          tjs.MaterialProperty.roughness: 0.7,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      );
    case _RailStyle.hedge:
      final leaves = _leafTexture();
      return (
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0x4E9A35),
          tjs.MaterialProperty.map: leaves,
          tjs.MaterialProperty.roughness: 0.95,
          tjs.MaterialProperty.metalness: 0.0,
        }),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0x6FB443),
          tjs.MaterialProperty.map: leaves,
          tjs.MaterialProperty.roughness: 0.95,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      );
    case _RailStyle.stone:
      final stones = _stoneTexture();
      return (
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0xB7AFA4),
          tjs.MaterialProperty.map: stones,
          tjs.MaterialProperty.roughness: 0.92,
          tjs.MaterialProperty.metalness: 0.0,
        }),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0xD8D1C6),
          tjs.MaterialProperty.roughness: 0.85,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      );
    case _RailStyle.barrier:
      return (
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.map: _barrierTexture(),
          tjs.MaterialProperty.roughness: 0.55,
          tjs.MaterialProperty.metalness: 0.0,
        }),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(_Farm.trim),
          tjs.MaterialProperty.roughness: 0.6,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      );
    case _RailStyle.barnBoard:
      return (
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(0xC23B2D),
          tjs.MaterialProperty.map: _boardTexture(),
          tjs.MaterialProperty.roughness: 0.8,
          tjs.MaterialProperty.metalness: 0.0,
        }),
        tjs.MeshStandardMaterial({
          tjs.MaterialProperty.color: _lin(_Farm.trim),
          tjs.MaterialProperty.roughness: 0.7,
          tjs.MaterialProperty.metalness: 0.0,
        }),
      );
  }
}

/// Leaves: blotches of light and shade, grey so the colour tints them.
tjs.DataTexture _leafTexture() {
  final bitmap = _Bitmap(64, 64);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      final n = _fbm(x / 6, y / 6, 31);
      final speck = _hash2(x, y, 9);
      var v = 0.7 + n * 0.45 + (speck - 0.5) * 0.12;
      if (speck > 0.93) v += 0.18;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}

/// Dry stone: irregular blocks with dark mortar, grey for tinting.
tjs.DataTexture _stoneTexture() {
  final bitmap = _Bitmap(128, 64);
  final rand = _Rand(77);
  // Three courses of stones, each with its own joints.
  const rows = 3;
  final joints = [
    for (var r = 0; r < rows; r++)
      [
        for (var x = 0.0; x < 128; x += rand.range(18, 34)) x,
      ],
  ];
  final shades = [for (var i = 0; i < 64; i++) rand.range(0.78, 1.0)];
  for (var y = 0; y < 64; y++) {
    final row = (y / (64 / rows)).floor().clamp(0, rows - 1);
    final inRow = y - row * (64 / rows);
    for (var x = 0; x < 128; x++) {
      var stone = 0;
      for (final joint in joints[row]) {
        if (x >= joint) stone++;
      }
      final nearJoint = joints[row].any((j) => (x - j).abs() < 1.5);
      final mortar = inRow < 1.5 || nearJoint;
      var v = mortar ? 0.42 : shades[(row * 13 + stone) % shades.length];
      if (!mortar) v += (_noise2(x / 5, y / 5, 5) - 0.5) * 0.12;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}

/// A road barrier's face: comb red and cream diagonal stripes.
tjs.DataTexture _barrierTexture() {
  final bitmap = _Bitmap(64, 32);
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 64; x++) {
      final band = (((x + y) / 16).floor()).isEven;
      bitmap.set(x, y, band ? 0xD8392B : 0xFFF6EA);
    }
  }
  return bitmap.texture(repeat: true);
}

/// The barn's boards: vertical planks with dark gaps, grey for tinting.
tjs.DataTexture _boardTexture() {
  final bitmap = _Bitmap(64, 32);
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 64; x++) {
      var v = 0.9 + (_noise2(x / 3, y / 9, 13) - 0.5) * 0.12;
      if (x % 16 == 0) v = 0.55;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}

// ---- the tiers' faces ------------------------------------------------------------

/// The face of a tier's step in a course's build: a retaining wall of dark
/// timber sleepers by the coop, along the road and in the maze, dry stone
/// by the pond, a stack of hay bales under the barn's loft. Darker than
/// the rails and capless, so a drop reads as a step and not as a rail.
tjs.MeshStandardMaterial _stepMaterial(_ThemeKind kind) {
  switch (kind) {
    case _ThemeKind.pond:
      return tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0x9C9488),
        tjs.MaterialProperty.map: _stoneTexture(),
        tjs.MaterialProperty.roughness: 0.94,
        tjs.MaterialProperty.metalness: 0.0,
      });
    case _ThemeKind.barn:
      // Big bales: a course is 0.62 high, a bale 1.6 long.
      return tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(_Farm.hay),
        tjs.MaterialProperty.map: _baleStackTexture()
          ..repeat.setValues(0.75, 0.5),
        tjs.MaterialProperty.roughness: 0.97,
        tjs.MaterialProperty.metalness: 0.0,
      });
    case _ThemeKind.coop:
    case _ThemeKind.maze:
    case _ThemeKind.road:
      return tjs.MeshStandardMaterial({
        tjs.MaterialProperty.color: _lin(0x8E5B35),
        tjs.MaterialProperty.map: _sleeperTexture(),
        tjs.MaterialProperty.roughness: 0.88,
        tjs.MaterialProperty.metalness: 0.0,
      });
  }
}

/// Timber sleepers laid flat one on another: two to a tile's height, dark
/// seams between them and grain along them, grey for tinting.
tjs.DataTexture _sleeperTexture() {
  final bitmap = _Bitmap(128, 32);
  final rand = _Rand(431);
  final shades = [for (var i = 0; i < 8; i++) rand.range(0.84, 1.0)];
  for (var y = 0; y < 32; y++) {
    final plank = y ~/ 16;
    final inPlank = y % 16;
    for (var x = 0; x < 128; x++) {
      // Each sleeper ends somewhere along the tile, the rows staggered.
      final joint = (x + plank * 53) % 128;
      var v = shades[(plank * 3 + (x + plank * 53) ~/ 128) % shades.length];
      v += (_noise2(x / 11, y / 2.5, 21) - 0.5) * 0.16;
      if (inPlank < 2 || inPlank > 14) v = 0.42;
      if (joint < 2) v = 0.5;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}

/// Square bales stacked in staggered courses: straw streaking along each,
/// two twine bands, a dark seam round it; grey for tinting.
tjs.DataTexture _baleStackTexture() {
  final bitmap = _Bitmap(128, 64);
  for (var y = 0; y < 64; y++) {
    final course = y ~/ 32;
    final inCourse = y % 32;
    for (var x = 0; x < 128; x++) {
      final shifted = (x + course * 32) % 128;
      final inBale = shifted % 64;
      var v = 0.82 + (_noise2(x / 3.5, y / 1.4, 17) - 0.5) * 0.3;
      v += (_hash2(x, y, 29) - 0.5) * 0.08;
      // The twine, a third in from each end.
      if ((inBale - 21).abs() < 2 || (inBale - 43).abs() < 2) v = 0.62;
      // The seams between bales and between courses.
      if (inBale < 2 || inBale > 61 || inCourse < 2 || inCourse > 29) v = 0.45;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}
