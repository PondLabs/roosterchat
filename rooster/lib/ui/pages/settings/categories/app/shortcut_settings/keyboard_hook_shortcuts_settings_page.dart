import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class KeyboardHookShortcutsSettingsPage extends StatefulWidget {
  const KeyboardHookShortcutsSettingsPage({super.key});

  @override
  State<KeyboardHookShortcutsSettingsPage> createState() =>
      _KeyboardHookShortcutsSettingsPageState();

  static String get labelConfigureKeyboardShortcuts => Intl.message(
      "Configure Shortcuts",
      name: "labelConfigureKeyboardShortcuts",
      desc:
          "Label for the tile containing settings to configure system wide keyboard shortcuts, for muting, unmuting etc");
}

class _KeyboardHookShortcutsSettingsPageState
    extends State<KeyboardHookShortcutsSettingsPage> {
  String get promptShortcutsPressAKeyCombination => Intl.message(
      "Press a key combination",
      name: "promptShortcutsPressAKeyCombination",
      desc:
          "Prompt the user to input a key combination, which is recorded and used to activate a shortcut");

  String get promptShortcutsClearKeyboardShortcut =>
      Intl.message("Clear Shortcut",
          name: "promptShortcutsClearKeyboardShortcut",
          desc: "Prompt the user to clear a key combination shortcut");

  String get labelSettingsShortcutWarning => Intl.message("Warning",
      name: "labelSettingsShortcutWarning",
      desc: "Settings > Shortcuts (Linux): title of the dialog warning that a "
          "shortcut with Shift may not work");

  String get messageSettingsShiftShortcutUnreliable => Intl.message(
      "Hotkeys using 'Shift' as a modifier may be unreliable on Linux, consider using a different key combination",
      name: "messageSettingsShiftShortcutUnreliable",
      desc: "Settings > Shortcuts (Linux): shown after recording a shortcut "
          "that uses the Shift key. 'Shift' is the name of the key");

  String get promptSettingsShortcutWarningOkay => Intl.message("Okay!",
      name: "promptSettingsShortcutWarningOkay",
      desc: "Settings > Shortcuts (Linux): button that closes the warning "
          "about Shift shortcuts");

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: KeyboardHookShortcutsSettingsPage.labelConfigureKeyboardShortcuts,
      child: Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var shortcut in SystemWideShortcuts.shortcuts.entries)
            Material(
              color: ColorScheme.of(context).surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  var key = await AdaptiveDialog.show<HotKey>(context,
                      dismissible: false, builder: (context) {
                    HotKey? hotkey = shortcut.value.hotkey;

                    return Column(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tiamat.Text.largeTitle(
                            promptShortcutsPressAKeyCombination),
                        SizedBox(
                          height: 50,
                          child: Center(
                            child: HotKeyRecorder(
                                initalHotKey: hotkey,
                                onHotKeyRecorded: (k) {
                                  hotkey = k;
                                }),
                          ),
                        ),
                        tiamat.Button(
                          text: CommonStrings.promptSubmit,
                          onTap: () => Navigator.of(context).pop(hotkey),
                        ),
                        tiamat.Button.secondary(
                          text: promptShortcutsClearKeyboardShortcut,
                          onTap: () => Navigator.of(context).pop(null),
                        )
                      ],
                    );
                  });

                  if (PlatformUtils.isLinux) {
                    if (key?.modifiers?.contains(HotKeyModifier.shift) ==
                        true) {
                      await AdaptiveDialog.show(context,
                          title: labelSettingsShortcutWarning,
                          builder: (_) => SizedBox(
                                width: 500,
                                child: Column(
                                  children: [
                                    tiamat.Text.label(
                                        messageSettingsShiftShortcutUnreliable),
                                    tiamat.Button.secondary(
                                      text: promptSettingsShortcutWarningOkay,
                                      onTap: () => Navigator.of(context).pop(),
                                    )
                                  ],
                                ),
                              ));
                    }
                  }

                  if (key != null) {
                    await shortcut.value.setHotkey(key);
                  } else {
                    await shortcut.value.clearHotkey();
                  }

                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    spacing: 12,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                          child: tiamat.Text(shortcut.value.getDisplayName())),
                      if (shortcut.value.hotkey != null)
                        HotKeyVirtualView(hotKey: shortcut.value.hotkey!)
                    ],
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}
