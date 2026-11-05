// The farm's birds up close. The host and the hens are built from the same
// parts: legs on scaly shanks, three toes forward and a short one back,
// each toe knuckled and clawed; feathers cut as blades with a rounded or a
// pointed tip, laid like shingles along a wing's edge; and the rooster's
// sickles, arching over his tail. Everything pours into merged geometry,
// so a bird stays a few meshes however many feathers it wears.
part of '../putt_world3d.dart';

/// The birds' own colours (sRGB).
abstract final class _Bird {
  // The plumage: white, the wings a shade warmer, the hens' tips cream.
  static const white = 0xFCF8F1;
  static const covert = 0xF4ECDF;
  static const wing = 0xEDE3D3;
  static const flight = 0xE3D6C2;
  static const hackle = 0xF3DCAD;
  static const hackleLight = 0xF8EBD2;
  static const cream = 0xEEDFC8;

  // The rooster's tail: near-black, and the green of its sheen.
  static const sickle = 0x1F2622;
  static const sheen = 0x2E5A45;

  // Legs and feet: yellow-orange scales, darker claws, a pale spur.
  static const leg = 0xF7A928;
  static const legDeep = 0xE08A18;
  static const claw = 0x6B4729;
  static const spur = 0xEAD3A2;
}

// ---- blades ----------------------------------------------------------------------

/// A blade swept along [path], points in its own x/y plane: round each
/// point an ellipse [widths] across the path (in the plane) and [depths]
/// through it (along z), both ends closed. Feathers, sickles and toes are
/// these.
tjs.BufferGeometry _sweep(
  List<(double, double)> path,
  List<double> widths,
  List<double> depths, {
  int sides = 8,
}) {
  final count = path.length;
  final positions = <double>[];
  final normals = <double>[];
  final indices = <int>[];
  (double, double) along(int i) {
    final (ax, ay) = path[math.max(0, i - 1)];
    final (bx, by) = path[math.min(count - 1, i + 1)];
    final length = math.max(
        1e-9, math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
    return ((bx - ax) / length, (by - ay) / length);
  }

  for (var i = 0; i < count; i++) {
    final (x, y) = path[i];
    final (tx, ty) = along(i);
    final a = widths[i] / 2;
    final b = depths[i] / 2;
    for (var k = 0; k < sides; k++) {
      final angle = k / sides * math.pi * 2;
      final c = math.cos(angle);
      final s = math.sin(angle);
      // Across the path, in the plane, is (-ty, tx); through it is z.
      positions
        ..add(x - ty * a * c)
        ..add(y + tx * a * c)
        ..add(b * s);
      // The ellipse's own normal, its gradient: (cos / a, sin / b).
      var nx = -ty * c * b;
      var ny = tx * c * b;
      var nz = s * a;
      var length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length < 1e-12) {
        nx = -ty * c;
        ny = tx * c;
        nz = s;
        length = 1;
      }
      normals
        ..add(nx / length)
        ..add(ny / length)
        ..add(nz / length);
    }
  }
  for (var i = 0; i < count - 1; i++) {
    for (var k = 0; k < sides; k++) {
      final next = (k + 1) % sides;
      final a = i * sides + k;
      final b = i * sides + next;
      final c = (i + 1) * sides + next;
      final d = (i + 1) * sides + k;
      indices.addAll([a, b, c, a, c, d]);
    }
  }
  // Each end closed by a fan round its middle.
  final first = count * sides;
  final last = first + 1;
  final (x0, y0) = path.first;
  final (x1, y1) = path.last;
  final (t0x, t0y) = along(0);
  final (t1x, t1y) = along(count - 1);
  positions.addAll([x0, y0, 0, x1, y1, 0]);
  normals.addAll([-t0x, -t0y, 0, t1x, t1y, 0]);
  final tip = (count - 1) * sides;
  for (var k = 0; k < sides; k++) {
    final next = (k + 1) % sides;
    indices
      ..addAll([first, next, k])
      ..addAll([last, tip + k, tip + next]);
  }
  return tjs.BufferGeometry()
    ..setIndex(indices)
    ..setAttributeFromString(
        'position', tjs.Float32BufferAttribute.fromList(positions, 3, false))
    ..setAttributeFromString(
        'normal', tjs.Float32BufferAttribute.fromList(normals, 3, false));
}

