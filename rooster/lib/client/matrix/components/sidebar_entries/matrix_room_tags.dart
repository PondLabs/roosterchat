import 'dart:convert';

import 'package:matrix/matrix.dart' as matrix;

/// A tag the user may not set by hand: empty, too long, or outside the
/// user's own namespace `u.`.
class InvalidRoomTag implements Exception {
  const InvalidRoomTag(this.tag);
  final String tag;

  @override
  String toString() => "Invalid room tag: $tag";
}

/// A room's tags (`m.tag` room account data): low priority, and the user's
/// own `u.*` tags, through `PUT`/`DELETE /v3/user/{userId}/rooms/{roomId}/tags/{tag}`.
class MatrixRoomTags {
  MatrixRoomTags(this.room);

  final matrix.Room room;

  static const customPrefix = 'u.';

  /// The spec's limit on a tag's length, in UTF-8 bytes.
  static const maxTagBytes = 255;

  static bool isValidCustomTag(String tag) =>
      tag == tag.trim() &&
      tag.startsWith(customPrefix) &&
      tag.length > customPrefix.length &&
      utf8.encode(tag).length <= maxTagBytes;

  /// The tag for [name] typed by the user: `u.` in front unless it is
  /// already there. Throws [InvalidRoomTag] for an empty name.
  static String customTagFor(String name) {
    final trimmed = name.trim();
    final tag =
        trimmed.startsWith(customPrefix) ? trimmed : "$customPrefix$trimmed";
    if (!isValidCustomTag(tag)) throw InvalidRoomTag(name);
    return tag;
  }

  bool get isLowPriority => room.tags.containsKey(matrix.TagType.lowPriority);

  /// The user's own tags on the room, sorted.
  List<String> get customTags =>
      room.tags.keys.where((t) => t.startsWith(customPrefix)).toList()..sort();

  Future<void> setLowPriority(bool lowPriority) => lowPriority
      ? room.addTag(matrix.TagType.lowPriority)
      : room.removeTag(matrix.TagType.lowPriority);

  Future<void> addCustomTag(String tag) {
    if (!isValidCustomTag(tag)) throw InvalidRoomTag(tag);
    return room.addTag(tag);
  }

  Future<void> removeCustomTag(String tag) {
    if (!isValidCustomTag(tag)) throw InvalidRoomTag(tag);
    return room.removeTag(tag);
  }
}
