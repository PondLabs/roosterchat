// The demo entry: the game plays itself on the real courses, for
// screenshots and recordings (built with --dart-define=PUTT_DEMO=true,
// which main() branches off before anything the app would otherwise boot).
//
// The local egg plays the hole's own reference solution - aimed with the
// real drag, so the arrow, its power ring and the roll guide show - with a
// small, fixed jitter; the other players (Maya, Jonas, Lou and friends, the
// brand's demo crew) putt toward the nest with seeded jitter and hop in
// with a Rabbit Hole when a rail stands in their way. The hole's overview
// opens it, the camera comes in close, the scoreboard moves on by itself.
//
// On the web the page's query picks what to show:
//   ?course=the_pond&hole=3&bots=3
// course: a catalog id (the_coop, the_corn_maze, the_pond, the_farm_road,
// the_barn; default the_coop), hole: 1-6 (the match opens there), bots:
// 0-7 other players (default 3). For close looks at the art, cam= holds the
// camera: nest (the nest and its flag), host (the rooster by the green),
// wide (the farm around the course), tee (the eggs on the tee). To show the
// power-ups: powerups=rabbit_hole,gust fills the viewer's carton, and
// arm=sprinkler (with armAt=3, seconds into the hole) arms that one's
// targeting over the green - the scripted putts wait while it is up.
// soft=0.25 makes the viewer's first putt a soft one at that power,
// straight at the nest (the guide's resting-spot mark). To show the casts
// everyone sees, script= has the crew (and the viewer) cast at set moments
// of each hole: who.power@seconds, comma separated, who being me or a crew
// member's first name, e.g.
//   script=me.thick_shell@3,maya.corn_rain@5,lou.thieving_crow@7.5
// (the caster is handed the power-up; a crow robs the viewer when they
// hold one, a swap trades with the viewer, a gust blows the others back
// toward the tee, a sprinkler soaks the crowd). Each hole logs
// `putt-demo: hole open <id>` to the console when the camera starts on it
// (its first drawn frame), and the script's seconds count from there, so a
// capture can time its shots from the hole's start, not the page's load.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/course_kit.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart'
    show puttLaunchPowerUps;
import 'package:rooster/ui/organisms/sunny_side_putt/putt_targeting.dart'
    show PuttPowerAim, puttPowerAimOf;
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

Future<void> runPuttDemo() async {
  runApp(const PuttDemoApp());
}

class PuttDemoApp extends StatelessWidget {
  const PuttDemoApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      // Not translated: the game's title never translates.
      title: 'Sunny Side Putt',
      debugShowCheckedModeBanner: false,
      home: PuttDemoPage(),
    );
  }
}

class PuttDemoPage extends StatefulWidget {
  /// The page's query (the web page's own when left out).
  final Map<String, String>? query;

  const PuttDemoPage({this.query});

  @override
  State<PuttDemoPage> createState() => _PuttDemoPageState();
}

/// The demo crew, in seat order after the viewer.
const _crew = [
  // Not translated: the demo crew's names are names.
  ('peer-maya', 'Maya'),
  ('peer-jonas', 'Jonas'),
  ('peer-lou', 'Lou'),
  ('peer-ana', 'Ana'),
  ('peer-theo', 'Theo'),
  ('peer-iris', 'Iris'),
  ('peer-bento', 'Bento'),
];

class _PuttDemoPageState extends State<PuttDemoPage> {
  late final PuttMatch match;
  late final List<SunnySidePuttHole> _holes;
  SunnySidePuttGame? _game;

  Timer? _ticker;
  final math.Random _random = math.Random(7);

  /// Seconds since the current hole came up (wall time, so a busy frame
  /// never pushes the script back), and which hole that is.
  double _holeTime = 0;
  final Stopwatch _holeClock = Stopwatch();
  String? _holeId;

  /// My reference shots taken this hole, and the aim in flight.
  int _myShot = 0;
  _DemoDrag? _drag;
  double _myNextAt = 3.2;

  /// Whether the demo's first hole is still ahead: on it the viewer waits
  /// a beat longer, so the aim coach shows over the egg first.
  bool _firstHole = true;

  /// Per bot: shots taken this hole and when the next may go.
  final Map<String, int> _botShots = {};
  final Map<String, double> _botNextAt = {};

