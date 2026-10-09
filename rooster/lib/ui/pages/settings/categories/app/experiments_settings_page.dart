import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class ExperimentsSettingsPage extends StatefulWidget {
  const ExperimentsSettingsPage({super.key});

  @override
  State<ExperimentsSettingsPage> createState() =>
      _ExperimentsSettingsPageState();
}

class _ExperimentsSettingsPageState extends State<ExperimentsSettingsPage> {
  String get labelSettingsExperimentsWarning => Intl.message(
      "These features are still under development, and may contain bugs or security issues. Enable at your own risk",
      name: "labelSettingsExperimentsWarning",
      desc: "Warning at the top of Settings > Experiments");

  String get labelSettingsExperimentsHeader => Intl.message("Experiments",
      name: "labelSettingsExperimentsHeader",
      desc: "Settings > Experiments: header of the panel with the "
          "experimental features");

  String get labelSettingsEncryptedElementCall =>
      Intl.message("Encrypted Element Call",
          name: "labelSettingsEncryptedElementCall",
          desc: "Settings > Experiments: toggle for end-to-end encrypted calls "
              "through Element Call (a product name)");

  String get labelSettingsEncryptedElementCallDescription => Intl.message(
      "Allow use of the experimental support for end to end encryption in element call",
      name: "labelSettingsEncryptedElementCallDescription",
      desc: "Description of the 'Encrypted Element Call' toggle in Settings > "
          "Experiments");

  String get labelSettingsExperimentsRestart =>
      Intl.message("You must restart the app for changes to take effect",
          name: "labelSettingsExperimentsRestart",
          desc: "Warning at the bottom of Settings > Experiments");

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: tiamat.Text.error(
            labelSettingsExperimentsWarning,
          ),
        ),
        Panel(
          header: labelSettingsExperimentsHeader,
          mode: TileType.surfaceContainerLow,
          child: Column(
            children: [
              BooleanPreferenceToggle(
                preference: preferences.experimentEnableE2eeElementCall,
                title: labelSettingsEncryptedElementCall,
                description: labelSettingsEncryptedElementCallDescription,
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: tiamat.Text.error(
            labelSettingsExperimentsRestart,
          ),
        ),
      ],
    );
  }
}
