// Criterion 3: a Matrix v1.15 rich topic (`m.topic` with `text/html` and
// `text/plain`) is shown formatted and sanitized, by the same renderer as
// a message's HTML, in the timeline, in the room header and in the room's
// general settings; without `m.topic` the legacy `topic` is shown as text.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_rich_topic.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_room_topic.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/ui/atoms/room_header.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:rooster/ui/pages/settings/categories/room/general/matrix_room_topic_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../matrix_html/html_test_utils.dart';
import 'harness.dart';

/// HTML a sender could put in a topic: formatting to keep, a script, an
/// event handler and a `javascript:` link to drop.
const hostileHtml = '<b>Bold</b> eggs <script>steal("cookies")</script>'
    '<img src="x" onerror="steal(1)">'
    '<a href="javascript:steal(2)">tap</a>';

Map<String, Object?> richTopic(
        {String plain = 'Bold eggs tap', String? html = hostileHtml}) =>
    {
      'topic': 'Legacy topic',
      'm.topic': {
        'm.text': [
          if (html != null) {'body': html, 'mimetype': 'text/html'},
          {'body': plain, 'mimetype': 'text/plain'},
        ],
      },
    };

void expectSanitizedRichTopic(WidgetTester tester) {
  final bold = findSpans(tester, 'Bold');
  expect(bold, isNotEmpty, reason: 'the formatted topic is drawn');
  expect(bold.first.style.fontWeight, FontWeight.bold);
  final text = allText(tester);
  expect(text, isNot(contains('steal')));
  expect(text, isNot(contains('<b>')));
  // The javascript: link is shown as text, never as something to open.
  for (final span in findSpans(tester, 'tap')) {
    expect(span.recognizer, isNull);
  }
}

