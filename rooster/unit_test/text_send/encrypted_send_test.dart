@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../speed_log/fake_account.dart';
import 'text_send_fakes.dart';

/// The olm account the SDK's own tests give `@test:fakeServer.notExisting`
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`): the fake server
/// knows its keys.
const _pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// The fake homeserver: the room's members are only us, every `PUT /send`
/// is answered and kept in [sends] as its event type, and room keys sent
/// to devices (`PUT /sendToDevice`) are held while [holdKeys] is set.
class _Homeserver extends FakeTransport {
  final List<String> sends = [];
  Completer<void>? holdKeys;
  int keysHeld = 0;

  static http.StreamedResponse _json(int status, Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.pathSegments;
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      return _json(200, {
        'chunk': [
          {
            'type': 'm.room.member',
            'state_key': '@test:fakeServer.notExisting',
            'sender': '@test:fakeServer.notExisting',
            'event_id': r'$join',
            'origin_server_ts': 0,
            'content': {'membership': 'join'},
          }
        ]
      });
    }
    if (request.method == 'PUT' && path.contains('sendToDevice')) {
      final hold = holdKeys;
      if (hold != null) {
        keysHeld++;
        await hold.future;
      }
    }
    final at = path.indexOf('send');
    if (request.method == 'PUT' && at > 0 && path.length == at + 3) {
      seen.add('${request.method} ${routeTemplate(request.url)}');
      await request.finalize().drain<void>();
      sends.add(path[at + 1]);
      return _json(200, {'event_id': '\$sent${sends.length}'});
    }
    return super.send(request);
  }
}

/// [dir] as the flutter_rust_bridge loader takes it: it goes through
/// `Uri.resolve`, so `C:/x` must be `/C:/x/` (a shell may drop the slash).
String _libraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final vodozemac = Platform.environment['VODOZEMAC_LIB_DIR'];
  final skip = vodozemac == null
      ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
      : false;

  late _Homeserver server;
  late MatrixClient client;
  late MatrixRoom room;
  var accounts = 0;

  setUp(() async {
    if (vodozemac == null) return;
    if (!vod.isInitialized()) {
      await vod.init(libraryPath: _libraryDir(vodozemac));
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    TextSendTrace.nextFrameDrawn = () async => true;
    server = _Homeserver();
    final name = 'encrypted_send_${accounts++}';
    final database = await matrix.MatrixSdkDatabase.init(
      name,
      database: await databaseFactoryFfi.openDatabase(':memory:',
          options: OpenDatabaseOptions(singleInstance: false)),
      sqfliteFactory: databaseFactoryFfi,
    );
    client =
        MatrixClient(identifier: name, database: database, transport: server);
    final mx = client.getMatrixClient();
    FakeMatrixApi.client = mx;
    await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await mx.init(
      newToken: 'abcd',
      newUserID: '@test:fakeServer.notExisting',
      newHomeserver: mx.homeserver,
      newDeviceName: 'Test client',
      newDeviceID: 'GHTYAJCE',
      newOlmAccount: _pickledOlmAccount,
    );
    await mx.abortSync();
    mx.backgroundSync = false;
    expect(mx.encryptionEnabled, isTrue);
    room = await joinedRoom(client, encrypted: true);
    expect(room.matrixRoom.encrypted, isTrue);
    // The devices in the room are known, as after a sync: keys for a
    // device that appears later are still sent at the send (the SDK's
    // check), which a preparation ahead does not cover.
    await mx.updateUserDeviceKeys();
    SpeedLog.instance.requests.clear();
    SpeedLog.instance.spans.clear();
  });

  tearDown(() async {
    if (vodozemac == null) return;
    await client.close();
  });

  /// Sends [text] the way the composer does, and returns its span.
  Future<SpeedSpan> sendText(String text) async {
    final trace = TextSendTrace.forComposer(
        sendPressed: TextSendTrace.now(), message: text, hasAttachments: false);
    await TextSendTrace.send(trace, () => room.sendMessage(message: text));
    return trace!.span;
  }

  bool ready() =>
      room.matrixRoom.client.encryption!.keyManager
          .getOutboundGroupSession(room.matrixRoom.id) !=
      null;

  /// The span's key requests, by method and route template.
  List<String> keyRequests(SpeedSpan span) => [
        for (final r in SpeedLog.instance.requests.toList())
          if (r.operationId == span.id && TextSendTrace.isKeyRequest(r))
            '${r.method} ${r.route}'
      ];

  test(
      'with the session prepared ahead (first keystroke): 1 PUT /send and no '
      'key request in the send',
      skip: skip, () async {
    room.prepareToSend();
    await until(ready);
    final preparedWith = SpeedLog.instance.requests
        .toList()
        .where(TextSendTrace.isKeyRequest)
        .map((r) => '${r.method} ${r.route}')
        .toList();
    server.seen.clear();

    final span = await sendText('Hello, ready session');

    final session =
        span.steps.singleWhere((s) => s.name == SpeedStep.outboundSession);
    print('prepared ahead with: $preparedWith');
    print(buildSpeedReport(SpeedLog.instance));
    expect(server.sends, ['m.room.encrypted']);
    expect(
        server.seen.where((r) => r.startsWith('PUT ') && r.contains('/send/')),
        hasLength(1));
    expect(keyRequests(span), isEmpty);
    expect(span.steps.where((s) => s.name == SpeedStep.keyRequest), isEmpty);
    expect(session.values, {
      SpeedValue.sessionCreated: 0,
      SpeedValue.sessionWaited: 0,
      SpeedValue.keyRequests: 0
    });
    expect(span.outcome, SpeedOutcome.ok);
  });

  test(
      'with no session: the send makes it, its key requests are counted and '
      'listed, and the span says the session was created',
      skip: skip, () async {
    expect(ready(), isFalse);

    final span = await sendText('Hello, new session');

    final listed = keyRequests(span);
    final session =
        span.steps.singleWhere((s) => s.name == SpeedStep.outboundSession);
    final report = buildSpeedReport(SpeedLog.instance);
    print('key requests of the send: $listed');
    print(report);
    expect(server.sends, ['m.room.encrypted']);
    expect(listed, isNotEmpty);
    expect(span.steps.where((s) => s.name == SpeedStep.keyRequest),
        hasLength(listed.length));
    expect(session.values, {
      SpeedValue.sessionCreated: 1,
      SpeedValue.sessionWaited: 0,
      SpeedValue.keyRequests: listed.length,
    });
    expect(
        report,
        contains('session_created=1 session_waited=0 '
            'key_requests=${listed.length}'));
    // Fixed names and numbers: no room, user or device id in the report's
    // spans and requests.
    for (final id in ['!1234', '@test', 'GHTYAJCE', 'OTHERDEVICE']) {
      expect(report, isNot(contains(id)), reason: id);
    }
  });

  test(
      'Send while the preparation shares the room key: the message waits for '
      'that session, and no second session is made',
      skip: skip, () async {
    server.holdKeys = Completer<void>();
    room.prepareToSend();
    await until(() => server.keysHeld > 0);
    final send = sendText('Hello while preparing');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.sends, isEmpty, reason: 'no message before the session');

    server.holdKeys!.complete();
    final span = await send;
    print(buildSpeedReport(SpeedLog.instance));
    expect(server.sends, ['m.room.encrypted']);
    final roomKeySends = SpeedLog.instance.requests
        .toList()
        .where((r) => r.route.contains('/sendToDevice/'))
        .length;
    expect(roomKeySends, 1, reason: 'one session, its key shared once');
    expect(server.keysHeld, 1);
    // The message waited for the session the preparation was making: it
    // says so by its own name, not as a session the send made.
    expect(
        span.steps
            .singleWhere((s) => s.name == SpeedStep.outboundSession)
            .values,
        {
          SpeedValue.sessionCreated: 0,
          SpeedValue.sessionWaited: 1,
          SpeedValue.keyRequests: 0
        });
    expect(buildSpeedReport(SpeedLog.instance),
        contains('session_created=0 session_waited=1 key_requests=0'));
    expect(span.outcome, SpeedOutcome.ok);
  });
}
