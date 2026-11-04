// The local match harness of Sunny Side Putt: the game view driven straight
// from a `PuttEngine`, host-like, with no session and no network - the
// playable-standalone seam this ticket builds on. The session ticket (T9)
// wires the same view to the authoritative host later; until then this
// harness ticks the engine itself, spends the events the engine emits as
// HUD headlines and sound cues, and keeps per-tick egg positions so the
// renderer can interpolate between the fixed 120 Hz steps.
//
// The view never mutates the engine outside here; the HUD and menus call
// submitShot / usePowerUp / advance / startCourse, exactly the inputs the
// engine journals.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'stub_courses.dart';

/// Sounds the view's audio service knows. The harness picks one per engine
/// event; the service maps each to a file (see `putt_audio.dart`).
enum PuttSfx {
  putt,
  bounce,
  bumper,
  water,
  swallow,
  out,
  holed,
  boost,
  portal,
  powerUpPicked,
  powerUpUsed,
  timerCue,
  timerTick,
  holeEnd,
  victory,
  click,
}

/// A headline for the HUD's banner strip: the big, low-frequency things a
/// match says (hole start, a score term, time up, match over), plus the
/// small sound-only notices with `title: null`.
class PuttNotice {
  final PuttSfx sfx;

  /// The banner line, when this notice earns one.
  final String? title;

  const PuttNotice(this.sfx, {this.title});

  @override
  String toString() => 'PuttNotice($sfx, $title)';
}

/// Where a burst of particles goes: the events that carry a spot on the
/// green. Filled next to [PuttNotice]s, read by the game's FX layer.
enum PuttFxSpotKind { splash, out, holed, pick }

class PuttFxSpot {
  final PuttFxSpotKind kind;

  /// The spot on the green, when the event has one.
  final Vec2? at;

  /// The player it happened to, when it did.
  final String? who;

  const PuttFxSpot(this.kind, {this.at, this.who});
}

/// The view's handle on a locally simulated match. A [ChangeNotifier], so
/// the HUD rebuilds on `notifyListeners()` once per rendered frame.
class PuttMatch extends ChangeNotifier {
  /// The id this view plays under; the session replaces it with the real
  /// Matrix identity later.
  final String localPlayerId;

  final PuttConfig config;

  final PuttEngine engine;

  /// A display name per player id; unknown ids render as themselves.
  final Map<String, String> displayNames;

  PuttMatch({
    required this.config,
    this.localPlayerId = 'me',
    this.displayNames = const {},
    List<String> seatedPlayerIds = const [],
  }) : engine = PuttEngine(config) {
    for (final id in seatedPlayerIds) {
      engine.join(id);
    }
    engine.join(localPlayerId);
    drainEvents();
  }

  /// A match to boot and play right now: one stub course, this client as
  /// the only - hosting - player, friendly names for the id.
  factory PuttMatch.solo({String localPlayerName = 'You'}) {
    final course = stubCourse(id: 'stub-course', holeCount: 3);
    return PuttMatch(
      config: PuttConfig(
        mode: GameMode.casual,
        courses: [course],
        catalog: {'stub-course': course},
        seed: 31337,
      ),
      displayNames: {'me': localPlayerName},
    )..boot();
  }

  /// Joins and starts: hole 1 is on the tee when this returns.
  void boot() {
    engine.start();
    drainEvents();
  }

  // ---- ticking --------------------------------------------------------------

  double _accumulator = 0;

  /// Fractions of a step accumulated past the last whole tick, for the
  /// renderer to interpolate with.
  double get alpha => (_accumulator / config.physics.dt).clamp(0.0, 1.0);

  /// Whether the view paused the world (pause menu up): ticks stop, events
  /// stick around until unpaused.
  bool paused = false;

  /// Egg positions the tick BEFORE the last one, per player: the lerp's
  /// from-end. Cleared per hole, so stale ids never leak.
  final Map<String, Vec2> previousPositions = {};

  /// Egg positions after the last whole tick: the lerp's to-end.
  final Map<String, Vec2> currentPositions = {};

  /// Sleep flags over the same two ticks, for the reset diffs below.
  final Map<String, bool> previousAsleep = {};
  final Map<String, bool> currentAsleep = {};

