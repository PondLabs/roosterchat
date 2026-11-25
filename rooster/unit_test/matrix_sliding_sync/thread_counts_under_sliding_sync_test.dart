// A room's badge under Simplified Sliding Sync (MSC4186): it has no
// per-thread unread counts, so the room's own count from the server is the
// badge. The thread counts /v3/sync left are dropped, also in a room the
// Sliding Sync answer does not name, and the badge is drawn again.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_room.dart';

import '../speed_log/fake_account.dart';
import 'sliding_sync_fakes.dart';

/// A `/v3/sync` that gives [room] a count of 1 and an unread thread of 2
/// notifications, 1 highlight.
Future<void> _v3ThreadCounts(MatrixRoom room) async {
  final mx = room.matrixRoom.client;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'v3_counts',
        rooms: matrix.RoomsUpdate(join: {
          room.matrixRoom.id: matrix.JoinedRoomUpdate(
            unreadNotifications: matrix.UnreadNotificationCounts(
                notificationCount: 1, highlightCount: 0),
            unreadThreadNotifications: {
              r'$thread_root': matrix.UnreadNotificationCounts(
                  notificationCount: 2, highlightCount: 1),
            },
          ),
        }),
      )));
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
      'the change to Sliding Sync leaves only the server count on the badge '
      'of a room its answer does not name, and draws it again', () async {
    final server = SlidingSyncServer();
    final client = await signedIn(server);
    final mx = client.getMatrixClient();
    mx.forceLegacySync = true;
    final room = await plainRoom(client);
    await _v3ThreadCounts(room);
    expect(room.notificationCount, 3, reason: 'room 1 + thread 2 on /v3');
    expect(room.highlightedNotificationCount, 1);

    var updates = 0;
    final subscription = room.onUpdate.listen((_) => updates++);
    mx.forceLegacySync = false;
    // The fake server's answer names no room.
    await mx.oneShotSync();
    await Future<void>.delayed(Duration.zero);
    expect(mx.syncTransport, matrix.SyncTransport.slidingSync);

    expect(room.notificationCount, 1);
    expect(room.highlightedNotificationCount, 0);
    expect(updates, greaterThan(0), reason: 'the badge is drawn again');
    await subscription.cancel();
  });
}
