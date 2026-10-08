// Matrix adapter: one state event in the voice channel.
//
// Type: `chat.commet.voice_channel_status`, state_key "", content
// {"status": "Movie night"}; {} when cleared. Voice channels we create let
// everyone set it (power level 0), as everyone may on Discord; older ones
// keep their state default, usually moderators.
import 'dart:async';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:rooster/client/components/voice_channel_status/voice_channel_status_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';

class MatrixVoiceChannelStatusComponent
    implements VoiceChannelStatusComponent<MatrixClient, MatrixRoom> {
  static const stateEventType = 'chat.commet.voice_channel_status';

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  final StreamController<void> _onChanged = StreamController.broadcast();

  MatrixVoiceChannelStatusComponent(this.client, this.room) {
    client.matrixClient.onRoomState.stream
        .where((e) =>
            e.roomId == room.matrixRoom.id && e.state.type == stateEventType)
        .listen((_) => _onChanged.add(null));
  }

  @override
  String? get status {
    final value = room.matrixRoom.getState(stateEventType)?.content['status'];
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  @override
  bool get canSetStatus => room.matrixRoom.canChangeState(stateEventType);

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  Future<void> setStatus(String? status) async {
    final clipped = (status?.trim() ?? '')
        .characters
        .take(VoiceChannelStatusComponent.maxLength)
        .toString();
    await client.matrixClient
        .setRoomStateWithKey(room.matrixRoom.id, stateEventType, '', {
      if (clipped.isNotEmpty) 'status': clipped,
    });
  }
}
