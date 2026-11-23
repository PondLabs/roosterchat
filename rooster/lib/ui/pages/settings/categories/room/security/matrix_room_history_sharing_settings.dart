import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/history_sharing/matrix_history_sharing.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Whether inviting someone shares the room's encrypted history (MSC4268),
/// and a quiet note when someone shared it with us.
class MatrixRoomHistorySharingSettings extends StatefulWidget {
  const MatrixRoomHistorySharingSettings(this.controller, {super.key});

  final HistorySharingController controller;

  static String get labelHistorySharingHeader =>
      Intl.message("Earlier messages for people you invite",
          desc: "Header of the room setting for whether inviting someone "
              "gives them the keys to read encrypted messages sent before "
              "they joined",
          name: "labelHistorySharingHeader");

  static String get labelHistorySharingToggle =>
      Intl.message("Share earlier messages when I invite someone",
          desc: "Switch in a room's security settings: when on, the people "
              "you invite get the keys to the room's earlier encrypted "
              "messages",
          name: "labelHistorySharingToggle");

  static String get messageHistorySharingOn => Intl.message(
      "People you invite get the keys to the earlier encrypted messages this "
      "room lets them read.",
      desc: "Below the history sharing switch, when it is on",
      name: "messageHistorySharingOn");

  static String get messageHistorySharingOff => Intl.message(
      "People you invite will not be able to read encrypted messages sent "
      "before they joined.",
      desc: "Below the history sharing switch, when it is off",
      name: "messageHistorySharingOff");

  static String get messageHistorySharingKeptToMembers => Intl.message(
      "This room's history setting keeps earlier messages from new members, "
      "so none are shared when you invite someone.",
      desc: "Below the history sharing switch, greyed out because the room "
          "only lets members read messages from when they joined",
      name: "messageHistorySharingKeptToMembers");

  static String messageHistorySharingImported(String sender) => Intl.message(
      "$sender shared the keys to this room's earlier messages with you when "
      "they invited you.",
      args: [sender],
      desc: "Quiet note in a room's security settings: the person who invited "
          "you gave you the keys to read the room's earlier encrypted "
          "messages. The placeholder is their name",
      name: "messageHistorySharingImported");

  @override
  State<MatrixRoomHistorySharingSettings> createState() =>
      _MatrixRoomHistorySharingSettingsState();
}

class _MatrixRoomHistorySharingSettingsState
    extends State<MatrixRoomHistorySharingSettings> {
  StreamSubscription<void>? changes;

  @override
  void initState() {
    super.initState();
    changes = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    changes?.cancel();
    super.dispose();
  }

  Future<void> toggle(bool on) => ErrorUtils.tryRun(context, () async {
        await widget.controller.setShareOnInvite(on);
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    if (state == HistorySharingState.notEncrypted) {
      return const SizedBox.shrink();
    }
    final notice = widget.controller.notice;
    final changeable = state != HistorySharingState.keptToMembers;
    final explanation = switch (state) {
      HistorySharingState.on =>
        MatrixRoomHistorySharingSettings.messageHistorySharingOn,
      HistorySharingState.off =>
        MatrixRoomHistorySharingSettings.messageHistorySharingOff,
      _ => MatrixRoomHistorySharingSettings.messageHistorySharingKeptToMembers,
    };
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomHistorySharingSettings.labelHistorySharingHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Opacity(
            opacity: changeable ? 1 : 0.5,
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(
                          MatrixRoomHistorySharingSettings
                              .labelHistorySharingToggle),
                      tiamat.Text.labelLow(explanation),
                    ],
                  ),
                ),
                IgnorePointer(
                  ignoring: !changeable,
                  child: tiamat.Switch(
                    state: state == HistorySharingState.on,
                    onChanged: (value) => toggle(value),
                  ),
                ),
              ],
            ),
          ),
          if (notice != null)
            tiamat.Text.labelLow(
                MatrixRoomHistorySharingSettings.messageHistorySharingImported(
                    notice.senderName)),
        ],
      ),
    );
  }
}
