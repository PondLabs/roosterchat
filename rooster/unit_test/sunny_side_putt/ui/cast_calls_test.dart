// Every cast is everyone's: another player's power-up makes a call in the
// feed, a sound and the scene's spots on the green; a theft from me, a swap
// with me and a shell that holds say so; the feed reads a run of casts one
// after another; and the game turns them into the world's frame (the crow
// in the air, the bubble, the ghost, the magnet, the kernels).
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_cast_feed.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart'
    show puttLaunchPowerUps;
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/stub_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

/// Me and two friends on a wide stub hole, the twelve real power-ups, the
/// boot's chatter spent.
PuttMatch _match() {
  final course = CourseDef(
      id: 'casts', holes: [stubHole(id: 'k0', width: 34, height: 22)]);
  final match = PuttMatch(
    config: PuttConfig(
      mode: GameMode.casual,
      courses: [course],
      seed: 12,
      wobbleMaxRadians: 0,
      powerUps: puttLaunchPowerUps(),
    ),
    displayNames: const {'me': 'Gabriel', 'p2': 'Maya', 'p3': 'Jonas'},
    seatedPlayerIds: const ['p2', 'p3'],
  )..boot();
  match.notices.clear();
  match.fxSpots.clear();
  return match;
}

/// [playerId] holds [effectId] and casts it from the wire (a relayed
/// move), then a frame drains it.
void _theyCast(PuttMatch match, String playerId, String effectId,
    [PowerUpTarget? target]) {
  match.engine.player(playerId)!.inventory.add(effectId);
  expect(match.engine.usePowerUp(playerId, effectId, target), isTrue);
  match.update(1 / 60);
}

Iterable<PuttFxSpot> _spots(PuttMatch match, PuttFxSpotKind kind) =>
    match.fxSpots.where((spot) => spot.kind == kind);

