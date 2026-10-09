import 'package:rooster/config/build_config.dart';
import 'package:rooster/ui/organisms/particle_player/particle_system_confetti.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:rooster/utils/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:starfield/renderer/particle_system_renderer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Shown the first time the app opens after an update: the version it is on
/// now, a way to read what changed, and a way back to the app. (It used to
/// end in Commet's "No, thanks", the answer to a donation request that is
/// gone, and people did not know what they were saying no to.)
class UpdateInstalledDialog extends StatefulWidget {
  const UpdateInstalledDialog({super.key});

  static String messageUpdateInstalled(String app, String version) =>
      Intl.message("$app is now on $version. Thanks for updating!",
          name: "messageUpdateInstalled",
          args: [app, version],
          desc: "The dialog shown the first time the app opens after an "
              "update, with the app's name and the version it updated to, "
              "such as v1.21.0");

  static String get promptUpdateWhatsNew => Intl.message("See what's new",
      name: "promptUpdateWhatsNew",
      desc: "Button in the dialog shown after an update: opens the notes of "
          "the new version's release");

  static String get promptUpdateInstalledDone => Intl.message("Let's go",
      name: "promptUpdateInstalledDone",
      desc: "Button in the dialog shown after an update: closes it, back to "
          "the app");

  @override
  State<UpdateInstalledDialog> createState() => _UpdateInstalledDialogState();
}

class _UpdateInstalledDialogState extends State<UpdateInstalledDialog> {
  MessageEffectConfetti? confetti;

  /// A release's tag (v1.21.0); a build of no release says "development".
  static final _releaseTag = RegExp(r'^v\d');

  String get updateInstalledContent => Intl.message(
      "Thank you for updating! You are now running the latest version.",
      desc:
          "Content for the dialog which is shown when an update has been installed",
      name: "updateInstalledContent");

  @override
  void initState() {
    confetti = MessageEffectConfetti();
    // The dialog may be closed before the confetti has loaded.
    confetti?.init().then((_) {
      if (mounted) setState(() {});
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    const version = BuildConfig.VERSION_TAG;
    final release = _releaseTag.hasMatch(version);

    return Stack(
      alignment: AlignmentGeometry.center,
      children: [
        if (confetti?.system != null)
          SizedBox(
              width: 500,
              height: 200,
              child: ParticleSystemRenderer(system: confetti!.system!)),
        SizedBox(
            width: 500,
            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      tiamat.Text.label(release
                          ? UpdateInstalledDialog.messageUpdateInstalled(
                              BuildConfig.app, version)
                          : updateInstalledContent),
                      // Side by side, or one over the other when a longer
                      // language's labels do not fit.
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TextButton.icon(
                            icon:
                                const Icon(Icons.open_in_new_rounded, size: 18),
                            label: Text(
                                UpdateInstalledDialog.promptUpdateWhatsNew),
                            onPressed: () => LinkUtils.open(
                                Uri.parse(release
                                    ? UpdateChecker.releaseNotesUrl(version)
                                    : UpdateChecker.releasesPageUrl),
                                context: context),
                          ),
                          FilledButton(
                            autofocus: true,
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(UpdateInstalledDialog
                                .promptUpdateInstalledDone),
                          ),
                        ],
                      ),
                    ])))
      ],
    );
  }
}
