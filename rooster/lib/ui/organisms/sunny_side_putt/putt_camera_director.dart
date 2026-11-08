// The camera's choreography over a hole, kept apart from the game's ticker:
// the whole hole while it opens, then - for the whole hole - one framing
// from right behind the viewer's egg on the tee, looking down the line to
// the nest, the egg dead centre, which only ever pans with the egg, as
// Putt Party has it; and once the egg is in, the nest it went in, kept. The
// camera is always on the viewer's own egg: another player's putt never
// takes it. A spectator, with no egg of their own, watches the field
// instead: the egg rolling, else the nearest, kept until another putts or
// it drops in. The player can take the camera at any time (wheel, pinch,
// orbit): from then on, for the rest of the hole, the director keeps
// following but leaves the zoom alone. C (or the HUD's camera button)
// toggles the whole-hole view, until my next putt.
library;

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'putt_world3d.dart';

/// Another player's egg still out on the green, as the director sees it.
class PuttCameraEgg {
  final String id;

  /// Where it is drawn.
  final Vec2 position;
  final Vec2 velocity;
  final bool resting;

  /// Its player's strokes this hole: one more is a putt (a hen or an egg
  /// bumping it moves it too, but is no putt, and never takes the camera).
  final int strokes;

  const PuttCameraEgg(this.id, this.position,
      {this.velocity = Vec2.zero, this.resting = true, this.strokes = 0});
}

/// What the director needs to know about the green this frame.
class PuttCameraCue {
  final HoleDef? hole;
  final PuttPhase phase;

  /// The viewer's egg: where it is drawn, whether it rests, whether it is
  /// in the nest. Null for a spectator.
  final Vec2? myEgg;
  final bool myEggResting;
  final bool myEggHoled;

  /// Every other egg still out on the green.
  final List<PuttCameraEgg> otherEggs;

  /// Whether the viewer is dragging an aim (the frame must hold still).
  final bool aiming;

  /// Where the host stands beside this hole (the opening's shot keeps him
  /// in the frame); null when he is not built yet.
  final Vec2? host;

  /// The strokes the viewer took in this hole: one more is a putt of mine
  /// (another egg knocking mine moves it too, but is no putt).
  final int myStrokes;

  const PuttCameraCue({
    required this.hole,
    required this.phase,
    this.myEgg,
    this.myEggResting = true,
    this.myEggHoled = false,
    this.otherEggs = const [],
    this.aiming = false,
    this.host,
    this.myStrokes = 0,
  });
}

class PuttCameraDirector {
  PuttCameraDirector(this.rig);

  final PuttCameraRig rig;

  /// How tall my egg stands in world units (the view sets it from the
  /// egg's radius), and how tall it should measure on screen, so the putt
  /// is aimed at an egg, not a speck.
  double eggHeight = 1.1;
  static const double aimEggPixels = 40;

  /// The hatch's close-up: how far out the camera stands, and how low it
  /// looks (degrees).
  static const double celebrateDistance = 12.5;
  static const double celebratePitch = 28;

  /// How high over the nest the close-up looks: a little over the middle of
  /// the viewer's chick (drawn a size up, from its feet on the lip to its
  /// hat mid-hop), so it stands in the lower middle of the frame, its hat
  /// clear of the score's banner at the top even mid-hop.
  static const double celebrateLookHeight = 2.2;

  /// How tall the nest's flag stands (world units), kept clear of the HUD
  /// when that is cheap.
  static const double nestFlagHeight = 3.7;

  /// How long the hole's overview holds before the camera comes in.
  static const double openingSeconds = 2.4;

  /// Whether the player asked their system for reduced motion: no
  /// opening sweep, the camera goes straight to the hole's play framing.
  bool reduceMotion = false;

  /// How long the camera stays in on the nest after the viewer's own egg
  /// drops in: the sink, the hatch, the chick's hops.
  static const double celebrateSeconds = 3.0;

  bool _wasHoled = false;
  double _celebrateUntil = 0;
  Vec2? _celebrateAt;

  /// Whether someone else drives the camera (the demo's held close-ups):
  /// the director then keeps its clock but moves nothing.
  bool held = false;

  /// Whether the hole's opening sweep is still on.
  bool get opening => !reduceMotion && _sweepClock < openingSeconds;

  /// Seconds since the camera settled on the hole after its opening (a
  /// second's glide after the sweep; at once with reduced motion).
  double get settledFor =>
      _sweepClock - (reduceMotion ? 0.3 : openingSeconds + 1.0);

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

