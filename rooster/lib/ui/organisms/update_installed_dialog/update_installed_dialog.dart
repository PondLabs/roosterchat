import 'package:rooster/ui/organisms/particle_player/particle_system_confetti.dart';
import 'package:rooster/config/build_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:starfield/renderer/particle_system_renderer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UpdateInstalledDialog extends StatefulWidget {
  const UpdateInstalledDialog({super.key});
  @override
  State<UpdateInstalledDialog> createState() => _UpdateInstalledDialogState();
}

class _UpdateInstalledDialogState extends State<UpdateInstalledDialog> {
  MessageEffectConfetti? confetti;

  String updateInstalledVersion(String version) => Intl.message(
      "Rooster is now on version $version.",
      desc:
          "Content for the dialog which is shown when an update has been installed",
      args: [version],
      name: "updateInstalledVersion");

  String get promptUpdateInstalledOk => Intl.message("Got it",
      desc: "Button that closes the dialog shown after an update",
      name: "promptUpdateInstalledOk");

  @override
  void initState() {
    confetti = MessageEffectConfetti();
    confetti?.init().then((_) => setState(() {}));
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    spacing: 12,
                    children: [
                      tiamat.Text.label(updateInstalledVersion(BuildConfig
                          .VERSION_TAG
                          .replaceFirst(RegExp(r"^v"), ""))),
                      Material(
                          clipBehavior: Clip.antiAlias,
                          color: ColorScheme.of(context).surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                            },
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 8,
                                  children: [
                                    tiamat.Text(promptUpdateInstalledOk),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    ])))
      ],
    );
  }
}
