// A text channel open on screen keeps showing its latest message as new ones
// come in, and the "New messages" line marks what arrived unseen. Asked for
// with the chat sitting still while messages piled up below it: one that
// grew after it was scrolled to (a link preview loading) left the view off
// the bottom, and from then on nothing new scrolled into view.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:rooster/generated/l10n.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/ui/pages/developer/benchmarks/benchmark_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Database implements matrix.DatabaseApi {
  @override
  Future<List<matrix.Event>> getUnimportantRoomEventStatesForRoom(
          List<String> types, matrix.Room room) async =>
      [];

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MatrixClient client;
  late MatrixRoom room;
  late MatrixTimeline timeline;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await T.load(const Locale('en'));
    await initializeDateFormatting('en');
    await preferences.layoutOverride.set('desktop');
  });

  setUp(() {
    client = MatrixClient(identifier: 'follow', database: _Database());
    client.mockComponents();
    client.self = MatrixProfile(client,
        matrix.Profile(userId: '@benchy:example.com', displayName: 'Benchy'));
    UserIdleWatcher.instance.dispose();
    room = client.createRoomWithData();
    timeline = room.getBenchmarkTimeline();
  });

  void lifecycle(AppLifecycleState state) {
    // ignore: invalid_use_of_protected_member
    WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
  }

  tearDown(() => lifecycle(AppLifecycleState.resumed));

  matrix.Event carolSays(String id, String body) => matrix.Event.fromJson({
        'event_id': id,
        'type': 'm.room.message',
        'content': {'body': body, 'msgtype': 'm.text'},
        'sender': '@carol:example.com',
        'room_id': room.matrixRoom.id,
        'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      }, room.matrixRoom);

  /// A message from someone else, as a sync brings it.
  void receive(String id, String body) =>
      timeline.insertEvent(0, room.convertEvent(carolSays(id, body)));

  /// The message at [index] grows, as one does when its link preview or
  /// image loads.
  void grow(int index, String id, String body) {
    timeline.events[index] = room.convertEvent(carolSays(id, body));
    timeline.notifyChanged(index);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
    ));
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await timeline.close();
  }

  Finder message(String text) =>
      find.textContaining(text, findRichText: true).first;

  Rect viewRect(WidgetTester tester) =>
      tester.getRect(find.byType(Scrollable).first);

  bool onScreen(WidgetTester tester, String text) {
    final found = find.textContaining(text, findRichText: true);
    if (found.evaluate().isEmpty) return false;
    final rect = tester.getRect(found.first);
    final view = viewRect(tester);
    return rect.top >= view.top - 0.5 && rect.bottom <= view.bottom + 0.5;
  }

  RoomTimelineWidgetViewState state(WidgetTester tester) =>
      tester.state(find.byType(RoomTimelineWidgetView));

  testWidgets('a message that comes in at the latest ones shows at once',
      (tester) async {
    await show(tester);

    for (var i = 0; i < 5; i++) {
      receive('\$new$i', 'fresh hello number $i');
      await tester.pump();
    }
    await settle(tester);

    expect(onScreen(tester, 'fresh hello number 4'), isTrue);
    expect(state(tester).recentItemsCount, 0);
    // Seen as it came in: no line.
    expect(find.text('New messages'), findsNothing);
    await done(tester);
  });

  testWidgets(
      'a burst of tall messages, one growing after it came in, keeps the '
      'latest in view', (tester) async {
    await show(tester);
    final tall = List.filled(40, 'line').join('\n');

    receive(r'$tall0', 'first of the burst\n$tall');
    await tester.pump(const Duration(milliseconds: 16));
    // It grows after it was scrolled to: the X card loading.
    grow(0, r'$tall0', 'first of the burst\n$tall\n$tall');
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 6; i++) {
      // Each one lands while the last is still scrolling into view.
      receive('\$tall$i', 'burst message $i\n$tall');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester);

    final last = find.textContaining('burst message 6', findRichText: true);
    expect(last, findsOneWidget);
    expect(tester.getRect(last).bottom,
        moreOrLessEquals(viewRect(tester).bottom, epsilon: 40));
    expect(state(tester).following, isTrue);
    expect(find.text('Jump to latest'), findsOneWidget,
        reason: 'built, but slid out of sight');
    expect(find.textContaining('new message'), findsNothing);
    await done(tester);
  });

  testWidgets(
      'with the window in the background, the line marks the first message '
      'that came in, and moves once it has been seen', (tester) async {
    await show(tester);

    lifecycle(AppLifecycleState.inactive);
    receive(r'$away1', 'while you were away one');
    await tester.pump();
    receive(r'$away2', 'while you were away two');
    await settle(tester);

    expect(onScreen(tester, 'while you were away two'), isTrue);
    expect(find.text('New messages'), findsOneWidget);
    expect(tester.getRect(find.text('New messages')).bottom,
        lessThanOrEqualTo(tester.getRect(message('away one')).top));

    // Back at the window: seen. The next one missed moves the line.
    lifecycle(AppLifecycleState.resumed);
    await settle(tester);
    lifecycle(AppLifecycleState.inactive);
    receive(r'$away3', 'while you were away three');
    await settle(tester);

    expect(find.text('New messages'), findsOneWidget);
    final line = tester.getRect(find.text('New messages'));
    expect(line.bottom,
        lessThanOrEqualTo(tester.getRect(message('away three')).top));
    expect(line.top,
        greaterThanOrEqualTo(tester.getRect(message('away two')).bottom));
    await done(tester);
  });

  testWidgets(
      'reading further up, new messages wait below, counted on the button '
      'that goes down to them', (tester) async {
    await show(tester);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
    await settle(tester);
    final reading = find
        .textContaining('https://example.com', findRichText: true)
        .evaluate()
        .map((e) => e.widget)
        .first;
    final before = tester.getRect(find.byWidget(reading));

    receive(r'$below1', 'came in below one');
    await tester.pump();
    receive(r'$below2', 'came in below two');
    await settle(tester);

    // What was being read stays put.
    expect(tester.getRect(find.byWidget(reading)), before);
    expect(onScreen(tester, 'came in below one'), isFalse);
    expect(find.text('2 new messages'), findsOneWidget);

    await tester.tap(find.text('2 new messages'));
    await settle(tester);
    await settle(tester);

    expect(onScreen(tester, 'came in below two'), isTrue);
    expect(find.text('New messages'), findsOneWidget);
    expect(tester.getRect(find.text('New messages')).bottom,
        lessThanOrEqualTo(tester.getRect(message('came in below one')).top));
    await done(tester);
  });
}
