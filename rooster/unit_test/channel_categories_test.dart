// A space's channels under headings, as on Discord: text channels and voice
// channels apart, and headings of the admin's own.
import 'package:rooster/client/components/space_categories/channel_categories.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Channel = ({String id, ChannelKind kind});

const _general = (id: '!general', kind: ChannelKind.text);
const _rules = (id: '!rules', kind: ChannelKind.text);
const _lounge = (id: '!lounge', kind: ChannelKind.voice);
const _stage = (id: '!stage', kind: ChannelKind.voice);
const _memes = (id: '!memes', kind: ChannelKind.text);

/// The space's channels in its own order: voice and text mixed.
const _channels = <_Channel>[_lounge, _general, _rules, _stage, _memes];

/// Each heading as "id: its channels".
List<String> _sections(ChannelCategories categories,
        [List<_Channel> channels = _channels]) =>
    [
      for (final section in categories.layout<_Channel>(channels,
          idOf: (c) => c.id, kindOf: (c) => c.kind))
        '${section.category.id}: '
                '${[for (final c in section.channels) c.id].join(' ')}'
            .trim(),
    ];

void main() {
  test('with no headings set, text channels come first, then voice', () {
    expect(_sections(ChannelCategories.defaults), [
      'text: !general !rules !memes',
      'voice: !lounge !stage',
    ]);
  });

  test('an empty built-in heading is left out', () {
    expect(_sections(ChannelCategories.defaults, [_general, _rules]), [
      'text: !general !rules',
    ]);
  });

  test("a heading of the admin's holds its channels, text before voice", () {
    final categories = ChannelCategories.fromJson({
      'categories': [
        {
          'id': 'info',
          'name': 'Info',
          'rooms': ['!stage', '!rules'],
        },
        {'id': 'text'},
        {'id': 'voice'},
      ],
    });

    expect(_sections(categories), [
      'info: !rules !stage',
      'text: !general !memes',
      'voice: !lounge',
    ]);
  });

  test("an empty heading of the admin's still shows, to put channels under",
      () {
    final categories = ChannelCategories.defaults.withCategoryAdded('x', 'X');
    expect(_sections(categories).first, 'x:');
  });

  test('a list missing a built-in heading gets it back at the end', () {
    final categories = ChannelCategories.fromJson({
      'categories': [
        {'id': 'voice', 'name': 'Hangouts'},
        {
          'id': 'info',
          'name': 'Info',
          'rooms': ['!rules'],
        },
      ],
    });

    expect([for (final c in categories.categories) c.id],
        ['voice', 'info', 'text']);
    expect(categories.byId('voice')!.name, 'Hangouts');
    expect(_sections(categories).last, 'text: !general !memes');
  });

  test('malformed content is read as far as it goes', () {
    final categories = ChannelCategories.fromJson({
      'categories': [
        'nonsense',
        {'name': 'no id'},
        {'id': 'a', 'name': '  ', 'rooms': 'not a list'},
        {
          'id': 'a',
          'name': 'Repeated',
          'rooms': ['!general'],
        },
        {
          'id': 'b',
          'rooms': ['!general', 3, null],
        },
      ],
    });

    expect([for (final c in categories.categories) c.id],
        ['a', 'b', 'text', 'voice']);
    expect(categories.byId('a')!.name, isNull);
    expect(categories.byId('a')!.roomIds, isEmpty);
    expect(categories.byId('b')!.roomIds, ['!general']);
    expect(ChannelCategories.fromJson(null).categories.length, 2);
    expect(ChannelCategories.fromJson({'categories': 5}).categories.length, 2);
  });

  test('a channel listed under two headings shows under the first', () {
    final categories = ChannelCategories.fromJson({
      'categories': [
        {
          'id': 'a',
          'rooms': ['!general'],
        },
        {
          'id': 'b',
          'rooms': ['!general'],
        },
      ],
    });

    final sections = _sections(categories, [_general]);
    expect(sections, ['a: !general', 'b:']);
  });

  test('what it writes reads back the same', () {
    final categories = ChannelCategories.defaults
        .withCategoryAdded('info', 'Info')
        .withChannelIn('!rules', 'info')
        .withCategoryRenamed('voice', 'Hangouts');

    final json = categories.toJson();
    expect(json, {
      'categories': [
        {
          'id': 'info',
          'name': 'Info',
          'rooms': ['!rules'],
        },
        {'id': 'text'},
        {'id': 'voice', 'name': 'Hangouts'},
      ],
    });
    expect(ChannelCategories.fromJson(json).toJson(), json);
  });

  group('editing', () {
    final base = ChannelCategories.defaults
        .withCategoryAdded('info', 'Info')
        .withCategoryAdded('games', 'Games');

    test("a new heading goes after the admin's others, before the built-in",
        () {
      expect([for (final c in base.categories) c.id],
          ['info', 'games', 'text', 'voice']);
    });

    test('a channel moves from one heading to another', () {
      final categories = base
          .withChannelIn('!lounge', 'info')
          .withChannelIn('!lounge', 'games');

      expect(categories.byId('info')!.roomIds, isEmpty);
      expect(categories.byId('games')!.roomIds, ['!lounge']);
      expect(categories.categoryOf('!lounge', ChannelKind.voice).id, 'games');
    });

    test('a channel put under a built-in heading leaves the admin\'s', () {
      final categories = base
          .withChannelIn('!lounge', 'info')
          .withChannelIn('!lounge', ChannelCategory.voiceId);

      expect(categories.customCategoryOf('!lounge'), isNull);
      expect(categories.categoryOf('!lounge', ChannelKind.voice).id, 'voice');
    });

    test('a removed heading gives its channels back to the built-in ones', () {
      final categories = base
          .withChannelIn('!rules', 'info')
          .withChannelIn('!stage', 'info')
          .withCategoryRemoved('info');

      expect(categories.byId('info'), isNull);
      expect(_sections(categories), [
        'games:',
        'text: !general !rules !memes',
        'voice: !lounge !stage',
      ]);
    });

    test('a built-in heading cannot be removed', () {
      expect(base.withCategoryRemoved('text').byId('text'), isNotNull);
    });

    test('renaming a built-in heading to nothing gives it its name back', () {
      final renamed = base.withCategoryRenamed('text', 'Chat');
      expect(renamed.byId('text')!.name, 'Chat');
      expect(
          renamed.withCategoryRenamed('text', ' ').byId('text')!.name, isNull);
    });

    test("renaming an admin's heading to nothing keeps its name", () {
      expect(base.withCategoryRenamed('info', '').byId('info')!.name, 'Info');
      expect(
          base.withCategoryRenamed('info', ' FAQ ').byId('info')!.name, 'FAQ');
    });

    test('headings move up and down, and stop at the ends', () {
      List<String> ids(ChannelCategories c) =>
          [for (final category in c.categories) category.id];

      expect(ids(base.withCategoryMoved('games', -1)),
          ['games', 'info', 'text', 'voice']);
      expect(ids(base.withCategoryMoved('info', 1)),
          ['games', 'info', 'text', 'voice']);
      expect(ids(base.withCategoryMoved('voice', -3)),
          ['voice', 'info', 'games', 'text']);
      expect(ids(base.withCategoryMoved('info', -1)), ids(base));
      expect(ids(base.withCategoryMoved('voice', 1)), ids(base));
    });
  });
}
