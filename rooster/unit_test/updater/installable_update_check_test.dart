// The look from the home screen on a build that installs over itself: it
// offers the restart for whatever the look before the app opened fetched,
// and looks again, once the network is up, when that look failed.
import 'dart:async';

import 'package:rooster/utils/updater/installable_update_check.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_self_updater.dart';

void main() {
  late FakeSelfUpdater updater;
  late List<String> restartsOffered;
  late List<String> pagesOffered;
  late List<Completer<void>> syncs;

  InstallableUpdateCheck check({int attempts = 3}) => InstallableUpdateCheck(
        updater,
        offerRestart: restartsOffered.add,
        offerReleasePage: pagesOffered.add,
        nextSync: () {
          final sync = Completer<void>();
          syncs.add(sync);
          return sync.future;
        },
        attempts: attempts,
        spacing: Duration.zero,
      );

  setUp(() {
    updater = FakeSelfUpdater();
    restartsOffered = [];
    pagesOffered = [];
    syncs = [];
  });

  test(
      'offers the restart once the look before the app opened has fetched the release',
      () async {
    // The app opened while the download was still going.
    updater.set(UpdateStage.downloading, tag: 'v2.0.0');
    final running = check().run();
    await Future<void>.delayed(Duration.zero);
    expect(restartsOffered, isEmpty);

    updater.set(UpdateStage.ready, tag: 'v2.0.0');
    await running;
    expect(restartsOffered, ['v2.0.0']);
    expect(updater.looks, 0, reason: 'no second look beside the first');
    expect(syncs, isEmpty);
  });

  test('offers a release already waiting when the app opened', () async {
    updater.set(UpdateStage.ready, tag: 'v2.0.0');

    await check().run();
    expect(restartsOffered, ['v2.0.0']);
    expect(updater.looks, 0);
  });

  test('looks itself when nothing looked before', () async {
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.ready])
    ];

    await check().run();
    expect(updater.looks, 1);
    expect(restartsOffered, ['v9.9.9']);
  });

  test(
      'a look that failed before the app opened is made again once a sync gets through',
      () async {
    updater.set(UpdateStage.failed, message: 'Could not reach GitHub');
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.ready])
    ];
    final running = check().run();
    await Future<void>.delayed(Duration.zero);
    expect(updater.looks, 0, reason: 'not before the network is known up');
    expect(syncs, hasLength(1));

    syncs.single.complete();
    await running;
    expect(updater.looks, 1);
    expect(restartsOffered, ['v9.9.9']);
  });

  test('gives up after the attempts', () async {
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.failed])
    ];
    final running = check(attempts: 3).run();
    while (syncs.length < 2) {
      await Future<void>.delayed(Duration.zero);
      for (final sync in syncs.where((s) => !s.isCompleted)) {
        sync.complete();
      }
    }
    await running;

    expect(updater.looks, 3);
    expect(restartsOffered, isEmpty);
    expect(pagesOffered, isEmpty);
  });

  test('a release this build cannot install points at the release page',
      () async {
    updater.plan = [
      (u) async {
        u.set(UpdateStage.checking);
        u.set(UpdateStage.available, tag: 'v2.0.0');
      }
    ];

    await check().run();
    expect(pagesOffered, ['v2.0.0']);
    expect(restartsOffered, isEmpty);
    expect(syncs, isEmpty);
  });

  test('nothing newer is left alone', () async {
    updater.plan = [
      stepping([UpdateStage.checking, UpdateStage.upToDate])
    ];

    await check().run();
    expect(updater.looks, 1);
    expect(restartsOffered, isEmpty);
    expect(pagesOffered, isEmpty);
  });

  test('the restart is offered once, however often the stage is reported',
      () async {
    updater.set(UpdateStage.ready, tag: 'v2.0.0');
    final it = check();
    await it.run();
    updater.set(UpdateStage.ready, tag: 'v2.0.0');
    await it.run();

    expect(restartsOffered, ['v2.0.0']);
  });

  test('two runs do not look twice at once', () async {
    final answer = Completer<void>();
    updater.plan = [waitingFor(answer)];
    final it = check();
    final first = it.run();
    final second = it.run();
    await Future<void>.delayed(Duration.zero);
    expect(updater.looks, 1);

    answer.complete();
    await Future.wait([first, second]);
    expect(restartsOffered, ['v9.9.9']);
  });
}
