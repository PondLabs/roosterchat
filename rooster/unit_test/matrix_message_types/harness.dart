import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../pending_media/matrix_fakes.dart';
import '../speed_log/fake_account.dart';

const alice = '@alice:fakeServer.notExisting';

/// A logged-in account on the SDK's in-process fake homeserver (no
/// network), whose sent events are kept, and a joined room where [alice]
/// is a member called "Alice".
Future<(MatrixClient, MatrixRoom, MediaTransport)> messageTypesRoom(
    String name) async {
  final transport = MediaTransport();
  final client = await fakeAccount(name, transport);
  client.getMatrixClient().backgroundSync = false;
  final room = await plainRoom(client);
  room.matrixRoom.setState(matrix.Event(
    type: matrix.EventTypes.RoomMember,
    stateKey: alice,
    senderId: alice,
    eventId: r'$alice_join',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
    content: {'membership': 'join', 'displayname': 'Alice'},
    room: room.matrixRoom,
  ));
  return (client, room, transport);
}

var _eventCount = 0;

/// An `m.room.message` from [alice] in [room], as the timeline gets it.
matrix.Event messageEvent(MatrixRoom room, Map<String, Object?> content) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      eventId: '\$message_${_eventCount++}',
      senderId: alice,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: content,
      room: room.matrixRoom,
    );

/// Converts like the timeline does.
MatrixTimelineEventMessage convertMessage(
        MatrixRoom room, Map<String, Object?> content) =>
    room.convertEvent(messageEvent(room, content))
        as MatrixTimelineEventMessage;

/// Loads [locale]'s translations and makes it the app's language until the
/// test ends.
Future<void> useLocale(String locale) async {
  await initializeMessages(locale);
  intl.Intl.defaultLocale = locale;
  addTearDown(() => intl.Intl.defaultLocale = null);
}

Widget host(Widget child) => MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Draws [content] as a message of [room]'s timeline.
Future<void> pumpMessage(
    WidgetTester tester, MatrixRoom room, Map<String, Object?> content) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(TimelineEventViewMessage(
      initialEvent: convertMessage(room, content),
      initialIndex: 0,
      room: room)));
  await tester.pump();
  // The sender's name colour, asked of the fake server once.
  await tester.pump(const Duration(milliseconds: 50));
}

/// Counts the HTTP clients made while it is in place: none means nothing
/// was fetched from any server.
class CountingHttpOverrides extends HttpOverrides {
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    return super.createHttpClient(context);
  }
}
