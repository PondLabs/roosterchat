// The game view of Sunny Side Putt: the real-3D farm (the three_js engine -
// perspective camera, sun with soft shadows, the course on its table in a
// meadow, see `putt_world3d.dart`) slung under the Flutter HUD, with
// slingshot aim from anywhere on the green, the predicted roll's dotted
// guide, eggs that roll and settle, nest confetti, splashes and sparkles,
// name tags over the other players' eggs, wrapped by the HUD and menus.
//
// Split of work:
//   * [SunnySidePuttView] - the Flutter shell: the GPU surface (the three_js
//     view), pointer plumbing (the main button putts, a secondary-button
//     drag and the wheel/pinch orbit and zoom the camera), Esc-to-pause,
//     the HUD (rebuilt as the match moves), the name tags, the menus and
//     the spectator strip (their own files), and the audio service's cue
//     tap.
//   * [SunnySidePuttGame] - the match's ticker and the world's frame
//     builder: the orbit rig fitted to the hole (the overview first, then
//     in close to the egg), the fixed-tick simulation driven through
//     `PuttMatch.update`, the aim's clock and its predicted roll, the hop
//     rides and the particle pool, all handed to the 3D world as a frame
//     each render.
//   * [PuttWorld3D] - the whole scene graph (putt_world3d.dart), moving to
//     the engine's truth every rendered frame.
//
// The game's core (physics, rules, power-ups) stays pure Dart and planar
// (`client/components/sunny_side_putt/core/`): the 3D world draws it, the
// engine never bends to the drawing - the roll guide runs a COPY of the
// engine's world ahead. Nothing here touches the network: the match is the
// local harness over the rules engine (`putt_match.dart`); the session
// wires the authoritative host under the same seams.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'putt_hud.dart';
import 'putt_match.dart';
import 'putt_menus.dart';
import 'putt_name_tags.dart';
import 'putt_world3d.dart';
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

  /// Handed the game once it exists: the demo drives its aim through it.
  final ValueChanged<SunnySidePuttGame>? onGame;

  const SunnySidePuttView(
      {super.key, this.match, this.audio, this.onLeave, this.onGame});

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
  late SunnySidePuttGame game;
  bool menuOpen = false;
  bool settingsOpen = false;

  /// The name tags' positions, refreshed after every rendered frame.
  final PuttTagBoard _tags = PuttTagBoard();

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
    game = SunnySidePuttGame(
      match: match,
      onSfx: (sfx) => widget.audio?.play(sfx),
    );
    widget.onGame?.call(game);
  }

  @override
  void didUpdateWidget(SunnySidePuttView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A session that rebuilt its match (a resync from scratch) hands a new
    // one: the same game and world follow it.
    final next = widget.match;
    if (next != null && !identical(next, match)) {
      match = next;
      game.swapMatch(next);
    }
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _gameFocus.dispose();
    _tags.dispose();
    super.dispose();
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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyC) {
      // C swaps between the close view and the whole hole.
      game.toggleOverview();
      return KeyEventResult.handled;
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
    _downPointers.add(event.pointer);
    _pointerAt[event.pointer] = event.localPosition;
    // A secondary-button drag orbits; only the main button putts.
    if (event.buttons == kSecondaryMouseButton ||
        event.buttons == kMiddleMouseButton) {
      _orbitPointer = event.pointer;
      _orbitLastPosition = event.localPosition;
      return;
    }
    // A second finger: pinch zoom takes over, the aim lets go.
    if (_downPointers.length >= 2) {
      game.cancelAim();
      _pinchSpan = _pointerSpan();
      _pinchDistance = game.world3d.rig.distance;
      return;
    }
    final world = _toWorld(event.localPosition);
    if (world != null) game.beginAim(world);
  }

  void _pointerMove(PointerEvent event, Size size) {
    _pointerAt[event.pointer] = event.localPosition;
    // The orbit drag: turn the yaw, tilt the pitch.
    if (_orbitPointer == event.pointer) {
      final last = _orbitLastPosition;
      if (last != null) {
        game.world3d.rig.orbitBy(
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
        game.world3d.rig
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
    if (orbiting || _pinchSpan != null) return;
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
    game.cancelAim();
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      game.world3d.rig.zoomByWheel(event.scrollDelta.dy);
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
    return game.screenToWorld(Vector2(at.dx, at.dy));
  }

  /// After every rendered frame: the tags follow the eggs on screen.
  void _afterFrame() {
    _tags.update(game.tagsForFrame());
  }

  @override
  Widget build(BuildContext context) {
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
              // The green, its 3D world behind the match's ticker.
              PuttThreeSurface(
                world: game.world3d,
                buildFrame: game.buildWorldFrame,
                onFrame: _afterFrame,
              ),
              // The ticker and the aim gestures, transparent over the
              // world; the pointer plumbing lands world-side through the
              // rig's ray.
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _pointerDown(event, size),
                onPointerMove: (event) => _pointerMove(event, size),
                onPointerUp: (event) => _pointerUp(event, size),
                onPointerCancel: (event) => _pointerCancel(event, size),
                onPointerSignal: _pointerSignal,
                child: GameWidget(
                  game: game,
                  focusNode: _gameFocus,
                  autofocus: false,
                ),
              ),
              // Who is who: names over the other players' eggs.
              IgnorePointer(child: PuttNameTags(board: _tags)),
              // HUD, menus and sheets: rebuilt as the match moves.
              ListenableBuilder(
                listenable: match,
                builder: (context, _) => _overlay(context),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final showVote = match.phase == PuttPhase.awaitingNextCourse && !menuOpen;
    return Stack(
      fit: StackFit.expand,
      children: [
        // HUD, with only its buttons eating pointers.
        PuttHud(
          match: match,
          onSfx: (sfx) => widget.audio?.play(sfx),
          onOpenMenu: _togglePause,
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
                  ? [for (final course in match.config.catalog.values) course]
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
                    onOpenSettings: () => setState(() => settingsOpen = true),
                    onResume: _togglePause,
                    onLeave: _leave,
                  ),
          ),
      ],
    );
  }
}

// ---- the game ---------------------------------------------------------------------------------

/// The game itself: the match ticking through its fixed steps, the 3D
/// world's hole built and refit on hole changes, the camera's choreography
/// (the hole's overview, then in close to the egg), and the per-frame world
/// snapshot (positions, rolls, hops, aim and its guide, bursts, camera
/// follow) the GPU surface's render hook applies. The aim, the sounds and
/// the HUD keep their own seams (`AimController`, `onSfx`, `PuttHud`); the
/// engine's planar truth stays untouched.
class SunnySidePuttGame extends FlameGame {
  PuttMatch match;

  /// The audio tap: strokes, bounces, timers, the works.
  final void Function(PuttSfx sfx) onSfx;

  final AimController aim = AimController();

  /// The real-3D world (`putt_world3d.dart`), built headlessly and drawn
  /// by the surface's three_js renderer; the camera rig lives in it.
  final PuttWorld3D world3d = PuttWorld3D();

  /// Seconds since the game booted, for art that breathes.
  double clock = 0;

  /// The aim's clock, for the arrow's sway.
  final PuttAimLayer aimLayer;

  final PuttFxLayer fx = PuttFxLayer();

  /// The hop rides, per player: the cosmetic arc of a Chicken Hop, keyed
  /// off the engine's own flag and sized by the egg's launch speed.
  final Map<String, _HopRide> _hopRides = {};

  String? _fittedHole;

  /// Seconds the current hole has been up: the overview holds first.
  double _holeClock = 0;

  /// Whether the camera has come in close for this hole yet, and whether
  /// the player asked for the whole-hole view.
  bool _closeIn = false;
  bool _overview = false;

  /// Where a drag anchored when it began away from the egg: the pull is
  /// measured from there, the arrow still drawn from the egg.
  core.Vec2? _dragAnchor;

  SunnySidePuttGame({required this.match, required this.onSfx})
      : aimLayer = PuttAimLayer();

  /// A session's rebuilt match: the same world and camera carry on.
  void swapMatch(PuttMatch next) {
    if (identical(next, match)) return;
    match = next;
    _fittedHole = null;
    _hopRides.clear();
    aim.cancel();
    _dragAnchor = null;
    _previewKey = null;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _fitCamera(size);
  }

  /// Frames the current hole: viewport pixels first, then the bounds.
  /// A hole change rebuilds (and refits); the same hole re-fits only on
  /// resize.
  void _fitCamera(Vector2 size) {
    final current = match.hole;
    if (current == null || size.x == 0 || size.y == 0) return;
    if (current.id != _fittedHole) {
      final number = match.holeInCourse;
      world3d.buildHole(
        current,
        eggRadius: eggRadius,
        label: number > 0 ? '$number' : null,
      );
      _holeClock = 0;
      _closeIn = false;
    }
    world3d.setViewport(ui.Size(size.x, size.y));
    world3d.fitCamera();
    if (_closeIn && !_overview) _glideClose();
    _fittedHole = current.id;
  }

  /// The whole hole, or back in close (the C key, the HUD's camera button).
  void toggleOverview() {
    _overview = !_overview;
    if (_overview) {
      world3d.fitCamera();
    } else {
      _glideClose();
    }
  }

  /// In close: near enough that the egg reads, far enough that the nest
  /// usually stays in view.
  void _glideClose() {
    final rig = world3d.rig;
    rig.glideTo(distance: rig.overviewDistance * 0.78);
  }

  /// A scripted camera (the demo's captures, a spectator's pick): while
  /// set, the camera's target rides this point instead of the egg.
  core.Vec2? followOverride;

  @override
  void update(double dt) {
    clock += dt;
    super.update(dt);
    match.update(dt);
    aim.noWobble = match.myNextShotSteady;
    aimLayer.update(this, dt);
    fx.update(dt);
    _updateHopRides();
    final holeId = match.hole?.id;
    if (holeId != null && holeId != _fittedHole) {
      _fitCamera(size);
      aim.cancel();
      _dragAnchor = null;
    }
    _holeClock += dt;
    if (!_closeIn && _holeClock > 2.4 && match.phase == PuttPhase.holePlay) {
      _closeIn = true;
      if (!_overview) _glideClose();
    }
    if (match.phase != PuttPhase.holePlay) {
      aim.cancel();
      _dragAnchor = null;
      // Between holes the whole green shows again under the cards.
      if (_closeIn) {
        _closeIn = false;
        world3d.fitCamera();
      }
    }
    _spendNotices();
    _spendFxSpots();
  }

  /// The frame the 3D world moves to this render: the engine's
  /// interpolated truth, the aim's drawn angle (wobble added) and its
  /// predicted roll, the particles, the camera's follow point and the
  /// collected "?" boxes.
  PuttWorldFrame buildWorldFrame() {
    final current = match.hole;
    final engineWorld = match.engine.world;
    final eggs = <PuttWorldEgg>[];
    final hens = <PuttWorldHen>[];
    PuttWorldAim? aimView;
    var fxViews = const <PuttWorldFx>[];
    var collected = const <String>{};
    if (current != null) {
      if (engineWorld != null) {
        collected = engineWorld.collectedBoxes;
        for (final ball in engineWorld.balls) {
          if (ball.holed) continue; // in the nest; the suction told the story
          eggs.add(PuttWorldEgg(
            playerId: ball.playerId,
            position: match.renderPositionOf(ball.playerId),
            height: eggHeightOf(ball),
            velocity: ball.velocity,
            tint: tintFor(ball.playerId),
            radius: eggRadius,
            mine: ball.playerId == match.localPlayerId && match.myShotReady,
          ));
        }
        final tickSeconds = match.config.physics.dt;
        for (final obstacle in current.obstacles) {
          final now = henPositionAt(obstacle, engineWorld.tick, tickSeconds);
          final then =
              henPositionAt(obstacle, engineWorld.tick + 1, tickSeconds);
          final at = ui.Offset.lerp(
            ui.Offset(now.x, now.y),
            ui.Offset(then.x, then.y),
            match.alpha,
          );
          final dx = then.x - now.x;
          final dy = then.y - now.y;
          hens.add(PuttWorldHen(
            position: core.Vec2(at?.dx ?? now.x, at?.dy ?? now.y),
            radius: obstacle.radius,
            phase: (engineWorld.tick + match.alpha) * 0.12,
            heading:
                dx * dx + dy * dy > 1e-12 ? core.Vec2(dx, dy) : core.Vec2.zero,
          ));
        }
      }
      final aimState = aim.state;
      if (aim.isActive && aimState != null) {
        aimView = PuttWorldAim(
          origin: aim.origin!,
          angle: aimState.angle + aim.visualWobble(aimLayer.holdSeconds),
          power: aimState.power,
          dragLength: aimState.dragLength,
          eggRadius: eggRadius,
          preview: aimState.dragLength >= AimController.deadZone
              ? _previewFor(aimState.angle, aimState.power)
              : const [],
        );
      }
      fxViews = [
        for (final particle in fx.particles) particle.worldView(),
      ];
    }
    return PuttWorldFrame(
      time: clock,
      eggs: eggs,
      hens: hens,
      aim: aimView,
      fxs: fxViews,
      followPoint: _cameraFollowPoint(),
      collectedBoxes: collected,
    );
  }

  /// The tags for this frame: every other player's egg on the green, at
  /// its screen spot just over the shell.
  List<PuttTag> tagsForFrame() {
    final engineWorld = match.engine.world;
    if (engineWorld == null || match.hole == null) return const [];
    final tags = <PuttTag>[];
    for (final ball in engineWorld.balls) {
      if (ball.holed || ball.playerId == match.localPlayerId) continue;
      final at = match.renderPositionOf(ball.playerId);
      final lift = eggRadius * 2.9 + eggHeightOf(ball);
      if (!world3d.inFrontOfCamera(at, height: lift)) continue;
      tags.add(PuttTag(
        playerId: ball.playerId,
        name: displayNameOf(match, ball.playerId),
        color: tintFor(ball.playerId),
        at: world3d.projectToWorld(at, height: lift),
      ));
    }
    return tags;
  }

  // ---- the roll guide ---------------------------------------------------------------

  ({double angle, double power})? _previewKey;
  List<core.Vec2> _preview = const [];

  /// The predicted roll for this aim, cached while the aim holds still.
  List<core.Vec2> _previewFor(double angle, double power) {
    final key = _previewKey;
    if (key != null &&
        (key.angle - angle).abs() < 0.0012 &&
        (key.power - power).abs() < 0.003) {
      return _preview;
    }
    _previewKey = (angle: angle, power: power);
    final world = match.engine.world;
    final current = match.hole;
    if (world == null || current == null) return _preview = const [];
    _preview = predictRoll(
      world: world,
      hole: current,
      config: match.config.physics,
      playerId: match.localPlayerId,
      angle: angle,
      power: power,
      modifiers: match.localPlayer?.nextShot,
    );
    return _preview;
  }

  /// The point the camera's target glides toward: my egg while the hole
  /// plays (leaning toward the nest while it rests, so the way ahead
  /// shows; a spectator drifts to whoever is out there); held while
  /// aiming, so a moving frame never slides out from under a drag.
  core.Vec2? _cameraFollowPoint() {
    final override = followOverride;
    if (override != null) return override;
    if (aim.isActive) return null;
    if (match.phase != PuttPhase.holePlay) return match.hole?.bounds.center;
    if (_holeClock < 2.4 || _overview) return match.hole?.bounds.center;
    final egg = match.myEggRenderPosition;
    final nest = match.hole?.nest.position;
    if (egg != null && !(match.myBall?.holed ?? true)) {
      final resting = match.myBall?.asleep ?? true;
      if (resting && nest != null) return egg.lerp(nest, 0.42);
      return egg;
    }
    for (final player in match.engine.players) {
      if (player.spectator) continue;
      final ball = match.engine.world?.ball(player.id);
      if (ball == null || ball.holed) continue;
      return match.renderPositionOf(player.id);
    }
    return match.hole?.bounds.center;
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
          if (spot.at != null) {
            fx.splash(spot.at!);
            fx.ring(spot.at!, PuttPalette.water, size: 2.2);
          }
        case PuttFxSpotKind.out:
          if (spot.at != null) fx.poof(spot.at!);
        case PuttFxSpotKind.holed:
          final nest = match.hole?.nest.position;
          if (spot.who != null && nest != null) {
            final tint = tintFor(spot.who!);
            fx.suction(nest, tint);
            fx.ring(nest, tint, size: 3.4);
            fx.confetti(nest, mine: spot.who == match.localPlayerId);
          }
        case PuttFxSpotKind.pick:
          final at = spot.who == null ? null : match.currentPositions[spot.who];
          if (at != null) {
            fx.sparkles(at);
            fx.ring(at, PuttPalette.yolk, size: 1.8);
          }
      }
    }
    match.fxSpots.clear();
  }

  // ---- pointer plumbing ---------------------------------------------------------------

  /// Screen (widget-local) coordinates into the ground plane, through
  /// the camera. Null when the pixel misses the green entirely (the sky
  /// above the horizon), and the caller does nothing.
  core.Vec2? screenToWorld(Vector2 screen) {
    return world3d.screenToWorld(ui.Offset(screen.x, screen.y));
  }

  /// The camera read the e2e drives its drags through (the seam the flat
  /// `view3d` was): world points to surface pixels, on the world's own
  /// perspective.
  PuttCameraSeam get view3d => PuttCameraSeam(world3d);

  /// Aims when my egg is on the green and settled. A press on (or near)
  /// the egg pulls from the egg itself; a press anywhere else anchors the
  /// slingshot where the finger landed - the pull is the drag from there,
  /// the arrow still leaves the egg.
  void beginAim(core.Vec2 point) {
    if (!match.myShotReady) return;
    final ball = match.myBall;
    if (ball == null) return;
    final reach = math.max(match.config.physics.ballRadius * 3, 1.8);
    _dragAnchor = ball.position.distanceTo(point) > reach ? point : null;
    aim.begin(ball.position);
    aim.update(_pullPoint(point));
    _previewKey = null;
  }

  /// The pointer as the aim reads it: itself when the drag began on the
  /// egg, else the egg plus the drag from the anchor.
  core.Vec2 _pullPoint(core.Vec2 point) {
    final anchor = _dragAnchor;
    final origin = aim.origin;
    if (anchor == null || origin == null) return point;
    return origin + (point - anchor);
  }

  void moveAim(core.Vec2 point) {
    if (aim.isActive) aim.update(_pullPoint(point));
  }

  void endAim(core.Vec2 point) {
    if (!aim.isActive) return;
    aim.update(_pullPoint(point));
    _dragAnchor = null;
    final shot = aim.commit();
    if (shot == null) return;
    final at = match.myBall?.position;
    if (match.submitShot(shot.angle, shot.power) && at != null) {
      fx.dust(at, shot.angle);
    }
  }

  void cancelAim() {
    aim.cancel();
    _dragAnchor = null;
  }

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
  ui.Color backgroundColor() => const ui.Color(0x00000000);
}

