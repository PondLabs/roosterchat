import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/pages/settings/categories/room/security/wrapping_radio_options.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Who can read the room's history (`m.room.history_visibility`).
class MatrixRoomHistoryVisibilitySettings extends StatefulWidget {
  const MatrixRoomHistoryVisibilitySettings(this.room, {super.key});

  final matrix.Room room;

  static String get messageRoomSettingNoPermission => Intl.message(
      "You need permission to change this setting.",
      desc: "Below a room setting someone without the power to change it can "
          "only look at",
      name: "messageRoomSettingNoPermission");

  static String get labelHistoryVisibilityHeader =>
      Intl.message("Who can read history",
          desc: "Header of the room setting for who can read past messages",
          name: "labelHistoryVisibilityHeader");

  static String get labelHistoryWorldReadable => Intl.message("Anyone",
      desc: "Room history option: anyone, even people not in the room, can "
          "read past messages",
      name: "labelHistoryWorldReadable");

  static String get labelHistoryShared =>
      Intl.message("Members, including messages from before they joined",
          desc: "Room history option: members can read all past messages",
          name: "labelHistoryShared");

  static String get labelHistoryInvited =>
      Intl.message("Members, from when they were invited",
          desc: "Room history option: members read messages sent after they "
              "were invited",
          name: "labelHistoryInvited");

  static String get labelHistoryJoined =>
      Intl.message("Members, from when they joined",
          desc: "Room history option: members read messages sent after they "
              "joined",
          name: "labelHistoryJoined");

  static String labelFor(matrix.HistoryVisibility value) => switch (value) {
        matrix.HistoryVisibility.worldReadable => labelHistoryWorldReadable,
        matrix.HistoryVisibility.shared => labelHistoryShared,
        matrix.HistoryVisibility.invited => labelHistoryInvited,
        matrix.HistoryVisibility.joined => labelHistoryJoined,
      };

  @override
  State<MatrixRoomHistoryVisibilitySettings> createState() =>
      _MatrixRoomHistoryVisibilitySettingsState();
}

class _MatrixRoomHistoryVisibilitySettingsState
    extends State<MatrixRoomHistoryVisibilitySettings> {
  // The spec's default when the room has no such state event.
  late matrix.HistoryVisibility value =
      widget.room.historyVisibility ?? matrix.HistoryVisibility.shared;

  Future<void> change(matrix.HistoryVisibility? next) async {
    if (next == null || next == value) return;
    if (!widget.room.canChangeHistoryVisibility) return;
    await ErrorUtils.tryRun(context, () async {
      await widget.room.setHistoryVisibility(next);
      if (mounted) setState(() => value = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.room.canChangeHistoryVisibility;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomHistoryVisibilitySettings.labelHistoryVisibilityHeader,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WrappingRadioOptions<matrix.HistoryVisibility>(
              value: value,
              enabled: allowed,
              onChanged: change,
              options: [
                for (final option in matrix.HistoryVisibility.values)
                  (
                    option,
                    switch (option) {
                      matrix.HistoryVisibility.worldReadable => Icons.public,
                      matrix.HistoryVisibility.shared => Icons.history,
                      matrix.HistoryVisibility.invited =>
                        Icons.mark_email_read_outlined,
                      matrix.HistoryVisibility.joined => Icons.login,
                    },
                    MatrixRoomHistoryVisibilitySettings.labelFor(option),
                  ),
              ],
            ),
            if (!allowed)
              tiamat.Text.labelLow(MatrixRoomHistoryVisibilitySettings
                  .messageRoomSettingNoPermission),
          ],
        ),
      ),
    );
  }
}

/// Whether guest accounts may join (`m.room.guest_access`).
class MatrixRoomGuestAccessSettings extends StatefulWidget {
  const MatrixRoomGuestAccessSettings(this.room, {super.key});

  final matrix.Room room;

  static String get labelGuestAccessHeader => Intl.message("Guest access",
      desc: "Header of the room setting for whether guest accounts (Matrix "
          "accounts without a full registration) can join",
      name: "labelGuestAccessHeader");

  static String get labelGuestsCanJoin => Intl.message("Guests can join",
      desc: "Guest access option: guest accounts may join the room",
      name: "labelGuestsCanJoin");

  static String get labelGuestsForbidden => Intl.message("No guests",
      desc: "Guest access option: guest accounts may not join the room",
      name: "labelGuestsForbidden");

  @override
  State<MatrixRoomGuestAccessSettings> createState() =>
      _MatrixRoomGuestAccessSettingsState();
}

class _MatrixRoomGuestAccessSettingsState
    extends State<MatrixRoomGuestAccessSettings> {
  late matrix.GuestAccess value = widget.room.guestAccess;

  Future<void> change(matrix.GuestAccess? next) async {
    if (next == null || next == value) return;
    if (!widget.room.canChangeGuestAccess) return;
    await ErrorUtils.tryRun(context, () async {
      await widget.room.setGuestAccess(next);
      if (mounted) setState(() => value = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.room.canChangeGuestAccess;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomGuestAccessSettings.labelGuestAccessHeader,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WrappingRadioOptions<matrix.GuestAccess>(
              value: value,
              enabled: allowed,
              onChanged: change,
              options: [
                (
                  matrix.GuestAccess.canJoin,
                  Icons.person_add_alt,
                  MatrixRoomGuestAccessSettings.labelGuestsCanJoin,
                ),
                (
                  matrix.GuestAccess.forbidden,
                  Icons.person_off_outlined,
                  MatrixRoomGuestAccessSettings.labelGuestsForbidden,
                ),
              ],
            ),
            if (!allowed)
              tiamat.Text.labelLow(MatrixRoomHistoryVisibilitySettings
                  .messageRoomSettingNoPermission),
          ],
        ),
      ),
    );
  }
}
