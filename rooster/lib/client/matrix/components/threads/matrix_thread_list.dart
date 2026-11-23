import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/debug/log.dart';

/// Which threads the list shows: `include` of the thread roots API.
enum ThreadListFilter {
  all,

  /// Threads we started or replied in.
  participated;

  matrix.Include get include => switch (this) {
        ThreadListFilter.all => matrix.Include.all,
        ThreadListFilter.participated => matrix.Include.participated,
      };
}

/// One thread in the list: its root, and the summary the server bundles
/// with it (`unsigned.m.relations.m.thread`).
class ThreadListEntry {
  ThreadListEntry({
    required this.root,
    required this.replyCount,
    required this.latestReply,
    required this.participated,
  });

  final TimelineEvent root;
  final int replyCount;
  final TimelineEvent? latestReply;
  final bool participated;

  String get threadRootId => root.eventId;
}

/// A room's threads, newest activity first, a page at a time, from
/// `GET /_matrix/client/v1/rooms/{roomId}/threads` (Matrix v1.4).
class MatrixThreadList {
  MatrixThreadList(this.room,
      {this.filter = ThreadListFilter.all, this.pageSize = 20});

  final MatrixRoom room;
  final ThreadListFilter filter;
  final int pageSize;

  final List<ThreadListEntry> entries = [];

  String? _nextBatch;
  bool _loadedFirstPage = false;
  bool _closed = false;
  Future<void>? _loading;

  /// The last page failed; [loadMore] asks again.
  Object? error;

  final StreamController<void> _changed = StreamController.broadcast();
  Stream<void> get onChanged => _changed.stream;

  bool get isLoading => _loading != null;

  /// Whether the server has more threads after the ones in [entries].
  bool get hasMore => !_loadedFirstPage || _nextBatch != null;

  /// Loaded, and the room has no thread (for [filter]).
  bool get isEmpty => _loadedFirstPage && entries.isEmpty && error == null;

  /// Loads the next page; joins the one already loading.
  Future<void> loadMore() {
    if (_closed || !hasMore) return Future.value();
    final loading = _loading;
    if (loading != null) return loading;
    error = null;
    final page = _loading = _loadPage().whenComplete(() {
      _loading = null;
      _notify();
    });
    _notify();
    return page;
  }

  Future<void> _loadPage() async {
    final mxRoom = room.matrixRoom;
    final mx = mxRoom.client;
    try {
      final response = await mx.getThreadRoots(
        mxRoom.id,
        include: filter.include,
        limit: pageSize,
        from: _nextBatch,
      );
      if (_closed) return;

      final known = entries.map((e) => e.threadRootId).toSet();
      for (final raw in response.chunk) {
        if (!known.add(raw.eventId)) continue;
        entries.add(await _entryFor(raw));
      }
      _nextBatch = response.nextBatch;
      _loadedFirstPage = true;
    } catch (e, s) {
      error = e;
      Log.onError(e, s, content: "Could not load the room's threads");
    }
  }

  Future<ThreadListEntry> _entryFor(matrix.MatrixEvent raw) async {
    final mxRoom = room.matrixRoom;
    final root = await _decrypted(matrix.Event.fromMatrixEvent(raw, mxRoom));

    final summary = raw.unsigned?['m.relations'];
    final thread = summary is Map ? summary['m.thread'] : null;
    var replyCount = 0;
    var participated = false;
    matrix.Event? latest;
    if (thread is Map) {
      final count = thread['count'];
      if (count is int) replyCount = count;
      participated = thread['current_user_participated'] == true;
      final latestJson = thread['latest_event'];
      if (latestJson is Map<String, Object?>) {
        try {
          latest = await _decrypted(matrix.Event.fromJson(latestJson, mxRoom));
        } catch (e, s) {
          Log.onError(e, s, content: "Unreadable latest event of a thread");
        }
      }
    }

    return ThreadListEntry(
      root: room.convertEvent(root),
      replyCount: replyCount,
      latestReply: latest == null ? null : room.convertEvent(latest),
      participated: participated,
    );
  }

  Future<matrix.Event> _decrypted(matrix.Event event) async {
    if (event.type != matrix.EventTypes.Encrypted) return event;
    try {
      return await room.matrixRoom.client.encryption?.decryptRoomEvent(event) ??
          event;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not decrypt a thread's event");
      return event;
    }
  }

  void _notify() {
    if (!_closed) _changed.add(null);
  }

  void close() {
    _closed = true;
    _changed.close();
  }
}
