// The menus: the pause card's buttons, the settings sheet's two volume
// sliders persisted to the local preferences, and the course vote sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/config/preferences/preference.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_audio.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_menus.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The seams the DoublePreferences read and write (the app's own
// Preferences shell is initialized in production the same way; the test
// skips the app bootstrap, whose unrelated parts other tickets are busy
// rewriting right now).
Future<void> freshPreferences() async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  Preference.preferences = await SharedPreferences.getInstance();
}

void main() {
  group('the pause menu', () {
    testWidgets('offers resume, settings and leave, with them wired',
        (tester) async {
      var resumed = false;
      var settings = false;
      var left = false;
      final match = PuttMatch.solo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttPauseMenu(
            match: match,
            onResume: () => resumed = true,
            onOpenSettings: () => settings = true,
            onLeave: () => left = true,
          ),
        ),
      ));
      expect(find.text('Paused'), findsOneWidget);
      // Over the buttons, the brand's own mark: the rooster in headphones.
      final mark =
          tester.widget<Image>(find.byKey(const Key('putt-menu-mark')));
      expect((mark.image as AssetImage).assetName,
          'assets/images/app_icon/app_icon_transparent_cropped.png');
      await tester.tap(find.byKey(const Key('putt-menu-resume')));
      await tester.tap(find.byKey(const Key('putt-menu-settings')));
      await tester.tap(find.byKey(const Key('putt-menu-leave')));
      expect(resumed, isTrue);
      expect(settings, isTrue);
      expect(left, isTrue);
    });
  });

  group('the settings sheet', () {
    setUp(() async {
      await freshPreferences();
    });

    testWidgets(
        'renders both sliders; dragging the music level persists '
        'it', (tester) async {
      final buses = PuttSilentBuses();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttSettingsSheet(buses: buses, onClose: () {}),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('putt-music-volume')), findsOneWidget);
      expect(find.byKey(const Key('putt-sfx-volume')), findsOneWidget);
      expect(find.text('Music volume'), findsOneWidget);
      expect(find.text('SFX volume'), findsOneWidget);

      // Drag the music slider to its far left (it starts at 55%).
      await tester.timedDrag(
        find.byKey(const Key('putt-music-volume')),
        const Offset(-300, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      expect(buses.musicVolume, lessThan(0.4),
          reason: 'the bus followed the drag live');
      expect(puttMusicVolume.value, lessThan(0.4),
          reason: 'and once committed at release, the preference holds it '
              'for the next game');
    });

    testWidgets('sfx level persists too, and a fresh bus reads it back',
        (tester) async {
      final buses = PuttSilentBuses();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttSettingsSheet(buses: buses, onClose: () {}),
        ),
      ));
      await tester.timedDrag(
        find.byKey(const Key('putt-sfx-volume')),
        const Offset(-200, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pump();
      final dropped = puttSfxVolume.value;
      expect(dropped, lessThan(0.8));

      // A service built later starts where the preference left it: the
      // silent buses read the same spot the audio service would.
      expect(PuttSilentBuses().sfxVolume, moreOrLessEquals(dropped));
      expect(PuttAudio().buses.sfxVolume, moreOrLessEquals(dropped));
    });

    testWidgets('Done closes the sheet', (tester) async {
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttSettingsSheet(
              buses: PuttSilentBuses(), onClose: () => closed = true),
        ),
      ));
      await tester.tap(find.byKey(const Key('putt-settings-close')));
      expect(closed, isTrue);
    });
  });

  group('the course vote sheet', () {
    testWidgets('lists courses and picks the played one', (tester) async {
      final picks = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttVoteSheet(
            options: [
              stubCourse(id: 'stubs', holeCount: 2),
              stubCourse(id: 'next-door', holeCount: 1),
            ],
            onPick: picks.add,
          ),
        ),
      ));
      expect(find.text('Choose the next course'), findsOneWidget);
      expect(find.text('stubs'), findsOneWidget);
      expect(find.text('next-door'), findsOneWidget);
      // The card's facts: 2 holes, pars 2+3.
      expect(find.text('2 holes · par 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('putt-vote-next-door')));
      expect(picks, ['next-door']);
    });

    testWidgets('the real vote flow: the match takes the picked course',
        (tester) async {
      final catalog = {
        'a': stubCourse(id: 'a', holeCount: 1),
        'b': stubCourse(id: 'b', holeCount: 1),
      };
      final match = PuttMatch(
        config: PuttConfig(
          mode: GameMode.casual,
          courses: [catalog['a']!],
          catalog: catalog,
          seed: 3,
          holeTimeLimitSeconds: 2,
        ),
      )..boot();
      for (var frame = 0; frame < 40; frame++) {
        match.update(0.3);
      }
      expect(match.advance(), isTrue);
      expect(match.phase, PuttPhase.awaitingNextCourse);

      String? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttVoteSheet(
            options: catalog.values.toList(),
            onPick: (courseId) {
              picked = courseId;
              match.startCourse(courseId);
            },
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('putt-vote-b')));
      expect(picked, 'b');
      expect(match.phase, PuttPhase.holePlay);
      expect(match.hole!.id, startsWith('b-'));
    });
  });
}