/// Where a feather's blade is sampled, from its base (0) to its tip (1):
/// closer together toward the tip, so a rounded end comes out round.
const List<double> _featherSteps = [
  0,
  0.2,
  0.42,
  0.62,
  0.77,
  0.88,
  0.95,
  0.988,
  1,
];

/// A cut feather, [length] long and [width] across at its widest: the
/// quill widening into the vane, then a rounded tip, or a [pointed] one;
/// [bend] of its length bowed toward -y. Built along +x, flat in its x/y
/// plane (its broad face toward z), [depth] thick.
tjs.BufferGeometry _feather(
  double length,
  double width, {
  double? depth,
  bool pointed = false,
  double bend = 0,
  int sides = 6,
}) {
  final thick = depth ?? width * 0.2;
  final path = <(double, double)>[];
  final widths = <double>[];
  final depths = <double>[];
  for (final t in _featherSteps) {
    path.add((t * length, -math.sin(t * math.pi) * bend * length));
    double w;
    if (t <= 0.6) {
      w = 0.5 + 0.5 * math.sin(t / 0.6 * math.pi / 2);
    } else {
      final k = (t - 0.6) / 0.4;
      w = pointed
          ? math.pow(1 - k, 1.1).toDouble()
          : math.sqrt(math.max(0.0, 1 - k * k));
    }
    widths.add(width * w);
    depths.add(thick * (1 - 0.45 * t) * math.min(1.0, w * 3));
  }
  return _sweep(path, widths, depths, sides: sides);
}

/// A sickle feather: a long blade along an arc, setting off along +x and
/// curling [curl] radians round toward +y, widest a quarter of the way
/// and tapering to a point. Flat in its x/y plane, [depth] thick.
tjs.BufferGeometry _sickle(
  double length,
  double width,
  double curl, {
  double? depth,
  int steps = 12,
  int sides = 6,
}) {
  final radius = length / math.max(curl, 1e-3);
  final thick = depth ?? width * 0.2;
  final path = <(double, double)>[];
  final widths = <double>[];
  final depths = <double>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final a = curl * t;
    path.add((radius * math.sin(a), radius * (1 - math.cos(a))));
    final w = t < 0.25
        ? 0.55 + 0.45 * math.sin(t / 0.25 * math.pi / 2)
        : math.pow(1 - (t - 0.25) / 0.75, 0.8).toDouble();
    widths.add(width * w);
    depths.add(thick * (1 - 0.5 * t) * math.min(1.0, w * 3));
  }
  return _sweep(path, widths, depths, sides: sides);
}

/// A placement at ([x], [y], [z]) whose x axis runs along [along] and
/// whose z axis faces [face] (squared to [along]): a blade built along x
/// and flat in its x/y plane lies along [along], its broad face toward
/// [face].
tjs.Matrix4 _aimed(
    double x, double y, double z, tjs.Vector3 along, tjs.Vector3 face) {
  final ax = along.clone()..normalize();
  final az = face.clone()
    ..sub(ax.clone()..scale(face.dot(ax)))
    ..normalize();
  final ay = az.clone()..cross(ax);
  return tjs.Matrix4().makeBasis(ax, ay, az)..setPosition(x, y, z);
}

/// [local] placed inside [frame].
tjs.Matrix4 _within(tjs.Matrix4 frame, tjs.Matrix4 local) =>
    frame.clone()..multiply(local);

// ---- legs ------------------------------------------------------------------------

