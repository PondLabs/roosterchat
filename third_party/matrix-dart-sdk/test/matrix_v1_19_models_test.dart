// ROOSTER: Tests for the Matrix v1.18-v1.19 event and account data models
// (T1.1b).

import 'dart:convert';

import 'package:test/test.dart';

import 'package:matrix/matrix_api_lite.dart';

/// Encodes and decodes, so a model's toJson is checked as wire JSON.
Map<String, Object?> wire(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  Logs().level = Level.error;

  test('1. EventTypes constants match the stable v1.18-v1.19 names', () {
    expect(EventTypes.RoomImagePack, 'm.room.image_pack');
    expect(EventTypes.ImagePackRooms, 'm.image_pack.rooms');
    expect(EventTypes.RecentEmoji, 'm.recent_emoji');
    expect(EventTypes.KeyBackup, 'm.key_backup');
    expect(EventTypes.InvitePermissionConfig, 'm.invite_permission_config');
    expect(EventTypes.RoomPolicy, 'm.room.policy');
    expect(EventTypes.RoomKeyBundle, 'm.room_key_bundle');
    expect(EventTypes.RtcMember, 'm.rtc.member');
  });

  group('2. Models round trip', () {
    test('m.room.image_pack: full payload', () {
      final json = {
        'images': {
          'party': {
            'url': 'mxc://example.org/party',
            'body': 'Party parrot',
            'info': {
              'mimetype': 'image/gif',
              'size': 1024,
              'w': 64,
              'h': 64,
              'is_animated': true,
              'com.example.extra': 1,
            },
            'usage': ['emoticon', 'com.example.usage'],
            'com.example.image': 'kept',
          },
        },
        'pack': {
          'display_name': 'Birds',
          'avatar_url': 'mxc://example.org/avatar',
          'usage': ['sticker'],
          'attribution': 'CC-BY',
          'com.example.pack': true,
        },
        'com.example.root': [1, 2],
      };
      final content = MatrixImagePackContent.fromJson(json);
      final party = content.images['party']!;
      expect(party.url, 'mxc://example.org/party');
      expect(party.body, 'Party parrot');
      expect(party.info?.isAnimated, isTrue);
      expect(party.info?.mimetype, 'image/gif');
      expect(party.usage, [ImagePackUsageTypes.emoticon, 'com.example.usage']);
      expect(content.pack?.displayName, 'Birds');
      expect(content.pack?.usage, [ImagePackUsageTypes.sticker]);
      expect(content.pack?.attribution, 'CC-BY');
      expect(wire(content.toJson()), json);
    });

    test('m.room.image_pack: optional fields absent', () {
      final content = MatrixImagePackContent.fromJson({
        'images': {
          'a': {'url': 'mxc://example.org/a'},
        },
      });
      expect(content.pack, isNull);
      expect(content.images['a']!.body, isNull);
      expect(content.images['a']!.info, isNull);
      expect(content.images['a']!.usage, isNull);
      expect(content.toJson(), {
        'images': {
          'a': {'url': 'mxc://example.org/a'},
        },
      });
      expect(MatrixImagePackContent.fromJson({}).images, isEmpty);
    });

    test('m.room.image_pack: malformed input does not throw', () {
      final content = MatrixImagePackContent.fromJson({
        'images': {
          'no_url': {'body': 'x'},
          'bad_url': {'url': 5},
          'not_a_map': 'mxc://example.org/x',
          'ok': {
            'url': 'mxc://example.org/ok',
            'body': 7,
            'info': 'nope',
            'usage': 'emoticon',
          },
        },
        'pack': 'not a map',
      });
      expect(content.images.keys, ['ok']);
      expect(content.images['ok']!.body, isNull);
      expect(content.images['ok']!.info, isNull);
      expect(content.images['ok']!.usage, isNull);
      expect(content.pack, isNull);
      expect(
        MatrixImagePackContent.fromJson({'images': []}).images,
        isEmpty,
      );
      expect(
        () => MatrixImagePackImage.fromJson({'url': 1}),
        throwsFormatException,
      );
      expect(
        MatrixImagePackInfo.fromJson({
          'display_name': 3,
          'usage': [1],
        }).toJson(),
        isEmpty,
      );
    });

    test('m.image_pack.rooms: full, absent and malformed', () {
      final json = {
        'rooms': {
          '!room:example.org': {'': {}, 'birds': {}},
        },
        'com.example': 'x',
      };
      final content = ImagePackRoomsContent.fromJson(json);
      expect(content.rooms['!room:example.org']!.keys, ['', 'birds']);
      expect(wire(content.toJson()), json);

      expect(ImagePackRoomsContent.fromJson({}).toJson(), {'rooms': {}});

      final bad = ImagePackRoomsContent.fromJson({
        'rooms': {
          '!a:example.org': 'nope',
          '!b:example.org': {'': 'nope', 'ok': {}},
        },
      });
      expect(bad.rooms.keys, ['!b:example.org']);
      expect(bad.rooms['!b:example.org']!.keys, ['ok']);
      expect(ImagePackRoomsContent.fromJson({'rooms': 1}).rooms, isEmpty);
    });

    test('m.recent_emoji: full, absent and malformed', () {
      final json = {
        'recent_emoji': [
          {'emoji': '😅', 'total': 7},
          {'emoji': '🐓', 'total': 1, 'com.example': true},
        ],
      };
      final content = RecentEmojiContent.fromJson(json);
      expect(content.recentEmoji.map((e) => e.emoji), ['😅', '🐓']);
      expect(content.recentEmoji.first.total, 7);
      expect(wire(content.toJson()), json);

      expect(RecentEmojiContent.fromJson({}).recentEmoji, isEmpty);

      final bad = RecentEmojiContent.fromJson({
        'recent_emoji': [
          ['😅', 7],
          {'emoji': 1, 'total': 2},
          {'emoji': '🙂'},
          {'emoji': '🙂', 'total': '3'},
          null,
          {'emoji': '👍', 'total': 2},
        ],
      });
      expect(bad.recentEmoji.map((e) => e.emoji), ['👍']);
      expect(
        RecentEmojiContent.fromJson({'recent_emoji': 'x'}).recentEmoji,
        isEmpty,
      );
    });

    test('m.key_backup: full, absent and malformed', () {
      final json = {'enabled': false, 'com.example': 1};
      final content = KeyBackupContent.fromJson(json);
      expect(content.enabled, isFalse);
      expect(wire(content.toJson()), json);
      expect(KeyBackupContent.fromJson({}).enabled, isNull);
      expect(KeyBackupContent.fromJson({}).toJson(), isEmpty);
      expect(KeyBackupContent.fromJson({'enabled': 'yes'}).enabled, isNull);
    });

    test('m.invite_permission_config: full, absent and malformed', () {
      final json = {'default_action': 'block', 'com.example': 1};
      final content = InvitePermissionConfigContent.fromJson(json);
      expect(content.defaultAction, InvitePermissionActions.block);
      expect(content.blocksInvites, isTrue);
      expect(wire(content.toJson()), json);

      final absent = InvitePermissionConfigContent.fromJson({});
      expect(absent.defaultAction, isNull);
      expect(absent.blocksInvites, isFalse);
      expect(absent.toJson(), isEmpty);

      final allow = InvitePermissionConfigContent.fromJson(
        {'default_action': InvitePermissionActions.allow},
      );
      expect(allow.blocksInvites, isFalse);
      final unknown = InvitePermissionConfigContent.fromJson(
        {'default_action': 'com.example.ask'},
      );
      expect(unknown.blocksInvites, isFalse);
      expect(unknown.toJson(), {'default_action': 'com.example.ask'});
      expect(
        InvitePermissionConfigContent.fromJson({'default_action': true})
            .defaultAction,
        isNull,
      );
    });

    test('m.room.policy: full, absent and malformed', () {
      final json = {
        'via': 'policy.example.org',
        'public_keys': {'ed25519': 'base64key'},
        'com.example': 1,
      };
      final content = RoomPolicyContent.fromJson(json);
      expect(content.via, 'policy.example.org');
      expect(content.ed25519PublicKey, 'base64key');
      expect(wire(content.toJson()), json);

      final legacy = RoomPolicyContent.fromJson(
        {'via': 'policy.example.org', 'public_key': 'oldkey'},
      );
      expect(legacy.ed25519PublicKey, 'oldkey');

      final absent = RoomPolicyContent.fromJson({});
      expect(absent.via, isNull);
      expect(absent.ed25519PublicKey, isNull);
      expect(absent.toJson(), isEmpty);

      final bad = RoomPolicyContent.fromJson({
        'via': 1,
        'public_keys': {'ed25519': 2},
        'public_key': [],
      });
      expect(bad.via, isNull);
      expect(bad.publicKeys, isNull);
      expect(bad.ed25519PublicKey, isNull);
    });

    test('m.room_key_bundle: full, absent and malformed', () {
      final file = {
        'url': 'mxc://example.org/bundle',
        'key': {
          'kty': 'oct',
          'key_ops': ['encrypt', 'decrypt'],
          'alg': 'A256CTR',
          'k': 'secretkey',
          'ext': true,
        },
        'iv': 'iv',
        'hashes': {'sha256': 'hash'},
        'v': 'v2',
      };
      final json = {'room_id': '!room:example.org', 'file': file, 'x': 1};
      final content = RoomKeyBundleContent.fromJson(json);
      expect(content.roomId, '!room:example.org');
      expect(content.file['url'], 'mxc://example.org/bundle');
      expect(wire(content.toJson()), json);

      expect(RoomKeyBundleContent.tryFromJson({}), isNull);
      expect(() => RoomKeyBundleContent.fromJson({}), throwsFormatException);
      expect(
        () => RoomKeyBundleContent.fromJson({'room_id': '!r:example.org'}),
        throwsFormatException,
      );
      expect(
        RoomKeyBundleContent.tryFromJson(
          {'room_id': 1, 'file': file},
        ),
        isNull,
      );
      expect(
        RoomKeyBundleContent.tryFromJson(
          {'room_id': '!r:example.org', 'file': 'mxc://x'},
        ),
        isNull,
      );
    });

    test('m.rtc.member: full, absent and malformed', () {
      final json = {
        'slot_id': 'm.call#',
        'application': {'type': 'm.call', 'm.call.intent': 'audio'},
        'member': {
          'id': 'xyz',
          'user_id': '@alice:example.org',
          'device_id': 'DEVICE',
        },
        'rtc_transports': [
          {'type': 'livekit', 'livekit_service_url': 'https://lk.example.org'},
        ],
        'versions': ['v0'],
        'sticky_key': 'xyz',
      };
      final content = RtcMemberContent.fromJson(json);
      expect(content.slotId, 'm.call#');
      expect(content.application?.type, 'm.call');
      expect(content.member?.userId, '@alice:example.org');
      expect(content.member?.deviceId, 'DEVICE');
      expect(content.rtcTransports?.single['type'], 'livekit');
      expect(content.isLeave, isFalse);
      expect(wire(content.toJson()), json);

      final leave = RtcMemberContent.fromJson({});
      expect(leave.isLeave, isTrue);
      expect(leave.toJson(), isEmpty);

      final bad = RtcMemberContent.fromJson({
        'slot_id': 1,
        'application': 'm.call',
        'member': {'user_id': 2, 'device_id': 'D'},
        'rtc_transports': [
          'livekit',
          {'type': 'livekit'},
        ],
        'versions': [1],
      });
      expect(bad.slotId, isNull);
      expect(bad.application, isNull);
      expect(bad.member?.userId, isNull);
      expect(bad.member?.deviceId, 'D');
      expect(bad.rtcTransports, [
        {'type': 'livekit'},
      ]);
      expect(bad.versions, isNull);
    });

    test('MatrixImageInfo: absent and malformed is_animated', () {
      expect(MatrixImageInfo.fromJson({}).isAnimated, isNull);
      expect(MatrixImageInfo.fromJson({}).toJson(), isEmpty);
      final bad = MatrixImageInfo.fromJson({'is_animated': 'yes', 'w': '1'});
      expect(bad.isAnimated, isNull);
      expect(bad.w, isNull);
      expect(
        MatrixImageInfo(isAnimated: false).toJson(),
        {'is_animated': false},
      );
    });
  });

  group('3. MatrixEvent keeps replaces_state and is_animated', () {
    Map<String, Object?> event({
      Map<String, Object?>? unsigned,
      Map<String, Object?>? content,
    }) =>
        {
          'type': EventTypes.Sticker,
          'content': content ??
              {
                'body': 'parrot',
                'url': 'mxc://example.org/parrot',
                'info': {'mimetype': 'image/webp', 'is_animated': true},
              },
          'sender': '@alice:example.org',
          'event_id': r'$new',
          'room_id': '!room:example.org',
          'origin_server_ts': 1700000000000,
          if (unsigned != null) 'unsigned': unsigned,
        };

    test('round trip preserves both fields', () {
      final json = event(unsigned: {'replaces_state': r'$old', 'age': 5});
      final parsed = MatrixEvent.fromJson(wire(json));
      expect(parsed.replacesState, r'$old');
      expect(parsed.isAnimated, isTrue);
      expect(parsed.imageInfo?.mimetype, 'image/webp');

      final again = MatrixEvent.fromJson(wire(parsed.toJson()));
      expect(again.replacesState, r'$old');
      expect(again.isAnimated, isTrue);
      expect(wire(again.toJson()), json);
    });

    test('absent and malformed values read as null', () {
      final plain = MatrixEvent.fromJson(event(content: {'body': 'x'}));
      expect(plain.replacesState, isNull);
      expect(plain.imageInfo, isNull);
      expect(plain.isAnimated, isNull);
      expect(plain.toJson().containsKey('unsigned'), isFalse);

      final bad = MatrixEvent.fromJson(
        event(
          unsigned: {'replaces_state': 42},
          content: {'info': 'nope'},
        ),
      );
      expect(bad.replacesState, isNull);
      expect(bad.isAnimated, isNull);
      expect(
        MatrixEvent.fromJson(
          event(
            content: {
              'info': {'is_animated': 'true'},
            },
          ),
        ).isAnimated,
        isNull,
      );
    });

    test('replacesState setter writes and clears unsigned', () {
      final parsed = MatrixEvent.fromJson(event());
      parsed.replacesState = r'$old';
      expect(parsed.toJson()['unsigned'], {'replaces_state': r'$old'});
      parsed.replacesState = null;
      expect(parsed.toJson()['unsigned'], isEmpty);
    });
  });
}
