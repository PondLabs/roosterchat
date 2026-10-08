// A message that calls on us is highlighted, as on Discord: mentioning us,
// or replying to one of our messages. Asked for with a screenshot of
// Discord's gold bar and tint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:rooster/generated/l10n.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:rooster/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:rooster/ui/pages/developer/benchmarks/benchmark_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const _me = '@benchy:example.com';

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

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await T.load(const Locale('en'));
    await initializeDateFormatting('en');
    await preferences.layoutOverride.set('desktop');
  });

  setUp(() {
    client = MatrixClient(identifier: 'mentions', database: _Database());
    client.mockComponents();
    client.self = MatrixProfile(
        client, matrix.Profile(userId: _me, displayName: 'Benchy'));
    client.matrixClient.setUserId(_me);
    UserIdleWatcher.instance.dispose();
    room = client.createRoomWithData();
  });

  matrix.Event message(String id, String body,
          {String sender = '@carol:example.com',
          Map<String, Object?>? mentions,
          String? replyTo}) =>
      matrix.Event.fromJson({
        'event_id': id,
        'type': 'm.room.message',
        'content': {
          'body': body,
          'msgtype': 'm.text',
          if (mentions != null) 'm.mentions': mentions,
          if (replyTo != null)
            'm.relates_to': {
              'm.in_reply_to': {'event_id': replyTo}
            },
        },
        'sender': sender,
        'room_id': room.matrixRoom.id,
        'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      }, room.matrixRoom);

  bool callsOnMe(matrix.Event event) => room.convertEvent(event).mentionsSelf;

  test('a message mentioning us calls on us', () {
    expect(
        callsOnMe(message(r'$a', 'hey', mentions: {
          'user_ids': [_me]
        })),
        isTrue);
  });

  test('one mentioning someone else, or nobody, does not', () {
    expect(
        callsOnMe(message(r'$b', 'hey', mentions: {
          'user_ids': ['@dave:example.com']
        })),
        isFalse);
    expect(callsOnMe(message(r'$c', 'hey')), isFalse);
  });

  test('our own message never does, even naming us', () {
    expect(
        callsOnMe(message(r'$d', 'note to self', sender: _me, mentions: {
          'user_ids': [_me]
        })),
        isFalse);
  });

  test('@room only from someone allowed to ping the room', () {
    expect(callsOnMe(message(r'$e', '@room hi', mentions: {'room': true})),
        isFalse);
  });

  testWidgets('in the timeline, a mention and a reply to us are highlighted',
      (tester) async {
    final timeline = room.getBenchmarkTimeline();
    // Ours, then a reply to it, a mention, and a message that is neither.
    void add(matrix.Event event) =>
        timeline.insertEvent(0, room.convertEvent(event));
    add(message(r'$mine', 'something I said', sender: _me));
    add(message(r'$reply', 'answering you', replyTo: r'$mine'));
    add(message(r'$ping', 'look at this', mentions: {
      'user_ids': [_me]
    }));
    add(message(r'$plain', 'just chatting'));

    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    bool highlighted(String text) {
      // The message's own text, not where a reply quotes it.
      final own = find
          .textContaining(text, findRichText: true)
          .evaluate()
          .where((e) => find
              .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byType(TimelineEventViewReply))
              .evaluate()
              .isEmpty)
          .single;
      final layout = find
          .ancestor(
              of: find.byWidget(own.widget),
              matching: find.byType(TimelineEventLayoutMessage))
          .first;
      return tester.widget<TimelineEventLayoutMessage>(layout).isMentioningSelf;
    }

    expect(highlighted('look at this'), isTrue);
    expect(highlighted('answering you'), isTrue);
    expect(highlighted('just chatting'), isFalse);
    expect(highlighted('something I said'), isFalse);

    // In the gold bar and tint, whatever the theme.
    final bar = find.byWidgetPredicate((widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border is Border &&
        ((widget.decoration as BoxDecoration).border as Border).left.color ==
            TimelineEventLayoutMessage.mentionColor);
    expect(bar, findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await timeline.close();
  });
}
