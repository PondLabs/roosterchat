import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_archived_rooms.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The rooms this account left or was removed from, with forgetting them.
/// When the homeserver forgets rooms on leave by itself
/// (`m.forget_forced_upon_leave`), it says so and offers nothing to forget.
class ArchivedRoomsView extends StatefulWidget {
  const ArchivedRoomsView(this.archive, {super.key});

  final MatrixArchivedRooms archive;

  static ValueKey<String> forgetKey(String roomId) =>
      ValueKey('archived_room_forget_$roomId');
  static const forcedNoticeKey = ValueKey('archived_rooms_forced_notice');

  static String get labelArchivedRoomsHeader => Intl.message("Rooms you left",
      desc: "Header of the list of rooms the account left or was removed from",
      name: "labelArchivedRoomsHeader");

  static String get promptLoadArchivedRooms =>
      Intl.message("Show rooms you left",
          desc: "Button that loads the list of rooms the account left",
          name: "promptLoadArchivedRooms");

  static String get messageNoArchivedRooms =>
      Intl.message("You have not left any rooms.",
          desc: "Shown when the list of rooms the account left is empty",
          name: "messageNoArchivedRooms");

  static String get promptForgetRoom => Intl.message("Forget",
      desc: "Button that forgets a room the account left: it leaves the "
          "room list for good and its history is no longer kept for you",
      name: "promptForgetRoom");

  static String labelForgetRoomPrompt(String room) => Intl.message(
      "Forget $room? It will no longer show up anywhere, and you will need "
      "an invite or the address to come back.",
      desc: "Confirmation before forgetting a room the account left",
      args: [room],
      name: "labelForgetRoomPrompt");

  static String get messageForgetForcedUponLeave => Intl.message(
      "Your homeserver forgets rooms as soon as you leave them, so there is "
      "nothing to forget here.",
      desc: "Shown above the rooms the account left when the homeserver "
          "already forgets every room on leave (Matrix capability "
          "m.forget_forced_upon_leave)",
      name: "messageForgetForcedUponLeave");

  static String get messageRoomForgotten => Intl.message("Room forgotten",
      desc: "Brief notice after forgetting a room",
      name: "messageRoomForgotten");

  @override
  State<ArchivedRoomsView> createState() => _ArchivedRoomsViewState();
}

class _ArchivedRoomsViewState extends State<ArchivedRoomsView> {
  List<matrix.Room>? rooms;
  bool forced = false;
  bool loading = false;
  final Set<String> busy = {};

  Future<void> load() async {
    setState(() => loading = true);
    await ErrorUtils.tryRun(context, () async {
      final isForced = await widget.archive.forgetForcedUponLeave();
      final loaded = await widget.archive.load();
      if (!mounted) return;
      setState(() {
        forced = isForced;
        rooms = loaded;
      });
    });
    if (mounted) setState(() => loading = false);
  }

  String nameOf(matrix.Room room) =>
      room.getLocalizedDisplayname(const RoomNameLocalizations());

  Future<void> forget(matrix.Room room) async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        prompt: ArchivedRoomsView.labelForgetRoomPrompt(nameOf(room)),
        confirmationText: ArchivedRoomsView.promptForgetRoom,
        dangerous: true);
    if (confirmed != true || !mounted) return;

    setState(() => busy.add(room.id));
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ErrorUtils.tryRun(context, () async {
      final outcome = await widget.archive.forget(room);
      if (!mounted) return;
      setState(() {
        rooms?.removeWhere((r) => r.id == room.id);
        if (outcome == ForgetOutcome.forcedByServer) forced = true;
      });
      messenger?.showSnackBar(SnackBar(
          content: Text(outcome == ForgetOutcome.forcedByServer
              ? ArchivedRoomsView.messageForgetForcedUponLeave
              : ArchivedRoomsView.messageRoomForgotten)));
    });
    if (mounted) setState(() => busy.remove(room.id));
  }

  @override
  Widget build(BuildContext context) {
    final list = rooms;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: ArchivedRoomsView.labelArchivedRoomsHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (list == null)
            tiamat.Button.secondary(
              text: ArchivedRoomsView.promptLoadArchivedRooms,
              isLoading: loading,
              onTap: loading ? null : load,
            )
          else ...[
            if (forced)
              tiamat.Text.labelLow(
                ArchivedRoomsView.messageForgetForcedUponLeave,
                key: ArchivedRoomsView.forcedNoticeKey,
              ),
            if (list.isEmpty)
              tiamat.Text.labelLow(ArchivedRoomsView.messageNoArchivedRooms),
            for (final room in list)
              Row(
                spacing: 8,
                children: [
                  Expanded(child: tiamat.Text.label(nameOf(room))),
                  if (!forced)
                    tiamat.Button.danger(
                      key: ArchivedRoomsView.forgetKey(room.id),
                      text: ArchivedRoomsView.promptForgetRoom,
                      isLoading: busy.contains(room.id),
                      onTap: busy.contains(room.id) ? null : () => forget(room),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
