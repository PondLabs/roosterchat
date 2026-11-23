import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_directory/matrix_room_directory_visibility.dart';
import 'package:rooster/debug/log.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Whether the room is listed in our homeserver's public room directory.
class MatrixRoomDirectoryVisibilitySettings extends StatefulWidget {
  const MatrixRoomDirectoryVisibilitySettings(this.room, {super.key});

  final matrix.Room room;

  static const switchKey = ValueKey('room_directory_visibility_switch');

  static String get labelRoomDirectoryHeader => Intl.message("Room directory",
      name: "labelRoomDirectoryHeader",
      desc:
          "Header of the room settings section about the homeserver's public room directory");

  static String get labelRoomPublishToDirectory => Intl.message(
      "List this room in the public room directory",
      name: "labelRoomPublishToDirectory",
      desc:
          "Switch that lists the room in the homeserver's public room directory, where anyone can find it");

  static String get messageRoomDirectoryForbidden => Intl.message(
      "Your homeserver did not let you change whether this room is listed.",
      name: "messageRoomDirectoryForbidden",
      desc:
          "Shown under the room directory switch when the homeserver refused the change (the switch goes back)");

  static String get messageRoomDirectoryFailed => Intl.message(
      "The change could not be saved. Try again later.",
      name: "messageRoomDirectoryFailed",
      desc:
          "Shown under the room directory switch when changing it failed for another reason (the switch goes back)");

  @override
  State<MatrixRoomDirectoryVisibilitySettings> createState() =>
      _MatrixRoomDirectoryVisibilitySettingsState();
}

class _MatrixRoomDirectoryVisibilitySettingsState
    extends State<MatrixRoomDirectoryVisibilitySettings> {
  late final visibility = RoomDirectoryVisibility(widget.room);
  bool? published;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    visibility.load().then((value) {
      if (mounted) setState(() => published = value);
    }, onError: (Object e, StackTrace s) {
      Log.onError(e, s, content: "Could not read the room's directory entry");
    });
  }

  Future<void> change(bool value) async {
    final before = published ?? false;
    setState(() {
      published = value;
      busy = true;
      error = null;
    });
    try {
      await visibility.setPublished(value);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the room's directory entry");
      published = before;
      error = e is matrix.MatrixException &&
              e.error == matrix.MatrixError.M_FORBIDDEN
          ? MatrixRoomDirectoryVisibilitySettings.messageRoomDirectoryForbidden
          : MatrixRoomDirectoryVisibilitySettings.messageRoomDirectoryFailed;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final value = published;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomDirectoryVisibilitySettings.labelRoomDirectoryHeader,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: tiamat.Text.label(MatrixRoomDirectoryVisibilitySettings
                      .labelRoomPublishToDirectory)),
              Switch(
                key: MatrixRoomDirectoryVisibilitySettings.switchKey,
                value: value ?? false,
                onChanged: value == null || busy || !visibility.canChange
                    ? null
                    : change,
              ),
            ]),
            if (error != null) tiamat.Text.error(error!),
          ],
        ),
      ),
    );
  }
}
