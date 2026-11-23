// Criterion 3: a thread's unread notifications show as a badge on its root
// in the timeline and in the threads panel, red when one calls on us, and
// the badge goes once they are zero. The room's own badge still counts
// them, now that the server reports threads apart (Matrix v1.4).
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/threads/matrix_thread_unread.dart';
import 'package:rooster/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_thread.dart';
import 'package:rooster/ui/molecules/timeline_events/thread_unread_badge.dart';
import 'package:rooster/ui/organisms/threads/threads_panel.dart';

import 'harness.dart';

const root = r'$root';

final plain = find.byKey(const ValueKey('thread-unread-badge'));
final red = find.byKey(const ValueKey('thread-unread-badge-highlight'));

/// The root of a thread with one reply, as the server bundles it.
matrix.Event rootWithReply(MatrixRoom room) => matrix.Event(
      type: matrix.EventTypes.Message,
      eventId: root,
      senderId: alice,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(10),
      content: {'msgtype': 'm.text', 'body': 'root'},
      unsigned: {
        'm.relations': {
          'm.thread': {
            'count': 1,
            'latest_event': {
              'type': 'm.room.message',
              'event_id': r'$reply',
              'sender': alice,
              'origin_server_ts': 20,
              'content': {
                'msgtype': 'm.text',
                'body': 'a reply',
                'm.relates_to': {'rel_type': 'm.thread', 'event_id': root},
              },
            },
          },
        },
      },
      room: room.matrixRoom,
    );

void main() {
  setUpAll(prepareTests);

  Future<(MatrixClient, MatrixRoom)> account(WidgetTester tester) async {
    final (_, client, room) = (await tester.runAsync(() => threadAccount()))!;
    return (client, room);
  }

  testWidgets('shows the count, red with a highlight, and goes at zero',
      (tester) async {
    final (_, room) = await account(tester);
    await tester.pumpWidget(host(ThreadUnreadBadge(
        room: room.matrixRoom, threadRootId: root, key: UniqueKey())));
    expect(plain, findsNothing);
    expect(red, findsNothing);

    await tester.runAsync(() => syncCounts(room, threads: {root: (3, 0)}));
    await tester.pump();
    expect(plain, findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip(ThreadUnreadBadge.tooltipThreadUnread(3)),
        findsOneWidget);

    await tester.runAsync(() => syncCounts(room, threads: {root: (4, 1)}));
    await tester.pump();
    expect(red, findsOneWidget);
    expect(plain, findsNothing);
    expect(find.text('4'), findsOneWidget);

    // A sync with the room's counts and no entry for the thread: it has
    // none left.
    await tester.runAsync(() => syncCounts(room, notifications: 2));
    await tester.pump();
    await tester.pump();
    expect(plain, findsNothing);
    expect(red, findsNothing);
  });

  testWidgets('a highlight alone still shows a count', (tester) async {
    final (_, room) = await account(tester);
    await tester.runAsync(() => syncCounts(room, threads: {root: (0, 1)}));
    await tester.pumpWidget(
        host(ThreadUnreadBadge(room: room.matrixRoom, threadRootId: root)));

    expect(red, findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('goes when the thread is read here', (tester) async {
    final (_, room) = await account(tester);
    await tester.runAsync(() => syncCounts(room, threads: {root: (2, 0)}));
    await tester.pumpWidget(
        host(ThreadUnreadBadge(room: room.matrixRoom, threadRootId: root)));
    expect(plain, findsOneWidget);

    MatrixThreadUnread.clearLocally(room.matrixRoom, root);
    await tester.pump();

    expect(plain, findsNothing);
  });

  testWidgets("is on the thread's root in the timeline", (tester) async {
    final (client, room) = await account(tester);
    await tester.runAsync(() => syncCounts(room, threads: {root: (5, 0)}));
    final timeline = timelineOf(client, room, [rootWithReply(room)]);

    await tester.pumpWidget(host(TimelineEventViewThread(
        initialIndex: 0,
        timeline: timeline,
        component: MatrixThreadsComponent(client))));

    expect(find.text('a reply'), findsOneWidget);
    expect(plain, findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await tester.runAsync(() => syncCounts(room, threads: {root: (0, 0)}));
    await tester.pump();
    await tester.pump();
    expect(plain, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(timeline.close);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('is on the thread in the threads panel', (tester) async {
    late final MatrixRoom room;
    (_, _, room) = (await tester.runAsync(() => threadAccount(routes: [
          (r) => r.path.endsWith('/threads')
              ? json({
                  'chunk': [rootWithReply(room).toJson()]
                })
              : null,
        ])))!;
    await tester.runAsync(() => syncCounts(room, threads: {root: (2, 1)}));

    await tester.pumpWidget(
        host(ThreadsPanel(room: room, onOpenThread: (_) {}), scroll: false));
    await settle(tester);

    expect(find.byKey(const ValueKey(r'thread-entry-$root')), findsOneWidget);
    expect(red, findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  group("the room's badge", () {
    test('counts its threads', () async {
      final (_, _, room) = await threadAccount();
      await syncCounts(room, notifications: 1, highlights: 0, threads: {
        root: (2, 1),
        r'$other': (3, 0),
      });

      expect(room.notificationCount, 6);
      expect(room.highlightedNotificationCount, 1);
    });

    test('hears a sync that only changes the threads', () async {
      final (_, _, room) = await threadAccount();
      var updates = 0;
      final sub = room.onUpdate.listen((_) => updates++);
      addTearDown(sub.cancel);

      final mx = room.matrixRoom.client;
      await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
            nextBatch: 'threads_only',
            rooms: matrix.RoomsUpdate(join: {
              room.matrixRoom.id: matrix.JoinedRoomUpdate(
                unreadThreadNotifications: {
                  root: matrix.UnreadNotificationCounts(
                      notificationCount: 1, highlightCount: 0),
                },
              ),
            }),
          )));
      await Future<void>.delayed(Duration.zero);

      expect(updates, greaterThan(0));
      expect(room.notificationCount, 1);
    });

    test('"Mark as Read" reads the threads too', () async {
      final (_, _, room) = await threadAccount();
      await syncCounts(room, notifications: 1, threads: {root: (2, 0)});

      room.clearUnreadCountsLocally(threads: true);

      expect(room.notificationCount, 0);
      expect(MatrixThreadUnread.of(room.matrixRoom, root).isEmpty, isTrue);
    });

    test("reading the room's timeline leaves the threads unread", () async {
      final (_, _, room) = await threadAccount();
      await syncCounts(room, notifications: 1, threads: {root: (2, 0)});

      room.clearUnreadCountsLocally();

      expect(room.notificationCount, 2);
    });
  });

  test('the sync filter asks for per-thread counts', () {
    final filter = MatrixClient.syncFilter.toJson();
    expect(filter, {
      'room': {
        'state': {'lazy_load_members': true},
        'timeline': {'unread_thread_notifications': true},
      },
    });
  });
}
