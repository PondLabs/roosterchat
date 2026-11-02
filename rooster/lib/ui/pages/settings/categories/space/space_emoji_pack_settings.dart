import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:rooster/ui/pages/settings/categories/space/space_emoji_settings_view.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceEmojiPackSettings extends StatefulWidget {
  final Space space;
  const SpaceEmojiPackSettings(this.space, {super.key});

  @override
  State<SpaceEmojiPackSettings> createState() => _SpaceEmojiPackSettingsState();
}

class _SpaceEmojiPackSettingsState extends State<SpaceEmojiPackSettings> {
  late SpaceEmoticonComponent component;

  String get labelSpaceEmojiPacks => Intl.message("Emoji packs",
      name: "labelSpaceEmojiPacks",
      desc:
          "Header in a space's emoticon settings, over the emoji and sticker packs the space has");

  String get labelSpaceEmojiPacksDescription => Intl.message(
      "Server emojis are stored in a pack of their own. Packs can also "
      "hold stickers and be imported in bulk.",
      name: "labelSpaceEmojiPacksDescription",
      desc:
          "Under the 'Emoji packs' header of a space's emoticon settings. 'Server emojis' are the space's own emoji listed above it (as Discord's server emoji)");

  @override
  void initState() {
    component = widget.space.getComponent<SpaceEmoticonComponent>()!;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.space.permissions.canEditRoomEmoticons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpaceEmojiSettingsView(component: component, editable: editable),
        const SizedBox(height: 24),
        tiamat.Text.labelEmphasised(labelSpaceEmojiPacks),
        tiamat.Text.labelLow(labelSpaceEmojiPacksDescription),
        const SizedBox(height: 8),
        RoomEmojiPackSettingsView(
          component: component,
          editable: editable,
        ),
      ],
    );
  }
}
