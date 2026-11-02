import 'package:rooster/client/client.dart';
import 'package:rooster/client/room_preview.dart';
import 'package:rooster/ui/pages/get_or_create_room/room_creation_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomPreviewView extends StatelessWidget {
  const RoomPreviewView({required this.previewData, super.key});
  final RoomPreview previewData;

  static String get labelRoomTypeChatRoom => Intl.message("Chat Room",
      name: "labelRoomTypeChatRoom",
      desc:
          "Tooltip on the icon of a room's preview (before joining it) when it is an ordinary text room");

  /// The kind of room, as the tooltip on its icon says it.
  static String typeName(RoomType type) => switch (type) {
        RoomType.defaultRoom => labelRoomTypeChatRoom,
        RoomType.photoAlbum => RoomCreationStrings.labelRoomTypePhotoAlbum,
        RoomType.space => RoomCreationStrings.labelRoomTypeSpace,
        RoomType.voipRoom => RoomCreationStrings.labelRoomTypeVoiceChat,
        RoomType.calendar => RoomCreationStrings.labelRoomTypeCalendar,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (previewData.avatar != null)
          ImageButton(
            size: 90,
            image: previewData.avatar!,
            placeholderColor: previewData.color,
            placeholderText: previewData.displayName,
          ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.Text.largeTitle(previewData.displayName),
                Row(
                  spacing: 8,
                  children: [
                    if (previewData.type != null)
                      tiamat.Tooltip(
                          text: typeName(previewData.type!),
                          child: Icon(size: 15, previewData.type!.icon)),
                    if (previewData.numMembers != null)
                      Row(
                        children: [
                          Icon(size: 15, Icons.people),
                          tiamat.Text.labelLow("${previewData.numMembers}")
                        ],
                      ),
                    Icon(
                        size: 15,
                        switch (previewData.visibility) {
                          null => Icons.lock,
                          final RoomVisibilityPublic _ => Icons.public,
                          final RoomVisibilityPrivate _ => Icons.lock,
                          final RoomVisibilityRestricted _ => Icons.shield,
                          _ => Icons.question_mark,
                        })
                  ],
                ),
                if (previewData.topic != null)
                  Flexible(
                      child: tiamat.Text.labelLow(
                    previewData.topic!,
                  ))
              ],
            ),
          ),
        )
      ],
    );
  }
}
