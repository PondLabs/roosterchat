// The warm-up before the click: opening a voice channel's page (or resting
// the pointer on a join button) opens the token service's connection and
// fetches the OpenID token and the room's call token, held in memory until
// 60 s before they lapse. The join then uses what is held.
//
// Pure Dart (no dart:io), so it also runs in Chrome. The token service is a
// MockClient, the clock is the test's. The HttpServer counts are in
// call_warm_up_server_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/call_warm_up.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// A call token service: `GET /healthz` and `POST /sfu/get`, each grant a
/// JWT of its own (`g1`, `g2`...) that lapses [jwtLife] after [now].
class _TokenService {
  DateTime now = DateTime.utc(2026, 11, 16, 12);
  Duration jwtLife = const Duration(minutes: 10);
  final List<String> requests = [];
  final List<String> jwts = [];

  /// Routes that answer 500.
  final Set<String> failing = {};

  /// Routes whose next request answers 500.
  final Set<String> failingOnce = {};

  /// Holds the next `/sfu/get` until opened, when set.
  Gate? sfuGate;

  late final CallTokenService tokens =
      CallTokenService(client: MockClient(_answer), now: () => now);

  int count(String route) => requests.where((r) => r == route).length;

  Future<http.Response> _answer(http.Request request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(route);
    if (route == 'GET /healthz') {
      return http.Response('', failing.contains(route) ? 500 : 200);
    }
    final gate = sfuGate;
    sfuGate = null;
    await gate?.passed;
    if (failing.contains(route) || failingOnce.remove(route)) {
      return http.Response('{}', 500);
    }
    final jwt = jwtUntil(now.add(jwtLife), id: 'g${jwts.length + 1}');
    jwts.add(jwt);
    return http.Response(
        jsonEncode({'url': 'wss://sfu.example.org', 'jwt': jwt}), 200);
  }
}

