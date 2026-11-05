// The world's shared kit: the farm palette and its trip into linear light,
// a seeded random for the scenery, merged vertex-coloured geometry (so a
// meadow of flowers is one draw call), and the procedural textures - all
// drawn straight into RGBA bytes, nothing platform-bound - plus the
// painted ones (text on the flag) that come from Flutter's own rasterizer.
part of '../putt_world3d.dart';

// ---- colour ----------------------------------------------------------------------

double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// [hex] (0xRRGGBB, sRGB as designers write it) in the renderer's linear
/// working space.
tjs.Color _lin(int hex) => tjs.Color(
      _toLinear(((hex >> 16) & 0xFF) / 255),
      _toLinear(((hex >> 8) & 0xFF) / 255),
      _toLinear((hex & 0xFF) / 255),
    );

/// A palette colour (dart:ui) as a linear three_js colour.
tjs.Color _linOf(ui.Color color) => _lin(_hexOf(color));

/// three_js takes int hex without the alpha byte; the palette keeps ui.Color.
int _hexOf(ui.Color color) => color.toARGB32() & 0xFFFFFF;

int _r(int hex) => (hex >> 16) & 0xFF;
int _g(int hex) => (hex >> 8) & 0xFF;
int _b(int hex) => hex & 0xFF;

/// Mixes two sRGB hexes channel-wise, [t] of the way from [a] to [b].
int _mix(int a, int b, double t) {
  final k = t.clamp(0.0, 1.0);
  int channel(int x, int y) => (x + (y - x) * k).round().clamp(0, 255);
  return (channel(_r(a), _r(b)) << 16) |
      (channel(_g(a), _g(b)) << 8) |
      channel(_b(a), _b(b));
}

/// [hex] brightened (factor over 1) or darkened (under 1).
int _shade(int hex, double factor) {
  int channel(int x) => (x * factor).round().clamp(0, 255);
  return (channel(_r(hex)) << 16) | (channel(_g(hex)) << 8) | channel(_b(hex));
}

/// The farm's own colours (sRGB), warmed toward the Rooster palette: comb
/// red on the barn and the bumpers, yolk on the straw and the crates, cream
/// on the trim, ink only where things go dark.
abstract final class _Farm {
  // The course.
  static const turfShade = 0x3E7F2A;
  static const woodTop = 0xE9AE6C;
  static const wood = 0xC27C42;
  static const tableSide = 0xB97440;
  static const post = 0xF4E6D2;
  static const shore = 0xD9BE82;

  // Around the course.
  static const path = 0xE2C48E;
  static const leafA = 0x4FA33F;
  static const leafB = 0x6DBB46;
  static const leafC = 0x3C8C3B;
  static const leafAutumn = 0xE0A53A;
  static const trunk = 0x7A5032;
  static const rock = 0xA39A90;
  static const rockDark = 0x7F776E;
  static const moss = 0x7FAE45;

  // The sky's clouds (the dome's colours come with each course's theme).
  static const cloud = 0xFFFFFF;

  // Water.
  static const water = 0x39A3D8;
  static const waterDeep = 0x1D6FAA;
  static const waterFoam = 0xEAF8FF;
  static const lily = 0x4E9C3A;

  // The farm's buildings and things.
  static const barnRed = 0xC63A2C;
  static const barnRedDark = 0x9C2C22;
  static const trim = 0xFAF1E4;
  static const roof = 0x5A3B30;
  static const roofDark = 0x46302A;
  static const hay = 0xEDC867;
  static const hayDark = 0xC79A3E;
  static const straw = 0xEDBE58;
  static const strawDark = 0xB98232;
  static const strawLight = 0xF8DB8A;
  static const metalDark = 0xA7AFB7;
  static const silo = 0xDCD3C6;
  static const siloRoof = 0xB9C2CB;

  // Flowers.
  static const flowerRed = 0xE8382A;
  static const flowerYolk = 0xF89B17;
  static const flowerCream = 0xFFF8EE;
  static const flowerPink = 0xF08AA0;
}

// ---- seeded randomness -------------------------------------------------------------

/// A small deterministic random (Park-Miller, exact in a double's 53 bits,
/// so web and native agree), so a hole's scenery comes out the same every
/// time it is built.
class _Rand {
  _Rand(int seed) : _state = (seed.abs() % 2147483646) + 1;

  int _state;

  /// The next number in [0, 1).
  double next() {
    _state = (_state * 16807) % 2147483647;
    return (_state - 1) / 2147483646;
  }

