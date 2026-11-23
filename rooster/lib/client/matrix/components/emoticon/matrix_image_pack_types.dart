import 'package:matrix/matrix.dart' as matrix;

/// The event and account data types of image packs: the stable ones of
/// Matrix v1.19 (MSC2545), which are written, and the unstable `im.ponies.*`
/// ones they replace, which are still read.
abstract class ImagePackTypes {
  /// A room's or space's packs, one per state key.
  static const room = matrix.EventTypes.RoomImagePack;
  static const legacyRoom = "im.ponies.room_emotes";

  /// The user's own pack, in account data.
  static const user = "m.image_pack";
  static const legacyUser = "im.ponies.user_emotes";

  /// The room packs the user enabled everywhere, in account data.
  static const rooms = matrix.EventTypes.ImagePackRooms;
  static const legacyRooms = "im.ponies.emote_rooms";

  /// The identifier of the user's own pack. Kept as it was before the
  /// stable types, so recent emoji saved with it still find the pack.
  static const userPackKey = legacyUser;
}

/// Room packs read from both the stable and the legacy state types, keyed
/// by state key. Where both have a pack with the same state key, the stable
/// one is used, even when empty: an empty content is a pack deleted after
/// it was migrated, and the legacy copy must not come back.
Map<String, Map<String, dynamic>> readRoomImagePacks(matrix.Room room) {
  final result = <String, Map<String, dynamic>>{};
  for (final type in const [ImagePackTypes.legacyRoom, ImagePackTypes.room]) {
    final states = room.states[type];
    if (states == null) continue;
    for (final entry in states.entries) {
      result[entry.key] = entry.value.content;
    }
  }
  return result;
}

extension MatrixImagePackRooms on matrix.Client {
  /// The room packs enabled everywhere: `m.image_pack.rooms` when the
  /// account has it, the legacy `im.ponies.emote_rooms` otherwise. Never
  /// both, so a pack turned off in the stable list stays off.
  matrix.ImagePackRoomsContent get imagePackRooms {
    final event = accountData[ImagePackTypes.rooms] ??
        accountData[ImagePackTypes.legacyRooms];
    return matrix.ImagePackRoomsContent.fromJson(event?.content ?? const {});
  }

  bool isImagePackEnabledEverywhere(String roomId, String stateKey) =>
      imagePackRooms.rooms[roomId]?.containsKey(stateKey) ?? false;

  /// Turns the pack of [roomId] with [stateKey] on or off everywhere,
  /// written to `m.image_pack.rooms` from what is in effect now, so a
  /// legacy list is carried over once.
  Future<void> setImagePackEnabledEverywhere(
      String roomId, String stateKey, bool enabled) async {
    final content = imagePackRooms;
    final packs = content.rooms.putIfAbsent(roomId, () => {});
    if (enabled) {
      packs[stateKey] = {};
    } else {
      packs.remove(stateKey);
      if (packs.isEmpty) content.rooms.remove(roomId);
    }
    await setAccountData(userID!, ImagePackTypes.rooms, content.toJson());
  }
}