  /// The opening sweep's own clock: it stops while the player drags an aim,
  /// so the camera never slides out from under a pull.
  double _sweepClock = 0;
  bool _userCamera = false;

  /// The hole's play framing: the zoom that keeps my egg a readable size
  /// (and the nest in the free view too, when the hole is short enough for
  /// both), and the offset from the egg to the point the camera centres on
  /// - nothing, the egg being the middle of the frame. Both are chosen once
  /// when the hole opens and held for the whole hole, so the egg keeps the
  /// same place in the frame from the tee to the nest and a shot never
  /// moves the camera.
  double _playDistance = 0;
  Vec2 _playOffset = Vec2.zero;

  /// The way the hole is played facing: from behind my egg where the hole
  /// opens, toward the nest (Putt Party's tee shot), held for the hole.
  double _playYaw = PuttCameraRig.defaultYaw;
  String? _playYawHole;
  bool _playFramed = false;

  bool _showingBetween = false;
  Vec2? _follow;

  /// [PuttCameraCue.myStrokes] at the last update.
  int _myStrokes = 0;

  /// The other player the camera watches once my egg is in (or for a
  /// spectator); null while it is on mine, or no one is out.
  String? get watching => _overview || celebrating ? null : _watching;
  String? _watching;

  /// Where the watched egg rested when it was last framed, as [_framedAt].
  Vec2? _watchFramedAt;
  bool _watchWasRolling = false;

  /// The other eggs' strokes at the last update, and the eggs rolling
  /// from a putt (a stroke more since they last rested): one of those
  /// takes the camera from a resting watched egg, a bumped one never does.
  final Map<String, int> _othersStrokes = {};
  final Set<String> _othersPutting = {};

  /// When the camera started watching [_watching]: it stays on it at least
  /// [watchDwellSeconds], unless it drops in.
  double _watchSince = 0;
  static const double watchDwellSeconds = 1.5;

  /// The point the rig's target glides toward this frame; null holds it.
  Vec2? get followPoint => _follow;

  /// Seconds the current hole has been up.
  double get holeClock => _holeClock;

  /// The zoom the hole plays at, and the offset from my egg to the point
  /// the camera centres on - both the hole's, from its first frame to its
  /// last.
  double get playDistance => _playDistance;
  Vec2 get playOffset => _playOffset;
  double get playYaw => _playYaw;

  /// The player zoomed, pinched or orbited: leave the zoom to them for the
  /// rest of this hole.
  void noteUserCamera() => _userCamera = true;

  /// After a refit (a resize): the hole's framing is measured again, and
  /// between holes the whole green is asked for again.
  void reframe() {
    _playFramed = false;
    _watchFramedAt = null;
    _showingBetween = false;
  }

  /// The whole hole, or back to the director's own framing.
  void toggleOverview() {
    _overview = !_overview;
    if (_overview) {
      rig.glideTo(
          distance: rig.overviewDistance, yaw: PuttCameraRig.defaultYaw);
    } else {
      rig.glideTo(yaw: _playYaw, distance: _userCamera ? null : _playDistance);
    }
  }

