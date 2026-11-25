// Criterion 1: the threads panel asks `GET /rooms/{roomId}/threads` with
// `include: all|participated`, pages with `from`, and says so, in the
// app's language, when the room has no thread.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/components/threads/matrix_thread_list.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/organisms/threads/threads_panel.dart';

import 'harness.dart';

Map<String, Object?> rootJson(String id,
        {int replies = 2, bool participated = false, String body = 'root'}) =>
    {
      'type': 'm.room.message',
      'event_id': id,
      'sender': alice,
      'origin_server_ts': 1000,
      'content': {'msgtype': 'm.text', 'body': body},
      'unsigned': {
        'm.relations': {
          'm.thread': {
            'count': replies,
            'current_user_participated': participated,
            'latest_event': {
              'type': 'm.room.message',
              'event_id': '${id}_latest',
              'sender': alice,
              'origin_server_ts': 2000,
              'content': {
                'msgtype': 'm.text',
                'body': 'latest of $id',
                'm.relates_to': {'rel_type': 'm.thread', 'event_id': id},
              },
            },
          },
        },
      },
    };

/// Answers the threads API page by page: `from` picks the page, and each
/// page but the last names the next.
http.Response? Function(Seen) threadPages(List<List<String>> pages) => (r) {
      if (r.method != 'GET' || !r.path.endsWith('/threads')) return null;
      final from = r.url.queryParameters['from'];
      final index = from == null ? 0 : int.parse(from.substring(4));
      return json({
        'chunk': [for (final id in pages[index]) rootJson(id)],
        if (index + 1 < pages.length) 'next_batch': 'page${index + 1}',
      });
    };

Iterable<Seen> threadRequests(Script script) => script.where('GET', '/threads');

void main() {
  setUpAll(prepareTests);

  group('MatrixThreadList', () {
    test('asks for all threads, then pages with from', () async {
      final (script, _, room) = await threadAccount(routes: [
        threadPages([
          [r'$a', r'$b'],
          [r'$c'],
        ]),
      ]);
      final list = MatrixThreadList(room, pageSize: 2);
      addTearDown(list.close);

      await list.loadMore();
      expect(list.entries.map((e) => e.threadRootId), [r'$a', r'$b']);
      expect(list.hasMore, isTrue);
      final first = threadRequests(script).single.url;
      expect(
          first.path,
          '/_matrix/client/v1/rooms/'
          '${Uri.encodeComponent(room.matrixRoom.id)}/threads');
      expect(first.queryParameters['include'], 'all');
      expect(first.queryParameters['limit'], '2');
      expect(first.queryParameters.containsKey('from'), isFalse);

      await list.loadMore();
      expect(list.entries.map((e) => e.threadRootId), [r'$a', r'$b', r'$c']);
      expect(threadRequests(script).last.url.queryParameters['from'], 'page1');
      expect(list.hasMore, isFalse);

      // The last page had no next: nothing more is asked.
      await list.loadMore();
      expect(threadRequests(script), hasLength(2));
    });

    test('asks for the threads we take part in', () async {
      final (script, _, room) = await threadAccount(routes: [
        threadPages([
          [r'$a']
        ]),
      ]);
      final list =
          MatrixThreadList(room, filter: ThreadListFilter.participated);
      addTearDown(list.close);

      await list.loadMore();

      expect(threadRequests(script).single.url.queryParameters['include'],
          'participated');
    });

    test('reads the summary the server bundles with each root', () async {
      final (_, _, room) = await threadAccount(routes: [
        (r) => r.path.endsWith('/threads')
            ? json({
                'chunk': [rootJson(r'$a', replies: 5, participated: true)]
              })
            : null,
      ]);
      final list = MatrixThreadList(room);
      addTearDown(list.close);

      await list.loadMore();

      final entry = list.entries.single;
      expect(entry.replyCount, 5);
      expect(entry.participated, isTrue);
      expect(entry.latestReply?.eventId, r'$a_latest');
    });

    test('is empty when the room has no thread', () async {
      final (_, _, room) = await threadAccount(routes: [
        threadPages([[]]),
      ]);
      final list = MatrixThreadList(room);
      addTearDown(list.close);
      expect(list.isEmpty, isFalse, reason: 'not loaded yet');

      await list.loadMore();

      expect(list.isEmpty, isTrue);
      expect(list.hasMore, isFalse);
    });

    test('keeps the error and asks again', () async {
      var fail = true;
      final (script, _, room) = await threadAccount(routes: [
        (r) {
          if (!r.path.endsWith('/threads')) return null;
          if (fail) return matrixError('M_UNKNOWN', status: 500);
          return json({
            'chunk': [rootJson(r'$a')]
          });
        },
      ]);
      final list = MatrixThreadList(room);
      addTearDown(list.close);

      await list.loadMore();
      expect(list.error, isNotNull);
      expect(list.isEmpty, isFalse);
      expect(list.hasMore, isTrue);

      fail = false;
      await list.loadMore();
      expect(list.error, isNull);
      expect(list.entries, hasLength(1));
      expect(threadRequests(script), hasLength(2));
    });
  });

  group('ThreadsPanel', () {
    Future<(Script, MatrixRoom)> panel(WidgetTester tester,
        List<List<String>> pages, List<String> opened) async {
      final (script, _, room) = (await tester.runAsync(() => threadAccount(
            routes: [threadPages(pages)],
          )))!;
      await tester.pumpWidget(host(
          ThreadsPanel(room: room, onOpenThread: opened.add),
          scroll: false));
      await settle(tester);
      return (script, room);
    }

    testWidgets('lists the threads and opens the one picked', (tester) async {
      final opened = <String>[];
      await panel(
          tester,
          [
            [r'$a', r'$b']
          ],
          opened);

      expect(find.byKey(const ValueKey(r'thread-entry-$a')), findsOneWidget);
      expect(find.byKey(const ValueKey(r'thread-entry-$b')), findsOneWidget);
      expect(
          find.text(ThreadsPanel.labelThreadReplyCount(2)), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey(r'thread-entry-$b')));
      expect(opened, [r'$b']);
    });

    testWidgets('loads the next page when the end of the list shows',
        (tester) async {
      final (script, _) = await panel(tester, [
        [r'$a'],
        [r'$b'],
      ], []);

      expect(threadRequests(script).map((s) => s.url.queryParameters['from']),
          [null, 'page1']);
      expect(find.byKey(const ValueKey(r'thread-entry-$b')), findsOneWidget);
    });

    testWidgets('says so when the room has no thread', (tester) async {
      await panel(tester, [[]], []);

      expect(find.text(ThreadsPanel.messageNoThreads), findsOneWidget);
      expect(find.text('No threads here yet'), findsOneWidget);
    });

    testWidgets('filters to the threads we take part in', (tester) async {
      final (script, _) = await panel(tester, [[]], []);

      await tester
          .tap(find.byKey(const ValueKey('threads-filter-participated')));
      await settle(tester);

      expect(
          threadRequests(script).map((s) => s.url.queryParameters['include']),
          ['all', 'participated']);
      expect(
          find.text(ThreadsPanel.messageNoParticipatedThreads), findsOneWidget);
    });
  });
}
