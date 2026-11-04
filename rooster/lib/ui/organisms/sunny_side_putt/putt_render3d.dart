// The 3D renderer of Sunny Side Putt: the flat board painters replaced by
// a perspective diorama. Every frame collects what the green is made of -
// ground stripes, walls, bumpers, the silo, crates, the nest, the eggs,
// the hen - as paintables tagged with how far they sit from the camera,
// sorts far-to-near, and paints. No z-buffer: the depth sort plus stable
// tie-breaks by kind do the job at these scales.
//
// All bodies stand on the SAME geometry the physics sees: the walls are
// the model's wall segments (boxes) and arcs (hedge chains or rocks), the
// silo is the gravity well, the crates the "?" boxes - nothing is drawn
// from data the engine does not know. The eggs and the hen keep their 2D
// art from `putt_art.dart`, pasted as billboards over elliptical ground
// shadows; a hop lifts the billboard cosmetically while the physics rolls
// on the plane as ever.
//
// The camera projection lives in `putt_camera.dart`; this file only
// projects. Nothing reads the clock or the network: the scene's time
// comes in with the frame.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'putt_art.dart';
import 'putt_camera.dart';

// ---- the scene the game hands over -------------------------------------------------

/// One egg on the green, as the renderer needs it.
class PuttEggView {
  /// The egg's spot on the ground plane, interpolated for the frame.
  final Vec2 position;

  /// Height above the green, 0 unless a hop is lifting the billboard.
  final double height;

  /// The egg's velocity, for the squash and where its face leans.
  final Vec2 velocity;

  /// The player's tint ring colour.
  final ui.Color tint;

  /// The egg radius in world units.
  final double radius;

  const PuttEggView({
    required this.position,
    required this.velocity,
    required this.tint,
    required this.radius,
    this.height = 0,
  });

  double get speed => velocity.length;
}

/// The hen (or any moving obstacle), interpolated for the frame.
class PuttHenView {
  final Vec2 position;
  final double radius;

  /// The waddle clock, ticks-and-alpha as the flat renderer used.
  final double phase;

  const PuttHenView({
    required this.position,
    required this.radius,
    required this.phase,
  });
}

/// One particle of the bursts: exactly the flat layer's four kinds.
enum PuttFxKind { droplet, sparkle, suction, poof }

class PuttFxView {
  final PuttFxKind kind;
  final Vec2 at;

  /// Where a suction particle flies home to.
  final Vec2? toward;

  /// Age over life, 0..1.
  final double progress;
  final double size;
  final ui.Color? color;

  const PuttFxView({
    required this.kind,
    required this.at,
    required this.progress,
    required this.size,
    this.toward,
    this.color,
  });
}

/// The aim while a stroke is being dragged, drawn on the ground.
class PuttAimView {
  final Vec2 origin;

  /// The drawn angle this frame: the shot's angle with the wobble sway
  /// already added.
  final double angle;

  /// Power in 0..1, which sizes the arrow and fills the ring.
  final double power;

  /// The raw pull length, for the ghost tail behind the egg.
  final double dragLength;

  /// The egg radius in world units, which sizes the power ring.
  final double eggRadius;

  const PuttAimView({
    required this.origin,
    required this.angle,
    required this.power,
    required this.dragLength,
    required this.eggRadius,
  });
}

/// Everything one frame paints. [hole] null paints just the apron (the
/// lobby's blank stage), as the flat layers did.
class PuttSceneInput {
  final HoleDef? hole;

  /// Seconds the game has breathed, for art that moves.
  final double time;

  /// The egg radius in world units (the tee cup sizes itself from it).
  final double eggRadius;

  final List<PuttEggView> eggs;
  final List<PuttHenView> hens;
  final PuttAimView? aim;
  final List<PuttFxView> fxs;

  const PuttSceneInput({
    required this.time,
    this.eggRadius = 0.45,
    this.hole,
    this.eggs = const [],
    this.hens = const [],
    this.aim,
    this.fxs = const [],
  });
}

// ---- the paint queue ------------------------------------------------------------------

/// One thing to paint, tagged for the order. Farther depth paints first;
/// equal depth (an egg standing on its own shadow) breaks the tie by
/// rank: shadow, then ground decal, then volume, then actor, then fx.
class PuttPaintable {
  final double depth;
  final int rank;
  final void Function(ui.Canvas canvas) paint;

  const PuttPaintable(this.depth, this.rank, this.paint);
}

/// The sort order of two [PuttPaintable]s. Public so the ordering itself
/// is unit-testable without pixels.
int comparePuttPaintOrder(PuttPaintable a, PuttPaintable b) {
  final byDepth = b.depth.compareTo(a.depth);
  if (byDepth != 0) return byDepth;
  return a.rank.compareTo(b.rank);
}

// Order ranks.
const int _rankShadow = 0;
const int _rankGround = 1;
const int _rankVolume = 2;
const int _rankActor = 3;
const int _rankFx = 4;

/// Paints one frame: apron backdrop, then every collected paintable in
/// depth order. The canvas is raw pixels; the camera maps world to it.
void renderPuttScene(
  ui.Canvas canvas,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  canvas.drawPaint(solidPaint(PuttPalette.apron));
  final paintables = <PuttPaintable>[];
  if (scene.hole != null) {
    _collectGround(paintables, camera, scene);
    _collectVolumes(paintables, camera, scene);
  }
  _collectActors(paintables, camera, scene);
  _collectAim(paintables, camera, scene);
  _collectFx(paintables, camera, scene);
  paintables.sort(comparePuttPaintOrder);
  for (final paintable in paintables) {
    paintable.paint(canvas);
  }
}

// ---- shared helpers --------------------------------------------------------------------

/// A path along a ground circle, projected: every ground ring the board
/// wears (shadows, rims, the nest, the wells) walks through this, so
/// perspective squashes all of them alike.
ui.Path _groundCirclePath(
  PuttCamera camera,
  Vec2 center,
  double radius, {
  double height = 0,
  int samples = 24,
}) {
  final path = ui.Path();
  for (var i = 0; i <= samples; i++) {
    final angle = i / samples * 2 * math.pi;
    final point = Vec2(
      center.x + math.cos(angle) * radius,
      center.y + math.sin(angle) * radius,
    );
    final screen = camera.project(point, height: height);
    if (i == 0) {
      path.moveTo(screen.dx, screen.dy);
    } else {
      path.lineTo(screen.dx, screen.dy);
    }
  }
  path.close();
  return path;
}

