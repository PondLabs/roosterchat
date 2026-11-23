import 'package:rooster/client/client.dart' as rooster;
import 'package:rooster/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/room_preview.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';

/// Returns whether a Matrix spec version string (such as `v1.15`) is greater
/// than or equal to [targetMajor].[targetMinor].
bool isMatrixVersionAtLeast(String version, int targetMajor, int targetMinor) {
  if (!version.startsWith('v')) return false;
  final parts = version.substring(1).split('.');
  if (parts.length < 2) return false;
  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  if (major == null || minor == null) return false;
  if (major != targetMajor) return major > targetMajor;
  return minor >= targetMinor;
}

extension MatrixExtensions on Client {
  Future<FileResponse> getContentFromUri(Uri uri) {
    return getContent(uri.authority, uri.pathSegments.first);
  }

  Future<FileResponse> getContentThumbnailFromUri(
      Uri uri, int width, int height) {
    return getContentThumbnail(
        uri.authority, uri.pathSegments.first, width, height);
  }

  Future<bool> _supportsStableRoomSummary() async {
    final versions = await getVersions();
    return versions.versions.any((v) => isMatrixVersionAtLeast(v, 1, 15));
  }

  Future<RoomPreview?> getRoomPreview(String roomId,
      {List<String>? via}) async {
    if (await _supportsStableRoomSummary()) {
      final summary = await getRoomSummary(roomId, via: via);
      return _buildRoomPreview(
        id: summary.roomId,
        name: summary.name,
        avatarUrl: summary.avatarUrl,
        topic: summary.topic,
        numMembers: summary.numJoinedMembers,
        joinRule: summary.joinRule,
        roomType: summary.roomType,
        allowedRoomIds: summary.allowedRoomIds,
        via: via,
      );
    }

    // Fallback for homeservers older than Matrix v1.15 (MSC3266).
    var result = await request(
      RequestType.GET,
      "/client/unstable/im.nheko.summary/rooms/${Uri.encodeComponent(roomId)}/summary",
      query: {
        if (via != null) "via": via,
      },
    );

    final avatar = result["avatar_url"] as String?;
    return _buildRoomPreview(
      id: result["room_id"] as String?,
      name: result["name"] as String?,
      avatarUrl: avatar != null ? Uri.tryParse(avatar) : null,
      topic: result["topic"] as String?,
      numMembers: result["num_joined_members"] as int?,
      joinRule: result["join_rule"] as String?,
      roomType: result["room_type"] as String?,
      via: via,
    );
  }

  RoomPreview? _buildRoomPreview({
    required String? id,
    required String? name,
    required Uri? avatarUrl,
    required String? topic,
    required int? numMembers,
    required String? joinRule,
    required String? roomType,
    List<String>? allowedRoomIds,
    List<String>? via,
  }) {
    var type = switch (roomType) {
      "m.space" => rooster.RoomType.space,
      "chat.commet.calendar" => rooster.RoomType.calendar,
      "chat.commet.photo_album" => rooster.RoomType.photoAlbum,
      "org.matrix.msc3417.call" => rooster.RoomType.voipRoom,
      _ => rooster.RoomType.defaultRoom
    };

    var visibility = switch (joinRule) {
      "public" => rooster.RoomVisibilityPublic(),
      "knock" => rooster.RoomVisibilityPrivate(),
      "invite" => rooster.RoomVisibilityPrivate(),
      "private" => rooster.RoomVisibilityPrivate(),
      "restricted" => rooster.RoomVisibilityRestricted(allowedRoomIds ?? []),
      "knock_restricted" =>
        rooster.RoomVisibilityRestricted(allowedRoomIds ?? []),
      _ => rooster.RoomVisibilityPrivate(),
    };

    if (name != null && id != null) {
      ImageProvider? image;
      if (avatarUrl != null) {
        image = MatrixMxcImage(avatarUrl, autoLoadFullRes: false, this);
      }

      return GenericRoomPreview(id,
          displayName: name,
          type: type,
          avatar: image,
          numMembers: numMembers,
          visibility: visibility,
          joinRule: joinRule,
          via: via ?? const [],
          topic: topic);
    }

    return null;
  }

  Future<void> addEmoticonRoomPack(String roomId, String packKey) async {
    var state = BasicEvent(
        type: MatrixEmoticonComponent.globalEmoteRoomsStateKey, content: {});

    if (accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      state = accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!;
    }

    if (!state.content.containsKey("rooms")) {
      state.content['rooms'] = {};
    }

    var rooms = state.content['rooms'] as Map;
    if (!rooms.containsKey(roomId)) {
      rooms[roomId] = {};
    }

    var roomPacks = rooms[roomId] as Map;
    roomPacks[packKey] = {};

    await setAccountData(userID!,
        MatrixEmoticonComponent.globalEmoteRoomsStateKey, state.content);
  }

  Future<void> removeEmoticonRoomPack(String roomId, String packKey) async {
    var state = BasicEvent(
        type: MatrixEmoticonComponent.globalEmoteRoomsStateKey, content: {});

    if (accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      state = accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!;
    }

    if (!state.content.containsKey("rooms")) {
      state.content['rooms'] = {};
    }

    var rooms = state.content['rooms'] as Map;
    if (!rooms.containsKey(roomId)) {
      rooms[roomId] = {};
    }

    var roomPacks = rooms[roomId] as Map;
    roomPacks.remove(packKey);

    await setAccountData(userID!,
        MatrixEmoticonComponent.globalEmoteRoomsStateKey, state.content);
  }

  bool isEmoticonPackGloballyAvailable(String roomId, String packKey) {
    if (!accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      return false;
    }

    var state =
        accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!.content;
    if (!state.containsKey("rooms")) {
      return false;
    }

    var rooms = state["rooms"] as Map;
    if (!rooms.containsKey(roomId)) {
      return false;
    }

    var roomData = rooms[roomId] as Map;

    return roomData.containsKey(packKey);
  }

  // This is stupid, is there a better way to do this?
  Future<bool> isRoomAliasAvailable(String alias) async {
    try {
      await request(
        RequestType.GET,
        '/client/v3/directory/room/${Uri.encodeComponent(alias)}',
      );
      return false;
    } catch (exception) {
      if (exception is MatrixException) {
        if (exception.error == MatrixError.M_NOT_FOUND) {
          return true;
        }
      }
      return false;
    }
  }
}
