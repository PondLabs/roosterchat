import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.encryption`: end-to-end encryption was turned on. It cannot be
/// turned off, so content without the Megolm algorithm only says the
/// settings changed.
class MatrixTimelineEventRoomEncryption extends MatrixTimelineEventState {
  MatrixTimelineEventRoomEncryption(super.event, {required super.client});

  static String messageRoomEncryptionEnabled(String user) =>
      Intl.message("$user turned on end-to-end encryption",
          name: "messageRoomEncryptionEnabled",
          args: [user],
          desc: "Timeline line for when someone turns on end-to-end "
              "encryption in the room");

  static String messageRoomEncryptionChanged(String user) =>
      Intl.message("$user changed the encryption settings",
          name: "messageRoomEncryptionChanged",
          args: [user],
          desc: "Timeline line for a change to the room's encryption "
              "settings that the app cannot describe (an unknown or "
              "missing algorithm)");

  bool get isMegolm =>
      contentString('algorithm') == matrix.AlgorithmTypes.megolmV1AesSha2;

  @override
  IconData get icon => Icons.lock_outline;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    return isMegolm
        ? messageRoomEncryptionEnabled(user)
        : messageRoomEncryptionChanged(user);
  }
}
