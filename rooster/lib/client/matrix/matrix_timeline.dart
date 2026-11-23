import 'dart:async';
import 'package:collection/collection.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_threaded_receipts.dart';
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/client/timeline_events/timeline_event_sticker.dart';
import 'package:rooster/debug/log.dart';

import '../client.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimeline extends Timeline {
  matrix.Timeline? _matrixTimeline;
  late matrix.Room _matrixRoom;

  late MatrixRoom _room;

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  matrix.Timeline? get matrixTimeline => _matrixTimeline;

  MatrixTimeline(
    MatrixClient client,
    MatrixRoom room,
    matrix.Room matrixRoom, {
    matrix.Timeline? initialTimeline,
  }) {
    events = List.empty(growable: true);
    _matrixRoom = matrixRoom;
    this.client = client;
    this.room = room;
    _room = room;
    _matrixTimeline = initialTimeline;

    if (_matrixTimeline != null) {
      convertAllTimelineEvents();
    }
  }

  Future<void> initTimeline({String? contextEventId}) async {
    if (contextEventId == "") {
      contextEventId = null;
    }

    _matrixTimeline = await _matrixRoom.getTimeline(
        onInsert: onEventInserted,
        onChange: onEventChanged,
        onRemove: onEventRemoved,
        eventContextId: contextEventId);

    if (_matrixTimeline?.events.isEmpty == true) {
      await _matrixTimeline?.requestHistory();
    }

    _matrixRoom.postLoad();

    // This could maybe make load times realllly slow if we have a ton of stuff in the cache?
    // Might be better to only convert as many as we would need to display immediately and then convert the rest on demand
    convertAllTimelineEvents();
  }

  void convertAllTimelineEvents() {
    for (int i = 0; i < _matrixTimeline!.events.length; i++) {
      var converted = _room.convertEvent(_matrixTimeline!.events[i]);
      insertEvent(i, converted);
    }

    // The room's first page of messages warms its previews as it is
    // loaded, cards ready before the first scroll.
    warmUpPreviews(events);
  }

  void onEventInserted(index) {
    if (_matrixTimeline == null) return;
    insertEvent(index, _room.convertEvent(_matrixTimeline!.events[index]));
    // The message's preview starts with the page it arrived in — history,
    // a live arrival, or our own local echo — not when it later scrolls
    // into view. A message asking again joins the same fetch.
    warmUpPreviews([events[index]]);
  }

  void onEventChanged(index) {
    if (_matrixTimeline == null) return;

    if (index < _matrixTimeline!.events.length) {
      events[index] = (room as MatrixRoom).convertEvent(
          _matrixTimeline!.events[index],
          timeline: _matrixTimeline);

      notifyChanged(index);
    }
  }

  /// Asks the room's preview component to warm [events]' previews, when
  /// the room has one. See docs/link-previews.md.
  void warmUpPreviews(Iterable<TimelineEvent> events) {
    client.getComponent<UrlPreviewComponent>()?.warmUpPreviews(this, events);
  }

  void onEventRemoved(index) {
    onRemove.add(index);
    events.removeAt(index);
  }

  @override
  Future<void> loadMoreHistory() async {
    if (_matrixTimeline?.canRequestHistory == true) {
      var f = _matrixTimeline!.requestHistory();
      _loadingStatusChangedController.add(null);

      await f;
    }
    _loadingStatusChangedController.add(null);
  }

  @override
  bool get canLoadFuture => _matrixTimeline?.canRequestFuture ?? false;

  @override
  bool get canLoadHistory => _matrixTimeline?.canRequestHistory ?? false;

  @override
  bool get isLoadingFuture => _matrixTimeline?.isRequestingFuture ?? false;

  @override
  bool get isLoadingHistory => _matrixTimeline?.isRequestingHistory ?? false;

  @override
  Future<void> loadMoreFuture() async {
    if (canLoadFuture) {
      int waitSec = 4;
      _loadingStatusChangedController.add(null);
      while (true) {
        var f = _matrixTimeline?.requestFuture();

        try {
          await f;
          _loadingStatusChangedController.add(null);
          break;
        } on matrix.MatrixException catch (e) {
          if (e.error == matrix.MatrixError.M_LIMIT_EXCEEDED) {
            Log.i("Rate limited, waiting $waitSec second(s)...");
            await Future.delayed(Duration(seconds: waitSec));
            waitSec *= 2;
            continue;
          } else {
            Log.e(e);
            break;
          }
        } catch (e) {
          Log.e(e);
          break;
        }
      }
    }
  }

  /// The event the read marker was last sent for, so the three places that
  /// ask on every incoming message (the view when attached, again after the
  /// frame, and every change to the newest event) make one request between
  /// them, and none when the server already has it.
  String? _readMarkerSentFor;

  @override
  void markAsRead(TimelineEvent event) async {
    var receipts = room.getComponent<MatrixReadReceiptComponent>();
    if (event.status != TimelineEventStatus.synced &&
        event.status != TimelineEventStatus.sent) {
      return;
    }

    if (event.eventId == _readMarkerSentFor) {
      return;
    }

    if (event.eventId == _matrixRoom.fullyRead) {
      // The server already has this read; only the local badge can lag
      // behind, for example from counts loaded before a restart.
      _room.clearUnreadCountsLocally();
      return;
    }

    var timeline = _matrixTimeline;
    if (timeline == null) return;

    var markerEventId = timeline.events
        .firstWhereOrNull((e) => e.status == matrix.EventStatus.synced)
        ?.eventId;
    if (markerEventId == null) return;

    _readMarkerSentFor = event.eventId;
    try {
      await _sendReadMarker(timeline, markerEventId,
          public: receipts?.usePublicReadReceiptsForRoom);
    } catch (e, s) {
      // Asked again next time: the server does not have it, so the badge
      // must stay.
      if (_readMarkerSentFor == event.eventId) _readMarkerSentFor = null;
      Log.onError(e, s, content: "Could not set the read marker");
      return;
    }

    receipts?.handleEvent(event.eventId, room.client.self!.identifier);

    // A message that arrived while the marker was in flight is newer than
    // what we read; its sync owns the counts. Otherwise clear the badge now
    // instead of waiting for the homeserver to echo the read counts.
    if (timeline.events
            .firstWhereOrNull((e) => e.status == matrix.EventStatus.synced)
            ?.eventId ==
        markerEventId) {
      _room.clearUnreadCountsLocally();
    }
  }

  /// Moves our read marker to [markerEventId], the newest event, and sends
  /// our receipt for the room's own timeline. A server with threaded
  /// receipts (Matrix v1.4) gets it with `thread_id: "main"`, on the newest
  /// event outside any thread, so the threads keep their unread messages
  /// until they are read; an older one gets the unthreaded receipt.
  Future<void> _sendReadMarker(matrix.Timeline timeline, String markerEventId,
      {bool? public}) async {
    if (!await MatrixThreadedReceipts.supported(_matrixRoom.client)) {
      await timeline.setReadMarker(eventId: markerEventId, public: public);
      return;
    }

    matrix.Event? lookup(String id) =>
        timeline.events.firstWhereOrNull((e) => e.eventId == id);
    final mainEvent = timeline.events.firstWhereOrNull((e) =>
        e.status == matrix.EventStatus.synced &&
        MatrixThreadedReceipts.threadOf(e, lookup) ==
            MatrixThreadedReceipts.mainThreadId);

    // The fully read marker has no thread: it goes on the newest event.
    await _matrixRoom.setReadMarker(markerEventId);
    if (mainEvent == null) return;
    await MatrixThreadedReceipts.send(_matrixRoom, mainEvent.eventId,
        threadId: MatrixThreadedReceipts.mainThreadId, public: public);
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) =>
      // The room's own fetch: it also asks for the key of an encrypted
      // event this device cannot read yet.
      _room.getEvent(eventId);

  Future<void> removeReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    var timeline = _matrixTimeline;
    if (timeline == null) return;

    // Read the aggregation the reaction chips are drawn from: fetching the
    // event again can miss it, and leaves the chip stuck on
    var reactions = timeline.aggregatedEvents[reactingTo.eventId]
            ?[matrix.RelationshipTypes.reaction] ??
        const <matrix.Event>{};

    var ownReactions = reactions.where((e) {
      if (e.senderId != _matrixRoom.client.userID) return false;
      var content = e.content["m.relates_to"];
      return content is Map && content["key"] == reaction.key;
    }).toList();

    // Remove every match: a double click can react twice with the same key
    for (var e in ownReactions) {
      if (e.status.isError) {
        await e.cancelSend();
      } else if (e.status.isSending) {
        var eventId = await _room.reactionSentEventId(e.eventId);
        if (eventId != null) await _matrixRoom.redactEvent(eventId);
      } else {
        await _matrixRoom.redactEvent(e.eventId);
      }
    }
  }

  @override
  Future<void> deleteEvent(TimelineEvent event) async {
    var matrixEvent = await _matrixTimeline!.getEventById(event.eventId);
    if (event.status == TimelineEventStatus.error) {
      await matrixEvent?.cancelSend();
    } else {
      await _matrixRoom.redactEvent(event.eventId);
    }
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    if (event.senderId != room.client.self!.identifier &&
        room.permissions.canDeleteOtherUserMessages != true) return false;

    if (event is TimelineEventMessage) {
      return true;
    }

    if (event is TimelineEventSticker) {
      return true;
    }

    return true;
  }

  @override
  Future<void> close() async {
    _matrixTimeline?.cancelSubscriptions();
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
  }

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    return e.event.getDisplayEvent(_matrixTimeline!).redacted;
  }

  @override
  String getDisplayId(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    var ev = e.event.getDisplayEvent(matrixTimeline!);

    return "${event.eventId}-${ev.eventId}";
  }
}

