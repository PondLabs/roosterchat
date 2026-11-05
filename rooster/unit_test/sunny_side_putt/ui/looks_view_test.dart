// The looks in the view: "Your egg" off the settings menu keeps its pick on
// this device and dresses the match at once, the next match picks the
// pick up, a guest's match asks the host for its look (a few times at
// most) while home shows it at once, and the scorecard's and the tags'
// little eggs wear every player's look.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/config/preferences/preference.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_audio.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_hud.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_look.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_menus.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_name_tags.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _freshPreferences([Map<String, Object> values = const {}]) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(values);
  Preference.preferences = await SharedPreferences.getInstance();
}

const _crown = PuttLook(pattern: EggPattern.stars, hat: HatchlingHat.crown);
const _bow = PuttLook(pattern: EggPattern.dots, hat: HatchlingHat.bow);

PuttConfig _duo() => PuttConfig(
      mode: GameMode.casual,
      courses: [
        CourseDef(id: 'duo', holes: [stubHole(id: 'd0'), stubHole(id: 'd1')]),
      ],
      seed: 3,
    );

Finder _glyphWearing(PuttLook look) => find.byWidgetPredicate(
    (widget) => widget is PuttEggGlyph && widget.look == look);

void main() {
  setUp(() async => _freshPreferences());
  tearDown(() => Preference.preferences = null);

  group('"Your egg"', () {
    testWidgets('the settings menu opens it, when wired', (tester) async {
      var opened = false;
      final match = PuttMatch.solo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttSettingsMenu(
            match: match,
            buses: PuttSilentBuses(),
            onClose: () {},
            onLeave: () {},
            onOpenLook: () => opened = true,
          ),
        ),
      ));
      expect(find.text('Your egg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('putt-menu-look')));
      expect(opened, isTrue);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttSettingsMenu(
            match: match,
            buses: PuttSilentBuses(),
            onClose: () {},
            onLeave: () {},
          ),
        ),
      ));
      expect(find.byKey(const Key('putt-menu-look')), findsNothing);
    });

    testWidgets('a pick is kept, worn at once, and the next match wears it',
        (tester) async {
      var picks = 0;
      var closed = false;
      final match = PuttMatch.solo();
      expect(match.look, PuttLook.standard, reason: 'nothing picked yet');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttLookSheet(
            match: match,
            onPick: () => picks++,
            onClose: () => closed = true,
          ),
        ),
      ));
      // Every pattern and every hat on offer, the current ones called.
      for (final pattern in EggPattern.values) {
        expect(find.byKey(Key('putt-look-pattern-${pattern.name}')),
            findsOneWidget);
      }
      for (final hat in HatchlingHat.values) {
        expect(find.byKey(Key('putt-look-hat-${hat.name}')), findsOneWidget);
      }
      expect(find.text('Pattern: Zigzag'), findsOneWidget);
      expect(find.text('No hat'), findsOneWidget);

      await tester.tap(find.byKey(const Key('putt-look-pattern-stars')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('putt-look-hat-crown')));
      await tester.pump();
      expect(find.text('Pattern: Stars'), findsOneWidget);
      expect(find.text('Hat: Crown'), findsOneWidget);
      expect(picks, 2);

      // Kept on this device...
      expect(puttEggLook.value, 'stars/crown');
      expect(savedPuttLook(), _crown);
      // ...worn in this match at once...
      expect(match.look, _crown);
      expect(match.engine.player('me')!.look, _crown);
      // ...and by the next match from the start.
      final next = PuttMatch.solo();
      expect(next.engine.player('me')!.look, _crown);

      // The same tile again picks nothing new.
      await tester.tap(find.byKey(const Key('putt-look-hat-crown')));
      await tester.pump();
      expect(picks, 2);

      await tester.ensureVisible(find.byKey(const Key('putt-look-close')));
      await tester.tap(find.byKey(const Key('putt-look-close')));
      expect(closed, isTrue);
    });

    testWidgets('fits a short window, scrolling', (tester) async {
      tester.view
        ..physicalSize = const Size(380, 360)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PuttLookSheet(match: PuttMatch.solo(), onClose: () {}),
        ),
      ));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('putt-look-close')));
      expect(find.byKey(const Key('putt-look-close')).hitTestable(),
          findsOneWidget);
    });

    test('a saved pick from an older version still reads', () async {
      await _freshPreferences({'putt_egg_look': 'plaid/crown'});
      expect(savedPuttLook(), const PuttLook(hat: HatchlingHat.crown));
      expect(
          PuttMatch.solo().engine.player('me')!.look.hat, HatchlingHat.crown);
    });
  });

  group('the match wears my look', () {
    test('a local match puts it on at once, with a puff on my egg', () {
      final match = PuttMatch.solo();
      match.fxSpots.clear();
      match.wear(_bow);
      expect(match.engine.player('me')!.look, _bow);
      expect(
          match.fxSpots
              .where((spot) => spot.kind == PuttFxSpotKind.restyle)
              .map((spot) => spot.who),
          ['me']);
    });

    test('a guest asks the host, a few times at most, and wears it at home',
        () {
      final engine = PuttEngine(_duo())
        ..join('host')
        ..join('me')
        ..start();
      final asked = <EngineInput>[];
      final match = PuttMatch(
        config: engine.config,
        engine: engine,
        localPlayerId: 'me',
        remoteMove: asked.add,
        look: PuttLook.standard,
      );
      match.update(0.016);
      expect(asked, isEmpty, reason: 'the engine already has it right');

      match.wear(_crown);
      expect(asked.whereType<LookInput>().single.look, _crown);
      expect(engine.player('me')!.look, _crown, reason: 'at home at once');

      // An older snapshot of the host's takes it back: the ask waits a
      // beat (the host's relay is likely on its way), then goes again.
      engine.setLook('me', PuttLook.standard);
      match.update(1);
      expect(asked, hasLength(1));
      match.update(2.5);
      expect(asked, hasLength(2));
      expect(engine.player('me')!.look, _crown);
      // A host that never takes it (an older version) is asked no more
      // than three times.
      for (var i = 0; i < 6; i++) {
        engine.setLook('me', PuttLook.standard);
        match.update(3.5);
      }
      expect(asked, hasLength(3));

      // A new seat (left and back) starts the asks over.
      engine.leave('me');
      match.update(3.5);
      engine.join('me');
      match.update(3.5);
      expect(asked, hasLength(4));
      expect(engine.player('me')!.look, _crown);
    });

    test('the asks go on while the menu pauses the match', () {
      final engine = PuttEngine(_duo())
        ..join('me')
        ..start();
      final asked = <EngineInput>[];
      final match = PuttMatch(
        config: engine.config,
        engine: engine,
        remoteMove: asked.add,
        look: PuttLook.standard,
      )..paused = true;
      match.wear(_bow);
      engine.setLook('me', PuttLook.standard);
      match.update(3.5);
      expect(asked, hasLength(2));
    });
  });

  group('the little eggs wear everyone\'s look', () {
    testWidgets('on the scorecard', (tester) async {
      final match = PuttMatch(
        config: _duo(),
        displayNames: const {'me': 'Rooster', 'p2': 'Hen'},
        seatedPlayerIds: const ['p2'],
        look: _crown,
      )..boot();
      match.engine.setLook('p2', _bow);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttHud(match: match, onOpenMenu: () {})),
      ));
      await tester.pump();
      final card = find.byKey(const Key('putt-scorecard'));
      expect(find.descendant(of: card, matching: _glyphWearing(_crown)),
          findsOneWidget);
      expect(find.descendant(of: card, matching: _glyphWearing(_bow)),
          findsOneWidget);
    });

    testWidgets('on the name tags, beside the picture or alone',
        (tester) async {
      final board = PuttTagBoard();
      addTearDown(board.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PuttNameTags(board: board)),
      ));
      board.update(const [
        PuttTag(
            playerId: 'maya',
            name: 'Maya',
            color: Colors.teal,
            at: Offset(200, 200),
            look: _bow),
        PuttTag(
            playerId: 'lou',
            name: 'Lou',
            color: Colors.pink,
            at: Offset(500, 200),
            look: _crown,
            compact: true),
      ]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final maya = tester
          .widget<PuttEggGlyph>(find.byKey(const Key('putt-tag-egg-maya')));
      expect(maya.look, _bow);
      expect(maya.tint, Colors.teal);
      expect(
          tester
              .widget<PuttEggGlyph>(find.byKey(const Key('putt-tag-egg-lou')))
              .look,
          _crown,
          reason: 'a far tag without a picture keeps the little egg');
    });

    test('a tag with a picture is wider by the little egg', () {
      // A picture that never needs to load.
      final image = MemoryImage(Uint8List(0));
      final bare = puttTagPill(
          const PuttTag(
              playerId: 'a', name: 'Ana', color: Colors.teal, at: Offset.zero),
          Offset.zero);
      final pictured = puttTagPill(
          PuttTag(
              playerId: 'a',
              name: 'Ana',
              color: Colors.teal,
              at: Offset.zero,
              avatar: image),
          Offset.zero);
      expect(pictured.width, greaterThan(bare.width + 18));
    });
  });
}
