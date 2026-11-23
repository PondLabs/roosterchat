import 'package:matrix/matrix.dart' as matrix;

/// The room cannot be read without joining it: it is not `world_readable`,
/// or the server does not let us peek.
class RoomPeekForbidden implements Exception {
  const RoomPeekForbidden();
}

/// One message seen while peeking.
class PeekedMessage {
  const PeekedMessage({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.encrypted,
  });

  final String eventId;
  final String senderId;
  final String senderName;

  /// The message's plain text; empty for an encrypted one.
  final String body;
  final bool encrypted;
}

/// A read-only look at a room we have not joined (spec "Room previews"):
/// `GET /v3/rooms/{roomId}/initialSync`, or `/messages` and `/state` from a
/// server that no longer has it, then `GET /v3/events?room_id=` for what
/// arrived since. Nothing is added to the client's rooms: the room is not
/// joined, and nothing is stored.
class MatrixRoomPeek {
  MatrixRoomPeek(this.client, this.roomId, {this.limit = 30});

  final matrix.Client client;
  final String roomId;
  final int limit;

  /// The messages read so far, oldest first.
  final List<PeekedMessage> messages = [];

  final Map<String, String> _names = {};

  String? name;
  String? topic;

  /// Where [loadNewer] continues from.
  String? end;

  static bool _isForbidden(matrix.MatrixException e) =>
      e.error == matrix.MatrixError.M_FORBIDDEN ||
      e.error == matrix.MatrixError.M_GUEST_ACCESS_FORBIDDEN;

  static bool _isUnsupported(matrix.MatrixException e) =>
      e.error == matrix.MatrixError.M_UNRECOGNIZED ||
      e.error == matrix.MatrixError.M_NOT_FOUND;

  /// Reads the room's latest messages; throws [RoomPeekForbidden] when the
  /// room cannot be read without joining.
  Future<void> load() async {
    messages.clear();
    List<matrix.MatrixEvent> state;
    List<matrix.MatrixEvent> timeline;
    try {
      final json = await client.request(
        matrix.RequestType.GET,
        '/client/v3/rooms/${Uri.encodeComponent(roomId)}/initialSync',
        query: {'limit': '$limit'},
      );
      final chunk = json['messages'] as Map<String, Object?>? ?? const {};
      state = _events(json['state']);
      timeline = _events(chunk['chunk']);
      end = chunk['end'] as String?;
    } on matrix.MatrixException catch (e) {
      if (_isForbidden(e)) throw const RoomPeekForbidden();
      if (!_isUnsupported(e)) rethrow;
      try {
        state = await client.getRoomState(roomId);
        final page = await client.getRoomEvents(roomId, matrix.Direction.b,
            limit: limit);
        timeline = page.chunk.reversed.toList();
        end = null;
      } on matrix.MatrixException catch (e) {
        if (_isForbidden(e)) throw const RoomPeekForbidden();
        rethrow;
      }
    }
    for (final event in state) {
      _readState(event);
    }
    _addAll(timeline);
  }

  /// Adds what was sent to the room since [load], when the server can tell.
  Future<void> loadNewer() async {
    final from = end;
    if (from == null) return;
    final response =
        await client.peekEvents(from: from, roomId: roomId, timeout: 0);
    end = response.end ?? end;
    _addAll(response.chunk
            ?.where((e) => e.roomId == null || e.roomId == roomId)
            .toList() ??
        const []);
  }

  static List<matrix.MatrixEvent> _events(Object? list) => list is List
      ? list
          .whereType<Map<String, Object?>>()
          .map(matrix.MatrixEvent.fromJson)
          .toList()
      : const [];

  void _readState(matrix.MatrixEvent event) {
    switch (event.type) {
      case matrix.EventTypes.RoomName:
        name = event.content.tryGet<String>('name');
      case matrix.EventTypes.RoomTopic:
        topic = event.content.tryGet<String>('topic');
      case matrix.EventTypes.RoomMember:
        final displayName = event.content.tryGet<String>('displayname');
        final key = event.stateKey;
        if (key != null && displayName != null && displayName.isNotEmpty) {
          _names[key] = displayName;
        }
    }
  }

  void _addAll(List<matrix.MatrixEvent> events) {
    for (final event in events) {
      if (event.stateKey != null) {
        _readState(event);
        continue;
      }
      final encrypted = event.type == matrix.EventTypes.Encrypted;
      if (event.type != matrix.EventTypes.Message && !encrypted) continue;
      if (messages.any((m) => m.eventId == event.eventId)) continue;
      final body = event.content.tryGet<String>('body');
      if (!encrypted && body == null) continue;
      messages.add(PeekedMessage(
        eventId: event.eventId,
        senderId: event.senderId,
        senderName: _names[event.senderId] ?? event.senderId,
        body: body ?? '',
        encrypted: encrypted,
      ));
    }
  }
}
