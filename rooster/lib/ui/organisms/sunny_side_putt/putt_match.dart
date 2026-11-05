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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show ImageProvider;
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';

import 'putt_art.dart';
import 'putt_look.dart';
import 'stub_courses.dart';

/// Sounds the view's audio service knows. The harness picks them from the
/// engine's events and the world's echoes; the service maps each to a file
/// (see `putt_audio.dart`).
enum PuttSfx {
  /// My stroke, a wooden tock in three strengths by the putt's power.
  puttSoft,
  putt,
  puttFirm,

  /// An egg off a timber rail (a knock), a rubber bumper (a boing),
  /// another egg (a clack), or a hen or a duck (who say so).
  bounce,
  bumper,
  clack,
  hen,
  duck,
  water,
  swallow,
  out,

  /// An egg in the nest: straw and a chime at once, then the chick's
  /// peeps timed to the hatch, and the host's crow for a hole in one.
  holed,
  hatch,
  crow,
  boost,
  portal,
  powerUpPicked,
  powerUpUsed,
  timerCue,

  /// The last seconds, one a second, tick then tock.
  timerTick,
  timerTock,
  holeStart,
  holeEnd,
  victory,
  click,

  /// The Thieving Crow's caw as it takes a power-up.
  crowCaw,

  /// A Thick Shell holding against a cast.
  shieldPop,

  /// Corn Rain's patter of kernels.
  cornRain,

  /// A Gust's wind.
  gust,
}

/// A headline for the HUD's banner strip: the big, low-frequency things a
/// match says (hole start, a score term, time up, match over), plus the
/// small sound-only notices with `title: null`.
class PuttNotice {
  final PuttSfx sfx;

  /// The banner line, when this notice earns one.
  final String? title;

  /// How loud, as a share of the effects bus: a glancing knock is quieter
  /// than a hard one.
  final double volume;

  const PuttNotice(this.sfx, {this.title, this.volume = 1});

  @override
  String toString() => 'PuttNotice($sfx, $title)';
}

/// What a headline announces, so the HUD can dress each kind its own way:
/// a hole's number big over its par and course, a score term in its
/// colour, the hole's or the match's end.
enum PuttHeadlineKind { holeStart, scoreTerm, holeEnd, course, matchOver }

/// Where a burst of particles goes: the events that carry a spot on the
/// green. Filled next to [PuttNotice]s, read by the game's FX layer.
enum PuttFxSpotKind {
  splash,
  out,
  back,
  holed,
  pick,

  /// Anyone cast a power-up ([PuttFxSpot.effectId]): the burst at the
  /// caster's egg ([PuttFxSpot.at], where it stood as it cast) and the
  /// scene's start at its spot ([PuttFxSpot.toward], the cast's target).
  cast,

  /// A cast reached an egg ([PuttFxSpot.who], cast by
  /// [PuttFxSpot.other]): the effect's scene on it (kernels round it, the
  /// wind behind it, a soak, a swap's swirl).
  hit,

  /// A Thieving Crow took [PuttFxSpot.effectId] from [PuttFxSpot.other]
  /// for [PuttFxSpot.who]: the crow flies from one egg to the other.
  steal,

  /// The Thick Shell round [PuttFxSpot.who]'s egg held and popped.
  shieldPop,

  /// A shot left with a next-shot power-up on it ([PuttFxSpot.effectId]:
  /// Hawk Eye, Strong Coffee, Chicken Hop, Nest Magnet), from
  /// [PuttFxSpot.at] toward [PuttFxSpot.toward].
  shot,

  /// [PuttFxSpot.who] put on another look, egg out on the green at
  /// [PuttFxSpot.at]: a puff as the new shell comes on.
  restyle,
}

class PuttFxSpot {
  final PuttFxSpotKind kind;

  /// The spot on the green, when the event has one.
  final Vec2? at;

  /// The player it happened to, when it did.
  final String? who;

  /// The power-up behind it, for the cast kinds.
  final String? effectId;

  /// The other player in it: who cast what hit [who], whom the crow robbed.
  final String? other;

  /// Where it points: a cast's spot on the green, a shot's heading.
  final Vec2? toward;

  const PuttFxSpot(this.kind,
      {this.at, this.who, this.effectId, this.other, this.toward});

  @override
  String toString() => 'PuttFxSpot($kind, $who, $effectId)';
}

/// What a [PuttCastCall] announces.
enum PuttCastCallKind {
  /// Someone cast a power-up.
  cast,

  /// A Thieving Crow took a power-up from someone.
  steal,

  /// A Nest Swap traded places with the viewer.
  swap,

  /// A Thick Shell held against a cast.
  blocked,
}

/// One cast as everyone hears of it: a line in the cast feed under the
/// top bar (`putt_cast_feed.dart` words it), led by who did it and the
/// power-up's icon. Calls queue, so casts in a row read one after another.
@immutable
class PuttCastCall {
  /// Counts calls as they are made: the feed takes in the ones it has not
  /// seen.
  final int serial;

