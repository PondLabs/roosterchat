// ignore: implementation_imports
import 'package:intl/src/intl_helpers.dart';

/// How strings are shown, for checking translations and layouts.
enum TranslationDebugMode {
  /// The translation, as normal.
  off,

  /// Each string's key instead of its text.
  keys,

  /// The English, accented and stretched to the length a long language
  /// takes, between brackets. Anything cut off, or still plain English, is
  /// a problem.
  pseudo,
}

/// Puts [mode] in front of the translations initializeMessages loaded.
/// Messages loaded afterwards go to the same translations underneath.
void setTranslationDebugMode(TranslationDebugMode mode) {
  final current = messageLookup;
  final translations = current is _DebugLookup ? current.translations : current;
  messageLookup = mode == TranslationDebugMode.off
      ? translations
      : _DebugLookup(translations, mode);
}

class _DebugLookup implements MessageLookup {
  _DebugLookup(this.translations, this.mode);

  final MessageLookup translations;
  final TranslationDebugMode mode;

  @override
  void addLocale(String localeName, Function findLocale) =>
      translations.addLocale(localeName, findLocale);

  @override
  String? lookupMessage(String? messageText, String? locale, String? name,
      List<Object>? args, String? meaning,
      {MessageIfAbsent? ifAbsent}) {
    if (mode == TranslationDebugMode.keys) return name ?? messageText;

    final text = translations.lookupMessage(
        messageText, locale, name, args, meaning,
        ifAbsent: ifAbsent);
    return text == null ? null : pseudoTranslate(text);
  }
}

// Each letter of _plain becomes the one at the same place in _accented:
// Latin-1 and Latin Extended-A only, which every bundled font has.
const _plain = 'acdeghijklnorstuwyzACDEGHIJKLNORSTUWYZ';
const _accented = 'áçďéğĥíĵķľñöřšťüŵýžÁÇĎÉĞĤÍĴĶĽÑÖŘŠŤÜŴÝŽ';

final _links = RegExp(r'https?://\S+');

/// [text] the way a long language would show it: accented, longer by as
/// much as translations grow (short strings grow the most), between
/// brackets so a cut-off end shows. Links are left as they are.
String pseudoTranslate(String text) {
  if (text.isEmpty) return text;

  final accented = text.splitMapJoin(_links,
      onMatch: (link) => link[0]!,
      onNonMatch: (part) => part.split('').map((char) {
            final index = _plain.indexOf(char);
            return index < 0 ? char : _accented[index];
          }).join());

  final length = text.length;
  final growth = length <= 10
      ? 0.8
      : length <= 20
          ? 0.6
          : length <= 50
              ? 0.4
              : 0.3;
  final padding = '~' * (length * growth).ceil();
  return '[$accented $padding]';
}
