import 'package:rooster/client/components/calendar_room/calendar_room_component.dart';
import 'package:rooster/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:rooster/ui/organisms/calendar_view/calendar_room_view.dart';
import 'package:rooster/ui/organisms/call_view/call.dart';
import 'package:rooster/ui/organisms/chat/chat.dart';
import 'package:rooster/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:flutter/material.dart';

class RoomPrimaryView extends StatelessWidget {
  const RoomPrimaryView(this.room,
      {super.key, this.bypassSpecialRoomTypes = false});
  final Room room;
  final bool bypassSpecialRoomTypes;

  @override
  Widget build(BuildContext context) {
    if (!bypassSpecialRoomTypes) {
      var photos = room.getComponent<PhotoAlbumRoom>();
      var voip = room.getComponent<VoipRoomComponent>();
      var calendar = room.getComponent<CalendarRoom>();

      var key = ValueKey("room-primary-view-${room.localId}");

      if (voip != null) {
        return ScaledSafeArea(
          bottom: true,
          top: false,
          child: VoipRoomView(
            voip,
            key: key,
          ),
        );
      }

      if (photos != null) {
        return PhotoAlbumView(
          photos,
          key: key,
        );
      }

      if (calendar?.isCalendarRoom == true) {
        return CalendarRoomView(
          calendar!,
          key: key,
        );
      }
    }

    final call = clientManager?.callManager.getCallInRoom(
      room.client,
      room.identifier,
    );

    return Column(
      children: [
        if (call != null) Flexible(child: CallWidget(call)),
        Flexible(
          child: Chat(room, key: key),
        ),
      ],
    );
  }
}