  final PuttCastCallKind kind;

  /// Who cast (the thief of a steal, the swapper, the caster a shell held
  /// against).
  final String casterId;

  /// The power-up cast.
  final String effectId;

  /// The other player in it: the one robbed, the one swapped with, the
  /// one whose shell held.
  final String? otherId;

  /// What the crow took, for a steal.
  final String? stolenId;

  const PuttCastCall({
    required this.serial,
    required this.kind,
    required this.casterId,
    required this.effectId,
    this.otherId,
    this.stolenId,
  });

  /// The player whose picture (or colour) leads the call: the shielded
  /// one for a block, the caster otherwise.
  String get leadId =>
      kind == PuttCastCallKind.blocked ? otherId ?? casterId : casterId;

  /// The power-up whose icon the call wears: what the crow took, the
  /// shell that held, else the one cast.
  String get iconId => switch (kind) {
        PuttCastCallKind.steal => stolenId ?? effectId,
        PuttCastCallKind.blocked => 'thick_shell',
        _ => effectId,
      };

  @override
  String toString() =>
      'PuttCastCall($serial, $kind, $casterId, $effectId, $otherId)';
}

/// The view's handle on a locally simulated match. A [ChangeNotifier], so
/// the HUD rebuilds on `notifyListeners()` once per rendered frame.
class PuttMatch extends ChangeNotifier {
  /// The id this view plays under; the session replaces it with the real
  /// Matrix identity later.
  final String localPlayerId;

  final PuttConfig config;

  final PuttEngine engine;

  /// A display name per player id; unknown ids go to [nameOf], then
  /// render as themselves.
  final Map<String, String> displayNames;

  /// Names for the ids [displayNames] does not hold - players who joined
  /// after the match was built: the session's roster lookup.
  final String Function(String playerId)? nameOf;

  /// A player's avatar (the call's member picture), when there is one:
  /// the name tags wear it over the egg.
  final ImageProvider? Function(String playerId)? avatarOf;

  /// Set when this match plays on a session's wire and this client is not
  /// its host: every move of ours is told to the handler (the session
  /// takes it to the host), and the flow moves - advancing, votes,
  /// leaving - go ONLY to the handler, the host's word coming back as the
  /// next state or relayed move.
  final ValueChanged<EngineInput>? remoteMove;

