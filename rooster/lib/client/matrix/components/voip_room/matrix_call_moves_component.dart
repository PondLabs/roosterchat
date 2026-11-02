import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/debug/log.dart';

/// Moving people between voice channels, or out of a call, as Discord's
/// admins do by dragging them. Matrix has no such thing: the mover sends the
/// person's devices a to-device message, and their Rooster switches channel
/// itself, after checking the mover may: someone above them with the power
/// to kick in the call's room. Their own devices may always move them.
class MatrixCallMovesComponent extends Component<MatrixClient> {
  MatrixCallMovesComponent(super.client) {
    client.matrixClient.onToDeviceEvent.stream
        .where((e) => e.type == eventType)
        .listen((e) => unawaited(_received(e).catchError(
            (Object e, StackTrace s) =>
                Log.onError(e, s, content: "Could not take a call move"))));
  }

  static const eventType = "chat.commet.call.move";

  /// A move held back while the device was offline is not acted on
  /// once it comes back: the call it was about has moved on.
  static const maxAge = Duration(minutes: 1);

  /// Whether [mover] may move [target] in [room]'s call: themselves, or
  /// someone whose power level reaches the room's kick level and is above
  /// the target's.
  static bool mayMove(matrix.Room room, String mover, String target) {
    if (mover == target) return true;
    final kick = room
            .getState(matrix.EventTypes.RoomPowerLevels)
            ?.content
            .tryGet<int>("kick") ??
        50;
    final power = room.getPowerLevelByUserId(mover);
    return power >= kick && power > room.getPowerLevelByUserId(target);
  }

  /// Whether we may move [userId] out of [room]'s call.
  static bool canMove(MatrixRoom room, String userId) {
    final self = room.client.self?.identifier;
    return self != null && mayMove(room.matrixRoom, self, userId);
  }

  /// Moves [userId] from [from]'s call to [to]'s, or out of the call
  /// altogether when [to] is null. Ourselves directly, anyone else through
  /// their devices.
  Future<void> move(MatrixRoom from, String userId, MatrixRoom? to) async {
    final mx = client.matrixClient;
    if (userId == mx.userID) {
      if (to == null) {
        await from
            .getComponent<VoipRoomComponent>()
            ?.currentSession
            ?.hangUpCall();
      } else {
        await to.getComponent<VoipRoomComponent>()?.joinCall();
      }
      return;
    }
    await mx.sendToDevice(eventType, mx.generateUniqueTransactionId(), {
      userId: {
        "*": {
          "room_id": from.identifier,
          if (to != null) "to_room_id": to.identifier,
          "sent_at": DateTime.now().millisecondsSinceEpoch,
        },
      },
    });
  }

  Future<void> _received(matrix.ToDeviceEvent event) async {
    final content = event.content;
    final sentAt = content.tryGet<int>("sent_at");
    if (sentAt == null ||
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(sentAt))
                .abs() >
            maxAge) {
      return;
    }
    final from = client.getRoom(content.tryGet<String>("room_id") ?? "");
    if (from is! MatrixRoom) return;
    // Only a call we are in.
    final session = from.getComponent<VoipRoomComponent>()?.currentSession;
    if (session == null || session.state == VoipState.ended) return;
    final self = client.matrixClient.userID!;
    if (!mayMove(from.matrixRoom, event.sender, self)) {
      Log.w("${event.sender} asked to move us out of ${from.identifier}'s "
          "call without the power to");
      return;
    }

    final toId = content.tryGet<String>("to_room_id");
    if (toId == null) {
      Log.i("${event.sender} disconnected us from ${from.identifier}'s call");
      await session.hangUpCall();
      return;
    }
    final to = client.getRoom(toId)?.getComponent<VoipRoomComponent>();
    if (to == null || !to.canJoinCall) return;
    Log.i("${event.sender} moved us from ${from.identifier}'s call to $toId's");
    await to.joinCall();
  }
}
