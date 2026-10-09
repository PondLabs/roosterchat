import 'dart:async';

import 'package:rooster/client/components/emoticon/emoji_pack.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountEmojiView extends StatefulWidget {
  const AccountEmojiView(this.component, {super.key});
  final EmoticonComponent component;
  @override
  State<AccountEmojiView> createState() => _AccountEmojiViewState();
}

class _AccountEmojiViewState extends State<AccountEmojiView> {
  late List<EmoticonPack> globalPacks;
  StreamSubscription? sub;

  String get labelSettingsFavoriteEmojiPacks => Intl.message("Favorite Packs",
      name: "labelSettingsFavoriteEmojiPacks",
      desc: "Settings > Account > Emoticons: header of the list of emoji and "
          "sticker packs you marked as favorite, to use them everywhere");

  @override
  void initState() {
    sub = widget.component.onStateChanged.listen((_) => updateState());
    updateState();
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  void updateState() {
    if (!mounted) return;
    setState(() {
      globalPacks = widget.component.globalPacks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        tiamat.Panel(
          header: labelSettingsFavoriteEmojiPacks,
          mode: tiamat.TileType.surfaceContainerLow,
          child:
              Column(children: globalPacks.map((e) => packSummary(e)).toList()),
        ),
      ],
    );
  }

  Widget packSummary(EmoticonPack pack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (pack.image != null)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Image(
                        image: pack.image!,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          tiamat.Text.labelEmphasised(pack.displayName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          tiamat.Text.labelLow(
                              preferences.developerMode.value
                                  ? "${pack.ownerDisplayName} - (${pack.ownerId})"
                                  : pack.ownerDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: tiamat.IconButton(
                icon: Icons.heart_broken,
                onPressed: () => pack.markAsGlobal(false),
              ),
            )
          ],
        ),
      ),
    );
  }
}
