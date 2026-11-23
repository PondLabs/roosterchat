import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/push_notifications/matrix_notification_history.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/ui/organisms/notifications/notification_history_panel.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../matrix_phase0/test_helpers.dart';

Map<String, Object?> notification(String eventId,
        {bool highlight = false, bool read = false, String? body}) =>
    {
      'actions': [
        'notify',
        if (highlight) {'set_tweak': 'highlight'},
      ],
      'event': {
        'event_id': eventId,
        'type': 'm.room.message',
        'sender': '@bob:example.test',
        'room_id': '!room:example.test',
        'origin_server_ts': 1700000000000,
        'content': {'msgtype': 'm.text', 'body': body ?? 'message $eventId'},
      },
      'read': read,
      'room_id': '!room:example.test',
      'ts': 1700000000000,
    };

/// `/v3/notifications` with two pages of everything and one of mentions.
class FakeNotificationsServer {
  final requests = <Uri>[];
  bool empty = false;
  bool fail = false;

  late final client = TestMatrixClient('history_test',
      accessToken: 'token',
      userId: '@alice:example.test', httpClient: MockClient((request) async {
    requests.add(request.url);
    if (fail) {
      return http.Response(
          jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'down'}), 500);
    }
    final query = request.url.queryParameters;
    if (empty) {
      return http.Response(jsonEncode({'notifications': []}), 200);
    }
    if (query['only'] == 'highlight') {
      return http.Response(
          jsonEncode({
            'notifications': [notification(r'$mention', highlight: true)]
          }),
          200);
    }
    if (query['from'] == 'page2') {
      return http.Response(
          jsonEncode({
            'notifications': [notification(r'$c', read: true)]
          }),
          200);
    }
    return http.Response(
        jsonEncode({
          'next_token': 'page2',
          'notifications': [notification(r'$a'), notification(r'$b')],
        }),
        200);
  }));
}

class _FakeRoom implements Room {
  _FakeRoom(this.identifier);
  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeNotificationsServer server;
  late MatrixNotificationHistory history;

  setUp(() {
    server = FakeNotificationsServer();
    history = MatrixNotificationHistory(server.client, pageSize: 2);
  });

  group('the history', () {
    test('reads the first page, then the next by next_token', () async {
      await history.refresh();
      expect(server.requests.single.path, '/_matrix/client/v3/notifications');
      expect(server.requests.single.queryParameters, {'limit': '2'});
      expect(history.items.map((n) => n.event.eventId), [r'$a', r'$b']);
      expect(history.hasMore, isTrue);

      await history.loadMore();
      expect(server.requests.last.queryParameters,
          {'from': 'page2', 'limit': '2'});
      expect(history.items.map((n) => n.event.eventId), [r'$a', r'$b', r'$c']);
      expect(history.hasMore, isFalse);

      // The last page had no next_token: nothing more to ask for.
      await history.loadMore();
      expect(server.requests, hasLength(2));
    });

    test('mentions only asks with only=highlight, from the start', () async {
      await history.refresh();
      await history.setFilter(NotificationHistoryFilter.mentions);
      expect(server.requests.last.queryParameters,
          {'limit': '2', 'only': 'highlight'});
      expect(history.items.map((n) => n.event.eventId), [r'$mention']);
      expect(
          MatrixNotificationHistory.isHighlight(history.items.single), isTrue);
      expect(history.hasMore, isFalse);
    });

    test('a page asked for before the filter changed is dropped', () async {
      final first = history.refresh();
      final second = history.setFilter(NotificationHistoryFilter.mentions);
      await Future.wait([first, second]);
      expect(history.items.map((n) => n.event.eventId), [r'$mention']);
    });

    test('no notifications is the empty state', () async {
      server.empty = true;
      expect(history.isEmpty, isFalse);
      await history.refresh();
      expect(history.isEmpty, isTrue);
      expect(history.hasMore, isFalse);
    });

    test('a refused request is an error, not an empty history', () async {
      server.fail = true;
      await history.refresh();
      expect(history.error, isA<matrix.MatrixException>());
      expect(history.isEmpty, isFalse);
    });
  });

  group('the panel', () {
    Future<List<matrix.Notification>> pump(WidgetTester tester) async {
      final opened = <matrix.Notification>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: SingleChildScrollView(
            child:
                NotificationHistoryPanel(history: history, onOpen: opened.add),
          ),
        ),
      ));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('lists, pages, filters and opens the event', (tester) async {
      final opened = await pump(tester);
      expect(find.textContaining(r'message $a'), findsOneWidget);
      expect(find.textContaining(r'message $b'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'message $c'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);

      await tester.tap(find.textContaining(r'message $b'));
      expect(opened.single.event.eventId, r'$b');
      expect(opened.single.roomId, '!room:example.test');

      await tester.tap(find.text('Mentions'));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'message $mention'), findsOneWidget);
      expect(find.textContaining(r'message $a'), findsNothing);
    });

    testWidgets('says when there are no notifications', (tester) async {
      server.empty = true;
      await pump(tester);
      expect(find.text('No notifications yet'), findsOneWidget);
      await tester.tap(find.text('Mentions'));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('No mentions yet'), findsOneWidget);
    });

    testWidgets('offers to try again after an error', (tester) async {
      server.fail = true;
      await pump(tester);
      expect(find.text("Couldn't load your notifications."), findsOneWidget);
      server.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'message $a'), findsOneWidget);
    });
  });

  testWidgets('opening a notification opens its room, then its event',
      (tester) async {
    final rooms = <RoomOpenArgs>[];
    final jumps = <String>[];
    final subscriptions = [
      EventBus.openRoom.stream.listen(rooms.add),
      EventBus.jumpToEvent.stream.listen(jumps.add),
    ];
    addTearDown(() {
      for (final s in subscriptions) {
        s.cancel();
      }
    });

    late BuildContext settingsContext;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Text('main page')));
    navigator.currentState!.push(MaterialPageRoute(builder: (context) {
      settingsContext = context;
      return const Text('settings');
    }));
    await tester.pumpAndSettle();

    final done = openNotificationEvent(settingsContext,
        roomId: '!room:example.test', eventId: r'$b', clientId: 'client-1');
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsNothing);
    expect(rooms.single.roomId, '!room:example.test');
    expect(rooms.single.clientId, 'client-1');
    // Not before the room is the selected one.
    expect(jumps, isEmpty);

    EventBus.onSelectedRoomChanged.add(_FakeRoom('!other:example.test'));
    EventBus.onSelectedRoomChanged.add(_FakeRoom('!room:example.test'));
    await tester.pump();
    await tester.pump();
    await done;
    expect(jumps, [r'$b']);
  });

  testWidgets('a room that was open already still gets the jump',
      (tester) async {
    final jumps = <String>[];
    final sub = EventBus.jumpToEvent.stream.listen(jumps.add);
    addTearDown(sub.cancel);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final done = openNotificationEvent(context,
        roomId: '!open:example.test',
        eventId: r'$x',
        timeout: const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 5));
    expect(jumps, isEmpty);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    await done;
    expect(jumps, [r'$x']);
  });
}