  /// The hole's entrance, driven frame by frame over [openingSeconds]: the
  /// camera starts low over the nest, turned a little, looking across it at
  /// the farm and the sky (the hour shows), holds there a breath, then
  /// rises and swings round behind my egg onto the hole's play framing -
  /// the egg dead centre, the nest ahead - so the sweep lands exactly where
  /// the hole is played and nothing glides afterwards.
  void _sweep(HoleDef hole, Vec2? host, Vec2 egg) {
    final t = (_sweepClock / (openingSeconds - 0.3)).clamp(0.0, 1.0);
    // A held beat, then an ease-in-out climb.
    final k = t < 0.25 ? 0.0 : (t - 0.25) / 0.75;
    final eased = k * k * (3 - 2 * k);
    double lerp(double a, double b) => a + (b - a) * eased;
    // The first pose takes in the whole table, its tee and the host beside
    // it, low from the side: aimed at the nest from a set distance, the
    // tee's eggs or the host stood cut at a frame's edge on some holes.
    final table = [
      hole.bounds.min,
      hole.bounds.max,
      Vec2(hole.bounds.min.x, hole.bounds.max.y),
      Vec2(hole.bounds.max.x, hole.bounds.min.y),
      hole.tee,
      hole.nest.position,
    ];
    // The host whole: his footprint, and as tall as he stands.
    final around = [
      if (host != null)
        for (final (dx, dy) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)])
          host + Vec2(dx * _hostReach, dy * _hostReach),
    ];
    final openingYaw = _playYaw + _openingTurn;
    final start = rig.frameAt(
      [...table, ...around],
      yaw: openingYaw,
      pitchDeg: _openingPitch,
      tall: [
        for (final _ in table) 0.0,
        for (final _ in around) _hostHeight,
      ],
    );
    rig
      ..aimAt(
        yaw: lerp(openingYaw, _playYaw),
        pitchDeg: lerp(_openingPitch, PuttCameraRig.pitchDefault),
        distance: lerp(start.distance, _playDistance),
        target: start.target.lerp(egg + _playOffset, eased),
      )
      ..snap();
  }

  /// The opening's first pose: turned a little off the play framing, low.
  static const double _openingTurn = 0.55;
  static const double _openingPitch = 15;

  /// How far the host reaches round the spot he stands on (his body, his
  /// tail), and how tall he stands to his comb (world units).
  static const double _hostReach = 2.6;
  static const double _hostHeight = 5.6;

  void update(double dt, PuttCameraCue cue) {
    final hole = cue.hole;
    if (hole == null) {
      _follow = null;
      return;
    }
    if (hole.id != _holeId) {
      _holeId = hole.id;
      _holeClock = 0;
      _sweepClock = 0;
      _userCamera = false;
      _playFramed = false;
      _showingBetween = false;
      _wasHoled = false;
      _celebrateUntil = 0;
      _watching = null;
      _watchFramedAt = null;
      _watchWasRolling = false;
      _othersStrokes.clear();
      _othersPutting.clear();
    }
    _holeClock += dt;
    if (_sweepClock < openingSeconds && !cue.aiming) _sweepClock += dt;
    if (held) {
      _follow = null;
      return;
    }
    final center = hole.bounds.center;
    final egg = cue.myEgg ?? hole.tee;

    // The hole's play framing, measured once: the egg dead centre, at the
    // distance that keeps it a readable size (the nest in the frame too
    // when the hole is short enough for it). Held for the whole hole -
    // this is the only time the zoom is chosen.
    if (!_playFramed) {
      _playFramed = true;
      // Turned once per hole: a resize frames again, but from the same side.
      if (_playYawHole != hole.id) {
        _playYawHole = hole.id;
        _playYaw = PuttCameraRig.yawToward(egg, hole.nest.position);
      }
      final framing = rig.playFraming(egg, hole.nest.position,
          yaw: _playYaw,
          eggHeight: eggHeight,
          eggPixels: aimEggPixels,
          tall: const [0, nestFlagHeight]);
      _playDistance = framing.distance;
      _playOffset = framing.target - egg;
      if (!_userCamera) rig.glideTo(distance: _playDistance, yaw: _playYaw);
    }

    // My egg just dropped in: the camera comes in on the nest for the
    // hatch (unless the player took the camera), then frames the rest.
    if (cue.myEggHoled && !_wasHoled && !_userCamera) {
      _celebrateUntil = _holeClock + celebrateSeconds;
      // Down low, from the side the camera already looks from (the chick
      // turns to it): the chick in its hat stands whole in the middle of
      // the frame, under the banner up top - from high above it was a
      // yellow blob under its crown. The camera looks at the chick's
      // middle, not the nest's floor: the target lies past the nest by what
      // lifts the view that high (centred on the ground, the hopping chick
      // rose out of the top of the frame).
      final away = Vec2(math.sin(rig.yawTarget), math.cos(rig.yawTarget));
      _celebrateAt = hole.nest.position +
          away *
              (celebrateLookHeight / math.tan(celebratePitch * math.pi / 180));
      rig.glideTo(
        target: _celebrateAt,
        distance: celebrateDistance,
        pitchDeg: celebratePitch,
        closeUp: true,
      );
    }
    _wasHoled = cue.myEggHoled;
    if (_holeClock < _celebrateUntil) {
      _follow = _celebrateAt ?? hole.nest.position;
      return;
    }
    if (_celebrateUntil > 0) {
      _celebrateUntil = 0;
      _watchFramedAt = null;
      // Back out to the hole's own framing, the close-up's floor released.
      rig.glideTo(
        pitchDeg: PuttCameraRig.pitchDefault,
        yaw: _playYaw,
        distance: _userCamera ? null : _playDistance,
      );
    }

    // A drag never slides out from under the pointer: the frame holds
    // exactly where it is, whatever the egg or the sweep is doing.
    if (cue.aiming) {
      _follow = rig.target;
      return;
    }

    // Between holes, and while the hole opens: the whole green.
    if (cue.phase != PuttPhase.holePlay) {
      _follow = center;
      _watching = null;
      if (!_showingBetween) {
        _showingBetween = true;
        rig.glideTo(
            distance: rig.overviewDistance, yaw: PuttCameraRig.defaultYaw);
      }
      return;
    }
    _showingBetween = false;
    // A new putt of mine hands the camera back from the whole-hole view
    // (my egg knocked by another stays in it).
    if (cue.myStrokes > _myStrokes) _overview = false;
    _myStrokes = cue.myStrokes;
    if (opening) {
      _sweep(hole, cue.host, egg);
      _follow = null;
      return;
    }
    if (_overview) {
      _follow = center;
      return;
    }

    if (cue.myEgg != null) {
      // The egg is the anchor. It keeps the one place in the frame the
      // hole's framing gave it and the camera only pans with it: no zoom,
      // no turn, no re-framing when it comes to rest, and no lead ahead of
      // a roll. The nest drifts across the frame as the egg travels; the
      // HUD's marker points at it when it leaves the free view. Once my
      // egg is in, the camera stays on the nest it went in - another
      // player's egg never takes it, as in Putt Party, so a player waiting
      // their turn still sees their own green and not someone else's putt.
      _follow = cue.myEggHoled ? hole.nest.position : cue.myEgg! + _playOffset;
      return;
    }

    // A spectator, with no egg of their own: one egg still out, followed.
    _watch(hole, cue.otherEggs);
  }

  /// A spectator's camera: picks the egg to watch and frames it like a
  /// player's own - followed while it rolls, framed with the nest where it
  /// rests (again wherever a splash or the line puts it back). The camera
  /// moves on only when another player putts while the watched egg rests
  /// (and has been watched for [watchDwellSeconds]), or the watched one
  /// drops in - never back and forth between eggs in play at once, nor to
  /// an egg a hen bumped. A player's own egg is never given up this way.
  void _watch(HoleDef hole, List<PuttCameraEgg> others) {
    for (final other in others) {
      final before = _othersStrokes[other.id];
      if (before != null && other.strokes > before) {
        _othersPutting.add(other.id);
      }
      _othersStrokes[other.id] = other.strokes;
      if (other.resting) _othersPutting.remove(other.id);
    }
    PuttCameraEgg? watched;
    for (final other in others) {
      if (other.id == _watching) watched = other;
    }
    PuttCameraEgg? nearest(Iterable<PuttCameraEgg> eggs) {
      PuttCameraEgg? best;
      for (final egg in eggs) {
        if (best == null ||
            egg.position.distanceTo(rig.target) <
                best.position.distanceTo(rig.target)) {
          best = egg;
        }
      }
      return best;
    }

    final next = watched == null
        ? nearest(others.where((o) => !o.resting)) ?? nearest(others)
        : watched.resting && _holeClock - _watchSince >= watchDwellSeconds
            ? nearest(others.where((o) => _othersPutting.contains(o.id))) ??
                watched
            : watched;
    if (next == null) {
      // Everyone is in: the nest, until the scoreboard's whole green.
      _watching = null;
      _follow = hole.nest.position;
      return;
    }
    if (next.id != _watching) {
      _watching = next.id;
      _watchSince = _holeClock;
      _watchFramedAt = null;
      _watchWasRolling = false;
    }
    final egg = next.position;
    if (!next.resting) {
      if (!_watchWasRolling && !_userCamera) {
        rig.glideTo(
            distance:
                math.max(rig.distanceTarget, rig.overviewDistance * 0.62));
      }
      _watchWasRolling = true;
      _watchFramedAt = null;
      final lead = next.velocity * 0.28;
      _follow =
          egg + (lead.length > 4 ? lead.normalized(Vec2.zero) * 4.0 : lead);
      return;
    }
    _watchWasRolling = false;
    _follow = null;
    final framedAt = _watchFramedAt;
    if (framedAt != null && framedAt.distanceTo(egg) <= 0.5) return;
    _watchFramedAt = egg;
    if (_userCamera) {
      rig.glideTo(target: egg.lerp(hole.nest.position, 0.35));
    } else {
      // Their egg and the nest with its flag: the shot they have ahead.
      rig.glideToFramePoints([egg, hole.nest.position],
          yaw: PuttCameraRig.yawLeaningToward(egg, hole.nest.position),
          tall: const [0, nestFlagHeight]);
    }
  }
}
