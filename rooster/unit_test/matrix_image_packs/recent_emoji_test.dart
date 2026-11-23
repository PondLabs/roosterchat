// Recently typed emoji read from m.recent_emoji (Matrix v1.18, MSC4356) or,
// without it, the legacy chat.commet.recent_emoji, and written as
// {recent_emoji: [{emoji, total}]}.
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:rooster/client/matrix/components/emoticon_recent/matrix_recent_emoticon_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

typedef _C = MatrixRecentEmoticonComponent;

Map<String, matrix.BasicEvent> _accountData(Map<String, Object?> byType) => {
      for (final e in byType.entries)
        e.key: matrix.BasicEvent(
            type: e.key, content: Map<String, Object?>.from(e.value as Map)),
    };

List<(String, String?, String?, int)> _flat(List<RecentEmoji> recents) => [
      for (final r in recents)
        (r.key, r.customPackId, r.customPackRoomId, r.count),
    ];

void main() {
  group('reading', () {
    test('takes m.recent_emoji, its pack emoji beside it', () {
      final recents = _C.readTypedRecents(_accountData({
        'm.recent_emoji': {
          'recent_emoji': [
            {'emoji': '😀', 'total': 3},
            {'emoji': '🐔', 'total': 1},
          ],
          'chat.commet.custom_emoji': [
            {'key': 'cat', 'state_key': 'cats', 'room_id': '!r:x', 'count': 2},
          ],
        },
        'chat.commet.recent_emoji': {
          'recent_emoji': [
            {'key': '👻', 'count': 9},
          ],
        },
      }));

      expect(_flat(recents), [
        ('😀', null, null, 3),
        ('🐔', null, null, 1),
        ('cat', 'cats', '!r:x', 2),
      ]);
    });

    test('falls back to chat.commet.recent_emoji without m.recent_emoji', () {
      final recents = _C.readTypedRecents(_accountData({
        'chat.commet.recent_emoji': {
          'recent_emoji': [
            {'key': '👻', 'count': 9},
            {'key': 'me', 'state_key': 'im.ponies.user_emotes', 'count': 4},
          ],
        },
      }));

      expect(_flat(recents), [
        ('👻', null, null, 9),
        ('me', 'im.ponies.user_emotes', null, 4),
      ]);
    });

    test('is empty with neither', () {
      expect(_C.readTypedRecents({}), isEmpty);
    });

    test('leaves out corrupted m.recent_emoji entries and keeps the rest', () {
      final recents = _C.readTypedRecents(_accountData({
        'm.recent_emoji': {
          'recent_emoji': [
            'not an object',
            null,
            {'total': 2},
            {'emoji': 5, 'total': 2},
            {'emoji': '🔥', 'total': 'many'},
            {'emoji': '', 'total': 1},
            {'emoji': '✨', 'total': 7},
          ],
          'chat.commet.custom_emoji': [
            42,
            {'key': 'no_pack', 'count': 1},
            {'key': 'ok', 'state_key': 'p', 'count': 'x'},
          ],
        },
      }));

      expect(_flat(recents), [
        ('✨', null, null, 7),
        ('ok', 'p', null, 1),
      ]);
    });

    test('takes an m.recent_emoji that is not a list as empty', () {
      for (final value in [null, 'x', 3, <String, Object?>{}]) {
        expect(
            _C.readTypedRecents(_accountData({
              'm.recent_emoji': {'recent_emoji': value},
              'chat.commet.recent_emoji': {
                'recent_emoji': [
                  {'key': '👻'},
                ],
              },
            })),
            isEmpty,
            reason: '$value');
      }
    });

    test('leaves out corrupted legacy entries and keeps the rest', () {
      final recents = _C.readTypedRecents(_accountData({
        'chat.commet.recent_emoji': {
          'recent_emoji': [
            'x',
            {'key': 3},
            {'count': 2},
            {'key': ''},
            {'key': '🙂', 'count': 'two', 'state_key': 9, 'room_id': false},
          ],
        },
      }));

      expect(_flat(recents), [('🙂', null, null, 1)]);
      expect(
          _C.readTypedRecents(_accountData({
            'chat.commet.recent_emoji': {'recent_emoji': 'garbage'},
          })),
          isEmpty);
    });
  });

  group('writing', () {
    test('puts Unicode emoji in the v1.18 schema, most recent first', () {
      final content = _C.typedRecentsContent([
        RecentEmoji(key: '😀', count: 2),
        RecentEmoji(key: '🐔'),
      ]);

      expect(content, {
        'recent_emoji': [
          {'emoji': '😀', 'total': 2},
          {'emoji': '🐔', 'total': 1},
        ],
      });
    });

    test('keeps pack emoji out of the list, in their own key', () {
      final content = _C.typedRecentsContent([
        RecentEmoji(key: '😀'),
        RecentEmoji(key: 'cat', customPackId: 'cats', customPackRoomId: '!r'),
      ], previous: {
        'recent_emoji': [
          {'emoji': '🙃', 'total': 1},
        ],
        'other.client': true,
        'chat.commet.custom_emoji': [
          {'key': 'old', 'state_key': 'p', 'count': 1},
        ],
      });

      expect(content, {
        'recent_emoji': [
          {'emoji': '😀', 'total': 1},
        ],
        'other.client': true,
        'chat.commet.custom_emoji': [
          {'key': 'cat', 'state_key': 'cats', 'room_id': '!r', 'count': 1},
        ],
      });
      // What is written reads back the same.
      expect(
          _flat(_C.readTypedRecents(_accountData({'m.recent_emoji': content}))),
          [('😀', null, null, 1), ('cat', 'cats', '!r', 1)]);
    });

    test('moves an emoji used again to the front', () {
      final component = _C(_NoClient());
      var list = <RecentEmoji>[];
      list = component.addToList(RecentEmoji(key: 'a'), list);
      list = component.addToList(RecentEmoji(key: 'b'), list);
      list = component.addToList(RecentEmoji(key: 'a'), list);

      expect(_flat(list), [('a', null, null, 2), ('b', null, null, 1)]);
    });
  });

  group('the component', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() => sqfliteFfiInit());

    late RecordingTransport transport;
    late MatrixClient client;
    var n = 0;

    setUp(() async {
      transport = RecordingTransport();
      client = await fakeAccount('recent_emoji_${n++}', transport);
    });

    tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

    test(
        'migrates the legacy list to m.recent_emoji and does not write the '
        'legacy type', () async {
      await syncIn(client, accountData: {
        'chat.commet.recent_emoji': {
          'recent_emoji': [
            {'key': '👻', 'count': 9},
            'broken',
            {'key': 'me', 'state_key': 'im.ponies.user_emotes', 'count': 4},
          ],
        },
      });
      final component = client.getComponent<RecentEmoticonComponent>()! as _C;
      component.postLoginInit();

      await component.storeRecentlyTyped();

      expect(transport.putsTo('/account_data/m.recent_emoji'), [
        {
          'recent_emoji': [
            {'emoji': '👻', 'total': 9},
          ],
          'chat.commet.custom_emoji': [
            {'key': 'me', 'state_key': 'im.ponies.user_emotes', 'count': 4},
          ],
        },
      ]);
      expect(
          transport.putsTo('/account_data/chat.commet.recent_emoji'), isEmpty);
    });

    test('clearing writes an empty m.recent_emoji', () async {
      final component = client.getComponent<RecentEmoticonComponent>()! as _C;
      await component.clear();

      expect(transport.putsTo('/account_data/m.recent_emoji'), [
        {'recent_emoji': []},
      ]);
    });
  });
}

/// Enough of a client for [MatrixRecentEmoticonComponent.addToList], which
/// does not touch it.
class _NoClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