/// One bird leg into [into], placed by [frame]: the hip at its origin, the
/// sole on y = -[length], the toes toward +x, the outer toe splaying to
/// [outward] (+1 or -1 along z). A feathered drumstick in [feather] hangs
/// [thigh] of the way down (none without a colour); under it the shank,
/// [shank] thick at the top, in [bands] of scales that overlap downward;
/// three toes forward (the middle one [toe] long) and a short one back,
/// each in [knuckles] pieces with a claw; and a rooster's spur when
/// [spur].
void _birdLeg(
  _Merged into,
  tjs.Matrix4 frame, {
  required double length,
  required double shank,
  required double toe,
  required double outward,
  int? feather,
  double thigh = 0.2,
  int bands = 5,
  int knuckles = 3,
  bool spur = false,
  int sides = 8,
}) {
  if (feather != null) {
    // Full at the top, tapering into the hock.
    into
      ..add(
          tjs.SphereGeometry(1, sides + 4, math.max(5, sides - 1)),
          _within(
              frame,
              _place(length * 0.02, -length * thigh, 0,
                  sx: shank * 2.4, sy: length * 0.19, sz: shank * 2.3)),
          feather)
      ..add(
          tjs.SphereGeometry(1, sides + 2, math.max(5, sides - 2)),
          _within(
              frame,
              _place(length * 0.04, -length * (thigh + 0.1), 0,
                  sx: shank * 1.6, sy: length * 0.1, sz: shank * 1.5)),
          feather);
  }
  // The shank, from the hock down to the ankle, leaning a little: each
  // band of scales flares at its foot over the next and darkens toward
  // that edge.
  final hockX = length * 0.05;
  final hockY = -length * (thigh + 0.16);
  final ankleX = length * 0.1;
  final ankleY = -length * 0.9;
  final lean = math.atan2(ankleX - hockX, hockY - ankleY);
  final run = math.sqrt((ankleX - hockX) * (ankleX - hockX) +
      (ankleY - hockY) * (ankleY - hockY));
  for (var i = 0; i < bands; i++) {
    final t = (i + 0.5) / bands;
    final top = shank * (1 - 0.2 * i / bands);
    into.add(
        tjg.CylinderGeometry(top, top * 1.14, run / bands * 1.1, sides),
        _within(
            frame,
            _place(
                hockX + (ankleX - hockX) * t, hockY + (ankleY - hockY) * t, 0,
                roll: lean)),
        i.isEven ? _Bird.leg : _Bird.legDeep,
        baseShade: 0.8);
  }
  if (spur) {
    // Low on the back of the shank, curving back and a little up.
    final atX = hockX + (ankleX - hockX) * 0.62 - shank * 0.8;
    final atY = hockY + (ankleY - hockY) * 0.62;
    final height = shank * 1.8;
    const angle = math.pi - 0.45;
    into.add(
        tjg.ConeGeometry(shank * 0.38, height, math.max(5, sides - 2)),
        _within(
            frame,
            _place(atX + math.cos(angle) * height * 0.45,
                atY + math.sin(angle) * height * 0.45, 0,
                roll: angle - math.pi / 2)),
        _Bird.spur);
  }
  // The foot: a pad under the ankle, three toes forward and one back.
  final toeRadius = shank * 0.76;
  into.add(
      tjs.SphereGeometry(1, sides, math.max(4, sides ~/ 2 + 1)),
      _within(
          frame,
          _place(ankleX, -length + toeRadius * 1.1, 0,
              sx: toeRadius * 1.9, sy: toeRadius * 1.3, sz: toeRadius * 1.9)),
      _Bird.legDeep);
  for (final (yaw, reach, lift) in [
    (0.0, toe, 0.0),
    (-outward * 0.6, toe * 0.8, 0.0),
    (outward * 0.62, toe * 0.78, 0.0),
    (math.pi - outward * 0.3, toe * 0.36, toeRadius * 0.35),
  ]) {
    _birdToe(into, _within(frame, _place(ankleX, -length, 0, yaw: yaw)), reach,
        toeRadius,
        lift: lift, knuckles: knuckles, sides: math.max(5, sides - 2));
  }
}

/// One toe along +x from the ankle (its frame's origin, on the ground):
/// [knuckles] pieces tapering from [radius], each swelling at its root,
/// to a dark claw hooked down at the tip; [lift] raises its root (the
/// back toe).
void _birdToe(
  _Merged into,
  tjs.Matrix4 frame,
  double length,
  double radius, {
  double lift = 0,
  int knuckles = 3,
  int sides = 6,
}) {
  double heightAt(double t) => lift * (1 - t) + radius * (1 - 0.45 * t);
  double radiusAt(double t) => radius * (1 - 0.42 * t);
  for (var i = 0; i < knuckles; i++) {
    final from = math.max(0.0, i / knuckles - 0.03);
    final to = (i + 1) / knuckles;
    final path = <(double, double)>[];
    final widths = <double>[];
    for (var j = 0; j <= 3; j++) {
      final t = from + (to - from) * j / 3;
      path.add((t * length, heightAt(t)));
      final swell = j == 0 ? 1.16 : (j == 1 ? 1.06 : 1.0);
      widths.add(2 * radiusAt(t) * swell);
    }
    into.add(
        _sweep(path, widths, [for (final w in widths) w * 1.08], sides: sides),
        frame.clone(),
        i.isOdd ? _Bird.legDeep : _Bird.leg,
        baseShade: 0.86);
  }
  // Pointing down just enough for its tip to touch the ground.
  const angle = -0.35;
  final claw = radius * 1.7;
  into.add(
      tjg.ConeGeometry(radiusAt(1) * 0.85, claw, sides),
      _within(
          frame,
          _place(length + math.cos(angle) * claw * 0.42,
              heightAt(1) + math.sin(angle) * claw * 0.42, 0,
              roll: angle - math.pi / 2)),
      _Bird.claw);
}