  double range(double a, double b) => a + (b - a) * next();

  int below(int n) => n <= 1 ? 0 : (next() * n).floor().clamp(0, n - 1);

  bool chance(double p) => next() < p;
}

/// A stable seed from a hole's id (kept under 2^31, exact everywhere).
int _seedOf(String id) {
  var hash = 7;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) % 2147483647;
  }
  return hash;
}

/// Smooth 2D value noise in [0, 1] - the meadow's patches and the hills'
/// rolls.
double _noise2(double x, double y, int seed) {
  final x0 = x.floor();
  final y0 = y.floor();
  final fx = x - x0;
  final fy = y - y0;
  double smooth(double t) => t * t * (3 - 2 * t);
  final a = _hash2(x0, y0, seed);
  final b = _hash2(x0 + 1, y0, seed);
  final c = _hash2(x0, y0 + 1, seed);
  final d = _hash2(x0 + 1, y0 + 1, seed);
  final sx = smooth(fx);
  final sy = smooth(fy);
  return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
}

/// The lattice's value at ([x], [y]): the shader world's sine hash, in
/// [0, 1).
double _hash2(int x, int y, int seed) {
  final v = math.sin(x * 127.1 + y * 311.7 + (seed % 1013) * 74.7) * 43758.5453;
  return v - v.floorToDouble();
}

/// Layered noise: two octaves, the meadow's and the turf's grain.
double _fbm(double x, double y, int seed) =>
    _noise2(x, y, seed) * 0.65 + _noise2(x * 2.3, y * 2.3, seed + 7) * 0.35;

// ---- merged geometry ---------------------------------------------------------------

/// Many small pieces poured into one vertex-coloured geometry: every tree,
/// flower and pebble of the meadow becomes a single mesh (one draw call),
/// each piece still carrying its own colour and a soft darkening toward
/// its base (the cheap ambient occlusion that grounds things).
class _Merged {
  /// A builder whose pieces placed beyond [shadowReach] of [shadowCenter]
  /// pour into a second mesh ([farMesh]) that casts no shadow: they stand
  /// outside the sun's shadow box anyway, and the shadow pass is spared
  /// their vertices.
  _Merged({this.shadowCenter, this.shadowReach = double.infinity});

  final Vec2? shadowCenter;
  final double shadowReach;

  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _colors = [];
  _Merged? _farPart;

  bool get isEmpty => _positions.isEmpty;

  /// Pours [geometry] in, moved by [matrix] and painted [hex]. The pieces'
  /// lowest vertices get [baseShade] of the colour (1 keeps it flat);
  /// [rand] with [variation] jitters each piece's tint a touch. The
  /// geometry is consumed (disposed).
  void add(
    tjs.BufferGeometry geometry,
    tjs.Matrix4 matrix,
    int hex, {
    double baseShade = 1,
    _Rand? rand,
    double variation = 0,
  }) {
    final center = shadowCenter;
    if (center != null) {
      final dx = matrix.storage[12] - center.x;
      final dz = matrix.storage[14] - center.y;
      if (dx * dx + dz * dz > shadowReach * shadowReach) {
        (_farPart ??= _Merged()).add(geometry, matrix, hex,
            baseShade: baseShade, rand: rand, variation: variation);
        return;
      }
    }
    // Moved first, while still indexed: the primitive's own smooth normals
    // ride the move (the flat-shaded materials facet in the shader).
    if (geometry.attributes['normal'] == null) geometry.computeVertexNormals();
    geometry.applyMatrix4(matrix);
    final flat = geometry.index != null ? geometry.toNonIndexed() : geometry;
    if (!identical(flat, geometry)) geometry.dispose();
    final position = flat.attributes['position'] as tjs.BufferAttribute;
    final normal = flat.attributes['normal'] as tjs.BufferAttribute;
    final count = position.count;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (var i = 0; i < count; i++) {
      final y = position.getY(i)!.toDouble();
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final span = math.max(maxY - minY, 1e-6);
    var tint = hex;
    if (rand != null && variation > 0) {
      tint = _shade(hex, 1 + (rand.next() * 2 - 1) * variation);
    }
    final base = _lin(tint);
    for (var i = 0; i < count; i++) {
      final x = position.getX(i)!.toDouble();
      final y = position.getY(i)!.toDouble();
      final z = position.getZ(i)!.toDouble();
      _positions
        ..add(x)
        ..add(y)
        ..add(z);
      _normals
        ..add(normal.getX(i)!.toDouble())
        ..add(normal.getY(i)!.toDouble())
        ..add(normal.getZ(i)!.toDouble());
      final up = (y - minY) / span;
      final k = baseShade + (1 - baseShade) * math.sqrt(up);
      _colors
        ..add(base.red * k)
        ..add(base.green * k)
        ..add(base.blue * k);
    }
    flat.dispose();
  }

  /// The poured geometry; null when nothing was added.
  tjs.BufferGeometry? build() {
    if (isEmpty) return null;
    return tjs.BufferGeometry()
      ..setAttributeFromString(
          'position', tjs.Float32BufferAttribute.fromList(_positions, 3, false))
      ..setAttributeFromString(
          'normal', tjs.Float32BufferAttribute.fromList(_normals, 3, false))
      ..setAttributeFromString(
          'color', tjs.Float32BufferAttribute.fromList(_colors, 3, false));
  }

  /// The pieces poured beyond the shadow's reach, as one mesh that casts
  /// no shadow (but still takes them); null when there are none.
  tjs.Mesh? farMesh(String name, {bool flat = true, double roughness = 0.92}) =>
      _farPart?.mesh(name, castShadow: false, flat: flat, roughness: roughness);

  /// One mesh of everything poured, in a matte vertex-coloured material.
  tjs.Mesh? mesh(String name,
      {bool castShadow = true,
      bool receiveShadow = true,
      bool flat = true,
      double roughness = 0.92}) {
    final geometry = build();
    if (geometry == null) return null;
    return tjs.Mesh(
      geometry,
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.vertexColors: true,
        tjs.MaterialProperty.roughness: roughness,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.flatShading: flat,
      }),
    )
      ..name = name
      ..castShadow = castShadow
      ..receiveShadow = receiveShadow;
  }
}