/// One egg's hop: how fast it left, so the drawn arc knows its length.
class _HopRide {
  final double launchSpeed;

  const _HopRide({required this.launchSpeed});
}

// ---- the roll guide -----------------------------------------------------------------------

/// The first stretch of the roll a shot would take: the engine's physics
/// run ahead on a COPY of [world] (every egg, the hen at her real step),
/// with the shot's power-up modifiers, cut after the first bounce off a
/// rail plus a short tail, at a reset (water, out of bounds, the silo, a
/// rabbit hole's jump), in the nest, or after [maxLength] of travel - a
/// guide for the line, not a promise of where the egg stops.
List<core.Vec2> predictRoll({
  required PhysicsWorld world,
  required hole.HoleDef hole,
  required PhysicsConfig config,
  required String playerId,
  required double angle,
  required double power,
  NextShotModifiers? modifiers,
  double maxLength = 12,
  double tailAfterBounce = 3.5,
  int maxTicks = 720,
}) {
  final copy =
      PhysicsWorld.restore(hole: hole, config: config, state: world.toJson());
  final ball = copy.ball(playerId);
  if (ball == null || ball.holed) return const [];
  final shotPower =
      (power * (modifiers?.powerMultiplier ?? 1)).clamp(0.0, 1.0).toDouble();
  if (modifiers?.hop ?? false) {
    copy.setBallFlagUntilRest(playerId, PowerUpFlag.hop);
  }
  if (modifiers?.magnet ?? false) {
    copy.setBallFlagUntilRest(playerId, PowerUpFlag.magnet);
  }
  copy.applyShot(playerId, angle, shotPower);
  final points = <core.Vec2>[ball.position];
  var travelled = 0.0;
  var bounced = false;
  var afterBounce = 0.0;
  var heading = ball.velocity;
  for (var i = 0; i < maxTicks; i++) {
    final before = ball.position;
    copy.stepTick();
    if (ball.holed) {
      points.add(hole.nest.position);
      break;
    }
    final after = ball.position;
    final step = before.distanceTo(after);
    // A jump is a reset or a portal: the guide stops at the edge of it.
    if (step > 2.0) break;
    travelled += step;
    final velocity = ball.velocity;
    if (!bounced &&
        velocity.length > 1e-6 &&
        heading.length > 1e-6 &&
        velocity.dot(heading) / (velocity.length * heading.length) < 0.985) {
      bounced = true;
    }
    if (bounced) afterBounce += step;
    heading = velocity;
    if (i % 3 == 0) points.add(after);
    if (ball.asleep ||
        travelled >= maxLength ||
        afterBounce >= tailAfterBounce) {
      points.add(after);
      break;
    }
  }
  return points;
}

