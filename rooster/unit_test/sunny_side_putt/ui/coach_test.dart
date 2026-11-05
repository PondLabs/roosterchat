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
    final a = placed.firstWhere((t) => t.playerId == 'a').at;
    final b = placed.firstWhere((t) => t.playerId == 'b').at;
    // The lower one keeps its place; the other rises above it.
    expect(b, const Offset(310, 306));
    expect(a.dy, lessThanOrEqualTo(306 - 26));
    expect(a.dx, 300);
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
    final at = placed.single.at;
    // The pill (26 tall, ending at its anchor) sits above my egg's box.
    expect(at.dy, lessThanOrEqualTo(mine.top - 2 + 1e-9));
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
