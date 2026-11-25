import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/sidebar_entries/matrix_room_marked_unread.dart';
import 'package:rooster/client/matrix/components/sidebar_entries/matrix_room_tags.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/moderation/report_content_dialog.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A room's own entries in its menu in the sidebar: mark unread, low
/// priority and the user's tags.
class RoomPanelActions {
  static String get promptRoomMarkAsUnread => Intl.message("Mark as Unread",
      name: "promptRoomMarkAsUnread",
      desc:
          "Entry in a room's menu (right-click or long press in the room list) that marks it unread, so its dot shows until it is read again");

  static String get promptRoomSetLowPriority => Intl.message(
      "Set as Low Priority",
      name: "promptRoomSetLowPriority",
      desc: "Entry in a room's menu that gives the room the low priority tag");

  static String get promptRoomUnsetLowPriority => Intl.message(
      "Remove Low Priority",
      name: "promptRoomUnsetLowPriority",
      desc:
          "Entry in a room's menu that takes the low priority tag off the room");

  static String get promptRoomEditTags => Intl.message("Tags",
      name: "promptRoomEditTags",
      desc:
          "Entry in a room's menu, and the title of the dialog it opens, where the user adds and removes their own tags on the room");

  static String get labelRoomTagsEmpty => Intl.message(
      "This room has no tags of yours yet.",
      name: "labelRoomTagsEmpty",
      desc: "In the room tags dialog, when the user has not tagged the room");

  static String get hintRoomTagName => Intl.message("New tag",
      name: "hintRoomTagName",
      desc: "Placeholder of the field where the user types a new room tag");

  static String get promptRoomAddTag => Intl.message("Add",
      name: "promptRoomAddTag",
      desc: "Button in the room tags dialog that adds the typed tag");

  static String promptRoomRemoveTag(String tag) => Intl.message(
      "Remove tag $tag",
      name: "promptRoomRemoveTag",
      args: [tag],
      desc:
          "Tooltip of the button next to a tag in the room tags dialog that removes it");

  static String get errorRoomTagInvalid => Intl.message(
      "Type a name for the tag that is not too long.",
      name: "errorRoomTagInvalid",
      desc:
          "Under the tag field when the typed tag is empty or too long to be saved");

  /// Whether the sidebar shows [room]'s unread dot for its mark, with no
  /// notification in it.
  static bool showsUnreadDot(Room room) => MatrixMarkedUnread.of(room);

  static List<tiamat.ContextMenuItem> menuItems(
      BuildContext context, Room room) {
    if (room is! MatrixRoom) return const [];
    final mx = room.matrixRoom;
    if (mx.membership != matrix.Membership.join) return const [];
    final tags = MatrixRoomTags(mx);
    final lowPriority = tags.isLowPriority;
    return [
      if (!MatrixMarkedUnread.isMarked(mx))
        tiamat.ContextMenuItem(
            text: promptRoomMarkAsUnread,
            icon: Icons.mark_chat_unread_outlined,
            onPressed: () => ErrorUtils.tryRun(
                context, () => MatrixMarkedUnread.setMarked(mx, true))),
      tiamat.ContextMenuItem(
          text: lowPriority
              ? promptRoomUnsetLowPriority
              : promptRoomSetLowPriority,
          icon: Icons.low_priority,
          onPressed: () => ErrorUtils.tryRun(
              context, () => tags.setLowPriority(!lowPriority))),
      tiamat.ContextMenuItem(
          text: promptRoomEditTags,
          icon: Icons.label_outline,
          onPressed: () => AdaptiveDialog.show(context,
              title: promptRoomEditTags, builder: (_) => RoomTagsEditor(tags))),
      tiamat.ContextMenuItem(
          text: ReportContentDialog.promptReportRoom,
          icon: Icons.flag_outlined,
          onPressed: () =>
              ReportContentDialog.reportRoom(context, mx.client, mx.id)),
    ];
  }
}

/// Lists the user's `u.*` tags on a room, with a field to add one and a
/// button to remove each.
class RoomTagsEditor extends StatefulWidget {
  const RoomTagsEditor(this.tags, {super.key});

  final MatrixRoomTags tags;

  static const fieldKey = ValueKey('room_tag_field');
  static const addKey = ValueKey('room_tag_add');

  @override
  State<RoomTagsEditor> createState() => _RoomTagsEditorState();
}

class _RoomTagsEditorState extends State<RoomTagsEditor> {
  final controller = TextEditingController();
  late List<String> tags = widget.tags.customTags;
  bool invalid = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final String tag;
    try {
      tag = MatrixRoomTags.customTagFor(controller.text);
    } on InvalidRoomTag {
      setState(() => invalid = true);
      return;
    }
    setState(() => invalid = false);
    await ErrorUtils.tryRun(context, () async {
      await widget.tags.addCustomTag(tag);
      controller.clear();
      if (mounted && !tags.contains(tag)) setState(() => tags = [...tags, tag]);
    });
  }

  Future<void> remove(String tag) => ErrorUtils.tryRun(context, () async {
        await widget.tags.removeCustomTag(tag);
        if (mounted) setState(() => tags = [...tags]..remove(tag));
      });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isEmpty)
            tiamat.Text.labelLow(RoomPanelActions.labelRoomTagsEmpty),
          for (final tag in tags)
            Row(children: [
              const Icon(Icons.label_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: tiamat.Text.label(
                      tag.substring(MatrixRoomTags.customPrefix.length))),
              IconButton(
                tooltip: RoomPanelActions.promptRoomRemoveTag(
                    tag.substring(MatrixRoomTags.customPrefix.length)),
                icon: const Icon(Icons.close),
                onPressed: () => remove(tag),
              ),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: RoomTagsEditor.fieldKey,
                controller: controller,
                onSubmitted: (_) => add(),
                decoration: InputDecoration(
                  hintText: RoomPanelActions.hintRoomTagName,
                  errorText:
                      invalid ? RoomPanelActions.errorRoomTagInvalid : null,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            tiamat.Button(
                key: RoomTagsEditor.addKey,
                text: RoomPanelActions.promptRoomAddTag,
                onTap: add),
          ]),
        ],
      ),
    );
  }
}