// ---- the layers that feed the world ---------------------------------------------------

/// The aim's clock: how long the current drag has held, which drives the
/// arrow's sway (the aim's own math lives in `aim_controller.dart`; the
/// sway lands on the 3D aim mark through [SunnySidePuttGame.buildWorldFrame]).
class PuttAimLayer {
  /// Seconds the aim has been held, for the sway's clock.
  double holdSeconds = 0;

  PuttAimLayer();

  void update(SunnySidePuttGame game, double dt) {
    holdSeconds = game.aim.isActive ? holdSeconds + dt : 0;
  }
}

/// The bursts: splash droplets, suction streaks, poofs, pickup sparkles,
/// the putt's dust, the nest's confetti and shockwave rings. Each lives
/// about half a second (the confetti longer), on plain velocity math. A
/// plain pool: the game ticks it every frame; `buildWorldFrame` hands the
/// particles to the 3D world, which draws them.
class PuttFxLayer {
  final List<_FxParticle> _particles = [];

  /// Cosmetic randomness, seeded so captures repeat.
  final math.Random _random = math.Random(17);

  /// The live particles, for the scene layer's paintables.
  List<_FxParticle> get particles => _particles;

  void splash(core.Vec2 at) {
    for (var i = 0; i < 18; i++) {
      final angle = i * 2.39996; // golden spaced
      final speed = 1.6 + (i % 4) * 0.8;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * speed,
        life: 0.65,
        kind: _FxKind.droplet,
        size: 0.26,
        color: const ui.Color(0xFFBFE6FF),
      ));
    }
  }

  void suction(core.Vec2 at, ui.Color tint) {
    for (var i = 0; i < 12; i++) {
      final angle = i * 2.39996 + 1;
      _particles.add(_FxParticle(
        at: at + core.Vec2(math.cos(angle), math.sin(angle)) * (1.2 + i * 0.1),
        velocity: core.Vec2.zero,
        life: 0.5,
        kind: _FxKind.suction,
        size: 0.2,
        toward: at,
        color: tint,
      ));
    }
  }

  void sparkles(core.Vec2 at) {
    for (var i = 0; i < 12; i++) {
      final angle = i / 12 * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * 1.6,
        life: 0.6,
        kind: _FxKind.sparkle,
        size: 0.28,
        color: i.isEven ? PuttPalette.yolk : PuttPalette.shell,
      ));
    }
  }

  void poof(core.Vec2 at) {
    for (var i = 0; i < 9; i++) {
      final angle = i / 9 * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * 0.9,
        life: 0.5,
        kind: _FxKind.poof,
        size: 0.42,
        color: PuttPalette.cream,
      ));
    }
  }

  /// The putt's kick: a little dust thrown back from under the egg.
  void dust(core.Vec2 at, double angle) {
    for (var i = 0; i < 7; i++) {
      final spread = angle + math.pi + (i - 3) * 0.35;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(spread), math.sin(spread)) *
            (0.8 + _random.nextDouble() * 1.2),
        life: 0.55,
        kind: _FxKind.dust,
        size: 0.32,
        color: const ui.Color(0xFFF3E6CF),
      ));
    }
  }

  /// The nest's party: paper confetti thrown up in the brand's colours
  /// (twice as much when it is the viewer's own egg).
  void confetti(core.Vec2 at, {bool mine = false}) {
    const colors = [
      PuttPalette.comb,
      PuttPalette.yolk,
      PuttPalette.shell,
      PuttPalette.water,
      ui.Color(0xFF7BD35A),
    ];
    final count = mine ? 64 : 32;
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 1.2 + _random.nextDouble() * 3.4;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * speed,
        life: 1.6 + _random.nextDouble() * 0.8,
        kind: _FxKind.confetti,
        size: 0.22 + _random.nextDouble() * 0.12,
        color: colors[i % colors.length],
        height: 0.4,
        climb: 5.5 + _random.nextDouble() * 4.5,
      ));
    }
  }

  /// A shockwave ring spreading over the turf.
  void ring(core.Vec2 at, ui.Color color, {double size = 2.5}) {
    _particles.add(_FxParticle(
      at: at,
      velocity: core.Vec2.zero,
      life: 0.7,
      kind: _FxKind.ring,
      size: size,
      color: color,
    ));
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

enum _FxKind { droplet, sparkle, suction, poof, dust, confetti, ring }

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

  /// Height over the green and its rate, for the particles that fly (the
  /// confetti falls under gravity and settles on the turf).
  double? height;
  double climb;

  _FxParticle({
    required core.Vec2 at,
    required this.velocity,
    required this.life,
    required this.kind,
    required this.size,
    this.toward,
    this.color,
    this.height,
    this.climb = 0,
  }) : position = at;

  void advance(double dt) {
    position = position + velocity * dt;
    if (kind == _FxKind.confetti) {
      // Paper: light air drag, gravity, a gentle landing.
      velocity = velocity + velocity * (-0.9 * dt);
      final h = height ?? 0;
      climb -= 9.0 * dt;
      // Fluttering slows the fall once it tops out.
      if (climb < -2.2) climb = -2.2;
      final next = h + climb * dt;
      if (next <= 0.06) {
        height = 0.06;
        climb = 0;
        velocity = core.Vec2.zero;
      } else {
        height = next;
      }
      return;
    }
    velocity = velocity + velocity * (-2.2 * dt);
  }

  /// The renderer's view of this particle this frame.
  PuttWorldFx worldView() {
    final kind = switch (this.kind) {
      _FxKind.droplet => PuttWorldFxKind.droplet,
      _FxKind.sparkle => PuttWorldFxKind.sparkle,
      _FxKind.suction => PuttWorldFxKind.suction,
      _FxKind.poof => PuttWorldFxKind.poof,
      _FxKind.dust => PuttWorldFxKind.dust,
      _FxKind.confetti => PuttWorldFxKind.confetti,
      _FxKind.ring => PuttWorldFxKind.ring,
    };
    return PuttWorldFx(
      kind: kind,
      at: position,
      toward: toward,
      progress: (age / life).clamp(0.0, 1.0),
      size: size,
      color: color,
      height: height,
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