Vec2 _mid(Vec2 a, Vec2 b) => (a + b) / 2;

Vec2 _atAngle(Vec2 center, double radius, double angle) => Vec2(
    center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius);

/// A projected open polyline through world points.
ui.Path _groundPath(PuttCamera camera, List<Vec2> points, {double height = 0}) {
  final path = ui.Path();
  for (final (index, point) in points.indexed) {
    final screen = camera.project(point, height: height);
    if (index == 0) {
      path.moveTo(screen.dx, screen.dy);
    } else {
      path.lineTo(screen.dx, screen.dy);
    }
  }
  return path;
}

ui.Path _closedGroundPath(PuttCamera camera, List<Vec2> points) =>
    _groundPath(camera, [...points, points.first]);

/// One flat polygon face standing in 3D: corners are (world spot, height)
/// pairs walked in order around the face. Used by every volume - box
/// sides, box lids, the diorama's skirt.
void _collectQuadFace(
  List<PuttPaintable> out,
  PuttCamera camera, {
  required List<(Vec2, double)> corners,
  required double depth,
  required ui.Color fill,
  required double outline,
}) {
  final center = corners.fold<Vec2>(
      corners.first.$1, (acc, corner) => _mid(acc, corner.$1));
  out.add(PuttPaintable(depth, _rankVolume, (canvas) {
    final path = ui.Path();
    for (final (index, corner) in corners.indexed) {
      final screen = camera.project(corner.$1, height: corner.$2);
      if (index == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    path.close();
    canvas.drawPath(path, solidPaint(fill));
    // The ink outline peters out on slivers (an edge viewed dead-on) so
    // the seams do not double up.
    final width = camera.screenRadius(center, outline);
    if (width > 0.4) {
      canvas.drawPath(path, strokePaint(PuttPalette.ink, width));
    }
  }));
}

// Derived shades: the flat palette warmed for the light the diorama gets.
const ui.Color _lawnDark = ui.Color(0xFFE9DDC9); // cream toward stone
const ui.Color _soil = ui.Color(0xFF2C2219); // apron warmed with ink
const ui.Color _soilDark = ui.Color(0xFF241B15);
const ui.Color _spruceTop = ui.Color(0xFF3E5147); // spruce lit from above
const ui.Color _stoneDark = ui.Color(0xFF6E645B);
const ui.Color _stoneLight = ui.Color(0xFF9C9086);
const ui.Color _hayBody = ui.Color(0xFFEDD9A3); // the flat art's hay
const ui.Color _hayTop = ui.Color(0xFFE3C98C);

// ---- ground -------------------------------------------------------------------------------

/// The green's ground: the diorama slab (the skirt of soil under the
/// lawn), the mown stripes, the walked line from tee to nest, water,
/// boost boards, portals, the well's pull field, the tee cup, and the
/// nest.
void _collectGround(
  List<PuttPaintable> out,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  final hole = scene.hole!;
  final bounds = hole.bounds;
  final time = scene.time;

  // The lawn's stripes, mown across the green.
  const stripe = 2.3;
  var index = 0;
  for (double y = bounds.min.y; y < bounds.max.y; y += stripe, index++) {
    final y1 = math.min(y + stripe + 0.02, bounds.max.y);
    final tint = index.isEven ? PuttPalette.cream : _lawnDark;
    final a = Vec2(bounds.min.x, y);
    final b = Vec2(bounds.max.x, y);
    final c = Vec2(bounds.max.x, y1);
    final d = Vec2(bounds.min.x, y1);
    out.add(PuttPaintable(
      camera.depthOf(_mid(a, c)),
      _rankGround,
      (canvas) =>
          canvas.drawPath(_groundQuad(camera, a, b, c, d), solidPaint(tint)),
    ));
  }

  // The cut edge of the green: an ink line around the bounds, painted as
  // the four sides so each rides its own depth.
  final edge = [
    Vec2(bounds.min.x, bounds.min.y),
    Vec2(bounds.max.x, bounds.min.y),
    Vec2(bounds.max.x, bounds.max.y),
    Vec2(bounds.min.x, bounds.max.y),
  ];
  for (var i = 0; i < 4; i++) {
    final p0 = edge[i];
    final p1 = edge[(i + 1) % 4];
    final center = _mid(p0, p1);
    final ink = strokePaint(PuttPalette.ink, camera.screenRadius(center, 0.22));
    out.add(PuttPaintable(
      camera.depthOf(center) + 0.01,
      _rankGround,
      (canvas) => canvas.drawPath(_closedGroundPath(camera, [p0, p1]), ink),
    ));
  }

  // A gentle walked path from tee to nest: the route as a read.
  final from = hole.tee;
  final to = hole.nest.position;
  if (from.distanceTo(to) > 0.5) {
    final dir = (to - from).normalized(Vec2(1, 0));
    final perp = dir.perpendicular;
    const half = 0.55;
    final corners = [
      from + perp * half,
      to + perp * half,
      to - perp * half,
      from - perp * half,
    ];
    out.add(PuttPaintable(
      camera.depthOf(_mid(from, to)),
      _rankGround,
      (canvas) => canvas.drawPath(
        _closedGroundPath(camera, corners),
        solidPaint(_lawnDark.withValues(alpha: 0.5)),
      ),
    ));
  }

  // The slab's soil skirt: the sides of the diorama, the ones facing the
  // camera only, hanging a shade below the lawn.
  const skirtDepth = 1.9;
  final slabCenterDepth = camera.depthOf(bounds.center);
  for (var i = 0; i < 4; i++) {
    final p0 = edge[i];
    final p1 = edge[(i + 1) % 4];
    final center = _mid(p0, p1);
    final faceDepth = camera.depthOf(center);
    if (faceDepth > slabCenterDepth + 0.05) continue; // faces away
    final tint = faceDepth < slabCenterDepth - 0.1 ? _soil : _soilDark;
    _collectQuadFace(
      out,
      camera,
      corners: [
        (p0, 0),
        (p1, 0),
        (p1, -skirtDepth),
        (p0, -skirtDepth),
      ],
      depth: faceDepth - 0.02,
      fill: tint,
      outline: 0.2,
    );
  }

  // Water: the shapes drawn flat on the ground, with drifting bands.
  for (final shape in hole.water) {
    _collectWater(out, camera, shape, time);
  }

  // Boost strips: a stone board with marching yolk chevrons.
  for (final strip in hole.boosts) {
    _collectBoost(out, camera, strip, time);
  }

  // Portals: dark burrows with glowing rims.
  for (final pair in hole.portals) {
    _collectPortal(out, camera, pair.a, pair.radius, time);
    _collectPortal(out, camera, pair.b, pair.radius, time + 1.6);
  }

  // The well's ground work: the pull's reach, its slow dust, and the
  // dark mouth the silo tank stands over (the tank is a volume).
  for (final well in hole.wells) {
    final center = well.position;
    out.add(PuttPaintable(
      camera.depthOf(center),
      _rankGround,
      (canvas) => canvas.drawPath(
        _groundCirclePath(camera, center, well.radius),
        solidPaint(const ui.Color(0x14150E08)),
      ),
    ));
    out.add(PuttPaintable(
      camera.depthOf(center) + 0.01,
      _rankGround,
      (canvas) {
        final dust = strokePaint(
            const ui.Color(0x590F0808), camera.screenRadius(center, 0.18));
        for (var i = 0; i < 3; i++) {
          final start = time * 2 + i * 2 * math.pi / 3;
          final points = [
            for (var k = 0; k <= 8; k++)
              _atAngle(
                  center, well.radius * 0.6, start + k / 8 * math.pi * 0.5),
          ];
          canvas.drawPath(_groundPath(camera, points), dust);
        }
      },
    ));
    out.add(PuttPaintable(
      camera.depthOf(center) + 0.02,
      _rankGround,
      (canvas) => canvas.drawPath(
        _groundCirclePath(camera, center, well.swallowRadius * 1.2),
        solidPaint(const ui.Color(0xFF1D1512)),
      ),
    ));
  }

  // The tee marker: a cream cup on the ground.
  final tee = hole.tee;
  final teeRadius = scene.eggRadius * 1.5;
  out.add(PuttPaintable(
    camera.depthOf(tee),
    _rankGround,
    (canvas) {
      canvas.drawPath(
        _groundCirclePath(camera, tee, teeRadius),
        solidPaint(PuttPalette.cream),
      );
      canvas.drawPath(
        _groundCirclePath(camera, tee, teeRadius),
        strokePaint(PuttPalette.ink, camera.screenRadius(tee, 0.16)),
      );
    },
  ));

  // The nest: straw strokes laid on the ground, the dark
  // want-in-there hole in the middle.
  final nest = hole.nest;
  final center = nest.position;
  final outer = nest.radius * 1.25;
  out.add(PuttPaintable(
    camera.depthOf(center),
    _rankGround,
    (canvas) {
      final strawWidth = camera.screenRadius(center, nest.radius * 0.34);
      final strawInk = strokePaint(PuttPalette.ink, strawWidth + 2.0);
      final straw = strokePaint(PuttPalette.yolk, strawWidth);
      final strawShade =
          strokePaint(const ui.Color(0xFFD3831F), strawWidth * 0.5);
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6 + time * 0.15;
        final direction = Vec2(math.cos(angle), math.sin(angle));
        final inner = camera.project(center + direction * (nest.radius * 0.55));
        final outerPoint = camera.project(center + direction * outer);
        canvas.drawLine(outerPoint, inner, strawInk);
        canvas.drawLine(outerPoint, inner, straw);
        if (i.isEven) {
          canvas.drawLine(
            outerPoint,
            camera.project(center + direction * (nest.radius * 0.7)),
            strawShade,
          );
        }
      }
      canvas.drawPath(
        _groundCirclePath(camera, center, nest.radius * 0.72),
        solidPaint(const ui.Color(0xFF2A2118)),
      );
      canvas.drawPath(
        _groundCirclePath(camera, center, nest.radius * 0.72),
        strokePaint(PuttPalette.ink, camera.screenRadius(center, 0.14)),
      );
    },
  ));
}

ui.Path _groundQuad(PuttCamera camera, Vec2 a, Vec2 b, Vec2 c, Vec2 d) =>
    _closedGroundPath(camera, [a, b, c, d]);

void _collectWater(
  List<PuttPaintable> out,
  PuttCamera camera,
  WaterShape shape,
  double time,
) {
  final (worldPoints, center) = switch (shape) {
    WaterCircle(:final center, :final radius) => (
        [
          for (var i = 0; i < 28; i++)
            _atAngle(center, radius, i / 28 * 2 * math.pi),
        ],
        center,
      ),
    WaterRect(:final rect) => (
        [
          rect.min,
          Vec2(rect.max.x, rect.min.y),
          rect.max,
          Vec2(rect.min.x, rect.max.y),
        ],
        rect.center,
      ),
    WaterPolygon(:final points) => (
        points,
        points.isEmpty ? Vec2.zero : points.reduce(_mid),
      ),
  };
  if (worldPoints.isEmpty) return;
  final path = _closedGroundPath(camera, worldPoints);
  final rimWidth = camera.screenRadius(center, 0.22);
  out.add(PuttPaintable(
    camera.depthOf(center),
    _rankGround,
    (canvas) {
      canvas.drawPath(path, solidPaint(PuttPalette.water));
      canvas.drawPath(path, strokePaint(PuttPalette.waterDeep, rimWidth));
      // The animated bands: highlights drifting across the water body,
      // clipped inside it so any shape reads as water.
      var minX = worldPoints.first.x;
      var maxX = minX;
      var minY = worldPoints.first.y;
      var maxY = minY;
      for (final point in worldPoints) {
        minX = math.min(minX, point.x);
        maxX = math.max(maxX, point.x);
        minY = math.min(minY, point.y);
        maxY = math.max(maxY, point.y);
      }
      canvas.save();
      canvas.clipPath(path);
      for (var i = 0; i < 3; i++) {
        final phase = (time * 0.3 + i / 3) % 1;
        final bandY = minY + (maxY - minY) * phase;
        final points = [
          for (var k = 0; k <= 8; k++)
            Vec2(
              minX + (maxX - minX) * k / 8,
              bandY + math.sin(k * 0.9 + time * 2 + i) * 0.18,
            ),
        ];
        canvas.drawPath(
          _groundPath(camera, points),
          strokePaint(
            PuttPalette.shell.withValues(alpha: (1 - phase) * 0.55),
            camera.screenRadius(center, 0.1),
          ),
        );
      }
      canvas.restore();
    },
  ));
}

void _collectBoost(
  List<PuttPaintable> out,
  PuttCamera camera,
  BoostStrip strip,
  double time,
) {
  final axis = (strip.to - strip.from).normalized(Vec2(1, 0));
  final perp = axis.perpendicular;
  final half = strip.width / 2;
  final length = (strip.to - strip.from).length;
  final corners = [
    strip.from + perp * half,
    strip.to + perp * half,
    strip.to - perp * half,
    strip.from - perp * half,
  ];
  final center = _mid(strip.from, strip.to);
  final pxWidth = camera.screenRadius(center, 0.22);
  out.add(PuttPaintable(
    camera.depthOf(center),
    _rankGround,
    (canvas) {
      final board = _closedGroundPath(camera, corners);
      canvas.drawPath(board, solidPaint(PuttPalette.stone));
      canvas.drawPath(board, strokePaint(PuttPalette.ink, pxWidth * 0.7));
      // The chevrons march along the strip.
      final chevron = strokePaint(PuttPalette.yolk, pxWidth);
      for (var i = 0; i < 4; i++) {
        final x = (length * 0.18 + i * length * 0.28 + time * 1.6) % length;
        final points = [
          strip.from + axis * (x - 0.35) + perp * (half * 0.6),
          strip.from + axis * (x + 0.35),
          strip.from + axis * (x - 0.35) - perp * (half * 0.6),
        ];
        canvas.drawPath(_groundPath(camera, points), chevron);
      }
    },
  ));
}

void _collectPortal(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 center,
  double radius,
  double time,
) {
  final breath = 0.14 + 0.08 * math.sin(time * 3.1);
  out.add(PuttPaintable(
    camera.depthOf(center),
    _rankGround,
    (canvas) {
      canvas.drawPath(
        _groundCirclePath(camera, center, radius),
        solidPaint(const ui.Color(0xFF1D1512)),
      );
      canvas.drawPath(
        _groundCirclePath(camera, center, radius),
        strokePaint(PuttPalette.ink, camera.screenRadius(center, 0.24)),
      );
      // The swirl: three arcs turning slowly.
      final swirl =
          strokePaint(PuttPalette.spruce, camera.screenRadius(center, 0.12));
      for (var i = 0; i < 3; i++) {
        final start = time * 1.5 + i * 2 * math.pi / 3;
        final points = [
          for (var k = 0; k <= 6; k++)
            _atAngle(center, radius * 0.6, start + k / 6 * math.pi * 0.6),
        ];
        canvas.drawPath(_groundPath(camera, points), swirl);
      }
      // The glow ring breathing around the burrow.
      canvas.drawPath(
        _groundCirclePath(camera, center, radius * 1.15),
        strokePaint(
          PuttPalette.cream.withValues(alpha: breath),
          camera.screenRadius(center, 0.16),
        ),
      );
      canvas.drawPath(
        _groundCirclePath(camera, center, radius * 1.15),
        strokePaint(
          PuttPalette.yolk.withValues(alpha: breath * 0.6),
          camera.screenRadius(center, 0.08),
        ),
      );
    },
  ));
}

// ---- volumes -----------------------------------------------------------------------------

/// The standing things: hedge boxes, bumper posts and rocks, the silo's
/// tank, the "?" crates, hay bales and fences.
void _collectVolumes(
  List<PuttPaintable> out,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  final hole = scene.hole!;
  for (final wall in hole.walls) {
    if (wall.bumper) {
      _collectBumperPosts(out, camera, wall.a, wall.b);
    } else {
      _collectHedgeBox(out, camera, wall.a, wall.b);
    }
  }
  for (final arc in hole.arcs) {
    final fullCircle = arc.sweep >= 2 * math.pi - 0.01;
    if (arc.bumper) {
      _collectBumperRock(out, camera, arc.center, arc.radius);
    } else if (fullCircle) {
      _collectRock(out, camera, arc.center, arc.radius);
    } else {
      // A hedge run bent along the arc: a chain of the same boxes.
      final steps = (arc.sweep * arc.radius / 1.1).ceil().clamp(1, 48).toInt();
      for (var i = 0; i < steps; i++) {
        final a0 = arc.startAngle + i / steps * arc.sweep;
        final a1 = arc.startAngle + (i + 1) / steps * arc.sweep;
        _collectHedgeBox(
          out,
          camera,
          _atAngle(arc.center, arc.radius, a0),
          _atAngle(arc.center, arc.radius, a1),
        );
      }
    }
  }
  for (final well in hole.wells) {
    _collectSilo(out, camera, well);
  }
  for (final box in hole.boxes) {
    _collectQuestionBox(out, camera, box, scene.time);
  }
  for (final decoration in hole.decorations) {
    switch (decoration.kind) {
      case 'hay':
      case 'hay_bale':
        _collectHayBale(
            out, camera, decoration.at, decoration.numbers['size'] ?? 1.0);
      case 'fence':
        _collectFence(out, camera, decoration);
      case 'tee_marker':
        // The tee cup is ground work; nothing to stand up.
        break;
      default:
        // Unknown tags rest as a pebble, so nothing smuggles in unseen.
        _collectRock(out, camera, decoration.at, 0.25);
    }
  }
}

/// One convex box: [base] corners (ground, walked in order around the
/// shape), [height] tall. Faces facing the camera pass the cull (their
/// depth sits nearer than the body's center); every kept face is its own
/// paintable, so the global depth sort runs at face granularity.
void _collectBoxVolume({
  required List<PuttPaintable> out,
  required PuttCamera camera,
  required List<Vec2> base,
  required double height,
  required ui.Color side,
  required ui.Color top,
  required double outline,
}) {
  var center = Vec2.zero;
  for (final point in base) {
    center = center + point;
  }
  center = center / base.length.toDouble();
  final centerDepth = camera.depthOf(center, height: height / 2);
  for (var i = 0; i < base.length; i++) {
    final b0 = base[i];
    final b1 = base[(i + 1) % base.length];
    final faceDepth = camera.depthOf(_mid(b0, b1));
    if (faceDepth > centerDepth + 0.02) continue; // faces away
    _collectQuadFace(
      out,
      camera,
      corners: [(b0, 0), (b1, 0), (b1, height), (b0, height)],
      depth: faceDepth,
      fill: side,
      outline: outline,
    );
  }
  // The lid, lit from above.
  _collectQuadFace(
    out,
    camera,
    corners: [for (final point in base) (point, height)],
    depth: camera.depthOf(center, height: height),
    fill: top,
    outline: outline,
  );
}

/// A hedge wall: a spruce box the egg cannot pass.
void _collectHedgeBox(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 a,
  Vec2 b,
) {
  const height = 1.35;
  const half = 0.5;
  final dir = (b - a).normalized(Vec2(1, 0));
  final perp = dir.perpendicular;
  _collectBoxVolume(
    out: out,
    camera: camera,
    base: [
      a + perp * half,
      b + perp * half,
      b - perp * half,
      a - perp * half,
    ],
    height: height,
    side: PuttPalette.spruce,
    top: _spruceTop,
    outline: 0.16,
  );
}

/// Bumper walls: a chain of short red posts, the yolk ring on each top.
void _collectBumperPosts(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 a,
  Vec2 b,
) {
  final length = a.distanceTo(b);
  final count = math.max(1, (length / 1.7).floor());
  for (var i = 0; i < count; i++) {
    final at = a + (b - a) * ((i + 0.5) / count);
    _collectBumperPost(out, camera, at);
  }
}

/// The bumper post the walls are built from: a short red drum, yolk
/// ring on top.
void _collectBumperPost(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 at, {
  double radius = 0.5,
  double height = 0.6,
}) {
  _collectCylinder(
    out,
    camera,
    center: at,
    radius: radius,
    height: height,
    side: PuttPalette.comb,
    top: PuttPalette.comb,
    topRing: PuttPalette.yolk,
  );
}

/// A bumper rock: the same short red drum as a wall's post, at the
/// authored radius.
void _collectBumperRock(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 center,
  double radius,
) {
  _collectBumperPost(
    out,
    camera,
    center,
    radius: radius,
    height: math.max(0.7, radius * 0.5),
  );
}

/// A vertical cylinder: the body from the near half of the top circle
/// down to the near half of the base, then the top face. [topRing], when
/// set, paints a ring on the top (the bumpers' yolk rim).
void _collectCylinder(
  List<PuttPaintable> out,
  PuttCamera camera, {
  required Vec2 center,
  required double radius,
  required double height,
  required ui.Color side,
  required ui.Color top,
  ui.Color? topRing,
}) {
  const samples = 18;
  final baseCircle = [
    for (var i = 0; i < samples; i++)
      _atAngle(center, radius, i / samples * 2 * math.pi),
  ];
  final centerScreen = camera.project(center);
  final depth = camera.depthOf(center);
  final outlineWidth = camera.screenRadius(center, 0.16);
  out.add(PuttPaintable(
    depth,
    _rankVolume,
    (canvas) {
      final topFront = <ui.Offset>[];
      final baseFront = <ui.Offset>[];
      for (final point in baseCircle) {
        final screen = camera.project(point, height: height);
        if (screen.dy >= centerScreen.dy) topFront.add(screen);
        final bottom = camera.project(point);
        if (bottom.dy >= centerScreen.dy) baseFront.add(bottom);
      }
      if (topFront.length > 1 && baseFront.length > 1) {
        final body = ui.Path()..moveTo(topFront.first.dx, topFront.first.dy);
        for (final screen in topFront.skip(1)) {
          body.lineTo(screen.dx, screen.dy);
        }
        for (final screen in baseFront.reversed) {
          body.lineTo(screen.dx, screen.dy);
        }
        body.close();
        canvas.drawPath(body, solidPaint(side));
        if (outlineWidth > 0.4) {
          canvas.drawPath(body, strokePaint(PuttPalette.ink, outlineWidth));
        }
      }
      // The top face, then its ring.
      final topPath = ui.Path();
      for (final (index, point) in baseCircle.indexed) {
        final screen = camera.project(point, height: height);
        if (index == 0) {
          topPath.moveTo(screen.dx, screen.dy);
        } else {
          topPath.lineTo(screen.dx, screen.dy);
        }
      }
      topPath.close();
      canvas.drawPath(topPath, solidPaint(top));
      if (outlineWidth > 0.4) {
        canvas.drawPath(topPath, strokePaint(PuttPalette.ink, outlineWidth));
      }
      if (topRing != null) {
        canvas.drawPath(
          _groundCirclePath(camera, center, radius * 0.62,
              height: height, samples: samples),
          strokePaint(topRing, camera.screenRadius(center, 0.3)),
        );
      }
    },
  ));
}

/// A plain rock: a domed stone blob.
void _collectRock(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 center,
  double radius,
) {
  const samples = 16;
  final depth = camera.depthOf(center);
  final centerY = camera.project(center).dy;
  final outlineWidth = camera.screenRadius(center, 0.14);
  out.add(PuttPaintable(
    depth,
    _rankVolume,
    (canvas) {
      final midRadius = radius * 0.78;
      final domeHeight = radius * 0.55;
      // The dome's side: the near half of the base up to the near half
      // of the crown ring.
      final body = ui.Path();
      var started = false;
      for (var i = 0; i <= samples; i++) {
        final screen =
            camera.project(_atAngle(center, radius, i / samples * 2 * math.pi));
        if (screen.dy >= centerY) {
          if (!started) {
            body.moveTo(screen.dx, screen.dy);
            started = true;
          } else {
            body.lineTo(screen.dx, screen.dy);
          }
        }
      }
      for (var i = samples; i >= 0; i--) {
        final screen = camera.project(
            _atAngle(center, midRadius, i / samples * 2 * math.pi),
            height: domeHeight);
        if (screen.dy >= centerY) body.lineTo(screen.dx, screen.dy);
      }
      if (started) {
        body.close();
        canvas.drawPath(body, solidPaint(_stoneDark));
        if (outlineWidth > 0.4) {
          canvas.drawPath(body, strokePaint(PuttPalette.ink, outlineWidth));
        }
      }
      final crown = _groundCirclePath(
        camera,
        center,
        midRadius,
        height: domeHeight,
        samples: samples,
      );
      canvas.drawPath(crown, solidPaint(_stoneLight));
      if (outlineWidth > 0.4) {
        canvas.drawPath(crown, strokePaint(PuttPalette.ink, outlineWidth));
      }
      // A chip of light, upper left of the crown.
      final chip = camera.project(
        _atAngle(center, midRadius * 0.4, math.pi * 1.15),
        height: domeHeight,
      );
      canvas.drawCircle(
        chip,
        camera.screenRadius(center, radius * 0.16),
        solidPaint(ui.Color.fromARGB(90, 255, 255, 255)),
      );
    },
  ));
}

/// The silo: the tall stone tank standing over the well's mouth.
void _collectSilo(
  List<PuttPaintable> out,
  PuttCamera camera,
  GravityWell well,
) {
  final tankRadius = well.radius * 0.3 + 0.2;
  final height = well.radius * 0.45 + 1.2;
  final center = well.position;
  _collectCylinder(
    out,
    camera,
    center: center,
    radius: tankRadius,
    height: height,
    side: PuttPalette.stone,
    top: _spruceTop,
  );
  // Two darker bands wrap the tank, and fresh dust drifts up around the
  // mouth. One paintable a hair nearer than the tank itself, so both
  // land on its face.
  final depth = camera.depthOf(center);
  final bandWidth = camera.screenRadius(center, 0.12);
  out.add(PuttPaintable(
    depth + 0.001,
    _rankVolume,
    (canvas) {
      final band = strokePaint(_stoneDark, bandWidth);
      for (final up in [0.45, 0.7]) {
        // Half the ring: the near side, where the wrap shows.
        final points = [
          for (var k = 0; k <= 10; k++)
            _atAngle(center, tankRadius, math.pi * k / 10),
        ];
        canvas.drawPath(_groundPath(camera, points, height: height * up), band);
      }
      final dust = strokePaint(
          const ui.Color(0x3D0F0808), camera.screenRadius(center, 0.16));
      for (var i = 0; i < 3; i++) {
        final angle = i * 2 * math.pi / 3 + camera.yaw;
        final points = [
          _atAngle(center, tankRadius * 1.5, angle),
          _atAngle(center, tankRadius * 1.8, angle + 0.4),
        ];
        canvas.drawPath(_groundPath(camera, points), dust);
      }
    },
  ));
}

/// The "?" egg-carton crate: a cream box with the mark on the faces
/// turned toward the camera.
void _collectQuestionBox(
  List<PuttPaintable> out,
  PuttCamera camera,
  QuestionBox box,
  double time,
) {
  final half = box.radius * 0.7;
  final height = box.radius * 1.5;
  final bob = math.sin(time * 2.4) * box.radius * 0.12;
  final lidHeight = height + bob;
  final base = [
    Vec2(box.position.x - half, box.position.y - half),
    Vec2(box.position.x + half, box.position.y - half),
    Vec2(box.position.x + half, box.position.y + half),
    Vec2(box.position.x - half, box.position.y + half),
  ];
  final center = box.position;
  final centerDepth = camera.depthOf(center, height: height / 2);
  final markFaces = <(Vec2, Vec2)>[];
  for (var i = 0; i < 4; i++) {
    final b0 = base[i];
    final b1 = base[(i + 1) % 4];
    final faceDepth = camera.depthOf(_mid(b0, b1));
    if (faceDepth > centerDepth + 0.02) continue;
    markFaces.add((b0, b1));
  }
  for (final (b0, b1) in markFaces) {
    _collectQuadFace(
      out,
      camera,
      corners: [(b0, 0), (b1, 0), (b1, lidHeight), (b0, lidHeight)],
      depth: camera.depthOf(_mid(b0, b1)),
      fill: PuttPalette.cream,
      outline: 0.18,
    );
    // The "?" on the face: mapped into the projected face with an
    // affine fit of the face's own corners (the projective wobble across
    // a crate face is invisible at this size).
    _collectFaceMark(out, camera,
        center: _mid(b0, b1), b0: b0, b1: b1, lidHeight: lidHeight);
  }
  // The lid: dimpled carton top.
  out.add(PuttPaintable(
    camera.depthOf(center, height: lidHeight),
    _rankVolume,
    (canvas) {
      final topPath =
          _groundCirclePath(camera, center, half * 1.06, height: lidHeight);
      canvas.drawPath(topPath, solidPaint(PuttPalette.cream));
      final outline = camera.screenRadius(center, 0.18);
      if (outline > 0.4) {
        canvas.drawPath(topPath, strokePaint(PuttPalette.ink, outline));
      }
      final dimple = strokePaint(
          const ui.Color(0xFFDFD2C2), camera.screenRadius(center, 0.08));
      for (final offset in [
        Vec2(-half * 0.5, -half * 0.2),
        Vec2(half * 0.5, -half * 0.2),
        Vec2(0, -half * 0.2),
        Vec2(0, half * 0.4),
      ]) {
        final at = camera.project(center + offset, height: lidHeight);
        canvas.drawCircle(
            at, camera.screenRadius(center, box.radius * 0.16), dimple);
      }
    },
  ));
}

/// The comb-red "?" for one crate face, as its own paintable at the
/// face's depth (so the mark sorts with the face).
void _collectFaceMark(
  List<PuttPaintable> out,
  PuttCamera camera, {
  required Vec2 center,
  required Vec2 b0,
  required Vec2 b1,
  required double lidHeight,
}) {
  final left = camera.project(b0);
  final right = camera.project(b1);
  final leftTop = camera.project(b0, height: lidHeight);
  if ((right - left).distance < 2 || (leftTop - left).distance < 2) {
    return; // edge-on: no face to write on
  }
  final depth = camera.depthOf(center);
  out.add(PuttPaintable(
    depth + 0.002,
    _rankVolume,
    (canvas) {
      canvas.save();
      canvas.translate(left.dx, left.dy);
      final ex = right - left;
      final ey = leftTop - left;
      final exLen = ex.distance;
      final eyLen = ey.distance;
      canvas.transform(Float64List.fromList([
        ex.dx / exLen, ex.dy / exLen, 0, 0, //
        ey.dx / eyLen, ey.dy / eyLen, 0, 0, //
        0, 0, 1, 0, //
        0, 0, 0, 1, //
      ]));
      final s = (exLen + eyLen) / 2; // the face's short-side pixel size
      final mark = strokePaint(PuttPalette.comb, s * 0.14)
        ..strokeCap = ui.StrokeCap.round;
      final path = ui.Path()
        ..moveTo(s * 0.34, s * 0.20)
        ..cubicTo(s * 0.34, s * 0.02, s * 0.66, s * 0.02, s * 0.66, s * 0.22)
        ..cubicTo(s * 0.66, s * 0.38, s * 0.52, s * 0.40, s * 0.52, s * 0.52);
      canvas.drawPath(path, mark);
      canvas.drawCircle(ui.Offset(s * 0.52, s * 0.64), s * 0.05, mark);
      canvas.restore();
    },
  ));
}

/// A hay bale: a fat amber roll standing on the yard.
void _collectHayBale(
  List<PuttPaintable> out,
  PuttCamera camera,
  Vec2 at,
  double scale,
) {
  _collectCylinder(
    out,
    camera,
    center: at,
    radius: 0.85 * scale,
    height: 1.05 * scale,
    side: _hayBody,
    top: _hayTop,
  );
  // Strand lines down the near face.
  final depth = camera.depthOf(at);
  final centerY = camera.project(at).dy;
  out.add(PuttPaintable(
    depth + 0.001,
    _rankVolume,
    (canvas) {
      final strand = strokePaint(
          const ui.Color(0xFFD8BC7F), camera.screenRadius(at, 0.08));
      for (final offset in [-0.35, 0.0, 0.35]) {
        final bottom = camera.project(at + Vec2(offset, 0.83 * scale));
        final top = camera.project(
          at + Vec2(offset * 0.8, 0.55 * scale),
          height: 1.0 * scale,
        );
        if (bottom.dy < centerY || top.dy < centerY) {
          continue; // strands only on the near face
        }
        canvas.drawLine(bottom, top, strand);
      }
    },
  ));
}

/// A fence line: spruce posts with two rails, from [decoration.at]
/// marching +x.
void _collectFence(
  List<PuttPaintable> out,
  PuttCamera camera,
  Decoration decoration,
) {
  final posts = (decoration.numbers['posts'] ?? 5).round();
  final spacing = decoration.numbers['length'] ?? 1.4;
  final at = decoration.at;
  final depth = camera.depthOf(at);
  for (final height in [0.62, 0.28]) {
    out.add(PuttPaintable(
      depth,
      _rankVolume,
      (canvas) {
        final from = camera.project(at, height: height);
        final last = camera.project(Vec2(at.x + (posts - 1) * spacing, at.y),
            height: height);
        canvas.drawLine(from, last,
            strokePaint(PuttPalette.ink, camera.screenRadius(at, 0.16)));
        canvas.drawLine(from, last,
            strokePaint(PuttPalette.spruce, camera.screenRadius(at, 0.1)));
      },
    ));
  }
  for (var i = 0; i < posts; i++) {
    final postAt = Vec2(at.x + i * spacing, at.y);
    _collectBoxVolume(
      out: out,
      camera: camera,
      base: [
        Vec2(postAt.x - 0.11, postAt.y - 0.11),
        Vec2(postAt.x + 0.11, postAt.y - 0.11),
        Vec2(postAt.x + 0.11, postAt.y + 0.11),
        Vec2(postAt.x - 0.11, postAt.y + 0.11),
      ],
      height: 0.85,
      side: PuttPalette.spruce,
      top: _spruceTop,
      outline: 0.1,
    );
  }
}

// ---- actors ------------------------------------------------------------------------------

/// The living things pasted over the diorama: shadows on the ground, the
/// eggs and the hen as billboards, the rooster host at the fence.
void _collectActors(
  List<PuttPaintable> out,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  final hole = scene.hole;

  // Shadows: elliptical by the projection itself, widening and fading
  // with height.
  for (final egg in scene.eggs) {
    final groundAt = egg.position;
    final shadowRadius = egg.radius * (1 + egg.height * 0.55);
    final alpha = (0.38 / (1 + egg.height * 1.1)).clamp(0.05, 0.6);
    out.add(PuttPaintable(
      camera.depthOf(groundAt),
      _rankShadow,
      (canvas) => canvas.drawPath(
        _groundCirclePath(camera, groundAt, shadowRadius),
        solidPaint(PuttPalette.ink.withValues(alpha: alpha)),
      ),
    ));
  }
  for (final hen in scene.hens) {
    out.add(PuttPaintable(
      camera.depthOf(hen.position),
      _rankShadow,
      (canvas) => canvas.drawPath(
        _groundCirclePath(camera, hen.position, hen.radius * 0.95),
        solidPaint(PuttPalette.ink.withValues(alpha: 0.30)),
      ),
    ));
  }

  // The eggs: the flat art standing at their ground spot.
  for (final egg in scene.eggs) {
    final baseScreen = camera.project(egg.position, height: egg.height);
    final depth = camera.depthOf(egg.position, height: egg.height);
    final radiusPx = camera.screenRadius(egg.position, egg.radius);
    final squash = (egg.speed / 28).clamp(0.0, 0.22).toDouble();
    out.add(PuttPaintable(
      depth,
      _rankActor,
      (canvas) => drawEgg(
        canvas,
        ui.Offset(baseScreen.dx, baseScreen.dy - radiusPx * 1.35),
        radiusPx,
        tint: egg.tint,
        squash: squash,
        look: _billboardLook(camera, egg),
      ),
    ));
  }

  // The hen, billboarded the same way.
  for (final hen in scene.hens) {
    final baseScreen = camera.project(hen.position);
    final radiusPx = camera.screenRadius(hen.position, hen.radius);
    out.add(PuttPaintable(
      camera.depthOf(hen.position),
      _rankActor,
      (canvas) => drawHen(
        canvas,
        ui.Offset(baseScreen.dx, baseScreen.dy - radiusPx * 1.0),
        radiusPx,
        phase: hen.phase,
      ),
    ));
  }

  // The rooster host at the green's far corner, bobbing at the fence.
  if (hole != null) {
    final bounds = hole.bounds;
    final at = Vec2(bounds.max.x + 0.8, bounds.min.y - 0.6);
    final baseScreen = camera.project(at);
    final scalePx = camera.screenRadius(at, 1.5);
    out.add(PuttPaintable(
      camera.depthOf(at),
      _rankActor,
      (canvas) => drawRoosterHead(
        canvas,
        ui.Offset(
          baseScreen.dx,
          baseScreen.dy -
              scalePx * 1.05 +
              math.sin(scene.time * 2) * scalePx * 0.08,
        ),
        scalePx,
        facing: -0.3,
      ),
    ));
  }
}

/// Where the egg's face leans, in screen space: the velocity dropped on
/// the ground a touch ahead, projected, normalized.
ui.Offset _billboardLook(PuttCamera camera, PuttEggView egg) {
  if (egg.speed < 0.5) return ui.Offset.zero;
  final here = camera.project(egg.position, height: egg.height);
  final ahead = camera.project(
    egg.position + egg.velocity * 0.12,
    height: egg.height,
  );
  final dx = ahead.dx - here.dx;
  final dy = ahead.dy - here.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 0.0001) return ui.Offset.zero;
  return ui.Offset(dx / length, dy / length);
}

