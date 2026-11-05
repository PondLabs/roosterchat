// The stage shell: the placeholder where the game's view goes, the way in
// and out (button and Esc), and the fullscreen toggle existing on desktop.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/call_activity/activity_stage.dart';

void main() {
  group('ActivityStage', () {
    testWidgets('shows the placeholder while the game has no view',
        (tester) async {
      await tester.pumpWidget(_stage());

      expect(find.text('Loading Sunny Side Putt'), findsOneWidget);
    });

    testWidgets('hosts the game slot once it is plugged in', (tester) async {
      await tester.pumpWidget(_stage(gameSlot: const Text('THE GAME')));

      expect(find.text('THE GAME'), findsOneWidget);
      expect(find.text('Loading Sunny Side Putt'), findsNothing);
    });

    testWidgets('the exit button releases the stage', (tester) async {
      var exited = false;
      await tester.pumpWidget(_stage(onExit: () => exited = true));

      await tester.tap(find.byTooltip(ActivityStageStrings.leave));
      await tester.pump();

      expect(exited, isTrue);
    });

    testWidgets('Esc releases the stage', (tester) async {
      var exited = false;
      await tester.pumpWidget(_stage(onExit: () => exited = true));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(exited, isTrue);
    });

    testWidgets(
        'the fullscreen toggle is there on desktop and does not '
        'throw where no window service answers', (tester) async {
      await tester.pumpWidget(_stage());

      // On the test host there is no window manager; entering fails inside
      // and is swallowed: the stage stays put rather than throwing.
      if (ActivityStage.hasFullscreen) {
        await tester.tap(find.byTooltip(ActivityStageStrings.toggleFullscreen));
        await tester.pump();
      }
      expect(find.text('Loading Sunny Side Putt'), findsOneWidget);
    });
  });
}

Widget _stage({Widget? gameSlot, VoidCallback? onExit}) => MaterialApp(
      home: Scaffold(
        body: ActivityStage(
          activityName: 'Sunny Side Putt',
          gameSlot: gameSlot,
          participantsStrip: const SizedBox(height: 60, width: 200),
          onExit: onExit ?? () {},
        ),
      ),
    );