  /// Advances the simulated world by [dt] seconds of frame time, in whole
  /// engine ticks, then drains the engine's events into notices and state.
  void update(double dt) {
    if (paused) return;
    if (phase != PuttPhase.holePlay) {
      // Between holes the world is static; drop the leftover fraction so
      // the next hole starts its clock fresh.
      _accumulator = 0;
      return;
    }
    _accumulator += math.min(dt, 0.25); // clamp jank: no tick avalanches
    final step = config.physics.dt;
    var steps = 0;
    final derived = <PuttNotice>[];
    final derivedSpots = <PuttFxSpot>[];
    while (_accumulator >= step && steps < 30) {
      _capturePositions(); // the from-end: positions as the tick found them
      engine.tickForward();
      _capturePositions(withPrevious: false); // the to-end: where they landed
      _deriveResets(derived, derivedSpots);
      _accumulator -= step;
      steps++;
    }
    if (steps > 0) {
      final drained = drainEvents();
      notices
        ..clear()
        ..addAll([...drained, ...derived]);
      fxSpots.addAll(derivedSpots);
      notifyListeners();
    }
  }

  /// After the last tick, where is egg [playerId] drawn?
  /// Between the last two whole ticks at [alpha], settled otherwise.
  Vec2 renderPositionOf(String playerId, [double? alphaOverride]) {
    final current = currentPositions[playerId];
    if (current == null) return Vec2.zero;
    final previous = previousPositions[playerId] ?? current;
    return previous.lerp(current, alphaOverride ?? alpha);
  }

  /// snaps the eggs into the per-tick maps: with [withPrevious] the last
  /// to-end becomes the new from-end (the capture before a tick); without
  /// it, the to-end alone updates (the capture after a tick).
  void _capturePositions({bool withPrevious = true}) {
    final world = engine.world;
    if (world == null) return;
    if (withPrevious) {
      previousPositions
        ..clear()
        ..addEntries(currentPositions.entries);
      previousAsleep
        ..clear()
        ..addEntries(currentAsleep.entries);
    }
    currentPositions
      ..clear()
      ..addEntries([
        for (final ball in world.balls) MapEntry(ball.playerId, ball.position),
      ]);
    currentAsleep
      ..clear()
      ..addEntries([
        for (final ball in world.balls)
          MapEntry(ball.playerId, ball.asleep || ball.holed),
      ]);
  }

  /// Between-tick resets: the jumps the engine makes silently (water, out
  /// of bounds, swallowed, portal) read from the world's state, since the
  /// physics events do not surface through the engine's own stream.
  void _deriveResets(List<PuttNotice> notices, List<PuttFxSpot> spots) {
    final h = hole;
    if (h == null) return;
    for (final entry in previousPositions.entries) {
      final id = entry.key;
      final before = entry.value;
      final after = currentPositions[id];
      if (after == null || currentAsleep[id] != true) continue;
      if (previousAsleep[id] != false) continue;
      final jumped = before.distanceTo(after) > 2.5;
      if (!jumped) continue;

      var handled = false;
      // A portal trip: one end to the other, nothing penalized.
      for (final pair in h.portals) {
        final fromA = before.distanceTo(pair.a) <= pair.radius;
        final fromB = before.distanceTo(pair.b) <= pair.radius;
        final landA = after.distanceTo(pair.a) <= pair.radius;
        final landB = after.distanceTo(pair.b) <= pair.radius;
        if ((fromA && landB) || (fromB && landA)) {
          notices.add(const PuttNotice(PuttSfx.portal));
          handled = true;
          break;
        }
      }
      if (handled) continue;

      // Water, then the silo's swallow zone, then off the green.
      handled = false;
      for (final shape in h.water) {
        if (shape.contains(before)) {
          notices.add(const PuttNotice(PuttSfx.water));
          spots.add(PuttFxSpot(PuttFxSpotKind.splash, at: before));
          handled = true;
          break;
        }
      }
      if (handled) continue;

      for (final well in h.wells) {
        if (well.swallowRadius > 0 &&
            before.distanceTo(well.position) <= well.swallowRadius) {
          notices.add(const PuttNotice(PuttSfx.swallow));
          spots.add(PuttFxSpot(PuttFxSpotKind.out, at: before));
          handled = true;
          break;
        }
      }
      if (handled) continue;

      if (!h.bounds.contains(before)) {
        notices.add(const PuttNotice(PuttSfx.out));
        spots.add(PuttFxSpot(PuttFxSpotKind.out, at: before));
      }
    }
  }

  // ---- state the HUD and game read ------------------------------------------

  PuttPhase get phase => engine.phase;

  /// The hole on the green, or null in the lobby / between courses.
  HoleDef? get hole => engine.currentHole;

  /// 1-based index of the hole across everything played so far.
  int get holeNumber => engine.world == null ? 0 : _holeNumber;

  int _holeNumber = 1;

  /// Par of the running hole, 0 between holes.
  int get par => hole?.par ?? 0;

