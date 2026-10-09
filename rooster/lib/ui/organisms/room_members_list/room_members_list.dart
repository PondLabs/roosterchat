import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/molecules/user_list.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(this.room, {super.key});
  final Room room;

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;

  String get labelRoomMembersHeader => Intl.message("Room Members",
      name: "labelRoomMembersHeader",
      desc:
          "Header over the list of a room's members, in the room's side panel");

  @override
  void initState() {
    isDirectMessage = widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDirectMessage) tiamat.Text.labelLow(labelRoomMembersHeader),
        Expanded(
          child: SizedBox(
            width: MediaQuery.sizeOf(context).desktop
                ? isDirectMessage
                    ? 300
                    : 200
                : null,
            child: RoomMemberList(
                key: ValueKey(
                    "room-participant-list-key-${widget.room.localId}"),
                widget.room),
          ),
        ),
      ],
    );
  }
}
