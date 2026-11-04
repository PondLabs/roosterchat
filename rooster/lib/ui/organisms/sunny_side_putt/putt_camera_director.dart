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

  const PuttCameraCue({
    required this.hole,
    required this.phase,
    this.myEgg,
    this.myEggResting = true,
    this.myEggHoled = false,
    this.otherEggs = const [],
    this.aiming = false,
  });
}

class PuttCameraDirector {
  PuttCameraDirector(this.rig);

  final PuttCameraRig rig;

  /// How long the hole's overview holds before the camera comes in.
  static const double openingSeconds = 2.4;

  /// Whether the player asked for the whole hole (C, the HUD's button).
  bool get overview => _overview;
  bool _overview = false;

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

  /// The whole hole, or back to the director's own framing.
  void toggleOverview() {
    _overview = !_overview;
    if (_overview) {
      rig.glideTo(distance: rig.overviewDistance);
    } else {
      _framedRest = false;
    }
  }

  /// The hole's entrance: the camera starts high over the nest, turned a
  /// little, and sweeps down and round to the whole green.
  void _sweepIn(HoleDef hole) {
    final overviewDistance = rig.overviewDistance;
    rig
      ..aimAt(
        yaw: PuttCameraRig.defaultYaw + 0.75,
        pitchDeg: PuttCameraRig.pitchMax,
        distance: overviewDistance * 1.35,
        target: hole.nest.position,
      )
      ..snap()
      ..glideTo(
        yaw: PuttCameraRig.defaultYaw,
        pitchDeg: PuttCameraRig.pitchDefault,
        distance: overviewDistance,
        target: hole.bounds.center,
      );
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
      _sweepIn(hole);
    }
    _holeClock += dt;
    final center = hole.bounds.center;

    // Between holes, and while the hole opens: the whole green.
    if (cue.phase != PuttPhase.holePlay) {
      _follow = center;
      if (!_showingBetween) {
        _showingBetween = true;
        rig.glideTo(distance: rig.overviewDistance);
      }
      return;
    }
    _showingBetween = false;
    if (_holeClock < openingSeconds || _overview) {
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
        _follow = egg;
        return;
      }
      _wasRolling = false;
      _follow = null;
      if (!_framedRest) {
        _framedRest = true;
        if (_userCamera) {
          rig.glideTo(target: egg.lerp(hole.nest.position, 0.35));
        } else {
          rig.glideToFrame(egg, hole.nest.position);
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
    var minX = hole.nest.position.x;
    var minY = hole.nest.position.y;
    var maxX = minX;
    var maxY = minY;
    for (final p in others) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    if (_userCamera) {
      rig.glideTo(target: Vec2((minX + maxX) / 2, (minY + maxY) / 2));
    } else {
      rig.glideToFrame(Vec2(minX, minY), Vec2(maxX, maxY), margin: 4);
    }
  }
}
