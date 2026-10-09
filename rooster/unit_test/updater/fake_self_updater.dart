// A SelfUpdater whose looks do what a test says, for the code around the
// real one: the look before the app opens and the one from the home screen.
import 'dart:async';

import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/updater/update_release.dart';
import 'package:flutter/foundation.dart';

typedef Look = Future<void> Function(FakeSelfUpdater updater);

class FakeSelfUpdater implements SelfUpdater {
  FakeSelfUpdater({this.canInstall = true, this.restarts = true});

  @override
  final ValueNotifier<UpdateProgress> progress =
      ValueNotifier(const UpdateProgress(UpdateStage.idle));

  @override
  bool canInstall;

  /// What [installAndRestart] answers.
  bool restarts;

  /// What each look does, in order; the last one repeats.
  List<Look> plan = [];

  int looks = 0;
  int restartsAsked = 0;

  /// Moves to [stage] with a release, the way the real one reports.
  void set(UpdateStage stage, {String tag = 'v9.9.9', String? message}) {
    progress.value = UpdateProgress(stage,
        release: UpdateRelease(tag: tag, assets: const []), message: message);
  }

  @override
  Future<void> checkAndPrepare({Duration? checkTimeout}) async {
    if (plan.isEmpty) return;
    final look = plan[looks < plan.length ? looks : plan.length - 1];
    looks++;
    await look(this);
  }

  @override
  Future<bool> installAndRestart() async {
    restartsAsked++;
    return restarts;
  }

  @override
  Future<void> discard() async {}
}

/// A look that goes through [stages] with a pause between them.
Look stepping(List<UpdateStage> stages,
        {Duration pause = const Duration(milliseconds: 10)}) =>
    (updater) async {
      for (final stage in stages) {
        updater.set(stage);
        await Future<void>.delayed(pause);
      }
    };

/// A look that asks GitHub and gets an answer only when [answer] completes.
Look waitingFor(Completer<void> answer,
        {UpdateStage then = UpdateStage.ready}) =>
    (updater) async {
      updater.set(UpdateStage.checking);
      await answer.future;
      updater.set(then);
    };
