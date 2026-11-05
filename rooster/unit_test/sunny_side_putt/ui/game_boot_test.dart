// The game view boots on the stub hole without network, plays a stroke
// through the real pipeline, interpolates, and quiets when a menu stands
// over it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:flame/game.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';

void main() {
  testWidgets('the view boots a solo stub match and the egg is on the tee',
      (tester) async {
    final match = PuttMatch.solo(localPlayerName: 'Tester');
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 120));

    expect(match.phase, PuttPhase.holePlay);
    expect(match.myBall, isNotNull);
    expect(match.myBall!.asleep, isTrue);
    // The engine laid the egg on the stub hole's tee.
    expect(match.myBall!.position.distanceTo(match.hole!.tee), lessThan(0.001));
  });

  testWidgets('a stroke rolls the egg through the fixed-step harness',
      (tester) async {
    final match = PuttMatch.solo(localPlayerName: 'Tester');
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 120));
    final before = Vec2(match.myBall!.position.x, match.myBall!.position.y);

    // The seam the aim layer calls on release.
    expect(match.submitShot(0, 0.7), isTrue);
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
    }
    final after = match.myBall!.position;
    expect(after.distanceTo(before), greaterThan(0.5));
    // And the stroke landed in the HUD's numbers.
    expect(match.myStrokesThisHole, 1);
  });

  testWidgets('a paused match does not tick', (tester) async {
    final match = PuttMatch.solo();
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 50));
    match.paused = true;
    final before = match.secondsRemaining;
    await tester.pump(const Duration(seconds: 1));
    expect(match.secondsRemaining, before,
        reason: 'the pause menu freezes the hole clock');
  });

  testWidgets('the pause button opens the pause menu and resumes',
      (tester) async {
    final match = PuttMatch.solo();
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('putt-pause')));
    await tester.pump();
    expect(match.paused, isTrue,
        reason: 'opening the pause menu freezes the match');
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.byKey(const Key('putt-menu-resume')));
    await tester.pump();
    expect(match.paused, isFalse);
    expect(find.text('Paused'), findsNothing);
  });

  testWidgets('Esc pauses', (tester) async {
    final match = PuttMatch.solo();
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(match.paused, isTrue);
  });

  testWidgets('nine on the tee: the ninth watches from the fence',
      (tester) async {
    final course = CourseDef(id: 'full', holes: [stubHole(id: 'f0')]);
    final match = PuttMatch(
      config: PuttConfig(mode: GameMode.casual, courses: [course], seed: 21),
      localPlayerId: 'me',
      seatedPlayerIds: [for (var i = 0; i < 8; i++) 'p$i'],
    )..boot();
    await tester.pumpWidget(MaterialApp(home: SunnySidePuttView(match: match)));
    await tester.pump(const Duration(milliseconds: 80));
    expect(match.isSpectator, isTrue);
    expect(find.text("You're watching from the fence"), findsOneWidget);
  });

  testWidgets('the aim: a press away from the egg anchors the pull there',
      (tester) async {
    final match = PuttMatch.solo();
    final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 50));

    // Pressed far from the egg: the aim begins at the egg, with no pull
    // yet - the drag is measured from where the press landed.
    final far = match.hole!.nest.position;
    game.beginAim(far);
    expect(game.aim.isActive, isTrue);
    expect(game.aim.origin, match.myBall!.position);
    expect(game.aim.dragLength, closeTo(0, 1e-9));
    // Released where it pressed: a tap, no stroke.
    game.endAim(far);
    expect(match.myStrokesThisHole, 0);

    // Pressed far again and dragged 3 units west: the shot fires east.
    game.beginAim(far);
    game.moveAim(far - const Vec2(3, 0));
    expect(game.aim.state!.angle, closeTo(0, 1e-9));
    expect(game.aim.dragLength, closeTo(3, 1e-9));
    game.endAim(far - const Vec2(3, 0));
    expect(match.myStrokesThisHole, 1);
  });

  testWidgets('the aim: starts near my settled egg, submits on release',
      (tester) async {
    final match = PuttMatch.solo();
    final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.aim.isActive, isFalse);

    // Near it, pulled 3 units west of the egg: the shot fires east on
    // release.
    final egg = match.myBall!.position;
    game.beginAim(egg);
    game.moveAim(egg - const Vec2(3, 0));
    expect(game.aim.isActive, isTrue);
    game.update(1 / 60); // one frame; the arrow's clock runs
    expect(game.aimLayer.holdSeconds, greaterThan(0));

    game.endAim(egg - const Vec2(3, 0));
    expect(game.aim.isActive, isFalse);
    expect(match.myStrokesThisHole, 1);
    expect(match.myBall!.asleep, isFalse, reason: 'the egg is rolling');
  });

  testWidgets('a tap on the egg cancels, no stroke spent', (tester) async {
    final match = PuttMatch.solo();
    final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 50));

    final egg = match.myBall!.position;
    game.beginAim(egg);
    game.moveAim(egg); // no pull at all
    game.endAim(egg);
    expect(match.myStrokesThisHole, 0);
  });
}
