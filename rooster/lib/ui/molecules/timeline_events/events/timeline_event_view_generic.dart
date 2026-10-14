import 'package:rooster/client/client.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_add_reaction.dart';
import 'package:rooster/client/timeline_events/timeline_event_generic.dart';
import 'package:rooster/ui/molecules/read_indicator.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart' as m;

import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:tiamat/atoms/avatar.dart';

class TimelineEventViewGeneric extends StatefulWidget {
  const TimelineEventViewGeneric(
      {this.timeline,
      this.initialEvent,
      required this.initialIndex,
      this.room,
      this.onReadReceiptsTapped,
      this.readReceipts = const [],
      this.jumpToEvent,
      super.key});
  final Timeline? timeline;
  final int initialIndex;
  final Room? room;
  final Function()? onReadReceiptsTapped;
  final List<String> readReceipts;
  final TimelineEvent? initialEvent;

  /// Where a reaction's row leads: the message it is on.
  final Function(String eventId, {bool highlight})? jumpToEvent;

  @override
  State<TimelineEventViewGeneric> createState() =>
      _TimelineEventViewGenericState();
}

class _TimelineEventViewGenericState extends State<TimelineEventViewGeneric>
    implements TimelineEventViewWidget {
  String? text;

  /// For a reaction, which message it is on.
  String? subtitle;
  String? reactsTo;
  IconData? icon;
  ImageProvider? senderAvatar;

  String messagePlaceholderSticker(String user) =>
      Intl.message("$user sent a sticker",
          desc: "Message body for when a user sends a sticker",
          args: [user],
          name: "messagePlaceholderSticker");

  String labelReactionOnMessage(String message) => Intl.message("On “$message”",
      desc: "Under a reaction shown as its own row in the timeline "
          "(developer mode): the start of the message it was on",
      args: [message],
      name: "labelReactionOnMessage");

  String get labelReactionOnUnloadedMessage =>
      Intl.message("On an older message that is not loaded",
          desc: "Under a reaction shown as its own row in the timeline "
              "(developer mode), when the message it was on is not loaded",
          name: "labelReactionOnUnloadedMessage");

  String get errorMessageFailedToSend => Intl.message("Failed to send",
      desc:
          "Text that is placed below a message when the message fails to send",
      name: "errorMessageFailedToSend");

  @override
  void initState() {
    if (widget.timeline != null) {
      setStateFromindex(widget.initialIndex);
    }

    if (widget.initialEvent != null) {
      loadStateFromEvent(widget.initialEvent!);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return Container();
    }

    final target = reactsTo;
    return m.Material(
      color: m.Colors.transparent,
      child: m.InkWell(
        onTap: target == null || widget.jumpToEvent == null
            ? null
            : () => widget.jumpToEvent!(target, highlight: true),
        child: Row(
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Row(
                      children: [
                        if (icon != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(44, 0, 8, 0),
                            child: Icon(
                              icon,
                              size: 20,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        if (senderAvatar != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(44, 0, 8, 0),
                            child: Avatar(
                              image: senderAvatar,
                              radius: 10,
                            ),
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              tiamat.Text.labelLow(text!),
                              if (subtitle != null)
                                tiamat.Text.labelLow(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.room != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                child: SizedBox(
                  width: 35,
                  child: ReadIndicator(
                    room: widget.room!,
                    users: widget.readReceipts,
                    onTap: widget.onReadReceiptsTapped,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  @override
  void update(int newIndex) {
    setStateFromindex(newIndex);
  }

  void setStateFromindex(int index) {
    var event = widget.timeline!.events[index];
    loadStateFromEvent(event);
  }

  void loadStateFromEvent(TimelineEvent event) {
    var room = widget.room ?? widget.timeline?.room;
    if (event is TimelineEventAddReaction) {
      text = event.plainTextBody;
      icon = Icons.add_reaction_outlined;
      reactsTo = event.reactsTo;
      final target =
          reactsTo == null ? null : widget.timeline?.tryGetEvent(reactsTo!);
      subtitle = target == null
          ? labelReactionOnUnloadedMessage
          : labelReactionOnMessage(
              target.plainTextBody.replaceAll(RegExp(r'\s+'), ' ').trim());
      return;
    }

    if (event is! TimelineEventGeneric) {
      text = event.plainTextBody;
      icon = Icons.question_mark;
      return;
    }

    text = event.getBody(timeline: widget.timeline);
    icon = event.icon;

    var sender = room!.getMemberOrFallback(event.senderId);
    if (event.showSenderAvatar) {
      senderAvatar = sender.avatar;
    }
  }
}
