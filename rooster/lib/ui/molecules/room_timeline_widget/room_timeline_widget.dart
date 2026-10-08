import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/timeline_selection_area.dart';
import 'package:flutter/material.dart';

class RoomTimelineWidget extends StatefulWidget {
  const RoomTimelineWidget(
      {required this.timeline,
      this.setEditingEvent,
      this.setReplyingEvent,
      this.isThreadTimeline = false,
      this.clearNotifications,
      super.key});
  final Timeline timeline;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(Room room)? clearNotifications;
  final bool isThreadTimeline;

  @override
  State<RoomTimelineWidget> createState() => _RoomTimelineWidgetState();
}

class _RoomTimelineWidgetState extends State<RoomTimelineWidget>
    with WidgetsBindingObserver {
  GlobalKey timelineViewKey = GlobalKey();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A new message at the bottom is marked read by the view, which is the
  // one that knows whether the reader is there (it calls markAsRead when
  // attached); this used to ask as well, for a second request per message.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
      if (state?.attachedToBottom == true &&
          widget.timeline.events.isNotEmpty) {
        markAsRead(widget.timeline.events.first);
        widget.clearNotifications?.call(widget.timeline.room);
      }
    }

    super.didChangeAppLifecycleState(state);
  }

  Future<void> markAsRead(TimelineEvent event) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    widget.timeline.markAsRead(event);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = RoomTimelineWidgetView(
      key: timelineViewKey,
      timeline: widget.timeline,
      onAttachedToBottom: onAttachedToBottom,
      isThreadTimeline: widget.isThreadTimeline,
      setReplyingEvent: widget.setReplyingEvent,
      setEditingEvent: widget.setEditingEvent,
      markAsRead: markAsRead,
    );

    if (MediaQuery.of(context).desktop) {
      result = TimelineSelectionArea(child: result);
    }

    return result;
  }

  void onAttachedToBottom() {
    if (widget.timeline.events.isNotEmpty) {
      markAsRead(widget.timeline.events.first);
      widget.clearNotifications?.call(widget.timeline.room);
    }
  }
}