/// Why "Jump to date" found no event.
enum JumpToDateFailure {
  /// Nothing in the room on that side of the date.
  notFound,

  /// The homeserver predates `timestamp_to_event` (Matrix v1.6, MSC3030).
  unsupported,
}

class JumpToDateException implements Exception {
  const JumpToDateException(this.failure);
  final JumpToDateFailure failure;

  @override
  String toString() => 'JumpToDateException($failure)';
}

/// "Jump to date": the room's event closest to a moment, from
/// `GET /_matrix/client/v1/rooms/{roomId}/timestamp_to_event` (Matrix v1.6).
class MatrixJumpToDate {
  /// The id of [room]'s event closest to [time]: the first at or after it
  /// with [matrix.Direction.f], the last at or before it with
  /// [matrix.Direction.b]. Throws [JumpToDateException] when the room has
  /// none there or the server cannot tell.
  static Future<String> eventIdAt(matrix.Room room, DateTime time,
      {matrix.Direction direction = matrix.Direction.f}) async {
    final client = room.client;
    final versions = await client.getVersions();
    if (!versions.versions.any((v) => isMatrixVersionAtLeast(v, 1, 6))) {
      throw const JumpToDateException(JumpToDateFailure.unsupported);
    }
    try {
      final found = await client.getEventByTimestamp(
          room.id, time.millisecondsSinceEpoch, direction);
      return found.eventId;
    } on matrix.MatrixException catch (e) {
      if (e.error == matrix.MatrixError.M_NOT_FOUND) {
        throw const JumpToDateException(JumpToDateFailure.notFound);
      }
      // Advertises v1.6 but has no such endpoint.
      if (e.error == matrix.MatrixError.M_UNRECOGNIZED) {
        throw const JumpToDateException(JumpToDateFailure.unsupported);
      }
      rethrow;
    }
  }

  /// The first event of [day] (local time); the last one before it when
  /// the room has nothing from that day on.
  static Future<String> eventIdForDay(matrix.Room room, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    try {
      return await eventIdAt(room, start, direction: matrix.Direction.f);
    } on JumpToDateException catch (e) {
      if (e.failure != JumpToDateFailure.notFound) rethrow;
      return await eventIdAt(room, start, direction: matrix.Direction.b);
    }
  }
}
