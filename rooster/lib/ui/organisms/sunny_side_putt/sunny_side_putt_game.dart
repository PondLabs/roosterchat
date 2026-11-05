// The game view of Sunny Side Putt: the real-3D farm (the three_js engine -
// perspective camera, sun with soft shadows, the course on its table in a
// meadow, see `putt_world3d.dart`) slung under the Flutter HUD, with
// slingshot aim from anywhere on the green, the predicted roll's dotted
// guide, eggs that roll and settle, nest confetti, splashes and sparkles,
// name tags over the other players' eggs, wrapped by the HUD and menus.
//
// Split of work:
//   * [SunnySidePuttView] - the Flutter shell: the GPU surface (the three_js
//     view), pointer plumbing (the main button putts - or casts an armed
//     power-up where it lands - a secondary-button drag and the
//     wheel/pinch orbit and zoom the camera), Esc-to-pause, the HUD
//     (rebuilt as the match moves), the targeting reticle, the name tags
//     and the menus (their own files), and the audio service's cue tap.
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
import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
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
import 'putt_camera_director.dart';
import 'putt_cast_feed.dart';
import 'putt_hud.dart';
import 'putt_match.dart';
import 'putt_menus.dart';
import 'putt_coach.dart';
import 'putt_reactions.dart';
import 'putt_name_tags.dart';
import 'putt_nest_marker.dart';
import 'putt_reticle.dart';
import 'putt_targeting.dart';
import 'putt_world3d.dart';

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

  /// "Your egg" is up over the pause menu.
  bool lookOpen = false;

  /// The name tags' positions, refreshed after every rendered frame.
  final PuttTagBoard _tags = PuttTagBoard();
  final ValueNotifier<PuttCoachCue?> _coach = ValueNotifier(null);
  final PuttBubbleBoard _bubbles = PuttBubbleBoard();

  /// When the last reaction went (the keys share the picker's cooldown).
  DateTime _lastReaction = DateTime.fromMillisecondsSinceEpoch(0);

  void _react(String reaction) {
    final now = DateTime.now();
    if (now.difference(_lastReaction) < const Duration(milliseconds: 700)) {
      return;
    }
    _lastReaction = now;
    match.react(reaction);
  }

  /// True while I aim or my egg rolls (the HUD folds its scorecard).
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  /// The off-screen nest's marker, refreshed after every rendered frame.
  final ValueNotifier<PuttNestPointer?> _nestPointer = ValueNotifier(null);

  /// Whether the green has been drawn yet (or never will be: no GPU
  /// surface here, or it failed). Until then the HUD's banners wait, so a
  /// slow boot does not play the hole's card to a blank screen.
  final ValueNotifier<bool> _greenShown =
      ValueNotifier(!PuttThreeSurface.gpuSupported);

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
      onSfx: (sfx, volume) => widget.audio?.play(sfx, volume: volume),
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
    _coach.dispose();
    _busy.dispose();
    _greenShown.dispose();
    _nestPointer.dispose();
    _bubbles.dispose();
    game.targeting.dispose();
    super.dispose();
  }

  void _togglePause() {
    // A power-up waiting for a spot or a pick goes back in the carton.
    game.targeting.cancel();
    setState(() {
      menuOpen = !menuOpen;
      settingsOpen = false;
      lookOpen = false;
      match.paused = menuOpen;
    });
    widget.audio?.play(PuttSfx.click);
  }

  /// The whole hole, or back in close: the C key and the HUD's button.
  void _toggleCamera() {
    setState(game.toggleOverview);
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
      // An armed power-up or an open picker goes away first, unspent.
      if (game.targeting.isActive) {
        game.targeting.cancel();
        return KeyEventResult.handled;
      }
      if (settingsOpen || lookOpen) {
        setState(() {
          settingsOpen = false;
          lookOpen = false;
        });
        return KeyEventResult.handled;
      }
      if (match.phase != PuttPhase.awaitingNextCourse) {
        _togglePause();
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyC) {
      // C swaps between the close view and the whole hole.
      _toggleCamera();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      // 1-5 send the quick reactions.
      const keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ];
      final index = keys.indexOf(event.logicalKey);
      if (index >= 0) {
        _react(puttReactions[index]);
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

  /// The press that casts the armed power-up where it lets go (the
  /// reticle follows it until then, so a finger can settle on the spot).
  int? _castPointer;

  void _pointerDown(PointerDownEvent event, Size size) {
    _downPointers.add(event.pointer);
    _pointerAt[event.pointer] = event.localPosition;
    final targeting = game.targeting;
    if (targeting.isActive) {
      // While a power-up waits for a spot or a pick, presses on the green
      // belong to it: a right click (or a press beside an open picker)
      // puts it away, the main button casts the armed one.
      if (targeting.armed == null || event.buttons == kSecondaryMouseButton) {
        targeting.cancel();
        _castPointer = null;
        return;
      }
      if (event.buttons != kMiddleMouseButton && _downPointers.length == 1) {
        game.cancelAim();
        _castPointer = event.pointer;
        targeting.hover = _toWorld(event.localPosition);
        return;
      }
      // A second finger: the pinch takes over, nothing is cast.
      _castPointer = null;
    }
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
    if (_castPointer == event.pointer) {
      game.targeting.hover = _toWorld(event.localPosition);
      return;
    }
    // The orbit drag: turn the yaw, tilt the pitch.
    if (_orbitPointer == event.pointer) {
      final last = _orbitLastPosition;
      if (last != null) {
        game.director.noteUserCamera();
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
        game.director.noteUserCamera();
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
    if (_castPointer == event.pointer) {
      _castPointer = null;
      final world = _toWorld(event.localPosition);
      // Let go over the sky: still armed, nothing spent.
      if (world != null) game.castArmedAt(world);
      return;
    }
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
    if (_castPointer == event.pointer) _castPointer = null;
    if (_orbitPointer == event.pointer) {
      _orbitPointer = null;
      _orbitLastPosition = null;
    }
    if (_downPointers.length < 2) _pinchSpan = null;
    game.cancelAim();
  }

  /// A mouse over the green while a power-up is armed: the reticle
  /// follows it.
  void _pointerHover(PointerHoverEvent event) {
    final targeting = game.targeting;
    if (targeting.armed == null) return;
    targeting.hover = _toWorld(event.localPosition);
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      game.director.noteUserCamera();
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

  /// After every rendered frame: the tags follow the eggs on screen, the
  /// coach follows mine.
  void _afterFrame() {
    game.worldDrew();
    _greenShown.value = true;
    _tags.update(game.tagsForFrame(), avoid: game.tagObstacles());
    _coach.value = game.coachForFrame();
    _nestPointer.value = game.nestPointerForFrame();
    _bubbles.update(game.bubblesForFrame());
    final mine = game.match.myBall;
    _busy.value =
        game.aim.isActive || (mine != null && !mine.asleep && !mine.holed);
  }

  @override
  Widget build(BuildContext context) {
    // The system's reduced motion: no sweep, no shakes, no punch-in.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    game.director.reduceMotion = still;
    game.world3d.rig.reduceMotion = still;
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
                onFailed: () {
                  game.worldDrew();
                  _greenShown.value = true;
                },
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
                onPointerHover: _pointerHover,
                onPointerSignal: _pointerSignal,
                // A crosshair while a power-up waits for its spot.
                child: ListenableBuilder(
                  listenable: game.targeting,
                  builder: (context, child) => MouseRegion(
                    cursor: game.targeting.armed != null
                        ? SystemMouseCursors.precise
                        : MouseCursor.defer,
                    child: child,
                  ),
                  child: GameWidget(
                    game: game,
                    focusNode: _gameFocus,
                    autofocus: false,
                  ),
                ),
              ),
              // Who is who: names over the other players' eggs.
              IgnorePointer(child: PuttNameTags(board: _tags)),
              // Where the nest is, when the camera is in on my egg and the
              // nest is off the screen.
              PuttNestMarker(pointer: _nestPointer),
              // The putt's gesture, shown over my egg until I have it.
              PuttCoach(cue: _coach),
              // Quick reactions over the eggs that sent them.
              PuttBubbles(board: _bubbles),
              // Where an armed power-up would land, and what it reaches.
              ListenableBuilder(
                listenable: Listenable.merge([match, game.targeting]),
                builder: (context, _) => PuttReticle(
                  match: match,
                  targeting: game.targeting,
                  project: game.world3d.projectToWorld,
                ),
              ),
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
        // HUD, with only its buttons and slots eating pointers (the
        // spectator note rides its hint line); its banners wait for the
        // green's first frame.
        PuttHud(
          match: match,
          targeting: game.targeting,
          busy: _busy,
          shown: _greenShown,
          onSfx: (sfx) => widget.audio?.play(sfx),
          onOpenMenu: _togglePause,
          onToggleCamera: _toggleCamera,
          cameraOverview: game.overview,
          onLeave: _leave,
        ),
        // Every power-up anyone casts, told to everyone: under the top
        // bar, clear of the green's middle (kept while the menu is up, so
        // its queue carries on after).
        if (match.phase == PuttPhase.holePlay)
          Positioned(
            top: 112,
            left: 64,
            right: 64,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Visibility(
                  visible: !menuOpen,
                  maintainState: true,
                  child: PuttCastFeed(match: match),
                ),
              ),
            ),
          ),
        // The quick reactions, under the top-right buttons, while a hole
        // plays or its results are up.
        if (!menuOpen &&
            (match.phase == PuttPhase.holePlay ||
                match.phase == PuttPhase.holeScoreboard))
          Positioned(
            top: 62,
            right: 10,
            child: SafeArea(child: PuttReactionPicker(onReact: _react)),
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
                : lookOpen
                    ? PuttLookSheet(
                        match: match,
                        onPick: () => widget.audio?.play(PuttSfx.click),
                        onClose: () => setState(() => lookOpen = false),
                      )
                    : PuttPauseMenu(
                        match: match,
                        onOpenLook: () => setState(() => lookOpen = true),
                        onOpenSettings: () =>
                            setState(() => settingsOpen = true),
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

  /// The audio tap: strokes, bounces, timers, the works, each at the
  /// volume its notice asks (a share of the effects bus).
  final void Function(PuttSfx sfx, double volume) onSfx;

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

  /// The camera's choreography: the hole's opening sweep, the egg and the
  /// nest framed at rest, the egg followed while it rolls.
  late final PuttCameraDirector director = PuttCameraDirector(world3d.rig)
    // The egg as drawn: about 2.4 radii from base to crown.
    ..eggHeight = eggRadius * 2.4;

  /// Where a drag anchored when it began away from the egg: the pull is
  /// measured from there, the arrow still drawn from the egg.
  core.Vec2? _dragAnchor;

  /// The power-up targeting the HUD shows and the view's presses feed: a
  /// slot armed for a spot on the green, or a player picker open.
  final PuttTargeting targeting = PuttTargeting();

  SunnySidePuttGame({required this.match, required this.onSfx})
      : aimLayer = PuttAimLayer();

  /// A session's rebuilt match: the same world and camera carry on.
  void swapMatch(PuttMatch next) {
    if (identical(next, match)) return;
    match = next;
    _fittedHole = null;
    _hopRides.clear();
    _clearCastScenes();
    aim.cancel();
    targeting.cancel();
    _dragAnchor = null;
    _previewKey = null;
  }

  /// Whether the camera shows the whole hole (the player's pick), rather
  /// than the close view of the egg.
  bool get overview => director.overview;

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
    }
    world3d.setViewport(ui.Size(size.x, size.y));
    world3d.fitCamera();
    // A resize refits the whole hole; the director frames the shot again.
    director.reframe();
    _fittedHole = current.id;
  }

  /// The whole hole, or back in close (the C key, the HUD's camera button).
  void toggleOverview() => director.toggleOverview();

  /// A scripted camera (the demo's captures, a spectator's pick): while
  /// set, the camera's target rides this point instead of the egg.
  core.Vec2? followOverride;

  @override
  void update(double dt) {
    clock += dt;
    super.update(dt);
    match.update(dt);
    targeting.validate(match);
    // A slot armed (or a picker opened) takes the green from the aim.
    if (targeting.isActive && aim.isActive) {
      aim.cancel();
      _dragAnchor = null;
    }
    aim.noWobble = match.myNextShotSteady;
    aim.wobbleAmplitude = match.config.wobbleMaxRadians;
    aimLayer.update(this, dt);
    fx.update(dt);
    _updateHopRides();
    final holeId = match.hole?.id;
    if (holeId != null && holeId != _fittedHole) {
      _fitCamera(size);
      _clearCastScenes();
      aim.cancel();
      _dragAnchor = null;
    }
    if (match.phase != PuttPhase.holePlay) {
      aim.cancel();
      _dragAnchor = null;
    }
    _directCamera(dt);
    _spendNotices();
    _spendFxSpots();
    _updateCastScenes(dt);
    _trackReadiness(dt);
  }

  // ---- the aim coach ------------------------------------------------------------------

  /// How long my egg has sat ready for a putt (resting, my hole in play,
  /// no aim or power-up pick under way).
  double _readyFor = 0;

  /// Set once I have putted in this match: the coach then only comes back
  /// after a long idle.
  bool _coachRetired = false;

  /// Seconds of idle (egg ready, no aim) before the coach shows again
  /// once I have putted.
  static const double coachIdleSeconds = 14;

  void _trackReadiness(double dt) {
    final mine = match.myBall;
    final ready = match.phase == PuttPhase.holePlay &&
        !match.isSpectator &&
        mine != null &&
        mine.asleep &&
        !mine.holed &&
        !aim.isActive &&
        !targeting.isActive;
    _readyFor = ready ? _readyFor + dt : 0;
    if (!_coachRetired) {
      final me = match.localPlayerId;
      if (match.engine.strokesInHole(me) > 0 ||
          match.engine.holeStrokes(me).any((strokes) => strokes != null)) {
        _coachRetired = true;
      }
    }
  }

  /// The coach's place this frame, or null when it should not show: my
  /// egg ready after the hole's opening sweep, and either no putt of mine
  /// yet this match or a long idle.
  PuttCoachCue? coachForFrame() {
    if (_readyFor <= 0) return null;
    // Once the camera has come out of the opening sweep and settled.
    if (director.settledFor < 0) return null;
    if (_coachRetired && _readyFor < coachIdleSeconds) return null;
    if (!_coachRetired && _readyFor < 0.5) return null;
    final hole = match.hole;
    final mine = match.myBall;
    if (hole == null || mine == null) return null;
    final at = match.myEggRenderPosition;
    if (at == null || !world3d.inFrontOfCamera(at)) return null;
    final egg = world3d.projectToWorld(at);
    // Only over an egg the player can see, clear of the HUD's bars.
    final view = world3d.rig.viewport;
    if (egg.dx < 40 ||
        egg.dx > view.width - 40 ||
        egg.dy < 90 ||
        egg.dy > view.height - 110) {
      return null;
    }
    final nest = world3d.projectToWorld(hole.nest.position);
    final way = nest - egg;
    final toward = way.distance < 1 ? const Offset(0, -1) : way / way.distance;
    return PuttCoachCue(egg: egg, toward: toward);
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
        final tick = engineWorld.tick;
        final tickSeconds = match.config.physics.dt;
        for (final ball in engineWorld.balls) {
          if (ball.holed) continue; // in the nest; the suction told the story
          // The power-ups on this egg, as everyone sees them: the shell's
          // bubble, the ghost's fade, the magnet's pull on the nest.
          final player = match.engine.player(ball.playerId);
          final ghostUntil = ball.timedUntil[PowerUpFlag.ghost];
          eggs.add(PuttWorldEgg(
            playerId: ball.playerId,
            position: match.renderPositionOf(ball.playerId),
            height: eggHeightOf(ball),
            velocity: ball.velocity,
            tint: tintFor(ball.playerId),
            look: player?.look ?? PuttLook.standard,
            radius: eggRadius,
            mine: ball.playerId == match.localPlayerId && match.myShotReady,
            shielded: (player?.shields ?? 0) > 0,
            ghostSeconds: ghostUntil == null || ghostUntil <= tick
                ? 0
                : (ghostUntil - tick - match.alpha) * tickSeconds,
            magnet: (player?.nextShot.magnet ?? false) ||
                ball.flagActive(PowerUpFlag.magnet, tick),
          ));
        }
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
        final sway = aim.swayNow(aimLayer.holdSeconds);
        // The guide runs from the pull's own angle (cached while the pull
        // holds) and turns with the sway, so it always shows where the
        // arrow, and so the shot, points.
        final guided = aimState.dragLength >= AimController.deadZone;
        final preview = guided
            ? _swayed(
                _previewFor(aimState.angle, aimState.power), aim.origin!, sway)
            : const <core.Vec2>[];
        final rest = guided ? _previewRest : null;
        aimView = PuttWorldAim(
          origin: aim.origin!,
          angle: aimState.angle + sway,
          power: aimState.power,
          dragLength: aimState.dragLength,
          eggRadius: eggRadius,
          preview: preview,
          rest: rest == null ? null : _swayed([rest], aim.origin!, sway).single,
        );
      }
      fxViews = [
        for (final particle in fx.particles)
          // A staggered particle shows once its beat comes.
          if (particle.age >= 0) particle.worldView(),
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
      crows: current == null ? const [] : _crowsForFrame(),
      closeUp: director.celebrating,
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
        look: puttLookOf(match, ball.playerId),
        at: world3d.projectToWorld(at, height: lift),
        dim: aim.isActive,
        avatar: match.avatarOf?.call(ball.playerId),
        // From far off, the names would cover the eggs: pictures only.
        compact: world3d.rig.distance > 44,
      ));
    }
    return tags;
  }

  /// The reactions' bubbles this frame: over the egg of whoever sent each
  /// (over the nest once their egg is in; anyone without an egg on the
  /// green - a spectator - is skipped).
  List<PuttBubble> bubblesForFrame() {
    final list = match.reactions;
    if (list.isEmpty) return const [];
    final now = match.reactionClock;
    final hole = match.hole;
    final world = match.engine.world;
    final out = <PuttBubble>[];
    var serial = 0;
    // The ones whose egg is in: over the nest, side by side rather than
    // stacked on the flag.
    var atNest = 0;
    for (final reaction in list) {
      serial++;
      final age = now - reaction.at;
      if (age < 0 || age > PuttReaction.life) continue;
      final ball = world?.ball(reaction.playerId);
      core.Vec2? at;
      var aside = 0.0;
      if (ball != null && !ball.holed) {
        at = match.renderPositionOf(reaction.playerId);
      } else if (ball != null && hole != null) {
        at = hole.nest.position;
        // 0, then right, left, further right...
        final k = atNest++;
        aside = (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) * 52.0;
      }
      if (at == null) continue;
      final lift = eggRadius * 5.6;
      if (!world3d.inFrontOfCamera(at, height: lift)) continue;
      out.add(PuttBubble(
        key: '${reaction.playerId}-${reaction.at}-$serial',
        reaction: reaction.reaction,
        at: world3d.projectToWorld(at, height: lift) + Offset(aside, 0),
        progress: age / PuttReaction.life,
      ));
    }
    return out;
  }

  /// The off-screen nest's marker this frame: while my egg is out on the
  /// green and the nest stands outside the part of the screen the HUD
  /// leaves free (or behind the camera). Not while the hole opens, nor in
  /// the whole-hole view, nor in on my egg's hatch.
  PuttNestPointer? nestPointerForFrame() {
    final hole = match.hole;
    final mine = match.myBall;
    if (hole == null ||
        mine == null ||
        mine.holed ||
        match.isSpectator ||
        match.phase != PuttPhase.holePlay ||
        director.opening ||
        director.overview ||
        director.celebrating) {
      return null;
    }
    final view = world3d.rig.viewport;
    if (view.width <= 0 || view.height <= 0) return null;
    final free = Rect.fromLTRB(16, 104, view.width - 16, view.height - 160);
    final nest = hole.nest.position;
    final inCourse = match.holeInCourse;
    return puttNestPointer(
      world3d.projectToWorld(nest, height: 0.6),
      free,
      behind: !world3d.inFrontOfCamera(nest, height: 0.6),
      number: '${inCourse > 0 ? inCourse : match.holeNumber}',
    );
  }

  /// What the tags must leave clear: every egg on the green (mine with its
  /// pin above it).
  List<Rect> tagObstacles() {
    final world = match.engine.world;
    if (world == null || match.hole == null) return const [];
    final out = <Rect>[];
    for (final ball in world.balls) {
      if (ball.holed) continue;
      final mine = ball.playerId == match.localPlayerId;
      final at = match.renderPositionOf(ball.playerId);
      if (!world3d.inFrontOfCamera(at)) continue;
      final foot = world3d.projectToWorld(at);
      // Mine with its pin over it; the others up to their shell's top (their
      // own tags stand above that).
      final top =
          world3d.projectToWorld(at, height: eggRadius * (mine ? 4.2 : 2.4));
      final half = math.max(mine ? 14.0 : 8.0, (foot.dy - top.dy) * 0.45);
      out.add(Rect.fromLTRB(foot.dx - half, top.dy, foot.dx + half, foot.dy));
    }
    return out;
  }

  // ---- the roll guide ---------------------------------------------------------------

  ({double angle, double power})? _previewKey;
  List<core.Vec2> _preview = const [];

  /// Where the cached guide's egg comes to rest, when it stops inside it.
  core.Vec2? _previewRest;

  /// [points] turned by [angle] about [origin] (the guide under the sway).
  static List<core.Vec2> _swayed(
      List<core.Vec2> points, core.Vec2 origin, double angle) {
    if (angle == 0 || points.isEmpty) return points;
    final c = math.cos(angle), s = math.sin(angle);
    return [
      for (final p in points)
        core.Vec2(origin.x + (p.x - origin.x) * c - (p.y - origin.y) * s,
            origin.y + (p.x - origin.x) * s + (p.y - origin.y) * c),
    ];
  }

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
    _previewRest = null;
    if (world == null || current == null) return _preview = const [];
    final roll = previewRoll(
      world: world,
      hole: current,
      config: match.config.physics,
      playerId: match.localPlayerId,
      angle: angle,
      power: power,
      modifiers: match.localPlayer?.nextShot,
    );
    _previewRest = roll.rest;
    return _preview = roll.points;
  }

  /// The point the camera's target glides toward: my egg while the hole
  /// plays (leaning toward the nest while it rests, so the way ahead
  /// shows; a spectator drifts to whoever is out there); held while
  /// aiming, so a moving frame never slides out from under a drag.
  core.Vec2? _cameraFollowPoint() => followOverride ?? director.followPoint;

  /// Whether the 3D world has drawn a frame yet (or never will: no GPU
  /// surface here, as under the test runner, or it failed). The camera's
  /// clock waits for it, so a slow boot does not play the hole's opening
  /// to a blank surface.
  bool _worldDrawn = !PuttThreeSurface.gpuSupported;

  /// The surface drew a frame (or gave up): the camera's clock may run.
  void worldDrew() => _worldDrawn = true;

  /// Tells the director what the green is doing this frame.
  void _directCamera(double dt) {
    final world = match.engine.world;
    final mine = match.myBall;
    director.update(
      // A frame after a stall (shaders compiling, a hidden tab) moves the
      // camera a tenth of a second at most: the opening sweep plays out
      // rather than being skipped in one step.
      _worldDrawn ? math.min(dt, 0.1) : 0,
      PuttCameraCue(
        hole: match.hole,
        phase: match.phase,
        myEgg: mine == null ? null : match.myEggRenderPosition,
        myEggResting: mine?.asleep ?? true,
        myEggHoled: mine?.holed ?? false,
        myEggVelocity: mine?.velocity ?? core.Vec2.zero,
        otherEggs: [
          if (world != null)
            for (final ball in world.balls)
              if (ball.playerId != match.localPlayerId && !ball.holed)
                match.renderPositionOf(ball.playerId),
        ],
        // Aiming, or picking a spot for a power-up: the frame holds still.
        aiming: aim.isActive || targeting.isActive,
      ),
    );
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
      onSfx(notice.sfx, notice.volume);
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
            fx.ring(spot.at!, PuttPalette.shell, size: 2.4);
            fx.ring(spot.at!, PuttPalette.shell, size: 1.4);
          }
        case PuttFxSpotKind.back:
          // Home again: a pop of the player's colour where the egg is put
          // back after the water.
          if (spot.at != null) {
            fx.poof(spot.at!);
            fx.ring(spot.at!,
                spot.who == null ? PuttPalette.shell : tintFor(spot.who!),
                size: 2.0);
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
        case PuttFxSpotKind.cast:
          _castScene(spot);
        case PuttFxSpotKind.hit:
          _hitScene(spot);
        case PuttFxSpotKind.steal:
          _launchCrow(spot);
        case PuttFxSpotKind.shieldPop:
          // The bubble bursts: a ring, the film's shards, a flash.
          final at = spot.at ?? _eggNow(spot.who);
          if (at != null) {
            fx.ring(at, _shellBlue, size: 2.8);
            fx.ring(at, PuttPalette.shell, size: 1.6);
            fx.shards(at);
            fx.sparkles(at);
          }
        case PuttFxSpotKind.shot:
          _shotScene(spot);
        case PuttFxSpotKind.restyle:
          // A new shell on the egg: a puff and a ring in its colour.
          final at = _eggNow(spot.who) ?? spot.at;
          if (at != null && spot.who != null) {
            fx.poof(at);
            fx.sparkles(at);
            fx.ring(at, tintFor(spot.who!), size: 1.8);
          }
      }
    }
    match.fxSpots.clear();
  }

  // ---- the casts' scenes ------------------------------------------------------------

  /// The Thick Shell's pale sky blue.
  static const ui.Color _shellBlue = ui.Color(0xFFBFEAFF);

  /// The crows in the air, oldest first.
  final List<_CrowFlight> _crows = [];

  /// Steam trailing a Strong Coffee's putt, per player: seconds left.
  final Map<String, double> _steamRides = {};

  /// Per egg, seconds to its next puff of steam and of the ghost's wisp.
  final Map<String, double> _steamClock = {};
  final Map<String, double> _wispClock = {};

  /// The spot each caster's last cast aimed at: its hits' scenes run
  /// toward it (the gust's wind).
  final Map<String, core.Vec2> _castSpots = {};

  /// A crow's whole flight, seconds.
  static const double crowFlightSeconds = 1.9;

  /// Where the crow lets go of its loot, as a share of its flight.
  static const double _crowDrop = 0.86;

  void _clearCastScenes() {
    _crows.clear();
    _steamRides.clear();
    _steamClock.clear();
    _wispClock.clear();
    _castSpots.clear();
  }

  /// Where [playerId]'s egg is drawn now, when it is out on the green.
  core.Vec2? _eggNow(String? playerId) {
    if (playerId == null) return null;
    final ball = match.engine.world?.ball(playerId);
    if (ball == null || ball.holed) return null;
    return match.renderPositionOf(playerId);
  }

  /// A cast, as everyone sees it: a burst in the power-up's colour at the
  /// caster's egg, and the scene's start where the cast aimed.
  void _castScene(PuttFxSpot spot) {
    final effect = spot.effectId ?? '';
    final caster = spot.who;
    final at = spot.at ?? _eggNow(caster);
    final point = spot.toward;
    if (caster != null && point != null) _castSpots[caster] = point;
    if (at != null) {
      fx.sparkles(at);
      fx.ring(at, puttPowerUpAccent(effect), size: 2.2);
    }
    switch (effect) {
      case 'sprinkler':
        if (point == null) return;
        fx.splash(point);
        fx.ring(point, PuttPalette.water, size: kSprinklerRadius);
        fx.ring(point, PuttPalette.shell, size: kSprinklerRadius * 0.55);
      case 'gust':
        if (point == null) return;
        fx.ring(point, PuttPalette.shell, size: 3.2);
        fx.poof(point);
        fx.windAround(point);
      case 'rabbit_hole':
        // Down the hole: a puff of dirt where the egg was.
        if (at == null) return;
        fx.poof(at);
        fx.dirt(at);
      case 'ghost_egg':
        if (at != null) fx.wisps(at, count: 8);
      case 'strong_coffee':
        if (at != null) fx.steam(at, count: 5);
      case 'chicken_hop':
        if (at != null) fx.feathers(at, count: 6);
      case 'thick_shell':
        if (at != null) fx.ring(at, _shellBlue, size: 1.5);
      case 'nest_magnet':
        final nest = match.hole?.nest.position;
        if (nest != null) {
          fx.ring(nest, puttPowerUpAccent(effect), size: 3.6);
          fx.sparkles(nest);
        }
      case 'nest_swap':
        // The trade: a dotted line between the two eggs' new spots.
        final mine = _eggNow(caster);
        final theirs = _eggNow(spot.other);
        if (mine != null && theirs != null) {
          fx.link(mine, theirs, puttPowerUpAccent(effect));
        }
    }
  }

  /// A cast reaching an egg: the kernels raining round it, the wind behind
  /// it, the spray on it, a swap's swirl, a hop's landing.
  void _hitScene(PuttFxSpot spot) {
    final who = spot.who;
    final at = spot.at ?? _eggNow(who);
    if (who == null || at == null) return;
    switch (spot.effectId) {
      case 'corn_rain':
        fx.kernels(at, count: 16);
      case 'gust':
        final toward = _castSpots[spot.other];
        if (toward != null) fx.windBehind(at, toward);
      case 'sprinkler':
        fx.soak(at);
      case 'nest_swap':
        // A bold trade: a poof, the swirl, two rings (violet and the
        // player's), sparkles.
        fx.poof(at);
        fx.swirl(at, tintFor(who));
        fx.ring(at, puttPowerUpAccent('nest_swap'), size: 2.8);
        fx.ring(at, tintFor(who), size: 1.8);
        fx.sparkles(at);
      case 'rabbit_hole':
        // Up out of the hole at the new spot.
        fx.dirt(at);
        fx.sparkles(at);
        fx.ring(at, PuttPalette.yolk, size: 1.8);
    }
  }

  /// A shot leaving with a next-shot power-up on it: a hawk's straight
  /// line glinting ahead, a coffee's steam trailing, a hop's feathers, the
  /// magnet's ring.
  void _shotScene(PuttFxSpot spot) {
    final who = spot.who;
    final at = spot.at;
    if (who == null || at == null) return;
    switch (spot.effectId) {
      case 'hawk_eye':
        final toward = spot.toward;
        if (toward != null) fx.sightLine(at, toward - at);
      case 'strong_coffee':
        _steamRides[who] = 1.3;
        fx.steam(at, count: 4);
      case 'chicken_hop':
        fx.feathers(at, count: 9);
      case 'nest_magnet':
        fx.ring(at, puttPowerUpAccent('nest_magnet'), size: 1.6);
    }
  }

  /// A Thieving Crow takes off from the robbed egg (or the nest, when that
  /// egg is in) for the thief's.
  void _launchCrow(PuttFxSpot spot) {
    final thief = spot.who;
    final victim = spot.other;
    final effect = spot.effectId;
    if (thief == null || victim == null || effect == null) return;
    final from = spot.at ?? _eggNow(victim) ?? match.hole?.nest.position;
    if (from == null) return;
    // Two at a time at most: a third sends the oldest off at once.
    if (_crows.length >= 2) _crows.removeAt(0);
    _crows.add(_CrowFlight(
      thiefId: thief,
      effectId: effect,
      from: from,
      startedAt: clock,
    ));
  }

  List<PuttWorldCrow> _crowsForFrame() => [
        for (final crow in _crows)
          PuttWorldCrow(
            from: crow.from,
            to: _eggNow(crow.thiefId) ?? match.hole?.nest.position ?? crow.from,
            progress: ((clock - crow.startedAt) / crowFlightSeconds)
                .clamp(0.0, 1.0)
                .toDouble(),
            effectId: crow.effectId,
          ),
      ];

  /// Once a frame: the crows land their loot and go; strong coffee steams
  /// (a wisp now and then while it waits, a trail behind its putt); a
  /// ghost leaves wisps.
  void _updateCastScenes(double dt) {
    for (final crow in _crows) {
      if (crow.landed) continue;
      if ((clock - crow.startedAt) / crowFlightSeconds < _crowDrop) continue;
      crow.landed = true;
      final at = _eggNow(crow.thiefId) ?? match.hole?.nest.position;
      if (at != null) {
        fx.sparkles(at);
        fx.ring(at, PuttPalette.yolk, size: 1.8);
      }
      // In the thief's hand now: my own carton chimes.
      if (crow.thiefId == match.localPlayerId) {
        onSfx(PuttSfx.powerUpPicked, 1);
      }
    }
    _crows.removeWhere((crow) => clock - crow.startedAt >= crowFlightSeconds);
    final world = match.engine.world;
    if (world == null || match.phase != PuttPhase.holePlay) {
      _steamRides.clear();
      return;
    }
    for (final ball in world.balls) {
      final id = ball.playerId;
      if (ball.holed) {
        _steamRides.remove(id);
        continue;
      }
      final at = match.renderPositionOf(id);
      // Strong Coffee: a trail of puffs behind the boosted putt, a wisp
      // now and then off a cup still waiting.
      final ride = _steamRides[id];
      var steamEvery = 0.0;
      if (ride != null) {
        final left = ride - dt;
        if (left <= 0) {
          _steamRides.remove(id);
        } else {
          _steamRides[id] = left;
        }
        if (ball.speed > 0.8) steamEvery = 0.045;
      } else if ((match.engine.player(id)?.nextShot.powerMultiplier ?? 1) > 1) {
        steamEvery = 0.42;
      }
      if (steamEvery > 0) {
        final next = (_steamClock[id] ?? 0) - dt;
        if (next <= 0) {
          fx.steam(at, count: 1, trailing: ride != null);
          _steamClock[id] = steamEvery;
        } else {
          _steamClock[id] = next;
        }
      }
      // Ghost Egg: pale wisps off it while it lasts.
      if (ball.flagActive(PowerUpFlag.ghost, world.tick)) {
        final next = (_wispClock[id] ?? 0) - dt;
        if (next <= 0) {
          fx.wisps(at, count: 1);
          _wispClock[id] = ball.speed > 0.8 ? 0.06 : 0.22;
        } else {
          _wispClock[id] = next;
        }
      }
    }
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
    // The shot goes where the arrow points this frame, sway and all.
    final sway = aim.swayNow(aimLayer.holdSeconds);
    final shot = aim.commit();
    if (shot == null) return;
    final angle = shot.angle + sway;
    final at = match.myBall?.position;
    if (match.submitShot(angle, shot.power) && at != null) {
      fx.dust(at, angle);
    }
  }

  void cancelAim() {
    aim.cancel();
    _dragAnchor = null;
  }

  /// The armed power-up, cast at [point] on the green: true when it went
  /// (and the burst plays there); false - nothing spent - when no slot is
  /// armed or the cast could do nothing now.
  bool castArmedAt(core.Vec2 point) {
    cancelAim();
    return targeting.castAt(match, point);
  }

  // ---- attached facts the layers read ---------------------------------------------------

  /// Egg ring colours, stable per player in id order: the same tint the
  /// HUD's scorecard dots and the name tags wear ([puttTintOf]).
  ui.Color tintFor(String playerId) => puttTintOf(match, playerId);

  double get eggRadius => match.config.physics.ballRadius;

  @override
  ui.Color backgroundColor() => const ui.Color(0x00000000);
}

