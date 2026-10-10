import 'dart:convert';

import 'package:rooster/client/alert.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:rooster/utils/updater/installable_update_check.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:http/http.dart' as http;

/// Checks for a newer Rooster release on GitHub Releases, once the app is up.
///
/// On a desktop build that installs over itself this is the second look,
/// after the one before the app opened (StartupUpdate), and the one that
/// recovers what that one missed: it fetches the release and offers the
/// restart from the home screen, and when GitHub could not be reached it
/// looks again once a sync has got through, since a launch with the session
/// can come before the network. Everywhere else it points at the release
/// page, which is all the app can do there.
///
/// This goes through the unauthenticated GitHub API. That is rate limited to 60
/// requests per hour per IP, which is ample for a few requests per launch on a
/// desktop install. Startup uses [checkForUpdatesOncePerLaunch] to preserve
/// that cadence, while [checkForUpdates] remains available to an explicit
/// caller that needs a fresh result later in the session.
///
/// Note that `releases/latest` excludes prereleases, so a release tagged as a
/// prerelease is invisible here by design.
class UpdateChecker {
  static bool _automaticCheckStarted = false;
  static final UpdateCheckState _state = UpdateCheckState();
  static InstallableUpdateCheck? _installable;

  /// The project whose releases we check.
  static const String releasesApiUrl =
      "https://api.github.com/repos/PondLabs/roosterchat/releases/latest";

  /// Where the "View release" action sends the user.
  static const String releasesPageUrl =
      "https://github.com/PondLabs/roosterchat/releases/latest";

  /// The notes of the release tagged [tag] (`v1.21.0`), for "See what's new"
  /// after an update.
  static String releaseNotesUrl(String tag) =>
      "https://github.com/PondLabs/roosterchat/releases/tag/$tag";

  static String get labelUpdateAvailable => Intl.message("Update Available",
      name: "labelUpdateAvailable",
      desc: "Label for the the info popup when an update is available");

  static String descriptionUpdateAvailable(String version) => Intl.message(
      "There is a newer version of Rooster available: ${version}. Tap to open the release page.",
      name: "descriptionUpdateAvailable",
      args: [version],
      desc:
          "Update alert body. Keep the version value unchanged and tell the user that tapping opens the release page");

  static String get labelUpdateReady => Intl.message("Update ready",
      name: "labelUpdateReady",
      desc:
          "Title of the home screen alert once a newer version is downloaded and waiting for a restart");

  static String descriptionUpdateReady(String version) => Intl.message(
      "Rooster ${version} is downloaded and ready. Tap to restart into it.",
      name: "descriptionUpdateReady",
      args: [version],
      desc:
          "Update alert body once the newer version is downloaded. Keep the version value unchanged and tell the user that tapping restarts the app into it");

  /// Runs the automatic startup check at most once during this app launch.
  ///
  /// Home screens can be recreated, so the call site alone cannot provide the
  /// once-per-launch guarantee. The flag is set before awaiting the request so
  /// two screens created close together cannot start duplicate checks.
  static Future<void> checkForUpdatesOncePerLaunch() async {
    if (_automaticCheckStarted) return;

    _automaticCheckStarted = true;
    await checkForUpdates();
  }

  static Future<void> checkForUpdates() async {
    if (!shouldCheckForUpdates) {
      return;
    }

    if (preferences.checkForUpdates.value != true) {
      return;
    }

    final updater = SelfUpdater.instance;
    if (updater.canInstall) {
      _installable ??= InstallableUpdateCheck(updater,
          offerRestart: _offerRestart,
          offerReleasePage: _offerReleasePage,
          nextSync: _nextSync);
      await _installable!.run();
      return;
    }

    if (_state.foundUpdate) return;

    String? latest;
    try {
      var response = await http.get(Uri.parse(releasesApiUrl), headers: {
        // Request GitHub's stable JSON media type. Dart supplies its own
        // User-Agent, so this client does not need to add one explicitly.
        "Accept": "application/vnd.github+json",
      });

      if (response.statusCode != 200) {
        Log.i("Update check failed: HTTP ${response.statusCode}");
        return;
      }

      var data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      latest = data["tag_name"] as String?;
    } catch (e, s) {
      // A failed update check is never worth surfacing to the user, and it must
      // not break startup.
      Log.onError(e, s);
      return;
    }

    if (latest == null || latest.isEmpty) return;

    _offerReleasePage(latest);
  }