// ---- aim ---------------------------------------------------------------------------------

/// The aim, drawn on the ground: the ghost of the pull behind the egg,
/// the power ring, and the arrow along the shot.
void _collectAim(
  List<PuttPaintable> out,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  final aim = scene.aim;
  if (aim == null) return;
  final origin = aim.origin;
  final pxWidth = camera.screenRadius(origin, 1.0);
  final direction = Vec2(math.cos(aim.angle), math.sin(aim.angle));
  final length = 1.5 + aim.power * 4.5;
  final tip = origin + direction * length;
  final depth = math.min(camera.depthOf(origin), camera.depthOf(tip));

  out.add(PuttPaintable(
    depth - 0.05,
    _rankActor,
    (canvas) {
      // The pull's ghost behind the egg.
      final pull = origin - direction * math.min(aim.dragLength, length);
      final ghost = strokePaint(const ui.Color(0x598FB4DA), pxWidth * 0.14);
      canvas.drawLine(camera.project(origin), camera.project(pull), ghost);

      // The power ring around the egg: a faint full ring, the yolk arc
      // filling from the top.
      final ringRadius = aim.eggRadius * 1.9;
      if (aim.power < 0.98) {
        canvas.drawPath(
          _groundCirclePath(camera, origin, ringRadius, samples: 28),
          strokePaint(const ui.Color(0x40211514), pxWidth * 0.22),
        );
      }
      final fillPoints = [
        for (var i = 0; i <= 22; i++)
          _atAngle(origin, ringRadius,
              -math.pi / 2 + i / 22 * 2 * math.pi * aim.power),
      ];
      canvas.drawPath(_groundPath(camera, fillPoints),
          strokePaint(PuttPalette.yolk, pxWidth * 0.24));

      // The shaft: ink underlay, comb over it.
      final originScreen = camera.project(origin);
      final tipScreen = camera.project(tip);
      final inkShaft = strokePaint(PuttPalette.ink, pxWidth * 0.62)
        ..strokeCap = ui.StrokeCap.round;
      final combShaft = strokePaint(PuttPalette.comb, pxWidth * 0.4)
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawLine(originScreen, tipScreen, inkShaft);
      canvas.drawLine(originScreen, tipScreen, combShaft);

      // The head, solid ink.
      final perp = Vec2(-direction.y, direction.x);
      final headBase = tip - direction * 0.7;
      final head = ui.Path()
        ..moveTo(tipScreen.dx, tipScreen.dy)
        ..lineTo(
          camera.project(headBase + perp * 0.42).dx,
          camera.project(headBase + perp * 0.42).dy,
        )
        ..lineTo(
          camera.project(headBase - perp * 0.42).dx,
          camera.project(headBase - perp * 0.42).dy,
        )
        ..close();
      canvas.drawPath(head, solidPaint(PuttPalette.ink));
    },
  ));
}