/// A plane in its own XY plane (normal +z), [nx] by [ny] cells, UVs from
/// the bottom-left - three_js's own PlaneGeometry swaps its two segment
/// counts when it indexes, so any grid that is not square comes out torn.
tjs.BufferGeometry _gridPlane(double width, double height, int nx, int ny) {
  final positions = <double>[];
  final normals = <double>[];
  final uvs = <double>[];
  final indices = <int>[];
  for (var iy = 0; iy <= ny; iy++) {
    final y = height / 2 - iy * height / ny;
    for (var ix = 0; ix <= nx; ix++) {
      final x = -width / 2 + ix * width / nx;
      positions.addAll([x, y, 0]);
      normals.addAll([0, 0, 1]);
      uvs.addAll([ix / nx, 1 - iy / ny]);
    }
  }
  final row = nx + 1;
  for (var iy = 0; iy < ny; iy++) {
    for (var ix = 0; ix < nx; ix++) {
      final a = ix + row * iy;
      final b = ix + row * (iy + 1);
      final c = ix + 1 + row * (iy + 1);
      final d = ix + 1 + row * iy;
      indices.addAll([a, b, d, b, c, d]);
    }
  }
  return tjs.BufferGeometry()
    ..setIndex(indices)
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false))
    ..setAttributeFromString(
        'uv', tjs.Float32BufferAttribute.fromList(uvs, 2, false));
}

/// A placement matrix: at ([x], [y], [z]), turned [yaw] about the
/// vertical (then [tilt] about x), scaled ([sx], [sy], [sz]).
tjs.Matrix4 _place(
  double x,
  double y,
  double z, {
  double yaw = 0,
  double tilt = 0,
  double roll = 0,
  double sx = 1,
  double sy = 1,
  double sz = 1,
}) {
  final rotation = tjs.Quaternion()
    ..setFromEuler(tjs.Euler(tilt, yaw, roll, tjs.RotationOrders.yxz));
  return tjs.Matrix4().compose(
    tjs.Vector3(x, y, z),
    rotation,
    tjs.Vector3(sx, sy, sz),
  );
}

// ---- materials ---------------------------------------------------------------------

/// A matte surface in [hex] (sRGB).
tjs.MeshStandardMaterial _matte(
  int hex, {
  double roughness = 0.88,
  double metalness = 0,
  bool flat = false,
}) =>
    tjs.MeshStandardMaterial({
      tjs.MaterialProperty.color: _lin(hex),
      tjs.MaterialProperty.roughness: roughness,
      tjs.MaterialProperty.metalness: metalness,
      tjs.MaterialProperty.flatShading: flat,
    });

