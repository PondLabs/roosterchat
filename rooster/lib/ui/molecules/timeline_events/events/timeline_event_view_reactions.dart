import 'package:intl/intl.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/atoms/emoji_reaction.dart';
import 'package:rooster/ui/atoms/emoji_widget.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:rooster/ui/molecules/user_panel.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:flutter/material.dart' as material;

class TimelineEventViewReactions extends StatefulWidget {
  const TimelineEventViewReactions(
      {required this.initialIndex, required this.timeline, super.key});

  final int initialIndex;
  final Timeline timeline;

  @override
  State<TimelineEventViewReactions> createState() =>
      _TimelineEventViewReactionsState();
}

class _TimelineEventViewReactionsState extends State<TimelineEventViewReactions>
    implements TimelineEventViewWidget {
  Map<Emoticon, Set<String>>? reactions;

  late final String? currentUserIdentifier;
  late int index;

  /// Whether we have reacted with an emoticon, as the user last asked for,
  /// until the timeline catches up. Keeps the chip from flickering back and a
  /// second tap from reacting again while the first is still in flight.
  final Map<Emoticon, bool> pendingOwnReactions = {};

  static const tooltipNameLimit = 3;

  String get labelReactionTooltipYou => Intl.message("You",
      desc: "Stands for the current user in the list of who reacted",
      name: "labelReactionTooltipYou");

  String labelReactionTooltipOthers(int howMany) => Intl.plural(howMany,
      one: "and 1 other",
      other: "and $howMany others",
      desc: "Ends the list of who reacted when there are too many names",
      name: "labelReactionTooltipOthers",
      args: [howMany]);

  String labelReactionTooltipReactedWith(int howMany, String emoji) =>
      Intl.plural(howMany,
          one: "reacted with $emoji",
          other: "reacted with $emoji",
          desc: "Follows the names of who reacted, in the reaction tooltip",
          name: "labelReactionTooltipReactedWith",
          args: [howMany, emoji]);

  @override
  void initState() {
    currentUserIdentifier = widget.timeline.client.self?.identifier;
    setStateFromIndex(widget.initialIndex);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (reactions == null) {
      return Container();
    }

    return Wrap(
        spacing: 3,
        runSpacing: 3,
        direction: material.Axis.horizontal,
        children: reactions!.keys
            .map((key) {
              var value = displayedSenders(key);
              if (value.isEmpty) return null;

              return EmojiReaction(
                  emoji: key,
                  onTapped: onReactionTapped,
                  onLongPressed: (emote) => showReactors(key, value),
                  tooltip: buildTooltip(key, value),
                  numReactions: value.length,
                  highlighted: value.contains(currentUserIdentifier));
            })
            .nonNulls
            .toList());
  }

  /// Who reacted with [emote], with our pending tap already applied.
  Set<String> displayedSenders(Emoticon emote) {
    var senders = reactions![emote] ?? const <String>{};
    var pending = pendingOwnReactions[emote];
    var self = currentUserIdentifier;
    if (pending == null || self == null) return senders;

    return pending ? {...senders, self} : ({...senders}..remove(self));
  }

  Widget buildTooltip(Emoticon emote, Set<String> senders) {
    var colors = Theme.of(context).colorScheme;

    var names = senders.take(tooltipNameLimit).map((id) {
      if (id == currentUserIdentifier) return labelReactionTooltipYou;
      return widget.timeline.room.getMemberOrFallback(id).displayName;
    }).join(", ");

    var others = senders.length - tooltipNameLimit;
    if (others > 0) names = "$names ${labelReactionTooltipOthers(others)}";

    var shortcode = emote.shortcode;
    var emojiName =
        shortcode != null && shortcode.isNotEmpty ? ":$shortcode:" : emote.key;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmojiWidget(emote, height: 32),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.name(names),
                tiamat.Text.labelLow(
                  labelReactionTooltipReactedWith(senders.length, emojiName),
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showReactors(Emoticon emote, Set<String> senders) {
    AdaptiveDialog.show(
      context,
      scrollable: false,
      builder: (context) => SizedBox(
        height: 400,
        width: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: EmojiWidget(
                emote,
                height: 40,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: senders.length,
                itemBuilder: (context, index) {
                  final id = senders.elementAt(index);
                  return UserPanel(
                      userId: id,
                      contextRoom: widget.timeline.room,
                      client: widget.timeline.client);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> onReactionTapped(Emoticon emote) async {
    if (reactions == null || pendingOwnReactions.containsKey(emote)) {
      return;
    }

    var event = widget.timeline.events[index];
    var react = reactions![emote]?.contains(currentUserIdentifier) != true;
    setState(() => pendingOwnReactions[emote] = react);

    try {
      if (react) {
        await widget.timeline.room.addReaction(event, emote);
      } else {
        await widget.timeline.room.removeReaction(event, emote);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to toggle reaction");
      if (mounted) setState(() => pendingOwnReactions.remove(emote));
      return;
    }

    // A cancelled local echo leaves the timeline without telling us
    if (mounted) setStateFromIndex(index);

    // Never leave the chip stuck if sync doesn't bring the change back
    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted || pendingOwnReactions[emote] != react) return;
      setState(() => pendingOwnReactions.remove(emote));
    });
  }

  @override
  void update(int newIndex) {
    setStateFromIndex(newIndex);
  }

  void setStateFromIndex(int index) {
    setState(() {
      this.index = index;
      final event = widget.timeline.events[index];
      if (event is TimelineEventFeatureReactions) {
        reactions = (event as TimelineEventFeatureReactions)
            .getReactions(widget.timeline);
      }

      // Drop what the timeline now shows, keep what is still on its way
      pendingOwnReactions.removeWhere((emote, react) =>
          (reactions?[emote]?.contains(currentUserIdentifier) ?? false) ==
          react);
    });
  }
}