  double get secondsRemaining => engine.secondsRemaining;

  int get timerSeconds => config.holeTimeLimitSeconds;

  PuttPlayer? get localPlayer => engine.player(localPlayerId);

  bool get isSpectator => engine.isSpectator(localPlayerId);

  /// This client's egg: interpolated for drawing.
  Vec2? get myEggRenderPosition => engine.world?.ball(localPlayerId) == null
      ? null
      : renderPositionOf(localPlayerId);

  /// My ball body: awake/holed checks for "can I strike now".
  BallBody? get myBall => engine.world?.ball(localPlayerId);

  /// A stroke is offered when my egg is settled, unhholed and on the green.
  bool get myShotReady {
    final ball = myBall;
    if (ball == null || ball.holed || !ball.asleep) return false;
    return phase == PuttPhase.holePlay && !isSpectator;
  }

  /// Hawk Eye (or any no-wobble modifier) pending for my next shot: the
  /// aim arrow must hold still to promise a straight one.
  bool get myNextShotSteady => localPlayer?.nextShot.noWobble ?? false;

  /// My held power-ups, oldest first, for the HUD's slots.
  List<String> get myInventory => localPlayer?.inventory.toList() ?? const [];

  /// The scoreboard as of now.
  List<ScoreRow> get scoreboard => engine.scoreboard();

  int get myTotal => engine.totals[localPlayerId] ?? 0;

  /// Strokes I have taken in the running hole.
  int get myStrokesThisHole => engine.strokesInHole(localPlayerId);

  /// The newest banner line, or null when nothing is up (the widget fades
  /// headlines out after a while on its own).
  String? headline;

  /// The notices drained since the last call: HUD banner material and the
  /// audio service's cue list.
  final List<PuttNotice> notices = [];

  // ---- player intent ----------------------------------------------------------

  /// STRIKE. The engine applies its own wobble to the REAL angle; the view
  /// only showed the arrow swaying as a warning.
  bool submitShot(double angle, double power) {
    final accepted = engine.submitShot(localPlayerId, angle, power);
    if (accepted) _afterInput();
    return accepted;
  }

  /// Uses a held power-up. Targeted effects (Nest Swap, Thieving Crow, the
  /// point-targeted ones) arrive when the effects ticket lands its UI; the
  /// engine consumes even effects it does not know, so the inventory stays
  /// honest either way.
  bool usePowerUp(String effectId, [PowerUpTarget? target]) {
    final accepted = engine.usePowerUp(localPlayerId, effectId, target);
    if (accepted) _afterInput();
    return accepted;
  }

  /// The scoreboard's Continue: next hole (or however the phase moves on).
  bool advance() {
    if (!engine.advance()) return false;
    _afterInput();
    return true;
  }

  /// Casual/barnyard vote settled: this course next.
  bool startCourse(String courseId) {
    if (!engine.startCourse(courseId)) return false;
    _afterInput();
    return true;
  }

  /// Leaving mid-match cleans my egg off the green.
  bool leave() {
    final accepted = engine.leave(localPlayerId);
    if (accepted) _afterInput();
    return accepted;
  }

  void _afterInput() {
    drainEvents();
    notifyListeners();
  }

  // ---- events --------------------------------------------------------------------

  /// Empties the engine's event queue into [notices], [fxSpots], banner
  /// lines and the per-hole bookkeeping the HUD reads. A bounce storm
  /// collapses to two roll noises; everything else passes through.
  List<PuttNotice> drainEvents() {
    fxSpots.clear();
    final result = <PuttNotice>[];
    final rollNoises = <PuttNotice>[];
    for (final event in engine.drainEvents()) {
      final notice = _noticeFor(event);
      if (notice == null) continue;
      if (_isRollNoise(notice.sfx)) {
        rollNoises.add(notice);
      } else {
        result.add(notice);
      }
    }
    result.addAll(rollNoises.take(2));
    notices
      ..clear()
      ..addAll(result);
    return result;
  }

  /// Burst anchors from the ticks this [drainEvents] covered.
  final List<PuttFxSpot> fxSpots = [];

