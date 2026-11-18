// A private conversation drawn by the real timeline view, changed the way
// the Matrix SDK changes it: a message in at an index, a message replaced
// in place (a local echo the server took, a message decrypted late), a
// message out (a send cancelled). The view hears each change through the
// same `MatrixTimeline` callbacks as in the app; no request leaves.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart' as matrix;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart' as matrix;
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:rooster/generated/l10n.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:rooster/ui/pages/developer/benchmarks/benchmark_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// The reader, as in the owner's screenshot.
const me = '@ggflores23:example.com';

/// The other person in the conversation.
const them = '@apbianco:example.com';

/// Whoever wrote the older messages that fill the view above.
const filler = '@carol:example.com';

const names = {me: 'ggflores23', them: 'apbianco', filler: 'Carol'};

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

/// The app's fonts, for [Dm.picture], when a picture is asked for.
Future<void> useAppFonts() async {
  if (Platform.environment['T83_EVIDENCE_DIR'] == null) return;
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }

  final flutter = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/flutter';
  await load('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
  await load('NunitoSans',
      ['assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf']);
  await load('MaterialIcons', [
    '$flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
  ]);
}

Future<void> setUpDmHarness() async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await T.load(const Locale('en'));
  await initializeDateFormatting('en');
  await preferences.layoutOverride.set('desktop');
}

/// One message of the conversation, newest first in [Dm.timeline].
class Line {
  const Line(this.sender, this.body);
  final String sender;
  final String body;
}

class Dm {
  late MatrixClient client;
  late MatrixRoom room;
  late MatrixTimeline timeline;

  /// Who wrote each message body, to check the name drawn over it.
  final senders = <String, String>{};

  /// A fixed noon long past: no date line between the conversation's
  /// messages, whatever the hour the test runs, and no clock timer left on
  /// a pending one.
  static final start = DateTime(2026, 1, 15, 12);
  int _seconds = 0;
  int _ids = 0;

  matrix.Room get mx => room.matrixRoom;
  matrix.Timeline get sdk => timeline.matrixTimeline!;

