// The 3D camera of Sunny Side Putt: a pinhole camera hovering over the
// planar game world. The physics stays planar (x, y on the ground, a
// height coordinate only lifts things toward the viewer); this file owns
// everything about how that ground plane becomes pixels: orbit yaw and
// tilt pitch, the zoom distance, the point the camera looks at, and the
// two-way projection between world and screen.
//
// The model, in the camera's own frame: the camera sits [distance] world
// units from the target, tilted down by [pitchDeg] degrees (90 would be
// straight overhead), turned around the vertical by [yaw]. A world point
// (x, y, z) is translated by the target, rotated by yaw (the plan's own
// clockwise sense), then split into a camera-right axis, an away axis and
// the height; the perspective divide by the depth does the rest. Nothing
// here runs Flame or GL: same numbers on every platform, unit-testable
// with a plain `flutter test`.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

/// The orbit camera: state, easing, and the world<->screen projection.
///
/// The camera owns its motion: gestures ([orbitBy], [zoomByWheel],
/// [setDistance]) write targets, [update] eases the live state toward
/// them, and [fitToHole] frames a hole and clamps the zoom range. The
/// target point follows the player's egg when the game asks for it, and
/// recenters on the green when the hole changes ([fitToHole] sets the
/// target to the bounds' center).
class PuttCamera {
  PuttCamera({this.viewport = const ui.Size(800, 600)});

  /// The pitch range in degrees: 35 = low oblique with the horizon in
  /// reach, 70 = looking steeply down; 90 (straight overhead) is not
  /// offered, the diorama needs the tilt.
  static const double pitchMin = 35;
  static const double pitchMax = 70;
  static const double pitchDefault = 55;

  /// Focal length as a multiple of the viewport height; 1.2 is a 45-deg
  /// field of view, wide enough to hold a course and tight enough that
  /// perspective reads.
  static const double focalFactor = 1.2;

  /// The depth a projection may divide by at the very least, keeping a
  /// point that would land behind or in the camera plane sane instead of
  /// flipping through negative coordinates.
  static const double _depthGuard = 0.4;

  /// The pixels the projection draws in. The game sets this on resize.
  ui.Size viewport;

  /// The orbit angle around the vertical, radians; unbounded, new drags
  /// add to it (no snap-back wrap).
  double yaw = 0;

  /// The tilt from the ground plane, degrees, in [pitchMin, pitchMax].
  double pitchDeg = pitchDefault;

  /// The camera's distance from the target, in world units.
  double distance = 30;

  /// The world point under the middle of the screen.
  Vec2 target = Vec2.zero;

  double _yawTarget = 0;
  double _pitchTarget = pitchDefault;
  double _distanceTarget = 30;
  Vec2 _targetTarget = Vec2.zero;

  /// The zoom clamp, set by [fitToHole] from the hole's size.
  double _distanceMin = 8;
  double _distanceMax = 160;

  /// The first [fitToHole] snaps instead of easing: boot must not play a
  /// swoop from the defaults.
  bool _snapNext = true;

  /// Focal length in pixels for the current viewport.
  double get focal => viewport.height * focalFactor;

  /// The game hands its canvas size over on resize.
  void setViewport(ui.Size size) => viewport = size;

  /// Project a world point to screen pixels. [height] lifts the point
  /// toward the camera (an egg in a Chicken Hop, a crate's lid); the
  /// ground plane is height 0.
  ui.Offset project(Vec2 world, {double height = 0}) {
    final (u, w, depth) = _cameraSpace(world, height);
    final f = focal;
    return ui.Offset(
      viewport.width / 2 + f * u / depth,
      viewport.height / 2 - f * (w * _sp + height * _cp) / depth,
    );
  }

  /// The sorted-paint key for a world point: how far it sits from the
  /// camera. Larger = farther = painted first; ties are broken by rank
  /// (see the renderer's ordering).
  double depthOf(Vec2 world, {double height = 0}) {
    final (_, _, depth) = _cameraSpace(world, height);
    return depth;
  }

  /// The screen radius a world circle at [at] paints with: pixels per
  /// world unit at that depth, times [worldRadius].
  double screenRadius(Vec2 at, double worldRadius, {double height = 0}) {
    final (_, _, depth) = _cameraSpace(at, height);
    return focal * worldRadius / depth;
  }

  /// The ground point under [screen]: the inverse of [project] on the
  /// height-0 plane. Null when the pixel misses the ground entirely (a
  /// click at the sky above the horizon) - the caller does nothing.
  Vec2? screenToWorld(ui.Offset screen) {
    final f = focal;
    final sx = screen.dx - viewport.width / 2;
    final sy = screen.dy - viewport.height / 2;
    // Ground (height 0) ties the two divide equations together; solve
    // the away-axis from the vertical one first.
    final denominator = f * _sp + sy * _cp;
    if (denominator.abs() < 1.0) return null; // ray parallel to the ground
    final w = -sy * distance / denominator;
    final depth = distance + w * _cp;
    if (depth <= _depthGuard) return null;
    final u = sx * depth / f;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final dx = c * u + s * w;
    final dy = -s * u + c * w;
    return Vec2(target.x + dx, target.y + dy);
  }

