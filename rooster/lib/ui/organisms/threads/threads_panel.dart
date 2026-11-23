import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_list.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/client/timeline_events/timeline_event_sticker.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/molecules/timeline_events/thread_unread_badge.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A room's threads, newest activity first: all of them, or the ones we
/// take part in. Picking one opens it beside the chat.
class ThreadsPanel extends StatefulWidget {
  const ThreadsPanel({required this.room, this.onOpenThread, super.key});

  final MatrixRoom room;

  /// Opens a thread by its root's id; by default in the room's side panel,
  /// closing the dialog this panel is in.
  final void Function(String threadRootId)? onOpenThread;

  static String get labelThreads => Intl.message("Threads",
      name: "labelThreads",
      desc: "Title of the panel that lists a room's threads, and the room "
          "menu entry that opens it");

  static String get labelThreadsFilterAll => Intl.message("All threads",
      name: "labelThreadsFilterAll",
      desc: "Filter of the threads panel that shows every thread of the room");

  static String get labelThreadsFilterParticipated => Intl.message("My threads",
      name: "labelThreadsFilterParticipated",
      desc: "Filter of the threads panel that shows only the threads the user "
          "started or replied in");

  static String get messageNoThreads => Intl.message("No threads here yet",
      name: "messageNoThreads",
      desc: "Shown in the threads panel when the room has no thread");

  static String get messageNoParticipatedThreads =>
      Intl.message("You haven't started or replied in a thread here yet",
          name: "messageNoParticipatedThreads",
          desc: "Shown in the threads panel, filtered to the user's threads, "
              "when the user has none in the room");

  static String get errorThreadsLoadFailed => Intl.message(
      "Couldn't load the threads",
      name: "errorThreadsLoadFailed",
      desc: "Shown in the threads panel when the server did not answer with "
          "the room's threads");

  static String labelThreadReplyCount(int count) => Intl.plural(count,
      zero: "No replies",
      one: "1 reply",
      other: "$count replies",
      name: "labelThreadReplyCount",
      args: [count],
      desc: "How many replies a thread has, in the threads panel");

  static String get labelThreadUnknownSender => Intl.message("Unknown sender",
      name: "labelThreadUnknownSender",
      desc: "Stands in for the name of who started a thread, in the threads "
          "panel, while it is not known");

  static String labelThreadLatestReply(String sender, String body) =>
      Intl.message("$sender: $body",
          name: "labelThreadLatestReply",
          args: [sender, body],
          desc: "Under a thread in the threads panel: who sent its latest "
              "reply and what it says");

  @override
  State<ThreadsPanel> createState() => ThreadsPanelState();
}

class ThreadsPanelState extends State<ThreadsPanel> {
  ThreadListFilter filter = ThreadListFilter.all;
  late MatrixThreadList list;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    list = MatrixThreadList(widget.room, filter: filter);
    _changes = list.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    list.loadMore();
  }

  void setFilter(ThreadListFilter value) {
    if (value == filter) return;
    _changes?.cancel();
    list.close();
    setState(() {
      filter = value;
      _start();
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    list.close();
    super.dispose();
  }

  void open(String threadRootId) {
    final onOpen = widget.onOpenThread;
    if (onOpen != null) {
      onOpen(threadRootId);
      return;
    }
    Navigator.of(context).maybePop();
    EventBus.openThread.add(
        (widget.room.client.identifier, widget.room.identifier, threadRootId));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.desktop ? 440 : size.width,
      height: min(560, size.height * 0.7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (value, label) in [
                  (ThreadListFilter.all, ThreadsPanel.labelThreadsFilterAll),
                  (
                    ThreadListFilter.participated,
                    ThreadsPanel.labelThreadsFilterParticipated
                  ),
                ])
                  ChoiceChip(
                    key: ValueKey("threads-filter-${value.name}"),
                    label: Text(label),
                    selected: filter == value,
                    onSelected: (_) => setFilter(value),
                  ),
              ],
            ),
          ),
          Expanded(child: body()),
        ],
      ),
    );
  }

  Widget body() {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: tiamat.Text.labelLow(
            filter == ThreadListFilter.participated
                ? ThreadsPanel.messageNoParticipatedThreads
                : ThreadsPanel.messageNoThreads,
          ),
        ),
      );
    }

    if (list.entries.isEmpty && list.error != null && !list.isLoading) {
      return failed();
    }

    final hasTail = list.hasMore || list.error != null;
    return ListView.builder(
      itemCount: list.entries.length + (hasTail ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < list.entries.length) {
          return entry(list.entries[index]);
        }
        if (list.error != null && !list.isLoading) return failed();
        // The end of the list came into view: the next page.
        if (!list.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) list.loadMore();
          });
        }
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget failed() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Text.labelLow(ThreadsPanel.errorThreadsLoadFailed),
            const SizedBox(height: 8),
            tiamat.Button.secondary(
              text: CommonStrings.promptRetry,
              onTap: () => list.loadMore(),
            ),
          ],
        ),
      );

  static String _preview(TimelineEvent event) {
    if (event is TimelineEventMessage) return event.body ?? "";
    if (event is TimelineEventSticker) return event.stickerName;
    return event.plainTextBody;
  }

  Widget entry(ThreadListEntry entry) {
    final room = widget.room;
    final sender = room.getMemberOrFallback(entry.root.senderId);
    final latest = entry.latestReply;
    final latestSender =
        latest == null ? null : room.getMemberOrFallback(latest.senderId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey("thread-entry-${entry.threadRootId}"),
        borderRadius: BorderRadius.circular(8),
        onTap: () => open(entry.threadRootId),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Avatar(
                image: sender.avatar,
                placeholderColor: sender.defaultColor,
                placeholderText: sender.displayName,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text(
                      sender.displayName.isEmpty
                          ? ThreadsPanel.labelThreadUnknownSender
                          : sender.displayName,
                      color: sender.defaultColor,
                      maxLines: 1,
                      autoAdjustBrightness: true,
                    ),
                    tiamat.Text.body(
                      _preview(entry.root),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    tiamat.Text.labelLow(
                      ThreadsPanel.labelThreadReplyCount(entry.replyCount),
                      maxLines: 1,
                    ),
                    if (latest != null && latestSender != null)
                      tiamat.Text.labelLow(
                        ThreadsPanel.labelThreadLatestReply(
                            latestSender.displayName, _preview(latest)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ThreadUnreadBadge(
                room: room.matrixRoom,
                threadRootId: entry.threadRootId,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
