import 'package:rooster/ui/atoms/emoji_widget.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class MatrixVerificationPageView extends StatelessWidget {
  const MatrixVerificationPageView(
      {required this.state,
      required this.sasTypes,
      required this.sasNumbers,
      required this.sasEmoji,
      required this.userID,
      super.key,
      this.onVerificationRequestAccepted,
      this.onVerificationRequestRejected,
      this.onSasAccepted,
      this.onSasRejected});

  final Function? onVerificationRequestAccepted;
  final Function? onVerificationRequestRejected;
  final Function? onSasAccepted;
  final Function? onSasRejected;
  final List<String> sasTypes;
  final List<KeyVerificationEmoji> sasEmoji;
  final List<int> sasNumbers;
  final String userID;

  final KeyVerificationState state;

  String get messageWaitingOtherDeviceToAccept => Intl.message(
      "Waiting for the other device to accept the request",
      name: "messageWaitingOtherDeviceToAccept",
      desc:
          "Message to show while waiting for another device to accept a matrix session verification request");

  String messageMatrixSessionVerificationRequest(String username) => Intl.message(
      "**$username** has requested to verify your session",
      desc:
          "Message to show when another user has requested to verify your matrix session. Supports markdown to emphasise the user name",
      args: [username],
      name: "messageMatrixSessionVerificationRequest");

  String get messageSasEmojiVerificationPrompt => Intl.message(
      "Check that the emoji are the same, and in the same order as on the other device",
      name: "messageSasEmojiVerificationPrompt",
      desc:
          "Explains what to look for when verifying using emoji. Needs to portray that the emoji MUST be the same AND in the same order");

  String get promptConfirmEmojiMatches => Intl.message("They match!",
      name: "promptConfirmEmojiMatches",
      desc: "Button text to confirm that the emoji matches");

  String get promptEmojiDoNotMatch => Intl.message("They don't match",
      name: "promptEmojiDoNotMatch",
      desc: "Button text to confirm that the emoji do NOT match");

  String get messageVerificationComplete => Intl.message(
      "Verification Complete!",
      name: "messageVerificationComplete",
      desc:
          "Message to show when verification was completed successfully, and the session has been verified");

  /// The SAS emoji's names by their number (the Matrix spec's list), as
  /// the keys of [labelRoomVerificationEmojiName].
  static const _sasEmojiKeys = [
    "dog",
    "cat",
    "lion",
    "horse",
    "unicorn",
    "pig",
    "elephant",
    "rabbit",
    "panda",
    "rooster",
    "penguin",
    "turtle",
    "fish",
    "octopus",
    "butterfly",
    "flower",
    "tree",
    "cactus",
    "mushroom",
    "globe",
    "moon",
    "cloud",
    "fire",
    "banana",
    "apple",
    "strawberry",
    "corn",
    "pizza",
    "cake",
    "heart",
    "smiley",
    "robot",
    "hat",
    "glasses",
    "spanner",
    "santa",
    "thumbsUp",
    "umbrella",
    "hourglass",
    "clock",
    "gift",
    "lightBulb",
    "book",
    "pencil",
    "paperclip",
    "scissors",
    "lock",
    "key",
    "hammer",
    "telephone",
    "flag",
    "train",
    "bicycle",
    "aeroplane",
    "rocket",
    "trophy",
    "ball",
    "guitar",
    "trumpet",
    "bell",
    "anchor",
    "headphones",
    "folder",
    "pin",
  ];

  String labelRoomVerificationEmojiName(String emoji) => Intl.select(
      emoji,
      {
        "dog": "Dog",
        "cat": "Cat",
        "lion": "Lion",
        "horse": "Horse",
        "unicorn": "Unicorn",
        "pig": "Pig",
        "elephant": "Elephant",
        "rabbit": "Rabbit",
        "panda": "Panda",
        "rooster": "Rooster",
        "penguin": "Penguin",
        "turtle": "Turtle",
        "fish": "Fish",
        "octopus": "Octopus",
        "butterfly": "Butterfly",
        "flower": "Flower",
        "tree": "Tree",
        "cactus": "Cactus",
        "mushroom": "Mushroom",
        "globe": "Globe",
        "moon": "Moon",
        "cloud": "Cloud",
        "fire": "Fire",
        "banana": "Banana",
        "apple": "Apple",
        "strawberry": "Strawberry",
        "corn": "Corn",
        "pizza": "Pizza",
        "cake": "Cake",
        "heart": "Heart",
        "smiley": "Smiley",
        "robot": "Robot",
        "hat": "Hat",
        "glasses": "Glasses",
        "spanner": "Spanner",
        "santa": "Santa",
        "thumbsUp": "Thumbs Up",
        "umbrella": "Umbrella",
        "hourglass": "Hourglass",
        "clock": "Clock",
        "gift": "Gift",
        "lightBulb": "Light Bulb",
        "book": "Book",
        "pencil": "Pencil",
        "paperclip": "Paperclip",
        "scissors": "Scissors",
        "lock": "Lock",
        "key": "Key",
        "hammer": "Hammer",
        "telephone": "Telephone",
        "flag": "Flag",
        "train": "Train",
        "bicycle": "Bicycle",
        "aeroplane": "Aeroplane",
        "rocket": "Rocket",
        "trophy": "Trophy",
        "ball": "Ball",
        "guitar": "Guitar",
        "trumpet": "Trumpet",
        "bell": "Bell",
        "anchor": "Anchor",
        "headphones": "Headphones",
        "folder": "Folder",
        "pin": "Pin",
        "other": "$emoji",
      },
      name: "labelRoomVerificationEmojiName",
      args: [emoji],
      desc:
          "The name under each emoji while verifying a session by comparing emoji (the Matrix spec's list of 64), picked by its English key. Translate each name; other is never shown");

  /// The name shown under a SAS emoji, in the app's language.
  String sasEmojiName(KeyVerificationEmoji emoji) {
    if (emoji.number < 0 || emoji.number >= _sasEmojiKeys.length) {
      return emoji.name;
    }
    return labelRoomVerificationEmojiName(_sasEmojiKeys[emoji.number]);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 350, width: 500, child: determineStage(context));
  }

  Widget determineStage(BuildContext context) {
    switch (state) {
      case KeyVerificationState.askAccept:
        return promptAcceptRequest(context);
      case KeyVerificationState.askSas:
        return promptAskSas(context);
      case KeyVerificationState.done:
        return done(context);
      case KeyVerificationState.waitingAccept:
        return Column(
          children: [
            tiamat.Text.label(messageWaitingOtherDeviceToAccept),
            loading(context)
          ],
        );
      case KeyVerificationState.waitingSas:
        return loading(context);
      default:
        return tiamat.Text.label(state.toString());
    }
  }

  Widget promptAcceptRequest(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Markdown(
                data: messageMatrixSessionVerificationRequest(userID))),
        Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Button.success(
                  text: CommonStrings.promptAccept,
                  onTap: onVerificationRequestAccepted?.call),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Button.danger(
                text: CommonStrings.promptReject,
                onTap: onVerificationRequestRejected?.call,
              ),
            )
          ],
        ),
      ],
    );
  }

  Widget promptAskSas(BuildContext context) {
    if (sasTypes.contains('emoji')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text.label(messageSasEmojiVerificationPrompt),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Wrap(
              spacing: 15,
              runSpacing: 5,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: sasEmoji
                  .map((e) => Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            EmojiWidget(
                              UnicodeEmoticon(e.emoji),
                              height: 30,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: tiamat.Text.tiny(sasEmojiName(e)),
                            )
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Button.success(
                      text: promptConfirmEmojiMatches,
                      onTap: onSasAccepted?.call),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Button.danger(
                    text: promptEmojiDoNotMatch,
                    onTap: onSasRejected?.call,
                  ),
                )
              ],
            ),
          )
        ],
      );
    }
    return const Placeholder();
  }

  Widget done(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
              child: Center(
                  child: Icon(
            Icons.verified_user_rounded,
            color: Colors.green,
            size: 100,
          ))),
          Button.success(
            text: messageVerificationComplete,
            onTap: () => Navigator.pop(context),
          )
        ]);
  }

  Widget loading(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