  /// The hole's intended route: the tee, where each reference shot comes
  /// to rest, the nest. The crew putts along it.
  List<Vec2> _route = const [];

  double _phaseTime = 0;

  /// The held camera, when the query asks for one.
  String? _cam;

  /// The carton the query asks for, and the power-up to arm (and when).
  List<String> _powerUps = const [];
  String? _arm;
  double _armAt = 3;

  /// The viewer's first putt soft, at this power (the `soft` query).
  double? _soft;

  /// The query's casts: (hole seconds, player id, power-up), each played
  /// once a hole, and which of them went this hole.
  List<(double, String, String)> _script = const [];
  final Set<int> _scriptDone = {};

  /// The query's staged splash: the first bot's first putt of the hole
  /// goes into the nearest pond (for a look at the splash and the return).
  bool _splash = false;
  bool _splashed = false;
  bool _armed = false;

  static const _step = Duration(milliseconds: 33);

  @override
  void initState() {
    super.initState();
    final query = widget.query ?? Uri.base.queryParameters;
    final courseId = query['course'] ?? 'the_coop';
    final course = sunnySidePuttCourses.firstWhere(
      (c) => c.id == courseId,
      orElse: () => sunnySidePuttCourses.first,
    );
    final start =
        (int.tryParse(query['hole'] ?? '') ?? 1).clamp(1, course.holes.length);
    _holes = course.holes;
    _cam = query['cam'];
    _powerUps = (query['powerups'] ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .take(3)
        .toList();
    _arm = query['arm'];
    _armAt = double.tryParse(query['armAt'] ?? '') ?? 3;
    _splash = query['splash'] == '1';
    _soft = double.tryParse(query['soft'] ?? '');
    _script = [
      for (final entry in (query['script'] ?? '').split(','))
        if (_parseCast(entry) case final cast?) cast,
    ];
    final bots = (int.tryParse(query['bots'] ?? '') ?? 3).clamp(0, 7);
    final seated = [for (final (id, _) in _crew.take(bots)) id];
    final played =
        CourseDef(id: course.id, holes: [for (final hole in _holes) hole.hole]);
    match = PuttMatch(
      config: PuttConfig(
        mode: GameMode.casual,
        courses: [played],
        catalog: {played.id: played},
        seed: 4242,
        // The match opens on the asked hole, numbered as in its course.
        startHoleIndex: start - 1,
        // The real effects, as a session registers them.
        powerUps: puttLaunchPowerUps(),
        // The demo plays the reference lines as written: a swaying arrow
        // would leave every later shot of the hole off its mark.
        wobbleMaxRadians: 0,
        // The results move on by themselves, as in a live session.
        scoreboardSeconds: puttScoreboardSeconds,
      ),
      // Not translated: the viewer's own name in the demo.
      displayNames: {
        'me': 'Gabriel',
        for (final (id, name) in _crew) id: name,
      },
      // The crew's pictures: their initial on a disc of their colour
      // (painted once the match knows the colours).
      avatarOf: (id) => _avatars[id],
      seatedPlayerIds: seated,
    )..boot();
    _paintAvatars();
    _ticker = Timer.periodic(_step, (_) => _tick());
  }

  /// The crew's stand-in pictures, by player id.
  final Map<String, ImageProvider> _avatars = {};

  Future<void> _paintAvatars() async {
    for (final (id, name) in _crew) {
      const size = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final tint = puttTintOf(match, id);
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2, Paint()..color = tint);
      canvas.drawCircle(const Offset(size * 0.38, size * 0.34), size * 0.3,
          Paint()..color = const Color(0x33FFFFFF));
      final text = TextPainter(
        text: TextSpan(
          text: name.characters.first,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
          canvas, Offset((size - text.width) / 2, (size - text.height) / 2));
      final image =
          await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null) {
        _avatars[id] = MemoryImage(bytes.buffer.asUint8List());
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  SunnySidePuttHole? get _currentHole {
    final id = match.hole?.id;
    for (final hole in _holes) {
      if (hole.hole.id == id) return hole;
    }
    return null;
  }

  void _tick() {
    const dt = 0.033;
    switch (match.phase) {
      case PuttPhase.holePlay:
        break;
      case PuttPhase.holeScoreboard:
        // The engine moves on by itself after the results' pause.
        return;
      case PuttPhase.lobby:
        match.advance();
        return;
      case PuttPhase.awaitingNextCourse:
      case PuttPhase.matchOver:
        _phaseTime += dt;
        if (_phaseTime > 3) {
          _phaseTime = 0;
          match.startCourse(match.config.courses.first.id);
        }
        return;
    }
    _phaseTime = 0;
    final hole = match.hole;
    if (hole == null) return;
    if (hole.id != _holeId) {
      _holeId = hole.id;
      _holeTime = 0;
      // The script's clock starts with the camera's (below), once the
      // green is up and drawing.
      _holeClock
        ..stop()
        ..reset();
      _myShot = 0;
      _drag = null;
      // The first hole waits for the coach to show the gesture once.
      _myNextAt = _firstHole ? 5.6 : 3.2;
      _firstHole = false;
      _botShots.clear();
      _holedSeen.clear();
      _reactionsDue.clear();
      _splashLaughed = false;
      _botNextAt.clear();
      _route = _routeOf(hole);
      _armed = false;
      _scriptDone.clear();
      final me = match.localPlayer;
      if (me != null) {
        for (final id in _powerUps) {
          if (!me.inventory.contains(id)) me.inventory.add(id);
        }
      }
    }
    if (!_holeClock.isRunning) {
      final director = _game?.director;
      if (director == null ||
          director.holeId != hole.id ||
          director.holeSeconds <= 0) {
        return;
      }
      _holeClock.start();
      // Not translated: a log line the capture tool times its shots from.
      debugPrint('putt-demo: hole open ${hole.id}');
    }
    _holeTime = _holeClock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    _holdCamera(hole);
    _armPowerUp(hole);
    if (!(_game?.targeting.isActive ?? false)) _driveMe(hole);
    _driveBots(hole);
    _driveScript(hole);
    _driveReactions();
  }

  /// One `who.power@seconds` of the query's script, or null when it does
  /// not read as one.
  static (double, String, String)? _parseCast(String entry) {
    final at = entry.split('@');
    if (at.length != 2) return null;
    final seconds = double.tryParse(at[1]);
    final who = at[0].split('.');
    if (seconds == null || who.length != 2 || who[1].isEmpty) return null;
    final id = who[0] == 'me' ? 'me' : 'peer-${who[0].toLowerCase()}';
    return (seconds, id, who[1]);
  }

  /// The query's casts at their moments: the caster is handed the
  /// power-up and casts it at the target a player would pick.
  void _driveScript(HoleDef hole) {
    for (var i = 0; i < _script.length; i++) {
      final (at, who, effect) = _script[i];
      if (_scriptDone.contains(i) || _holeTime < at) continue;
      _scriptDone.add(i);
      final player = match.engine.player(who);
      final egg = match.engine.world?.ball(who);
      if (player == null) continue;
      if (!player.inventory.contains(effect)) {
        if (player.inventory.isFull) player.inventory.takeFirst();
        player.inventory.add(effect);
      }
      final target = _scriptTarget(hole, who, effect, egg);
      if (target == null && puttPowerAimOf(effect) != PuttPowerAim.none) {
        continue;
      }
      if (who == match.localPlayerId) {
        match.usePowerUp(effect, target);
      } else {
        match.engine.usePowerUp(who, effect, target);
      }
    }
  }

  /// Where a scripted cast aims: a crow robs the viewer when they hold a
  /// power-up (else whoever does), a swap trades with the viewer, a gust
  /// blows the others back toward the tee, a sprinkler soaks the crowd, a
  /// rabbit hole hops toward the nest.
  PowerUpTarget? _scriptTarget(
      HoleDef hole, String who, String effect, BallBody? egg) {
    final others = [
      for (final ball in match.engine.world?.balls ?? const <BallBody>[])
        if (ball.playerId != who && !ball.holed) ball,
    ];
    switch (effect) {
      case 'thieving_crow':
        final victims = [
          for (final player in match.engine.players)
            if (player.id != who &&
                !player.spectator &&
                !player.inventory.isEmpty)
              player.id,
        ];
        if (victims.isEmpty) {
          // Something to steal: the viewer picked up a crate on the way.
          match.engine.player(match.localPlayerId)?.inventory.add('gust');
          return PowerUpTarget.player(match.localPlayerId);
        }
        return PowerUpTarget.player(victims.contains(match.localPlayerId)
            ? match.localPlayerId
            : victims.first);
      case 'nest_swap':
        if (others.isEmpty) return null;
        final mine = others.where((b) => b.playerId == match.localPlayerId);
        return PowerUpTarget.player(
            (mine.isNotEmpty ? mine.first : others.first).playerId);
      case 'gust':
        return PowerUpTarget.point(hole.tee);
      case 'sprinkler':
        if (others.isEmpty) return null;
        final crowd = others.map((b) => b.position).reduce((a, b) => a + b) *
            (1 / others.length);
        return PowerUpTarget.point(crowd);
      case 'rabbit_hole':
        if (egg == null || egg.holed) return null;
        return PowerUpTarget.point(egg.position +
            (hole.nest.position - egg.position).normalized(const Vec2(1, 0)) *
                5);
      default:
        return null;
    }
  }

  /// The query's power-up, armed over the green at its moment, its reticle
  /// resting where it would do the most.
  void _armPowerUp(HoleDef hole) {
    final game = _game;
    final effect = _arm;
    if (game == null || effect == null || _armed || _holeTime < _armAt) return;
    final slot = match.myInventory.indexOf(effect);
    if (slot < 0 || !match.myShotReady) return;
    _armed = true;
    if (effect == 'thieving_crow') {
      // Someone to rob: the crew picked up a crate or two on the way.
      for (final (id, grab) in const [
        ('peer-maya', 'gust'),
        ('peer-lou', 'nest_magnet')
      ]) {
        final player = match.engine.player(id);
        if (player != null && player.inventory.isEmpty) {
          player.inventory.add(grab);
        }
      }
    }
    game.targeting.tapSlot(match, slot, effect);
    final mine = match.myBall?.position ?? hole.tee;
    final others = [
      for (final ball in match.engine.world?.balls ?? const <BallBody>[])
        if (ball.playerId != match.localPlayerId && !ball.holed) ball.position,
    ];
    final crowd = others.isEmpty
        ? hole.nest.position
        : others.reduce((a, b) => a + b) * (1 / others.length);
    game.targeting.hover = switch (effect) {
      'rabbit_hole' =>
        mine + (hole.nest.position - mine).normalized(const Vec2(1, 0)) * 5,
      'sprinkler' => crowd,
      _ => hole.nest.position,
    };
  }

  /// The query's held camera, re-asked every beat so the game's own
  /// choreography never takes it back.
  void _holdCamera(HoleDef hole) {
    final game = _game;
    final cam = _cam;
    if (game == null || cam == null) return;
    final rig = game.world3d.rig;
    final bounds = hole.bounds;
    game.director.held = true;
    switch (cam) {
      case 'nest':
        game.followOverride = hole.nest.position;
        rig.glideTo(distance: 10, pitchDeg: 32);
      case 'host':
        // Where he stands: beyond the side rail on the nest's side, about
        // level with the green's middle.
        final right = hole.nest.position.x >= bounds.center.x;
        game.followOverride = Vec2(
            right ? bounds.max.x + 2.5 : bounds.min.x - 2.5,
            hole.nest.position.y
                .clamp(bounds.center.y - bounds.height * 0.2,
                    bounds.center.y + bounds.height * 0.05)
                .toDouble());
        rig.glideTo(distance: 16, pitchDeg: 13);
      case 'wide':
        game.followOverride = bounds.center;
        rig.glideTo(distance: rig.overviewDistance * 1.5, pitchDeg: 27);
      case 'tee':
        game.followOverride = hole.tee;
        rig.glideTo(distance: 9, pitchDeg: 30);
    }
  }

  /// My egg: the reference line, aimed by a real drag on the game.
  void _driveMe(HoleDef hole) {
    final game = _game;
    final ball = match.myBall;
    if (game == null || ball == null || ball.holed) return;
    final drag = _drag;
    if (drag != null) {
      drag.elapsed += 0.033;
      final pullIn = (drag.elapsed / 0.9).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - pullIn, 3).toDouble();
      final at = drag.from + drag.pull * eased;
      if (drag.elapsed < 2.1) {
        game.moveAim(at);
      } else {
        game.endAim(drag.from + drag.pull);
        _drag = null;
        _myShot++;
        _myNextAt = _holeTime + 1.2;
      }
      return;
    }
    if (_holeTime < _myNextAt || !match.myShotReady) return;
    // A power-up armed for the camera holds the putt (an aim would put
    // the targeting away).
    final targeting = game.targeting;
    if (targeting.armedSlot != null || targeting.pickingSlot != null) return;
    final reference = _currentHole?.solution.shots ?? const <ReferenceShot>[];
    double angle;
    double power;
    final soft = _soft;
    if (soft != null && _myShot == 0) {
      final toNest = hole.nest.position - ball.position;
      angle = math.atan2(toNest.y, toNest.x);
      power = soft;
    } else if (_myShot < reference.length) {
      final shot = reference[_myShot];
      // Exactly the validated line: the engine fires what it is sent.
      angle = shot.angle;
      power = shot.power;
    } else {
      // Off the script: a hop with the Rabbit Hole when the nest is near,
      // else a plain putt at it.
      final toNest = hole.nest.position - ball.position;
      if (toNest.length < 6) {
        _rabbitHop('me', hole.nest.position);
        _myNextAt = _holeTime + 1.5;
        return;
      }
      final shot = putt(ball.position, hole.nest.position, arrival: 1.2);
      angle = shot.angle;
      power = shot.power;
    }
    // The pull that gives this power, back along the shot.
    final length =
        game.aim.maxDragLength * math.pow(power, 1 / game.aim.powerExponent);
    final pull = Vec2(-math.cos(angle), -math.sin(angle)) * length.toDouble();
    game.beginAim(ball.position);
    _drag = _DemoDrag(from: ball.position, pull: pull);
  }

  /// The intended route: the reference solution replayed headless, its
  /// resting spots between the tee and the nest.
  List<Vec2> _routeOf(HoleDef hole) {
    final reference = _currentHole?.solution;
    final points = <Vec2>[hole.tee];
    if (reference != null) {
      final world = PhysicsWorld(
          hole: hole, config: match.config.physics, playerIds: const ['route']);
      final ball = world.ball('route')!;
      for (final shot in reference.shots) {
        for (var i = 0;
            i < (shot.waitSeconds / match.config.physics.dt).round();
            i++) {
          world.stepTick();
        }
        world.applyShot('route', shot.angle, shot.power);
        var guard = 0;
        while (!ball.holed && !ball.asleep && guard++ < 6000) {
          world.stepTick();
        }
        if (ball.holed) break;
        points.add(ball.position);
      }
    }
    points.add(hole.nest.position);
    return points;
  }

  /// Whether an egg can roll the straight line [a]-[b] without meeting a
  /// wall of [hole]: the centre line and both of the egg's edges clear. A
  /// ledge stops the line only from below; from above, it rolls off.
  bool _clearLine(HoleDef hole, Vec2 a, Vec2 b) {
    final along = (b - a).normalized(const Vec2(1, 0));
    final side = Vec2(-along.y, along.x) * 0.5;
    final lanes = [(a, b), (a + side, b + side), (a - side, b - side)];
    final walls = <(Vec2, Vec2)>[
      for (final wall in hole.walls)
        if (!wall.ledge || (a - wall.a).dot(wall.highSide) <= 0)
          (wall.a, wall.b),
      // Arcs as their chords.
      for (final arc in hole.arcs)
        for (var i = 0; i < 16; i++)
          (
            Vec2(
                arc.center.x +
                    math.cos(arc.startAngle + i / 16 * arc.sweep) * arc.radius,
                arc.center.y +
                    math.sin(arc.startAngle + i / 16 * arc.sweep) * arc.radius),
            Vec2(
                arc.center.x +
                    math.cos(arc.startAngle + (i + 1) / 16 * arc.sweep) *
                        arc.radius,
                arc.center.y +
                    math.sin(arc.startAngle + (i + 1) / 16 * arc.sweep) *
                        arc.radius),
          ),
    ];
    for (final (p, q) in walls) {
      for (final (from, to) in lanes) {
        if (_crosses(from, to, p, q)) return false;
      }
    }
    return true;
  }

  /// Whether segments [a]-[b] and [p]-[q] properly cross.
  bool _crosses(Vec2 a, Vec2 b, Vec2 p, Vec2 q) {
    double cross(Vec2 o, Vec2 u, Vec2 v) =>
        (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x);
    final d1 = cross(p, q, a);
    final d2 = cross(p, q, b);
    final d3 = cross(a, b, p);
    final d4 = cross(a, b, q);
    return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
  }

  /// The furthest point of the route a bot at [from] can putt to in a
  /// straight line (the nest when it can see it), or the nearest route
  /// point ahead when none is clear.
  Vec2 _nextTarget(HoleDef hole, Vec2 from) {
    for (var i = _route.length - 1; i >= 1; i--) {
      if (_clearLine(hole, from, _route[i])) return _route[i];
    }
    var best = _route.length > 1 ? _route[1] : hole.nest.position;
    var bestDistance = double.infinity;
    for (final point in _route.skip(1)) {
      final d = from.distanceTo(point);
      if (d < bestDistance) {
        bestDistance = d;
        best = point;
      }
    }
    return best;
  }

  /// Eggs already seen in the nest this hole, and the crew's reactions
  /// waiting for their moment (hole time, who, which).
  final Set<String> _holedSeen = {};
  final List<(double, String, String)> _reactionsDue = [];
  bool _splashLaughed = false;

  /// The crew reacts the way friends on a call do: the scorer cheers (fire
  /// for a hole in one), someone says nice one, and my sinks get a wow; a
  /// splash gets a laugh.
  void _driveReactions() {
    final world = match.engine.world;
    if (world == null) return;
    final crew = [
      for (final ball in world.balls)
        if (ball.playerId != match.localPlayerId) ball.playerId,
    ];
    if (crew.isEmpty) return;
    for (final ball in world.balls) {
      if (!ball.holed || !_holedSeen.add(ball.playerId)) continue;
      final strokes = match.engine.strokesInHole(ball.playerId);
      final others = [
        for (final id in crew)
          if (id != ball.playerId) id,
      ];
      if (ball.playerId == match.localPlayerId) {
        _reactionsDue.add((_holeTime + 0.5, crew.first, 'wow'));
        if (crew.length > 1) {
          _reactionsDue
              .add((_holeTime + 1.1, crew[1], strokes == 1 ? 'fire' : 'gg'));
        }
      } else {
        _reactionsDue.add(
            (_holeTime + 0.3, ball.playerId, strokes == 1 ? 'fire' : 'cheer'));
        if (others.isNotEmpty) {
          _reactionsDue.add((_holeTime + 0.9, others.first, 'gg'));
        }
      }
    }
    if (_splashed && !_splashLaughed && crew.length > 1) {
      _splashLaughed = true;
      _reactionsDue.add((_holeTime + 0.7, crew[1], 'laugh'));
    }
    _reactionsDue.removeWhere((due) {
      if (_holeTime < due.$1) return false;
      match.engine.react(due.$2, due.$3);
      return true;
    });
  }

  /// The crew: putts along the hole's route (the furthest point of it in
  /// a clear line) with a jitter that tightens stroke by stroke, and a
  /// Rabbit Hole hop when one stalls near the nest.
  void _driveBots(HoleDef hole) {
    final world = match.engine.world;
    if (world == null) return;
    var order = 0;
    for (final ball in world.balls) {
      if (ball.playerId == match.localPlayerId) continue;
      order++;
      if (ball.holed || !ball.asleep) continue;
      final nextAt = _botNextAt[ball.playerId] ?? (3.6 + order * 0.55);
      if (_holeTime < nextAt) continue;
      final shots = _botShots[ball.playerId] ?? 0;
      final toNest = hole.nest.position - ball.position;
      final pond = _splash && !_splashed && order == 1
          ? _nearestWater(hole, ball.position)
          : null;
      if (pond != null) {
        // Staged: straight into the pond, with pace.
        _splashed = true;
        final shot = putt(ball.position, pond, arrival: 4.5);
        match.engine.submitShot(ball.playerId, shot.angle, shot.power);
      } else if (shots >= 3 && toNest.length < 6) {
        _rabbitHop(ball.playerId, hole.nest.position);
      } else {
        final target = _nextTarget(hole, ball.position);
        final last = target == hole.nest.position;
        final shot = putt(ball.position, target, arrival: last ? 1.4 : 0.7);
        final spread = 0.16 / (shots + 1);
        final angle = shot.angle + (_random.nextDouble() * 2 - 1) * spread;
        // Hills, ramps, drops and silos bend and stop a roll the flat math
        // cannot see: there the bot reads the green by running the engine
        // ahead.
        final reads = hole.hasRelief || hole.wells.isNotEmpty;
        final base = reads
            ? _readPower(hole, ball.playerId, angle, target, shot.power)
            : shot.power;
        final power = (base * (0.93 + _random.nextDouble() * 0.14))
            .clamp(0.05, 1.0)
            .toDouble();
        match.engine.submitShot(ball.playerId, angle, power);
      }
      _botShots[ball.playerId] = shots + 1;
      _botNextAt[ball.playerId] = _holeTime + 2.2 + order * 0.4;
    }
  }

  /// The middle of the pond nearest [from], or null on a dry hole.
  static Vec2? _nearestWater(HoleDef hole, Vec2 from) {
    Vec2? best;
    var bestDistance = double.infinity;
    for (final shape in hole.water) {
      final Vec2 middle = switch (shape) {
        WaterCircle() => shape.center,
        WaterRect() => shape.rect.center,
        WaterPolygon() =>
          shape.points.reduce((a, b) => a + b) * (1 / shape.points.length),
      };
      final d = middle.distanceTo(from);
      if (d < bestDistance) {
        best = middle;
        bestDistance = d;
      }
    }
    return best;
  }

  /// The power that leaves [playerId]'s egg nearest [target] along
  /// [angle] on this hole's ground: the engine run ahead on a copy of the
  /// world, a coarse sweep of powers then a finer one round the best.
  double _readPower(
      HoleDef hole, String playerId, double angle, Vec2 target, double guess) {
    final world = match.engine.world;
    final start = world?.ball(playerId)?.position;
    if (world == null || start == null) return guess;
    final state = world.toJson();
    final heading = Vec2(math.cos(angle), math.sin(angle));
    final wanted = (target - start).dot(heading);
    if (wanted <= 0.1) return guess;
    // One roll on a copy of the world: where it stops, how far along the
    // shot's line that is, and whether it dropped in.
    (Vec2, double, bool) roll(double power) {
      final copy = PhysicsWorld.restore(
          hole: hole, config: match.config.physics, state: state);
      final ball = copy.ball(playerId)!;
      copy.applyShot(playerId, angle, power);
      for (var i = 0; i < 1200 && !ball.holed && !ball.asleep; i++) {
        copy.stepTick();
      }
      return (ball.position, (ball.position - start).dot(heading), ball.holed);
    }

    // A few rolls, each power scaled by how far short or long the last one
    // stopped (on flat ground the distance grows with the power squared),
    // instead of a sweep: the main thread must not stall on a bot's putt.
    var power = guess.clamp(0.05, 1.0).toDouble();
    var best = power;
    var bestMiss = double.infinity;
    for (var i = 0; i < 4; i++) {
      final (rest, reached, holed) = roll(power);
      if (holed) return power;
      final miss = rest.distanceTo(target);
      if (miss < bestMiss) {
        best = power;
        bestMiss = miss;
      }
      final next = reached <= 0.2
          // Rolled back (a ramp, a ridge) or stopped at once: more pace.
          ? math.min(1.0, power * 1.6)
          : (power * math.sqrt(wanted / reached)).clamp(0.05, 1.0).toDouble();
      if ((next - power).abs() < 0.004) break;
      power = next;
    }
    return best;
  }

  /// A Rabbit Hole hop toward [target] (the demo hands the power-up over
  /// first; a real player earns it at a crate).
  void _rabbitHop(String playerId, Vec2 target) {
    final player = match.engine.player(playerId);
    if (player == null) return;
    player.inventory.add('rabbit_hole');
    if (playerId == match.localPlayerId) {
      match.usePowerUp('rabbit_hole', PowerUpTarget.point(target));
    } else {
      match.engine
          .usePowerUp(playerId, 'rabbit_hole', PowerUpTarget.point(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: const Color(0xFF211614),
        child: SunnySidePuttView(
          match: match,
          onGame: (game) => _game = game,
        ),
      ),
    );
  }
}

/// A scripted drag in flight: where it began and the full pull.
class _DemoDrag {
  final Vec2 from;
  final Vec2 pull;
  double elapsed = 0;

  _DemoDrag({required this.from, required this.pull});
}
