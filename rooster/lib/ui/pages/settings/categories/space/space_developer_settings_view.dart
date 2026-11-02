import 'package:rooster/client/space.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:rooster/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceDeveloperSettingsView extends StatelessWidget {
  final Space space;
  const SpaceDeveloperSettingsView(this.space, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [jsonDump(context)].map<Widget>((e) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 3, 0, 3),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: e),
      );
    }).toList());
  }

  Widget jsonDump(BuildContext context) {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(
          RoomDeveloperSettingsView.labelRoomDeveloperState),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        SelectionArea(
          child: Codeblock(
            language: "json",
            text: space.developerInfo,
          ),
        )
      ],
    );
  }
}
