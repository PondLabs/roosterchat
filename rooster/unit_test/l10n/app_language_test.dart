import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:rooster/config/languages.dart';
import 'package:rooster/debug/l10n_debug_lookup.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/language/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Languages.resolve', () {
    Language resolve(List<Locale> preferred, {String? picked}) =>
        Languages.resolve(picked: picked, preferred: preferred);

    test('the language picked in settings comes first', () {
      expect(resolve(const [Locale('en', 'US')], picked: 'pt'),
          Languages.portuguese);
    });

    test('a picked language Rooster no longer has falls back to the system',
        () {
      expect(resolve(const [Locale('pt', 'BR')], picked: 'de'),
          Languages.portuguese);
    });

    test('every Portuguese gets the Brazilian translation', () {
      expect(resolve(const [Locale('pt', 'BR')]), Languages.portuguese);
      expect(resolve(const [Locale('pt', 'PT')]), Languages.portuguese);
      expect(resolve(const [Locale('pt')]), Languages.portuguese);
    });

    test('the first of the system\'s languages that Rooster has wins', () {
      expect(resolve(const [Locale('de', 'DE'), Locale('pt', 'BR')]),
          Languages.portuguese);
      expect(resolve(const [Locale('en', 'GB'), Locale('pt', 'BR')]),
          Languages.english);
    });

    test('anything else is English', () {
      expect(resolve(const [Locale('de'), Locale('ja')]), Languages.english);
      expect(resolve(const []), Languages.english);
    });

    test('codes with a region or a script make the right locale', () {
      expect(const Language('pt_PT', '').locale, const Locale('pt', 'PT'));
      expect(const Language('zh_Hant', '').locale,
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
      expect(Languages.portuguese.tag, 'pt-BR');
      expect(Languages.english.tag, 'en');
    });
  });

  group('AppLanguage', () {
    Future<void> start(Map<String, Object> values) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(values);
      await preferences.init();
      await AppLanguage.load();
    }

    tearDown(() => start({}));

    test('loads the language picked in settings', () async {
      await start({'flutter.app_language': 'pt'});
      expect(AppLanguage.current.value, Languages.portuguese);
      expect(Intl.defaultLocale, 'pt');
      expect(CommonStrings.promptCancel, 'Cancelar');
    });

    test('switches while the app runs', () async {
      await start({'flutter.app_language': 'pt'});
      await AppLanguage.pick(Languages.english);
      expect(CommonStrings.promptCancel, 'Cancel');
      expect(preferences.language.value, 'en');

      await AppLanguage.pick(Languages.portuguese);
      expect(CommonStrings.promptCancel, 'Cancelar');

      await AppLanguage.pick(null);
      expect(preferences.language.value, isNull);
    });

    test('shows the keys instead of the text', () async {
      await start({'flutter.enable_translations_debug': true});
      expect(CommonStrings.promptCancel, 'promptCancel');
    });

    test('pseudo-translates the English', () async {
      await start({
        'flutter.app_language': 'pt',
        'flutter.enable_pseudo_translations': true,
      });
      expect(AppLanguage.current.value, Languages.english);
      expect(CommonStrings.promptCancel, pseudoTranslate('Cancel'));
    });
  });

  group('pseudoTranslate', () {
    test('accents, stretches and brackets the text', () {
      final text = pseudoTranslate('Join call');
      expect(text, startsWith('[Ĵöíñ çáľľ '));
      expect(text, endsWith(']'));
      expect(text.length, greaterThan('Join call'.length * 1.5));
    });

    test('leaves links alone', () {
      expect(pseudoTranslate('See https://example.com/a'),
          contains('https://example.com/a'));
    });
  });
}
