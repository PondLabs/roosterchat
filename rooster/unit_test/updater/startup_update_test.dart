// The look for an update before the app opens: started beside
// initialisation and waited for after it, but not for long. A slow cold
// start or a network still coming up must open the app rather than keep
// it shut, and must not stop the look either.
import 'dart:async';

import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/updater/startup_update.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_self_updater.dart';

void main() {
  late FakeSelfUpdater updater;
  var closed = 0;

  StartupUpdate startup(
          {bool wanted = true, Duration grace = const Duration(seconds: 1)}) =>
      StartupUpdate(updater,
          wanted: () async => wanted,
          close: () async => closed++,
          grace: grace);

  setUp(() {
    updater = FakeSelfUpdater();
    closed = 0;
  });

  test('restarts into a release fetched while the app initialised', () async {
    updater.plan = [
      stepping([
        UpdateStage.checking,
        UpdateStage.downloading,
        UpdateStage.unpacking,
        UpdateStage.ready,
      ])
    ];
    final update = startup()..begin();

    expect(await update.finish(), isTrue);
    expect(updater.looks, 1);
    expect(updater.restartsAsked, 1);
    expect(closed, 1);
  });

  test('a look that GitHub has answered keeps the app shut while it fetches',
      () async {
    final fetched = Completer<void>();
    updater.plan = [
      (u) async {
        u.set(UpdateStage.checking);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        u.set(UpdateStage.downloading);
        await fetched.future;
        u.set(UpdateStage.ready);
      }
    ];
    final update = startup(grace: const Duration(milliseconds: 100))..begin();

    var finished = false;
    final finish = update.finish().then((restarting) {
      finished = true;
      return restarting;
    });
    // Well past the grace: the download, not the answer, is what is waited
    // for now.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(finished, isFalse);

    fetched.complete();
    expect(await finish, isTrue);
    expect(closed, 1);
  });

  test(
      'opens the app when GitHub has not answered by the grace, and the look goes on',
      () async {
    final answer = Completer<void>();
    updater.plan = [waitingFor(answer)];
    final update = startup(grace: const Duration(milliseconds: 50))..begin();

    expect(await update.finish(), isFalse);
    expect(updater.restartsAsked, 0);
    expect(closed, 0);
    expect(updater.progress.value.stage, UpdateStage.checking);

    // The answer comes later, and the look carries on to the end: the home
    // screen is what offers it then.
    answer.complete();
    await Future<void>.delayed(Duration.zero);
    expect(updater.progress.value.stage, UpdateStage.ready);
    expect(updater.restartsAsked, 0);
  });

  test(
      'a look that failed, found nothing newer, or nothing it can install, opens the app',
      () async {
    for (final outcome in [
      UpdateStage.failed,
      UpdateStage.upToDate,
      UpdateStage.available,
    ]) {
      updater = FakeSelfUpdater()
        ..plan = [
          stepping([UpdateStage.checking, outcome])
        ];
      final update = startup()..begin();

      expect(await update.finish(), isFalse, reason: '$outcome');
      expect(updater.restartsAsked, 0, reason: '$outcome');
    }
    expect(closed, 0);
  });

  test('does not look when the preference says no', () async {
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.ready])
    ];
    final update = startup(wanted: false)..begin();

    expect(await update.finish(), isFalse);
    expect(updater.looks, 0);
  });

  test('does not look on a build that cannot install over itself', () async {
    updater = FakeSelfUpdater(canInstall: false)
      ..plan = [
        stepping([UpdateStage.checking, UpdateStage.ready])
      ];
    final update = startup()..begin();

    expect(await update.finish(), isFalse);
    expect(updater.looks, 0);
  });

  test('a swap that could not be handed over opens the app', () async {
    updater = FakeSelfUpdater(restarts: false)
      ..plan = [
        stepping([UpdateStage.checking, UpdateStage.ready])
      ];
    final update = startup()..begin();

    expect(await update.finish(), isFalse);
    expect(updater.restartsAsked, 1);
    expect(closed, 0);
  });

  test('finishing without having begun still looks', () async {
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.ready])
    ];

    expect(await startup().finish(), isTrue);
    expect(updater.looks, 1);
  });

  test('a look that throws opens the app', () async {
    updater.plan = [(u) async => throw StateError('no network stack')];
    final update = startup()..begin();

    expect(await update.finish(), isFalse);
    expect(closed, 0);
  });
}
