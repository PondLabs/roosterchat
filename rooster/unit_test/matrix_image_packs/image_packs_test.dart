// Image packs read from the stable Matrix v1.19 types (MSC2545) and the
// legacy im.ponies.* ones, the stable ones winning without duplicates, and
// written to the stable types only.
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/emoticon/emoji_pack.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_emoticon_pack.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_image_pack_types.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

const _roomId = '!1234:fakeServer.notExisting';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  late RecordingTransport transport;
  late MatrixClient client;
  late MatrixRoom room;
  var n = 0;

  setUp(() async {
    transport = RecordingTransport();
    client = await fakeAccount('image_packs_${n++}', transport);
    room = await plainRoom(client);
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  MatrixRoomEmoticonComponent roomPacks() =>
      room.getComponent<RoomEmoticonComponent>()!
          as MatrixRoomEmoticonComponent;

  MatrixEmoticonComponent personal() =>
      client.getComponent<EmoticonComponent>()! as MatrixEmoticonComponent;

  Map<String, List<String>> shortcodesByPack(Iterable<EmoticonPack> packs) => {
        for (final p in packs.cast<MatrixEmoticonPack>())
          p.identifier: [for (final e in p.emotes) e.shortcode!],
      };

  group('room packs', () {
    test('are read from m.room.image_pack alone', () async {
      await syncIn(client, state: [
        (
          type: 'm.room.image_pack',
          stateKey: 'cats',
          content: pack('Cats', {'cat': 'mxc://x/cat'}),
        ),
      ]);

      final packs = roomPacks().ownedPacks;
      expect(shortcodesByPack(packs), {
        'cats': ['cat'],
      });
      expect(packs.single.displayName, 'Cats');
    });

    test('are read from the legacy im.ponies.room_emotes alone', () async {
      await syncIn(client, state: [
        (
          type: 'im.ponies.room_emotes',
          stateKey: 'dogs',
          content: pack('Dogs', {'dog': 'mxc://x/dog'}),
        ),
      ]);

      expect(shortcodesByPack(roomPacks().ownedPacks), {
        'dogs': ['dog'],
      });
    });

    test(
        'with both types, the stable pack wins its state key and the others '
        'are kept, none twice', () async {
      await syncIn(client, state: [
        (
          type: 'im.ponies.room_emotes',
          stateKey: 'shared',
          content: pack('Old', {'old': 'mxc://x/old'}),
        ),
        (
          type: 'im.ponies.room_emotes',
          stateKey: 'legacy_only',
          content: pack('Legacy', {'l': 'mxc://x/l'}),
        ),
        (
          type: 'm.room.image_pack',
          stateKey: 'shared',
          content: pack('New', {'new': 'mxc://x/new'}),
        ),
      ]);

      final packs = roomPacks().ownedPacks;
      expect(shortcodesByPack(packs), {
        'shared': ['new'],
        'legacy_only': ['l'],
      });
      expect(packs.map((p) => p.identifier).toList(), hasLength(2));
      expect(
          packs.firstWhere((p) => p.identifier == 'shared').displayName, 'New');
    });

    test('an emptied stable pack hides the legacy one with its state key',
        () async {
      await syncIn(client, state: [
        (
          type: 'im.ponies.room_emotes',
          stateKey: 'gone',
          content: pack('Gone', {'g': 'mxc://x/g'}),
        ),
        (type: 'm.room.image_pack', stateKey: 'gone', content: {}),
      ]);

      expect(roomPacks().ownedPacks, isEmpty);
    });

    test('an image without a url is skipped, not a crash', () async {
      await syncIn(client, state: [
        (
          type: 'm.room.image_pack',
          stateKey: 'mixed',
          content: {
            'pack': {'display_name': 'Mixed'},
            'images': {
              'ok': {'url': 'mxc://x/ok'},
              'no_url': {'body': 'broken'},
              'bad_url': {'url': 7},
            },
          },
        ),
      ]);

      expect(shortcodesByPack(roomPacks().ownedPacks), {
        'mixed': ['ok'],
      });
    });

    test('a new pack is written to m.room.image_pack only', () async {
      await roomPacks().createEmoticonPack('Birds', null);

      final stable = transport.putsTo('/state/m.room.image_pack/Birds');
      expect(stable, [
        {
          'pack': {'display_name': 'Birds'},
        },
      ]);
      expect(transport.putsTo('/state/im.ponies.room_emotes/Birds'), isEmpty);
      roomPacks().refreshOwnedPacks();
      expect(shortcodesByPack(roomPacks().ownedPacks), {'Birds': <String>[]});
    });

    test('editing a legacy pack writes it to m.room.image_pack', () async {
      await syncIn(client, state: [
        (
          type: 'im.ponies.room_emotes',
          stateKey: 'dogs',
          content: pack('Dogs', {'dog': 'mxc://x/dog', 'pup': 'mxc://x/pup'}),
        ),
      ]);

      await roomPacks().deleteEmoticon('dogs', 'pup');

      expect(transport.putsTo('/state/m.room.image_pack/dogs'), [
        pack('Dogs', {'dog': 'mxc://x/dog'}),
      ]);
      expect(
          transport.puts.where((p) => p.path.contains('im.ponies')), isEmpty);
      roomPacks().refreshOwnedPacks();
      expect(shortcodesByPack(roomPacks().ownedPacks), {
        'dogs': ['dog'],
      });
    });

    test('the permission checked is the one of the type written', () {
      expect(MatrixEmoticonComponent.roomEmotesStateKey, 'm.room.image_pack');
      expect(
          client
              .getMatrixClient()
              .importantStateEvents
              .containsAll({'m.room.image_pack', 'im.ponies.room_emotes'}),
          isTrue);
    });
  });

  group('the personal pack', () {
    test('is read from m.image_pack alone', () async {
      await syncIn(client, accountData: {
        'm.image_pack': pack('Mine', {'me': 'mxc://x/me'}),
      });

      expect(shortcodesByPack(personal().ownedPacks), {
        ImagePackTypes.userPackKey: ['me'],
      });
    });

    test('is read from the legacy im.ponies.user_emotes alone', () async {
      await syncIn(client, accountData: {
        'im.ponies.user_emotes': pack('Old mine', {'old': 'mxc://x/old'}),
      });

      expect(shortcodesByPack(personal().ownedPacks), {
        ImagePackTypes.userPackKey: ['old'],
      });
    });

    test('with both, is the stable one, once', () async {
      await syncIn(client, accountData: {
        'im.ponies.user_emotes': pack('Old mine', {'old': 'mxc://x/old'}),
        'm.image_pack': pack('Mine', {'me': 'mxc://x/me'}),
      });

      final packs = personal().ownedPacks;
      expect(packs, hasLength(1));
      expect(packs.single.displayName, 'Mine');
      expect(shortcodesByPack(packs), {
        ImagePackTypes.userPackKey: ['me'],
      });
    });

    test('is written to m.image_pack only', () async {
      await syncIn(client, accountData: {
        'im.ponies.user_emotes': pack('Old mine', {'old': 'mxc://x/old'}),
      });

      await personal().deleteEmoticon(ImagePackTypes.userPackKey, 'old');

      expect(transport.putsTo('/account_data/m.image_pack'), [
        pack('Old mine', {}),
      ]);
      expect(
          transport.puts.where((p) => p.path.contains('im.ponies')), isEmpty);
    });
  });

  group('packs enabled everywhere', () {
    Future<void> roomHasPacks() => syncIn(client, state: [
          (
            type: 'm.room.image_pack',
            stateKey: 'cats',
            content: pack('Cats', {'cat': 'mxc://x/cat'}),
          ),
          (
            type: 'im.ponies.room_emotes',
            stateKey: 'dogs',
            content: pack('Dogs', {'dog': 'mxc://x/dog'}),
          ),
        ]);

    test('are read from m.image_pack.rooms alone', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'm.image_pack.rooms': {
          'rooms': {
            _roomId: {'cats': {}},
          },
        },
      });

      expect(shortcodesByPack(personal().globalPacks()), {
        'cats': ['cat'],
      });
      expect(
          (roomPacks().ownedPacks.cast<MatrixEmoticonPack>())
              .map((p) => (p.identifier, p.isGloballyAvailable))
              .toSet(),
          {('cats', true), ('dogs', false)});
    });

    test('are read from the legacy im.ponies.emote_rooms alone', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'im.ponies.emote_rooms': {
          'rooms': {
            _roomId: {'dogs': {}},
          },
        },
      });

      expect(shortcodesByPack(personal().globalPacks()), {
        'dogs': ['dog'],
      });
    });

    test('with both lists, come from the stable one only', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'im.ponies.emote_rooms': {
          'rooms': {
            _roomId: {'dogs': {}, 'cats': {}},
          },
        },
        'm.image_pack.rooms': {
          'rooms': {
            _roomId: {'cats': {}},
          },
        },
      });

      final global = personal().globalPacks();
      expect(shortcodesByPack(global), {
        'cats': ['cat'],
      });
      expect(global, hasLength(1));
    });

    test('a malformed list is read as empty', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'm.image_pack.rooms': {
          'rooms': {_roomId: 'not a map'},
        },
      });

      expect(personal().globalPacks(), isEmpty);
    });

    test(
        'turning one on writes m.image_pack.rooms, carrying the legacy list '
        'over', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'im.ponies.emote_rooms': {
          'rooms': {
            _roomId: {'dogs': {}},
          },
        },
      });

      await roomPacks().markAsGlobal(true, 'cats');

      expect(transport.putsTo('/account_data/m.image_pack.rooms'), [
        {
          'rooms': {
            _roomId: {'dogs': {}, 'cats': {}},
          },
        },
      ]);
      expect(
          transport.puts.where((p) => p.path.contains('im.ponies')), isEmpty);
      expect(shortcodesByPack(personal().globalPacks()).keys.toSet(),
          {'dogs', 'cats'});
    });

    test('turning the last one off drops the room from the list', () async {
      await roomHasPacks();
      await syncIn(client, accountData: {
        'm.image_pack.rooms': {
          'rooms': {
            _roomId: {'cats': {}},
          },
        },
      });

      final cats = roomPacks()
          .ownedPacks
          .firstWhere((p) => p.identifier == 'cats') as MatrixEmoticonPack;
      await cats.markAsGlobal(false);

      expect(transport.putsTo('/account_data/m.image_pack.rooms'), [
        {'rooms': {}},
      ]);
      expect(personal().globalPacks(), isEmpty);
    });
  });
}
