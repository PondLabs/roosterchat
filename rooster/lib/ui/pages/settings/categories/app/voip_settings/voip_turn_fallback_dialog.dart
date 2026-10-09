import 'package:rooster/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipTurnFallbackDialog extends StatefulWidget {
  const VoipTurnFallbackDialog(this.homeserver, {super.key});
  final Uri homeserver;

  @override
  State<VoipTurnFallbackDialog> createState() => _VoipTurnFallbackDialogState();
}

class _VoipTurnFallbackDialogState extends State<VoipTurnFallbackDialog> {
  String messageVoipTurnFallback(String homeserver, String fallbackServer) =>
      Intl.message(
          "Your homeserver `($homeserver)` is not configured to route calls. "
          "Would you like to fall back to a separate server "
          "`($fallbackServer)` to handle routing?",
          name: "messageVoipTurnFallback",
          args: [homeserver, fallbackServer],
          desc: "Asked when a call is placed and the homeserver, whose "
              "address is given, offers no server to route calls through; "
              "the second address is the fallback server. Markdown: keep the "
              "backticks around each address");

  String get messageVoipTurnFallbackPrivacy => Intl.message(
      "Without a server to route, calls cannot be connected. Your IP Address "
      "will be shared with the fallback server",
      name: "messageVoipTurnFallbackPrivacy",
      desc: "Under the question whether to route calls through a fallback "
          "server, when the homeserver has none");

  String get promptVoipUseFallbackServer => Intl.message("Use fallback server",
      name: "promptVoipUseFallbackServer",
      desc: "Button that routes calls through the fallback server, when the "
          "homeserver has no server to route them");

  String get promptVoipCancelCall => Intl.message("Cancel call",
      name: "promptVoipCancelCall",
      desc: "Button that gives up on the call rather than route it through "
          "the fallback server");

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Markdown(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                data: messageVoipTurnFallback(widget.homeserver.toString(),
                    preferences.fallbackTurnServer.value)),
            const SizedBox(
              height: 20,
            ),
            tiamat.Text.labelLow(messageVoipTurnFallbackPrivacy),
            const SizedBox(
              height: 20,
            ),
            Row(
              children: [
                Expanded(
                  child: tiamat.Button(
                    text: promptVoipUseFallbackServer,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                const SizedBox(
                  width: 20,
                ),
                Expanded(
                  child: tiamat.Button.secondary(
                      text: promptVoipCancelCall,
                      onTap: () => Navigator.of(context).pop(false)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