  /// [look] is the one this client's egg wears, the one saved in "Your
  /// egg" when left out ([savedPuttLook]).
  PuttMatch({
    required this.config,
    PuttEngine? engine,
    this.remoteMove,
    this.localPlayerId = 'me',
    this.displayNames = const {},
    this.nameOf,
    this.avatarOf,
    List<String> seatedPlayerIds = const [],
    PuttLook? look,
  })  : engine = engine ?? PuttEngine(config),
        _look = look ?? savedPuttLook() {
    if (engine == null) {
      for (final id in seatedPlayerIds) {
        this.engine.join(id);
      }
      this.engine.join(localPlayerId, look: _look);
      drainEvents();
    }
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
    // The look goes out even while the menu is up (it is picked there).
    _lookWait = math.max(0, _lookWait - dt);
    _keepLook();
    if (paused) return;
    if (phase == PuttPhase.holeScoreboard && engine.scoreboardSecondsLeft > 0) {
      // The results' pause runs on the engine's ticks, like a hole's
      // clock: the match moves on by itself at the same tick on every
      // engine (nothing else ticks it between holes).
      _accumulator += math.min(dt, 0.25);
      final step = config.physics.dt;
      var steps = 0;
      while (_accumulator >= step &&
          steps < 30 &&
          phase == PuttPhase.holeScoreboard) {
        engine.tickForward();
        _accumulator -= step;
        steps++;
      }
      if (phase != PuttPhase.holeScoreboard) _accumulator = 0;
      if (engine.pendingEventCount > 0) {
        drainEvents();
      }
      notifyListeners();
      return;
    }
    if (phase != PuttPhase.holePlay) {
      // Between holes the world is static; drop the leftover fraction so
      // the next hole starts its clock fresh. Moves that came in from the
      // wire (reactions, mostly) still surface; the world's last echoes
      // were heard with the hole.
      _accumulator = 0;
      engine.drainWorldEvents();
      if (engine.pendingEventCount > 0) {
        drainEvents();
        notifyListeners();
      }
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
      drainEvents();
      notices.addAll([...derived, ..._worldNotices()]);
      fxSpots.addAll(derivedSpots);
      _trimBatches();
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
        // The egg went in (and was put back) within the tick: its last
        // drawn spot is often still on the bank, so look a step around it.
        final entry = _entryNear(before, shape.contains);
        if (entry != null) {
          notices.add(const PuttNotice(PuttSfx.water));
          spots.add(PuttFxSpot(PuttFxSpotKind.splash, at: entry));
          // Where it came back: the egg pops up there, so the player sees
          // the stroke counted and the egg home.
          spots.add(PuttFxSpot(PuttFxSpotKind.back, at: after, who: id));
          handled = true;
          break;
        }
      }
      if (handled) continue;

      for (final well in h.wells) {
        if (well.swallowRadius <= 0) continue;
        final entry = _entryNear(
            before, (p) => p.distanceTo(well.position) <= well.swallowRadius);
        if (entry != null) {
          notices.add(const PuttNotice(PuttSfx.swallow));
          spots.add(PuttFxSpot(PuttFxSpotKind.out, at: entry));
          handled = true;
          break;
        }
      }
      if (handled) continue;

      final out = _entryNear(before, (p) => !h.bounds.contains(p));
      if (out != null) {
        notices.add(const PuttNotice(PuttSfx.out));
        spots.add(PuttFxSpot(PuttFxSpotKind.out, at: out));
      }
    }
  }

  /// The spot nearest [from] (itself, or within a frame's roll of it) for
  /// which [inside] holds, or null: where a reset egg met its hazard.
  static Vec2? _entryNear(Vec2 from, bool Function(Vec2 point) inside) {
    if (inside(from)) return from;
    for (final reach in const [0.4, 0.8, 1.2]) {
      for (var i = 0; i < 16; i++) {
        final angle = i * math.pi / 8;
        final p = Vec2(
            from.x + math.cos(angle) * reach, from.y + math.sin(angle) * reach);
        if (inside(p)) return p;
      }
    }
    return null;
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

  /// The running hole's place in its course (1-based) - the number its
  /// flag flies - or 0 between holes.
  int get holeInCourse {
    final course = engine.currentCourse;
    final current = hole;
    if (course == null || current == null) return 0;
    return course.holes.indexOf(current) + 1;
  }

  /// How many holes the running course has, 0 between courses.
  int get courseHoleCount => engine.currentCourse?.holes.length ?? 0;

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

  /// The display name of the course on the green (the catalog's localized
  /// name), or null before the match has one.
  String? get courseName {
    final course = engine.currentCourse;
    return course == null ? null : puttCourseName(course.id);
  }

  /// Whether this client has putted at all this match: the HUD's "drag to
  /// aim" hint stays up until the first stroke.
  bool get hasPutted => _hasPutted;
  bool _hasPutted = false;

  /// The newest banner line, or null when nothing is up (the widget fades
  /// headlines out after a while on its own).
  String? get headline => _headline;
  String? _headline;

  /// The banner's second line, when its kind has one: a hole start's par
  /// and course.
  String? get headlineDetail => _headlineDetail;
  String? _headlineDetail;

  /// What the banner announces, null before the first one.
  PuttHeadlineKind? get headlineKind => _headlineKind;
  PuttHeadlineKind? _headlineKind;

  /// The term a [PuttHeadlineKind.scoreTerm] banner calls, null otherwise.
  ScoreTerm? get headlineTerm => _headlineTerm;
  ScoreTerm? _headlineTerm;

  /// The engine tick the banner went up at.
  int _headlineTick = 0;

  /// How the last hole ended ("Hole cleared!", "Time's up!"): the results
  /// card's subtitle, kept apart from the banner so a score term called on
  /// the hole's last stroke keeps its own moment.
  String? get holeEndLine => _holeEndLine;
  String? _holeEndLine;

  /// Counts banner lines as they are set: the same words twice in a row
  /// still pop a fresh banner.
  int get headlineSerial => _headlineSerial;
  int _headlineSerial = 0;

  void _announce(
    PuttHeadlineKind kind,
    String text, {
    String? detail,
    ScoreTerm? term,
  }) {
    _headline = text;
    _headlineDetail = detail;
    _headlineKind = kind;
    _headlineTerm = term;
    _headlineTick = engine.tick;
    _headlineSerial++;
  }

  /// Whether the banner up now is my score term, called within the last
  /// second and a half: the hole's end then leaves it standing.
  bool get _myTermIsFresh {
    if (_headlineKind != PuttHeadlineKind.scoreTerm) return false;
    final ticks = (1.5 / config.physics.dt).round();
    return engine.tick - _headlineTick <= ticks;
  }

  /// The notices drained and not yet spent: HUD banner material and the
  /// audio service's cue list. Every drain adds to them; the game plays
  /// and clears them once a frame, so a batch drained between frames (my
  /// own putt or cast, from a press) is never lost to the next tick's.
  final List<PuttNotice> notices = [];

  // ---- player intent ----------------------------------------------------------

  /// STRIKE, exactly at [angle]: the view sends the angle its arrow shows
  /// at release (the sway included), and the engine adds nothing.
  bool submitShot(double angle, double power) {
    remoteMove
        ?.call(ShotInput(playerId: localPlayerId, angle: angle, power: power));
    final accepted = engine.submitShot(localPlayerId, angle, power);
    if (accepted) {
      _hasPutted = true;
      _afterInput();
    }
    return accepted;
  }

  /// Uses a held power-up. The targeted effects need their [target]: a
  /// spot on the green (Rabbit Hole, Gust, Sprinkler) or another player
  /// (Nest Swap, Thieving Crow); the HUD's targeting asks for it first
  /// (`putt_targeting.dart`). The engine consumes even an effect that
  /// finds nothing to do, so the inventory stays honest either way.
  bool usePowerUp(String effectId, [PowerUpTarget? target]) {
    remoteMove?.call(PowerUpInput(
        playerId: localPlayerId, effectId: effectId, target: target));
    final accepted = engine.usePowerUp(localPlayerId, effectId, target);
    if (accepted) _afterInput();
    return accepted;
  }

  /// The scoreboard's Continue: next hole (or however the phase moves on).
  bool advance() {
    if (remoteMove != null) {
      remoteMove!(const AdvanceInput());
      return true;
    }
    if (!engine.advance()) return false;
    _afterInput();
    return true;
  }

  /// Casual/barnyard vote settled: this course next.
  bool startCourse(String courseId) {
    if (remoteMove != null) {
      remoteMove!(StartCourseInput(courseId: courseId));
      return true;
    }
    if (!engine.startCourse(courseId)) return false;
    _afterInput();
    return true;
  }

  /// Leaving mid-match cleans my egg off the green.
  bool leave() {
    if (remoteMove != null) {
      remoteMove!(LeaveInput(playerId: localPlayerId));
      _afterInput();
      return true;
    }
    final accepted = engine.leave(localPlayerId);
    if (accepted) _afterInput();
    return accepted;
  }

  void _afterInput() {
    drainEvents();
    notifyListeners();
  }

  // ---- my look -------------------------------------------------------------------

  /// The look my egg wears in this match: the saved one, or what "Your
  /// egg" picked since.
  PuttLook get look => _look;
  PuttLook _look;

  /// How many times a look goes to the host before this client stops
  /// asking (a host that never takes it - an older version - is not
  /// pestered), and how long it waits between asks, seconds.
  static const int _lookAsks = 3;
  static const double _lookAskEvery = 3;

  int _lookAsked = 0;
  double _lookWait = 0;

  /// Whether the engine had a seat for me when last looked at: a new seat
  /// (a join, a rejoin) comes in the host's guess of a look, and the asks
  /// start over.
  bool _lookSeated = false;

  /// Puts on [look]: at once on a local match; on a session's wire, at
  /// home at once (like a shot) and through the host for everyone.
  void wear(PuttLook look) {
    _look = look;
    _lookAsked = 0;
    _lookWait = 0;
    _keepLook();
  }

  /// Keeps the engine's word on my look in step with mine: whenever it
  /// differs (my pick, a seat the host gave me without one, a host's
  /// snapshot from before my pick) the look goes in again, through the
  /// host on a session - a few asks at most, a few seconds apart.
  void _keepLook() {
    final me = engine.player(localPlayerId);
    if (me == null) {
      _lookSeated = false;
      return;
    }
    if (!_lookSeated) {
      _lookSeated = true;
      _lookAsked = 0;
    }
    if (me.look == _look) return;
    final move = remoteMove;
    if (move != null) {
      if (_lookWait > 0 || _lookAsked >= _lookAsks) return;
      _lookAsked++;
      _lookWait = _lookAskEvery;
      move(LookInput(playerId: localPlayerId, look: _look));
    }
    if (engine.setLook(localPlayerId, _look)) _afterInput();
  }

  // ---- reactions -----------------------------------------------------------------

  /// Sends a quick reaction ([puttReactions]) from me: through the host on
  /// a session, at once on a local match. Everyone sees it over my egg.
  bool react(String reaction) {
    if (remoteMove != null) {
      remoteMove!(ReactInput(playerId: localPlayerId, reaction: reaction));
      return true;
    }
    final accepted = engine.react(localPlayerId, reaction);
    if (accepted) _afterInput();
    return accepted;
  }

  /// The reactions of the last few seconds, oldest first: who, which, and
  /// when (on [reactionClock]).
  final List<PuttReaction> reactions = [];

  /// The clock reactions are stamped with (seconds, wall time).
  double get reactionClock =>
      DateTime.now().microsecondsSinceEpoch / Duration.microsecondsPerSecond;

  // ---- events --------------------------------------------------------------------

  /// Empties the engine's event queue into [notices], [fxSpots], the cast
  /// calls, banner lines and the per-hole bookkeeping the HUD reads, and
  /// returns this batch's notices. A bounce storm collapses to two roll
  /// noises; everything else passes through.
  List<PuttNotice> drainEvents() {
    final result = <PuttNotice>[];
    final rollNoises = <PuttNotice>[];
    _castCall = null;
    _stolenPick = null;
    for (final event in engine.drainEvents()) {
      for (final notice in _noticesFor(event)) {
        if (_isRollNoise(notice.sfx)) {
          rollNoises.add(notice);
        } else {
          result.add(notice);
        }
      }
      result.addAll(_extraNotices);
      _extraNotices.clear();
    }
    result.addAll(rollNoises.take(2));
    notices.addAll(result);
    _trimBatches();
    return result;
  }

  /// Burst anchors drained and not yet spent (the game spawns and clears
  /// them once a frame, like [notices]).
  final List<PuttFxSpot> fxSpots = [];

  /// A second sound an event makes (a cast's scene over the cast's chime).
  final List<PuttNotice> _extraNotices = [];

  /// With nobody spending them (a match with no view), the batches stop
  /// growing at a few seconds' worth.
  void _trimBatches() {
    if (notices.length > 96) notices.removeRange(0, notices.length - 96);
    if (fxSpots.length > 192) fxSpots.removeRange(0, fxSpots.length - 192);
  }

  // ---- the casts everyone sees ---------------------------------------------------

  /// The casts called so far, oldest first (the last few dozen): the cast
  /// feed under the top bar takes in the ones past its last serial.
  final List<PuttCastCall> castCalls = [];
  int _castSerial = 0;

  /// The serial of the call a cast made while its events drain: a steal
  /// or a swap rewrites it.
  int? _castCall;

  /// The thief and the power-up of a steal in this drain: its pickup is
  /// the crow's to show when it lands, not the box sparkle's.
  (String, String)? _stolenPick;

  void _call(PuttCastCall Function(int serial) make) {
    final call = make(++_castSerial);
    castCalls.add(call);
    if (castCalls.length > 24) castCalls.removeRange(0, castCalls.length - 24);
  }

  /// Rewrites the call [_castCall] names, if it is still there.
  void _recall(PuttCastCall Function(PuttCastCall call) make) {
    final serial = _castCall;
    if (serial == null) return;
    final index = castCalls.lastIndexWhere((call) => call.serial == serial);
    if (index < 0) return;
    castCalls[index] = make(castCalls[index]);
  }

  /// Where [playerId]'s egg is now, when it is out on the green.
  Vec2? _eggOf(String playerId) {
    final ball = engine.world?.ball(playerId);
    if (ball == null || ball.holed) return null;
    return ball.position;
  }

  /// The sound a cast's scene makes over the cast's chime, if it has one.
  static PuttSfx? _sceneSound(String effectId) => switch (effectId) {
        'corn_rain' => PuttSfx.cornRain,
        'gust' => PuttSfx.gust,
        'sprinkler' => PuttSfx.water,
        'nest_swap' || 'rabbit_hole' => PuttSfx.portal,
        _ => null,
      };

  List<PuttNotice> _noticesFor(PuttEvent event) {
    switch (event) {
      case HoleStarted():
        _holeNumber = event.globalIndex + 1;
        previousPositions.clear();
        currentPositions.clear();
        previousAsleep.clear();
        currentAsleep.clear();
        _holeEndLine = null;
        // The number its flag flies (the hole bar's), the match-wide one
        // when the course does not know it.
        final inCourse = holeInCourse;
        final number = inCourse > 0 ? inCourse : event.globalIndex + 1;
        final course = courseName;
        _announce(
          PuttHeadlineKind.holeStart,
          labelPuttHole(number),
          detail: course == null
              ? labelPuttPar(event.par)
              : labelPuttHoleStartDetail(event.par, course),
        );
        return [PuttNotice(PuttSfx.holeStart, title: headline)];
      case MatchStarted():
        _announce(PuttHeadlineKind.course,
            labelPuttCourseStart(puttCourseName(event.courseId)));
        return [PuttNotice(PuttSfx.click, title: headline)];
      case CourseStarted():
        _announce(PuttHeadlineKind.course,
            labelPuttCourseStart(puttCourseName(event.courseId)));
        return [PuttNotice(PuttSfx.click, title: headline)];
      case ShotApplied():
        // The next-shot power-ups on it show on the green for everyone.
        final from = _eggOf(event.playerId);
        if (from != null) {
          final heading =
              Vec2(math.cos(event.actualAngle), math.sin(event.actualAngle));
          for (final (rode, effectId) in [
            (event.steady, 'hawk_eye'),
            (event.powerMultiplier > 1, 'strong_coffee'),
            (event.hop, 'chicken_hop'),
            (event.magnet, 'nest_magnet'),
          ]) {
            if (!rode) continue;
            fxSpots.add(PuttFxSpot(PuttFxSpotKind.shot,
                who: event.playerId,
                effectId: effectId,
                at: from,
                toward: from + heading));
          }
        }
        if (event.playerId != localPlayerId) return const [];
        _hasPutted = true;
        return [PuttNotice(puttSfxFor(event.power))];
      case PlayerHoled():
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.holed, who: event.playerId));
        final term = ScoreTerm.of(event.strokes, par);
        if (event.playerId == localPlayerId) {
          _announce(PuttHeadlineKind.scoreTerm, scoreTermText(term),
              term: term);
        }
        return [
          const PuttNotice(PuttSfx.holed),
          const PuttNotice(PuttSfx.hatch),
          if (term == ScoreTerm.holeInOne) const PuttNotice(PuttSfx.crow),
        ];
      case TimerCue():
        return const [PuttNotice(PuttSfx.timerCue)];
      case TimerTick():
        return [
          PuttNotice(event.remainingSeconds.isEven
              ? PuttSfx.timerTick
              : PuttSfx.timerTock),
        ];
      case HoleEnded():
        _holeEndLine =
            event.completed ? labelPuttHoleCleared() : labelPuttHoleTimedOut();
        // My last stroke's term keeps the banner when it only just went
        // up; the results card says how the hole ended either way.
        if (!_myTermIsFresh) {
          _announce(PuttHeadlineKind.holeEnd, _holeEndLine!);
        }
        return [
          PuttNotice(
            event.completed ? PuttSfx.holeEnd : PuttSfx.timerCue,
            title: _holeEndLine,
          ),
        ];
      case PowerUpPicked():
        // What a crow just took lands in the thief's hand when the crow
        // gets there: the flight shows it (and the thief hears it then).
        final stolen = _stolenPick;
        if (stolen != null &&
            stolen.$1 == event.playerId &&
            stolen.$2 == event.effectId) {
          _stolenPick = null;
          return const [];
        }
        // The pickup's sparkle pops at whoever grabbed the "?" box (the
        // caster or a Barnyard Chaos grain); the sound stays the local
        // player's only.
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.pick, who: event.playerId));
        if (event.playerId != localPlayerId) return const [];
        return const [PuttNotice(PuttSfx.powerUpPicked)];
      case PowerUpUsed():
        // Everyone's cast is everyone's: the call in the feed, the burst
        // at the caster's egg, the chime and the scene's own sound.
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.cast,
            who: event.playerId,
            effectId: event.effectId,
            at: event.at,
            toward: event.target?.point,
            other: event.target?.playerId));
        _call((serial) => PuttCastCall(
              serial: serial,
              kind: PuttCastCallKind.cast,
              casterId: event.playerId,
              effectId: event.effectId,
              otherId: event.target?.playerId,
            ));
        _castCall = _castSerial;
        final scene = _sceneSound(event.effectId);
        if (scene != null) _extraNotices.add(PuttNotice(scene));
        return const [PuttNotice(PuttSfx.powerUpUsed)];
      case PowerUpStolen():
        // The crow's cast becomes the theft: who took what from whom.
        _recall((call) => PuttCastCall(
              serial: call.serial,
              kind: PuttCastCallKind.steal,
              casterId: event.thiefId,
              effectId: call.effectId,
              otherId: event.victimId,
              stolenId: event.effectId,
            ));
        _stolenPick = (event.thiefId, event.effectId);
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.steal,
            who: event.thiefId,
            other: event.victimId,
            effectId: event.effectId,
            at: _eggOf(event.victimId)));
        return const [PuttNotice(PuttSfx.crowCaw)];
      case ShieldBlocked():
        PuttCastCall blocked(int serial) => PuttCastCall(
              serial: serial,
              kind: PuttCastCallKind.blocked,
              casterId: event.casterId,
              effectId: event.effectId,
              otherId: event.playerId,
            );
        // A cast aimed at one player (a theft, a swap) that their shell
        // stopped says so in its own toast, at once; an area cast keeps
        // its call and adds one per shell that held.
        final aimed =
            event.effectId == 'thieving_crow' || event.effectId == 'nest_swap';
        if (aimed && _castCall != null) {
          _recall((call) => blocked(call.serial));
          _castCall = null;
        } else {
          _call(blocked);
        }
        fxSpots.add(PuttFxSpot(PuttFxSpotKind.shieldPop,
            who: event.playerId,
            effectId: event.effectId,
            other: event.casterId,
            at: _eggOf(event.playerId)));
        return const [PuttNotice(PuttSfx.shieldPop)];
      case PowerUpHit():
        for (final id in event.playerIds) {
          fxSpots.add(PuttFxSpot(PuttFxSpotKind.hit,
              who: id,
              other: event.casterId,
              effectId: event.effectId,
              at: _eggOf(id)));
        }
        // A swap that moved my egg is a swap with me: the call says so.
        if (event.effectId == 'nest_swap' &&
            event.casterId != localPlayerId &&
            event.playerIds.contains(localPlayerId)) {
          _recall((call) => PuttCastCall(
                serial: call.serial,
                kind: PuttCastCallKind.swap,
                casterId: call.casterId,
                effectId: call.effectId,
                otherId: localPlayerId,
              ));
        }
        _castCall = null;
        return const [];
      case MatchEnded():
        _announce(PuttHeadlineKind.matchOver, labelPuttMatchOver());
        return [PuttNotice(PuttSfx.victory, title: headline)];
      case PlayerLookChanged():
        // A new shell on an egg out on the green: a puff as it comes on.
        final at = _eggOf(event.playerId);
        if (at != null) {
          fxSpots.add(
              PuttFxSpot(PuttFxSpotKind.restyle, who: event.playerId, at: at));
        }
        return const [];
      case PlayerReacted():
        final now = reactionClock;
        reactions
          ..removeWhere((r) => now - r.at > PuttReaction.life)
          ..add(PuttReaction(event.playerId, event.reaction, now));
        return const [];
      default:
        return const [];
    }
  }

  /// Physics noise the egg makes by rolling: many per tick are collapsed
  /// to the loudest (the noise trimmer keeps at most one of each kind).
  bool _isRollNoise(PuttSfx sfx) =>
      sfx == PuttSfx.bounce || sfx == PuttSfx.bumper;

  // ---- the world's echoes ---------------------------------------------------------

  /// Under this an egg is rolling along a rail, not hitting it (units/s
  /// into the surface).
  static const double quietImpact = 1.2;

  /// A walker nudging a resting egg is worth a word from far less.
  static const double quietNudge = 0.6;

  /// The engine tick each egg last knocked on: a rattle along a rail
  /// stays a knock, not a drum roll.
  final Map<String, int> _lastKnock = {};
  int? _lastWalkerWord;

  /// Whether [last] (an engine tick) is under [seconds] ago. A tick from
  /// the future - a guest's resnapshot can step the clock back - is long
  /// ago.
  bool _within(int? last, double seconds) {
    if (last == null) return false;
    final since = engine.tick - last;
    return since >= 0 && since < (seconds / config.physics.dt).round();
  }

  /// The world's echoes since the last frame as sounds: rails, bumpers,
  /// eggs meeting and the walkers' bumps, each as loud as the hit (another
  /// player's egg a little quieter than mine), and the speed strips. At
  /// most the two hardest hits a frame.
  List<PuttNotice> _worldNotices() {
    final hits = <(double, PuttNotice)>[];
    final rest = <PuttNotice>[];
    for (final event in engine.drainWorldEvents()) {
      switch (event) {
        case BallBounced():
          final notice = _bounceNotice(event);
          if (notice != null) hits.add((event.impactSpeed, notice));
        case BallBoosted():
          rest.add(const PuttNotice(PuttSfx.boost));
        default:
          break;
      }
    }
    hits.sort((a, b) => b.$1.compareTo(a.$1));
    return [...rest, for (final (_, notice) in hits.take(2)) notice];
  }

  PuttNotice? _bounceNotice(BallBounced event) {
    final walker = event.kind == BounceKind.obstacle;
    if (event.impactSpeed < (walker ? quietNudge : quietImpact)) return null;
    // Two eggs meeting report it from both sides: one clack.
    final other = event.otherPlayerId;
    if (other != null && other.compareTo(event.playerId) < 0) return null;
    if (walker) {
      // A hen with an egg against her says it once.
      if (_within(_lastWalkerWord, 0.6)) return null;
      _lastWalkerWord = engine.tick;
    } else {
      if (_within(_lastKnock[event.playerId], 0.075)) return null;
      _lastKnock[event.playerId] = engine.tick;
    }
    final hard = ((event.impactSpeed - quietImpact) / 12).clamp(0.0, 1.0);
    final mine = event.playerId == localPlayerId || other == localPlayerId;
    final sfx = switch (event.kind) {
      BounceKind.bumper => PuttSfx.bumper,
      BounceKind.ball => PuttSfx.clack,
      BounceKind.obstacle => _walkerAt(event.at),
      _ => PuttSfx.bounce,
    };
    return PuttNotice(sfx,
        volume: walker ? 1.0 : (0.3 + 0.7 * hard) * (mine ? 1 : 0.7));
  }

  /// Who an egg bumped into, by the world's own rule: ducks paddle the
  /// Pond (a duck by name, or one whose path crosses water), hens walk the
  /// rest; on a hole with both, the walker whose stops lie nearest.
  PuttSfx _walkerAt(Vec2 at) {
    final h = hole;
    if (h == null) return PuttSfx.hen;
    MovingObstacle? nearest;
    var best = double.infinity;
    for (final walker in h.obstacles) {
      for (final stop in walker.stops) {
        final distance = stop.at.distanceTo(at);
        if (distance < best) {
          best = distance;
          nearest = walker;
        }
      }
    }
    if (nearest == null) return PuttSfx.hen;
    final swims = nearest.id.contains('duck') ||
        nearest.stops
            .any((stop) => h.water.any((pond) => pond.contains(stop.at)));
    return swims ? PuttSfx.duck : PuttSfx.hen;
  }
}

