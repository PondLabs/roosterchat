import 'dart:async';

import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:rooster/ui/pages/setup/setup_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UpdateCheckerSetup implements SetupMenu {
  StreamController<SetupMenuState> controller = StreamController();

  GlobalKey key = GlobalKey();

  static String get labelSettingsAskCheckForUpdates => Intl.message(
      "Would you like Rooster to automatically check for new updates?",
      name: "labelSettingsAskCheckForUpdates",
      desc: "First-run setup, under the title 'Check for updates': asks "
          "whether the app should look for new versions by itself");

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle(
            CheckForUpdatesSettingWidget.labelSettingsCheckForUpdates),
        tiamat.Text.label(labelSettingsAskCheckForUpdates),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
              decoration: BoxDecoration(
                color: ColorScheme.of(context).surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CheckForUpdatesSettingWidget(),
              )),
        ),
      ],
    );
  }

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  /// Going past the question without touching the switch is a yes, which
  /// is what the switch showed: a desktop build looks for a newer release
  /// at every launch unless told not to (docs/updating.md), and the home
  /// screen's check needs the yes written down.
  @override
  Future<void> submit() async {
    if (preferences.checkForUpdates.value == null) {
      preferences.checkForUpdates.set(true);
    }
  }
}

class CheckForUpdatesSettingWidget extends StatefulWidget {
  const CheckForUpdatesSettingWidget({super.key});

  static String get labelSettingsCheckForUpdates =>
      Intl.message("Check for updates",
          name: "labelSettingsCheckForUpdates",
          desc: "Title of the first-run setup step, and of the toggle in it "
              "and in Settings > General, that makes the app look for new "
              "versions by itself");

  static String get labelSettingsCheckForUpdatesDescription => Intl.message(
      "Automatically check if there is a newer version of Rooster available",
      name: "labelSettingsCheckForUpdatesDescription",
      desc: "Description of the 'Check for updates' toggle (first-run setup "
          "and Settings > General)");

  @override
  State<CheckForUpdatesSettingWidget> createState() =>
      _CheckForUpdatesSettingWidgetState();
}

class _CheckForUpdatesSettingWidgetState
    extends State<CheckForUpdatesSettingWidget> {
  @override
  Widget build(BuildContext context) {
    return NullableBooleanPreferenceToggle(
      preference: preferences.checkForUpdates,
      defaultValue: true,
      title: CheckForUpdatesSettingWidget.labelSettingsCheckForUpdates,
      description:
          CheckForUpdatesSettingWidget.labelSettingsCheckForUpdatesDescription,
    );
  }
}