  /// The alert that opens the release page, for a newer [tag] this build
  /// cannot install over itself. Once per launch.
  static void _offerReleasePage(String tag) {
    if (!_state.shouldAlertFor(tag, BuildConfig.VERSION_TAG)) {
      Log.i("Up to date: running ${BuildConfig.VERSION_TAG}, latest $tag");
      return;
    }

    Log.i("Found update: ${BuildConfig.VERSION_TAG} -> $tag");

    clientManager?.alertManager.addAlert(Alert(AlertType.info,
        messageGetter: () => descriptionUpdateAvailable(tag),
        titleGetter: () => labelUpdateAvailable,
        action: doUpdateAction));
  }

  /// The alert that restarts into [tag], unpacked and waiting.
  static void _offerRestart(String tag) {
    Log.i("Update: $tag is ready; offering the restart");

    clientManager?.alertManager.addAlert(Alert(AlertType.info,
        messageGetter: () => descriptionUpdateReady(tag),
        titleGetter: () => labelUpdateReady,
        action: restartIntoUpdate));
  }

  /// The next sync to get through, which says the network is up. Without
  /// any account there is nothing to wait for.
  static Future<void> _nextSync() =>
      clientManager?.onSync.stream.first ?? Future.value();

  /// True when [candidate] is a strictly newer version than [current].
  ///
  /// Both are expected as `vMAJOR.MINOR.PATCH` (the format of the git tags and
  /// of [BuildConfig.VERSION_TAG]) but any leading `v` and any trailing
  /// pre-release/build suffix are tolerated: only the leading numeric dotted
  /// run is compared, so `v1.2.3-rc1` compares as `1.2.3`.
  ///
  /// Returns false when either side has no parseable version, so a local build
  /// with the default `VERSION_TAG` of `development` never reports an update.
  static bool isNewer(String candidate, String current) {
    var a = parseVersion(candidate);
    var b = parseVersion(current);

    if (a == null || b == null) return false;

    var length = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < length; i++) {
      var x = i < a.length ? a[i] : 0;
      var y = i < b.length ? b[i] : 0;

      if (x != y) return x > y;
    }

    return false;
  }

  /// The leading numeric dotted run of [tag] as a list of ints, or null when
  /// there is none.
  static List<int>? parseVersion(String tag) {
    var match = RegExp(r"(\d+(?:\.\d+)*)").firstMatch(tag);

    if (match == null) return null;

    var version = <int>[];

    // ROOSTER: Preserve the documented null contract for components outside
    // Dart's integer range instead of allowing int.parse to throw.
    for (var component in match.group(1)!.split(".")) {
      var value = int.tryParse(component);
      if (value == null) return null;
      version.add(value);
    }

    return version;
  }

  static bool get shouldCheckForUpdates {
    if (PlatformUtils.isWeb) {
      return false;
    }

    if (BuildConfig.VERSION_TAG == "v0.0.0-artifact") {
      return false;
    }

    return true;
  }

  /// Where the build cannot install over itself, an update is the release
  /// page: Android, the web, and a desktop build that belongs to a package
  /// manager (see docs/updating.md).
  static doUpdateAction(BuildContext context) async {
    LinkUtils.open(Uri.parse(releasesPageUrl), context: context);
  }

  /// Swaps in the release the updater unpacked and closes the app, which the
  /// swap starts again. Nothing changes when there is nothing staged.
  static Future<void> restartIntoUpdate(BuildContext context) async {
    if (await SelfUpdater.instance.installAndRestart()) {
      await WindowManagement.close();
    }
  }
}

/// Tracks whether this process has already alerted for an available update.
///
/// An up-to-date result deliberately does not latch: a later explicit check in
/// the same session must still be able to discover a newly published release.
class UpdateCheckState {
  bool foundUpdate = false;

  bool shouldAlertFor(String candidate, String current) {
    if (foundUpdate) return false;

    foundUpdate = UpdateChecker.isNewer(candidate, current);
    return foundUpdate;
  }
}