/// One egg's hop: how fast it left, so the drawn arc knows its length.
class _HopRide {
  final double launchSpeed;

  const _HopRide({required this.launchSpeed});
}

/// A Thieving Crow's flight: whose egg it heads for, what it carries, the
/// spot it took the loot from, and when it left (the game's clock).
class _CrowFlight {
  final String thiefId;
  final String effectId;
  final core.Vec2 from;
  final double startedAt;

  /// Whether the loot is in the thief's hand yet.
  bool landed = false;

  _CrowFlight({
    required this.thiefId,
    required this.effectId,
    required this.from,
    required this.startedAt,
  });
}

/// Each power-up's colour on the green: the ring its cast sends out.
ui.Color puttPowerUpAccent(String effectId) => switch (effectId) {
      'hawk_eye' => PuttPalette.yolk,
      'nest_magnet' => PuttPalette.comb,
      'ghost_egg' => const ui.Color(0xFFD9CCFF),
      'chicken_hop' => PuttPalette.shell,
      'rabbit_hole' => const ui.Color(0xFFC08A55),
      'gust' => const ui.Color(0xFFE2F4FF),
      'thick_shell' => const ui.Color(0xFFBFEAFF),
      'strong_coffee' => const ui.Color(0xFFB07A52),
      'nest_swap' => const ui.Color(0xFFC3A2FF),
      'sprinkler' => PuttPalette.water,
      'corn_rain' => const ui.Color(0xFFFFC61A),
      'thieving_crow' => const ui.Color(0xFF5A5470),
      _ => PuttPalette.yolk,
    };

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
}) =>
    previewRoll(
      world: world,
      hole: hole,
      config: config,
      playerId: playerId,
      angle: angle,
      power: power,
      modifiers: modifiers,
      maxLength: maxLength,
      tailAfterBounce: tailAfterBounce,
      maxTicks: maxTicks,
    ).points;

