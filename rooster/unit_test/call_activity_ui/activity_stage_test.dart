// The stage shell: the placeholder where the game's view goes, the way in
// and out (Esc, and the button until the game's own menu takes over), and
// fullscreen: the game edge to edge, the stage's chrome gone, the game's own
// menu still there over it.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/call_activity/activity_stage.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

void main() {
  group('ActivityStage', () {
    tearDown(() => ActivityStage.debugSetFullscreen = null);

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

    testWidgets('no exit button over a game: its own menu has the leave',
        (tester) async {
      await tester.pumpWidget(_stage(gameSlot: const Text('THE GAME')));

      expect(find.byTooltip(ActivityStageStrings.leave), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('while loading, the exit button releases the stage',
        (tester) async {
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

    testWidgets('fullscreen fills the stage with the game, chrome gone',
        (tester) async {
      var fullscreen = false;
      ActivityStage.debugSetFullscreen = (on) async {
        final was = fullscreen;
        fullscreen = on;
        return was;
      };
      await tester.pumpWidget(_stage(gameSlot: const Text('THE GAME')));
      final before = tester.getSize(find.text('THE GAME'));

      await tester.tap(find.byTooltip(ActivityStageStrings.toggleFullscreen));
      await tester.pumpAndSettle();

      expect(fullscreen, isTrue);
      // The header and the call's videos are gone: the game has the stage.
      expect(find.text('Sunny Side Putt'), findsNothing);
      expect(
          find.byTooltip(ActivityStageStrings.toggleFullscreen), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
      final after = tester.getSize(find.text('THE GAME'));
      expect(after.height, greaterThan(before.height),
          reason: 'the game grew into the header and the strip');
      expect(after.width, greaterThan(before.width),
          reason: 'and into the stage padding');
      // The game itself is still mounted and interactive: its own menu is
      // the way to the Rooster options over the fullscreen game.
      expect(find.text('THE GAME'), findsOneWidget);
      expect(
          find.byTooltip(ActivityStageStrings.exitFullscreen), findsOneWidget);
    });

    testWidgets('the way out of fullscreen floats, then rests out of the way',
        (tester) async {
      var fullscreen = false;
      ActivityStage.debugSetFullscreen = (on) async {
        final was = fullscreen;
        fullscreen = on;
        return was;
      };
      await tester.pumpWidget(_stage(gameSlot: const Text('THE GAME')));
      await tester.tap(find.byTooltip(ActivityStageStrings.toggleFullscreen));
      await tester.pumpAndSettle();
      expect(
          find.byTooltip(ActivityStageStrings.exitFullscreen), findsOneWidget);

      // The pointer rests: the button fades out of the game's way.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final faded = tester.widget<AnimatedOpacity>(find.ancestor(
          of: find.byTooltip(ActivityStageStrings.exitFullscreen),
          matching: find.byType(AnimatedOpacity)));
      expect(faded.opacity, 0);

      // A move brings it back, and it leaves fullscreen.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(ActivityStageStrings.exitFullscreen));
      await tester.pumpAndSettle();
      expect(fullscreen, isFalse);
      expect(find.text('Sunny Side Putt'), findsOneWidget,
          reason: 'the call is back around the game');
    });

    testWidgets("the game's own menu opens over the fullscreen game",
        (tester) async {
      var fullscreen = false;
      ActivityStage.debugSetFullscreen = (on) async {
        final was = fullscreen;
        fullscreen = on;
        return was;
      };
      final match = PuttMatch.solo();
      await tester
          .pumpWidget(_stage(gameSlot: SunnySidePuttView(match: match)));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.byTooltip(ActivityStageStrings.toggleFullscreen));
      // The game's own ticker never settles: a few frames, not a settle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      // The Rooster options stay reachable over the fullscreen game: the
      // gear is the game's own, and its menu comes up over it.
      await tester.tap(find.byKey(const Key('putt-settings')));
      await tester.pump();
      expect(find.text('Game settings'), findsOneWidget);
      expect(match.paused, isTrue);
    });

    testWidgets('Esc leaves fullscreen before it leaves the stage',
        (tester) async {
      var fullscreen = false;
      var exited = false;
      ActivityStage.debugSetFullscreen = (on) async {
        final was = fullscreen;
        fullscreen = on;
        return was;
      };
      await tester.pumpWidget(_stage(
          gameSlot: const Text('THE GAME'), onExit: () => exited = true));
      await tester.tap(find.byTooltip(ActivityStageStrings.toggleFullscreen));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fullscreen, isFalse);
      expect(exited, isFalse, reason: 'the stage is still up');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(exited, isTrue);
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
