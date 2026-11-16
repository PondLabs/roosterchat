// The warm-up's requests, counted by a fake server: a real HttpServer on
// 127.0.0.1 standing for both the homeserver (OpenID) and the call token
// service (/healthz, /sfu/get). Plain test(): the widgets binding would
// replace dart:io's HttpClient with one that answers 400.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/call_warm_up.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/keep_alive_client_io.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _openIdRoute = 'POST /openid/request_token';

void main() {
  late HttpServer server;
  final routes = <String>[];
  final ports = <String, List<int>>{};
  late http.Client homeserver;

  setUp(() async {
    routes.clear();
    ports.clear();
    homeserver = http.Client();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final route = '${request.method} ${request.uri.path}';
      routes.add(route);
      ports
          .putIfAbsent(route, () => [])
          .add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      final response = request.response..headers.contentType = ContentType.json;
      if (route == 'POST /sfu/get') {
        response.write(jsonEncode({
          'url': 'wss://sfu.example.org',
          'jwt': jwtUntil(DateTime.now().add(const Duration(hours: 1)),
              id: 'g${routes.length}'),
        }));
      } else if (route == _openIdRoute) {
        response.write(jsonEncode({
          'access_token': 'openid-${routes.length}',
          'expires_in': 3600,
          'matrix_server_name': 'example.org',
          'token_type': 'Bearer',
        }));
      } else {
        response.write('{"status":"ok"}');
      }
      await response.close();
    });
  });

  tearDown(() async {
    homeserver.close();
    await server.close(force: true);
  });

  int count(String route) => routes.where((r) => r == route).length;

  FakeHost host(Journal journal, {String roomId = '!room:example.org'}) =>
      FakeHost(journal, focus: 'http://127.0.0.1:${server.port}')
        ..roomId = roomId
        ..openId = () async {
          final response = await homeserver.post(Uri.parse(
              'http://127.0.0.1:${server.port}/openid/request_token'));
          return matrix.OpenIdCredentials.fromJson(
              jsonDecode(response.body) as Map<String, Object?>);
        };

  void report(String scenario) {
    // ignore: avoid_print
    print('[$scenario] server saw: OpenID ${count(_openIdRoute)}, '
        '/healthz ${count('GET /healthz')}, /sfu/get ${count('POST /sfu/get')}'
        ' (client ports: $ports)');
  }

  test(
      'open the page, then click Join: the join sends no OpenID request and '
      'no /sfu/get', () async {
    final journal = Journal();
    final tokens = CallTokenService();
    addTearDown(tokens.close);
    final channel = host(journal);

    await CallWarmUp(host: channel, tokens: tokens).run();
    report('after opening the page');
    expect(count(_openIdRoute), 1);
    expect(count('POST /sfu/get'), 1);
    expect(count('GET /healthz'), 1);

    final before = routes.length;
    await CallJoin(
            host: channel,
            tokens: tokens,
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
    report('after the join');
    expect(routes.sublist(before), isEmpty,
        reason: 'the join asked the server for nothing');
    expect(journal.entries, contains('connected'));
  });

  test('ten openings in a row: one OpenID request, one /sfu/get per room',
      () async {
    final journal = Journal();
    final tokens = CallTokenService();
    addTearDown(tokens.close);
    final rooms = [host(journal), host(journal, roomId: '!other:example.org')];
    for (var i = 0; i < 10; i++) {
      for (final room in rooms) {
        await CallWarmUp(host: room, tokens: tokens).run();
      }
    }
    report('10 openings x 2 rooms');
    expect(count(_openIdRoute), 1);
    expect(count('POST /sfu/get'), 2);
    expect(count('GET /healthz'), 1);
  });

  test('the token service connection is kept idle for 55 s', () async {
    expect(CallTokenService.idleTimeout, const Duration(seconds: 55));
    expect(keepAliveIoClient(CallTokenService.idleTimeout).idleTimeout,
        const Duration(seconds: 55));
  });

  test(
      'the idle time is what keeps the connection: past it a new one is '
      'opened, within it the same one is reused', () async {
    // The same knob, at a scale a test can wait for.
    Future<List<int>> twoRequests(Duration idle) async {
      final client = keepAliveIoClient(idle);
      final seen = <int>[];
      for (var i = 0; i < 2; i++) {
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/healthz'));
        final response = await request.close();
        await response.drain<void>();
        seen.add(ports['GET /healthz']!.last);
        if (i == 0) await Future<void>.delayed(const Duration(seconds: 2));
      }
      client.close(force: true);
      return seen;
    }

    final short = await twoRequests(const Duration(seconds: 1));
    final long = await twoRequests(const Duration(seconds: 5));
    // ignore: avoid_print
    print('[idle] 1 s idle, 2 s apart: ports $short; '
        '5 s idle, 2 s apart: ports $long');
    expect(short.toSet(), hasLength(2), reason: 'closed while idle');
    expect(long.toSet(), hasLength(1), reason: 'kept while idle');
  });
}