/// [predictRoll]'s guide, and where the egg comes to rest when it stops
/// on the turf inside the guide (a soft putt): null when the guide was cut
/// first, or the egg drops into the nest or out of play.
({List<core.Vec2> points, core.Vec2? rest}) previewRoll({
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
  if (ball == null || ball.holed) return (points: const [], rest: null);
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
  core.Vec2? rest;
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
    if (ball.asleep) {
      points.add(after);
      rest = after;
      break;
    }
    if (travelled >= maxLength || afterBounce >= tailAfterBounce) {
      points.add(after);
      break;
    }
  }
  return (points: points, rest: rest);
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
    // Water, not cotton: drops in the pond's blues with white highlights,
    // a crown that keeps close to where the egg went in (over the water,
    // not spilling onto the turf), thin jets standing up out of it, and a
    // spout falling back.
    const blues = [
      ui.Color(0xFF6CC4F2),
      ui.Color(0xFF9AD8FA),
      ui.Color(0xFFFFFFFF),
      ui.Color(0xFF3FA6E6),
    ];
    for (var i = 0; i < 26; i++) {
      final angle = i * 2.39996; // golden spaced
      final speed = 1.3 + (i % 5) * 0.5;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * speed,
        life: 0.85,
        kind: _FxKind.droplet,
        size: i.isEven ? 0.46 : 0.34,
        color: blues[i % blues.length],
      ));
    }
    // Four thin jets: small drops stacked up a column, each a beat behind
    // the one under it.
    for (var jet = 0; jet < 4; jet++) {
      final angle = jet * math.pi / 2 + 0.6;
      final foot = at + core.Vec2(math.cos(angle), math.sin(angle)) * 0.35;
      for (var k = 0; k < 6; k++) {
        _particles.add(_FxParticle(
          at: foot,
          velocity:
              core.Vec2(math.cos(angle), math.sin(angle)) * (0.25 + k * 0.04),
          life: 0.75 + k * 0.05,
          kind: _FxKind.droplet,
          size: 0.24 - k * 0.015,
          color: k.isEven ? const ui.Color(0xFFFFFFFF) : blues[0],
          height: 0.1,
          climb: 7.2 + jet * 0.6 - k * 0.55,
        ));
      }
    }
    // And the spout where the egg went in, falling back.
    for (var i = 0; i < 10; i++) {
      final angle = i * 2.39996 + 0.4;
      _particles.add(_FxParticle(
        at: at,
        velocity:
            core.Vec2(math.cos(angle), math.sin(angle)) * (0.2 + (i % 3) * 0.2),
        life: 1.0,
        kind: _FxKind.droplet,
        size: 0.5 + (i % 4) * 0.05,
        color: i.isEven ? const ui.Color(0xFFFFFFFF) : blues[1],
        height: 0.15,
        climb: 6.0 + (i % 4) * 1.0,
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
    // Another player's sink: a smaller, shorter burst, so a run of sinks
    // does not bury the nest.
    final count = mine ? 64 : 16;
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 1.2 + _random.nextDouble() * 3.4;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) * speed,
        life: mine
            ? 1.6 + _random.nextDouble() * 0.8
            : 1.0 + _random.nextDouble() * 0.4,
        kind: _FxKind.confetti,
        size: 0.22 + _random.nextDouble() * 0.12,
        color: colors[i % colors.length],
        height: 0.4,
        climb: 5.5 + _random.nextDouble() * 4.5,
      ));
    }
  }

  // ---- the casts' particles ----------------------------------------------------------

  /// Corn Rain round an egg at [at]: kernels dropping out of the sky on
  /// staggered beats, bouncing twice and lying a moment.
  void kernels(core.Vec2 at, {int count = 10}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final reach = 0.35 + _random.nextDouble() * 1.4;
      final scatter = _random.nextDouble() * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at + core.Vec2(math.cos(angle), math.sin(angle)) * reach,
        velocity: core.Vec2.zero,
        life: 1.8 + _random.nextDouble() * 0.5,
        kind: _FxKind.kernel,
        size: 0.44 + _random.nextDouble() * 0.12,
        // White: the kernel's own drawing shows.
        color: const ui.Color(0xFFFFFFFF),
        height: 5.5 + _random.nextDouble() * 3,
        climb: -1 - _random.nextDouble() * 2,
        kick: core.Vec2(math.cos(scatter), math.sin(scatter)) *
            (0.9 + _random.nextDouble() * 1.4),
        delay: _random.nextDouble() * 0.5,
      ));
    }
  }

  /// A Gust's wind converging on its spot from all round.
  void windAround(core.Vec2 spot, {int count = 14}) {
    for (var i = 0; i < count; i++) {
      final angle = i / count * 2 * math.pi + _random.nextDouble() * 0.3;
      final reach = 6 + _random.nextDouble() * 5;
      final from = spot + core.Vec2(math.cos(angle), math.sin(angle)) * reach;
      _streak(from, spot, delay: _random.nextDouble() * 0.35);
    }
  }

  /// The wind behind a pushed egg at [at], running on toward [spot].
  void windBehind(core.Vec2 at, core.Vec2 spot, {int count = 10}) {
    final way = (spot - at).normalized(const core.Vec2(1, 0));
    final side = core.Vec2(-way.y, way.x);
    for (var i = 0; i < count; i++) {
      final back = 1.5 + _random.nextDouble() * 3.5;
      final off = (_random.nextDouble() * 2 - 1) * 1.1;
      final from = at - way * back + side * off;
      _streak(from, from + way * (back + 4), delay: i * 0.05);
    }
  }

  void _streak(core.Vec2 from, core.Vec2 to, {double delay = 0}) {
    final way = to - from;
    final speed = 11 + _random.nextDouble() * 5;
    final life = (way.length / speed).clamp(0.35, 0.85).toDouble();
    _particles.add(_FxParticle(
      at: from,
      velocity: way.normalized(const core.Vec2(1, 0)) * speed,
      life: life,
      kind: _FxKind.streak,
      size: 0.5 + _random.nextDouble() * 0.25,
      color: const ui.Color(0xFFFFFFFF),
      height: 0.3 + _random.nextDouble() * 0.9,
      delay: delay,
    ));
  }

  /// A Rabbit Hole's dirt, thrown up round the hole at [at].
  void dirt(core.Vec2 at) {
    for (var i = 0; i < 10; i++) {
      final angle = i / 10 * 2 * math.pi + _random.nextDouble() * 0.4;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) *
            (1.2 + _random.nextDouble() * 1.6),
        life: 0.6,
        kind: _FxKind.dust,
        size: 0.4,
        color:
            i.isEven ? const ui.Color(0xFF8A623F) : const ui.Color(0xFFB98A5E),
      ));
    }
  }

  /// A Ghost Egg's pale wisps rising off the egg at [at].
  void wisps(core.Vec2 at, {int count = 1}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at + core.Vec2(math.cos(angle), math.sin(angle)) * 0.25,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) *
            (0.2 + _random.nextDouble() * 0.5),
        life: 0.8 + _random.nextDouble() * 0.4,
        kind: _FxKind.steam,
        size: 0.32 + _random.nextDouble() * 0.12,
        color: const ui.Color(0xFFE6DEFF),
        height: 0.5,
      ));
    }
  }

  /// Strong Coffee's steam off the egg at [at]: a soft wisp, or with
  /// [trailing] the bigger puffs a boosted putt leaves behind it.
  void steam(core.Vec2 at, {int count = 1, bool trailing = false}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      _particles.add(_FxParticle(
        at: at + core.Vec2(math.cos(angle), math.sin(angle)) * 0.15,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) *
            (0.15 + _random.nextDouble() * 0.35),
        life: (trailing ? 0.8 : 1.1) + _random.nextDouble() * 0.4,
        kind: _FxKind.steam,
        size: (trailing ? 0.55 : 0.4) + _random.nextDouble() * 0.15,
        color:
            i.isEven ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFFF3E9DD),
        height: trailing ? 0.45 : 0.8,
      ));
    }
  }

  /// A Chicken Hop's feathers, puffed off the egg at [at] to drift down.
  void feathers(core.Vec2 at, {int count = 8}) {
    for (var i = 0; i < count; i++) {
      final angle = i / count * 2 * math.pi + _random.nextDouble() * 0.5;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) *
            (0.8 + _random.nextDouble() * 1.2),
        life: 1.4 + _random.nextDouble() * 0.5,
        kind: _FxKind.feather,
        size: 0.42 + _random.nextDouble() * 0.12,
        color: i % 3 == 2 ? PuttPalette.cream : PuttPalette.shell,
        height: 0.7,
        climb: 1.8 + _random.nextDouble() * 1.2,
      ));
    }
  }

  /// A popped Thick Shell: the bubble's film flying out in shards.
  void shards(core.Vec2 at) {
    const colors = [
      ui.Color(0xFFBFEAFF),
      ui.Color(0xFFFFFFFF),
      ui.Color(0xFF8FD0FF),
    ];
    for (var i = 0; i < 16; i++) {
      final angle = i / 16 * 2 * math.pi + _random.nextDouble() * 0.3;
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2(math.cos(angle), math.sin(angle)) *
            (2.2 + _random.nextDouble() * 2.4),
        life: 0.85 + _random.nextDouble() * 0.35,
        kind: _FxKind.shard,
        size: 0.22 + _random.nextDouble() * 0.12,
        color: colors[i % colors.length],
        height: 0.6 + _random.nextDouble() * 0.4,
        climb: 2.5 + _random.nextDouble() * 3.5,
        kick: core.Vec2.zero,
      ));
    }
  }

  /// A Sprinkler's spray landing on a soaked egg at [at].
  void soak(core.Vec2 at) {
    for (var i = 0; i < 10; i++) {
      final angle = i * 2.39996;
      _particles.add(_FxParticle(
        at: at,
        velocity:
            core.Vec2(math.cos(angle), math.sin(angle)) * (1 + (i % 4) * 0.6),
        life: 0.6,
        kind: _FxKind.droplet,
        size: i.isEven ? 0.34 : 0.26,
        color: i % 3 == 2
            ? const ui.Color(0xFF8FD0FF)
            : const ui.Color(0xFFFFFFFF),
      ));
    }
  }

  /// A Nest Swap's swirl round the egg at [at], in the player's [tint]
  /// and the swap's violet.
  void swirl(core.Vec2 at, ui.Color tint) {
    for (var i = 0; i < 18; i++) {
      _particles.add(_FxParticle(
        at: at,
        velocity: core.Vec2.zero,
        life: 1.2,
        kind: _FxKind.swirl,
        size: 0.7,
        color: i.isEven ? tint : const ui.Color(0xFFC3A2FF),
        orbit: at,
        orbitRadius: 0.9 + (i % 3) * 0.22,
        orbitAngle: i / 18 * 2 * math.pi,
        orbitSpeed: 7.5,
      ));
    }
  }

  /// A dotted line of glints from [from] to [to], lighting up one after
  /// another: a Nest Swap's trade.
  void link(core.Vec2 from, core.Vec2 to, ui.Color color) {
    final way = to - from;
    final steps = (way.length / 0.8).ceil().clamp(2, 30);
    for (var i = 0; i <= steps; i++) {
      _particles.add(_FxParticle(
        at: from + way * (i / steps),
        velocity: core.Vec2.zero,
        life: 0.8,
        kind: _FxKind.glint,
        size: 0.5,
        color: i.isEven ? color : PuttPalette.shell,
        delay: i * 0.02,
      ));
    }
  }

  /// Hawk Eye's straight line: glints along the shot's [heading] from
  /// [at], lighting up one after another ahead of the egg.
  void sightLine(core.Vec2 at, core.Vec2 heading) {
    final way = heading.normalized(const core.Vec2(1, 0));
    for (var i = 1; i <= 18; i++) {
      final along = i * 0.7;
      _particles.add(_FxParticle(
        at: at + way * along,
        velocity: core.Vec2.zero,
        life: 0.8,
        kind: _FxKind.glint,
        size: 0.6,
        color: i.isEven ? PuttPalette.yolk : PuttPalette.shell,
        delay: i * 0.03,
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
      // Still waiting for its beat (a staggered rain, a wind's gusts).
      if (particle.age < 0) continue;
      particle.advance(dt);
    }
    _particles.removeWhere((particle) => particle.age >= particle.life);
  }
}

// ---- particles -------------------------------------------------------------------------

enum _FxKind {
  droplet,
  sparkle,
  suction,
  poof,
  dust,
  confetti,
  ring,
  kernel,
  streak,
  steam,
  swirl,
  shard,
  feather,
  glint,
}

class _FxParticle {
  core.Vec2 position;
  core.Vec2 velocity;

  /// Where a suction particle flies home to.
  final core.Vec2? toward;

  /// Seconds lived; it starts below zero by a staggered particle's delay,
  /// and the particle shows from 0.
  double age;
  final double life;
  final _FxKind kind;
  final double size;

  /// Null keeps the kind's own color.
  final ui.Color? color;

  /// Height over the green and its rate, for the particles that fly (the
  /// confetti falls under gravity and settles on the turf; kernels and
  /// shards bounce).
  double? height;
  double climb;

  /// What a kernel's first bounce throws it along the turf.
  final core.Vec2 kick;
  int _bounces = 0;

  /// A swirl's centre, radius, angle and turn rate.
  final core.Vec2? orbit;
  final double orbitRadius;
  double orbitAngle;
  final double orbitSpeed;

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
    this.kick = core.Vec2.zero,
    this.orbit,
    this.orbitRadius = 0,
    this.orbitAngle = 0,
    this.orbitSpeed = 0,
    double delay = 0,
  })  : position = at,
        age = -delay;

  void advance(double dt) {
    switch (kind) {
      case _FxKind.kernel:
      case _FxKind.shard:
        _fallAndBounce(dt, gravity: kind == _FxKind.kernel ? 24 : 16);
        return;
      case _FxKind.feather:
        // Up with the puff, then a slow rocking drift down.
        position = position + velocity * dt;
        velocity = velocity + velocity * (-1.6 * dt);
        climb = math.max(climb - 6 * dt, -0.75);
        height = math.max(0.06, (height ?? 0) + climb * dt);
        return;
      case _FxKind.swirl:
        final centre = orbit ?? position;
        orbitAngle += orbitSpeed * dt;
        final shrink = 1 - 0.35 * (age / life).clamp(0.0, 1.0);
        position = centre +
            core.Vec2(math.cos(orbitAngle), math.sin(orbitAngle)) *
                (orbitRadius * shrink);
        return;
      case _FxKind.streak:
        position = position + velocity * dt;
        return;
      case _FxKind.glint:
        return;
      default:
        break;
    }
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
    if (kind == _FxKind.droplet && height != null) {
      // A spout's drop: up, then back down into the water.
      climb -= 16.0 * dt;
      height = math.max(0.05, height! + climb * dt);
    }
    velocity = velocity + velocity * (-2.2 * dt);
  }

  /// A kernel or a shard under gravity: down onto the turf, a bounce or
  /// two (a kernel's first one throws it along its [kick]), then still.
  void _fallAndBounce(double dt, {required double gravity}) {
    position = position + velocity * dt;
    velocity = velocity + velocity * (-1.4 * dt);
    climb -= gravity * dt;
    var h = (height ?? 0) + climb * dt;
    if (h <= 0.08) {
      h = 0.08;
      final bounces = kind == _FxKind.kernel ? 2 : 1;
      if (_bounces < bounces && climb < -1.2) {
        climb = -climb * 0.42;
        if (_bounces == 0 && kind == _FxKind.kernel) velocity = kick;
        velocity = velocity * 0.6;
        _bounces++;
      } else {
        climb = 0;
        velocity = core.Vec2.zero;
      }
    }
    height = h;
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
      _FxKind.kernel => PuttWorldFxKind.kernel,
      _FxKind.streak => PuttWorldFxKind.streak,
      _FxKind.steam => PuttWorldFxKind.steam,
      _FxKind.swirl => PuttWorldFxKind.swirl,
      _FxKind.shard => PuttWorldFxKind.shard,
      _FxKind.feather => PuttWorldFxKind.feather,
      _FxKind.glint => PuttWorldFxKind.glint,
    };
    return PuttWorldFx(
      kind: kind,
      at: position,
      // A streak turns along its run.
      toward: this.kind == _FxKind.streak
          ? position + velocity.normalized(const core.Vec2(1, 0))
          : toward,
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
