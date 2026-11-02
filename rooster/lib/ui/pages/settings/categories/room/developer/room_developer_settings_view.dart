import 'package:rooster/client/room.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/main.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomDeveloperSettingsView extends StatelessWidget {
  final Room room;
  const RoomDeveloperSettingsView(this.room, {super.key});

  static String get labelRoomDeveloperState => Intl.message("Room State",
      name: "labelRoomDeveloperState",
      desc:
          "Developer settings of a room or space: header of the section that shows the room's state as JSON");

  static String get labelRoomDeveloperShortcuts => Intl.message("Shortcuts",
      name: "labelRoomDeveloperShortcuts",
      desc:
          "Developer settings of a room: header of the section that tests the launcher shortcut to the room (an icon on the phone's home screen)");

  static String get promptRoomDeveloperRegisterShortcut => Intl.message(
      "Register Shortcut",
      name: "promptRoomDeveloperRegisterShortcut",
      desc:
          "Developer settings of a room: button that creates a launcher shortcut to the room");

  static String get promptRoomDeveloperClearShortcuts => Intl.message(
      "Clear All Shortcuts",
      name: "promptRoomDeveloperClearShortcuts",
      desc:
          "Developer settings of a room: button that removes every launcher shortcut the app made");

  @override
  Widget build(BuildContext context) {
    return Column(
        children:
            [jsonDump(context), notificationTests(context)].map<Widget>((e) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 3, 0, 3),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: e),
      );
    }).toList());
  }

  Widget jsonDump(BuildContext context) {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelRoomDeveloperState),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        SelectionArea(
          child: Codeblock(
            language: "json",
            text: room.developerInfo,
            // The copy button: the state is what gets pasted into a bug
            // report.
            clipboardText: room.developerInfo,
          ),
        )
      ],
    );
  }

  Widget notificationTests(BuildContext context) {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelRoomDeveloperShortcuts),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
            text: promptRoomDeveloperRegisterShortcut,
            onTap: () => shortcutsManager.createShortcutForRoom(room),
          ),
          tiamat.Button(
            text: promptRoomDeveloperClearShortcuts,
            onTap: () => shortcutsManager.clearAllShortcuts(),
          ),
        ])
      ],
    );
  }
}
