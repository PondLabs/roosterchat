// The game view of Sunny Side Putt: a Flame-rendered, top-down cartoon
// farm green under an orbiting 3D camera - a miniature-farm diorama - with
// slingshot aim, an animated crowd of eggs, nest suction, splashes and
// sparkle bursts, wrapped by the Flutter HUD and menus.
//
// Split of work:
//   * [SunnySidePuttView] - the Flutter shell: the GameWidget, pointer
//     plumbing (the main button putts, a secondary-button drag and the
//     wheel/pinch orbit and zoom the camera), Esc-to-pause, the HUD, the
//     menus and the spectator strip (their own files), and the audio
//     service's cue tap.
//   * [SunnySidePuttGame] - the FlameGame: the orbit camera fitted to the
//     hole, the fixed-tick simulation driven through `PuttMatch.update`,
//     and the paintable layers.
//   * [PuttSceneLayer] - the one Flame layer, which collects the frame's
//     scene and hands it to the perspective renderer.
//
// Art is code-drawn: the volumes and ground in `putt_render3d.dart`
// (projected through `putt_camera.dart`), the eggs, the hen and the
// rooster host in `putt_art.dart` from the Rooster palette - ink outlines,
// Cream lawn, Spruce hedges, Yolk accents - the host (comb worn as a
// crown) standing at the green's edge as the round's emcee. Nothing here
// touches the network: the match is the local harness over the rules
// engine (`putt_match.dart`); the session wires the authoritative host
// under the same seams later.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart'
    as hole;
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart'
    as core;

import 'aim_controller.dart';
import 'putt_art.dart';
import 'putt_audio.dart';
import 'putt_camera.dart';
import 'putt_hud.dart';
import 'putt_match.dart';
import 'putt_menus.dart';
import 'putt_render3d.dart';
import 'spectator_strip.dart';

/// The whole putter experience on the call's stage: game, HUD, menus.
class SunnySidePuttView extends StatefulWidget {
  /// The match to play. A solo stub match is created when left out.
  final PuttMatch? match;

  /// The audio service, when the shell should make sound. Left out, the
  /// view is silent (widget tests pass nothing).
  final PuttAudio? audio;

  /// Called when the player leaves the match from the pause menu.
  final VoidCallback? onLeave;

  const SunnySidePuttView({super.key, this.match, this.audio, this.onLeave});

  /// Standalone launch, session-less: a solo stub match with audio.
  static Widget solo({PuttAudio? audio}) => SunnySidePuttView(
        match: PuttMatch.solo(),
        audio: audio ?? PuttAudio()
          ..preload(),
      );

  @override
  State<SunnySidePuttView> createState() => _SunnySidePuttViewState();
}

class _SunnySidePuttViewState extends State<SunnySidePuttView> {
  late PuttMatch match;
  SunnySidePuttGame? game;
  bool menuOpen = false;
  bool settingsOpen = false;

  /// Where Esc lands: the view holds the focus while the game does. The
  /// GameWidget keeps its own node under it (autofocus off), so the two
  /// never fight over the keyboard.
  final FocusNode _keyFocus = FocusNode(debugLabel: 'sunny-side-putt');
  final FocusNode _gameFocus =
      FocusNode(debugLabel: 'sunny-side-putt-game', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    match = widget.match ?? PuttMatch.solo();
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _gameFocus.dispose();
    super.dispose();
  }

  SunnySidePuttGame _createGame() {
    final created = SunnySidePuttGame(
      match: match,
      onSfx: (sfx) => widget.audio?.play(sfx),
    );
    return created;
  }

  void _togglePause() {
    setState(() {
      menuOpen = !menuOpen;
      settingsOpen = false;
      match.paused = menuOpen;
    });
    widget.audio?.play(PuttSfx.click);
  }

