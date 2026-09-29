import 'dart:typed_data';

import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/client_manager.dart';
import 'package:cockhouse/client/components/emoticon/emoticon.dart';
import 'package:cockhouse/client/components/emoticon/emoji_pack.dart';
import 'package:cockhouse/client/components/emoticon/emoticon_component.dart';
import 'package:cockhouse/ui/pages/settings/categories/account/account_emoji/account_emoji_view.dart';
import 'package:cockhouse/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:flutter/widgets.dart';

import '../../../../../molecules/account_selector.dart';

class AccountEmojiTab extends StatefulWidget {
  const AccountEmojiTab(
      {required this.clientManager, this.selectedClientIndex = 0, super.key});
  final ClientManager clientManager;
  final int selectedClientIndex;
  @override
  State<AccountEmojiTab> createState() => _AccountEmojiTabState();
}

class _AccountEmojiTabState extends State<AccountEmojiTab> {
  Client? selectedClient;
  EmoticonComponent? component;

  @override
  void initState() {
    selectedClient = widget.clientManager.clients[widget.selectedClientIndex];
    component = selectedClient!.getComponent<EmoticonComponent>();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            onClientSelected: (client) {
              setState(() {
                selectedClient = client;
                component = selectedClient!.getComponent<EmoticonComponent>();
              });
            },
          ),
        const SizedBox(
          height: 10,
        ),
        buildEmojiView(context)
      ],
    );
  }

  Widget buildEmojiView(BuildContext context) {
    if (component == null) {
      return const Placeholder();
    }

    return Column(
      // I dont love using a key here, is there a better way to do this? i dont know
      key: ValueKey("account_emoji_editor_key_${selectedClient!.identifier}"),
      children: [
        RoomEmojiPackSettingsView(
          component: component!,
          editable: true,
        ),
        const SizedBox(
          height: 5,
        ),
        if (component!.globalPacks().isNotEmpty) AccountEmojiView(component!),
      ],
    );
  }

  Future<void> createPack(String name, Uint8List? avatarData) {
    return component!.createEmoticonPack(name, avatarData);
  }

  Future<void> deleteEmoticon(EmoticonPack pack, Emoticon emoticon) {
    return pack.deleteEmoticon(emoticon);
  }

  Future<void> deletePack(EmoticonPack pack) {
    return component!.deleteEmoticonPack(pack);
  }
}