/// The tock a putt of [power] (0..1) makes: a tap, a stroke, a whack.
PuttSfx puttSfxFor(double power) {
  if (power < 0.3) return PuttSfx.puttSoft;
  if (power >= 0.7) return PuttSfx.puttFirm;
  return PuttSfx.putt;
}

/// A quick reaction someone sent: who, which ([puttReactions]), and when
/// (on [PuttMatch.reactionClock]).
class PuttReaction {
  final String playerId;
  final String reaction;
  final double at;

  const PuttReaction(this.playerId, this.reaction, this.at);

  /// How long a reaction's bubble stays up, seconds.
  static const double life = 2.4;
}

/// The display name of a player id: the match's map, its roster lookup,
/// then the id itself.
String displayNameOf(PuttMatch match, String playerId) =>
    match.displayNames[playerId] ?? match.nameOf?.call(playerId) ?? playerId;

/// The display name of a course id: the catalog's localized name, or the
/// id itself for a course outside the catalog (the stubs tests play).
String puttCourseName(String courseId) {
  for (final course in sunnySidePuttCourses) {
    if (course.id == courseId) return course.displayName();
  }
  return courseId;
}

/// A player's egg tint, the colour their egg, name tag and scorecard dot
/// share: the player's place among the eggs on the green (in id order),
/// else among the engine's players.
ui.Color puttTintOf(PuttMatch match, String playerId) {
  final ids = match.currentPositions.keys.toList()..sort();
  var index = ids.indexOf(playerId);
  if (index < 0) {
    index = match.engine.players.indexWhere((p) => p.id == playerId);
  }
  return PuttPalette.tintForIndex(index.clamp(0, 7));
}

