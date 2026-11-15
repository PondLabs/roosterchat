// Every join made a new HTTP client for the call token service, so every
// `POST /sfu/get` opened a new TCP and TLS connection. One client per
// account now keeps it, until the account logs out.
//
// A real HttpServer on 127.0.0.1, in plain test(): the widgets binding
// would replace dart:io's HttpClient with one that answers 400.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// [http.Client] that counts [close] calls.
class _Closing extends http.BaseClient {
  _Closing(this._inner);
  final http.Client _inner;
  int closed = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed++;
    _inner.close();
  }
}

void main() {
  late HttpServer server;
  final remotePorts = <int>[];
  final routes = <String>[];

  setUp(() async {
    remotePorts.clear();
    routes.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      routes.add('${request.method} ${request.uri.path}');
      remotePorts.add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'url': 'wss://sfu.example.org', 'jwt': 'jwt'}));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<void> joinOnce(CallTokenService tokens) async {
    final journal = Journal();
    final host = FakeHost(journal, focus: 'http://127.0.0.1:${server.port}');
    await CallJoin(
            host: host,
            tokens: tokens,
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
  }

  test(
      'two joins in a row send both POST /sfu/get on one connection, and the '
      'client closes only when the account logs out', () async {
    final logins = StreamController<matrix.LoginState>.broadcast();
    final account = Object();
    final inner = _Closing(http.Client());
    CallTokenService create() =>
        CallTokenService(client: SpeedHttpClient(inner: inner));

    final first =
        CallTokenService.forAccount(account, logins.stream, create: create);
    await joinOnce(first);
    final second =
        CallTokenService.forAccount(account, logins.stream, create: create);
    await joinOnce(second);

    expect(identical(first, second), isTrue, reason: 'one per account');
    expect(routes, ['POST /sfu/get', 'POST /sfu/get']);
    expect(remotePorts.toSet(), hasLength(1),
        reason: 'the same client port both times: one TCP connection '
            '(${remotePorts.join(', ')})');
    // ignore: avoid_print
    print('sfu/get client ports seen by the server: $remotePorts');

    logins.add(matrix.LoginState.loggedIn);
    await settle();
    expect(inner.closed, 0, reason: 'only a logout closes it');
    expect(first.isClosed, isFalse);

    logins.add(matrix.LoginState.loggedOut);
    await settle();
    expect(inner.closed, 1);
    expect(first.isClosed, isTrue);
    expect(() => first.requestSfu(Uri.parse('http://127.0.0.1'), {}),
        throwsStateError);

    final afterLogin = CallTokenService.forAccount(account, logins.stream,
        create: () => CallTokenService(client: http.Client()));
    expect(identical(afterLogin, first), isFalse,
        reason: 'the next login gets a new client');
    afterLogin.close();
    await logins.close();
  });

  test('a new client per join, as before, opened a new connection each time',
      () async {
    // The baseline the test above improves on: what one client per join did.
    final clients = [CallTokenService(), CallTokenService()];
    addTearDown(() => clients.forEach((client) => client.close()));
    await joinOnce(clients[0]);
    await joinOnce(clients[1]);

    expect(remotePorts, hasLength(2));
    expect(remotePorts.toSet(), hasLength(2));
  });
}