  void _leave() {
    match.leave();
    widget.audio?.play(PuttSfx.click);
    final leave = widget.onLeave;
    if (leave != null) {
      leave();
      return;
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    debugPrint('PUTT KEY: ${event.logicalKey} ${event.runtimeType}');
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (settingsOpen) {
        setState(() => settingsOpen = false);
        return KeyEventResult.handled;
      }
      if (match.phase != PuttPhase.awaitingNextCourse) {
        _togglePause();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---- pointer plumbing ----------------------------------------------------------------

  /// The pointers currently on the surface, and where they sit, so the
  /// pinch can measure the span between two fingers.
  final Set<int> _downPointers = {};
  final Map<int, Offset> _pointerAt = {};

  /// The pointer dragging the camera's orbit (secondary button), and its
  /// last position for the drag delta.
  int? _orbitPointer;
  Offset? _orbitLastPosition;

  /// The pinch in progress: the span at its start and the camera
  /// distance it began from.
  double? _pinchSpan;
  double? _pinchDistance;

  void _pointerDown(PointerDownEvent event, Size size) {
    final game = this.game;
    if (game == null) return;
    _downPointers.add(event.pointer);
    _pointerAt[event.pointer] = event.localPosition;
    // A secondary-button drag orbits; only the main button putts.
    if (event.buttons == kSecondaryMouseButton) {
      _orbitPointer = event.pointer;
      _orbitLastPosition = event.localPosition;
      return;
    }
    // A second finger: pinch zoom takes over, the aim lets go.
    if (_downPointers.length >= 2) {
      game.cancelAim();
      _pinchSpan = _pointerSpan();
      _pinchDistance = game.view3d.distance;
      return;
    }
    final world = _toWorld(event.localPosition);
    if (world != null) game.beginAim(world);
  }

  void _pointerMove(PointerEvent event, Size size) {
    final game = this.game;
    if (game == null) return;
    _pointerAt[event.pointer] = event.localPosition;
    // The orbit drag: turn the yaw, tilt the pitch.
    if (_orbitPointer == event.pointer) {
      final last = _orbitLastPosition;
      if (last != null) {
        game.view3d.orbitBy(
          event.localPosition.dx - last.dx,
          event.localPosition.dy - last.dy,
        );
      }
      _orbitLastPosition = event.localPosition;
      return;
    }
    // The pinch: closing fingers move the camera nearer.
    if (_pinchSpan != null && _downPointers.length >= 2) {
      final span = _pointerSpan();
      if (span > 8) {
        game.view3d
            .pinch(span / _pinchSpan!, distanceAtGestureStart: _pinchDistance!);
      }
      return;
    }
    final world = _toWorld(event.localPosition);
    if (world != null) game.moveAim(world);
  }

  void _pointerUp(PointerEvent event, Size size) {
    _downPointers.remove(event.pointer);
    _pointerAt.remove(event.pointer);
    final orbiting = _orbitPointer == event.pointer;
    if (orbiting) {
      _orbitPointer = null;
      _orbitLastPosition = null;
    }
    if (_downPointers.length < 2) _pinchSpan = null;
    final game = this.game;
    if (game == null || orbiting || _pinchSpan != null) return;
    final world = _toWorld(event.localPosition);
    if (world != null) game.endAim(world);
  }

  void _pointerCancel(PointerEvent event, Size size) {
    _downPointers.remove(event.pointer);
    _pointerAt.remove(event.pointer);
    if (_orbitPointer == event.pointer) {
      _orbitPointer = null;
      _orbitLastPosition = null;
    }
    if (_downPointers.length < 2) _pinchSpan = null;
    game?.cancelAim();
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      game?.view3d.zoomByWheel(event.scrollDelta.dy);
    }
  }

  /// The distance between the first two pointers on the surface, 0 when
  /// fewer than two report positions.
  double _pointerSpan() {
    final known = _downPointers
        .map((pointer) => _pointerAt[pointer])
        .whereType<Offset>()
        .toList(growable: false);
    if (known.length < 2) return 0;
    return (known[0] - known[1]).distance;
  }

  /// Screen (widget-local) coordinates into the ground plane, through
  /// the 3D camera; null when the pixel misses the ground (the sky over
  /// the horizon), and the caller does nothing.
  core.Vec2? _toWorld(Offset at) {
    final game = this.game;
    if (game == null) return null;
    return game.screenToWorld(Vector2(at.dx, at.dy));
  }

  @override
  Widget build(BuildContext context) {
    final showVote = match.phase == PuttPhase.awaitingNextCourse && !menuOpen;
    return Focus(
      focusNode: _keyFocus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Scaffold(
        backgroundColor: PuttPalette.apron,
        body: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              // The green, with the pointer plumbing into world space.
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _pointerDown(event, size),
                onPointerMove: (event) => _pointerMove(event, size),
                onPointerUp: (event) => _pointerUp(event, size),
                onPointerCancel: (event) => _pointerCancel(event, size),
                onPointerSignal: _pointerSignal,
                child: GameWidget(
                  game: game ??= _createGame(),
                  focusNode: _gameFocus,
                  autofocus: false,
                ),
              ),
              // HUD, with only its buttons eating pointers.
              IgnorePointer(
                ignoring: false,
                child: PuttHud(
                  match: match,
                  onSfx: (sfx) => widget.audio?.play(sfx),
                  onOpenMenu: _togglePause,
                ),
              ),
              // The fence-side strip while watching.
              if (match.isSpectator)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 112,
                  child: IgnorePointer(child: SpectatorStrip(match: match)),
                ),
              if (showVote)
                Center(
                  child: PuttVoteSheet(
                    options: match.config.catalog.length > 1
                        ? [
                            for (final course in match.config.catalog.values)
                              course
                          ]
                        : match.config.courses,
                    onPick: (courseId) {
                      match.startCourse(courseId);
                      setState(() {});
                    },
                  ),
                ),
              if (menuOpen)
                Align(
                  alignment: Alignment.center,
                  child: settingsOpen
                      ? PuttSettingsSheet(
                          buses: widget.audio?.buses ?? PuttSilentBuses(),
                          onClose: () => setState(() => settingsOpen = false),
                        )
                      : PuttPauseMenu(
                          match: match,
                          onOpenSettings: () =>
                              setState(() => settingsOpen = true),
                          onResume: _togglePause,
                          onLeave: _leave,
                        ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ---- the Flame game -----------------------------------------------------------------

/// The game itself: the match ticking through its fixed steps, the orbit
/// camera fitted to the hole and eased one frame at a time, and the one
/// scene layer painting the diorama (`putt_render3d.dart`). The aim, the
/// sounds and the HUD keep their own seams (`AimController`, `onSfx`,
/// `PuttHud`).
class SunnySidePuttGame extends FlameGame {
  final PuttMatch match;

  /// The audio tap: strokes, bounces, timers, the works.
  final void Function(PuttSfx sfx) onSfx;

  final AimController aim = AimController();

  /// The board's own 3D camera (not Flame's flat one): orbit, tilt and
  /// zoom over the green.
  final PuttCamera view3d = PuttCamera();

  /// Seconds since the game booted, for art that breathes.
  double clock = 0;

  /// The one Flame layer painting the frame.
  late final PuttSceneLayer scene;

  /// The aim's clock, for the arrow's sway.
  late final PuttAimLayer aimLayer;

  late final PuttFxLayer fx;

  /// The hop rides, per player: the cosmetic arc of a Chicken Hop, keyed
  /// off the engine's own flag and sized by the egg's launch speed.
  final Map<String, _HopRide> _hopRides = {};

  String? _fittedHole;

  SunnySidePuttGame({required this.match, required this.onSfx});

  @override
  Future<void> onLoad() async {
    scene = PuttSceneLayer(this);
    aimLayer = PuttAimLayer(this);
    fx = PuttFxLayer();
    await world.add(scene);
    _fitCamera();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _fitCamera();
  }

  /// Frames the current hole: viewport pixels first, then the bounds.
  /// A hole change refits; the same hole re-fits only on resize.
  void _fitCamera() {
    final hole = match.hole;
    if (hole == null || size.x == 0 || size.y == 0) return;
    view3d
      ..setViewport(ui.Size(size.x, size.y))
      ..fitToHole(hole.bounds);
    _fittedHole = hole.id;
  }

  @override
  void update(double dt) {
    clock += dt;
    super.update(dt);
    match.update(dt);
    aim.noWobble = match.myNextShotSteady;
    aimLayer.update(dt);
    fx.update(dt);
    _updateHopRides();
    final holeId = match.hole?.id;
    if (holeId != null && holeId != _fittedHole) {
      _fitCamera();
      aim.cancel();
    }
    if (match.phase != PuttPhase.holePlay) aim.cancel();
    view3d.update(dt, followPoint: _cameraFollowPoint());
    _spendNotices();
    _spendFxSpots();
  }

  /// The point the camera's target glides toward: my egg while the hole
  /// plays (a spectator drifts to whoever is out there); held while
  /// aiming, so a moving frame never slides out from under a drag.
  core.Vec2? _cameraFollowPoint() {
    if (aim.isActive || match.phase != PuttPhase.holePlay) return null;
    final egg = match.myEggRenderPosition;
    if (egg != null) return egg;
    for (final player in match.engine.players) {
      if (player.spectator) continue;
      if (match.currentPositions.containsKey(player.id)) {
        return match.renderPositionOf(player.id);
      }
    }
    return null;
  }

  /// The cosmetic lift of a hopping egg: 0 when the ride is over, a
  /// parabola over the roll's progress (read off the speed decay) while
  /// the hop flag is up. The engine stays planar; only the drawing lifts.
  double eggHeightOf(BallBody ball) {
    final ride = _hopRides[ball.playerId];
    if (ride == null) return 0;
    final t = (1 - ball.speed / ride.launchSpeed).clamp(0.0, 1.0);
    final maxLift = match.config.physics.ballRadius * 2.6;
    return 4 * maxLift * t * (1 - t);
  }

  /// Keeps [_hopRides] honest: a ride starts at the first moving frame
  /// with the hop flag, dies when the egg settles (the flag's own rule).
  void _updateHopRides() {
    final world = match.engine.world;
    if (world == null) {
      _hopRides.clear();
      return;
    }
    _hopRides.removeWhere((playerId, _) {
      final ball = world.ball(playerId);
      return ball == null ||
          ball.asleep ||
          ball.holed ||
          !ball.flagActive(PowerUpFlag.hop, world.tick);
    });
    for (final ball in world.balls) {
      if (ball.asleep || ball.holed) continue;
      if (!ball.flagActive(PowerUpFlag.hop, world.tick)) continue;
      if (ball.speed < 1.0) continue;
      _hopRides.putIfAbsent(
        ball.playerId,
        () => _HopRide(launchSpeed: math.max(ball.speed, 1.0)),
      );
    }
  }

  /// Plays this batch's sounds once and drops them (the match refills the
  /// list with the next batch's); without this, an idle frame re-fires
  /// the last batch every frame until the next drain.
  void _spendNotices() {
    if (match.notices.isEmpty) return;
    for (final notice in match.notices) {
      onSfx(notice.sfx);
    }
    match.notices.clear();
  }

  /// Spawns this batch's bursts once, then drops the batch (same rule as
  /// the sounds above).
  void _spendFxSpots() {
    if (match.fxSpots.isEmpty) return;
    for (final spot in match.fxSpots) {
      switch (spot.kind) {
        case PuttFxSpotKind.splash:
          if (spot.at != null) fx.splash(spot.at!);
        case PuttFxSpotKind.out:
          if (spot.at != null) fx.poof(spot.at!);
        case PuttFxSpotKind.holed:
          final nest = match.hole?.nest.position;
          if (spot.who != null && nest != null) {
            fx.suction(nest, tintFor(spot.who!));
          }
        case PuttFxSpotKind.pick:
          final at = spot.who == null ? null : match.currentPositions[spot.who];
          if (at != null) fx.sparkles(at);
      }
    }
    match.fxSpots.clear();
  }

  // ---- pointer plumbing ---------------------------------------------------------------

  /// Screen (widget-local) coordinates into the ground plane, through
  /// the camera. Null when the pixel misses the green entirely (the sky
  /// above the horizon), and the caller does nothing.
  core.Vec2? screenToWorld(Vector2 screen) {
    return view3d.screenToWorld(ui.Offset(screen.x, screen.y));
  }

  /// Aims only when my egg is on the green and settled, and only from near
  /// it (a full-screen thrash must not strike).
  void beginAim(core.Vec2 point) {
    if (!match.myShotReady) return;
    final ball = match.myBall;
    if (ball == null) return;
    final reach = math.max(match.config.physics.ballRadius * 3, 1.8);
    if (ball.position.distanceTo(point) > reach) return;
    aim.begin(ball.position);
    aim.update(point);
  }

  void moveAim(core.Vec2 point) {
    if (aim.isActive) aim.update(point);
  }

  void endAim(core.Vec2 point) {
    if (!aim.isActive) return;
    aim.update(point);
    final shot = aim.commit();
    if (shot == null) return;
    match.submitShot(shot.angle, shot.power);
  }

  void cancelAim() => aim.cancel();

  // ---- attached facts the layers read ---------------------------------------------------

  /// Egg ring colours, stable per player in id order.
  ui.Color tintFor(String playerId) {
    final ids = match.currentPositions.keys.toList()..sort();
    var index = ids.indexOf(playerId);
    if (index < 0) {
      index = match.engine.players.indexWhere((p) => p.id == playerId);
    }
    return PuttPalette.tintForIndex(index.clamp(0, 7));
  }

  double get eggRadius => match.config.physics.ballRadius;

  @override
  ui.Color backgroundColor() => PuttPalette.apron;
}

/// One egg's hop: how fast it left, so the drawn arc knows its length.
class _HopRide {
  final double launchSpeed;

  const _HopRide({required this.launchSpeed});
}

// ---- layers ---------------------------------------------------------------------------

/// The one Flame layer on the board: collects the frame's scene from the
/// match and hands it to the perspective renderer (`putt_render3d.dart`),
/// which sorts and paints it.
class PuttSceneLayer extends Component {
  final SunnySidePuttGame game;

  PuttSceneLayer(this.game);

  @override
  void render(ui.Canvas canvas) {
    final hole = game.match.hole;
    final world = game.match.engine.world;
    final eggs = <PuttEggView>[];
    final hens = <PuttHenView>[];
    PuttAimView? aimView;
    var fxViews = const <PuttFxView>[];
    if (hole != null) {
      if (world != null) {
        for (final ball in world.balls) {
          if (ball.holed) continue; // in the nest; the suction told the story
          eggs.add(PuttEggView(
            position: game.match.renderPositionOf(ball.playerId),
            height: game.eggHeightOf(ball),
            velocity: ball.velocity,
            tint: game.tintFor(ball.playerId),
            radius: game.eggRadius,
          ));
        }
        for (final obstacle in hole.obstacles) {
          final tickSeconds = game.match.config.physics.dt;
          final now = henPositionAt(obstacle, world.tick, tickSeconds);
          final then = henPositionAt(obstacle, world.tick + 1, tickSeconds);
          final at = ui.Offset.lerp(
            ui.Offset(now.x, now.y),
            ui.Offset(then.x, then.y),
            game.match.alpha,
          );
          hens.add(PuttHenView(
            position: core.Vec2(at?.dx ?? now.x, at?.dy ?? now.y),
            radius: obstacle.radius,
            phase: (world.tick + game.match.alpha) * 0.6,
          ));
        }
      }
      final aim = game.aim;
      final state = aim.state;
      if (aim.isActive && state != null) {
        aimView = PuttAimView(
          origin: aim.origin!,
          angle: state.angle + aim.visualWobble(game.aimLayer.holdSeconds),
          power: state.power,
          dragLength: state.dragLength,
          eggRadius: game.eggRadius,
        );
      }
      fxViews = [
        for (final particle in game.fx.particles) particle.view(),
      ];
    }
    renderPuttScene(
      canvas,
      game.view3d,
      PuttSceneInput(
        time: game.clock,
        hole: hole,
        eggRadius: game.eggRadius,
        eggs: eggs,
        hens: hens,
        aim: aimView,
        fxs: fxViews,
      ),
    );
  }
}

/// The aim's clock: how long the current drag has held, which drives the
/// arrow's sway (the aim's own math lives in `aim_controller.dart`, the
/// ground-plane drawing in `putt_render3d.dart`).
class PuttAimLayer {
  final SunnySidePuttGame game;

  /// Seconds the aim has been held, for the sway's clock.
  double holdSeconds = 0;

  PuttAimLayer(this.game);

  void update(double dt) {
    holdSeconds = game.aim.isActive ? holdSeconds + dt : 0;
  }
}

/// The bursts: splash droplets, suction rings, poofs, pickup sparkles.
/// Each lives about half a second, on plain velocity math, no shaders. A
/// plain pool now: the game ticks it every frame, the scene layer paints
/// from it through the renderer.
class PuttFxLayer {
  final List<_FxParticle> _particles = [];

  /// The live particles, for the scene layer's paintables.
  List<_FxParticle> get particles => _particles;

  void splash(core.Vec2 at) {
    for (var i = 0; i < 14; i++) {
      final angle = i * 2.39996; // golden spaced
      final speed = 1.6 + (i % 4) * 0.8;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * speed,
        life: 0.6,
        kind: _FxKind.droplet,
        size: 0.22,
      ));
    }
  }

  void suction(core.Vec2 at, ui.Color tint) {
    for (var i = 0; i < 10; i++) {
      final angle = i * 2.39996 + 1;
      _particles.add(_FxParticle(
        at: at + core.Vec2(math.cos(angle), math.sin(angle)) * (1.2 + i * 0.1),
        velocity: core.Vec2.zero,
        life: 0.5,
        kind: _FxKind.suction,
        size: 0.18,
        toward: at,
        color: tint,
      ));
    }
  }

  void sparkles(core.Vec2 at) {
    for (var i = 0; i < 8; i++) {
      final angle = i / 8 * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * 1.3,
        life: 0.55,
        kind: _FxKind.sparkle,
        size: 0.22,
        color: PuttPalette.yolk,
      ));
    }
  }

  void poof(core.Vec2 at) {
    for (var i = 0; i < 7; i++) {
      final angle = i / 7 * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * 0.8,
        life: 0.45,
        kind: _FxKind.poof,
        size: 0.3,
        color: PuttPalette.stone,
      ));
    }
  }

