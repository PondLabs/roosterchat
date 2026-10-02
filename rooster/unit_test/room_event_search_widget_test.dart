import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/event_search/event_search_component.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/room_event_search/room_event_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class Search implements EventSearchComponent {
  final requests = <Completer<EventSearchSession>>[];
  @override
  Future<EventSearchSession> createSearchSession(Room room) {
    final request = Completer<EventSearchSession>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SearchClient implements Client {
  SearchClient(this.search);
  final Search search;
  @override
  T? getComponent<T extends Component>() => search as T;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SearchRoom implements Room {
  SearchRoom(Search search) : client = SearchClient(search);
  @override
  final Client client;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Session implements EventSearchSession {
  final stream = StreamController<List<TimelineEvent>>();
  String? term;
  int pages = 0;
  @override
  bool currentlySearching = false;
  @override
  bool canContinueSearch = false;
  @override
  Stream<List<TimelineEvent>> startSearch(String searchTerm) {
    term = searchTerm;
    return stream.stream;
  }

  @override
  Stream<List<TimelineEvent>> continueSearch() {
    pages++;
    canContinueSearch = false;
    return Stream.value([]);
  }
}

Widget app(Room room) => MaterialApp(
      theme: ThemeData(extensions: const [ThemeSettings()]),
      home: Scaffold(body: RoomEventSearchWidget(room: room)),
    );

Future<void> submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  test('search actions and errors are translated in Portuguese', () async {
    await initializeMessages('pt_BR');
    Intl.withLocale('pt_BR', () {
      expect(RoomEventSearchWidget.roomSearchClear, 'Limpar busca');
      expect(RoomEventSearchWidget.roomSearchRetry, 'Tentar novamente');
      expect(RoomEventSearchWidget.roomSearchFailed,
          'Não foi possível buscar mensagens');
    });
  });

  testWidgets('Enter searches immediately and cancels the delayed duplicate', (
    tester,
  ) async {
    final search = Search();
    await tester.pumpWidget(app(SearchRoom(search)));
    await submit(tester, '  hello  ');
    expect(search.requests, hasLength(1));
    final session = Session();
    search.requests.single.complete(session);
    await tester.pump();
    expect(session.term, 'hello');
    session.stream.add([]);
    await tester.pump();
    expect(find.text('No results found'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(search.requests, hasLength(1));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('No results found'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    unawaited(session.stream.close());
    await tester.pump();
  });

  testWidgets('late session cannot replace a newer query or a cleared search', (
    tester,
  ) async {
    final search = Search();
    await tester.pumpWidget(app(SearchRoom(search)));
    await submit(tester, 'old');
    await submit(tester, 'new');
    final old = Session();
    final current = Session();
    search.requests[1].complete(current);
    await tester.pump();
    search.requests[0].complete(old);
    await tester.pump();
    expect(old.term, isNull);
    expect(current.term, 'new');
    await submit(tester, 'pending');
    await tester.tap(find.byTooltip('Clear search'));
    final cleared = Session();
    search.requests[2].complete(cleared);
    await tester.pump();
    expect(cleared.term, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('session and stream failures stop loading and allow retry', (
    tester,
  ) async {
    final search = Search();
    await tester.pumpWidget(app(SearchRoom(search)));
    await submit(tester, 'hello');
    search.requests.single.completeError(StateError('offline'));
    await tester.pump();
    expect(find.text("Couldn't search messages"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    final session = Session();
    search.requests.last.complete(session);
    await tester.pump();
    session.stream.addError(StateError('offline'));
    await tester.pump();
    expect(find.text("Couldn't search messages"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    final success = Session();
    search.requests.last.complete(success);
    await tester.pump();
    unawaited(success.stream.close());
    await tester.pump();
    expect(find.text("Couldn't search messages"), findsNothing);
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('empty page can continue when older messages remain', (
    tester,
  ) async {
    final search = Search();
    await tester.pumpWidget(app(SearchRoom(search)));
    await submit(tester, 'hello');
    final session = Session()..canContinueSearch = true;
    search.requests.single.complete(session);
    await tester.pump();
    session.stream.add([]);
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(session.pages, 1);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('switching rooms ignores the previous room search',
      (tester) async {
    final first = Search();
    final second = Search();
    await tester.pumpWidget(app(SearchRoom(first)));
    await submit(tester, 'hello');
    await tester.pumpWidget(app(SearchRoom(second)));
    await tester.pump(const Duration(seconds: 1));
    final stale = Session();
    first.requests.single.complete(stale);
    final current = Session();
    second.requests.single.complete(current);
    await tester.pump();
    expect(stale.term, isNull);
    expect(current.term, 'hello');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing cancels debounce and ignores an in-flight session', (
    tester,
  ) async {
    final search = Search();
    final room = SearchRoom(search);
    await tester.pumpWidget(app(room));
    await tester.enterText(find.byType(TextField), 'delayed');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(search.requests, isEmpty);
    await tester.pumpWidget(app(room));
    await submit(tester, 'pending');
    await tester.pumpWidget(const SizedBox());
    final session = Session();
    search.requests.single.complete(session);
    await tester.pump();
    expect(session.term, isNull);
    expect(tester.takeException(), isNull);
  });
}
