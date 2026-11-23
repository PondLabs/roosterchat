// Criterion 1: the public room directory keeps the exact order of
// `POST /v3/publicRooms` (v1.19, MSC4423), even when `num_joined_members`
// is out of order, pages through `next_batch`, and handles an empty list or
// a server that does not answer.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/components/room_directory/matrix_room_directory.dart';
import 'package:rooster/ui/pages/explore/explore_page.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

Map<String, Object?> chunk(String id, int members,
        {bool worldReadable = false}) =>
    {
      'room_id': id,
      'name': 'Room $id',
      'num_joined_members': members,
      'guest_can_join': false,
      'world_readable': worldReadable,
    };

/// Two pages whose member counts go up and down: a client sorting by
/// members would show them in another order.
http.Response? twoPages(Seen request) {
  if (!request.path.endsWith('/v3/publicRooms')) return null;
  final since = (request.body as Map?)?['since'];
  if (since == null) {
    return json({
      'chunk': [
        chunk('!small:example.org', 2),
        chunk('!big:example.org', 900, worldReadable: true),
        chunk('!mid:example.org', 40),
      ],
      'next_batch': 'page2',
      'total_room_count_estimate': 5,
    });
  }
  return json({
    'chunk': [
      chunk('!huge:example.org', 5000),
      chunk('!tiny:example.org', 1),
    ],
    'prev_batch': 'page1',
  });
}

const firstPage = [
  '!small:example.org',
  '!big:example.org',
  '!mid:example.org'
];

