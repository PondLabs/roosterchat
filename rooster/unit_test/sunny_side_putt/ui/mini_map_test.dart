// The hole from above while the viewer aims with the nest out of sight:
// turned with the camera (ahead is up), fitted to its corner, and only
// while aiming.
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart'
    show Vec2;
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_mini_map.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

void main() {
  const size = Size(176, 132);

  test('ahead on the screen is up on the map, right is right', () {
    // The camera on the green's south side, looking north (-y).
    const north = Vec2(0, -1);
    final centre = PuttMiniMapPainter.place(
        const Vec2(10, 10), const Vec2(10, 10), north, 2, size);
    expect(centre, const Offset(88, 66));
    final east = PuttMiniMapPainter.place(
        const Vec2(14, 10), const Vec2(10, 10), north, 2, size);
    expect(east, const Offset(96, 66));
    final ahead = PuttMiniMapPainter.place(
        const Vec2(10, 6), const Vec2(10, 10), north, 2, size);
    expect(ahead, const Offset(88, 58));
    // Looking east instead: east is up.
    final turned = PuttMiniMapPainter.place(
        const Vec2(14, 10), const Vec2(10, 10), const Vec2(1, 0), 2, size);
    expect(turned.dx, closeTo(88, 1e-9));
    expect(turned.dy, closeTo(58, 1e-9));
  });

  testWidgets('the map draws while it has a frame, and not without one',
      (tester) async {
    final match = PuttMatch.solo();
    final frame = ValueNotifier<PuttMiniMapFrame?>(null);
    addTearDown(frame.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [PuttMiniMap(frame: frame)]),
    ));
    expect(find.byKey(const Key('putt-mini-map')), findsNothing);
    frame.value = PuttMiniMapFrame(
      hole: match.hole!,
      forward: const Vec2(0, -1),
      mine: match.myBall!.position,
      tint: Colors.amber,
      others: const [],
      aimAngle: 0,
      aimPower: 0.5,
    );
    await tester.pump();
    expect(find.byKey(const Key('putt-mini-map')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('putt-mini-map'))),
        puttMiniMapRect);
  });

  testWidgets('only while aiming with the nest out of sight', (tester) async {
    final match = PuttMatch.solo();
    final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.miniMapForFrame(nestOutOfSight: true), isNull,
        reason: 'not aiming');
    final egg = match.myBall!.position;
    game.beginAim(egg);
    game.moveAim(egg - const Vec2(3, 0));
    expect(game.miniMapForFrame(nestOutOfSight: false), isNull,
        reason: 'the nest is on the screen');
    final map = game.miniMapForFrame(nestOutOfSight: true)!;
    expect(map.mine, match.myBall!.position);
    expect(map.forward.length, closeTo(1, 1e-9));
    expect(game.hudOverGreen(), contains(puttMiniMapRect),
        reason: 'name tags keep out from under it');
  });
}
