import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../matrix_phase0/test_helpers.dart';

const self = '@me:example.org';

/// A request the fake homeserver received.
class Seen {
  Seen(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final Map<String, Object?>? body;

  String get path => Uri.decodeComponent(url.path);

  @override
  String toString() => '$method $path ${url.query} $body';
}

/// A homeserver on a [MockClient]: answers the endpoints these tests use and
/// keeps every request in [seen]. Nothing leaves the process.
class FakeHomeserver {
  FakeHomeserver({Map<String, Object?>? capabilities})
      : capabilities = capabilities ?? {};

  Map<String, Object?> capabilities;
  final List<Seen> seen = [];

  Iterable<Seen> where(String method, String pathPart) =>
      seen.where((s) => s.method == method && s.path.contains(pathPart));

  late final http.Client transport = MockClient((request) async {
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, Object?>;
    final seenRequest = Seen(request.method, request.url, body);
    seen.add(seenRequest);
    final path = seenRequest.path;

    Object? answer = <String, Object?>{};
    if (path.endsWith('/v3/capabilities')) {
      answer = {'capabilities': capabilities};
    } else if (path.contains('/v3/join/')) {
      answer = {'room_id': path.split('/v3/join/').last};
    } else if (path.contains('/v3/knock/')) {
      answer = {'room_id': path.split('/v3/knock/').last};
    } else if (path.endsWith('/upgrade')) {
      answer = {'replacement_room': '!upgraded:example.org'};
    } else if (path.contains('/state/')) {
      answer = {'event_id': r'$state'};
    }
    return http.Response(jsonEncode(answer), 200,
        headers: {'content-type': 'application/json'});
  });
}

/// [MemoryCacheDatabase] that also takes the forget a room's `forget()`
/// writes before calling the homeserver.
class ForgettingDatabase extends MemoryCacheDatabase {
  final List<String> forgotten = [];

  @override
  Future<void> forgetRoom(String roomId) async => forgotten.add(roomId);
}

class LifecycleTestClient extends matrix.Client {
  factory LifecycleTestClient(FakeHomeserver server) =>
      LifecycleTestClient._(server, ForgettingDatabase());

  LifecycleTestClient._(this.server, this.forgetting)
      : super('lifecycle_test',
            httpClient: server.transport, database: forgetting) {
    homeserver = Uri.parse('http://127.0.0.1:9');
    accessToken = 'test-token';
  }

  final FakeHomeserver server;
  final ForgettingDatabase forgetting;

  @override
  String? get userID => self;
}

/// A state event for [buildRoom].
typedef StateSpec = ({
  String type,
  String stateKey,
  String sender,
  Map<String, Object?> content
});

StateSpec state(String type, Map<String, Object?> content,
        {String stateKey = '', String sender = '@admin:example.org'}) =>
    (type: type, stateKey: stateKey, sender: sender, content: content);

/// Power levels where we hold [ownLevel] and everything else is the spec's
/// usual defaults (state 50, invite 0, kick 50).
StateSpec powerLevels(
        {int ownLevel = 100, Map<String, Object?> extra = const {}}) =>
    state(matrix.EventTypes.RoomPowerLevels, {
      'users': {self: ownLevel, '@admin:example.org': 100},
      'users_default': 0,
      'state_default': 50,
      'events_default': 0,
      'invite': 0,
      'kick': 50,
      ...extra,
    });

matrix.Room buildRoom(
  matrix.Client client, {
  String id = '!room:example.org',
  matrix.Membership membership = matrix.Membership.join,
  String roomVersion = '11',
  List<StateSpec> states = const [],
}) {
  final room = matrix.Room(id: id, client: client, membership: membership);
  var ts = 100;
  for (final s in [
    state(matrix.EventTypes.RoomCreate, {'room_version': roomVersion}),
    ...states,
  ]) {
    room.setState(matrix.Event(
      type: s.type,
      stateKey: s.stateKey,
      eventId: '\$${s.type}_${s.stateKey}_$ts',
      senderId: s.sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts++),
      content: s.content,
      room: room,
    ));
  }
  return room;
}

Future<void> preparePreferences() async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
}

Widget host(Widget child) => MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Types [text] into the open text prompt and presses its button labelled
/// [submit].
Future<void> answerPrompt(WidgetTester tester, String text,
    {required String submit}) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.text(submit).last);
  await settle(tester);
}

/// Lets the fake homeserver's answers arrive (real async) and the frames
/// they cause be drawn; [WidgetTester.pumpAndSettle] would wait forever on
/// a button's spinner.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
