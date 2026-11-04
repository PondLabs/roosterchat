// The game view of Sunny Side Putt: a Flame-rendered, top-down cartoon
// farm green with slingshot aim, an animated crowd of eggs, nest suction,
// splashes and sparkle bursts, wrapped by the Flutter HUD and menus.
//
// Split of work:
//   * [SunnySidePuttView] - the Flutter shell: the GameWidget, pointer
//     plumbing, Esc-to-pause, the HUD, the menus and the spectator strip
//     (their own files), and the audio service's cue tap.
//   * [SunnySidePuttGame] - the FlameGame: the camera fitted to the hole,
//     the fixed-tick simulation driven through `PuttMatch.update`, and the
//     paintable layers.
//
// Art is code-drawn in `putt_art.dart` from the Rooster palette - ink
// outlines, Cream fairway planks, Spruce hedges, Yolk accents - and the
// rooster host (comb worn as a crown) stands at the green's edge as the
// round's emcee. Nothing here touches the network: the match is the local
// harness over the rules engine (`putt_match.dart`); the session wires the
// authoritative host under the same seams later.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart'
    as hole;
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart'
    as core;

import 'aim_controller.dart';
import 'putt_art.dart';
import 'putt_audio.dart';
import 'putt_hud.dart';
import 'putt_match.dart';
import 'putt_menus.dart';
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

  void _pointerDown(Offset at, Size size) => game?.beginAim(_toWorld(at, size));

  void _pointerMove(Offset at, Size size) => game?.moveAim(_toWorld(at, size));

  void _pointerUp(Offset at, Size size) => game?.endAim(_toWorld(at, size));

  core.Vec2 _toWorld(Offset at, Size size) {
    final game = this.game;
    if (game == null) return core.Vec2.zero;
    return game.screenToWorld(Vector2(at.dx, at.dy), size);
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
                onPointerDown: (event) =>
                    _pointerDown(event.localPosition, size),
                onPointerMove: (event) =>
                    _pointerMove(event.localPosition, size),
                onPointerUp: (event) => _pointerUp(event.localPosition, size),
                onPointerCancel: (event) => game?.cancelAim(),
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

class SunnySidePuttGame extends FlameGame {
  final PuttMatch match;

  /// The audio tap: strokes, bounces, timers, the works.
  final void Function(PuttSfx sfx) onSfx;

  final AimController aim = AimController();

  /// Seconds since the game booted, for art that breathes.
  double clock = 0;

  late final PuttBoardLayer board;
  late final PuttFxLayer fx;
  late final PuttActorsLayer actors;
  late final PuttAimLayer aimLayer;

  SunnySidePuttGame({required this.match, required this.onSfx});

  @override
  Future<void> onLoad() async {
    board = PuttBoardLayer(this);
    fx = PuttFxLayer(this);
    actors = PuttActorsLayer(this);
    aimLayer = PuttAimLayer(this);
    for (final layer in [board, fx, actors, aimLayer]) {
      await world.add(layer);
    }
    _fitCamera();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _fitCamera();
  }

  String? _fittedHole;

  void _fitCamera() {
    final hole = match.hole;
    if (hole == null || size.x == 0 || size.y == 0) return;
    const margin = 2.5;
    final bounds = hole.bounds;
    final width = bounds.width + margin * 2;
    final height = bounds.height + margin * 2 + 2.2; // room for the host
    final zoom =
        math.min(size.x / width, size.y / height).clamp(0.05, 40.0).toDouble();
    camera.viewfinder.zoom = zoom;
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = Vector2(
        (bounds.min.x + bounds.max.x) / 2, (bounds.min.y + bounds.max.y) / 2);
    _fittedHole = hole.id;
  }

  @override
  void update(double dt) {
    clock += dt;
    super.update(dt);
    match.update(dt);
    aim.noWobble = match.myNextShotSteady;
    final holeId = match.hole?.id;
    if (holeId != null && holeId != _fittedHole) {
      _fitCamera();
      aim.cancel();
    }
    if (match.phase != PuttPhase.holePlay) aim.cancel();
    _spendNotices();
    _spendFxSpots();
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

  /// Screen (widget-local) coordinates into the world, computed by hand:
  /// the viewport is the whole widget and the finder sits at its middle.
  core.Vec2 screenToWorld(Vector2 screen, ui.Size widgetSize) {
    final zoom = camera.viewfinder.zoom;
    final center = camera.viewfinder.position;
    return core.Vec2(
      (screen.x - widgetSize.width / 2) / zoom + center.x,
      (screen.y - widgetSize.height / 2) / zoom + center.y,
    );
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

// ---- layers ---------------------------------------------------------------------------

/// Everything the green is made of: apron, plank fairway, tee, water,
/// boosts, portals, silos, decorations, hedges, the "?" cartons, the nest,
/// and the rooster host standing off-green.
class PuttBoardLayer extends Component {
  final SunnySidePuttGame game;

  PuttBoardLayer(this.game);

  @override
  void render(ui.Canvas canvas) {
    final hole = game.match.hole;
    if (hole == null) return;
    final bounds = hole.bounds;
    drawApron(
        canvas,
        ui.Rect.fromLTRB(bounds.min.x - 3, bounds.min.y - 3, bounds.max.x + 3,
            bounds.max.y + 3));
    drawFairway(
        canvas,
        ui.Rect.fromLTRB(
            bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y));
    drawTeeMarker(
        canvas, ui.Offset(hole.tee.x, hole.tee.y), game.eggRadius * 1.6);
    for (final shape in hole.water) {
      _drawWaterShape(canvas, shape);
    }
    for (final strip in hole.boosts) {
      drawBoostStrip(canvas, ui.Offset(strip.from.x, strip.from.y),
          ui.Offset(strip.to.x, strip.to.y), strip.width);
    }
    for (final pair in hole.portals) {
      drawPortal(canvas, ui.Offset(pair.a.x, pair.a.y), pair.radius,
          time: game.clock);
      drawPortal(canvas, ui.Offset(pair.b.x, pair.b.y), pair.radius,
          time: game.clock + 1.6);
    }
    for (final well in hole.wells) {
      _drawSilo(canvas, well);
    }
    for (final decoration in hole.decorations) {
      _drawDecoration(canvas, decoration);
    }
    for (final box in hole.boxes) {
      drawQuestionBox(canvas, ui.Offset(box.position.x, box.position.y),
          box.radius, game.clock);
    }
    for (final arc in hole.arcs) {
      drawWallArc(canvas, ui.Offset(arc.center.x, arc.center.y), arc.radius,
          arc.startAngle, arc.sweep, _hedgeWidth,
          bumper: arc.bumper);
    }
    for (final wall in hole.walls) {
      drawWallSegment(
        canvas,
        ui.Offset(wall.a.x, wall.a.y),
        ui.Offset(wall.b.x, wall.b.y),
        _hedgeWidth,
        bumper: wall.bumper,
      );
    }
    drawNest(canvas, ui.Offset(hole.nest.position.x, hole.nest.position.y),
        hole.nest.radius,
        time: game.clock);
    _drawHost(canvas, bounds);
  }

  /// The hedge crown width in world units.
  static const double _hedgeWidth = 1.0;

  void _drawWaterShape(ui.Canvas canvas, hole.WaterShape shape) {
    switch (shape) {
      case hole.WaterCircle():
        drawWaterCircle(canvas, ui.Offset(shape.center.x, shape.center.y),
            shape.radius, game.clock);
      case hole.WaterRect():
        final rect = shape.rect;
        final area =
            ui.Rect.fromLTRB(rect.min.x, rect.min.y, rect.max.x, rect.max.y);
        _drawWaterArea(canvas, area);
      case hole.WaterPolygon():
        final path = ui.Path();
        var first = true;
        for (final point in shape.points) {
          if (first) {
            path.moveTo(point.x, point.y);
            first = false;
          } else {
            path.lineTo(point.x, point.y);
          }
        }
        path.close();
        _drawWaterPath(canvas, path);
    }
  }

  void _drawWaterArea(ui.Canvas canvas, ui.Rect area) {
    canvas.drawRect(area, solidPaint(PuttPalette.water));
    canvas.drawRect(area, strokePaint(PuttPalette.waterDeep, 0.2));
  }

  void _drawWaterPath(ui.Canvas canvas, ui.Path path) {
    canvas.drawPath(path, solidPaint(PuttPalette.water));
    canvas.drawPath(path, strokePaint(PuttPalette.waterDeep, 0.2));
  }

  /// The silo: a shadowed pull, a stone ring, a spruce mouth, drifting
  /// dust.
  void _drawSilo(ui.Canvas canvas, hole.GravityWell well) {
    final center = ui.Offset(well.position.x, well.position.y);
    canvas.drawCircle(
        center, well.radius, solidPaint(const ui.Color(0x14150E08)));
    final ring = ui.Rect.fromCircle(center: center, radius: well.radius * 0.6);
    canvas.drawOval(ring, solidPaint(PuttPalette.stone));
    canvas.drawOval(ring, strokePaint(PuttPalette.ink, 0.2));
    final mouth =
        ui.Rect.fromCircle(center: center, radius: well.radius * 0.34);
    canvas.drawOval(mouth, solidPaint(const ui.Color(0xFF1D1512)));
    canvas.drawOval(mouth, strokePaint(PuttPalette.ink, 0.14));
    final dust = strokePaint(const ui.Color(0x590F0808), 0.1);
    for (var i = 0; i < 3; i++) {
      final start = game.clock * 2 + i * 2 * math.pi / 3;
      canvas.drawArc(ring, start, math.pi * 0.5, false, dust);
    }
  }

  void _drawDecoration(ui.Canvas canvas, hole.Decoration decoration) {
    final at = ui.Offset(decoration.at.x, decoration.at.y);
    switch (decoration.kind) {
      case 'hay':
        drawHay(canvas, at, decoration.numbers['size'] ?? 1.2);
      case 'fence':
        drawFence(canvas, at, (decoration.numbers['posts'] ?? 5).round(),
            decoration.numbers['length'] ?? 1.4);
      case 'tee_marker':
        drawTeeMarker(canvas, at, 0.8);
      default:
        // Unknown tags rest as a pebble, so nothing smuggles in unseen.
        canvas.drawCircle(at, 0.25, solidPaint(PuttPalette.stone));
    }
  }

  /// The rooster host, planted just off the green's far corner, bobbing.
  void _drawHost(ui.Canvas canvas, core.Rect bounds) {
    final base = ui.Offset(bounds.max.x + 0.8, bounds.min.y - 0.6);
    drawRoosterHead(canvas, base, 1.5,
        facing: -0.3, bob: math.sin(game.clock * 2) * 0.12);
  }
}

/// The moving things: the hen (or any obstacle) and the eggs.
class PuttActorsLayer extends Component {
  final SunnySidePuttGame game;

  PuttActorsLayer(this.game);

  @override
  void render(ui.Canvas canvas) {
    final w = game.match.engine.world;
    final hole = game.match.hole;
    if (w == null || hole == null) return;
    for (final obstacle in hole.obstacles) {
      final dt = game.match.config.physics.dt;
      final now = henPositionAt(obstacle, w.tick, dt);
      final then = henPositionAt(obstacle, w.tick + 1, dt);
      final at = ui.Offset.lerp(
        ui.Offset(now.x, now.y),
        ui.Offset(then.x, then.y),
        game.match.alpha,
      );
      drawHen(canvas, at ?? ui.Offset(now.x, now.y), obstacle.radius,
          phase: (w.tick + game.match.alpha) * 0.6);
    }
    for (final ball in w.balls) {
      if (ball.holed) continue; // in the nest; the suction told the story
      final position = game.match.renderPositionOf(ball.playerId);
      final speed = ball.velocity.length;
      final squash = (speed / 28).clamp(0.0, 0.25).toDouble();
      final look = speed > 0.5
          ? ui.Offset(ball.velocity.x / speed, ball.velocity.y / speed)
          : ui.Offset.zero;
      drawEgg(
        canvas,
        ui.Offset(position.x, position.y),
        game.eggRadius,
        tint: game.tintFor(ball.playerId),
        squash: squash,
        look: look,
      );
    }
  }
}

/// The aim arrow: from the egg, out the way the shot will fly, long by
/// power, swaying by the wobble the engine may apply (gone under Hawk
/// Eye), with a power ring around the egg that fills with the pull.
class PuttAimLayer extends Component {
  final SunnySidePuttGame game;

  /// Seconds the aim has been held, for the sway's clock.
  double holdSeconds = 0;

  PuttAimLayer(this.game);

  @override
  void update(double dt) {
    holdSeconds = game.aim.isActive ? holdSeconds + dt : 0;
  }

  @override
  void render(ui.Canvas canvas) {
    final aim = game.aim;
    final state = aim.state;
    if (!aim.isActive || state == null) return;
    final origin = aim.origin!;
    final center = ui.Offset(origin.x, origin.y);
    final angle = state.angle + aim.visualWobble(holdSeconds);
    final direction = ui.Offset(math.cos(angle), math.sin(angle));
    final length = 1.5 + state.power * 4.5;
    final tip = center + direction * length;

    // The pull's ghost: a soft tail back behind the egg toward the
    // pointer's side.
    final ghost = strokePaint(const ui.Color(0x598FB4DA), 0.14);
    final pull = center - direction * math.min(state.dragLength, length);
    canvas.drawLine(center, pull, ghost);

    // The shaft: ink underlay, comb red on top - it must read on planks
    // and on the apron both.
    final shaft = strokePaint(PuttPalette.ink, 0.62)
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(center, tip, shaft);
    final shaftRed = strokePaint(PuttPalette.comb, 0.4)
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(center, tip, shaftRed);

    // The head.
    final head = ui.Path()
      ..moveTo(tip.dx + direction.dx * 0.7, tip.dy + direction.dy * 0.7)
      ..lineTo(tip.dx - direction.dy * 0.42, tip.dy + direction.dx * 0.42)
      ..lineTo(tip.dx + direction.dy * 0.42, tip.dy - direction.dx * 0.42)
      ..close();
    canvas.drawPath(head, solidPaint(PuttPalette.ink));

    // The power ring: a yolk arc filling clockwise from the top; a full
    // ring is a full stroke. The estimate beats a number nobody reads
    // mid-flick.
    final ringRadius = game.eggRadius * 1.9;
    final ringBox = ui.Rect.fromCircle(center: center, radius: ringRadius);
    if (state.power < 0.98) {
      canvas.drawArc(ringBox, -math.pi / 2, 2 * math.pi, false,
          strokePaint(const ui.Color(0x40211514), 0.22));
    }
    canvas.drawArc(ringBox, -math.pi / 2, 2 * math.pi * state.power, false,
        strokePaint(PuttPalette.yolk, 0.24));
  }
}

/// The bursts: splash droplets, suction rings, poofs, pickup sparkles.
/// Each lives about half a second, on plain velocity math, no shaders.
class PuttFxLayer extends Component {
  final SunnySidePuttGame game;

  PuttFxLayer(this.game);

  final List<_FxParticle> _particles = [];

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

  @override
  void update(double dt) {
    for (final particle in _particles) {
      particle.age += dt;
      particle.advance(dt);
    }
    _particles.removeWhere((particle) => particle.age >= particle.life);
  }

  @override
  void render(ui.Canvas canvas) {
    for (final particle in _particles) {
      final progress = (particle.age / particle.life).clamp(0.0, 1.0);
      final at = ui.Offset(particle.position.x, particle.position.y);
      switch (particle.kind) {
        case _FxKind.droplet:
          drawDroplet(canvas, at, particle.size, progress);
        case _FxKind.sparkle:
          drawSparkle(canvas, at, particle.size, progress,
              particle.color ?? PuttPalette.yolk);
        case _FxKind.suction:
          final target =
              ui.Offset(particle.toward!.x + 0.2, particle.toward!.y + 0.2);
          final drawn = ui.Offset.lerp(at, target, progress * progress) ?? at;
          _drawRing(canvas, drawn, particle.size * (1 - progress),
              particle.color ?? PuttPalette.yolk, 1 - progress);
        case _FxKind.poof:
          _drawRing(canvas, at, particle.size * (1 + progress),
              particle.color ?? PuttPalette.stone, 1 - progress);
      }
    }
  }

  void _drawRing(ui.Canvas canvas, ui.Offset at, double radius, ui.Color color,
      double alpha) {
    canvas.drawCircle(
        at,
        radius,
        solidPaint(
            color.withValues(alpha: (alpha * 0.7).clamp(0.0, 1.0).toDouble())));
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
