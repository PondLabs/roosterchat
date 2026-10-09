import 'dart:ui';

/// A language Rooster is translated into.
class Language {
  const Language(this.code, this.name, {String? tag}) : _tag = tag;

  /// The code of its translation, `assets/l10n/intl_<code>.arb`: the
  /// language, then a script or a region only where they differ from the
  /// language's default (`pt_PT`, `zh_Hant`).
  final String code;

  /// The language's name in itself, as the language picker lists it.
  final String name;

  final String? _tag;

  /// Its BCP 47 tag, for the web page's `lang`, where screen readers pick
  /// a voice by it.
  String get tag => _tag ?? code.replaceAll('_', '-');

  Locale get locale {
    final parts = code.split('_');
    final rest = parts.skip(1);
    return Locale.fromSubtags(
      languageCode: parts.first,
      scriptCode: rest.where((part) => part.length == 4).firstOrNull,
      countryCode: rest.where((part) => part.length != 4).firstOrNull,
    );
  }

  @override
  String toString() => code;
}

/// The languages Rooster ships. English is the source language: every
/// string is written in English in the code and translated from
/// `assets/l10n/intl_en.arb`. See docs/localization.md, which also says how
/// to add one.
abstract final class Languages {
  static const english = Language('en', 'English');

  /// Brazilian Portuguese. As in Flutter and CLDR, plain `pt` is Brazil's;
  /// European Portuguese would be `pt_PT`.
  static const portuguese = Language('pt', 'Português (Brasil)', tag: 'pt-BR');

  /// In the order the language picker lists them. Each one has its
  /// `assets/l10n/intl_<code>.arb`; `unit_test/l10n/translations_test.dart`
  /// checks the two lists agree.
  static const List<Language> supported = [english, portuguese];

  /// What anyone whose languages Rooster does not have gets.
  static const Language fallback = english;

  static Language? byCode(String? code) {
    if (code == null) return null;
    for (final language in supported) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// The language to show: [picked] in settings when Rooster has it, else
  /// the first of the system's [preferred] languages that Rooster has, else
  /// English.
  static Language resolve({String? picked, required List<Locale> preferred}) {
    final chosen = byCode(picked);
    if (chosen != null) return chosen;

    for (final locale in preferred) {
      final match = closest(locale);
      if (match != null) return match;
    }
    return fallback;
  }

  /// The translation closest to [locale]: its own script or region when
  /// Rooster has one (`pt_PT`), else its language (`pt` for `pt_PT` and
  /// `pt_BR` alike). Null when Rooster does not have the language at all.
  static Language? closest(Locale locale) {
    final language = locale.languageCode;
    return byCode(locale.scriptCode == null
            ? null
            : '${language}_${locale.scriptCode}') ??
        byCode(locale.countryCode == null
            ? null
            : '${language}_${locale.countryCode}') ??
        byCode(language);
  }
}