  PuttNotice? _noticeFor(PuttEvent event) {
    switch (event) {
      case HoleStarted():
        _holeNumber = event.globalIndex + 1;
        previousPositions.clear();
        currentPositions.clear();
        previousAsleep.clear();
        currentAsleep.clear();
        headline = labelPuttHoleStart(event.globalIndex + 1, event.par);
        return PuttNotice(PuttSfx.putt, title: headline);
      case MatchStarted():
        headline = labelPuttCourseStart(_courseName(event.courseId));
        return PuttNotice(PuttSfx.click, title: headline);
      case CourseStarted():
        headline = labelPuttCourseStart(_courseName(event.courseId));
        return PuttNotice(PuttSfx.click, title: headline);
      case ShotApplied():
        if (event.playerId != localPlayerId) return null;
        return const PuttNotice(PuttSfx.putt);
      case PlayerHoled():
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.holed, who: event.playerId));
        if (event.playerId == localPlayerId) {
          final term = ScoreTerm.of(event.strokes, par);
          headline = scoreTermText(term);
        }
        return PuttNotice(PuttSfx.holed);
      case TimerCue():
        return PuttNotice(PuttSfx.timerCue);
      case TimerTick():
        return PuttNotice(PuttSfx.timerTick);
      case HoleEnded():
        headline =
            event.completed ? labelPuttHoleCleared() : labelPuttHoleTimedOut();
        return PuttNotice(
          event.completed ? PuttSfx.holeEnd : PuttSfx.timerCue,
          title: headline,
        );
      case PowerUpPicked():
        if (event.playerId != localPlayerId) return null;
        return const PuttNotice(PuttSfx.powerUpPicked);
      case PowerUpUsed():
        if (event.playerId != localPlayerId) return null;
        return const PuttNotice(PuttSfx.powerUpUsed);
      case MatchEnded():
        headline = labelPuttMatchOver();
        return PuttNotice(PuttSfx.victory, title: headline);
      default:
        return null;
    }
  }

  String _courseName(String courseId) => courseId;

  /// Physics noise the egg makes by rolling: many per tick are collapsed
  /// to the loudest (the noise trimmer keeps at most one of each kind).
  bool _isRollNoise(PuttSfx sfx) =>
      sfx == PuttSfx.bounce || sfx == PuttSfx.bumper;
}

/// The display name of a player id: the match's map, then the id itself.
String displayNameOf(PuttMatch match, String playerId) =>
    match.displayNames[playerId] ?? playerId;

// ---- strings (inline Intl.message; the arb sync is not this ticket) ----------

String labelPuttHoleStart(int hole, int par) =>
    Intl.message("Hole $hole - Par $par",
        name: "labelPuttHoleStart",
        args: [hole, par],
        desc: "HUD banner when a hole starts; the placeholders are the hole's "
            "number in the match and its par");

String labelPuttCourseStart(String course) =>
    Intl.message("Now playing: $course",
        name: "labelPuttCourseStart",
        args: [course],
        desc: "HUD banner when a course starts or a voted course comes on; the "
            "placeholder is the course's name");

String labelPuttHoleCleared() => Intl.message("Hole cleared!",
    name: "labelPuttHoleCleared",
    desc: "HUD banner when every egg is in the nest before the timer runs "
        "out");

String labelPuttHoleTimedOut() => Intl.message("Time's up!",
    name: "labelPuttHoleTimedOut",
    desc: "HUD banner when the hole's timer expires with eggs still on the "
        "green");

String labelPuttMatchOver() => Intl.message("Match over",
    name: "labelPuttMatchOver",
    desc: "HUD banner when the last hole of the match is scored");

String scoreTermText(ScoreTerm term) {
  switch (term) {
    case ScoreTerm.holeInOne:
      return Intl.message("Hole in one!",
          name: "labelPuttTermHoleInOne",
          desc: "One stroke on a hole of any par");
    case ScoreTerm.albatross:
      return Intl.message("Albatross!",
          name: "labelPuttTermAlbatross", desc: "Three strokes under par");
    case ScoreTerm.eagle:
      return Intl.message("Eagle!",
          name: "labelPuttTermEagle", desc: "Two strokes under par");
    case ScoreTerm.birdie:
      return Intl.message("Birdie!",
          name: "labelPuttTermBirdie", desc: "One stroke under par");
    case ScoreTerm.par:
      return Intl.message("Par",
          name: "labelPuttTermPar", desc: "Exactly the hole's par");
    case ScoreTerm.bogey:
      return Intl.message("Bogey",
          name: "labelPuttTermBogey", desc: "One stroke over par");
    case ScoreTerm.doubleBogey:
      return Intl.message("Double bogey",
          name: "labelPuttTermDoubleBogey", desc: "Two strokes over par");
    case ScoreTerm.tripleBogey:
      return Intl.message("Triple bogey",
          name: "labelPuttTermTripleBogey", desc: "Three strokes over par");
    case ScoreTerm.more:
      return Intl.message("In the nest",
          name: "labelPuttTermMore",
          desc: "Four or more strokes over par: holed, but no golf term "
              "left to call it");
  }
}
