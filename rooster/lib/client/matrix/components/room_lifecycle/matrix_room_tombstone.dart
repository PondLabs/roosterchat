import 'package:matrix/matrix.dart' as matrix;

/// What an `m.room.tombstone` says about the room that replaced this one.
///
/// Matrix v1.19 added `via` to the tombstone: the servers to join the
/// replacement room through (room ids carry no server name from room version
/// 12 on). Older tombstones have no `via`; for those the server of whoever sent
/// the tombstone is used, since that server took part in the upgrade.
class MatrixRoomTombstone {
  const MatrixRoomTombstone({
    required this.replacementRoomId,
    required this.via,
    required this.senderId,
    this.body,
  });

  final String replacementRoomId;

  /// Servers to route the join through. Empty when nothing is known.
  final List<String> via;

  final String senderId;
  final String? body;

  /// The tombstone in [room]'s current state, or null when it has none or
  /// the tombstone names no replacement room.
  static MatrixRoomTombstone? ofRoom(matrix.Room room) {
    final state = room.getState(matrix.EventTypes.RoomTombstone);
    if (state == null) return null;
    return fromContent(state.content, senderId: state.senderId);
  }

  static MatrixRoomTombstone? fromContent(
    Map<String, Object?> content, {
    required String senderId,
  }) {
    final replacement = content['replacement_room'];
    if (replacement is! String || replacement.isEmpty) return null;

    final via = <String>[];
    final rawVia = content['via'];
    if (rawVia is List) {
      for (final server in rawVia) {
        if (server is String && server.isNotEmpty && !via.contains(server)) {
          via.add(server);
        }
      }
    }

    if (via.isEmpty) {
      final senderServer = _serverOf(senderId);
      if (senderServer != null) via.add(senderServer);
    }

    final body = content['body'];
    return MatrixRoomTombstone(
      replacementRoomId: replacement,
      via: via,
      senderId: senderId,
      body: body is String && body.isNotEmpty ? body : null,
    );
  }

  static String? _serverOf(String userId) {
    final colon = userId.indexOf(':');
    if (colon < 0 || colon == userId.length - 1) return null;
    return userId.substring(colon + 1);
  }
}
