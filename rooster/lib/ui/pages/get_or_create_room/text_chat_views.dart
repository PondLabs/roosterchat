import 'dart:math';

import 'package:rooster/ui/atoms/emoji_reaction.dart';
import 'package:rooster/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TextChatCreatorDescription extends StatelessWidget {
  const TextChatCreatorDescription({super.key});

  String get labelTextChatDescription => Intl.message(
      "Simple text chat, with all the features you could want! Send messages, media, stickers, GIFs and more!",
      name: "labelTextChatDescription");

  // A made-up chat between two friends, in the picture of a text chat in the
  // dialog that adds a room. Casual, typed fast, lowercase where the English
  // is.

  String get labelRoomSampleMessageSerialGamer => Intl.message(
      "This guy is a serial gamer",
      name: "labelRoomSampleMessageSerialGamer",
      desc:
          "Example chat message (teasing a friend who plays games all the time) in the picture of a text chat, in the dialog that adds a room");

  String get labelRoomSampleMessageGrind => Intl.message(
      "Gotta stay on that grind",
      name: "labelRoomSampleMessageGrind",
      desc:
          "Example chat message (the friend answering that he has to keep playing hard) in the picture of a text chat, in the dialog that adds a room");

  String get labelRoomSampleMessagePlay => Intl.message(
      "u still wanna play smth?",
      name: "labelRoomSampleMessagePlay",
      desc:
          "Example chat message, typed casually ('you still want to play something?'), in the picture of a text chat, in the dialog that adds a room");

  String get labelRoomSampleMessageIceCream => Intl.message(
      "yea just gimme 1 sec im eating icecream 😋",
      name: "labelRoomSampleMessageIceCream",
      desc:
          "Example chat message, typed casually ('yes, just give me a second, I'm eating ice cream'), in the picture of a text chat, in the dialog that adds a room. Keep the emoji");

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      tiamat.Text.labelLow(labelTextChatDescription),
      SizedBox(
        height: 16,
      ),
      Column(
        children: [
          TimelineEventLayoutMessage(
            senderName: "pluto",
            timestamp: "8:17",
            senderColor: Colors.pinkAccent.shade400,
            senderAvatar: AssetImage("assets/images/placeholders/avatar1.jpg"),
            formattedContent:
                tiamat.Text.body(labelRoomSampleMessageSerialGamer),
          ),
          TimelineEventLayoutMessage(
            senderName: "luna",
            timestamp: "8:30",
            senderAvatar: AssetImage("assets/images/placeholders/avatar2.jpg"),
            senderColor: Colors.cyanAccent,
            formattedContent: tiamat.Text.body(labelRoomSampleMessageGrind),
          ),
          TimelineEventLayoutMessage(
            senderName: "luna",
            timestamp: "8:31",
            senderColor: Colors.cyanAccent,
            senderAvatar: AssetImage("assets/images/placeholders/avatar2.jpg"),
            formattedContent: tiamat.Text.body(labelRoomSampleMessagePlay),
          ),
          TimelineEventLayoutMessage(
            senderName: "pluto",
            timestamp: "8:35",
            senderColor: Colors.pinkAccent.shade400,
            senderAvatar: AssetImage("assets/images/placeholders/avatar1.jpg"),
            formattedContent: tiamat.Text.body(labelRoomSampleMessageIceCream),
            reactions:
                EmojiReaction(emoji: UnicodeEmoticon("🔥"), numReactions: 1),
          )
        ]
            .mapIndexed((e, i) => Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Transform.rotate(
                    angle: (Random((i + 12) * 7).nextDouble() - 0.5) * 0.04,
                    child: Material(
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        color: ColorScheme.of(context).surfaceContainerLow,
                        child: InkWell(
                          onTap: () {},
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: e,
                          ),
                        )),
                  ),
                ))
            .toList(),
      )
    ]);
  }
}

class TextChatCreatorForm extends StatefulWidget {
  const TextChatCreatorForm({super.key});

  @override
  State<TextChatCreatorForm> createState() => _TextChatCreatorFormState();
}

class _TextChatCreatorFormState extends State<TextChatCreatorForm> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
