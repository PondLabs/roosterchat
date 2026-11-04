// The aim coach: shown over the egg while the game hands it a cue,
// gone when the cue goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rooster/ui/organisms/sunny_side_putt/putt_coach.dart';

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
}
