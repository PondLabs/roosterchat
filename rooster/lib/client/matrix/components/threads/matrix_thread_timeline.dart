import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_threaded_receipts.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_unread.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixThreadTimeline implements Timeline {
  @override
  Client client;

  @override
  late List<TimelineEvent> events;

  @override
  Room room;

  MatrixTimeline mainRoomTimeline;

  ThreadsComponent component;

  String threadRootId;

  @override
  StreamController<int> onChange = StreamController.broadcast();

  @override
  StreamController<int> onEventAdded = StreamController.broadcast();

  @override
  StreamController<int> onRemove = StreamController.broadcast();

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  late List<StreamSubscription> subs;

  String? nextBatch;
  bool finished = false;

  Future? nextChunkRequest;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => nextBatch != null && nextChunkRequest != null;

  @override
  bool get isLoadingFuture => false;

  @override
  bool isLoadingHistory = false;

  MatrixThreadTimeline({
    required this.client,
    required this.room,
    required this.threadRootId,
    required this.mainRoomTimeline,
    required this.component,
    this.nextBatch,
  }) {
    subs = [
      mainRoomTimeline.onEventAdded.stream.listen(onMainTimelineEventAdded),
      mainRoomTimeline.onChange.stream.listen(onMainTimelineEventChanged),
      mainRoomTimeline.onRemove.stream.listen(onMainTimelineEventRemoved),
    ];

    events = List.empty(growable: true);
  }

  Future<List<TimelineEvent>> getThreadEvents(
      {int limit = 20, String? nextBatch}) async {
    var client = this.client as MatrixClient;
    var room = this.room as MatrixRoom;

    var mx = client.getMatrixClient();
    final response = await mx.getRelatingEventsWithRelType(
      room.identifier,
      threadRootId,
      matrix.RelationshipTypes.thread,
      limit: limit,
      from: nextBatch,
    );

    var mxevents = response.chunk
        .map((e) => matrix.Event.fromMatrixEvent(e, room.matrixRoom))
        .toList();

    for (var i = 0; i < mxevents.length; i++) {
      var event = mxevents[i];

      if (event.type == "m.room.encrypted") {
        var decrypted = await mx.encryption?.decryptRoomEvent(event);
        if (decrypted != null) {
          mxevents[i] = decrypted;
        }
      }
    }

    for (var event in mxevents) {
      mainRoomTimeline.matrixTimeline?.addAggregatedEvent(event);
    }

    var convertedEvents = mxevents
        .map((e) =>
            room.convertEvent(e, timeline: mainRoomTimeline.matrixTimeline))
        .toList();

    this.nextBatch = response.nextBatch;

    if (this.nextBatch == null) {
      finished = true;
      TimelineEvent? root = mainRoomTimeline.tryGetEvent(threadRootId);
      if (root == null) {
        try {
          root = await mainRoomTimeline.fetchEventById(threadRootId);
        } catch (_) {}
      }
      if (root != null &&
          !convertedEvents.any((e) => e.eventId == root!.eventId)) {
        convertedEvents.add(root);
      }
    }

    return convertedEvents;
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    return mainRoomTimeline.canDeleteEvent(event);
  }

  @override
  Future<void> close() async {
    for (var sub in subs) {
      sub.cancel();
    }
    // Closed: the chat's slots show its files again.
    for (final send in _shownSends) {
      send.notShownInThreadList(this);
    }
    _shownSends.clear();
  }

  @override
  void deleteEvent(TimelineEvent event) {
    mainRoomTimeline.deleteEvent(event);
  }

  @override
  Future<TimelineEvent?> fetchEventById(String eventId) {
    return mainRoomTimeline.fetchEventById(eventId);
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) {
    return mainRoomTimeline.fetchEventByIdInternal(eventId);
  }

  @override
  bool hasEvent(String eventId) {
    return events.any((element) => element.eventId == eventId);
  }

  @override
  void insertEvent(int index, TimelineEvent event) {}

  @override
  Future<void> loadMoreHistory() async {
    if (finished) {
      return;
    }

    if (nextChunkRequest != null) {
      return;
    }

    isLoadingHistory = true;

    nextChunkRequest = getThreadEvents(nextBatch: nextBatch);
    var nextEvents = await nextChunkRequest;

    nextChunkRequest = null;

    for (var event in nextEvents) {
      events.add(event);
      onEventAdded.add(events.length - 1);
    }

    // A thread's older messages warm their previews as their page arrives,
    // the way the room's timeline does.
    client
        .getComponent<UrlPreviewComponent>()
        ?.warmUpPreviews(this, nextEvents);

    isLoadingHistory = false;
  }

  @override
  Future<void> loadMoreFuture() {
    throw UnimplementedError();
  }

  /// The reply our last thread receipt was sent for, so the view asking on
  /// every incoming message makes one request per reply.
  String? _receiptSentFor;

  /// Sends our receipt for this thread (Matrix v1.4, MSC3771): on its
  /// newest reply the server has, with `thread_id` set to the root, public
  /// or private as the room prefers. A thread with no reply yet, or a
  /// server without threaded receipts, gets none. Then the thread's unread
  /// badge clears.
  @override
  Future<void> markAsRead(TimelineEvent event) async {
    final reply = events.firstWhereOrNull((e) =>
        e.eventId != threadRootId &&
        e is MatrixTimelineEvent &&
        e.event.status.isSynced &&
        e.event.relationshipType == matrix.RelationshipTypes.thread &&
        e.event.relationshipEventId == threadRootId);
    if (reply == null || reply.eventId == _receiptSentFor) return;

    final mxRoom = (room as MatrixRoom).matrixRoom;
    if (!await MatrixThreadedReceipts.supported(mxRoom.client)) return;

    _receiptSentFor = reply.eventId;
    try {
      await MatrixThreadedReceipts.send(mxRoom, reply.eventId,
          threadId: threadRootId,
          public: room
              .getComponent<MatrixReadReceiptComponent>()
              ?.usePublicReadReceiptsForRoom);
    } catch (e, s) {
      // Asked again next time: the server does not have it.
      if (_receiptSentFor == reply.eventId) _receiptSentFor = null;
      Log.onError(e, s, content: "Could not send the thread's read receipt");
      return;
    }

    // A reply that arrived meanwhile is still unread; its sync owns the
    // counts.
    if (events.firstOrNull?.eventId == reply.eventId) {
      MatrixThreadUnread.clearLocally(mxRoom, threadRootId);
      (room as MatrixRoom).threadCountsClearedLocally();
    }
  }

  @override
  void notifyChanged(int index) {}

  @override
  TimelineEvent? tryGetEvent(String eventId) {
    return mainRoomTimeline.tryGetEvent(eventId);
  }

  bool isEventInThisThread(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    if (event.eventId == threadRootId) {
      return true;
    }

    var mxEvent = event.event;
    var relation = mxEvent.content["m.relates_to"];
    if (relation == null) {
      return false;
    }

    if (relation is! Map<String, dynamic>) {
      return false;
    }

    if (relation["rel_type"] != matrix.RelationshipTypes.thread) {
      return false;
    }

    if (relation["event_id"] == threadRootId) {
      return true;
    }

    var reply = relation["m.in_reply_to"] as Map<String, dynamic>?;

    if (reply == null) {
      return false;
    }

    var replyingEventID = reply["event_id"];

    if (replyingEventID == threadRootId) {
      return true;
    }

    var replyingEvent = mainRoomTimeline.tryGetEvent(replyingEventID);
    if (replyingEvent != null) {
      return isEventInThisThread(replyingEvent as MatrixTimelineEvent);
    }

    return false;
  }

  void onMainTimelineEventAdded(int index) {
    var event = mainRoomTimeline.events[index];

    if (!isEventInThisThread(event)) {
      return;
    }

    _insert(index, event);
  }

  /// Puts [event], at [mainIndex] in the room's timeline, where it goes in
  /// this thread's.
  void _insert(int mainIndex, TimelineEvent event) {
    var newIndex = 0;
    if (mainIndex != 0) {
      // Theres gotta be a smarter way of doing this but whatever
      var copy = List<TimelineEvent>.from(mainRoomTimeline.events);
      copy.removeWhere((element) => !isEventInThisThread(element));
      newIndex = copy.indexOf(event);
    }
    events.insert(newIndex, event);
    _showsSend(event);
    onEventAdded.add(newIndex);
  }

  /// Where [event] is in this thread's list: by its id, or by its
  /// transaction id while it is listed as the pending event it was.
  int _indexOf(TimelineEvent event) {
    final index = events.indexWhere((e) => e.eventId == event.eventId);
    if (index != -1) return index;
    final txid = _transactionOf(event);
    return events.indexWhere((e) => e.eventId == txid);
  }

  void onMainTimelineEventChanged(int index) {
    var event = mainRoomTimeline.events[index];
    if (!isEventInThisThread(event)) return;
    final at = _indexOf(event);
    if (at == -1) {
      // It joined the thread now: a file's pending event gets its relation
      // once uploaded. It goes where it belongs; it never takes the place
      // of another event (or of none, in an empty list).
      _insert(index, event);
      return;
    }
    events[at] = event;
    _showsSend(event);
    onChange.add(at);
  }

  void onMainTimelineEventRemoved(int index) {
    var event = mainRoomTimeline.events[index];
    if (isEventInThisThread(event)) {
      var index = _indexOf(event);
      if (index == -1) return;

      events.removeAt(index);
      _stopsShowingSend(event);
      onRemove.add(index);
    }
  }

  /// The files sent from this thread's chat whose pending event this list
  /// shows: the chat's own slot for each gives way to it, so a file is
  /// never shown twice.
  final Set<AttachmentSend> _shownSends = {};

  AttachmentSend? _sendOf(TimelineEvent event) {
    final send = AttachmentSends.instance
        .byTransaction(room.localId, _transactionOf(event));
    return send?.threadId == threadRootId ? send : null;
  }

  void _showsSend(TimelineEvent event) {
    final send = _sendOf(event);
    if (send != null && _shownSends.add(send)) send.shownInThreadList(this);
  }

  void _stopsShowingSend(TimelineEvent event) {
    final send = _sendOf(event);
    if (send != null && _shownSends.remove(send)) {
      send.notShownInThreadList(this);
    }
  }

  static String _transactionOf(TimelineEvent event) =>
      (event is MatrixTimelineEvent ? event.event.transactionId : null) ??
      event.eventId;

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    return e.event.getDisplayEvent(mainRoomTimeline.matrixTimeline!).redacted ||
        MatrixIgnoredUsers.of(e.event.room.client).hides(e.event);
  }

  @override
  String getDisplayId(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    var ev = e.event.getDisplayEvent(mainRoomTimeline.matrixTimeline!);

    return "thread-${threadRootId}-${event.eventId}-${ev.eventId}";
  }
}