// ---- the host -------------------------------------------------------------------

/// The host's body into [into], in his own frame (forward +x, up +y, the
/// ground at y = 0): body and breast, the neck, two legs (the near one a
/// step ahead), the hackles falling over his shoulders and his tail
/// fanned up behind.
void _roosterBody(_Merged into) {
  const white = _Bird.white;
  into
    ..add(tjs.SphereGeometry(1, 24, 16),
        _place(-0.1, 4.3, 0, roll: 0.1, sx: 2.6, sy: 2.15, sz: 2.0), white,
        baseShade: 0.82)
    ..add(tjs.SphereGeometry(1, 20, 14),
        _place(1.45, 4.75, 0, sx: 1.7, sy: 1.85, sz: 1.6), white)
    ..add(tjg.CylinderGeometry(0.85, 1.25, 2.4, 14),
        _place(1.9, 6.3, 0, roll: -0.35), white);
  for (final (side, ahead) in const [(-1.0, 0.16), (1.0, -0.14)]) {
    _birdLeg(into, _place(0.25 + ahead, 2.6, side * 0.9),
        length: 2.6,
        shank: 0.22,
        toe: 1.3,
        outward: side,
        feather: white,
        thigh: 0.14,
        spur: true);
  }
  // The hackles: a cream-gold cape of long pointed feathers falling from
  // under his head over the neck and the shoulders, round the back and
  // the sides, their points a zig-zag along its edge.
  for (var k = 0; k < 11; k++) {
    final around = -2.0 + k * 4.0 / 10; // 0 at the back of the neck
    final out = tjs.Vector3(-math.cos(around), 0, math.sin(around));
    final along = tjs.Vector3(-0.3, -1, 0)..add(out.clone()..scale(0.42));
    final face = out.clone()..add(tjs.Vector3(0, 0.35, 0));
    into.add(
        _feather(k.isEven ? 1.85 : 1.6, 0.72,
            depth: 0.12, pointed: true, bend: out.z >= 0 ? 0.05 : -0.05),
        _aimed(2.12 + out.x * 0.9, 7.0, out.z * 0.9, along, face),
        k.isEven ? _Bird.hackle : _Bird.hackleLight);
  }
  // The saddle: long pointed feathers draping from his back over the
  // wings' ends, before the tail.
  for (final side in [-1.0, 1.0]) {
    for (var k = 0; k < 3; k++) {
      into.add(
          _feather(1.6 - k * 0.12, 0.6,
              depth: 0.11, pointed: true, bend: side * 0.06),
          _aimed(
              -1.25 - k * 0.4,
              6.1 - k * 0.14,
              side * (1.0 - k * 0.1),
              tjs.Vector3(-0.8, -1, side * 0.12),
              tjs.Vector3(-0.2, 0.55, side)),
          k.isEven ? _Bird.hackleLight : _Bird.white);
    }
  }
  // The tail: broad coverts at the root, then the sickles arching up and
  // over, near-black with his green sheen.
  final ink = _hexOf(PuttPalette.ink);
  final spruce = _hexOf(PuttPalette.spruce);
  for (var i = 0; i < 5; i++) {
    final across = i / 4 - 0.5;
    into.add(
        _feather(1.75 - across.abs() * 0.4, 0.8, depth: 0.14),
        _place(-2.2, 5.3, across * 0.9,
            roll: 2.2 + across.abs() * 0.3, yaw: across * 0.5),
        i.isEven ? ink : spruce);
  }
  for (final (z, rise, curl, length, width, hex) in [
    (-0.42, 1.95, 1.7, 3.0, 0.52, ink),
    (-0.26, 1.72, 2.1, 3.8, 0.6, spruce),
    (-0.08, 1.55, 2.5, 4.7, 0.7, ink),
    (0.1, 1.62, 2.45, 4.5, 0.68, _Bird.sheen),
    (0.27, 1.8, 2.0, 3.7, 0.6, _Bird.sickle),
    (0.43, 2.0, 1.65, 3.0, 0.52, spruce),
    (0.0, 2.3, 1.3, 2.6, 0.6, _Bird.sheen),
  ]) {
    into.add(_sickle(length, width, curl, depth: 0.12),
        _place(-2.35, 5.45, z, roll: rise, yaw: z * 0.35), hex);
  }
}