void main() {
  late MatrixClient client;
  late MatrixRoom room;

  setUpAll(() async {
    sqfliteFfiInit();
    (client, room) = await stateEventsRoom('rich_topic');
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  /// Makes [content] the room's current `m.room.topic`.
  void setTopic(Map<String, Object?> content) => room.matrixRoom
      .setState(stateEvent(room, matrix.EventTypes.RoomTopic, content));

  group('MatrixRichTopic reads m.topic through the SDK parser', () {
    test('HTML and plain text', () {
      final topic = MatrixRichTopic.fromContent(richTopic());
      expect(topic.html, hostileHtml);
      expect(topic.plain, 'Bold eggs tap');
    });

    test('a mimetype with parameters and an entry without one', () {
      final topic = MatrixRichTopic.fromContent({
        'm.topic': {
          'm.text': [
            {'body': '<i>x</i>', 'mimetype': 'Text/HTML; charset=utf-8'},
            {'body': 'x'},
          ],
        },
      });
      expect(topic.html, '<i>x</i>');
      expect(topic.plain, 'x');
    });

    test('m.topic without text/plain falls back to the legacy topic', () {
      final topic = MatrixRichTopic.fromContent({
        'topic': 'Legacy topic',
        'm.topic': {
          'm.text': [
            {'body': '<b>Rich</b>', 'mimetype': 'text/html'},
          ],
        },
      });
      expect(topic.html, '<b>Rich</b>');
      expect(topic.plain, 'Legacy topic');
    });

    test('only HTML: the text is the HTML\'s text', () {
      final topic = MatrixRichTopic.fromContent({
        'm.topic': {
          'm.text': [
            {'body': '<p><b>Rich</b> topic</p>', 'mimetype': 'text/html'},
          ],
        },
      });
      expect(topic.plain, 'Rich topic');
    });

    test('without m.topic, the legacy topic and no HTML', () {
      final topic = MatrixRichTopic.fromContent({'topic': 'Legacy topic'});
      expect(topic.html, isNull);
      expect(topic.plain, 'Legacy topic');
    });

    test('the room\'s topic is its m.room.topic state', () {
      setTopic(richTopic());
      expect(MatrixRichTopic.ofRoom(room.matrixRoom).html, hostileHtml);
      setTopic({'topic': 'Legacy topic'});
      expect(MatrixRichTopic.ofRoom(room.matrixRoom).html, isNull);
    });
  });

  group('timeline', () {
    testWidgets('a rich topic is drawn formatted and sanitized',
        (tester) async {
      final event = convert(room, matrix.EventTypes.RoomTopic, richTopic());
      expect(event, isA<MatrixTimelineEventRoomTopic>());
      expect((event as MatrixTimelineEventRoomTopic).getBody(),
          'Alice changed the topic to: Bold eggs tap');

      await tester.pumpWidget(host(TimelineEventViewGeneric(
          initialEvent: event, initialIndex: 0, room: room)));
      await tester.pump();

      expect(find.text('Alice changed the topic to:'), findsOneWidget);
      expect(find.byKey(TimelineEventViewGeneric.formattedTopicKey),
          findsOneWidget);
      expect(find.byType(MatrixHtmlState), findsOneWidget);
      expectSanitizedRichTopic(tester);
    });

    testWidgets('without m.topic, the legacy topic is the line\'s text',
        (tester) async {
      final event = convert(
          room, matrix.EventTypes.RoomTopic, {'topic': '<b>Legacy</b>'});

      await tester.pumpWidget(host(TimelineEventViewGeneric(
          initialEvent: event, initialIndex: 0, room: room)));
      await tester.pump();

      expect(find.text('Alice changed the topic to: <b>Legacy</b>'),
          findsOneWidget);
      expect(
          find.byKey(TimelineEventViewGeneric.formattedTopicKey), findsNothing);
      expect(find.byType(MatrixHtmlState), findsNothing);
    });

    testWidgets('m.topic with only text/plain is shown as text',
        (tester) async {
      final event =
          convert(room, matrix.EventTypes.RoomTopic, richTopic(html: null));

      await tester.pumpWidget(host(TimelineEventViewGeneric(
          initialEvent: event, initialIndex: 0, room: room)));
      await tester.pump();

      expect(find.text('Alice changed the topic to: Bold eggs tap'),
          findsOneWidget);
      expect(find.byType(MatrixHtmlState), findsNothing);
    });
  });

  group('room header', () {
    Future<void> pumpHeader(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(height: 50, child: RoomHeader(room)))));
      await tester.pump();
    }

    testWidgets('shows the rich topic formatted and sanitized', (tester) async {
      setTopic(richTopic());
      await pumpHeader(tester);

      expect(find.byKey(RoomHeader.formattedTopicKey), findsOneWidget);
      expect(find.text('Legacy topic'), findsNothing);
      expectSanitizedRichTopic(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the legacy topic without m.topic',
        (tester) async {
      setTopic({'topic': 'Legacy topic'});
      await pumpHeader(tester);

      expect(find.byKey(RoomHeader.formattedTopicKey), findsNothing);
      expect(find.text('Legacy topic'), findsOneWidget);
    });

    testWidgets('m.topic text/plain wins over the legacy topic',
        (tester) async {
      setTopic(richTopic(plain: 'Rich plain', html: null));
      await pumpHeader(tester);

      expect(find.byKey(RoomHeader.formattedTopicKey), findsNothing);
      expect(find.text('Rich plain'), findsOneWidget);
    });
  });

  group('general settings', () {
    testWidgets('shows the rich topic formatted and sanitized', (tester) async {
      setTopic(richTopic());
      await tester.pumpWidget(host(MatrixRoomTopicSettings(room)));
      await tester.pump();

      expect(find.text(MatrixRoomTopicSettings.labelRoomTopicHeader),
          findsOneWidget);
      expect(find.byKey(MatrixRoomTopicSettings.formattedKey), findsOneWidget);
      expectSanitizedRichTopic(tester);
    });

    testWidgets('shows the legacy topic as text without m.topic',
        (tester) async {
      setTopic({'topic': 'Legacy topic'});
      await tester.pumpWidget(host(MatrixRoomTopicSettings(room)));
      await tester.pump();

      expect(find.byKey(MatrixRoomTopicSettings.formattedKey), findsNothing);
      expect(find.text('Legacy topic'), findsOneWidget);
    });

    for (final (locale, empty, header) in [
      ('en', 'This room has no topic.', 'Topic'),
      ('pt', 'Esta sala não tem descrição.', 'Descrição'),
    ]) {
      testWidgets('says when there is no topic ($locale)', (tester) async {
        await useLocale(locale);
        setTopic({});
        await tester.pumpWidget(host(MatrixRoomTopicSettings(room)));
        await tester.pump();

        expect(find.text(header), findsOneWidget);
        expect(find.text(empty), findsOneWidget);
      });
    }

    testWidgets('follows a new topic', (tester) async {
      setTopic({'topic': 'Before'});
      await tester.pumpWidget(host(MatrixRoomTopicSettings(room)));
      expect(find.text('Before'), findsOneWidget);

      final after =
          stateEvent(room, matrix.EventTypes.RoomTopic, {'topic': 'After'});
      room.matrixRoom.setState(after);
      // What the room does when a sync changes its topic.
      room.onRoomStateUpdated((roomId: room.matrixRoom.id, state: after));
      await tester.pump();
      expect(find.text('After'), findsOneWidget);
    });
  });
}
