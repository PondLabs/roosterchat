import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// An `m.notice` message: sent by a bot or a service, not typed by a
/// person. Marked with a robot and a line down its side, its text a tone
/// quieter, so it never reads as someone's message.
class TimelineEventViewNotice extends StatelessWidget {
  const TimelineEventViewNotice({this.child, super.key});

  /// The notice's text.
  final Widget? child;

  static const markerKey = ValueKey('notice-marker');

  static String get labelNotice => Intl.message("Automated notice",
      name: "labelNotice",
      desc: "Marks a message in the chat that a bot or a service sent (a "
          "Matrix notice), not a person");

  static String get tooltipNotice =>
      Intl.message("Sent by a bot or a service, not typed by a person",
          name: "tooltipNotice",
          desc: "Tooltip of the mark on a message that a bot or a service "
              "sent (a Matrix notice)");

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
          border:
              Border(left: BorderSide(color: colors.outlineVariant, width: 3))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: tooltipNotice,
            child: Row(
              key: markerKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined,
                    size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: tiamat.Text.labelLow(labelNotice,
                      color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (child != null)
            DefaultTextStyle.merge(
              style: TextStyle(color: colors.onSurfaceVariant),
              child: child!,
            ),
        ],
      ),
    );
  }
}
