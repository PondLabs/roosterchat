// Criterion 2: a thread's receipt names its root (`thread_id`, Matrix v1.4,
// MSC3771) as `m.read` or `m.read.private` by the user's preference, an
// empty thread gets none, and the room's own timeline reads with
// `thread_id: "main"`.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_threaded_receipts.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_unread.dart';
import 'package:rooster/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';

import 'harness.dart';

const root = r'$root';

/// The thread of [root] in [room], listing [replies] (newest first) and
/// the root, as it does once loaded.
(MatrixTimeline, MatrixThreadTimeline) threadOf(
    MatrixClient client, MatrixRoom room, List<matrix.Event> replies) {
  final main = timelineOf(client, room, [message(room, root, ts: 10)]);
  final thread = MatrixThreadTimeline(
    client: client,
    room: room,
    threadRootId: root,
    mainRoomTimeline: main,
    component: MatrixThreadsComponent(client),
  );
  thread.events
    ..addAll(replies.map(room.convertEvent))
    ..add(main.events.single);
  return (main, thread);
}

Future<void> settleRequests() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUpAll(prepareTests);

  group('a thread', () {
    test('sends m.read with thread_id = its root, on its newest reply',
        () async {
      final (script, client, room) = await threadAccount();
      room.matrixRoom.client.receiptsPublicByDefault = true;
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply2', threadRoot: root, ts: 30),
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(receipts(script), [
        ('m.read', r'$reply2', threaded(root)),
      ]);
      // Nothing unthreaded, and the fully read marker is left alone.
      expect(script.where('POST', '/read_markers'), isEmpty);
    });

    test('sends m.read.private when receipts are private', () async {
      final (script, client, room) = await threadAccount();
      room.matrixRoom.client.receiptsPublicByDefault = false;
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(receipts(script), [
        ('m.read.private', r'$reply1', threaded(root)),
      ]);
    });

    test("follows the room's own preference over the account's", () async {
      final (script, client, room) = await threadAccount();
      room.matrixRoom.client.receiptsPublicByDefault = true;
      await room.matrixRoom.client.handleSync(matrix.SyncUpdate(
        nextBatch: 'pref',
        rooms: matrix.RoomsUpdate(join: {
          room.matrixRoom.id: matrix.JoinedRoomUpdate(accountData: [
            matrix.BasicEvent(
                type: MatrixReadReceiptComponent.publicReadReceiptsKey,
                content: {'enabled': false}),
          ]),
        }),
      ));
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(receipts(script).single.$1, 'm.read.private');
    });

    test('with no reply sends nothing', () async {
      final (script, client, room) = await threadAccount();
      final (_, thread) = threadOf(client, room, []);

      // Only the root is listed: it belongs to the room's timeline.
      await thread.markAsRead(thread.events.first);
      thread.events.clear();
      await thread.markAsRead(room.convertEvent(message(room, root)));
      await settleRequests();

      expect(receipts(script), isEmpty);
    });

    test('sends one receipt per reply, and again for a newer one', () async {
      final (script, client, room) = await threadAccount();
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);
      await thread.markAsRead(thread.events.first);
      expect(receipts(script), hasLength(1));

      thread.events.insert(
          0, room.convertEvent(message(room, r'$reply2', threadRoot: root)));
      await thread.markAsRead(thread.events.first);
      expect(receipts(script).map((r) => r.$2), [r'$reply1', r'$reply2']);
    });

    test('on a server without threaded receipts sends nothing', () async {
      final (script, client, room) =
          await threadAccount(versions: ['v1.1', 'v1.3']);
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(receipts(script), isEmpty);
    });

    test("clears the thread's badge once read", () async {
      final (_, client, room) = await threadAccount();
      await syncCounts(room, notifications: 1, threads: {root: (2, 1)});
      expect(MatrixThreadUnread.of(room.matrixRoom, root).notifications, 2);
      expect(room.notificationCount, 3);
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(MatrixThreadUnread.of(room.matrixRoom, root).isEmpty, isTrue);
      // The room's own unread message is still there.
      expect(room.notificationCount, 1);
    });

    test('keeps the badge when the receipt fails', () async {
      final (script, client, room) = await threadAccount(routes: [
        (r) => r.path.contains('/receipt/')
            ? matrixError('M_UNKNOWN', status: 500)
            : null,
      ]);
      await syncCounts(room, threads: {root: (2, 0)});
      final (_, thread) = threadOf(client, room, [
        message(room, r'$reply1', threadRoot: root, ts: 20),
      ]);

      await thread.markAsRead(thread.events.first);

      expect(MatrixThreadUnread.of(room.matrixRoom, root).notifications, 2);
      // Asked again next time.
      await thread.markAsRead(thread.events.first);
      expect(script.where('POST', '/receipt/').length, greaterThan(1));
    });
  });

  group("the room's timeline", () {
    test('reads with thread_id "main" on its newest event outside threads',
        () async {
      final (script, client, room) = await threadAccount();
      room.matrixRoom.client.receiptsPublicByDefault = true;
      final timeline = timelineOf(client, room, [
        message(room, r'$inThread', threadRoot: root, ts: 40),
        message(room, r'$main2', ts: 30),
        message(room, root, ts: 10),
      ]);

      timeline.markAsRead(timeline.events.first);
      await settleRequests();

      expect(receipts(script), [
        ('m.read', r'$main2', threaded('main')),
      ]);
      // The fully read marker still goes on the newest event, with no
      // receipt of its own.
      expect(script.where('POST', '/read_markers').single.body,
          {'m.fully_read': r'$inThread'});
    });

    test('reads privately with thread_id "main" when receipts are private',
        () async {
      final (script, client, room) = await threadAccount();
      room.matrixRoom.client.receiptsPublicByDefault = false;
      final timeline = timelineOf(client, room, [message(room, r'$main1')]);

      timeline.markAsRead(timeline.events.first);
      await settleRequests();

      expect(receipts(script), [
        ('m.read.private', r'$main1', threaded('main')),
      ]);
    });

    test('keeps unthreaded receipts on a server before Matrix v1.4', () async {
      final (script, client, room) =
          await threadAccount(versions: ['v1.1', 'v1.3']);
      room.matrixRoom.client.receiptsPublicByDefault = true;
      final timeline = timelineOf(client, room, [message(room, r'$main1')]);

      timeline.markAsRead(timeline.events.first);
      await settleRequests();

      expect(receipts(script), isEmpty);
      expect(script.where('POST', '/read_markers').single.body, {
        'm.fully_read': r'$main1',
        'm.read': r'$main1',
        'm.read.private': r'$main1',
      });
    });
  });

  group('threadOf', () {
    matrix.Event? none(String _) => null;

    test('places messages, replies, reactions and edits', () async {
      final (_, _, room) = await threadAccount();
      final inThread = message(room, r'$t', threadRoot: root);
      final known = {r'$t': inThread, root: message(room, root)};
      matrix.Event related(String rel, String target) => matrix.Event(
            type: matrix.EventTypes.Reaction,
            eventId: '\$$rel$target',
            senderId: alice,
            originServerTs: DateTime.now(),
            content: {
              'm.relates_to': {'rel_type': rel, 'event_id': target}
            },
            room: room.matrixRoom,
          );

      expect(MatrixThreadedReceipts.threadOf(message(room, r'$m'), none),
          MatrixThreadedReceipts.mainThreadId);
      expect(MatrixThreadedReceipts.threadOf(inThread, none), root);
      expect(
          MatrixThreadedReceipts.threadOf(
              related(matrix.RelationshipTypes.reaction, r'$t'),
              (id) => known[id]),
          root);
      expect(
          MatrixThreadedReceipts.threadOf(
              related(matrix.RelationshipTypes.edit, root), (id) => known[id]),
          MatrixThreadedReceipts.mainThreadId);
      // Unknown target: could be in a thread.
      expect(
          MatrixThreadedReceipts.threadOf(
              related(matrix.RelationshipTypes.reaction, r'$gone'), none),
          isNull);
    });
  });
}