/// A flat, unlit colour (glows, dark holes, the sky's own colours).
tjs.MeshBasicMaterial _unlit(
  int hex, {
  double opacity = 1,
  bool fog = true,
  bool depthWrite = true,
  int blending = tjs.NormalBlending,
}) =>
    tjs.MeshBasicMaterial({
      tjs.MaterialProperty.color: _lin(hex),
      tjs.MaterialProperty.transparent: opacity < 1,
      tjs.MaterialProperty.opacity: opacity,
      tjs.MaterialProperty.fog: fog,
      tjs.MaterialProperty.depthWrite: depthWrite,
      tjs.MaterialProperty.blending: blending,
    });

// ---- procedural textures ------------------------------------------------------------

/// An RGBA canvas of bytes the texture stamps draw into.
/// A camera-facing quad: what a three_js Sprite is meant to be, as a plain
/// mesh. This renderer draws no Sprite on the web (no trail, no confetti,
/// no glints ever showed), so every camera-facing piece is one of these;
/// the world turns them all to the camera once a frame, [roll] spinning
/// one in the screen's plane. Each has its own unit quad, so it disposes
/// like any mesh.
class _Billboard extends tjs.Mesh {
  _Billboard({
    tjs.Texture? map,
    Object color = 0xFFFFFF,
    double opacity = 0,
    int blending = tjs.NormalBlending,
    bool fog = true,
  }) : super(
          tjs.PlaneGeometry(1, 1),
          tjs.MeshBasicMaterial({
            if (map != null) tjs.MaterialProperty.map: map,
            tjs.MaterialProperty.color: color,
            tjs.MaterialProperty.transparent: true,
            tjs.MaterialProperty.opacity: opacity,
            tjs.MaterialProperty.depthWrite: false,
            tjs.MaterialProperty.blending: blending,
            tjs.MaterialProperty.fog: fog,
          }),
        ) {
    castShadow = false;
    receiveShadow = false;
  }

  /// The spin in the screen's plane, radians.
  double roll = 0;

  /// Its material, typed.
  tjs.MeshBasicMaterial get look => material as tjs.MeshBasicMaterial;
}

/// An ink outline for a character's [mesh]: its geometry pushed out along
/// its normals by [thickness], drawn from the back faces in ink - a line
/// round the silhouette that follows every part. Added to [mesh] itself,
/// so it moves with it.
tjs.Mesh _inkOutline(tjs.Mesh mesh, double thickness) {
  final source = mesh.geometry!;
  final position = source.attributes['position'] as tjs.BufferAttribute;
  final normal = source.attributes['normal'] as tjs.BufferAttribute;
  final pushed = Float32List(position.count * 3);
  for (var i = 0; i < position.count; i++) {
    pushed[i * 3] =
        position.getX(i)!.toDouble() + normal.getX(i)!.toDouble() * thickness;
    pushed[i * 3 + 1] =
        position.getY(i)!.toDouble() + normal.getY(i)!.toDouble() * thickness;
    pushed[i * 3 + 2] =
        position.getZ(i)!.toDouble() + normal.getZ(i)!.toDouble() * thickness;
  }
  final geometry = tjs.BufferGeometry()
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(pushed, 3, false));
  final index = source.index;
  if (index != null) geometry.setIndex(index);
  final outline = tjs.Mesh(
    geometry,
    tjs.MeshBasicMaterial({
      tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.ink)),
      tjs.MaterialProperty.side: tjs.BackSide,
    }),
  )..name = '${mesh.name}-outline';
  mesh.add(outline);
  return outline;
}

/// Solid white, for the billboards that are flat squares of colour
/// (confetti, straw). Shared, like the soft disc, and never disposed with
/// a hole.
final tjs.DataTexture _paperTexture = (_Bitmap(4, 4)..fill(0xFFFFFF)).texture();

/// The green's relief as the actors stand on it: the current hole's hills
/// and tiers (flat when it has none). Shared by the world and everything
/// it moves.
class _Ground {
  HoleDef? _hole;

  set hole(HoleDef? hole) => _hole = hole;

  bool get flat => _hole == null || !_hole!.hasRelief;

  /// The ground's height under [point].
  double at(Vec2 point) => flat ? 0 : _hole!.groundHeightAt(point);

  /// The ground's gradient under [point] (rise per unit, uphill).
  Vec2 slopeAt(Vec2 point) => flat ? Vec2.zero : _hole!.groundGradientAt(point);