/// One of the host's wings, folded, in its shoulder's frame ([side] +1 or
/// -1 along z): rounded coverts over the top, the secondaries hanging
/// under them (their rounded tips scallop the wing's lower edge, each a
/// little inside the one before), and the long pointed primaries layered
/// along its back edge, out past the body under the tail.
void _roosterWing(_Merged into, double side) {
  into.add(
      tjs.SphereGeometry(1, 16, 12),
      _place(-0.35, -0.3, side * 0.25,
          tilt: side * 0.12, roll: 0.15, sx: 1.35, sy: 0.68, sz: 0.32),
      _Bird.covert);
  final face = tjs.Vector3(0, 0.12, side);
  for (var j = 0; j < 4; j++) {
    into.add(
        _feather(1.6 + j * 0.15, 0.56,
            depth: 0.12, pointed: true, bend: side * 0.05),
        _aimed(-0.9 - j * 0.22, -0.5 - j * 0.06, side * (0.4 - j * 0.05),
            tjs.Vector3(-1, -0.5 + j * 0.04, -side * 0.4), face),
        _Bird.flight);
  }
  for (var i = 0; i < 6; i++) {
    into.add(
        _feather(1.35 + i * 0.06, 0.74, depth: 0.13, bend: side * 0.04),
        _aimed(0.75 - i * 0.42, -0.55 - i * 0.03, side * (0.54 - i * 0.035),
            tjs.Vector3(-0.42 - i * 0.1, -1, -side * (0.06 + i * 0.06)), face),
        i.isEven ? _Bird.wing : _Bird.covert);
  }
}

// ---- the hens -----------------------------------------------------------------

/// A hen's build, in her size: how high her hips stand, and where her
/// head's middle sits (her body is built round them).
const double _henHip = 0.63;
const double _henHeadY = 1.93;
const double _henHeadZ = 0.85;

/// A hen's body into [into], placed by [frame] (forward +z, the ground at
/// y = 0), [r] her size: plump and white, her breast out front, a folded
/// wing on each side with its feathers cut along the lower edge, and a
/// small cream tail cocked up behind. [small] for the yard's hens, seen
/// from afar: fewer facets.
void _henBody(_Merged into, tjs.Matrix4 frame, double r, {bool small = false}) {
  // Her body rides a little over her hips, her legs showing under it.
  final body = _within(frame, _place(0, r * (_henHip - 0.55), 0));
  into
    ..add(
        tjs.SphereGeometry(1, small ? 12 : 20, small ? 8 : 14),
        _within(body,
            _place(0, r * 1.05, 0, sx: r * 0.92, sy: r * 0.82, sz: r * 1.1)),
        _Bird.white,
        baseShade: 0.8)
    ..add(
        tjs.SphereGeometry(1, small ? 10 : 16, small ? 7 : 12),
        _within(
            body,
            _place(0, r * 1.2, r * 0.55,
                sx: r * 0.62, sy: r * 0.68, sz: r * 0.6)),
        _Bird.white);
  final sides = small ? 5 : 6;
  for (final side in [-1.0, 1.0]) {
    // The folded wing: rounded coverts on top, sloping to the tail; the
    // long primaries tucked along the back; and the secondaries hanging
    // under the coverts, their rounded tips a scalloped edge.
    into.add(
        tjs.SphereGeometry(1, small ? 8 : 14, small ? 6 : 10),
        _within(
            body,
            _place(side * r * 0.82, r * 1.27, r * 0.02,
                tilt: -0.2, sx: r * 0.17, sy: r * 0.28, sz: r * 0.56)),
        _Bird.covert);
    final face = tjs.Vector3(side, 0.15, 0);
    for (var j = 0; j < 3; j++) {
      into.add(
          _feather(r * (0.45 + j * 0.06), r * 0.25,
              depth: r * 0.06, bend: side * 0.05, sides: sides),
          _within(
              body,
              _aimed(
                  side * r * (0.86 - j * 0.04),
                  r * (1.12 - j * 0.03),
                  -r * (0.22 + j * 0.12),
                  tjs.Vector3(-side * 0.25, -0.12, -1),
                  face)),
          _Bird.flight);
    }
    for (var i = 0; i < 5; i++) {
      into.add(
          _feather(r * (0.5 + i * 0.03), r * 0.32,
              depth: r * 0.065, bend: side * 0.04, sides: sides),
          _within(
              body,
              _aimed(
                  side * r * (0.95 - i * 0.03),
                  r * (1.14 - i * 0.015),
                  r * (0.4 - i * 0.18),
                  tjs.Vector3(-side * 0.3, -1, -(0.45 + i * 0.12)),
                  face)),
          i.isEven ? _Bird.cream : _Bird.wing);
    }
  }
  // The tail: a little fan, its rounded tips spread from back to up.
  for (var i = 0; i < 5; i++) {
    final k = i / 4;
    final rise = 0.3 + k * 1.0;
    into.add(
        _feather(r * (0.6 + (0.5 - (k - 0.5).abs()) * 0.24), r * 0.32,
            depth: r * 0.08, sides: sides),
        _within(
            body,
            _aimed(
                (k - 0.5) * r * 0.1,
                r * (1.28 + k * 0.16),
                -r * (0.86 - k * 0.12),
                tjs.Vector3(0, math.sin(rise), -math.cos(rise)),
                tjs.Vector3(1, 0, 0))),
        i.isEven ? _Bird.cream : _Bird.white);
  }
}

