import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/pages/settings/categories/app/shortcut_settings/keyboard_hook_shortcuts_settings_page.dart';
import 'package:rooster/ui/pages/settings/categories/app/shortcut_settings/outsource_shortcut_settings_page.dart';
import 'package:rooster/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ShortcutSettingsPage extends StatelessWidget {
  const ShortcutSettingsPage({super.key});

  static String get labelSettingsShortcutsDesktopAppNotice => Intl.message(
      "⌨️ Mute and deafen with one key from any app, mid-game "
      "included. Global shortcuts come with the desktop app.",
      name: "labelSettingsShortcutsDesktopAppNotice",
      desc: "Settings > Shortcuts in the browser: a short pitch for the "
          "desktop app, which has shortcuts that work from any other app. "
          "Followed by where the desktop app is available, and a download "
          "link");

  @override
  Widget build(BuildContext context) {
    if (BuildConfig.WEB) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: DesktopAppNotice(labelSettingsShortcutsDesktopAppNotice),
      );
    }
    if (SystemWideShortcuts.isSupported == false) {
      return Placeholder();
    }

    bool showOutsourceMenu =
        PlatformUtils.isDisplayServer(DisplayServer.Wayland) &&
            PlatformUtils.isDesktopEnvironment(DesktopEnvironment.KDEPlasma);

    bool showHooksMenu = !showOutsourceMenu;

    if (preferences.developerMode.value) {
      showHooksMenu = true;
    }

    if (BuildConfig.IS_FLATPAK) {
      showHooksMenu = false;
    }

    return Column(
      spacing: 8,
      children: [
        if (showOutsourceMenu) OutsourceShortcutSettingsPage(),
        if (showHooksMenu) KeyboardHookShortcutsSettingsPage()
      ],
    );
  }
}
