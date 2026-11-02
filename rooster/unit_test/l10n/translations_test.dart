import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/config/languages.dart';

import '../../scripts/l10n/translations.dart';

// The rules of docs/localization.md that a test can hold: the English file
// is what the code says, every language that ships translates every string,
// and no English is left in a translation by mistake.

/// Translations that are the English on purpose: the same word in both
/// languages, or a name. Anything else that equals the English is a string
/// nobody translated. Strings with no word outside their placeholders
/// (`{start} – {end}`) need no entry.
const _sameAsEnglish = <String, Set<String>>{
  'pt': {
    // Kept in English by the glossary (docs/localization.md).
    'labelDjLinkCount',
    'labelDjSidebarDj',
    'labelDjSongLinkField',
    'labelDjSourceLink',
    'labelCallHistoryDjTime',
    'labelSettingsAppDj',
    'labelSettingsAppLogs',
    'labelSettingsAppSoundboard',
    'labelSoundboardDialogTitle',
    'labelSoundboardLink',
    'labelSpaceSoundboardSettings',
    'labelWidgetDebugLogs',
    'tooltipDjBadge',
    'tooltipGifButton',
    // The same word in Portuguese.
    'labelCallDurationHours',
    'labelEmojiPickerEmojiTab',
    'labelMediaVolume',
    'labelRoomEmoticonUsageEmoji',
    'labelRoomSettingsEmoticons',
    'labelSettingsTabEmoticons',
    'labelSpaceEmoticonSettings',
    'labelWidgetOpenConfirmTitle',
    'promptRoomWidgets',
    // Names: of keys, of sounds, of a protocol field.
    'labelChatKeyEnter',
    'labelEnableUnifiedPushEndpoint',
    'labelHomeQuickSwitcherShortcut',
    'labelSoundboardDefaultBonk',
    'labelSoundboardDefaultVineBoom',
  },
};

/// Placeholders, then whatever is left once they are gone.
final _placeholder = RegExp(r'\{\w+\}');
final _word = RegExp(r'[A-Za-z]{2,}');

void main() {
  final arbFiles = readArbFiles();
  final english = arbFiles[sourceLocale]!;

  test('intl_en.arb has exactly the code\'s strings', () {
    final warnings = <String>[];
    final extracted = extractEnglish(messageSources(), warnings: warnings);
    expect(warnings, isEmpty, reason: warnings.join('\n'));

    final differences = <String>[
      for (final key in {...extracted.keys, ...english.keys})
        if (jsonEncode(extracted[key]) != jsonEncode(english[key]))
          key.startsWith('@')
              ? '$key: the description or placeholders changed'
              : !english.containsKey(key)
                  ? '$key: new in the code'
                  : !extracted.containsKey(key)
                      ? '$key: no longer in the code'
                      : '$key: the English changed',
    ];
    if (differences.isEmpty &&
        jsonEncode(extracted.keys.toList()) !=
            jsonEncode(english.keys.toList())) {
      differences.add('the strings moved');
    }

    expect(differences, isEmpty,
        reason: 'assets/l10n/intl_en.arb is not what the code says. From '
            'rooster/, run `dart run scripts/extract_strings.dart`, then '
            'translate what it lists.\n${differences.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('no text in the interface is written straight into the code', () {
    final found = hardcodedStrings(messageSources());
    expect(found, isEmpty,
        reason: 'Make these Intl.messages (docs/localization.md, How a '
            'string is written). One that has to stay as it is (a unit, a '
            'protocol value) gets a "// $notTranslatedMarker <why>" comment '
            'on its line or right above it.\n${found.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('every language that ships has its translation, and only those', () {
    expect(arbFiles.keys.toSet(),
        Languages.supported.map((language) => language.code).toSet(),
        reason: 'Languages.supported (lib/config/languages.dart) and the '
            'ARB files in assets/l10n must name the same languages.');
  });

  for (final language in Languages.supported) {
    if (language.code == sourceLocale) continue;
    final translation = arbFiles[language.code] ?? const {};

    test('${language.name} translates every string', () {
      final problems = translationProblems(english, translation);
      expect(problems, isEmpty,
          reason: 'assets/l10n/intl_${language.code}.arb:\n'
              '${problems.join('\n')}');
    });

    test('${language.name} has no English left in it', () {
      final allowed = _sameAsEnglish[language.code] ?? const {};
      final untranslated = [
        for (final key in messageKeys(english))
          if (translation[key] == english[key] &&
              !allowed.contains(key) &&
              _word.hasMatch(
                  (english[key] as String).replaceAll(_placeholder, '')))
            '$key: ${english[key]}',
      ];
      expect(untranslated, isEmpty,
          reason: 'Translate these, or list them in _sameAsEnglish if the '
              'English is right in ${language.name} too:\n'
              '${untranslated.join('\n')}');

      final stale = [
        for (final key in allowed)
          if (translation[key] != english[key]) key,
      ];
      expect(stale, isEmpty,
          reason: 'No longer the same as the English; take them out of '
              '_sameAsEnglish.');
    });
  }
}
