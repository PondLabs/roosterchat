import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/config/languages.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/language/app_language.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Picks the language the app is shown in: the system's, or one of
/// [Languages.supported], each under its own name. It applies at once.
class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key});

  static String get labelSettingsLanguage => Intl.message("Language",
      name: "labelSettingsLanguage",
      desc: "Header of the setting that picks the language the app is in");

  static String get labelSettingsLanguageDescription => Intl.message(
      "The language of Rooster's menus, buttons and notices. Messages stay in the language they were written in.",
      name: "labelSettingsLanguageDescription",
      desc: "Explains the language setting, under its header");

  static String labelSettingsLanguageSystem(String language) => Intl.message(
      "Same as the system ($language)",
      name: "labelSettingsLanguageSystem",
      args: [language],
      desc:
          "Option of the language setting that follows the system's language. In brackets, the language it stands for now, under its own name, such as 'English' or 'Português (Brasil)'");

  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  /// The system's option, among the languages' codes.
  static const _system = "";

  String _label(String code) => code == _system
      ? LanguageSettings.labelSettingsLanguageSystem(AppLanguage.system.name)
      : Languages.byCode(code)!.name;

  @override
  Widget build(BuildContext context) {
    final picked = Languages.byCode(preferences.language.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(
              LanguageSettings.labelSettingsLanguageDescription),
          const SizedBox(height: 8),
          DropdownSelector<String>(
            items: [
              _system,
              ...Languages.supported.map((language) => language.code),
            ],
            value: picked?.code ?? _system,
            itemBuilder: (code) => tiamat.Text.label(_label(code),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onItemSelected: (code) async {
              if (code == null) return;
              await AppLanguage.pick(Languages.byCode(code));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
