import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

/// One batch of the rooms we share with someone.
class MutualRoomsBatch {
  const MutualRoomsBatch(this.roomIds, {this.nextBatch, this.local = false});

  final List<String> roomIds;

  /// Where the next batch starts; null on the last one.
  final String? nextBatch;

  /// Worked out on this device, because the homeserver has no
  /// `mutual_rooms` (before Matrix v1.19): it may miss rooms whose members
  /// this device has not loaded.
  final bool local;
}

/// The rooms we share with [userId]: the homeserver's
/// `GET /_matrix/client/v1/mutual_rooms` (Matrix v1.19, MSC2666), batch by
/// batch, or the rooms this device knows both of us joined when the server
/// does not have it.
class MatrixMutualRooms {
  MatrixMutualRooms(this.client, this.userId);

  final matrix.Client client;
  final String userId;

  /// The accounts whose homeserver answered that it has no `mutual_rooms`:
  /// they are not asked again until the app restarts.
  static final _unsupported = Expando<bool>('mutual_rooms_unsupported');

  /// The batch that starts at [from], or the first one.
  Future<MutualRoomsBatch> load({String? from}) async {
    if (from == null && _unsupported[client] == true) return _local();
    try {
      final response = await client.getMutualRooms(userId, from: from);
      return MutualRoomsBatch(response.joined, nextBatch: response.nextBatch);
    } catch (e) {
      if (from != null || !isUnsupported(e)) rethrow;
      _unsupported[client] = true;
      return _local();
    }
  }

  /// `404`/`405` and `M_UNRECOGNIZED`: the server does not know the
  /// endpoint. The SDK turns an answer without an `errcode` (a bare 404) into
  /// a plain exception; a dropped connection or a timeout is not this.
  static bool isUnsupported(Object e) {
    if (e is matrix.MatrixException) {
      return e.error == matrix.MatrixError.M_UNRECOGNIZED ||
          e.error == matrix.MatrixError.M_NOT_FOUND;
    }
    return e is! http.ClientException && e is! TimeoutException;
  }

  MutualRoomsBatch _local() => MutualRoomsBatch([
        for (final room in client.rooms)
          if (room.membership == matrix.Membership.join &&
              room
                      .getState(matrix.EventTypes.RoomMember, userId)
                      ?.content['membership'] ==
                  'join')
            room.id,
      ], local: true);
}
