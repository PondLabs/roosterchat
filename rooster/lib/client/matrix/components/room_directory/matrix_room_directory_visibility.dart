import 'package:matrix/matrix.dart' as matrix;

/// Whether a room is listed in our homeserver's published room directory
/// (`GET/PUT /v3/directory/list/room/{roomId}`).
class RoomDirectoryVisibility {
  RoomDirectoryVisibility(this.room);

  final matrix.Room room;

  /// True when the room is published. The server decides who may change
  /// it; this only hides the switch from people who could not change the
  /// room's address either.
  bool get canChange =>
      room.membership == matrix.Membership.join &&
      room.canChangeStateEvent(matrix.EventTypes.RoomCanonicalAlias);

  Future<bool> load() async =>
      await room.client.getRoomVisibilityOnDirectory(room.id) ==
      matrix.Visibility.public;

  Future<void> setPublished(bool published) =>
      room.client.setRoomVisibilityOnDirectory(room.id,
          visibility:
              published ? matrix.Visibility.public : matrix.Visibility.private);
}