  /// The conversation with [history], oldest first, below a screenful and
  /// more of older messages (so the view never asks for history).
  static Future<Dm> open(WidgetTester tester, List<Line> history) async {
    final dm = Dm();
    // The call components listen to WebRTC's events, absent here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await tester.runAsync(() async {
      dm.client = MatrixClient(identifier: 'sender', database: _Database());
    });
    dm.client.mockComponents();
    dm.client.self = MatrixProfile(
        dm.client, matrix.Profile(userId: me, displayName: names[me]));
    dm.client.matrixClient.setUserId(me);
    UserIdleWatcher.instance.dispose();
    dm.room = dm.client.createRoomWithData();
    for (final user in names.keys) {
      dm.mx.setState(matrix.Event.fromJson({
        'event_id': '\$member-${user.hashCode}',
        'type': 'm.room.member',
        'state_key': user,
        'sender': user,
        'origin_server_ts': start.millisecondsSinceEpoch,
        'content': {'displayname': names[user], 'membership': 'join'},
      }, dm.mx));
    }

    final older = [
      for (var i = 0; i < 80; i++)
        dm.message(filler, 'older message number $i',
            at: start.subtract(Duration(hours: 80 - i))),
    ];
    final recent = [for (final line in history) dm.say(line)];
    final chunk =
        matrix.TimelineChunk(events: [...recent.reversed, ...older.reversed]);
    dm.timeline = MatrixTimeline(dm.client, dm.room, dm.mx,
        initialTimeline: matrix.Timeline(chunk: chunk, room: dm.mx));
    return dm;
  }

  matrix.Event message(String sender, String body,
      {String? id,
      DateTime? at,
      matrix.EventStatus status = matrix.EventStatus.synced,
      String? transactionId}) {
    senders[body] = sender;
    return matrix.Event.fromJson({
      'event_id': id ?? '\$m${_ids++}',
      'type': 'm.room.message',
      'content': {'body': body, 'msgtype': 'm.text'},
      'sender': sender,
      'room_id': mx.id,
      'origin_server_ts': (at ?? start).millisecondsSinceEpoch,
      'status': status.intValue,
      if (transactionId != null) 'unsigned': {'transaction_id': transactionId},
    }, mx);
  }

  /// [line], a second after the message before it.
  matrix.Event say(Line line, {String? id}) => message(line.sender, line.body,
      id: id, at: start.add(Duration(seconds: _seconds++)));

  /// A message from someone else that a sync brings, in at the bottom.
  void receive(Line line) => insert(0, say(line));

  /// [event] in at [index], as the SDK's `onInsert` has it.
  void insert(int index, matrix.Event event) {
    sdk.events.insert(index, event);
    timeline.onEventInserted(index);
  }

  /// The event at [index] replaced by [event], as the SDK's `onChange`.
  void replace(int index, matrix.Event event) {
    sdk.events[index] = event;
    timeline.onEventChanged(index);
  }

  /// The event at [index] out of the timeline, as the SDK's `onRemove`
  /// for a send cancelled.
  void remove(int index) {
    sdk.events.removeAt(index);
    timeline.onEventRemoved(index);
  }

  /// Our own message, sent from this device: its local echo, in at the
  /// bottom while it is sent. Returns its transaction id.
  String send(Line line) {
    final txn = 'txn${_ids++}';
    insert(
        0,
        message(line.sender, line.body,
            id: txn,
            at: start.add(Duration(seconds: _seconds++)),
            status: matrix.EventStatus.sending,
            transactionId: txn));
    return txn;
  }

  /// Our message [txn] taken by the server: its echo replaced in place by
  /// the event, under the event's id.
  void confirm(String txn) {
    final index = sdk.events.indexWhere((e) => e.eventId == txn);
    final echo = sdk.events[index];
    replace(
        index,
        message(echo.senderId, echo.body,
            id: '\$sent-$txn',
            at: echo.originServerTs,
            status: matrix.EventStatus.sent,
            transactionId: txn));
  }

  int indexOf(String body) => sdk.events.indexWhere((e) => e.body == body);

  /// The messages that came in encrypted, by id, as they read once their
  /// room key arrives.
  final _sealed = <String, matrix.Event>{};

  /// [line] from someone else in at the bottom, encrypted with a room key
  /// this device does not have yet: "Failed to decrypt event" until
  /// [decrypt]. Returns its id.
  String receiveSealed(Line line) {
    final plain = say(line);
    _sealed[plain.eventId] = plain;
    insert(
        0,
        matrix.Event.fromJson({
          'event_id': plain.eventId,
          'type': 'm.room.encrypted',
          'content': {
            'algorithm': 'm.megolm.v1.aes-sha2',
            'ciphertext': 'sealed',
            'session_id': 'late-session',
            'sender_key': 'their-key',
            'device_id': 'THEIRPHONE',
          },
          'sender': line.sender,
          'room_id': mx.id,
          'origin_server_ts': plain.originServerTs.millisecondsSinceEpoch,
        }, mx));
    return plain.eventId;
  }

  /// The room key of [id] arrived: the message is decrypted in place.
  void decrypt(String id) => replace(
      sdk.events.indexWhere((e) => e.eventId == id), _sealed.remove(id)!);

  /// The message [body] redacted (deleted) by its sender, in place.
  void redact(String body) {
    final index = indexOf(body);
    final json = sdk.events[index].toJson();
    json['content'] = <String, Object?>{};
    json['unsigned'] = {
      'redacted_because': {
        'event_id': '\$redaction${_ids++}',
        'type': 'm.room.redaction',
        'sender': json['sender'],
        'redacts': json['event_id'],
        'content': <String, Object?>{},
        'origin_server_ts': start.millisecondsSinceEpoch,
      },
    };
    replace(index, matrix.Event.fromJson(json, mx));
  }

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: _picture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeDark.theme,
        home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
      ),
    ));
    await settle(tester);
  }

  final _picture = GlobalKey();

  /// Writes the view as drawn now, as `<name>.png`, to the folder in
  /// `T83_EVIDENCE_DIR`; nothing without it. [useAppFonts] first, for a
  /// picture with the app's letters rather than the test font's boxes.
  Future<void> picture(WidgetTester tester, String name) async {
    final dir = Platform.environment['T83_EVIDENCE_DIR'];
    if (dir == null) return;
    final png = await tester.runAsync(() async {
      final boundary =
          _picture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final file = File('$dir/$name.png')..writeAsBytesSync(png!);
    // ignore: avoid_print
    print('wrote ${file.path} (${png.length} bytes)');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await timeline.close();
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void lifecycle(AppLifecycleState state) {
  // ignore: invalid_use_of_protected_member
  WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
}

/// The drawn message whose text is exactly [body].
TimelineEventLayoutMessage layoutOf(WidgetTester tester, String body) {
  final text = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == body,
      description: 'the message "$body"');
  expect(text, findsWidgets, reason: '"$body" is drawn');
  return tester.widget<TimelineEventLayoutMessage>(find
      .ancestor(
          of: text.first, matching: find.byType(TimelineEventLayoutMessage))
      .first);
}

/// Each of [expected]'s messages, by body, has its sender's name and
/// avatar over it (true) or sits under the one before it, by the same
/// person, with neither (false). Every message drawn carries its own
/// sender's name, never a neighbour's, header shown or not.
void expectHeaders(WidgetTester tester, Dm dm, Map<String, bool> expected) {
  final wrong = <String>[];
  expected.forEach((body, header) {
    final layout = layoutOf(tester, body);
    if (layout.showSender != header) {
      wrong.add('"$body": ${header ? 'no' : 'a'} header');
    }
  });
  expect(wrong, isEmpty, reason: 'messages with the wrong header');
  expectOwnNames(tester, dm);
}

/// Every message drawn names and pictures the person who sent it.
void expectOwnNames(WidgetTester tester, Dm dm) {
  final borrowed = <String>[];
  for (final element
      in find.byType(TimelineEventLayoutMessage).evaluate().toList()) {
    final layout = element.widget as TimelineEventLayoutMessage;
    final bodies = find
        .descendant(of: find.byWidget(layout), matching: find.byType(RichText))
        .evaluate()
        .map((e) => (e.widget as RichText).text.toPlainText())
        .where(dm.senders.containsKey)
        .toSet();
    for (final body in bodies) {
      final name = names[dm.senders[body]];
      if (layout.senderName != name) {
        borrowed.add('"$body" is drawn as ${layout.senderName}\'s, '
            'sent by $name');
      }
      if (layout.showSender &&
          find
              .descendant(of: find.byWidget(layout), matching: find.text(name!))
              .evaluate()
              .isEmpty) {
        borrowed.add('"$body" has a header without $name');
      }
    }
  }
  expect(borrowed, isEmpty);
}
