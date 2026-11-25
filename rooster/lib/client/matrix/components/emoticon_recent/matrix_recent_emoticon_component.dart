import 'package:collection/collection.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_image_pack_types.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRecentEmoticonComponent
    implements RecentEmoticonComponent<MatrixClient>, NeedsPostLoginInit {
  MatrixRecentEmoticonComponent(this.client);

  List<RecentEmoji> _reactionEmoji = List.empty(growable: true);
  List<RecentEmoji> _typedEmoji = List.empty(growable: true);

  Debouncer reactionDebouncer = Debouncer(delay: Duration(seconds: 5));
  Debouncer typedDebouncer = Debouncer(delay: Duration(seconds: 5));

  static const String reactionsKey = "chat.commet.recent_reaction_emoji";

  /// Recently typed emoji (Matrix v1.18, MSC4356), written. Its entries are
  /// Unicode emoji; ours from packs go in [customKey] beside them.
  static const String typedKey = matrix.EventTypes.RecentEmoji;

  /// What [typedKey] replaces, read when the account has no [typedKey].
  static const String legacyTypedKey = "chat.commet.recent_emoji";

  /// Emoji from packs in the [typedKey] content, as [RecentEmoji.toJson].
  static const String customKey = "chat.commet.custom_emoji";

  @override
  MatrixClient client;

  @override
  List<Emoticon> getRecentReactionEmoticon(Room room) {
    return toEmoticons(room, _reactionEmoji);
  }

  @override
  List<Emoticon> getRecentTypedEmoticon(Room? room) {
    return toEmoticons(room, _typedEmoji);
  }

  @override
  void postLoginInit() {
    var data = client.matrixClient.accountData[reactionsKey];
    if (data != null) {
      _reactionEmoji = toRecentsList(data);
      Log.i("Got ${_reactionEmoji.length} recent reaction emoji");
    }

    _typedEmoji = readTypedRecents(client.matrixClient.accountData);
    Log.i("Got ${_typedEmoji.length} recently typed emoji");
  }

  /// The recently typed emoji: from `m.recent_emoji` when the account has
  /// it, from the legacy `chat.commet.recent_emoji` otherwise. Entries that
  /// are not what the schema says are left out.
  static List<RecentEmoji> readTypedRecents(
      Map<String, matrix.BasicEvent> accountData) {
    final standard = accountData[typedKey];
    if (standard == null) {
      final legacy = accountData[legacyTypedKey];
      return legacy == null ? [] : toRecentsList(legacy);
    }

    final content = matrix.RecentEmojiContent.fromJson(standard.content);
    return [
      for (final entry in content.recentEmoji)
        if (entry.emoji.isNotEmpty)
          RecentEmoji(key: entry.emoji, count: entry.total),
      ..._parseList(content.additionalProperties[customKey])
          .where((e) => e.customPackId != null),
    ];
  }

  /// [recents] as `m.recent_emoji` content, most recent first, keeping what
  /// other clients put in [previous] beside the list.
  static Map<String, Object?> typedRecentsContent(List<RecentEmoji> recents,
      {Map<String, Object?>? previous}) {
    final kept = previous == null
        ? <String, Object?>{}
        : matrix.RecentEmojiContent.fromJson(previous).additionalProperties;
    final custom = recents.where((e) => e.customPackId != null).toList();
    return matrix.RecentEmojiContent(
      recentEmoji: [
        for (final e in recents)
          if (e.customPackId == null)
            matrix.RecentEmojiEntry(emoji: e.key, total: e.count),
      ],
      additionalProperties: {
        ...kept..remove(customKey),
        if (custom.isNotEmpty) customKey: [for (final e in custom) e.toJson()],
      },
    ).toJson();
  }

  List<Emoticon> toEmoticons(Room? room, List<RecentEmoji> emojis) {
    var result = List<Emoticon>.empty(growable: true);

    var comp = room?.getComponent<RoomEmoticonComponent>();

    var availablePacks = comp?.availablePacks ??
        client.getComponent<EmoticonComponent>()?.availablePacks;

    if (availablePacks == null) return [];

    emojis.sort((a, b) => b.count.compareTo(a.count));

    for (var emote in emojis) {
      if (emote.customPackId == null && emote.customPackRoomId == null) {
        result.add(UnicodeEmoticon(emote.key));
      }

      if (emote.customPackId != null) {
        for (var pack in availablePacks) {
          // this is a custom pack, it cant be in unicode
          if (pack is UnicodeEmoticonPack) continue;

          if (emote.customPackRoomId != null) {
            if (pack.ownerId != emote.customPackRoomId) continue;
          }

          if (pack.identifier == emote.customPackId) {
            var emoticon = pack.getByShortcode(emote.key);
            if (emoticon != null) {
              result.add(emoticon);
            }
          }
        }
      }
    }
    "❤️👍👎😂🔥😭🤣✨🙏💀😍🥺🥰😊😵‍💫😵🤩😎😘😅👏😁🤠💔💖💙🩷🤍💕😢🤔😆🙄💪😉☺️👌🤗"
        .characters
        .map((i) => UnicodeEmoticon(i.toString()))
        .forEach((i) {
      if (result.contains(i) == false) {
        result.add(i);
      }
    });

    return result;
  }

  RecentEmoji? toRecentEmoji(Room room, Emoticon emoticon) {
    String? customPackid;
    String? customPackRoomId;
    String key = emoticon.key;

    if (emoticon is UnicodeEmoticon) {
      return RecentEmoji(key: key);
    }

    if (emoticon is MatrixEmoticon) {
      if (emoticon.shortcode != null) {
        key = emoticon.shortcode!;
      }
      var comp = room.getComponent<RoomEmoticonComponent>();
      if (comp == null) {
        return null;
      }

      for (var pack in comp.availablePacks) {
        if (pack is DynamicEmoticonPack) continue;

        if (pack.emotes.contains(emoticon)) {
          customPackid = pack.identifier;
          if (customPackid != ImagePackTypes.userPackKey)
            customPackRoomId = pack.ownerId;
          break;
        }
      }

      if (customPackid == null) {
        return null;
      }
    }

    return RecentEmoji(
        key: key,
        customPackId: customPackid,
        customPackRoomId: customPackRoomId);
  }

  @override
  Future<void> reactedEmoticon(Room room, Emoticon emoticon) async {
    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null || emoji.key == "") return;

    _reactionEmoji = addToList(emoji, _reactionEmoji);
    reactionDebouncer.run(() => storeRecentReactions());
  }

  @override
  Future<void> typedEmoticon(Room room, Emoticon emoticon) async {
    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null) return;

    _typedEmoji = addToList(emoji, _typedEmoji);
    typedDebouncer.run(() => storeRecentlyTyped());
  }

  List<RecentEmoji> addToList(RecentEmoji emoji, List<RecentEmoji> list) {
    const maxLen = 30;

    if (list.length > maxLen) {
      list = list.sublist(0, maxLen);
    }

    var existing = list.firstWhereOrNull((i) =>
        i.customPackId == emoji.customPackId &&
        i.customPackRoomId == emoji.customPackRoomId &&
        i.key == emoji.key);

    // Most recent first, as m.recent_emoji keeps them.
    if (existing != null) {
      existing.count++;
      list.remove(existing);
      list.insert(0, existing);
    } else {
      list.insert(0, emoji);
    }

    return list;
  }

  Future<void> storeRecentReactions() async {
    var content = {
      "recent_emoji": _reactionEmoji.map((i) => i.toJson()).toList()
    };
    client.matrixClient
        .setAccountData(client.matrixClient.userID!, reactionsKey, content);
  }

  Future<void> storeRecentlyTyped() async {
    final mx = client.matrixClient;
    final content = typedRecentsContent(_typedEmoji,
        previous: mx.accountData[typedKey]?.content);

    await mx.setAccountData(mx.userID!, typedKey, content);
  }

  /// A list in our own format (`{key, state_key?, room_id?, count}`).
  static List<RecentEmoji> toRecentsList(matrix.BasicEvent data) =>
      _parseList(data.content["recent_emoji"]);

  static List<RecentEmoji> _parseList(Object? list) {
    if (list is! List) return [];
    return list
        .map(RecentEmoji.fromjson)
        .nonNulls
        .where((i) => i.key != "")
        .toList();
  }

  @override
  Future<void> clear() async {
    _reactionEmoji = List.empty(growable: true);
    _typedEmoji = List.empty(growable: true);

    await storeRecentReactions();
    await storeRecentlyTyped();
  }
}

class RecentEmoji {
  RecentEmoji(
      {required this.key,
      this.customPackId,
      this.customPackRoomId,
      this.count = 1});

  String key;
  String? customPackId;
  String? customPackRoomId;
  int count;

  Map<String, dynamic> toJson() {
    return {
      "key": key,
      if (customPackId != null) "state_key": customPackId,
      if (customPackRoomId != null) "room_id": customPackRoomId,
      "count": count,
    };
  }

  /// Null for anything but an object with a string `key`; a field of the
  /// wrong type is taken as absent.
  static RecentEmoji? fromjson(Object? data) {
    if (data is! Map) return null;
    final key = data["key"];
    if (key is! String) return null;
    final packId = data["state_key"];
    final roomId = data["room_id"];
    final count = data["count"];
    return RecentEmoji(
        key: key,
        customPackId: packId is String ? packId : null,
        customPackRoomId: roomId is String ? roomId : null,
        count: count is int ? count : 1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! RecentEmoji) {
      return false;
    }

    return other.customPackId == customPackId &&
        other.customPackRoomId == customPackRoomId &&
        other.key == key;
  }

  @override
  int get hashCode {
    return "${key}_${customPackId}_${customPackRoomId}".hashCode;
  }
}