/// A player's look, as the engine has it: the pattern on their egg and the
/// scorecard's, the hat on their chick and their tag's egg (the default
/// for anyone the engine does not know).
PuttLook puttLookOf(PuttMatch match, String playerId) =>
    match.engine.player(playerId)?.look ?? PuttLook.standard;

// ---- strings -------------------------------------------------------------------

String labelPuttHole(int hole) => Intl.message("Hole $hole",
    name: "labelPuttHole",
    args: [hole],
    desc: "The big line of the banner a hole starts with; the placeholder "
        "is the number of the hole in its course");

String labelPuttPar(int par) => Intl.message("Par $par",
    name: "labelPuttPar",
    args: [par],
    desc: "The hole's par - the strokes it should take - under a hole "
        "start's banner when the course has no name to add");

String labelPuttHoleStartDetail(int par, String course) =>
    Intl.message("Par $par · $course",
        name: "labelPuttHoleStartDetail",
        args: [par, course],
        desc: "The second line of the banner a hole starts with, under its "
            "number: the hole's par, then the course's name");

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

String labelPuttTermHoleInOne() => Intl.message("Hole in one!",
    name: "labelPuttTermHoleInOne", desc: "One stroke on a hole of any par");

String labelPuttTermAlbatross() => Intl.message("Albatross!",
    name: "labelPuttTermAlbatross", desc: "Three strokes under par");

