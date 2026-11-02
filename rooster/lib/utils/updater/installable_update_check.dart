// The in-app look for an update on a build that installs over itself: the
// second look, after the one before the app opened (StartupUpdate), and the
// one that recovers what that one missed. A launch with the session can come
// before the network, and a cold start can be too slow for the first look;
// either way the user used to be pointed at the release page and nothing
// was installed.
import 'dart:async';

import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/updater/self_updater.dart';

class InstallableUpdateCheck {
  InstallableUpdateCheck(
    this.updater, {
    required this.offerRestart,
    required this.offerReleasePage,
    required this.nextSync,
    this.attempts = 3,
    this.spacing = const Duration(seconds: 30),
  });

  final SelfUpdater updater;

  /// Called once, with the tag, when a release is unpacked and waiting for
  /// the restart, whichever look fetched it.
  final void Function(String tag) offerRestart;

  /// Called with the tag of a newer release this build cannot install (no
  /// archive for it, or none checksummed), which is fetched by hand.
  final void Function(String tag) offerReleasePage;

  /// Completes when the next sync has got through: the network is up.
  final Future<void> Function() nextSync;

  /// How many looks in all, the one before the app opened included.
  final int attempts;

  /// The least time between two looks.
  final Duration spacing;

  bool _running = false;
  bool _watching = false;
  bool _offered = false;

  /// Looks, fetches and offers. Safe to call again; one at a time.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      _watch();
      // The look before the app opened counts: it may still be going, or
      // have failed.
      var looked = updater.progress.value.stage != UpdateStage.idle;
      for (var attempt = 1; attempt <= attempts; attempt++) {
        if (!looked) {
          try {
            await updater.checkAndPrepare();
          } catch (e, s) {
            Log.onError(e, s, content: 'Update: could not look');
            return;
          }
        }
        await _settled();
        looked = true;
        switch (updater.progress.value.stage) {
          case UpdateStage.failed:
            if (attempt == attempts) return;
            // GitHub out of reach, or a download that broke off. At a
            // launch with the session the network may still be coming up:
            // again once a sync has got through, and not at once.
            Log.i('Update: looking again once a sync has got through');
            await Future.wait([nextSync(), Future<void>.delayed(spacing)]);
            looked = false;
          case UpdateStage.available:
            final tag = updater.progress.value.release?.tag;
            if (tag != null) offerReleasePage(tag);
            return;
          default:
            // Ready (the watcher offers it), up to date, or idle on an
            // updater that does not look.
            return;
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Offers the restart the moment a release is ready, now or later: the
  /// look before the app opened may still be fetching it.
  void _watch() {
    if (_watching) return;
    _watching = true;
    void onProgress() {
      final progress = updater.progress.value;
      if (progress.stage == UpdateStage.ready && !_offered) {
        _offered = true;
        offerRestart(progress.release?.tag ?? '');
      }
    }

    updater.progress.addListener(onProgress);
    onProgress();
  }

  /// Waits for a look or a download already going to finish.
  Future<void> _settled() {
    if (!updater.progress.value.busy) return Future.value();
    final settled = Completer<void>();
    void onProgress() {
      if (!updater.progress.value.busy && !settled.isCompleted) {
        settled.complete();
      }
    }

    updater.progress.addListener(onProgress);
    return settled.future
        .whenComplete(() => updater.progress.removeListener(onProgress));
  }
}
