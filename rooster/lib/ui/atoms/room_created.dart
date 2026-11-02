import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import '../../client/room.dart';

class RoomCreated extends StatelessWidget {
  const RoomCreated(this.room, {super.key});
  final Room room;

  static String labelRoomCreatedWelcome(String roomName) => Intl.message(
      "Welcome to $roomName!",
      name: "labelRoomCreatedWelcome",
      args: [roomName],
      desc:
          "Big title at the very beginning of a room's history, with the room's name");

  static String get labelRoomCreatedMakeYourselfAtHome => Intl.message(
      "Make yourself at home.",
      name: "labelRoomCreatedMakeYourselfAtHome",
      desc:
          "Under the welcome title at the very beginning of a room's history");

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 200, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Avatar.large(
              image: room.avatar,
              placeholderText: room.displayName,
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.largeTitle(
                    labelRoomCreatedWelcome(room.displayName),
                  ),
                  tiamat.Text.labelEmphasised(
                    labelRoomCreatedMakeYourselfAtHome,
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
