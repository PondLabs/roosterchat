import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../speed_log/fake_account.dart';

const alice = '@alice:fakeServer.notExisting';

/// A logged-in account on the SDK's in-process fake homeserver (no network)
/// and a joined room where [alice] is a member called "Alice".
Future<(MatrixClient, MatrixRoom)> stateEventsRoom(String name) async {
  final client = await fakeAccount(name, FakeTransport());
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
  return (client, room);
}

var _eventCount = 0;

/// A state event from [alice] in [room], as the timeline gets it.
matrix.Event stateEvent(
  MatrixRoom room,
  String type,
  Map<String, Object?> content, {
  Map<String, Object?>? prevContent,
  Map<String, Object?>? unsigned,
}) =>
    matrix.Event(
      type: type,
      stateKey: '',
      eventId: '\$state_${_eventCount++}',
      senderId: alice,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: content,
      prevContent: prevContent,
      unsigned: unsigned,
      room: room.matrixRoom,
    );

/// Converts like the timeline does.
TimelineEvent convert(
        MatrixRoom room, String type, Map<String, Object?> content,
        {Map<String, Object?>? prevContent}) =>
    room.convertEvent(
        stateEvent(room, type, content, prevContent: prevContent));

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
