// The aim of Sunny Side Putt: press on (or near) your egg, drag away like a
// slingshot, release to strike. The drag points BACK along the shot, mini
// golf style: pull south, the egg flies north.
//
// This file holds the pure math, so the feel is unit-testable without a
// game, a screen or a pointer: the slingshot angle, the power curve whose
// exponent is tuned so flicks feel crisp (a half-way drag already gives two
// thirds of full power, and only a near-zero pull cancels the shot), and
// the aim arrow's sinusoidal wobble - the visible tell of the wobble the
// rules engine rolls into the real shot, gone when Hawk Eye is up.
//
// The controller never touches Flutter or Flame: the game feeds it world
// coordinates from pointer events and reads [state] to draw; the game adds
// [visualWobble] to the drawn angle on every frame it renders.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

/// One frame of the aim while dragging.
class AimState {
  /// The angle the shot will fire at, radians, in the core's convention
  /// (atan2, y down), WITHOUT the visual wobble.
  final double angle;

  /// Power in 0..1 that [angle] and [power] carry into the engine.
  final double power;

  /// Drag distance in world units, unclamped, for the power meter.
  final double dragLength;

  const AimState({
    required this.angle,
    required this.power,
    required this.dragLength,
  });

  /// The angle to DRAW the arrow at: [angle] plus this frame's sway.
  double visualAngle(double wobble) => angle + wobble;
}

/// The press/drag/release state machine of a stroke.
///
/// A stroke goes: [begin] at press, [update] as the pointer moves, [commit]
/// at release (null when the pull was too small - a tap never fires an
/// egg). [cancel] aborts cleanly. Mouse and touch arrive as the same world
/// coordinates, so one machine drives both.
class AimController {
  /// Drag distance (world units) that is full power.
  final double maxDragLength;

  /// Drag exponent: power `= t ^ exponent` for `t` the clamped drag
  /// fraction. Below 1 favors flicks: half the windup keeps 66% of full
  /// power, so quick wrist-flicks are not punished.
  final double powerExponent;

  /// Pulls shorter than this (world units) cancel the shot on release.
  static const double deadZone = 0.8;

  /// Frequency (Hz) of the arrow's sway while the aim wobbles.
  static const double wobbleHz = 1.6;

  /// The wobble the engine may roll into a real shot (see
  /// `PuttConfig.wobbleMaxRadians`); the arrow's sway mirrors it. The
  /// owning view keeps this in sync with the engine's config.
  final double wobbleAmplitude;

  AimController({
    this.maxDragLength = 8.0,
    this.powerExponent = 0.6,
    this.wobbleAmplitude = 0.055,
  });

  /// Set while Hawk Eye (or any no-wobble modifier) covers the shot: the
  /// arrow holds dead still, because the shot will be dead straight.
  bool noWobble = false;

  /// Where the drag started - the egg's world position at press.
  Vec2? origin;

  /// The current aim, or null when not dragging.
  AimState? state;

  bool get isActive => origin != null;

  /// Distance the pointer has pulled from the origin, unclamped.
  double get dragLength => state?.dragLength ?? 0;

  /// Starts a drag at [pointer] (the egg's world position; the pointer
  /// offset from the egg matters only relative to later updates, so any
  /// starting point works).
  void begin(Vec2 pointer) {
    origin = pointer;
    state = null;
  }

  /// Moves the drag; aims opposite to the pull, powers by the curve.
  void update(Vec2 pointer) {
    final origin = this.origin;
    if (origin == null) return;
    final pull = origin - pointer;
    final dragLength = pull.length;
    final angle = dragLength < Vec2.epsilon ? 0.0 : pull.angle;
    state = AimState(
      angle: angle,
      power: powerFor(dragLength),
      dragLength: dragLength,
    );
  }

  /// The arrow's sway in radians at [elapsed] seconds into the drag.
  /// Sinusoidal (a steady back-and-forth read of the risk), zero while
  /// [noWobble] holds. Pure: same time in, same angle out.
  double visualWobble(double elapsed) {
    if (noWobble) return 0;
    final omega = 2 * math.pi * wobbleHz;
    return math.sin(omega * elapsed) * wobbleAmplitude;
  }

  /// Releases the drag. Returns (angle, power) for the engine, or null
  /// when the pull was inside the dead zone (a tap, not a putt).
  ({double angle, double power})? commit() {
    final state = this.state;
    origin = null;
    this.state = null;
    if (state == null || state.dragLength < deadZone) return null;
    return (angle: state.angle, power: state.power);
  }

  /// Cancels the drag (pointer left the area, hole ended mid-aim...).
  void cancel() {
    origin = null;
    state = null;
  }

  /// Applies the drag-then-exponent power curve, clamped into 0..1.
  double powerFor(double dragLength) {
    final t = (dragLength / maxDragLength).clamp(0.0, 1.0);
    return math.pow(t, powerExponent).toDouble();
  }
}
