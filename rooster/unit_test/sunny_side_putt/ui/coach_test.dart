// The aim coach: shown over the egg while the game hands it a cue,
// gone when the cue goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rooster/ui/organisms/sunny_side_putt/putt_coach.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_name_tags.dart';

void main() {
  testWidgets('the coach shows its gesture while it has a cue', (tester) async {
    final cue = ValueNotifier<PuttCoachCue?>(null);
    addTearDown(cue.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [PuttCoach(cue: cue)]),
    ));
    expect(find.text(labelPuttCoachPull()), findsNothing);
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);

    cue.value = const PuttCoachCue(egg: Offset(300, 240), toward: Offset(1, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text(labelPuttCoachPull()), findsOneWidget);
    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);

    cue.value = null;
    await tester.pump();
    expect(find.text(labelPuttCoachPull()), findsNothing);
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
}
