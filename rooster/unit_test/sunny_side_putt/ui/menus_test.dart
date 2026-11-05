// The menus: the settings card's two volume sliders persisted to the local
// preferences and its leave and done buttons, and the course vote sheet.
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
  group('the settings menu', () {
    setUp(() async {
      await freshPreferences();
    });

    Widget menu(
            {PuttBuses? buses, VoidCallback? onClose, VoidCallback? onLeave}) =>
        MaterialApp(
          home: Scaffold(
            body: PuttSettingsMenu(
              match: PuttMatch.solo(),
              buses: buses ?? PuttSilentBuses(),
              onClose: onClose ?? () {},
              onLeave: onLeave ?? () {},
            ),
          ),
        );

    testWidgets('offers the volumes, leave and done, with them wired',
        (tester) async {
      var closed = false;
      var left = false;
      await tester.pumpWidget(
          menu(onClose: () => closed = true, onLeave: () => left = true));
      expect(find.text('Game settings'), findsOneWidget);
      // Nothing pauses, so nothing says so.
      expect(find.text('Paused'), findsNothing);
      expect(find.text('Back to the green'), findsNothing);
      // Over the controls, the brand's own mark: the rooster in headphones.
      final mark =
          tester.widget<Image>(find.byKey(const Key('putt-menu-mark')));
      expect((mark.image as AssetImage).assetName,
          'assets/images/app_icon/app_icon_transparent_cropped.png');
      // The HUD's type: the title in its display face, the buttons in its
      // label face.
      expect(tester.widget<Text>(find.text('Game settings')).style?.fontFamily,
          'Sora');
      expect(
          DefaultTextStyle.of(tester.element(find.text('Done')))
              .style
              .fontFamily,
          'NunitoSans');
      expect(find.text('Music volume'), findsOneWidget);
      expect(find.text('SFX volume'), findsOneWidget);
      await tester.tap(find.byKey(const Key('putt-menu-leave')));
      await tester.tap(find.byKey(const Key('putt-menu-close')));
      expect(left, isTrue);
      expect(closed, isTrue);
    });

    testWidgets('dragging the music level persists it', (tester) async {
      final buses = PuttSilentBuses();
      await tester.pumpWidget(menu(buses: buses));
      await tester.pump();

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
      await tester.pumpWidget(menu());
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
      expect(match.advance(), isTrue); // the course's awards
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