String labelPuttTermEagle() => Intl.message("Eagle!",
    name: "labelPuttTermEagle", desc: "Two strokes under par");

String labelPuttTermBirdie() => Intl.message("Birdie!",
    name: "labelPuttTermBirdie", desc: "One stroke under par");

String labelPuttTermPar() => Intl.message("Par",
    name: "labelPuttTermPar", desc: "Exactly the hole's par");

String labelPuttTermBogey() => Intl.message("Bogey",
    name: "labelPuttTermBogey", desc: "One stroke over par");

String labelPuttTermDoubleBogey() => Intl.message("Double bogey",
    name: "labelPuttTermDoubleBogey", desc: "Two strokes over par");

String labelPuttTermTripleBogey() => Intl.message("Triple bogey",
    name: "labelPuttTermTripleBogey", desc: "Three strokes over par");

String labelPuttTermMore() => Intl.message("In the nest",
    name: "labelPuttTermMore",
    desc: "Four or more strokes over par: holed, but no golf term "
        "left to call it");

String scoreTermText(ScoreTerm term) {
  switch (term) {
    case ScoreTerm.holeInOne:
      return labelPuttTermHoleInOne();
    case ScoreTerm.albatross:
      return labelPuttTermAlbatross();
    case ScoreTerm.eagle:
      return labelPuttTermEagle();
    case ScoreTerm.birdie:
      return labelPuttTermBirdie();
    case ScoreTerm.par:
      return labelPuttTermPar();
    case ScoreTerm.bogey:
      return labelPuttTermBogey();
    case ScoreTerm.doubleBogey:
      return labelPuttTermDoubleBogey();
    case ScoreTerm.tripleBogey:
      return labelPuttTermTripleBogey();
    case ScoreTerm.more:
      return labelPuttTermMore();
  }
}
