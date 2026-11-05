// The camera's choreography over a hole, kept apart from the game's ticker:
// the whole hole while it opens, then - whenever the viewer's egg is at
// rest - the egg and the nest framed together, so the shot ahead always
// shows; the egg followed while it rolls; and once the egg is in (or for a
// spectator) the eggs still out there framed with the nest. The player can
// take the camera at any time (wheel, pinch, orbit): from then on, for the
// rest of the hole, the director keeps following but leaves the zoom alone.
// C (or the HUD's camera button) toggles the whole-hole view.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'putt_world3d.dart';

/// What the director needs to know about the green this frame.
class PuttCameraCue {
  final HoleDef? hole;
  final PuttPhase phase;

  /// The viewer's egg: where it is drawn, whether it rests, whether it is
  /// in the nest. Null for a spectator.
  final Vec2? myEgg;
  final bool myEggResting;
  final bool myEggHoled;

  /// Every other egg still out on the green, where it is drawn.
  final List<Vec2> otherEggs;

  /// Whether the viewer is dragging an aim (the frame must hold still).
  final bool aiming;

  /// The viewer's egg's velocity (the follow leads along it).
  final Vec2 myEggVelocity;

  const PuttCameraCue({
    required this.hole,
    required this.phase,
    this.myEgg,
    this.myEggResting = true,
    this.myEggHoled = false,
    this.otherEggs = const [],
    this.aiming = false,
    this.myEggVelocity = Vec2.zero,
  });
}

class PuttCameraDirector {
  PuttCameraDirector(this.rig);

  final PuttCameraRig rig;

  /// How tall my egg stands in world units (the view sets it from the
  /// egg's radius), and the least it should measure on screen at rest, so
  /// the putt is aimed at an egg, not a speck.
  double eggHeight = 1.1;
  static const double aimEggPixels = 30;

  /// How long the hole's overview holds before the camera comes in.
  static const double openingSeconds = 2.4;

  /// Whether the player asked their system for reduced motion: no
  /// opening sweep, the camera goes straight to the hole's play framing.
  bool reduceMotion = false;

  /// How long the camera stays in on the nest after the viewer's own egg
  /// drops in: the sink, the hatch, the chick's hops.
  static const double celebrateSeconds = 2.7;

  bool _wasHoled = false;
  double _celebrateUntil = 0;
  Vec2? _celebrateAt;

  /// Whether someone else drives the camera (the demo's held close-ups):
  /// the director then keeps its clock but moves nothing.
  bool held = false;

  /// Whether the hole's opening sweep is still on.
  bool get opening => !reduceMotion && _holeClock < openingSeconds;

  /// Seconds since the camera settled on the hole after its opening (a
  /// second's glide after the sweep; at once with reduced motion).
  double get settledFor =>
      _holeClock - (reduceMotion ? 0.3 : openingSeconds + 1.0);

  /// Whether the player asked for the whole hole (C, the HUD's button).
  bool get overview => _overview;
  bool _overview = false;

  /// Whether the camera is in close on the nest for my egg's hatch.
  bool get celebrating => _holeClock < _celebrateUntil;

  /// The hole the camera is directing, and for how long it has (seconds
  /// of frames, from the hole's first): the demo keeps its script on it.
  String? get holeId => _holeId;
  double get holeSeconds => _holeClock;

  String? _holeId;
  double _holeClock = 0;
  bool _userCamera = false;
  bool _framedRest = false;
  bool _wasRolling = false;
  double _sinceFieldFrame = 0;
  bool _showingBetween = false;
  Vec2? _follow;

  /// The point the rig's target glides toward this frame; null holds it.
  Vec2? get followPoint => _follow;

  /// Seconds the current hole has been up.
  double get holeClock => _holeClock;

  /// The player zoomed, pinched or orbited: leave the zoom to them for the
  /// rest of this hole.
  void noteUserCamera() => _userCamera = true;

