import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;

/// How many notifications a thread has that we have not read: the
/// homeserver's `unread_thread_notifications` from `/sync` (Matrix v1.4,
/// MSC3773), read by the SDK into `Room.unreadThreadNotifications`.
class ThreadUnreadCounts {
  const ThreadUnreadCounts(this.notifications, this.highlights);

  static const none = ThreadUnreadCounts(0, 0);

  final int notifications;

  /// Notifications that call on us (a mention, a keyword).
  final int highlights;

  bool get isEmpty => notifications <= 0 && highlights <= 0;

  @override
  bool operator ==(Object other) =>
      other is ThreadUnreadCounts &&
      other.notifications == notifications &&
      other.highlights == highlights;

  @override
  int get hashCode => Object.hash(notifications, highlights);

  @override
  String toString() => 'ThreadUnreadCounts($notifications, $highlights)';
}

/// The per-thread unread counts of a room, and when they change. The SDK
/// keeps them; this reads them and clears one as soon as we read its
/// thread, instead of waiting for the next sync.
class MatrixThreadUnread {
  static final StreamController<String> _clearedLocally =
      StreamController<String>.broadcast();

  /// The counts of the thread rooted at [threadRootId] in [room].
  static ThreadUnreadCounts of(matrix.Room room, String threadRootId) {
    final counts = room.unreadThreadNotifications[threadRootId];
    if (counts == null) return ThreadUnreadCounts.none;
    return ThreadUnreadCounts(
        counts.notificationCount ?? 0, counts.highlightCount ?? 0);
  }

  /// Every thread of [room] with something unread, by root event id.
  static Map<String, ThreadUnreadCounts> all(matrix.Room room) => {
        for (final id in room.unreadThreadNotifications.keys)
          if (!of(room, id).isEmpty) id: of(room, id),
      };

  /// Fires when the counts of [room]'s threads may have changed: a sync
  /// that carries the room's counts (the server then names every thread
  /// with any), or a thread of it read here.
  static Stream<void> changes(matrix.Room room) {
    late final StreamController<void> controller;
    final subscriptions = <StreamSubscription>[];
    controller = StreamController<void>.broadcast(
      onListen: () {
        subscriptions.add(room.client.onSync.stream.listen((sync) {
          final update = sync.rooms?.join?[room.id];
          if (update == null) return;
          if (update.unreadNotifications == null &&
              update.unreadThreadNotifications == null) {
            return;
          }
          controller.add(null);
        }));
        subscriptions.add(_clearedLocally.stream
            .where((roomId) => roomId == room.id)
            .listen((_) => controller.add(null)));
      },
      onCancel: () {
        for (final subscription in subscriptions) {
          subscription.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  /// Clears the counts of the thread rooted at [threadRootId] once its
  /// latest message has been marked read. The next sync remains the
  /// authority: a message that arrived meanwhile brings them back.
  static void clearLocally(matrix.Room room, String threadRootId) {
    if (room.unreadThreadNotifications.remove(threadRootId) != null) {
      _changedLocally(room);
    }
  }

  /// Clears the counts of every thread of [room], once an unthreaded
  /// receipt has read them all.
  static void clearAllLocally(matrix.Room room) {
    if (room.unreadThreadNotifications.isEmpty) return;
    room.unreadThreadNotifications.clear();
    _changedLocally(room);
  }

  /// The SDK keeps the counts across restarts as each sync leaves them; a
  /// thread read here is kept too, so its badge does not come back when
  /// the app starts again before the next sync.
  static void _changedLocally(matrix.Room room) {
    unawaited(room.client.storeUnreadThreadNotifications());
    _clearedLocally.add(room.id);
  }
}
