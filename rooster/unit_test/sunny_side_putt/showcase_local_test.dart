// SHOWCASE (local only, NOT committed): drives the real game and captures
// PNG frames of a match — the tee, the aim with its arrow, the roll, the
// nest trick, the hole end — for the user to see the game's look. Run:
//   cd rooster && /home/gabriel/flutter/bin/flutter test \
//     unit_test/sunny_side_putt/showcase_local_test.dart
// Frames land in /home/gabriel/putt-showcase/.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

const _out = '/home/gabriel/putt-showcase';
final _captureKey = GlobalKey();

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    final image = await boundary.toImage(pixelRatio: 1.4);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _harness(Widget child) => RepaintBoundary(
      key: _captureKey,
      child: SizedBox(
        width: 1024,
        height: 640,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFFF89B17)),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  testWidgets('the board with its HUD: tee, roll, trick, hole end',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 640));
    final match = PuttMatch.solo(localPlayerName: 'Gabriel');
    await tester.pumpWidget(_harness(SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 250));
    await _shoot(tester, '01-the-egg-on-the-tee');

    // A good whack across the green; the boards roll on their own.
    match.submitShot(0.6, 0.7);
    var kept = 1;
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 30));
      final asleep = match.myBall?.asleep ?? true;
      if (!asleep && kept <= 36) {
        await _shoot(tester, 'roll-${kept.toString().padLeft(3, '0')}');
        kept++;
      }
      if (asleep && i > 5) break;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await _shoot(tester, '04-the-egg-settled');

    // The Rabbit Hole power-up: straight to the nest, the party trick.
    match.usePowerUp(
        'rabbit_hole', PowerUpTarget.point(match.hole!.nest.position));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      if (match.myBall?.holed ?? false) break;
    }
    await tester.pump(const Duration(milliseconds: 250));
    await _shoot(tester, '05-in-the-nest');

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (match.phase != PuttPhase.holePlay) break;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await _shoot(tester, '06-hole-end');
  });

  testWidgets('the aim up close: the arrow swaying over the egg',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 640));
    final match = PuttMatch.solo(localPlayerName: 'Gabriel');
    final game = SunnySidePuttGame(match: match, onSfx: (_) {});
    await tester.pumpWidget(_harness(GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 250));

    final egg = match.myBall!.position;
    game.beginAim(egg);
    game.moveAim(egg - const Vec2(4, 2));
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
      await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
      if (i == 15) {
        // Near the sway's other end: the arrow shows its wobble.
        game.moveAim(egg - const Vec2(5, 1));
      }
      if (i == 22) await _shoot(tester, '02-aiming-the-putt');
    }
    game.endAim(egg - const Vec2(4.5, 1.6));

    var kept = 1;
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 30));
      final asleep = match.myBall?.asleep ?? true;
      if (!asleep && kept <= 48) {
        await _shoot(tester, 'aim-roll-${kept.toString().padLeft(3, '0')}');
        kept++;
      }
      if (asleep && i > 5) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, '08-aim-shot-settled');
  });
}
