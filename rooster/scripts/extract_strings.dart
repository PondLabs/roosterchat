// ignore_for_file: avoid_print

import 'dart:io';

import 'l10n/translations.dart';

/// Reads every `Intl.message` in the app (and in the calendar widget it
/// embeds) into assets/l10n/intl_en.arb, the file every translation
/// translates. Then puts each translation in the same order, drops the
/// strings the code no longer has, and lists what each one still needs.
/// See docs/localization.md.
///
/// From rooster/: `dart run scripts/extract_strings.dart`
void main() {
  final warnings = <String>[];
  final english = extractEnglish(messageSources(), warnings: warnings);
  warnings.forEach(print);

  writeArb(sourceLocale, english);
  print('${messageKeys(english).length} strings in '
      '${arbFile(sourceLocale).path}');

  readArbFiles().forEach((locale, arb) {
    if (locale == sourceLocale) return;

    final translation = syncTranslation(locale, english, arb);
    writeArb(locale, translation);

    final problems = translationProblems(english, translation);
    if (problems.isEmpty) {
      print('$locale: complete');
    } else {
      print('$locale: ${problems.length} to do');
      for (final problem in problems) {
        print('  $problem');
      }
    }
  });

  if (warnings.isNotEmpty) exit(1);
}