void main() {
  group('the calls', () {
    test("another player's cast is called, heard and played on the green", () {
      final match = _match();
      _theyCast(match, 'p2', 'corn_rain');
      final call = match.castCalls.last;
      expect(call.kind, PuttCastCallKind.cast);
      expect(call.casterId, 'p2');
      expect(puttCastLine(match, call), 'Maya: Corn Rain');
      expect(puttCastTone(match, call), PuttCastTone.theirs);
      expect(call.leadId, 'p2');
      expect(call.iconId, 'corn_rain');
      // The chime for everyone, and the corn's own patter.
      expect(match.notices.map((n) => n.sfx),
          containsAll([PuttSfx.powerUpUsed, PuttSfx.cornRain]));
      // The burst at the caster's egg, the kernels on everyone else's.
      final cast = _spots(match, PuttFxSpotKind.cast).single;
      expect(cast.who, 'p2');
      expect(cast.effectId, 'corn_rain');
      expect(cast.at, isNotNull);
      expect(_spots(match, PuttFxSpotKind.hit).map((spot) => spot.who),
          unorderedEquals(['me', 'p3']));
    });

    test('an egg knocked at rest hears who did it, and the knocker too', () {
      final match = _match();
      final world = match.engine.world!;
      // Maya has putted and rests: her egg is solid (a waiting egg would be
      // a ghost).
      world.ball('p2')!.putted = true;
      final mine = match.myBall!.position;
      final hers = world.ball('p2')!.position;
      expect(match.submitShot((hers - mine).angle, 0.45), isTrue);
      for (var i = 0; i < 90 && match.castCalls.isEmpty; i++) {
        match.update(1 / 60);
      }
      final mineCall = match.castCalls.last;
      expect(mineCall.kind, PuttCastCallKind.knock);
      expect(mineCall.casterId, 'me');
      expect(mineCall.otherId, 'p2');
      expect(puttCastLine(match, mineCall), "You knocked Maya's egg");
      expect(puttCastTone(match, mineCall), PuttCastTone.mine);

      // And the other way round: Maya's egg into mine, at rest.
      for (var i = 0; i < 600 && !world.allSettled; i++) {
        match.update(1 / 60);
      }
      final calls = match.castCalls.length;
      final me = match.myBall!.position;
      final from = world.ball('p2')!.position;
      expect(match.engine.submitShot('p2', (me - from).angle, 0.45), isTrue);
      for (var i = 0; i < 90 && match.castCalls.length == calls; i++) {
        match.update(1 / 60);
      }
      final theirs = match.castCalls.last;
      expect(theirs.casterId, 'p2');
      expect(puttCastLine(match, theirs), 'Maya knocked your egg!');
      expect(puttCastTone(match, theirs), PuttCastTone.againstMe);
    });

    test("a knock between two others is not the viewer's news", () {
      final match = _match();
      final world = match.engine.world!;
      world.ball('p3')!.putted = true;
      final from = world.ball('p2')!.position;
      final to = world.ball('p3')!.position;
      expect(match.engine.submitShot('p2', (to - from).angle, 0.45), isTrue);
      for (var i = 0; i < 120; i++) {
        match.update(1 / 60);
      }
      expect(match.castCalls.where((c) => c.kind == PuttCastCallKind.knock),
          isEmpty);
    });

    test('a point cast carries its spot to the scene', () {
      final match = _match();
      const spot = Vec2(17, 4);
      _theyCast(match, 'p3', 'gust', const PowerUpTarget.point(spot));
      expect(puttCastLine(match, match.castCalls.last), 'Jonas: Gust');
      expect(_spots(match, PuttFxSpotKind.cast).single.toward, spot);
      expect(match.notices.map((n) => n.sfx), contains(PuttSfx.gust));
      expect(_spots(match, PuttFxSpotKind.hit).map((s) => s.who),
          unorderedEquals(['me', 'p2']));
    });

    test('a theft from me says so, and the crow flies it home', () {
      final match = _match();
      match.localPlayer!.inventory.add('gust');
      _theyCast(match, 'p2', 'thieving_crow', const PowerUpTarget.player('me'));
      // One call for the crow: the theft, not a cast and a theft.
      expect(match.castCalls.where((c) => c.effectId == 'thieving_crow').length,
          1);
      final call = match.castCalls.last;
      expect(call.kind, PuttCastCallKind.steal);
      expect(puttCastLine(match, call), 'Maya stole your Gust!');
      expect(puttCastTone(match, call), PuttCastTone.againstMe);
      expect(call.iconId, 'gust');
      expect(match.myInventory, isEmpty);
      expect(match.notices.map((n) => n.sfx), contains(PuttSfx.crowCaw));
      final steal = _spots(match, PuttFxSpotKind.steal).single;
      expect(steal.who, 'p2');
      expect(steal.other, 'me');
      expect(steal.effectId, 'gust');
      expect(steal.at, match.myBall!.position);
      // The loot's sparkle waits for the crow to land.
      expect(_spots(match, PuttFxSpotKind.pick), isEmpty);
    });

    test('a theft reads from every seat', () {
      final match = _match();
      match.engine.player('p3')!.inventory.add('hawk_eye');
      _theyCast(match, 'p2', 'thieving_crow', const PowerUpTarget.player('p3'));
      expect(puttCastLine(match, match.castCalls.last),
          "Maya stole Jonas's Hawk Eye");
      expect(puttCastTone(match, match.castCalls.last), PuttCastTone.theirs);

      match.engine.player('p2')!.inventory.add('sprinkler');
      match.localPlayer!.inventory.add('thieving_crow');
      expect(
          match.usePowerUp('thieving_crow', const PowerUpTarget.player('p2')),
          isTrue);
      final mine = match.castCalls.last;
      // The crow went for the first slot: what it stole from Jonas.
      expect(puttCastLine(match, mine), "You stole Maya's Hawk Eye!");
      expect(puttCastTone(match, mine), PuttCastTone.mine);
    });

    test('a shell that holds says so, after the cast it held against', () {
      final match = _match();
      match.localPlayer!.inventory.add('thick_shell');
      expect(match.usePowerUp('thick_shell'), isTrue);
      expect(puttCastLine(match, match.castCalls.last), 'You: Thick Shell');
      _theyCast(match, 'p3', 'gust', const PowerUpTarget.point(Vec2(3, 3)));
      final calls = match.castCalls.reversed.take(2).toList().reversed;
      expect([for (final call in calls) puttCastLine(match, call)],
          ['Jonas: Gust', "Your shell blocked Jonas's Gust!"]);
      final blocked = match.castCalls.last;
      expect(blocked.kind, PuttCastCallKind.blocked);
      expect(blocked.leadId, 'me');
      expect(blocked.iconId, 'thick_shell');
      expect(puttCastTone(match, blocked), PuttCastTone.mine);
      expect(match.notices.map((n) => n.sfx), contains(PuttSfx.shieldPop));
      final pop = _spots(match, PuttFxSpotKind.shieldPop).single;
      expect(pop.who, 'me');
      expect(pop.other, 'p3');
      // The wind still caught Maya.
      expect(_spots(match, PuttFxSpotKind.hit).map((s) => s.who), ['p2']);

      // Someone else's shell, seen from here.
      _theyCast(match, 'p2', 'thick_shell');
      _theyCast(match, 'p3', 'corn_rain');
      expect(puttCastLine(match, match.castCalls.last),
          "Maya's shell blocked Jonas's Corn Rain");

      // A theft aimed at a shell is stopped outright, and its own toast
      // says so at once (no "stole" line behind it).
      match.engine.player('p2')!.inventory.add('gust');
      _theyCast(match, 'p2', 'thick_shell');
      final before = match.castCalls.length;
      _theyCast(match, 'p3', 'thieving_crow', const PowerUpTarget.player('p2'));
      final crowCalls = match.castCalls.skip(before).toList();
      expect([for (final call in crowCalls) puttCastLine(match, call)],
          ["Maya's shell blocked Jonas's Thieving Crow"]);
      expect(match.engine.player('p2')!.inventory.contains('gust'), isTrue,
          reason: 'nothing was taken');
    });

    test('a swap that moves my egg is a swap with me', () {
      final match = _match();
      final before = match.myBall!.position;
      _theyCast(match, 'p2', 'nest_swap', const PowerUpTarget.player('me'));
      final call = match.castCalls.last;
      expect(call.kind, PuttCastCallKind.swap);
      expect(puttCastLine(match, call), 'Maya swapped places with you!');
      expect(puttCastTone(match, call), PuttCastTone.againstMe);
      expect(match.myBall!.position.distanceTo(before), greaterThan(0.5));
      expect(_spots(match, PuttFxSpotKind.hit).map((s) => s.who),
          unorderedEquals(['me', 'p2']));
    });

    test('a boosted shot shows its power-up to everyone', () {
      final match = _match();
      _theyCast(match, 'p2', 'strong_coffee');
      match.fxSpots.clear();
      expect(match.engine.submitShot('p2', 0, 0.4), isTrue);
      match.update(1 / 60);
      final shot = _spots(match, PuttFxSpotKind.shot).single;
      expect(shot.who, 'p2');
      expect(shot.effectId, 'strong_coffee');
      expect(shot.toward!.x, greaterThan(shot.at!.x), reason: 'putted east');
    });

    test("my own cast's sound and burst wait for the game to spend them", () {
      final match = _match();
      match.localPlayer!.inventory.add('hawk_eye');
      expect(match.usePowerUp('hawk_eye'), isTrue);
      // The next tick drains again before the game plays the batch: what
      // the press drained must still be there.
      match.update(1 / 60);
      expect(match.notices.map((n) => n.sfx), contains(PuttSfx.powerUpUsed));
      expect(_spots(match, PuttFxSpotKind.cast).single.who, 'me');
    });
  });

  group('the feed', () {
    testWidgets('casts in a row read one after another', (tester) async {
      final match = _match();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: PuttCastFeed(match: match)))));
      expect(find.byKey(const Key('putt-cast-toast')), findsNothing);

      match.localPlayer!.inventory.add('thick_shell');
      match.usePowerUp('thick_shell');
      _theyCast(match, 'p2', 'corn_rain');
      await tester.pump();
      expect(find.text('You: Thick Shell'), findsOneWidget);
      expect(find.text('Maya: Corn Rain'), findsNothing);

      // Others wait: each one goes once it has been read (sooner while
      // two wait).
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('You: Thick Shell'), findsNothing);
      expect(find.text('Maya: Corn Rain'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Maya: Corn Rain'), findsNothing);
      expect(find.text("Your shell blocked Maya's Corn Rain!"), findsOneWidget);

      // The last one stays its full time, then the feed is empty.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('putt-cast-toast')), findsNothing);
    });

    testWidgets('what was called before the feed came up is not replayed',
        (tester) async {
      final match = _match();
      _theyCast(match, 'p2', 'gust', const PowerUpTarget.point(Vec2(3, 3)));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: PuttCastFeed(match: match)))));
      await tester.pump();
      expect(find.byKey(const Key('putt-cast-toast')), findsNothing);
    });
  });

  group('the frame', () {
    testWidgets('a theft puts a crow in the air with the loot, then lands it',
        (tester) async {
      final match = _match();
      final sounds = <PuttSfx>[];
      final game =
          SunnySidePuttGame(match: match, onSfx: (sfx, _) => sounds.add(sfx));
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await tester.pump(const Duration(milliseconds: 50));

      match.engine.player('p3')!.inventory.add('sprinkler');
      match.localPlayer!.inventory.add('thieving_crow');
      match.usePowerUp('thieving_crow', const PowerUpTarget.player('p3'));
      await tester.pump(const Duration(milliseconds: 16));
      var crows = game.buildWorldFrame().crows;
      expect(crows, hasLength(1));
      expect(crows.single.effectId, 'sprinkler');
      expect(crows.single.from, match.engine.world!.ball('p3')!.position);
      expect(
          crows.single.to.distanceTo(match.myBall!.position), lessThan(1e-6));
      expect(sounds, contains(PuttSfx.crowCaw));
      expect(sounds, isNot(contains(PuttSfx.powerUpPicked)));

      // Mid-flight, then in my hand: the carton chimes as it lands.
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      crows = game.buildWorldFrame().crows;
      expect(crows.single.progress, inInclusiveRange(0.4, 0.8));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.buildWorldFrame().crows, isEmpty);
      expect(sounds, contains(PuttSfx.powerUpPicked));
    });

    testWidgets('the eggs carry their shells, ghosts and magnets',
        (tester) async {
      final match = _match();
      final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await tester.pump(const Duration(milliseconds: 50));

      _theyCast(match, 'p2', 'thick_shell');
      _theyCast(match, 'p3', 'ghost_egg');
      match.localPlayer!.inventory.add('nest_magnet');
      match.usePowerUp('nest_magnet');
      await tester.pump(const Duration(milliseconds: 16));
      PuttWorldEgg egg(String id) =>
          game.buildWorldFrame().eggs.firstWhere((e) => e.playerId == id);
      expect(egg('p2').shielded, isTrue);
      expect(egg('p3').ghostSeconds, inInclusiveRange(2.5, 3.0));
      expect(egg('me').magnet, isTrue);
      expect(egg('me').shielded || egg('p2').ghostSeconds > 0, isFalse);

      // The ghost runs out; a cast pops the shell.
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(egg('p3').ghostSeconds, 0);
      _theyCast(match, 'p3', 'corn_rain');
      await tester.pump(const Duration(milliseconds: 16));
      expect(egg('p2').shielded, isFalse);
    });

    testWidgets('corn rain sends kernels down round the eggs it hits',
        (tester) async {
      final match = _match();
      final game = SunnySidePuttGame(match: match, onSfx: (_, __) {});
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await tester.pump(const Duration(milliseconds: 50));

      _theyCast(match, 'p2', 'corn_rain');
      // Where the eggs it nudged stood as it hit.
      final hitAt = {
        for (final spot in _spots(match, PuttFxSpotKind.hit))
          spot.who!: spot.at!,
      };
      expect(hitAt.keys, unorderedEquals(['me', 'p3']));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final kernels = game
          .buildWorldFrame()
          .fxs
          .where((fx) => fx.kind == PuttWorldFxKind.kernel)
          .toList();
      expect(kernels.length, greaterThan(10));
      expect(kernels.every((fx) => (fx.height ?? 0) > 0), isTrue);
      // They rain round the eggs they hit (each gets its share), not the
      // caster's.
      double nearest(PuttWorldFx fx) => hitAt.values
          .map((at) => fx.at.distanceTo(at))
          .reduce((a, b) => a < b ? a : b);
      expect(kernels.every((fx) => nearest(fx) < 3), isTrue);
      for (final at in hitAt.values) {
        expect(kernels.any((fx) => fx.at.distanceTo(at) < 2), isTrue);
      }
    });
  });
}