/// A hen's head into [into], placed by [frame] (its middle at the origin,
/// forward +z), [r] her size: a little comb of three rounded points, the
/// beak's upper half over a shorter lower one, two wattle lobes under it,
/// and the eyes (with a glint, unless [small]).
void _henHead(_Merged into, tjs.Matrix4 frame, double r, {bool small = false}) {
  final comb = _hexOf(PuttPalette.comb);
  final yolk = _hexOf(PuttPalette.yolk);
  final ink = _hexOf(PuttPalette.ink);
  into
    ..add(tjs.SphereGeometry(r * 0.42, small ? 10 : 16, small ? 8 : 12),
        frame.clone(), _Bird.white)
    ..add(
        tjg.ConeGeometry(r * 0.14, r * 0.38, 8),
        _within(frame, _place(0, -r * 0.02, r * 0.5, tilt: math.pi / 2 + 0.12)),
        yolk)
    ..add(
        tjg.ConeGeometry(r * 0.09, r * 0.22, 8),
        _within(frame, _place(0, -r * 0.12, r * 0.45, tilt: math.pi / 2 - 0.2)),
        _shade(yolk, 0.9));
  for (final side in [-1.0, 1.0]) {
    into.add(
        tjs.SphereGeometry(r * 0.1, small ? 6 : 10, small ? 5 : 8),
        _within(frame,
            _place(side * r * 0.05, -r * 0.27, r * 0.33, sy: 1.5, sz: 0.8)),
        comb);
  }
  for (final (z, y, s) in const [
    (0.14, 0.4, 0.15),
    (-0.06, 0.47, 0.16),
    (-0.24, 0.4, 0.12)
  ]) {
    into.add(tjs.SphereGeometry(r * s, small ? 6 : 10, small ? 5 : 8),
        _within(frame, _place(0, r * y, r * z, sx: 0.55)), comb);
  }
  for (final side in [-1.0, 1.0]) {
    into.add(tjs.SphereGeometry(r * 0.07, 8, 6),
        _within(frame, _place(side * r * 0.3, r * 0.08, r * 0.24)), ink);
    if (!small) {
      into.add(
          tjs.SphereGeometry(r * 0.025, 6, 5),
          _within(frame, _place(side * r * 0.35, r * 0.11, r * 0.28)),
          _Bird.white);
    }
  }
}

/// One of a hen's legs into [into], placed by [frame] (her hip at its
/// origin, forward +z), on her [side] (+1 or -1 along x): a fluffy
/// drumstick under the belly, the scaly shank, the toes.
void _henLeg(_Merged into, tjs.Matrix4 frame, double r, double side,
        {bool small = false}) =>
    _birdLeg(
        into,
        // The leg is built facing +x: a quarter turn faces it forward.
        _within(frame, _place(0, 0, 0, yaw: -math.pi / 2)),
        length: r * _henHip,
        shank: r * 0.085,
        toe: r * 0.42,
        outward: -side,
        feather: _Bird.white,
        thigh: 0.42,
        bands: small ? 3 : 4,
        knuckles: small ? 2 : 3,
        sides: small ? 5 : 7);
