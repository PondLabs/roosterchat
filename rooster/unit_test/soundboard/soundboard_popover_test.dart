import 'dart:convert';

import 'package:rooster/client/components/soundboard/soundboard_catalog.dart';
import 'package:rooster/client/components/soundboard/soundboard_emoji.dart';
import 'package:rooster/client/components/soundboard/soundboard_sound.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_favorites.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

SoundboardSound _sound(String id, String name, [String emoji = '📢']) =>
    SoundboardSound(
      soundId: id,
      name: name,
      emoji: SoundboardEmoji.unicode(emoji),
      mediaUri: 'mxc://x/$id',
      mimeType: 'audio/mpeg',
      durationMs: 2000,
      normalizedGain: 1.0,
    );

SoundboardSource _source(String id, String name, List<SoundboardSound> s,
        {bool canAdd = false}) =>
    SoundboardSource(
      id: id,
      name: name,
      color: Colors.blue,
      catalog: InMemorySoundboardCatalog(s),
      canAddSounds: () => canAdd,
    );

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.light().copyWith(
      extensions: const [ThemeSettings()],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

// 1x1 transparent PNG, so a custom emoji has an image to render.
final _pixel = MemoryImage(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> played;
  late SoundboardFavorites favorites;
  late double volume;

  setUp(() {
    played = [];
    favorites = SoundboardFavorites.inMemory();
    volume = 0.8;
  });

  Future<void> pumpPopover(
    WidgetTester tester,
    List<SoundboardSource> sources, {
    ValueChanged<SoundboardSource>? onAddSound,
  }) async {
    await tester.pumpWidget(_testApp(SoundboardPopover(
      sources: sources,
      favorites: favorites,
      onPlay: played.add,
      volume01: volume,
      onVolumeChanged: (v) => volume = v,
      onAddSound: onAddSound,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('shows one section per space and plays the tapped sound',
      (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [_sound('s1', 'Airhorn')]),
      _source('!b', 'Other space', [_sound('s2', 'Bruh')]),
    ]);

    expect(find.text('Roscas do CCO'), findsOneWidget);
    expect(find.text('Other space'), findsOneWidget);

    await tester.tap(find.text('Bruh'));
    expect(played, ['s2']);
  });

  // With a keyboard and a mouse: the tests below this one run as the phone
  // flutter_test pretends to be unless they say otherwise.
  const desktop = TargetPlatformVariant({TargetPlatform.linux});

  testWidgets('search is focused on open and filters sounds by name',
      variant: desktop, (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [
        _sound('s1', 'Airhorn'),
        _sound('s2', 'Sad trombone'),
      ]),
      _source('!b', 'Other space', [_sound('s3', 'Bruh')]),
    ]);

    // Typing without tapping first: the field has autofocus.
    await tester.enterText(find.byType(TextField), 'TROMB');
    await tester.pumpAndSettle();

    expect(find.text('Sad trombone'), findsOneWidget);
    expect(find.text('Airhorn'), findsNothing);
    expect(find.text('Bruh'), findsNothing);
    expect(find.text('Other space'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('No sounds found'), findsOneWidget);
  });

  testWidgets('starring a sound adds a Favorites section at the top',
      variant: desktop, (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [
        _sound('s1', 'Airhorn'),
        _sound('s2', 'Bruh'),
      ]),
    ]);
    expect(find.text('Favorites'), findsNothing);

    await tester.tap(find.byTooltip('Add Bruh to favorites'));
    await tester.pumpAndSettle();

    expect(favorites.ids, ['s2']);
    expect(find.text('Bruh'), findsNWidgets(2));
    final favoritesTop = tester.getTopLeft(find.text('Favorites')).dy;
    final spaceTop = tester.getTopLeft(find.text('Roscas do CCO')).dy;
    expect(favoritesTop, lessThan(spaceTop));

    // Playing from the favorites section plays the same sound.
    await tester.tap(find.text('Bruh').first);
    expect(played, ['s2']);

    await tester.tap(find.byTooltip('Remove Bruh from favorites').first);
    await tester.pumpAndSettle();
    expect(favorites.ids, isEmpty);
    expect(find.text('Favorites'), findsNothing);
  });

  testWidgets('favorites keep their order and skip removed sounds',
      (tester) async {
    favorites = SoundboardFavorites.inMemory(['gone', 's2', 's1']);
    await pumpPopover(tester, [
      _source('!a', 'A', [_sound('s1', 'Airhorn'), _sound('s2', 'Bruh')]),
    ]);

    final bruh = tester.getTopLeft(find.text('Bruh').first);
    final airhorn = tester.getTopLeft(find.text('Airhorn').first);
    expect(bruh.dy, airhorn.dy);
    expect(bruh.dx, lessThan(airhorn.dx));
    expect(find.text('Airhorn'), findsNWidgets(2));
  });

  testWidgets('tapping a section header collapses and expands it',
      (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [_sound('s1', 'Airhorn')]),
    ]);

    await tester.tap(find.text('Roscas do CCO'));
    await tester.pumpAndSettle();
    expect(find.text('Airhorn'), findsNothing);

    await tester.tap(find.text('Roscas do CCO'));
    await tester.pumpAndSettle();
    expect(find.text('Airhorn'), findsOneWidget);
  });

  testWidgets('the rail jumps to a space section', (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Big space', [
        for (var i = 0; i < 60; i++) _sound('a$i', 'Sound $i'),
      ]),
      _source('!b', 'Other space', [_sound('b1', 'Bruh')]),
    ]);
    expect(find.text('Bruh').hitTestable(), findsNothing);
    // No favorites yet, so the rail has no star.
    expect(find.byTooltip('Favorites'), findsNothing);

    await tester.tap(find.byTooltip('Other space'));
    await tester.pumpAndSettle();

    expect(find.text('Bruh').hitTestable(), findsOneWidget);
  });

  testWidgets('the rail only lists sections the search leaves visible',
      (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [_sound('s1', 'Airhorn')]),
      _source('!b', 'Other space', [_sound('s2', 'Bruh')]),
    ]);
    expect(find.byTooltip('Roscas do CCO'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bruh');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Roscas do CCO'), findsNothing);
    expect(find.byTooltip('Other space'), findsOneWidget);
  });

  testWidgets('volume lives in a secondary popover', (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'A', [_sound('s1', 'Airhorn')]),
    ]);
    const sliderKey = ValueKey('soundboard-volume-slider');
    expect(find.byKey(sliderKey), findsNothing);

    await tester.tap(find.byTooltip('Sound effects volume'));
    await tester.pumpAndSettle();
    expect(find.text('80%'), findsOneWidget);

    await tester.drag(find.byKey(sliderKey), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(volume, 0.0);
    expect(find.text('0%'), findsOneWidget);

    // Tapping outside closes only the volume popover.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(sliderKey), findsNothing);
    expect(find.text('Airhorn'), findsOneWidget);
  });

  testWidgets('a custom Space emoji renders its image in the sound tile',
      (tester) async {
    // Issue #16 icons reach the issue #17 popover through the image
    // resolver; without one, only the unicode fallback can be shown.
    const velho = SoundboardEmoji.custom(
        mxc: 'mxc://example.org/velho', shortcode: ':velho:');
    final withImage = SoundboardSound(
      soundId: 's1',
      name: 'Velho',
      emoji: velho,
      mediaUri: 'mxc://x/s1',
      mimeType: 'audio/mpeg',
      durationMs: 2000,
      normalizedGain: 1.0,
    );

    await tester.pumpWidget(_testApp(SoundboardPopover(
      sources: [
        _source('!a', 'Roscas do CCO', [withImage])
      ],
      favorites: favorites,
      onPlay: played.add,
      volume01: volume,
      onVolumeChanged: (v) => volume = v,
      imageFor: (emoji) => emoji == velho ? _pixel : null,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(SoundboardEmoji.fallback), findsNothing);
  });

  testWidgets('a custom Space emoji without an image shows the fallback',
      (tester) async {
    final noImage = SoundboardSound(
      soundId: 's1',
      name: 'Velho',
      emoji: const SoundboardEmoji.custom(
          mxc: 'mxc://example.org/velho', shortcode: ':velho:'),
      mediaUri: 'mxc://x/s1',
      mimeType: 'audio/mpeg',
      durationMs: 2000,
      normalizedGain: 1.0,
    );

    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [noImage]),
    ]);

    expect(find.text(SoundboardEmoji.fallback), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a name that does not fit gets a tooltip with all of it',
      (tester) async {
    const long = 'The longest airhorn anyone has ever put on a soundboard';
    await pumpPopover(tester, [
      _source('!a', 'Roscas do CCO', [
        _sound('s1', 'Bruh'),
        _sound('s2', long),
      ]),
    ]);

    expect(find.byTooltip(long), findsOneWidget);
    expect(find.byTooltip('Bruh'), findsNothing);
  });

  testWidgets('a space the user manages ends with an Add sound tile',
      (tester) async {
    final added = <String>[];
    await pumpPopover(
        tester,
        [
          _source('!a', 'Managed', [_sound('s1', 'Airhorn')], canAdd: true),
          _source('!b', 'Not managed', [_sound('s2', 'Bruh')]),
        ],
        onAddSound: (source) => added.add(source.id));

    expect(find.text('Add sound'), findsOneWidget);
    await tester.tap(find.text('Add sound'));
    expect(added, ['!a']);
  });

  testWidgets('a managed space with no sounds still shows, to add one',
      (tester) async {
    await pumpPopover(
        tester,
        [
          _source('!a', 'Empty space', const [], canAdd: true),
        ],
        onAddSound: (_) {});

    expect(find.text('Empty space'), findsOneWidget);
    expect(find.text('Add sound'), findsOneWidget);
  });

  testWidgets('searching hides the Add sound tile', (tester) async {
    await pumpPopover(
        tester,
        [
          _source('!a', 'Managed', [_sound('s1', 'Airhorn')], canAdd: true),
        ],
        onAddSound: (_) {});

    await tester.enterText(find.byType(TextField), 'air');
    await tester.pumpAndSettle();
    expect(find.text('Airhorn'), findsOneWidget);
    expect(find.text('Add sound'), findsNothing);
  });

  testWidgets('without onAddSound there is no Add sound tile', (tester) async {
    await pumpPopover(tester, [
      _source('!a', 'Managed', [_sound('s1', 'Airhorn')], canAdd: true),
    ]);

    expect(find.text('Add sound'), findsNothing);
  });

  // Reported from the PWA on a phone: the sounds had no titles, only their
  // emoji. The popover asks for 540 pixels and a phone gives it some 340,
  // where three columns left each name about 30.
  group('on a phone', () {
    Future<void> pumpNarrow(WidgetTester tester, double width,
        List<SoundboardSource> sources) async {
      await tester.pumpWidget(_testApp(SizedBox(
        width: width,
        child: SoundboardPopover(
          sources: sources,
          favorites: favorites,
          onPlay: played.add,
          volume01: volume,
          onVolumeChanged: (v) => volume = v,
        ),
      )));
      await tester.pumpAndSettle();
    }

    test('the grid has as many columns as leave a name room', () {
      expect(SoundboardPopover.columnsFor(SoundboardPopover.width), 3);
      // A 360 wide phone, less the popover's margins.
      expect(SoundboardPopover.columnsFor(344), 2);
      // An early foldable's cover screen.
      expect(SoundboardPopover.columnsFor(264), 1);
    });

    testWidgets('every sound shows its title next to its emoji',
        (tester) async {
      const names = ['Airhorn', 'Sad trombone', 'Vine boom', 'Bruh'];
      await pumpNarrow(tester, 344, [
        _source('!a', 'Roscas do CCO', [
          for (final (i, name) in names.indexed) _sound('s$i', name),
        ]),
      ]);

      for (final name in names) {
        // Room for a dozen letters, where there were some 30 pixels (the
        // test font is far wider than a real one, so not by the text).
        expect(tester.getSize(find.text(name)).width, greaterThan(80));
      }
      // Two to a row.
      expect(tester.getTopLeft(find.text('Airhorn')).dy,
          tester.getTopLeft(find.text('Sad trombone')).dy);
      expect(tester.getTopLeft(find.text('Vine boom')).dy,
          greaterThan(tester.getTopLeft(find.text('Airhorn')).dy));

      await tester.tap(find.text('Vine boom'));
      expect(played, ['s2']);
    });

    testWidgets('opening it does not bring the keyboard up', (tester) async {
      await pumpNarrow(tester, 344, [
        _source('!a', 'Roscas do CCO', [_sound('s1', 'Airhorn')]),
      ]);

      expect(
          tester.widget<TextField>(find.byType(TextField)).autofocus, isFalse);
    });

    testWidgets('a long press stars a sound; only a favorite has a star',
        (tester) async {
      await pumpNarrow(tester, 344, [
        _source('!a', 'Roscas do CCO', [_sound('s1', 'Airhorn')]),
      ]);
      // No hidden button taking the name's room, to be hit by accident.
      expect(find.byTooltip('Add Airhorn to favorites'), findsNothing);

      await tester.longPress(find.text('Airhorn'));
      await tester.pumpAndSettle();

      expect(favorites.ids, ['s1']);
      expect(find.byTooltip('Remove Airhorn from favorites'), findsWidgets);
    });
  });
}
