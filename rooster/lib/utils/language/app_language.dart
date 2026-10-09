import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rooster/config/languages.dart';
import 'package:rooster/debug/l10n_debug_lookup.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/language/document_language.dart';

/// The language the app is shown in, and switching it while the app runs.
/// See docs/localization.md.
abstract final class AppLanguage {
  /// What the app is shown in. The app's root listens, for the Material
  /// widgets' own strings.
  static final ValueNotifier<Language> current =
      ValueNotifier(Languages.fallback);

  /// The language that "Same as the system" stands for: the first of the
  /// system's (or the browser's) languages that Rooster has.
  static Language get system =>
      Languages.resolve(preferred: PlatformDispatcher.instance.locales);

  static bool _listening = false;

  /// Loads the translations, before anything shows a string. Before the
  /// preferences are read (the loading window, which comes up before the
  /// data directory may be touched) that is the system's language.
  static Future<void> load() async {
    final settings = preferences.isInit ? preferences : null;
    final mode = settings == null
        ? TranslationDebugMode.off
        : settings.debugTranslations.value
            ? TranslationDebugMode.keys
            : settings.pseudoTranslations.value
                ? TranslationDebugMode.pseudo
                : TranslationDebugMode.off;

    // Pseudo-translations stretch the English, so that whatever is cut off,
    // or left untranslated, stands out.
    final language = mode == TranslationDebugMode.pseudo
        ? Languages.english
        : Languages.resolve(
            picked: settings?.language.value,
            preferred: PlatformDispatcher.instance.locales);

    // Awaited: on the web a first frame built before the translations
    // arrived showed the English until the next rebuild.
    await initializeMessages(language.code);
    await initializeDateFormatting(language.code);
    Intl.defaultLocale = language.code;
    setTranslationDebugMode(mode);
    setDocumentLanguage(language.tag);
    current.value = language;
  }

  /// Shows the app in [language] from now on, or in the system's when null.
  static Future<void> pick(Language? language) async {
    await preferences.language.set(language?.code);
    await reload();
  }

  /// Loads the translations again and builds every widget with them, so
  /// the change shows at once, without leaving the page. Text a widget
  /// keeps from before (a field's contents) stays as it was.
  static Future<void> reload() async {
    await load();
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;

    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    rebuild(root);
  }

  /// Keeps the app in step from now on: the debug views of the strings
  /// (Developer settings), and the system's languages when none is picked.
  /// Only where there is an interface to redraw; a background isolate
  /// loads once.
  static void follow() {
    if (_listening) return;
    _listening = true;

    preferences.debugTranslations.onChanged.listen((_) => reload());
    preferences.pseudoTranslations.onChanged.listen((_) => reload());
    WidgetsBinding.instance.addObserver(_SystemLanguageObserver());
  }
}

/// Follows the system's languages changing while the app runs (a browser's
/// language settings, say) while no language is picked.
class _SystemLanguageObserver with WidgetsBindingObserver {
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (preferences.language.value == null) AppLanguage.reload();
  }
}
