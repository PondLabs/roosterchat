import 'package:rooster/config/build_config.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'dart:async';
import 'dart:io';

import 'package:rooster/config/layout_config.dart';
import 'package:rooster/config/theme_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:path/path.dart' as path;

class ThemeListWidget extends StatefulWidget {
  const ThemeListWidget({super.key});

  @override
  State<ThemeListWidget> createState() => _ThemeListWidgetState();
}

class _ThemeEntry {
  String name;
  Function(BuildContext context) setter;

  late Widget Function(BuildContext context, Widget child) builder;

  Widget defaultBuilder(BuildContext context, Widget child) {
    return child;
  }

  _ThemeEntry(this.name, this.setter,
      {Widget Function(BuildContext context, Widget child)? builder}) {
    this.builder = builder ?? defaultBuilder;
  }
}

class _ThemeListWidgetState extends State<ThemeListWidget> {
  late List<_ThemeEntry> entries;
  StreamSubscription? customThemesDirSub;

  String get labelThemeDark => Intl.message("Dark Theme",
      name: "labelThemeDark", desc: "Label for the dark theme");

  String get labelThemeLight => Intl.message("Light Theme",
      name: "labelThemeLight", desc: "Label for the light theme");

  String get labelThemeAmoled => Intl.message("Amoled",
      name: "labelThemeAmoled",
      desc: "Label for the AMOLED (pure black) theme");

  String get labelSettingsCustomThemesDesktopAppNotice => Intl.message(
      "🎨 Make Rooster yours with custom themes, installed in one "
      "click in the desktop app.",
      name: "labelSettingsCustomThemesDesktopAppNotice",
      desc: "Settings > Appearance > Theme in the browser: a short pitch for "
          "the desktop app, where you can install your own themes. Followed "
          "by where the desktop app is available, and a download link");

  String get labelSettingsPickThemeArchive =>
      Intl.message("Pick theme archive file",
          name: "labelSettingsPickThemeArchive",
          desc: "Settings > Appearance > Theme: title of the system file "
              "picker for choosing a theme packed in a .zip file");

  List<_ThemeEntry> get defaultThemes => [
        _ThemeEntry(labelThemeLight, (BuildContext context) async {
          preferences.theme.set("light");
          var theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.light);
          if (context.mounted) ThemeChanger.setTheme(context, theme);
        }),
        _ThemeEntry(labelThemeDark, (BuildContext context) async {
          preferences.theme.set("dark");
          var theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.dark);
          if (context.mounted) ThemeChanger.setTheme(context, theme);
        }),
        _ThemeEntry(labelThemeAmoled, (BuildContext context) async {
          preferences.theme.set("amoled");
          var theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.dark);

          if (context.mounted) ThemeChanger.setTheme(context, theme);
        }),
      ];

  @override
  void initState() {
    entries = List.from(defaultThemes);
    initCustomThemes();
    super.initState();
  }

  @override
  void dispose() {
    customThemesDirSub?.cancel();
    super.dispose();
  }

  void initCustomThemes() async {
    loadCustomThemes();
    var dir = await ThemeConfig.getCustomThemesDir();
    customThemesDirSub =
        dir.watch(recursive: true).listen(onCustomThemesDirUpdated);
  }

  void loadCustomThemes() async {
    var themes = await ThemeConfig.getCustomThemes();

    var customEntries = themes.map((e) {
      var name = path.basenameWithoutExtension(e.path);

      return _ThemeEntry(
        name,
        (context) async {
          var file = await ThemeConfig.getFileFromThemeDir(e);
          if (file != null) {
            if (context.mounted) ThemeChanger.setThemeFromFile(context, file);
            preferences.theme.set(name);
          }
        },
        builder: (context, child) {
          if (MediaQuery.sizeOf(context).mobile)
            return GestureDetector(
              onLongPress: () => AdaptiveDialog.show(
                context,
                title: name,
                builder: (context) {
                  return Column(
                    children: [
                      tiamat.TextButton(
                        CommonStrings.promptDelete,
                        icon: Icons.delete,
                        onTap: () {
                          ThemeConfig.removeTheme(e);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              ),
              child: child,
            );

          return tiamat.ContextMenu(
            items: [
              ContextMenuItem(
                  text: CommonStrings.promptDelete,
                  onPressed: () => ThemeConfig.removeTheme(e)),
            ],
            child: child,
          );
        },
      );
    });
    var newEntries = List<_ThemeEntry>.from(defaultThemes);
    newEntries.addAll(customEntries);

    setState(() {
      entries = newEntries;
    });
  }

  void onCustomThemesDirUpdated(FileSystemEvent event) {
    Log.i("Themes dir updated, reloading items!");
    loadCustomThemes();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var entry in entries)
          entry.builder(
              context,
              tiamat.TextButton(entry.name,
                  onTap: () => entry.setter(context))),
        // Themes are installed into the app's folder, which a browser has
        // none of.
        if (BuildConfig.WEB)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DesktopAppNotice(labelSettingsCustomThemesDesktopAppNotice),
          )
        else
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                tiamat.CircleButton(
                  icon: Icons.add,
                  onPressed: () async {
                    var result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ["zip"],
                        dialogTitle: labelSettingsPickThemeArchive);

                    var file = result?.files.firstOrNull;
                    if (file?.path == null) {
                      return;
                    }

                    File f = File(file!.path!);
                    await ThemeConfig.installThemeFromZip(f);
                  },
                ),
              ],
            ),
          )
      ],
    );
  }
}
