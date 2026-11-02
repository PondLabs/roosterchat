// The update a desktop build installs before the app opens: looked for
// beside initialisation, waited for once the app is otherwise ready to open,
// and never for long.
//
// The look at GitHub shares the main isolate with everything else that
// starts: the Rust library loading, the accounts opening. A bound on the
// request alone counted that time too, and on a cold start (nothing in the
// page cache, or a launch with the session before the network was up) the
// five seconds ran out before GitHub's answer had been read. The app then
// opened on the old build, and nothing later in the session installed the
// update: the home screen only pointed at the release page. Now the request
// has its usual budget, the app waits for the answer only once it could
// open, and briefly. A look still unanswered carries on in the background,
// and the home screen offers what it finds (UpdateChecker).
import 'dart:async';

import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/updater/update_release.dart';

class StartupUpdate {
  StartupUpdate(
    this.updater, {
    required this.wanted,
    required this.close,
    this.grace = const Duration(seconds: 5),
    this.checkTimeout = UpdateRelease.defaultTimeout,
  });

  final SelfUpdater updater;

  /// Whether the preference allows it. Asked when the look starts, since
  /// the preferences load beside this.
  final Future<bool> Function() wanted;

  /// Closes the app once the swap has been handed over.
  final Future<void> Function() close;

  /// How long [finish] waits for GitHub's answer once the app could open.
  final Duration grace;

  /// The request's own bound. Generous: it does not hold the app shut.
  final Duration checkTimeout;

  Future<bool>? _started;
  Future<void>? _prepare;

  /// Starts the look, when this build installs over itself and [wanted].
  /// Nothing waits on it here.
  void begin() {
    _started ??= _begin();
  }

  /// Never throws: an update that could not be looked for is no reason to
  /// keep the app from opening.
  Future<bool> _begin() async {
    try {
      if (!updater.canInstall) return false;
      if (!await wanted()) return false;
      // Nothing waits on the look until finish(), so a look that threw
      // would be an error nobody caught.
      _prepare = updater.checkAndPrepare(checkTimeout: checkTimeout).catchError(
          (Object e, StackTrace s) => Log.onError(e, s,
              content: 'Could not look for an update at startup'));
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: 'Could not look for an update at startup');
      return false;
    }
  }

  /// Called once the app is otherwise ready to open. True when it is
  /// restarting into a newer release instead, and the caller is done.
  /// Never throws.
  Future<bool> finish() async {
    try {
      if (!await (_started ??= _begin())) return false;
      if (!await _answered()) {
        Log.i('Update: no answer from GitHub yet; opening without it');
        return false;
      }
      // Fetching: the loading window shows it, and the restart is worth
      // the wait.
      if (updater.progress.value.busy) await _prepare;
      if (updater.progress.value.stage != UpdateStage.ready) return false;
      if (!await updater.installAndRestart()) return false;
      await close();
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: 'Could not install an update at startup');
      return false;
    }
  }

  /// Whether the look has got past asking GitHub, within [grace].
  Future<bool> _answered() {
    if (updater.progress.value.stage != UpdateStage.checking) {
      return Future.value(true);
    }
    final answered = Completer<bool>();
    void onProgress() {
      if (updater.progress.value.stage != UpdateStage.checking &&
          !answered.isCompleted) {
        answered.complete(true);
      }
    }

    updater.progress.addListener(onProgress);
    final timer = Timer(grace, () {
      if (!answered.isCompleted) answered.complete(false);
    });
    return answered.future.whenComplete(() {
      updater.progress.removeListener(onProgress);
      timer.cancel();
    });
  }
}