// ---- fx -----------------------------------------------------------------------------------

void _collectFx(
  List<PuttPaintable> out,
  PuttCamera camera,
  PuttSceneInput scene,
) {
  for (final fx in scene.fxs) {
    final progress = fx.progress.clamp(0.0, 1.0);
    final depthAt = camera.depthOf(fx.at);
    switch (fx.kind) {
      case PuttFxKind.droplet:
        final lift = 0.55 * math.sin(progress * math.pi);
        final at = camera.project(fx.at, height: lift);
        out.add(PuttPaintable(
          depthAt,
          _rankFx,
          (canvas) => drawDroplet(
              canvas, at, camera.screenRadius(fx.at, fx.size), progress),
        ));
      case PuttFxKind.sparkle:
        final lift = 0.35 + 0.45 * math.sin(progress * math.pi);
        final at = camera.project(fx.at, height: lift);
        out.add(PuttPaintable(
          depthAt,
          _rankFx,
          (canvas) => drawSparkle(
              canvas,
              at,
              camera.screenRadius(fx.at, fx.size),
              progress,
              fx.color ?? PuttPalette.yolk),
        ));
      case PuttFxKind.suction:
        final toward = fx.toward ?? fx.at;
        final drawn =
            fx.at + (toward + Vec2(0.2, 0.2) - fx.at) * (progress * progress);
        final radius = math.max(fx.size * (1 - progress), 0.02);
        final color = fx.color ?? PuttPalette.yolk;
        out.add(PuttPaintable(
          camera.depthOf(drawn),
          _rankFx,
          (canvas) => canvas.drawPath(
            _groundCirclePath(camera, drawn, radius),
            solidPaint(color.withValues(
                alpha: ((1 - progress) * 0.7).clamp(0.0, 1.0))),
          ),
        ));
      case PuttFxKind.poof:
        final radius = math.max(fx.size * (1 + progress), 0.02);
        final color = fx.color ?? PuttPalette.stone;
        out.add(PuttPaintable(
          depthAt,
          _rankFx,
          (canvas) => canvas.drawPath(
            _groundCirclePath(camera, fx.at, radius),
            solidPaint(color.withValues(
                alpha: ((1 - progress) * 0.7).clamp(0.0, 1.0))),
          ),
        ));
    }
  }
}
