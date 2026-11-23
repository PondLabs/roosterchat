import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/threads/matrix_thread_unread.dart';

/// How many unread notifications a thread has, on its root in the
/// timeline and in the threads panel: red when one of them calls on us,
/// gone once they are read.
class ThreadUnreadBadge extends StatefulWidget {
  const ThreadUnreadBadge(
      {required this.room, required this.threadRootId, super.key});

  final matrix.Room room;
  final String threadRootId;

  static String tooltipThreadUnread(int count) => Intl.plural(count,
      one: "1 unread notification in this thread",
      other: "$count unread notifications in this thread",
      name: "tooltipThreadUnread",
      args: [count],
      desc: "Tooltip of the count of unread notifications on a thread, under "
          "its first message and in the room's list of threads");

  @override
  State<ThreadUnreadBadge> createState() => _ThreadUnreadBadgeState();
}

class _ThreadUnreadBadgeState extends State<ThreadUnreadBadge> {
  StreamSubscription<void>? _changes;
  late ThreadUnreadCounts _counts;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ThreadUnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room ||
        oldWidget.threadRootId != widget.threadRootId) {
      _changes?.cancel();
      _listen();
    }
  }

  void _listen() {
    _counts = MatrixThreadUnread.of(widget.room, widget.threadRootId);
    _changes = MatrixThreadUnread.changes(widget.room).listen((_) {
      final counts = MatrixThreadUnread.of(widget.room, widget.threadRootId);
      if (mounted && counts != _counts) setState(() => _counts = counts);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_counts.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final highlight = _counts.highlights > 0;
    // A highlight with no other notification still shows a count.
    final count =
        _counts.notifications > 0 ? _counts.notifications : _counts.highlights;
    final background = highlight ? Colors.red.shade600 : scheme.secondary;
    final foreground = highlight ? Colors.white : scheme.onSecondary;

    return Tooltip(
      message: ThreadUnreadBadge.tooltipThreadUnread(count),
      child: Container(
        key: ValueKey(highlight
            ? "thread-unread-badge-highlight"
            : "thread-unread-badge"),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          // Not translated: a number, formatted for the app's language.
          count > 99 ? "99+" : NumberFormat.decimalPattern().format(count),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
              fontWeight: FontWeight.bold, fontSize: 10, color: foreground),
        ),
      ),
    );
  }
}
