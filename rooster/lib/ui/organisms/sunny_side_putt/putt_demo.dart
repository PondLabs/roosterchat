// The demo entry: the game plays itself, for screenshots and recordings
// (built with --dart-define=PUTT_DEMO=true, which main() branches off
// before anything the app would otherwise boot). The puts are aimed at
// the nest with a small, fixed jitter so the runs are deterministic:
// the same seed + the same script = the same frames every capture.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
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
  const PuttDemoPage();

  @override
  State<PuttDemoPage> createState() => _PuttDemoPageState();
}

class _PuttDemoPageState extends State<PuttDemoPage> {
  late final PuttMatch match;

  static const _beat = Duration(milliseconds: 2300);

  static const _jitters = [
    -0.06,
    0.09,
    -0.04,
    0.12,
    -0.02,
    0.05,
    -0.14,
    0.03,
  ];
  static const _powers = [
    0.68,
    0.74,
    0.58,
    0.71,
    0.8,
    0.63,
    0.77,
    0.66,
  ];
  int _scriptIndex = 0;

  Timer? _beatTimer;

  @override
  void initState() {
    super.initState();
    match = PuttMatch.solo();
    match.boot();
    _beatTimer = Timer.periodic(_beat, (_) => _onBeat());
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    super.dispose();
  }

  void _onBeat() {
    switch (match.phase) {
      case PuttPhase.holePlay:
        break;
      case PuttPhase.holeScoreboard:
      case PuttPhase.lobby:
        match.advance();
        return;
      case PuttPhase.awaitingNextCourse:
      case PuttPhase.matchOver:
        match.startCourse(match.config.courses.first.id);
        return;
    }

    final ball = match.myBall;
    final nest = match.hole?.nest.position;
    if (ball == null || nest == null || !ball.asleep) return;

    if (_scriptIndex % 5 == 4) {
      match.usePowerUp('rabbit_hole', PowerUpTarget.point(nest));
      _scriptIndex++;
      return;
    }

    final toNest =
        math.atan2(nest.y - ball.position.y, nest.x - ball.position.x);
    match.submitShot(toNest + _jitters[_scriptIndex % _jitters.length],
        _powers[_scriptIndex % _powers.length]);
    _scriptIndex++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: const Color(0xFF211614),
        child: Center(
          child: SunnySidePuttView(match: match),
        ),
      ),
    );
  }
}
