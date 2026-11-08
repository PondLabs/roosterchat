// The aim coach: shown over the egg while the game hands it a cue,
// gone when the cue goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rooster/ui/organisms/sunny_side_putt/putt_coach.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_name_tags.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_reactions.dart';

void main() {
  testWidgets('the coach shows its gesture while it has a cue', (tester) async {
    final cue = ValueNotifier<PuttCoachCue?>(null);
    addTearDown(cue.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [PuttCoach(cue: cue)]),
    ));
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);

    cue.value = const PuttCoachCue(egg: Offset(300, 240), toward: Offset(1, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);

    cue.value = null;
    await tester.pump();
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
  });

  test('name tags bunched on the tee lift clear of each other', () {
    const tags = [
      PuttTag(
          playerId: 'a',
          name: 'Maya',
          color: Colors.teal,
          at: Offset(300, 300)),
      PuttTag(
          playerId: 'b',
          name: 'Jonas',
          color: Colors.blue,
          at: Offset(310, 306)),
      PuttTag(
          playerId: 'c', name: 'Lou', color: Colors.pink, at: Offset(600, 300)),
    ];
    final placed = declutterTags(tags);
    final a = placed.firstWhere((t) => t.playerId == 'a');
    final b = placed.firstWhere((t) => t.playerId == 'b');
    // The lower one keeps its place; the other steps clear of it, to a side
    // or above, and stays near its egg.
    expect(b.at, const Offset(310, 306));
    expect(puttTagPill(a, a.at).overlaps(puttTagPill(b, b.at)), isFalse);
    expect((a.at - const Offset(300, 300)).distance, lessThan(80));
    // A tag clear of the others stays put.
    expect(
        placed.firstWhere((t) => t.playerId == 'c').at, const Offset(600, 300));
  });

  test('tags rise clear of my own egg', () {
    const tags = [
      PuttTag(
          playerId: 'a',
          name: 'Maya',
          color: Colors.teal,
          at: Offset(300, 300)),
    ];
    const mine = Rect.fromLTRB(280, 270, 320, 310);
    final placed = declutterTags(tags, avoid: [mine]);
    final tag = placed.single;
    // The pill keeps clear of my egg's box.
    expect(puttTagPill(tag, tag.at).overlaps(mine), isFalse);
  });

  test('a tag steps beside my egg rather than over it, pointing back', () {
    // Maya's egg stands just in front of mine (lower on the screen): her
    // tag's own spot is on my egg and its pin.
    const mine = Rect.fromLTRB(630, 230, 710, 420);
    const maya = PuttTag(
        playerId: 'a', name: 'Maya', color: Colors.teal, at: Offset(670, 440));
    final tag = declutterTags(const [maya], avoid: [mine]).single;
    final pill = puttTagPill(tag, tag.at);
    expect(pill.overlaps(mine), isFalse);
    expect(pill.bottom, 440, reason: 'beside, at her height: not over mine');
    // The pointer leans back toward her egg.
    expect(
        (tag.at.dx + tag.tail - 670).abs(), lessThan((tag.at.dx - 670).abs()));

    // No room beside either: not drawn, rather than over my egg.
    const wide = Rect.fromLTRB(540, 230, 800, 420);
    expect(declutterTags(const [maya], avoid: [wide]), isEmpty);
  });

  test('a tag that would stand under the HUD is not drawn', () {
    final board = PuttTagBoard();
    addTearDown(board.dispose);
    const strip = Rect.fromLTRB(474, 0, 806, 98);
    board.update(const [
      PuttTag(
          playerId: 'up',
          name: 'Jonas',
          color: Colors.blue,
          at: Offset(640, 90)),
      PuttTag(
          playerId: 'down',
          name: 'Lou',
          color: Colors.pink,
          at: Offset(640, 300)),
      PuttTag(
          playerId: 'beside',
          name: 'Maya',
          color: Colors.teal,
          at: Offset(300, 60)),
    ], hud: [
      strip
    ]);
    expect(board.tags.map((t) => t.playerId), ['down', 'beside'],
        reason: 'under the strip: gone; below it or beside it: drawn');
  });

  test('a tag stays within one and a half egg widths, else goes to its chip',
      () {
    // Lou's spot is taken by another egg's box; the nearest clear spot for
    // her full tag is far off to the side, past what her egg's width allows.
    const lou = PuttTag(
        playerId: 'lou',
        name: 'Lou',
        color: Colors.pink,
        at: Offset(400, 300),
        eggWidth: 30);
    const blocked = Rect.fromLTRB(345, 250, 455, 305);
    final placed = declutterTags(const [lou], soft: [blocked]).single;
    expect((placed.at.dx - 400).abs(), lessThanOrEqualTo(45),
        reason: 'by her egg');
    expect(placed.compact || placed.dim, isTrue,
        reason: 'a chip, or faded where it stands, not a name far off');
  });

  test("tags keep inside the screen's margin, and go with their egg", () {
    final board = PuttTagBoard();
    addTearDown(board.dispose);
    const screen = Rect.fromLTRB(12, 12, 1268, 788);
    board.update(const [
      // Its egg 20 px from the left edge: the pill would run past it.
      PuttTag(
          playerId: 'edge',
          name: 'Maya',
          color: Colors.teal,
          at: Offset(20, 400)),
      // Its egg off the screen to the right.
      PuttTag(
          playerId: 'off',
          name: 'Lou',
          color: Colors.pink,
          at: Offset(1320, 400)),
    ], screen: screen);
    expect(board.tags.map((t) => t.playerId), ['edge']);
    final tag = board.tags.single;
    final pill = puttTagPill(tag, tag.at);
    expect(pill.left, greaterThanOrEqualTo(screen.left - 1e-9));
    expect(tag.at.dx + tag.tail, closeTo(20, 12),
        reason: 'its pointer leans back to the egg');
  });

  test("tags keep clear of the coach's hand and its row", () {
    // My egg at (400, 400), the nest up the screen: the hand pulls down
    // from under the egg, the row of chevrons grows up toward the nest.
    const cue = PuttCoachCue(egg: Offset(400, 400), toward: Offset(0, -1));
    final obstacles = puttCoachObstacles(cue);
    const handAt = Offset(410, 480); // on the hand's path
    expect(obstacles.any((rect) => rect.contains(handAt)), isTrue);
    expect(
        obstacles.any((rect) => rect.contains(const Offset(400, 300))), isTrue,
        reason: 'the row of chevrons');
    const tags = [
      PuttTag(
          playerId: 'a',
          name: 'Jonas',
          color: Colors.blue,
          at: Offset(410, 500)),
    ];
    final placed = declutterTags(tags, soft: obstacles).single;
    final pill = puttTagPill(placed, placed.at);
    expect(obstacles.any((rect) => rect.overlaps(pill)), isFalse);
  });

  test("with no room clear of the coach, a tag stands by its egg anyway", () {
    // Maya's egg just in front of mine on the tee, the coach's hand and
    // row (with their margins) round her tag's spot.
    const mine = Rect.fromLTRB(560, 230, 780, 405);
    const hand = Rect.fromLTRB(495, 339, 655, 423);
    const arrow = Rect.fromLTRB(600, 372, 820, 441);
    const maya = PuttTag(
        playerId: 'a', name: 'Maya', color: Colors.teal, at: Offset(670, 450));
    final placed =
        declutterTags(const [maya], avoid: [mine], soft: [hand, arrow]);
    expect(placed, hasLength(1), reason: 'drawn, not dropped');
    expect(placed.single.at, const Offset(670, 450),
        reason: 'by her egg, not up over mine');
    expect(placed.single.compact, isFalse, reason: 'her name shows');
    expect(placed.single.dim, isTrue, reason: 'faded under the coach');
  });

  testWidgets('the reaction picker opens and sends one, then folds',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: PuttReactionPicker(onReact: sent.add),
        ),
      ),
    ));
    expect(find.byKey(const Key('putt-react-fire')), findsNothing);
    await tester.tap(find.byKey(const Key('putt-react')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('putt-react-fire')));
    await tester.pumpAndSettle();
    expect(sent, ['fire']);
    expect(find.byKey(const Key('putt-react-fire')), findsNothing);
  });

  testWidgets('a bubble pops over its spot', (tester) async {
    final board = PuttBubbleBoard();
    addTearDown(board.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [PuttBubbles(board: board)]),
    ));
    board.update(const [
      PuttBubble(
          key: 'a', reaction: 'cheer', at: Offset(200, 200), progress: 0.3),
    ]);
    await tester.pump();
    expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
  });
}