  bool get isEmpty => _particles.isEmpty;

  void update(double dt) {
    for (final particle in _particles) {
      particle.age += dt;
      particle.advance(dt);
    }
    _particles.removeWhere((particle) => particle.age >= particle.life);
  }
}

// ---- particles -------------------------------------------------------------------------

enum _FxKind { droplet, sparkle, suction, poof }

class _FxParticle {
  core.Vec2 position;
  core.Vec2 velocity;

  /// Where a suction particle flies home to.
  final core.Vec2? toward;

  double age = 0;
  final double life;
  final _FxKind kind;
  final double size;

  /// Null keeps the kind's own color.
  final ui.Color? color;

  _FxParticle({
    required core.Vec2 at,
    required this.velocity,
    required this.life,
    required this.kind,
    required this.size,
    this.toward,
    this.color,
  }) : position = at;

  void advance(double dt) {
    position = position + velocity * dt;
    velocity = velocity + velocity * (-2.2 * dt);
  }

  /// The renderer's view of this particle this frame.
  PuttFxView view() {
    final kind = switch (this.kind) {
      _FxKind.droplet => PuttFxKind.droplet,
      _FxKind.sparkle => PuttFxKind.sparkle,
      _FxKind.suction => PuttFxKind.suction,
      _FxKind.poof => PuttFxKind.poof,
    };
    return PuttFxView(
      kind: kind,
      at: position,
      toward: toward,
      progress: (age / life).clamp(0.0, 1.0),
      size: size,
      color: color,
    );
  }
}

