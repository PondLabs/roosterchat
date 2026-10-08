import 'dart:async';

import 'package:rooster/client/components/message_effects/message_effect_component.dart';
import 'package:rooster/client/components/read_receipts/read_receipt_component.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_overlay.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';

class RoomTimelineWidgetView extends StatefulWidget {
  const RoomTimelineWidgetView(
      {required this.timeline,
      this.markAsRead,
      this.onViewScrolled,
      this.setEditingEvent,
      this.setReplyingEvent,
      this.onAttachedToBottom,
      this.isThreadTimeline = false,
      super.key});
  final Timeline timeline;
  final Function(TimelineEvent event)? markAsRead;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function()? onAttachedToBottom;
  final bool isThreadTimeline;

  final Function(
      {required double offset,
      required double maxScrollExtent,
      required double minScrollExtent})? onViewScrolled;

  @override
  State<RoomTimelineWidgetView> createState() => RoomTimelineWidgetViewState();
}

class RoomTimelineWidgetViewState extends State<RoomTimelineWidgetView>
    with WidgetsBindingObserver {
  int numBuilds = 0;

  int recentItemsCount = 0;
  int get historyItemsCount => timeline.events.length - recentItemsCount;

  bool firstFrame = true;
  bool animatingToBottom = false;

  late ScrollController controller;
  late List<(GlobalKey, String)> eventKeys;

  /// Where an event, or an entry's key, is in [eventKeys]: built once after
  /// the list changes, instead of a scan of it per lookup. The slivers ask
  /// for every built child on every rebuild, and a session that has
  /// scrolled back a few thousand events paid thousands of comparisons per
  /// child per incoming message.
  Map<String, int>? _indexByEventId;
  Map<Key, int>? _indexByKey;

  void _eventKeysChanged() {
    _indexByEventId = null;
    _indexByKey = null;
  }

  int indexOfEventId(String eventId) {
    final index = _indexByEventId ??= {
      for (var i = 0; i < eventKeys.length; i++) eventKeys[i].$2: i
    };
    return index[eventId] ?? -1;
  }

  int indexOfKey(Key key) {
    final index = _indexByKey ??= {
      for (var i = 0; i < eventKeys.length; i++) eventKeys[i].$1: i
    };
    return index[key] ?? -1;
  }

  late Timeline timeline;

  GlobalKey firstFrameScrollViewKey = GlobalKey();
  GlobalKey scrollViewKey = GlobalKey();
  GlobalKey centerKey = GlobalKey();
  GlobalKey recentItemsKey = GlobalKey();
  GlobalKey overlayKey = GlobalKey();
  GlobalKey stackKey = GlobalKey();

  LayerLink selectedEventLayerLink = LayerLink();
  SelectableEventViewWidget? selectedEventView;

  String? highlightedEventId;
  TimelineViewEntryState? highlightedEventState;
  GlobalKey? highlightedEventOffstageKey;
  int? highlightedEventOffstageIndex;
  List<StreamSubscription>? subscriptions;
  StreamSubscription<String>? _jumpSubscription;

  bool wasLastScrollAttachedToBottom = false;
  bool loading = false;

  /// Whether the view shows the latest messages: following them, or within
  /// a little of the bottom.
  bool get attachedToBottom =>
      controller.hasClients ? following || atBottom || animatingToBottom : true;

  /// Within a little of the bottom of the list, by the scroll position.
  bool get atBottom =>
      controller.offset - controller.positions.first.minScrollExtent < 50;

  /// Whether new messages are followed: true at the latest messages, and
  /// false once the reader scrolls away from them. Only the reader's own
  /// scrolling changes it, not ours, nor a message growing below the view:
  /// read from the scroll position as a message came in, a tall one (or
  /// one arriving while we still scrolled to the last) said we had left.
  bool following = true;

  /// How many scrolls of ours are under way, which [following] ignores.
  int ownScrolls = 0;

  bool isLoadingFuture = false;
  bool isLoadingHistory = false;

  MessageEffectComponent? effects;

  /// The first message not seen yet, with the "New messages" line above it.
  /// Set from the read marker when the room opens, and while it is open by
  /// the first message that arrives unseen: with the window in the
  /// background, or while reading further up.
  String? lastReadEventId;

  /// The line has been seen where it is: the view was at the latest
  /// messages with the window in front. The next message that arrives
  /// unseen moves it there.
  bool unreadMarkerSeen = false;

  /// Messages from others that arrived below while reading further up, for
  /// the button that jumps down to them.
  int newMessagesBelow = 0;

  /// Events reaching index 0 are new ones, not a page of the past loaded
  /// while scrolling down a timeline opened at an old message.
  bool get isLive => !timeline.canLoadFuture && !timeline.isLoadingFuture;

  /// Whether the window is in front, so what lands on screen is seen. A
  /// platform that never says counts as in front.
  static bool get appInForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    effects = widget.timeline.client.getComponent<MessageEffectComponent>();

    initFromTimeline(widget.timeline);

    controller = ScrollController(initialScrollOffset: -999999);
    _jumpSubscription = EventBus.jumpToEvent.stream.listen(jumpToEvent);
    WidgetsBinding.instance.addPostFrameCallback(onAfterFirstFrame);
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) acknowledgeIfLooking();
  }

  /// A timeline loaded around an event jumped to, which this view owns:
  /// closed when the view goes back to [widget.timeline], jumps elsewhere
  /// or is disposed. Each used to replace the room's timeline and leak the
  /// one before.
  Timeline? _contextTimeline;
  int _jumpGeneration = 0;

  void initFromTimeline(Timeline timeline) {
    if (subscriptions != null) {
      for (var sub in subscriptions!) {
        sub.cancel();
      }
    }

    final leaving = _contextTimeline;
    if (leaving != null && !identical(leaving, timeline)) {
      _contextTimeline = null;
      leaving.close();
    }

    String? targetEventId = timeline.room.lastRead;

    this.timeline = timeline;
    var index = timeline.events.indexWhere((i) => i.eventId == targetEventId);

    lastReadEventId = null;
    unreadMarkerSeen = false;
    newMessagesBelow = 0;

    if (index > 0) {
      // The line goes above the first message after the latest read event.
      // (It went above the newest one: this kept looking past the first.)
      for (int i = index - 1; i >= 0; i--) {
        var eventType =
            TimelineViewEntryState.eventToDisplayType(timeline.events[i]);

        if (eventType == TimelineEventWidgetDisplayType.message) {
          lastReadEventId = timeline.events[i].eventId;
          break;
        }
      }

      isLoadingFuture = false;
      isLoadingHistory = false;
    }

    // Opens at the latest message, everything in the history sliver: the
    // one anchored to the bottom of the view (see [settleAtBottom]).
    recentItemsCount = 0;

    var receipts = timeline.room.getComponent<ReadReceiptComponent>();
    subscriptions = [
      timeline.onEventAdded.stream.listen(onEventAdded),
      timeline.onChange.stream.listen(onEventChanged),
      timeline.onRemove.stream.listen(onEventRemoved),
      timeline.onLoadingStatusChanged.listen(onLoadingStatusChanged),
      if (receipts != null)
        receipts.onReadReceiptsUpdated.listen(onReadReceiptUpdated),
    ];

    if (preferences.messageEffectsEnabled.value) {
      for (int i = 0; i < 5; i++) {
        if (i >= timeline.events.length) break;

        var event = timeline.events[i];
        if (effects?.hasEffect(event) == true) {
          effects?.doEffect(event);
          break;
        }
      }
    }

    eventKeys = List.from(
        timeline.events
            .map((e) => (GlobalKey(debugLabel: e.eventId), e.eventId)),
        growable: true);
    _eventKeysChanged();
  }

  @override
  void dispose() {
    for (var element in subscriptions!) {
      element.cancel();
    }
    _jumpGeneration++;
    _contextTimeline?.close();
    _contextTimeline = null;
    _jumpSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void onEventAdded(int index, {bool cascade = true}) {
    eventKeys.insert(index, (
      GlobalKey(debugLabel: timeline.events[index].eventId),
      timeline.events[index].eventId
    ));
    _eventKeysChanged();

    final event = timeline.events[index];
    final live = index == 0 && isLive;
    final following = attachedToBottom;
    final mine = event.senderId == timeline.client.self?.identifier;
    final isMessage = TimelineViewEntryState.eventToDisplayType(event) ==
        TimelineEventWidgetDisplayType.message;

    if (live && mine && isMessage && !following) {
      // Sent while reading further up: back to the present to see it.
      animateAndSnapToBottom(keepUnreadMarker: false);
      return;
    }

    if (live && following) {
      // Listed at the start of the history sliver, which is anchored to the
      // bottom of the view: the newest message stays at the bottom however
      // it grows when its previews load.
      if (recentItemsCount > 0) settleAtBottom();
    } else if (index == 0 || index < recentItemsCount) {
      recentItemsCount += 1;
    }

    if (live && isMessage) {
      if (mine) {
        // Caught up: we are talking.
        lastReadEventId = null;
      } else if (!following || !appInForeground) {
        markUnseen(event);
      }

      if (!following && !mine) {
        newMessagesBelow += 1;
        (overlayKey.currentState as TimelineOverlayState?)
            ?.setNewMessageCount(newMessagesBelow);
      }
    }

    if (index == 0) {
      if (attachedToBottom) {
        // In front of the reader it scrolls into view; behind other
        // windows it is simply put there.
        appInForeground ? scrollToBottom() : stickToBottom();

        widget.markAsRead?.call(timeline.events[0]);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          appInForeground ? scrollToBottom() : stickToBottom();

          widget.markAsRead?.call(timeline.events[0]);
        });
      }

      if (preferences.messageEffectsEnabled.value) {
        effects?.doEffect(timeline.events[index]);
      }
    }

    if (cascade) {
      if (index > 0) {
        onEventChanged(index - 1, cascade: false);
      }

      if (index < timeline.events.length - 1) {
        onEventChanged(index + 1, cascade: false);
      }
    }

    setState(() {});
  }

  void onEventChanged(int index, {bool cascade = true}) {
    var event = timeline.events[index];
    var existing = eventKeys[index];
    if (existing.$2 != event.eventId) {
      eventKeys[index] = (existing.$1, event.eventId);
      _eventKeysChanged();
    }

    var key = eventKeys[index];

    assert(event.eventId == key.$2);

    var state = key.$1.currentState;

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }

    if (index == 0) {
      if (attachedToBottom) {
        scrollToBottom();

        widget.markAsRead?.call(timeline.events[0]);
      }
    }

    if (cascade) {
      if (index > 0) {
        onEventChanged(index - 1, cascade: false);
      }

      if (index < timeline.events.length - 1) {
        onEventChanged(index + 1, cascade: false);
      }
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      ownScroll(() => controller.animateTo(controller.position.minScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutExpo));
    });
  }

  /// Runs [move], a scroll of ours, without [following] reading it as the
  /// reader's.
  Future<void> ownScroll(FutureOr<void> Function() move) async {
    ownScrolls += 1;
    try {
      await move();
    } finally {
      ownScrolls -= 1;
    }
  }

  /// Puts the view at the very bottom, and keeps it there for the next few
  /// frames. A list laying out children it had not built corrects the
  /// scroll position to keep what was on screen in place, which left the
  /// newest message just below the view after a jump to the bottom.
  void stickToBottom({int frames = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients || !following) return;
      final bottom = controller.position.minScrollExtent;
      if (controller.offset != bottom) {
        ownScroll(() => controller.jumpTo(bottom));
      }
      (overlayKey.currentState as TimelineOverlayState?)
          ?.setAttachedToBottom(attachedToBottom);
      if (frames > 1) stickToBottom(frames: frames - 1);
    });
  }

  /// Moves what is below the history sliver into it, and the view to its
  /// start. The bottom of the list is then the bottom of the view, where it
  /// stays as new messages come in and as the newest ones grow (an image or
  /// a link preview loading). Below the sliver it did not: a message there
  /// grew past the bottom of the view after we had scrolled to it, the view
  /// no longer counted as at the bottom, and from then on nothing new
  /// scrolled into view.
  void settleAtBottom() {
    if (!controller.hasClients) return;
    if (recentItemsCount == 0 && controller.offset == 0) return;

    following = true;
    setState(() => recentItemsCount = 0);
    ownScroll(() => controller.jumpTo(0));
    stickToBottom();
  }

  /// [event] arrived unseen: the line goes above it, unless it already
  /// marks an earlier one nobody has seen yet.
  void markUnseen(TimelineEvent event) {
    final marker = lastReadEventId;
    if (marker != null && !unreadMarkerSeen && timeline.hasEvent(marker)) {
      return;
    }
    lastReadEventId = event.eventId;
    unreadMarkerSeen = false;
  }

  /// At the latest messages with the window in front: the line has been
  /// seen, and nothing waits below.
  void acknowledgeIfLooking() {
    if (!mounted || !attachedToBottom || !appInForeground) return;
    unreadMarkerSeen = true;
    newMessagesBelow = 0;
    (overlayKey.currentState as TimelineOverlayState?)?.setNewMessageCount(0);
  }

  void onEventRemoved(int index) {
    if (index < recentItemsCount) {
      recentItemsCount -= 1;
    }

    var removed = eventKeys.removeAt(index);
    _eventKeysChanged();

    assert(timeline.events[index].eventId == removed.$2);

    setState(() {});
  }

  void onAfterFirstFrame(_) {
    if (!mounted) return;
    if (controller.hasClients) {
      double extent = controller.position.minScrollExtent;

      if (controller.position.viewportDimension < -extent) {
        extent = -controller.position.viewportDimension / 2;
      }

      final previousController = controller;
      controller = ScrollController(initialScrollOffset: extent);
      scrollViewKey = GlobalKey();
      controller.addListener(onScroll);
      setState(() {
        firstFrame = false;
      });
      // The old Scrollable detaches on the next frame, after setState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onScroll();
    });
  }

  void onScroll() {
    if (!mounted || !controller.hasClients) return;
    if (ownScrolls == 0) following = atBottom || animatingToBottom;
    widget.onViewScrolled?.call(
        offset: controller.offset,
        maxScrollExtent: controller.position.maxScrollExtent,
        minScrollExtent: controller.position.minScrollExtent);

    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(attachedToBottom);

    if (wasLastScrollAttachedToBottom == false && attachedToBottom) {
      widget.onAttachedToBottom?.call();
    }

    wasLastScrollAttachedToBottom = attachedToBottom;
    acknowledgeIfLooking();

    double loadingThreshold = 500;

    // When the history items are empty, the sliver takes up exactly the height of the viewport, so we should use that height instead
    if (historyItemsCount == 0) {
      var renderBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        loadingThreshold = renderBox.size.height;
      }
    }

    if (controller.offset >
            controller.position.maxScrollExtent - loadingThreshold &&
        !timeline.isLoadingHistory &&
        timeline.canLoadHistory) {
      timeline.loadMoreHistory().then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onScroll());
      });
    }

    if (controller.offset <
            (controller.position.minScrollExtent + loadingThreshold) &&
        !timeline.isLoadingFuture &&
        timeline.canLoadFuture) {
      timeline.loadMoreFuture();
    }
  }

  void animateAndSnapToBottom({bool keepUnreadMarker = true}) {
    controller.position.hold(() {});

    final marker = lastReadEventId;
    setState(() {
      initFromTimeline(widget.timeline);
      // The line marking what came in while reading further up stays
      // where it is, to read on from it.
      if (keepUnreadMarker && marker != null && timeline.hasEvent(marker)) {
        lastReadEventId = marker;
      }
    });

    following = true;
    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.setAttachedToBottom(attachedToBottom);
    widget.onAttachedToBottom?.call();

    animatingToBottom = true;

    ownScroll(() => controller.animateTo(controller.position.minScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutExpo)).then((_) {
      if (!mounted || !controller.hasClients) return;
      setState(() {
        ownScroll(() => controller.jumpTo(0));
        animatingToBottom = false;
      });
      stickToBottom();
    });

    setState(() {
      recentItemsCount = 0;
    });
  }

  void eventHovered(String eventId) {
    final index = indexOfEventId(eventId);
    if (index == -1) return;
    var key = eventKeys[index];

    assert(eventId == key.$2);

    var state = key.$1.currentState;

    if (state is SelectableEventViewWidget) {
      var selectable = state as SelectableEventViewWidget;

      if (selectable != selectedEventView) {
        deselectEvent();

        selectable.select(selectedEventLayerLink);
        selectedEventView = selectable;

        var overlayState = overlayKey.currentState as TimelineOverlayState?;
        var event = timeline.tryGetEvent(eventId)!;
        overlayState?.setMenu(TimelineEventMenu(
          timeline: timeline,
          context: context,
          isThreadTimeline: widget.isThreadTimeline,
          event: event,
          setEditingEvent: (event) => widget.setEditingEvent?.call(event),
          setReplyingEvent: (event) => widget.setReplyingEvent?.call(event),
        ));
      }
    } else {
      Log.w("Failed to get selectable state");
    }
  }

  void deselectEvent() {
    var overlayState = overlayKey.currentState as TimelineOverlayState?;
    overlayState?.clearSelection();

    selectedEventView?.deselect();
    selectedEventView = null;
  }

  @override
  Widget build(BuildContext context) {
    final view = Material(
      color: Colors.transparent,
      child: MouseRegion(
        onExit: (_) => deselectEvent(),
        child: ClipRect(
          child: Stack(
            key: stackKey,
            children: [
              Offstage(
                offstage: firstFrame,
                child: CustomScrollView(
                  key: firstFrame ? firstFrameScrollViewKey : scrollViewKey,
                  controller: controller,
                  reverse: true,
                  center: centerKey,
                  slivers: <Widget>[
                    if (isLoadingFuture)
                      SliverList(
                          delegate: SliverChildBuilderDelegate(childCount: 1,
                              (BuildContext context, int index) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      })),
                    // The slivers are split into recent and history events and
                    // are rendered separately. This prevents the timeline from
                    // jumping around and allows jumping to specific indices
                    // with more reliability.
                    SliverList(
                      key: recentItemsKey,
                      // Recent Items
                      delegate: SliverChildBuilderDelegate(
                        childCount: recentItemsCount,
                        addAutomaticKeepAlives: false,
                        (BuildContext context, int sliverIndex) {
                          int timelineIndex =
                              recentItemsCount - sliverIndex - 1;
                          numBuilds += 1;

                          var key;

                          key = eventKeys[timelineIndex];

                          assert(
                              key.$2 == timeline.events[timelineIndex].eventId);

                          return Container(
                            alignment: Alignment.center,
                            color: preferences.developerMode.value &&
                                    BuildConfig.DEBUG
                                ? Colors.blue[200 + sliverIndex % 4 * 100]!
                                    .withAlpha(30)
                                : null,
                            child: TimelineViewEntry(
                                key: key.$1,
                                timeline: timeline,
                                onEventHovered: eventHovered,
                                canCollapse: true,
                                setEditingEvent: widget.setEditingEvent,
                                setReplyingEvent: widget.setReplyingEvent,
                                isThreadTimeline: widget.isThreadTimeline,
                                highlightedEventId: highlightedEventId,
                                lastReadEventId: lastReadEventId,
                                previewMedia:
                                    widget.timeline.room.shouldPreviewMedia,
                                jumpToEvent: jumpToEvent,
                                initialIndex: timelineIndex),
                          );
                        },
                        findChildIndexCallback: (key) {
                          var timelineIndex = indexOfKey(key);
                          if (timelineIndex == -1) {
                            Log.w(
                                "Failed to get timeline index for key: $timelineIndex");
                            return null;
                          }

                          return recentItemsCount - timelineIndex - 1;
                        },
                      ),
                    ),
                    SliverList(
                      key: centerKey,
                      // History Items
                      delegate: SliverChildBuilderDelegate(
                        addAutomaticKeepAlives: false,
                        childCount: historyItemsCount,
                        (BuildContext context, int sliverIndex) {
                          numBuilds += 1;
                          // ignore: avoid_print
                          var timelineIndex = recentItemsCount + sliverIndex;

                          var key;

                          key = eventKeys[timelineIndex];

                          assert(
                              key.$2 == timeline.events[timelineIndex].eventId);

                          return Container(
                            alignment: Alignment.center,
                            color: preferences.developerMode.value &&
                                    BuildConfig.DEBUG
                                ? Colors.red[200 + sliverIndex % 4 * 100]!
                                    .withAlpha(30)
                                : null,
                            child: TimelineViewEntry(
                                key: key.$1,
                                onEventHovered: eventHovered,
                                timeline: timeline,
                                canCollapse: true,
                                setEditingEvent: widget.setEditingEvent,
                                setReplyingEvent: widget.setReplyingEvent,
                                isThreadTimeline: widget.isThreadTimeline,
                                highlightedEventId: highlightedEventId,
                                previewMedia:
                                    widget.timeline.room.shouldPreviewMedia,
                                lastReadEventId: lastReadEventId,
                                jumpToEvent: jumpToEvent,
                                initialIndex: timelineIndex),
                          );
                        },
                        findChildIndexCallback: (key) {
                          var timelineIndex = indexOfKey(key);
                          if (timelineIndex == -1) {
                            Log.w(
                                "Failed to get timeline index for key: $timelineIndex");
                            return null;
                          }

                          return timelineIndex - recentItemsCount;
                        },
                      ),
                    ),
                    if (isLoadingHistory)
                      SliverList(
                          delegate: SliverChildBuilderDelegate(childCount: 1,
                              (BuildContext context, int index) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      })),
                  ],
                ),
              ),
              TimelineOverlay(
                  key: overlayKey,
                  showMessageMenu: MediaQuery.sizeOf(context).desktop,
                  jumpToLatest: animateAndSnapToBottom,
                  onScrolled: (event) {
                    controller.jumpTo(controller.offset - event.scrollDelta.dy);
                  },
                  link: selectedEventLayerLink),
              if (highlightedEventOffstageIndex != null &&
                  highlightedEventOffstageKey != null)
                Offstage(
                  offstage: true,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.red,
                        child: TimelineViewEntry(
                          key: highlightedEventOffstageKey,
                          timeline: timeline,
                          canCollapse: true,
                          isThreadTimeline: widget.isThreadTimeline,
                          initialIndex: highlightedEventOffstageIndex!,
                        ),
                      ),
                    ],
                  ),
                ),
              if (loading)
                Container(
                    color: Colors.black.withAlpha(50),
                    child: const Center(child: CircularProgressIndicator()))
            ],
          ),
        ),
      ),
    );

    return NotificationListener<ScrollEndNotification>(
      onNotification: onScrollEnd,
      child: view,
    );
  }

  /// Scrolled down to the latest messages and stopped there: from now on
  /// new ones show as they come in.
  bool onScrollEnd(ScrollEndNotification notification) {
    // The timeline's own, not a code block's or an embed's inside it.
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (!firstFrame && !animatingToBottom && recentItemsCount > 0 && atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => settleAtBottom());
    }
    return false;
  }

  void jumpToEvent(String eventId, {bool highlight = true}) async {
    if (!mounted) return;
    if (highlight && highlightedEventState?.mounted == true) {
      highlightedEventState!.setHighlighted(false);
      highlightedEventState = null;
    }

    int index = timeline.events.indexWhere((event) => event.eventId == eventId);
    if (index == -1) {
      final generation = ++_jumpGeneration;
      setState(() {
        loading = true;
      });
      Timeline newTimeline;
      try {
        newTimeline = await timeline.room.loadTimeline(contextEventId: eventId);
      } catch (e, s) {
        Log.onError(e, s,
            content: "Could not load the timeline around an event");
        if (mounted) setState(() => loading = false);
        return;
      }
      // A later jump, or the view going away, while this one loaded.
      if (!mounted || generation != _jumpGeneration) {
        await newTimeline.close();
        return;
      }

      index =
          newTimeline.events.indexWhere((event) => event.eventId == eventId);

      if (index == -1) {
        await newTimeline.close();
        if (mounted) setState(() => loading = false);
        return;
      }

      setState(() {
        // initFromTimeline first: it closes the context timeline being
        // left, which is the one still in _contextTimeline.
        initFromTimeline(newTimeline);
        _contextTimeline = newTimeline;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients || index >= eventKeys.length) {
        return;
      }
      var key = eventKeys[index].$1;
      final state = key.currentState;

      if (highlight && state is TimelineViewEntryState) {
        state.setHighlighted(true);
        highlightedEventState = state;
      }

      var boundsSize = stackKey.globalPaintBounds?.height;
      var offset = 0.0;
      if (boundsSize != null) {
        offset = -(boundsSize / 2);
      }

      final eventHeight =
          highlightedEventOffstageKey?.globalPaintBounds?.height;
      if (eventHeight != null) {
        offset += eventHeight / 2;
      }

      controller.animateTo(offset,
          duration: const Duration(milliseconds: 300),
          curve: Easing.emphasizedDecelerate);

      if (mounted) {
        setState(() {
          highlightedEventOffstageIndex = null;
          highlightedEventOffstageKey = null;
        });
      }
    });

    setState(() {
      recentItemsCount = index;
      if (highlight) {
        highlightedEventId = timeline.events[index].eventId;
        highlightedEventOffstageIndex = index;
        highlightedEventOffstageKey = GlobalKey();
      }
      loading = false;
    });
  }

  void onLoadingStatusChanged(void event) {
    setState(() {
      isLoadingFuture = timeline.isLoadingFuture;
      isLoadingHistory = timeline.isLoadingHistory;
    });
  }

  void onReadReceiptUpdated(String event) {
    final keyIndex = indexOfEventId(event);
    if (keyIndex == -1) return;
    var key = eventKeys[keyIndex];

    assert(event == key.$2);

    var state = key.$1.currentState;

    var index = timeline.events.indexWhere((i) => i.eventId == event);

    if (index == -1) {
      Log.w("Could not find the event in the timeline view");
    }

    if (state is TimelineEventViewWidget) {
      (state as TimelineEventViewWidget).update(index);
    } else {
      Log.w("Failed to get state");
    }
  }
}

extension GlobalKeyExtension on GlobalKey {
  Rect? get globalPaintBounds {
    final renderObject = currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      return renderObject!.paintBounds.shift(offset);
    } else {
      return null;
    }
  }
}
