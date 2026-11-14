import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

Map<String, Object?> card(String id, {String theme = 'animals'}) => {
      'id': id,
      'theme': theme,
      'kind': 'animal',
      'reach': 'world',
      'difficulty': 'easy',
    };

Map<String, Object?> text(String id, {String? name, String? caption}) =>
    {'id': id, 'name': name ?? 'Name of $id', 'caption': caption ?? 'a thing'};

void main() {
  List<String> check(List<Object?> cards, Map<String, List<Object?>> texts) =>
      Deck.check(cards: cards, texts: texts, languages: const ['en', 'pt']);

  final sound = [card('cat'), card('dog')];
  final soundTexts = {
    'en': [text('cat'), text('dog')],
    'pt': [text('cat'), text('dog')],
  };

  test('a sound deck has no problems', () {
    expect(check(sound, soundTexts), isEmpty);
  });

  test('an id written twice is a problem', () {
    expect(check([...sound, card('cat')], soundTexts),
        [contains('"cat" is in the deck twice')]);
    expect(
        check(sound, {
          'en': [...soundTexts['en']!, text('dog')],
          'pt': soundTexts['pt']!,
        }),
        [contains('"dog" is written twice in en')]);
  });

  test('a card missing in a language is a problem', () {
    expect(
        check(sound, {
          'en': soundTexts['en']!,
          'pt': [text('cat')],
        }),
        ['"dog" has no pt text']);
    expect(
        check(sound, {
          'en': [text('cat')],
          'pt': soundTexts['pt']!,
        }),
        ['"dog" has no en text']);
    expect(check(sound, {'en': soundTexts['en']!}),
        containsAll(['no pt texts', '"cat" has no pt text']));
  });

  test('a name over 40 characters is a problem, 40 is not', () {
    final forty = 'ã' * 40;
    expect(
        check(sound, {
          'en': [text('cat', name: forty), text('dog')],
          'pt': [text('cat', name: '$forty!'), text('dog')],
        }),
        [startsWith('"cat" has a pt name longer than 40')]);
  });

  test('a caption over 60 characters is a problem, 60 is not', () {
    final sixty = 'é' * 60;
    expect(
        check(sound, {
          'en': [text('cat', caption: '${sixty}x'), text('dog')],
          'pt': [text('cat', caption: sixty), text('dog')],
        }),
        [startsWith('"cat" has a en caption longer than 60')]);
  });

  test('an empty name or caption is a problem', () {
    expect(
        check(sound, {
          'en': soundTexts['en']!,
          'pt': [text('cat', name: ' '), text('dog')],
        }),
        ['"cat" has an empty pt name or caption']);
  });

  test('an unknown theme, kind, reach or difficulty is a problem', () {
    for (final (field, value) in [
      ('theme', 'history'),
      ('kind', 'plant'),
      ('reach', 'pt'),
      ('difficulty', 'impossible'),
    ]) {
      expect(
          check([
            card('cat'),
            {...card('dog'), field: value}
          ], soundTexts),
          ['"dog" has an unknown $field "$value"'],
          reason: field);
    }
  });

  test('a missing field is a problem', () {
    expect(
        check([
          card('cat'),
          {...card('dog')}..remove('kind')
        ], soundTexts),
        ['"dog" has no kind']);
  });

  test('text for a card the deck does not have is a problem', () {
    expect(
        check(sound, {
          'en': [...soundTexts['en']!, text('cow')],
          'pt': soundTexts['pt']!,
        }),
        ['en has text for "cow", which is no card']);
  });

  test('parsing refuses what it cannot read', () {
    expect(
        () => Deck.parse(cards: [card('cat'), card('cat')], texts: soundTexts),
        throwsFormatException);
    expect(
        () => Deck.parse(cards: [
              {...card('cat'), 'theme': 'history'}
            ], texts: soundTexts),
        throwsFormatException);
  });
}
