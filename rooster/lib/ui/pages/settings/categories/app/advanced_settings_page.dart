import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  String get labelSettingsDeveloperMode => Intl.message("Developer mode",
      desc: "Header for the settings to enable developer mode",
      name: "labelSettingsDeveloperMode");

  String get labelSettingsDeveloperModeExplanation =>
      Intl.message("Shows extra information, useful for developers",
          desc: "Explains what developer mode does",
          name: "labelSettingsDeveloperModeExplanation");

  String get labelStickerCompatibility => Intl.message("Sticker compatibility",
      desc: "Header for the settings to enable sticker compatibility mode",
      name: "labelStickerCompatibility");

  String get labelSettingsStickerCompatibilityExplanation => Intl.message(
      "In some matrix clients, sending a sticker as 'm.sticker' will cause the sticker to not load correctly. Enabling this setting will send stickers as 'm.image' which will allow them to render correctly",
      desc: "Explains what sticker compatibility mode does",
      name: "labelSettingsStickerCompatibilityExplanation");

  String get labelSettingsOverrideLayout => Intl.message("Override Layout",
      name: "labelSettingsOverrideLayout",
      desc: "Settings > Advanced: header of the setting that forces the "
          "desktop or the phone layout of the app, whatever the window size");

  String get labelSettingsOverrideLayoutRestart => Intl.message(
      "You may need to restart the app for this to take effect",
      name: "labelSettingsOverrideLayoutRestart",
      desc: "Settings > Advanced > Override Layout: changing the layout may "
          "need a restart");

  String get labelSettingsLayoutNoOverride => Intl.message("No Override",
      name: "labelSettingsLayoutNoOverride",
      desc: "Settings > Advanced > Override Layout: choice that leaves the "
          "layout to the window size");

  String get labelSettingsLayoutDesktop => Intl.message("desktop",
      name: "labelSettingsLayoutDesktop",
      desc: "Settings > Advanced > Override Layout: choice that always uses "
          "the computer (desktop) layout");

  String get labelSettingsLayoutMobile => Intl.message("mobile",
      name: "labelSettingsLayoutMobile",
      desc: "Settings > Advanced > Override Layout: choice that always uses "
          "the phone (mobile) layout");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Panel(
          header: labelSettingsDeveloperMode,
          mode: TileType.surfaceContainerLow,
          child: BooleanPreferenceToggle(
            preference: preferences.developerMode,
            title: labelSettingsDeveloperMode,
            description: labelSettingsDeveloperModeExplanation,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Panel(
            header: labelStickerCompatibility,
            mode: TileType.surfaceContainerLow,
            child: BooleanPreferenceToggle(
              preference: preferences.stickerCompatibilityMode,
              title: labelStickerCompatibility,
              description: labelSettingsStickerCompatibilityExplanation,
            )),
        const SizedBox(
          height: 10,
        ),
        Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: labelSettingsOverrideLayout,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelLow(labelSettingsOverrideLayoutRestart),
                tiamat.DropdownSelector(
                    items: [null, "desktop", "mobile"],
                    // The items are the preference's values; these are
                    // what they are called on screen.
                    itemBuilder: (item) => tiamat.Text.label(switch (item) {
                          "desktop" => labelSettingsLayoutDesktop,
                          "mobile" => labelSettingsLayoutMobile,
                          String other => other,
                          null => labelSettingsLayoutNoOverride,
                        }),
                    onItemSelected: (item) async {
                      await preferences.layoutOverride.set(item);
                      setState(() {});
                    },
                    value: preferences.layoutOverride.value)
              ],
            ))
      ],
    );
  }
}
