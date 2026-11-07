// The aim of Sunny Side Putt: press on (or near) your egg, drag away like a
// slingshot, release to strike. The drag points BACK along the shot, mini
// golf style: pull south, the egg flies north.
//
// This file holds the pure math, so the feel is unit-testable without a
// game, a screen or a pointer: the slingshot angle, the power curve whose
// exponent is tuned so flicks feel crisp (a half-way drag already gives two
// thirds of full power, and only a near-zero pull cancels the shot), and
// the aim's sway - the shot fires at the angle the aim shows at release.
// A soft or quick putt holds still; the sway only grows into a hard pull
// held a while (nerves), and Hawk Eye stills it.
//
// The controller never touches Flutter or Flame: the game feeds it world
// coordinates from pointer events and reads [state] to draw; the game adds
// [visualWobble] to the drawn angle on every frame it renders.
//
// The keyboard drives the same state without a pointer: [hold] sets an
// angle and a power outright (the state reads as the pull that would give
// that power), [turnBy] and [stepPower] move them, and the release is the
// same [commit], so the row, the guide and the sway behave alike.
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

  /// The angle to DRAW the aim at: [angle] plus this frame's sway.
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

  /// Frequency (Hz) of the aim's sway while it wobbles.
  static const double wobbleHz = 1.6;

  /// Below this power the aim holds still: a soft putt is a steady one.
  /// From here the sway grows in, reaching [wobbleAmplitude] at full power.
  static const double steadyPower = 0.4;

  /// The arrow holds still this long into a pull (a quick, sure putt never
  /// shakes), then the sway grows in over [swayRampSeconds].
  static const double steadySeconds = 0.8;
  static const double swayRampSeconds = 1.0;

  /// How far the arrow sways at full power, held (see
  /// `PuttConfig.wobbleMaxRadians`); the shot fires at the swayed angle the
  /// arrow shows at release. The owning view keeps this in sync with the
  /// engine's config.
  double wobbleAmplitude;

  AimController({
    this.maxDragLength = 8.0,
    this.powerExponent = 0.6,
    this.wobbleAmplitude = 0.035,
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

  /// The arrow's sway in radians at [elapsed] seconds into a pull of
  /// [power]. A steady back-and-forth (a read of the risk) whose reach
  /// grows with the power above [steadyPower] and with the time held past
  /// [steadySeconds]; zero while [noWobble] holds. Pure: the same time and
  /// power in, the same angle out.
  double visualWobble(double elapsed, {double power = 1}) {
    if (noWobble) return 0;
    final reach = _ease((power - steadyPower) / (1 - steadyPower)) *
        _ease((elapsed - steadySeconds) / swayRampSeconds);
    if (reach == 0) return 0;
    final omega = 2 * math.pi * wobbleHz;
    return math.sin(omega * elapsed) * wobbleAmplitude * reach;
  }

  /// The sway of the pull under way at [elapsed] (0 when not pulling).
  double swayNow(double elapsed) {
    final state = this.state;
    if (state == null) return 0;
    return visualWobble(elapsed, power: state.power);
  }

  static double _ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
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

  // ---- the keyboard's aim ----------------------------------------------------

  /// One press of Left or Right turns the aim this far (radians); with
  /// Shift held, [keyFineTurnStep].
  static const double keyTurnStep = 3 * math.pi / 180;
  static const double keyFineTurnStep = 0.5 * math.pi / 180;

  /// One press of Up or Down moves the power this much.
  static const double keyPowerStep = 0.05;

  /// The power a keyboard aim starts at: the middle of the stroke.
  static const double keyPowerStart = 0.5;

  /// The softest keyboard putt: the first [keyPowerStep] a pull just out
  /// of the [deadZone] reaches (a softer one is a tap, and fires nothing).
  double get keyPowerMin {
    final steps = (powerFor(deadZone) / keyPowerStep - 1e-9).ceil();
    return steps * keyPowerStep;
  }

  /// Holds an aim from [egg] at [angle] with [power] (clamped into
  /// [keyPowerMin]..1), no pointer involved: the keyboard's way in. An aim
  /// already under way keeps its origin.
  void hold(Vec2 egg, {required double angle, required double power}) {
    origin ??= egg;
    _set(angle, power);
  }

  /// Turns the held aim by [radians] (positive turns clockwise on screen:
  /// the core's angles grow with y down).
  void turnBy(double radians) {
    final state = this.state;
    if (state == null) return;
    _set(state.angle + radians, state.power);
  }

  /// Moves the held aim's power by [steps] of [keyPowerStep], snapped to
  /// the step so presses never drift between grid points.
  void stepPower(int steps) {
    final state = this.state;
    if (state == null) return;
    final at = (state.power / keyPowerStep).round();
    _set(state.angle, (at + steps) * keyPowerStep);
  }

  void _set(double angle, double power) {
    final clamped = power.clamp(keyPowerMin, 1.0);
    state = AimState(
      angle: math.atan2(math.sin(angle), math.cos(angle)),
      power: clamped,
      dragLength: dragFor(clamped),
    );
  }

  /// The pull (world units) that gives [power]: the curve run backwards.
  double dragFor(double power) =>
      maxDragLength * math.pow(power.clamp(0.0, 1.0), 1 / powerExponent);

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