  /// Frames [bounds] on screen: distance so the green fits (the host
  /// standing off the far corner included), target at the green's
  /// center, and the zoom clamps from the hole's size. Only the first
  /// call in a camera's life snaps; later calls ease.
  void fitToHole(Rect bounds) {
    final c = math.cos(yaw).abs();
    final s = math.sin(yaw).abs();
    final spanRight = bounds.width * c + bounds.height * s;
    final spanAway = bounds.width * s + bounds.height * c;
    final maxSpan = math.max(spanRight, spanAway);
    // The billboard heights and the host add a fixed margin around the
    // green; keep a finger's width of viewport to spare.
    const margin = 5.0;
    final usableWidth = math.max(1.0, viewport.width - 24);
    final usableHeight = math.max(1.0, viewport.height - 24);
    final scaleNeeded = math.min(
      usableWidth / (spanRight + margin),
      usableHeight / (spanAway * _sp + margin + 2.2),
    );
    final wanted = focal / scaleNeeded;
    _distanceMin = 0.55 * maxSpan;
    _distanceMax = 2.8 * maxSpan;
    _distanceTarget = wanted.clamp(_distanceMin, _distanceMax).toDouble();
    _targetTarget = bounds.center;
    if (_snapNext) _snap();
  }

  /// Orbit the camera: [dxFactor] pixels of horizontal drag turn the yaw,
  /// vertical drag tilts the pitch (clamped). Dragging down looks from
  /// higher above.
  void orbitBy(double dxFactor, double dyFactor) {
    _yawTarget += dxFactor * 0.006;
    _pitchTarget = (_pitchTarget + dyFactor * 0.11).clamp(pitchMin, pitchMax);
  }

  /// Zoom by a mouse-wheel tick; positive scroll (down) moves the camera
  /// out.
  void zoomByWheel(double delta) {
    _distanceTarget = (_distanceTarget * math.exp(delta * 0.0011))
        .clamp(_distanceMin, _distanceMax)
        .toDouble();
  }

  /// Pinch zoom: the gesture hands the live scale against its start and
  /// the camera's distance when the pinch began; fingers closing (scale
  /// under 1) move the camera closer.
  void pinch(double scale, {required double distanceAtGestureStart}) {
    _distanceTarget = (distanceAtGestureStart / scale)
        .clamp(_distanceMin, _distanceMax)
        .toDouble();
  }

  /// Set the zoom distance directly (world units).
  void setDistance(double worldDistance) {
    _distanceTarget =
        worldDistance.clamp(_distanceMin, _distanceMax).toDouble();
  }

  /// Ease the camera one frame. [followPoint], when given, is the point
  /// the target glides toward (the player's egg); leave it out to hold
  /// the target where it is (while aiming, between holes).
  void update(double dt, {Vec2? followPoint}) {
    if (followPoint != null) _targetTarget = followPoint;
    if (_snapNext) _snap();
    const yawSpeed = 7.0;
    const pitchSpeed = 8.0;
    const distanceSpeed = 5.0;
    const targetSpeed = 6.0;
    final yawK = 1 - math.exp(-yawSpeed * dt);
    final pitchK = 1 - math.exp(-pitchSpeed * dt);
    final distanceK = 1 - math.exp(-distanceSpeed * dt);
    final targetK = 1 - math.exp(-targetSpeed * dt);
    yaw += (_yawTarget - yaw) * yawK;
    pitchDeg += (_pitchTarget - pitchDeg) * pitchK;
    distance += (_distanceTarget - distance) * distanceK;
    target = Vec2(
      target.x + (_targetTarget.x - target.x) * targetK,
      target.y + (_targetTarget.y - target.y) * targetK,
    );
  }

  /// Copy every target into the live state at once.
  void _snap() {
    yaw = _yawTarget;
    pitchDeg = _pitchTarget;
    distance = _distanceTarget.clamp(_distanceMin, _distanceMax).toDouble();
    target = _targetTarget;
    _snapNext = false;
  }

  double get _pitch => pitchDeg * math.pi / 180;
  double get _cp => math.cos(_pitch);
  double get _sp => math.sin(_pitch);

  /// The point in the camera's own frame: the camera-right axis (u), the
  /// away axis (w), and the clamped depth the perspective divides by.
  (double, double, double) _cameraSpace(Vec2 world, double height) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final dx = world.x - target.x;
    final dy = world.y - target.y;
    final u = dx * c - dy * s;
    final w = dx * s + dy * c;
    final depth =
        (distance + w * _cp - height * _sp).clamp(_depthGuard, 1e9).toDouble();
    return (u, w, depth);
  }
}