void main() {
  late Journal journal;
  late FakeHost host;
  late _TokenService service;

  /// The OpenID token's `expires_in`.
  var openIdLife = 3600;

  /// Fails the OpenID requests while set.
  Object? openIdError;

  FakeHost newHost({String roomId = '!room:example.org'}) => FakeHost(journal)
    ..roomId = roomId
    ..openId = () async {
      if (openIdError != null) throw openIdError!;
      return matrix.OpenIdCredentials(
          accessToken: 'openid-${journal.count('openid')}',
          expiresIn: openIdLife,
          matrixServerName: 'example.org',
          tokenType: 'Bearer');
    };

  setUp(() {
    journal = Journal();
    openIdLife = 3600;
    openIdError = null;
    host = newHost();
    service = _TokenService();
  });

  Future<void> warmUp([FakeHost? other]) =>
      CallWarmUp(host: other ?? host, tokens: service.tokens).run();

  /// Joins with a new LiveKit room, and returns it.
  Future<FakeLivekitRoom> join({Set<String> refused = const {}}) async {
    final room = FakeLivekitRoom(journal)..refusedTokens.addAll(refused);
    host.room = room;
    await CallJoin(
            host: host,
            tokens: service.tokens,
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
    return room;
  }

  void report(String scenario) {
    // ignore: avoid_print
    print('[$scenario] OpenID requests: ${journal.count('openid')}, '
        'token service: ${service.requests}');
  }

  test(
      'a join after the page opened sends no OpenID request and no '
      '/sfu/get: the warm-up made both', () async {
    await warmUp();
    expect(journal.count('openid'), 1);
    expect(service.requests, ['GET /healthz', 'POST /sfu/get']);

    final room = await join();
    report('open, then join');
    expect(journal.count('openid'), 1, reason: 'the join asked for none');
    expect(service.count('POST /sfu/get'), 1, reason: 'nor a call token');
    expect(room.connectTokens, [service.jwts.single]);
    expect(journal.entries, contains('connected'));
  });

  test(
      'ten openings in a row: one OpenID request, at most one /sfu/get per '
      'room, one /healthz', () async {
    final other = newHost(roomId: '!other:example.org');
    for (var i = 0; i < 10; i++) {
      await warmUp();
      await warmUp(other);
    }
    // And ten at once: one request at a time.
    await Future.wait([for (var i = 0; i < 10; i++) warmUp(newHost())]);
    report('10 openings x 2 rooms, then 10 at once');
    expect(journal.count('openid'), 1);
    expect(service.count('POST /sfu/get'), 2);
    expect(service.count('GET /healthz'), 1);
  });

  test('the OpenID token is asked for again with less than 60 s left',
      () async {
    final start = service.now;
    await warmUp();
    expect(journal.count('openid'), 1);

    // 61 s left: still held (a new room needs it for its call token).
    service.now = start.add(Duration(seconds: openIdLife - 61));
    await warmUp(newHost(roomId: '!b:example.org'));
    expect(journal.count('openid'), 1);

    // 59 s left: asked for again.
    service.now = start.add(Duration(seconds: openIdLife - 59));
    await warmUp(newHost(roomId: '!c:example.org'));
    expect(journal.count('openid'), 2);
    report('OpenID at 61 s and 59 s left');
  });

  test(
      'a call token is asked for again with less than 60 s left, and never '
      'used lapsed', () async {
    openIdLife = 86400;
    final start = service.now;
    await warmUp();
    final first = service.jwts.single;

    service.now = start.add(service.jwtLife - const Duration(seconds: 61));
    expect((await join()).connectTokens, [first], reason: '61 s left: held');
    expect(service.count('POST /sfu/get'), 1);

    service.now = start.add(service.jwtLife - const Duration(seconds: 59));
    final fresh = await join();
    expect(service.count('POST /sfu/get'), 2, reason: '59 s left: new');
    expect(fresh.connectTokens, [service.jwts.last]);
    expect(fresh.connectTokens, isNot(contains(first)));

    service.now = start.add(const Duration(hours: 2));
    final late = await join();
    expect(service.count('POST /sfu/get'), 3);
    expect(late.connectTokens.single, service.jwts.last);
    report('call token at 61 s, 59 s and long past');
  });

  test('a call token without an exp is used once, never held', () async {
    final tokens = CallTokenService(client: MockClient((request) async {
      journal.add('sfu_get');
      return http.Response(
          jsonEncode({'url': 'wss://sfu.example.org', 'jwt': 'jwt'}), 200);
    }));
    await CallWarmUp(host: host, tokens: tokens).run();
    expect(tokens.holdsGrant(host.roomId, host.deviceId), isFalse);
  });

  test('the SFU refusing the held token: the join asks for a new one, once',
      () async {
    await warmUp();
    final held = service.jwts.single;

    final room = await join(refused: {held});
    report('held token refused');
    expect(room.connectTokens, [held, service.jwts.last]);
    expect(service.count('POST /sfu/get'), 2);
    expect(journal.count('connect_refused'), 1);
    expect(journal.entries.last, isNot('connect_refused'));
    expect(journal.entries, contains('connected'));
    expect(service.tokens.holdsGrant(host.roomId, host.deviceId), isTrue,
        reason: 'the new one is held');
  });

  test('a refusal of the new token too fails the join: one retry only',
      () async {
    await warmUp();
    // The clock stands still: the next grant is g2, with the same exp.
    final next = jwtUntil(service.now.add(service.jwtLife), id: 'g2');
    final room = FakeLivekitRoom(journal)
      ..refusedTokens.addAll({service.jwts.single, next});
    host.room = room;
    await expectLater(
        CallJoin(
                host: host,
                tokens: service.tokens,
                log: SpeedLog(),
                remoteAudioWindow: const Duration(milliseconds: 1))
            .run(),
        throwsA(isA<TokenRefused>()));
    expect(room.connectTokens, [service.jwts.first, next]);
    expect(service.count('POST /sfu/get'), 2);
    expect(room.disposed, isTrue);
  });

  test('a token fetched by the join itself and refused is not asked again',
      () async {
    final room = FakeLivekitRoom(journal);
    host.room = room;
    final run = CallJoin(
            host: host,
            tokens: service.tokens,
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
    // The first grant this service hands out.
    room.refusedTokens
        .add(jwtUntil(service.now.add(service.jwtLife), id: 'g1'));
    await expectLater(run, throwsA(isA<TokenRefused>()));
    expect(room.connectTokens, hasLength(1));
    expect(service.count('POST /sfu/get'), 1);
  });

  test('a logout drops the tokens: the next login asks again', () async {
    final logins = StreamController<matrix.LoginState>.broadcast();
    addTearDown(logins.close);
    final account = Object();
    CallTokenService create() => service.tokens;
    final tokens =
        CallTokenService.forAccount(account, logins.stream, create: create);
    await CallWarmUp(host: host, tokens: tokens).run();
    expect(tokens.holdsGrant(host.roomId, host.deviceId), isTrue);

    logins.add(matrix.LoginState.loggedOut);
    await settle();
    expect(tokens.isClosed, isTrue);
    expect(tokens.holdsGrant(host.roomId, host.deviceId), isFalse);
    expect(() => tokens.openId(host.openIdToken), throwsStateError);

    final next = _TokenService();
    final again = CallTokenService.forAccount(account, logins.stream,
        create: () => next.tokens);
    await CallWarmUp(host: host, tokens: again).run();
    expect(journal.count('openid'), 2);
    expect(next.count('POST /sfu/get'), 1);
    again.close();
  });

  test('a token that arrives after the logout is not kept', () async {
    final gate = Gate();
    host.openId = () async {
      await gate.passed;
      return FakeHost.credentials;
    };
    final warm = warmUp();
    await settle();
    service.tokens.close();
    gate.open();
    await warm;
    expect(service.tokens.holdsGrant(host.roomId, host.deviceId), isFalse);
    expect(service.count('POST /sfu/get'), 0);
  });

  test(
      'warming up opens no microphone, makes no LiveKit room, connects '
      'nothing and writes no membership', () async {
    await warmUp();
    await warmUp();
    expect(host.roomsCreated, 0);
    expect(host.room.connectTokens, isEmpty);
    expect(host.room.microphones, isEmpty);
    for (final step in [
      'connect',
      'prepare',
      'microphone_options',
      'microphone_open',
      'membership_write',
      'output_device',
    ]) {
      expect(journal.count(step), 0, reason: step);
    }
  });

  test('a failing /healthz is ignored: the tokens are still fetched', () async {
    service.failing.add('GET /healthz');
    await warmUp();
    expect(service.count('POST /sfu/get'), 1);
    await join();
    expect(service.count('POST /sfu/get'), 1);
  });

  test(
      'a /healthz that cannot connect, or that the browser blocks (CORS), '
      'is ignored', () async {
    // In a browser: this page's server under another name, another origin
    // that sends no CORS header, so fetch fails as a CORS block does. In
    // the VM: a port nothing listens on.
    const web = bool.fromEnvironment('dart.library.js_interop');
    final base = Uri.base;
    final focus = web
        ? Uri(
            scheme: base.scheme,
            host: base.host == '127.0.0.1' ? 'localhost' : '127.0.0.1',
            port: base.port)
        : Uri.parse('http://127.0.0.1:9');
    final real = http.Client();
    addTearDown(real.close);
    final healthz = <Object>[];
    final tokens = CallTokenService(
        client: _Routing(real, MockClient((request) async {
      return http.Response(
          jsonEncode({
            'url': 'wss://sfu.example.org',
            'jwt': jwtUntil(DateTime.now().add(const Duration(hours: 1)))
          }),
          200);
    }), healthz));
    final remote = FakeHost(journal,
        focus: focus.toString().replaceAll(RegExp(r'/$'), ''));
    await CallWarmUp(host: remote, tokens: tokens).run();
    // ignore: avoid_print
    print('[healthz blocked] web=$web focus=$focus outcome=$healthz');
    expect(healthz, hasLength(1));
    expect(healthz.single, isA<http.ClientException>(),
        reason: 'the request failed, and the warm-up went on');
    expect(tokens.holdsGrant(remote.roomId, remote.deviceId), isTrue);
    tokens.close();
  });

  test('a failed /sfu/get ahead is not shown and does not stop the join',
      () async {
    service.failing.add('POST /sfu/get');
    await warmUp();
    expect(service.tokens.holdsGrant(host.roomId, host.deviceId), isFalse);

    service.failing.clear();
    await join();
    expect(service.count('POST /sfu/get'), 2,
        reason: 'the join asked for its own');
  });

  test('a join sharing a request made ahead that fails sends its own',
      () async {
    final gate = Gate();
    service.sfuGate = gate;
    service.failingOnce.add('POST /sfu/get');
    final warm = warmUp();
    await settle();
    expect(service.count('POST /sfu/get'), 1);

    host.room = FakeLivekitRoom(journal);
    final joining = CallJoin(
            host: host,
            tokens: service.tokens,
            log: SpeedLog(),
            remoteAudioWindow: const Duration(milliseconds: 1))
        .run();
    await settle();
    expect(service.count('POST /sfu/get'), 1, reason: 'it shares the request');
    gate.open();
    await warm;
    await joining;
    expect(service.count('POST /sfu/get'), 2);
    expect(journal.entries, contains('connected'));
  });

  test('a failed OpenID request ahead does not stop the join', () async {
    openIdError = StateError('homeserver down');
    await warmUp();
    expect(service.count('POST /sfu/get'), 0);
    openIdError = null;
    await join();
    expect(service.count('POST /sfu/get'), 1);
  });

  test('a call token service refusing the OpenID token drops it', () async {
    service.failing.add('POST /sfu/get');
    await warmUp();
    service.failing.clear();
    await warmUp();
    expect(journal.count('openid'), 2,
        reason: 'a refused OpenID token is not used again');
  });

  test('no OpenID token for a service that is not HTTPS', () async {
    final plain = FakeHost(journal, focus: 'http://jwt.example.org');
    await CallWarmUp(host: plain, tokens: service.tokens).run();
    expect(journal.count('openid'), 0);
    expect(service.requests, isEmpty);
  });

  test('nothing for a member who may not join', () async {
    host.allowed = false;
    await warmUp();
    expect(journal.count('openid'), 0);
    expect(service.requests, isEmpty);
  });

  group('a server that never answers, on a fake clock', () {
    /// How long after the click the join fails, when the page opened
    /// [openedBefore] the click (or never), with [tokenService] and
    /// [homeserver] (the OpenID request) never answering when false.
    Duration? failsAfter(
        {Duration? openedBefore,
        bool tokenService = false,
        bool homeserver = true}) {
      Duration? waited;
      fakeAsync((async) {
        final start = DateTime.utc(2026, 11, 16, 12);
        final silent = FakeHost(Journal());
        if (!homeserver) {
          silent.openId = () => Completer<matrix.OpenIdCredentials>().future;
        }
        final tokens = CallTokenService(
            client: MockClient((request) async {
              if (!tokenService) await Completer<void>().future;
              return http.Response(
                  jsonEncode({
                    'url': 'wss://sfu.example.org',
                    'jwt': jwtUntil(start.add(const Duration(hours: 1)))
                  }),
                  200);
            }),
            now: () => start.add(async.elapsed));
        if (openedBefore != null) {
          unawaited(CallWarmUp(host: silent, tokens: tokens).run());
          async.elapse(openedBefore);
        }
        final clicked = async.elapsed;
        CallJoin(
                host: silent,
                tokens: tokens,
                log: SpeedLog(),
                remoteAudioWindow: const Duration(milliseconds: 1))
            .run()
            .then((_) {}, onError: (Object _) {
          waited = async.elapsed - clicked;
        });
        async.elapse(const Duration(minutes: 2));
      });
      return waited;
    }

    test('a silent token service fails the join 15 s after the click', () {
      expect(failsAfter(), const Duration(seconds: 15));
    });

    test(
        'a silent token service fails the join 15 s after the click when the '
        'page opened 2 s before it, not 28 s', () {
      expect(failsAfter(openedBefore: const Duration(seconds: 2)),
          const Duration(seconds: 15));
      expect(failsAfter(openedBefore: const Duration(seconds: 14)),
          const Duration(seconds: 15));
    });

    test(
        'a silent OpenID request fails the join 15 s after the click when the '
        'page opened 2 s before it', () {
      expect(
          failsAfter(
              openedBefore: const Duration(seconds: 2),
              tokenService: true,
              homeserver: false),
          const Duration(seconds: 15));
    });
  });
}

/// Sends `GET /healthz` through [healthz] and the rest through [rest],
/// writing how each `/healthz` ended to [outcomes].
class _Routing extends http.BaseClient {
  _Routing(this.healthz, this.rest, this.outcomes);

  final http.Client healthz;
  final http.Client rest;
  final List<Object> outcomes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/healthz')) return rest.send(request);
    try {
      final response = await healthz.send(request);
      outcomes.add(response.statusCode);
      return response;
    } catch (e) {
      outcomes.add(e);
      rethrow;
    }
  }
}