// ---- the hen's path, rendered -------------------------------------------------------------

/// The obstacle's position at [tick], the physics's own path walk, re-done
/// here for the DRAWING only: the phase walk must never drive the
/// simulation, and the helper lives private in the physics. Kept an exact
/// copy of the rounding, so hens render exactly where they act.
core.Vec2 henPositionAt(
    hole.MovingObstacle obstacle, int tick, double tickSeconds) {
  final stops = obstacle.stops;
  if (stops.isEmpty) return core.Vec2.zero;
  if (stops.length == 1) return stops.first.at;
  final count = stops.length;
  final travel = [
    for (final stop in stops) (stop.travelSecondsToNext / tickSeconds).round(),
  ];
  final dwell = [
    for (final stop in stops) (stop.dwellSeconds / tickSeconds).round(),
  ];
  var period = 0;
  for (var i = 0; i < count; i++) {
    period += dwell[i] + travel[i];
  }
  if (period <= 0) return stops.first.at;
  var phase = tick % period;
  if (phase < 0) phase += period;
  var index = 0;
  var guard = 0;
  while (guard++ <= count * 2) {
    if (phase < dwell[index]) return stops[index].at;
    phase -= dwell[index];
    if (phase < travel[index]) {
      final next = (index + 1) % count;
      return stops[index].at.lerp(stops[next].at, phase / travel[index]);
    }
    phase -= travel[index];
    index = (index + 1) % count;
  }
  return stops.first.at;
}
