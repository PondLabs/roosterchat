import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../matrix_phase0/test_helpers.dart';
import '../speed_log/fake_account.dart';

const self = '@me:example.org';

/// A request a fake homeserver received.
class Seen {
  Seen(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final Object? body;

  String get path => Uri.decodeComponent(url.path);

  @override
  String toString() => '$method $path ${url.query} $body';
}

/// Answers one request, or null to leave it to the default answer.
typedef FakeRoute = http.Response? Function(Seen request);

http.Response json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

http.Response matrixError(String errcode, {int status = 403}) =>
    json({'errcode': errcode, 'error': errcode}, status: status);

/// The requests seen and the routes that answer them, shared by both
/// transports below. Nothing leaves the process.
class Script {
  final List<Seen> seen = [];
  final List<FakeRoute> routes = [];

  Iterable<Seen> where(String method, String pathPart) =>
      seen.where((s) => s.method == method && s.path.contains(pathPart));

  Future<http.Response?> answer(http.BaseRequest request) async {
    final raw = request is http.Request
        ? request.body
        : await request.finalize().bytesToString();
    Object? body;
    if (raw.isNotEmpty) {
      try {
        body = jsonDecode(raw);
      } on FormatException {
        body = raw;
      }
    }
    final seenRequest = Seen(request.method, request.url, body);
    seen.add(seenRequest);
    for (final route in routes) {
      final response = route(seenRequest);
      if (response != null) return response;
    }
    return null;
  }

  /// A bare homeserver for an SDK client: routes first, then `{}`.
  late final http.Client transport = MockClient((request) async =>
      await answer(request) ??
      json(<String, Object?>{}, status: request.method == 'GET' ? 404 : 200));
}

/// The SDK's fake homeserver under a Rooster account, with [script]'s
/// routes in front of it.
class ScriptedAccountTransport extends FakeTransport {
  ScriptedAccountTransport(this.script);
  final Script script;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    // The account's own HTTP stack may hand on a streamed request.
    copy.bodyBytes = request is http.Request
        ? request.bodyBytes
        : await request.finalize().toBytes();
    final answer = await script.answer(copy);
    if (answer == null) return super.send(copy);
    return http.StreamedResponse(
        Stream.value(answer.bodyBytes), answer.statusCode,
        headers: answer.headers, request: request);
  }
}

/// An SDK client logged in as [self] on [script], with an in-memory store.
class DirectoryTestClient extends matrix.Client {
  DirectoryTestClient(this.script)
      : super('room_directory_test',
            httpClient: script.transport, database: MemoryCacheDatabase()) {
    homeserver = Uri.parse('http://127.0.0.1:9');
    accessToken = 'test-token';
  }

  final Script script;

  @override
  String? get userID => self;
}

matrix.Room joinedRoom(matrix.Client client,
    {String id = '!room:example.org', int ownLevel = 100}) {
  final room =
      matrix.Room(id: id, client: client, membership: matrix.Membership.join);
  var ts = 1;
  for (final (type, content) in [
    (matrix.EventTypes.RoomCreate, <String, Object?>{'room_version': '11'}),
    (
      matrix.EventTypes.RoomPowerLevels,
      <String, Object?>{
        'users': {self: ownLevel},
        'users_default': 0,
        'state_default': 50,
      }
    ),
  ]) {
    room.setState(matrix.Event(
      type: type,
      stateKey: '',
      eventId: '\$${type}_$ts',
      senderId: self,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts++),
      content: content,
      room: room,
    ));
  }
  client.rooms.add(room);
  return room;
}

Future<void> prepareTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Event');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
  sqfliteFfiInit();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
}

Widget host(Widget child, {bool scroll = true}) => MaterialApp(
      theme: ThemeDark.theme,
      home:
          Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
    );

/// Lets the fake homeserver's answers arrive (real async) and the frames
/// they cause be drawn.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
