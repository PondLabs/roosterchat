// The update control in settings: what is running, a button to look for
// something newer, and, once one is unpacked and waiting, a restart.
//
// Always here, whatever the "check for updates" preference says: that
// preference only governs the check that runs by itself at startup, and
// somebody who turned it off should still be able to ask.
import 'package:rooster/config/build_config.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:rooster/utils/update_checker.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key});

  static String get labelUpdateVersion => Intl.message("Version",
      name: "labelUpdateVersion",
      desc: "Heading of the update control in Settings, above the running "
          "version or what the update is doing");

  static String get promptUpdateRestart => Intl.message("Restart to update",
      name: "promptUpdateRestart",
      desc: "Button in Settings once a newer release is downloaded: restarts "
          "the app into it");

  static String get promptUpdateOpenReleasePage =>
      Intl.message("Open release page",
          name: "promptUpdateOpenReleasePage",
          desc: "Button in Settings that opens the newer release's page on "
              "GitHub, where this build cannot install it by itself");

  static String get promptUpdateCheck => Intl.message("Check for updates",
      name: "promptUpdateCheck",
      desc: "Button in Settings that looks for a newer release now");

  static String get labelUpdateLookingForNewer =>
      Intl.message("Looking for a newer version…",
          name: "labelUpdateLookingForNewer",
          desc: "Under Version in Settings while the app asks GitHub for a "
              "newer release");

  static String labelUpdateDownloading(String tag) => Intl.message(
      "Downloading $tag…",
      name: "labelUpdateDownloading",
      args: [tag],
      desc: "Under Version in Settings while a newer release downloads; the "
          "tag is its version, for example v1.18.0");

  static String labelUpdateDownloadingPercent(String tag, int percent) =>
      Intl.message("Downloading $tag… $percent%",
          name: "labelUpdateDownloadingPercent",
          args: [tag, percent],
          desc: "Under Version in Settings while a newer release downloads, "
              "with how much of it has arrived, from 0 to 100 percent");

  static String get labelUpdateVerifying =>
      Intl.message("Checking the download…",
          name: "labelUpdateVerifying",
          desc: "Under Version in Settings while the downloaded release is "
              "checked against its checksum");

  static String labelUpdateReadyOnRestart(String tag) =>
      Intl.message("$tag is ready. It goes in when Rooster restarts.",
          name: "labelUpdateReadyOnRestart",
          args: [tag],
          desc: "Under Version in Settings once a newer release is downloaded "
              "and unpacked; it is installed when the app restarts. The tag is "
              "its version");

  static String labelUpdateTagAvailable(String tag) => Intl.message(
      "$tag is available.",
      name: "labelUpdateTagAvailable",
      args: [tag],
      desc: "Under Version in Settings when a newer release exists; the tag "
          "is its version");

  static String labelUpdateIsLatest(String version) => Intl.message(
      "$version is the latest.",
      name: "labelUpdateIsLatest",
      args: [version],
      desc: "Under Version in Settings when the running version is the newest "
          "release");

  static String get labelUpdateFailed => Intl.message("The update failed.",
      name: "labelUpdateFailed",
      desc: "Under Version in Settings when an update failed and there is no "
          "more detail to give");

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  SelfUpdater get updater => SelfUpdater.instance;

  Future<void> _restart() async {
    if (await updater.installAndRestart()) {
      await WindowManagement.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateProgress>(
      valueListenable: updater.progress,
      builder: (context, progress, _) {
        final release = progress.release;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.label(UpdateButton.labelUpdateVersion),
                      tiamat.Text.labelLow(_status(progress)),
                    ],
                  ),
                ),
                if (progress.stage == UpdateStage.ready)
                  tiamat.Button.success(
                    text: UpdateButton.promptUpdateRestart,
                    onTap: _restart,
                  )
                else if (progress.stage == UpdateStage.available &&
                    release != null)
                  tiamat.Button(
                    text: UpdateButton.promptUpdateOpenReleasePage,
                    onTap: () => LinkUtils.open(
                        Uri.parse(UpdateChecker.releasesPageUrl),
                        context: context),
                  )
                else
                  tiamat.Button(
                    text: UpdateButton.promptUpdateCheck,
                    onTap: progress.busy ? null : updater.checkAndPrepare,
                  ),
              ],
            ),
            if (progress.fraction != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: progress.fraction),
              ),
          ],
        );
      },
    );
  }

  String _status(UpdateProgress progress) {
    final version = BuildConfig.VERSION_TAG;
    final tag = progress.release?.tag;
    // An interpolated null, as before: a stage with a tag always has one.
    final tagText = "$tag";
    return switch (progress.stage) {
      UpdateStage.checking => UpdateButton.labelUpdateLookingForNewer,
      UpdateStage.downloading => progress.fraction == null
          ? UpdateButton.labelUpdateDownloading(tagText)
          : UpdateButton.labelUpdateDownloadingPercent(
              tagText, (progress.fraction! * 100).round()),
      UpdateStage.verifying => UpdateButton.labelUpdateVerifying,
      UpdateStage.unpacking => labelUpdateUnpacking(tagText),
      UpdateStage.ready =>
        progress.message ?? UpdateButton.labelUpdateReadyOnRestart(tagText),
      UpdateStage.available =>
        progress.message ?? UpdateButton.labelUpdateTagAvailable(tagText),
      UpdateStage.upToDate =>
        progress.message ?? UpdateButton.labelUpdateIsLatest(version),
      UpdateStage.failed => progress.message ?? UpdateButton.labelUpdateFailed,
      UpdateStage.idle => version,
    };
  }
}
