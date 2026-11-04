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
    exposure: 1.08,
    rails: _RailStyle.wood,
    turfLight: 0x86CF4E,
    turfDark: 0x72C043,
    turfFringe: 0x5BA737,
    meadow: 0x86C24A,
    meadowDeep: 0x67AB3D,
    meadowDry: 0xAECB5A,
    hillFar: 0x9DC872,
  );

  /// High noon over the corn: a bright sun, short shadows, golden fields.
  static const maze = _Theme(
    kind: _ThemeKind.maze,
    skyTop: 0x3C8FDC,
    skyMid: 0x84C2F2,
    horizon: 0xF7EDCB,
    sun: 0xFFF7E8,
    sunIntensity: 1.42,
    sunFrom: (-12, 52, 14),
    hemiSky: 0xDCEFFF,
    hemiGround: 0xB8B05A,
    hemiIntensity: 0.6,
    exposure: 1.04,
    rails: _RailStyle.hedge,
    turfLight: 0x93CE4D,
    turfDark: 0x80BF42,
    turfFringe: 0x63A535,
    meadow: 0xB7BC52,
    meadowDeep: 0x93AE45,
    meadowDry: 0xD6C66A,
    hillFar: 0xB9C77C,
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
    exposure: 1.06,
    rails: _RailStyle.stone,
    turfLight: 0x7FCB52,
    turfDark: 0x6BBA47,
    turfFringe: 0x549F3A,
    meadow: 0x72B84C,
    meadowDeep: 0x559F3F,
    meadowDry: 0x9CC45C,
    hillFar: 0x93C47A,
  );

  /// Golden hour on the farm road: a low sun from the west, long
  /// shadows, a peach sky.
  static const road = _Theme(
    kind: _ThemeKind.road,
    skyTop: 0x5F8ACB,
    skyMid: 0xF2B583,
    horizon: 0xFFD6A0,
    clouds: 0xFFE4CC,
    sun: 0xFFC27A,
    sunIntensity: 1.38,
    sunFrom: (-44, 20, 12),
    hemiSky: 0xFFE0BE,
    hemiGround: 0x8F8F55,
    hemiIntensity: 0.56,
    exposure: 1.1,
    rails: _RailStyle.barrier,
    turfLight: 0x8DC94C,
    turfDark: 0x7BB843,
    turfFringe: 0x60A036,
    meadow: 0xA2BF4F,
    meadowDeep: 0x83AA45,
    meadowDry: 0xD3BF62,
    hillFar: 0xC7B97A,
  );

  /// Dusk at the barn: the sun nearly down, the sky deepening, lanterns
  /// glowing warm along the yard.
  static const barn = _Theme(
    kind: _ThemeKind.barn,
    skyTop: 0x2F4C8C,
    skyMid: 0xD98E72,
    horizon: 0xFFC690,
    clouds: 0xF6C7B0,
    sun: 0xFFA463,
    sunIntensity: 1.12,
    sunFrom: (34, 16, 10),
    hemiSky: 0xBCCBF2,
    hemiGround: 0x6F7448,
    hemiIntensity: 0.66,
    exposure: 1.14,
    rails: _RailStyle.barnBoard,
    turfLight: 0x7EC24C,
    turfDark: 0x6BB143,
    turfFringe: 0x529634,
    meadow: 0x7FAE48,
    meadowDeep: 0x62983E,
    meadowDry: 0xA7B45A,
    hillFar: 0x8E9E78,
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