  /// The turn that stands a flat piece (a shadow, a ring) on the ground
  /// under [point]: world up onto the surface normal.
  tjs.Quaternion tiltAt(Vec2 point) {
    final tilt = tjs.Quaternion();
    if (flat) return tilt;
    final g = _hole!.groundGradientAt(point);
    if (g == Vec2.zero) return tilt;
    final normal = tjs.Vector3(-g.x, 1, -g.y)..normalize();
    return tilt..setFromUnitVectors(tjs.Vector3(0, 1, 0), normal);
  }
}

class _Bitmap {
  _Bitmap(this.width, this.height) : data = Uint8List(width * height * 4);

  final int width;
  final int height;
  final Uint8List data;

  void set(int x, int y, int hex, [int alpha = 255]) {
    final i = (y * width + x) * 4;
    data[i] = _r(hex);
    data[i + 1] = _g(hex);
    data[i + 2] = _b(hex);
    data[i + 3] = alpha;
  }

  /// The texel's colour (alpha dropped).
  int get(int x, int y) {
    final i = (y * width + x) * 4;
    return (data[i] << 16) | (data[i + 1] << 8) | data[i + 2];
  }

  /// Blends [hex] over the texel by [t] (alpha kept).
  void blend(int x, int y, int hex, double t) {
    if (t <= 0) return;
    final k = t.clamp(0.0, 1.0);
    final i = (y * width + x) * 4;
    data[i] = (data[i] + (_r(hex) - data[i]) * k).round();
    data[i + 1] = (data[i + 1] + (_g(hex) - data[i + 1]) * k).round();
    data[i + 2] = (data[i + 2] + (_b(hex) - data[i + 2]) * k).round();
  }

  void fill(int hex, [int alpha = 255]) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        set(x, y, hex, alpha);
      }
    }
  }

  /// The bytes as a texture: colour in sRGB, mipmapped and repeating
  /// unless told otherwise.
  tjs.DataTexture texture({bool repeat = false, bool srgb = true}) {
    final texture = tjs.DataTexture(data, width, height)
      ..needsUpdate = true
      ..magFilter = tjs.LinearFilter
      ..minFilter = tjs.LinearMipmapLinearFilter
      ..generateMipmaps = true
      ..anisotropy = 8;
    if (srgb) texture.colorSpace = tjs.SRGBColorSpace;
    if (repeat) {
      texture
        ..wrapS = tjs.RepeatWrapping
        ..wrapT = tjs.RepeatWrapping;
    }
    return texture;
  }
}

/// A mask that is 1 inside [inner], 0 past [inner] + [softness], smooth
/// between - the stamps' antialiasing.
double _softBand(double distance, double inner, double softness) {
  if (softness <= 0) return distance <= inner ? 1 : 0;
  if (distance <= inner - softness) return 1;
  if (distance >= inner + softness) return 0;
  final t = (inner + softness - distance) / (2 * softness);
  return t * t * (3 - 2 * t);
}

/// Distance from [p] to the segment [a]-[b].
double _segmentDistance(Vec2 p, Vec2 a, Vec2 b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final lengthSquared = abx * abx + aby * aby;
  var t = lengthSquared <= 1e-12
      ? 0.0
      : ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  final dx = p.x - (a.x + abx * t);
  final dy = p.y - (a.y + aby * t);
  return math.sqrt(dx * dx + dy * dy);
}

/// Wood grain: warm planks with darker seams and grain streaks, grey so
/// the material's colour tints it. Tiles along u.
tjs.DataTexture _woodGrainTexture() {
  final bitmap = _Bitmap(128, 32);
  final rand = _Rand(911);
  final streaks = [
    for (var i = 0; i < 9; i++)
      (rand.range(0, 32), rand.range(0.4, 1.4), rand.range(0, 6.28)),
  ];
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      var v = 0.86 + 0.08 * _noise2(x / 9, y / 3, 3);
      for (final (row, width, phase) in streaks) {
        final wave = row + math.sin(x / 13 + phase) * 1.4;
        final d = (y - wave).abs();
        if (d < width) v -= 0.045 * (1 - d / width);
      }
      // A plank seam once per tile.
      if (x == 0 || x == 127) v -= 0.1;
      final level = (v.clamp(0.0, 1.0) * 255).round();
      bitmap.set(x, y, (level << 16) | (level << 8) | level);
    }
  }
  return bitmap.texture(repeat: true);
}