  /// After a refit (a resize): the next rest frames the shot again, and
  /// between holes the whole green is asked for again.
  void reframe() {
    _framedRest = false;
    _showingBetween = false;
  }

  /// The whole hole, or back to the director's own framing.
  void toggleOverview() {
    _overview = !_overview;
    if (_overview) {
      rig.glideTo(
          distance: rig.overviewDistance, yaw: PuttCameraRig.defaultYaw);
    } else {
      _framedRest = false;
    }
  }

  /// The hole's entrance, driven frame by frame over [openingSeconds]: the
  /// camera starts low over the nest, turned a little, looking across it at
  /// the farm and the sky (the hour shows), holds there a breath, then
  /// rises and turns onto the whole green.
  void _sweep(HoleDef hole) {
    final t = (_holeClock / (openingSeconds - 0.3)).clamp(0.0, 1.0);
    // A held beat, then an ease-in-out climb.
    final k = t < 0.25 ? 0.0 : (t - 0.25) / 0.75;
    final eased = k * k * (3 - 2 * k);
    double lerp(double a, double b) => a + (b - a) * eased;
    final overviewDistance = rig.overviewDistance;
    rig
      ..aimAt(
        yaw: lerp(PuttCameraRig.defaultYaw + 0.55, PuttCameraRig.defaultYaw),
        pitchDeg: lerp(15, PuttCameraRig.pitchDefault),
        distance: lerp(overviewDistance * 0.92, overviewDistance),
        target: hole.nest.position.lerp(hole.bounds.center, eased),
      )
      ..snap();
  }

  /// The orbit that turns the camera partway behind [from], looking down
  /// the line to [to]: half the turn from the hole's own view, never more
  /// than about 45 degrees, so the shot's direction reads while the hole
  /// keeps the orientation everyone shares.
  double _yawToward(Vec2 from, Vec2 to) {
    final line = to - from;
    if (line.length < 1e-3) return PuttCameraRig.defaultYaw;
    // The camera's away axis is (sin yaw, cos yaw) in x/z.
    final along = math.atan2(line.x, line.y);
    var turn = along - PuttCameraRig.defaultYaw;
    turn = math.atan2(math.sin(turn), math.cos(turn)); // into (-pi, pi]
    return PuttCameraRig.defaultYaw + (turn * 0.5).clamp(-0.8, 0.8);
  }

