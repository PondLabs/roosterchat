import 'package:matrix/matrix.dart' as matrix;

import '../matrix_room_directory/fakes.dart';

export '../matrix_room_directory/fakes.dart'
    show
        DirectoryTestClient,
        Script,
        Seen,
        host,
        joinedRoom,
        json,
        matrixError,
        prepareTests,
        self,
        settle;

const roomId = '!room:example.org';

var _ts = 100;

/// Puts a state event in [room], as a sync would.
void putState(matrix.Room room, String type, Map<String, Object?> content,
    {String stateKey = '', String sender = self}) {
  room.setState(matrix.Event(
    type: type,
    stateKey: stateKey,
    eventId: '\$${type}_$_ts',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(_ts++),
    content: content,
    room: room,
  ));
}

/// A member event as `GET /members` returns it.
Map<String, Object?> memberEvent(String userId, String membership,
        {String? reason, String? displayName}) =>
    {
      'type': 'm.room.member',
      'state_key': userId,
      'sender': '@mod:example.org',
      'event_id': '\$member_$userId',
      'room_id': roomId,
      'origin_server_ts': 1,
      'content': {
        'membership': membership,
        if (reason != null) 'reason': reason,
        if (displayName != null) 'displayname': displayName,
      },
    };

/// A client logged in as [self] with a joined room at [ownLevel], whose
/// requests go to a new [Script].
(Script, matrix.Room) moderatedRoom({int ownLevel = 100}) {
  final script = Script();
  final client = DirectoryTestClient(script);
  final room = joinedRoom(client, id: roomId, ownLevel: ownLevel);
  return (script, room);
}

/// Every request that is not a read.
Iterable<Seen> writes(Script script) =>
    script.seen.where((s) => s.method != 'GET');