void main() {
  group('PublicRoomDirectory', () {
    test('keeps the order the server sent, across pages', () async {
      final script = Script()..routes.add(twoPages);
      final directory = PublicRoomDirectory(DirectoryTestClient(script));

      await directory.search();
      expect(directory.rooms.map((r) => r.roomId), firstPage);
      expect(directory.status, PublicRoomDirectoryStatus.loaded);
      expect(directory.hasMore, isTrue);

      await directory.loadMore();
      expect(directory.rooms.map((r) => r.roomId),
          [...firstPage, '!huge:example.org', '!tiny:example.org']);
      expect(directory.hasMore, isFalse, reason: 'no next_batch on page 2');

      final posts = script.where('POST', '/_matrix/client/v3/publicRooms');
      expect(posts, hasLength(2));
      expect((posts.first.body as Map).containsKey('since'), isFalse);
      expect((posts.last.body as Map)['since'], 'page2');
      expect((posts.first.body as Map)['limit'], directory.pageSize);

      // Nothing more to load: no request.
      await directory.loadMore();
      expect(script.where('POST', '/publicRooms'), hasLength(2));
    });

    test('a search sends its term and the remote server, and joins via it',
        () async {
      final script = Script()..routes.add(twoPages);
      final directory = PublicRoomDirectory(DirectoryTestClient(script));

      await directory.search(term: '  rust  ', server: ' other.org ');

      final post = script.where('POST', '/publicRooms').single;
      expect(post.url.queryParameters['server'], 'other.org');
      expect((post.body as Map)['filter'], {'generic_search_term': 'rust'});
      expect(directory.joinAddress(directory.rooms.first),
          '!small:example.org?via=other.org');

      await directory.search();
      final local = script.where('POST', '/publicRooms').last;
      expect(local.url.queryParameters.containsKey('server'), isFalse);
      expect((local.body as Map).containsKey('filter'), isFalse);
      expect(
          directory.joinAddress(directory.rooms.first), '!small:example.org');
    });

    test('an empty directory is empty, not loaded', () async {
      final script = Script()
        ..routes.add((r) => r.path.endsWith('/publicRooms')
            ? json({'chunk': <Object>[], 'next_batch': ''})
            : null);
      final directory = PublicRoomDirectory(DirectoryTestClient(script));

      await directory.search();
      expect(directory.status, PublicRoomDirectoryStatus.empty);
      expect(directory.rooms, isEmpty);
      expect(directory.hasMore, isFalse);
    });

    for (final (label, route) in <(String, FakeRoute)>[
      ('answers 502', (r) => http.Response('Bad gateway', 502)),
      ('refuses with M_FORBIDDEN', (r) => matrixError('M_FORBIDDEN')),
      (
        'cannot be reached',
        (r) => throw const SocketException('Connection refused')
      ),
    ]) {
      test('a server that $label is unavailable', () async {
        final script = Script()..routes.add(route);
        final directory = PublicRoomDirectory(DirectoryTestClient(script));

        await directory.search(server: 'down.example.org');
        expect(directory.status, PublicRoomDirectoryStatus.unavailable);
        expect(directory.error, isNotNull);
        expect(directory.rooms, isEmpty);
      });
    }

    test('a failed next page keeps the rooms shown and can be asked again',
        () async {
      var failNext = false;
      final script = Script()
        ..routes.add((r) {
          if (failNext && (r.body as Map?)?['since'] != null) {
            failNext = false;
            return http.Response('down', 503);
          }
          return twoPages(r);
        });
      final directory = PublicRoomDirectory(DirectoryTestClient(script));
      await directory.search();

      failNext = true;
      await directory.loadMore();
      expect(directory.loadMoreFailed, isTrue);
      expect(directory.rooms.map((r) => r.roomId), firstPage);
      expect(directory.hasMore, isTrue);

      await directory.loadMore();
      expect(directory.rooms, hasLength(5));
      expect(directory.loadMoreFailed, isFalse);
    });
  });

  group('ExplorePage', () {
    setUpAll(prepareTests);

    Future<Script> open(WidgetTester tester, FakeRoute route) async {
      final script = Script()..routes.add(route);
      final client = await tester.runAsync(() => fakeAccount(
          'explore_${DateTime.now().microsecondsSinceEpoch}',
          ScriptedAccountTransport(script)));
      await tester.pumpWidget(host(ExplorePage(client!), scroll: false));
      await settle(tester);
      return script;
    }

    double top(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('explore_room_$id'))).dy;

    testWidgets('lists the rooms in the server order and loads more',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester, twoPages);

      expect(top(tester, firstPage[0]), lessThan(top(tester, firstPage[1])));
      expect(top(tester, firstPage[1]), lessThan(top(tester, firstPage[2])));
      expect(find.text(ExplorePage.labelExploreMembers(900)), findsOneWidget);
      // Only the world-readable room offers a preview.
      expect(find.text(ExplorePage.promptExplorePreview), findsOneWidget);

      await tester.tap(find.byKey(ExplorePage.loadMoreKey));
      await settle(tester);
      expect(top(tester, firstPage[2]),
          lessThan(top(tester, '!huge:example.org')));
      expect(top(tester, '!huge:example.org'),
          lessThan(top(tester, '!tiny:example.org')));
      expect(find.byKey(ExplorePage.loadMoreKey), findsNothing);
    });

    testWidgets('says so when there is no public room', (tester) async {
      await open(
          tester,
          (r) => r.path.endsWith('/publicRooms')
              ? json({'chunk': <Object>[]})
              : null);
      expect(find.text(ExplorePage.messageExploreEmpty), findsOneWidget);
    });

    testWidgets('says so when the server is unavailable, and retries',
        (tester) async {
      var down = true;
      final script = await open(
          tester,
          (r) => r.path.endsWith('/publicRooms')
              ? (down ? http.Response('down', 502) : twoPages(r))
              : null);
      expect(find.text(ExplorePage.messageExploreUnavailable), findsOneWidget);

      down = false;
      await tester.tap(find.text(ExplorePage.promptExploreRetry));
      await settle(tester);
      expect(find.text(ExplorePage.messageExploreUnavailable), findsNothing);
      expect(find.byKey(const ValueKey('explore_room_!small:example.org')),
          findsOneWidget);
      expect(script.where('POST', '/publicRooms'), hasLength(2));
    });
  });
}