/// Grass up close: a tiling normal map of fine blades leaning every which
/// way, so the turf keeps a texture when the camera comes in (the lawn's
/// colour map is only ten texels a unit). Seamless: its noise wraps.
tjs.DataTexture _grassNormalTexture() {
  const size = 128;
  const period = 32; // lattice cells across the tile
  double lattice(int x, int y, int seed) =>
      _hash2(x % period, y % period, seed);
  double noise(double x, double y, int seed) {
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    double smooth(double t) => t * t * (3 - 2 * t);
    final a = lattice(x0, y0, seed);
    final b = lattice(x0 + 1, y0, seed);
    final c = lattice(x0, y0 + 1, seed);
    final d = lattice(x0 + 1, y0 + 1, seed);
    final sx = smooth(fx);
    final sy = smooth(fy);
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
  }

  // Heights: blades (fine, stretched along a slant) over soft clumps.
  final heights = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = x / size * period;
      final v = y / size * period;
      // Every argument spans whole lattice periods across the tile, so
      // the shear and the scales wrap without a seam.
      final blades = noise(u * 2 + v, v, 3);
      final clumps = noise(u, v, 9);
      heights[y * size + x] = blades * 0.7 + clumps * 0.3;
    }
  }
  final bitmap = _Bitmap(size, size);
  const strength = 2.2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      double h(int dx, int dy) =>
          heights[((y + dy) % size) * size + ((x + dx) % size)];
      final gx = (h(1, 0) - h(size - 1, 0)) * strength;
      final gy = (h(0, 1) - h(0, size - 1)) * strength;
      final length = math.sqrt(gx * gx + gy * gy + 1);
      int encode(double n) => ((n / length * 0.5 + 0.5) * 255).round();
      final r = encode(-gx);
      final g = encode(-gy);
      final b = encode(1);
      bitmap.set(x, y, (r << 16) | (g << 8) | b);
    }
  }
  return bitmap.texture(repeat: true, srgb: false);
}

/// The soft round blob the particles and the eggs' contact shadows use,
/// white so tinting does the colour.
tjs.DataTexture _discTexture({int size = 64, double hardness = 2}) {
  final bitmap = _Bitmap(size, size);
  for (var row = 0; row < size; row++) {
    for (var col = 0; col < size; col++) {
      final dx = col + 0.5 - size / 2;
      final dy = row + 0.5 - size / 2;
      final d = math.sqrt(dx * dx + dy * dy) / (size / 2);
      final core = (1 - d).clamp(0.0, 1.0);
      final alpha = (math.pow(core, hardness) * 255).round().clamp(0, 255);
      bitmap.set(col, row, 0xFFFFFF, alpha);
    }
  }
  final texture = bitmap.texture(srgb: false);
  return texture;
}

/// A texture whose pixels come from Flutter's own rasterizer: the flag's
/// number, in the brand's display face. It starts as [background] and
/// fills in once the picture is read back (one frame later); in the test
/// runner the read may never land, and the texture just stays plain.
tjs.DataTexture _paintedTexture(
  int width,
  int height,
  int background,
  void Function(ui.Canvas canvas, ui.Size size) paint,
) {
  final bitmap = _Bitmap(width, height)..fill(background);
  final texture = bitmap.texture();
  unawaited(() async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(ui.Color(0xFF000000 | background), ui.BlendMode.src);
      paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (bytes == null) return;
      final source = bytes.buffer.asUint8List();
      // Rows flip: the picture reads top-down, the texture bottom-up.
      final rowBytes = width * 4;
      for (var y = 0; y < height; y++) {
        bitmap.data.setRange(
          (height - 1 - y) * rowBytes,
          (height - y) * rowBytes,
          source,
          y * rowBytes,
        );
      }
      texture.needsUpdate = true;
    } on Object {
      // No rasterizer here (a headless runner): the plain texture stays.
    }
  }());
  return texture;
}

// ---- the animated pieces --------------------------------------------------------------

/// Something in the hole that moves with the clock (water, the flag, the
/// windmill's sails, the boosts' chevrons, the clouds).
abstract class _Animated {
  void tick(double time, double dt);
}

/// A closure as an animated piece.
class _AnimatedBy implements _Animated {
  _AnimatedBy(this._tick);

  final void Function(double time, double dt) _tick;

  @override
  void tick(double time, double dt) => _tick(time, dt);
}