  void update(double dt, PuttCameraCue cue) {
    final hole = cue.hole;
    if (hole == null) {
      _follow = null;
      return;
    }
    if (hole.id != _holeId) {
      _holeId = hole.id;
      _holeClock = 0;
      _userCamera = false;
      _framedRest = false;
      _wasRolling = false;
      _sinceFieldFrame = 0;
      _showingBetween = false;
      _wasHoled = false;
      _celebrateUntil = 0;
    }
    _holeClock += dt;
    if (held) {
      _follow = null;
      return;
    }
    final center = hole.bounds.center;

    // My egg just dropped in: the camera comes in on the nest for the
    // hatch (unless the player took the camera), then frames the rest.
    if (cue.myEggHoled && !_wasHoled && !_userCamera) {
      _celebrateUntil = _holeClock + celebrateSeconds;
      // From higher up (less of what stands between the camera and the
      // nest), the nest a little below the middle, under the banner.
      final away = Vec2(math.sin(rig.yawTarget), math.cos(rig.yawTarget));
      // The nest low in the frame and the flag short from up here: both
      // under the banner across the top.
      _celebrateAt = hole.nest.position + away * 2.4;
      rig.glideTo(
        target: _celebrateAt,
        distance: math.max(rig.overviewDistance * 0.36, 9.5),
        pitchDeg: 56,
      );
    }
    _wasHoled = cue.myEggHoled;
    if (_holeClock < _celebrateUntil) {
      _follow = _celebrateAt ?? hole.nest.position;
      return;
    }
    if (_celebrateUntil > 0) {
      _celebrateUntil = 0;
      _sinceFieldFrame = 0;
      rig.glideTo(
          pitchDeg: PuttCameraRig.pitchDefault, yaw: PuttCameraRig.defaultYaw);
    }

    // Between holes, and while the hole opens: the whole green.
    if (cue.phase != PuttPhase.holePlay) {
      _follow = center;
      if (!_showingBetween) {
        _showingBetween = true;
        rig.glideTo(
            distance: rig.overviewDistance, yaw: PuttCameraRig.defaultYaw);
      }
      return;
    }
    _showingBetween = false;
    if (opening) {
      _sweep(hole);
      _follow = null;
      return;
    }
    if (_overview) {
      _follow = center;
      return;
    }
    if (cue.aiming) {
      _follow = null;
      return;
    }

    final egg = cue.myEgg;
    if (egg != null && !cue.myEggHoled) {
      if (!cue.myEggResting) {
        // Rolling: ride with it, a little farther out than the rest framing
        // if that was tight, so the way ahead shows.
        if (!_wasRolling && !_userCamera) {
          rig.glideTo(
              distance:
                  math.max(rig.distanceTarget, rig.overviewDistance * 0.62));
        }
        _wasRolling = true;
        _framedRest = false;
        // A lead along the roll (at most four units), so the way ahead
        // shows more than the way behind.
        final lead = cue.myEggVelocity * 0.28;
        _follow =
            egg + (lead.length > 4 ? lead.normalized(Vec2.zero) * 4.0 : lead);
        return;
      }
      _wasRolling = false;
      _follow = null;
      if (!_framedRest) {
        _framedRest = true;
        if (_userCamera) {
          rig.glideTo(target: egg.lerp(hole.nest.position, 0.35));
        } else {
          // My egg, the eggs around mine (the tee's crowd) and the nest, so
          // none of them sits under the HUD - as long as my egg stays big
          // enough to aim at (aimEggPixels tall). A nest too far for that
          // gives way to the stretch toward it, the egg low in the frame;
          // the HUD points at the nest, and C still shows the whole hole.
          final yaw = _yawToward(egg, hole.nest.position);
          final crowd = [
            egg,
            for (final other in cue.otherEggs)
              if (other.distanceTo(egg) < 5) other,
          ];
          final cap = rig.distanceForHeight(eggHeight, aimEggPixels);
          // The frame may come in as close as the cap asks.
          final closest = math.min(0.42, cap / rig.overviewDistance);
          var ahead = hole.nest.position;
          if (rig.fitDistance([...crowd, ahead], yaw: yaw, closest: closest) >
              cap) {
            final way = hole.nest.position - egg;
            final along = way.normalized(const Vec2(0, -1));
            var lo = 0.0, hi = way.length;
            for (var i = 0; i < 14; i++) {
              final mid = (lo + hi) / 2;
              if (rig.fitDistance([...crowd, egg + along * mid],
                      yaw: yaw, closest: closest) <=
                  cap) {
                lo = mid;
              } else {
                hi = mid;
              }
            }
            ahead = egg + along * lo;
          }
          rig.glideToFramePoints([...crowd, ahead], yaw: yaw, closest: closest);
        }
      }
      return;
    }

    // In the nest already (or watching): the eggs still out, with the nest.
    _follow = null;
    _sinceFieldFrame -= dt;
    if (_sinceFieldFrame > 0) return;
    _sinceFieldFrame = 0.6;
    final others = cue.otherEggs;
    if (others.isEmpty) {
      rig.glideTo(target: hole.nest.position);
      return;
    }
    final points = [hole.nest.position, ...others];
    if (_userCamera) {
      var sum = Vec2.zero;
      for (final p in points) {
        sum += p;
      }
      rig.glideTo(target: sum / points.length.toDouble());
    } else {
      rig.glideToFramePoints(points, margin: 4);
    }
  }
}
