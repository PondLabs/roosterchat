import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import '../matrix_auth_oidc/oidc_fakes.dart';

export '../matrix_auth_oidc/oidc_fakes.dart'
    show homeserverHost, tokenEndpoint, initVodozemac, skipWithoutVodozemac;

const userId = '@alice:$homeserverHost';
const deviceId = 'DEVICE1';
const oidcClientId = 'client-1';

/// A homeserver whose tokens expire on demand: a request with a token in
/// [expired] gets `401 M_UNKNOWN_TOKEN` with `soft_logout: true`. It renews
/// on `/v3/refresh` and on the OAuth [tokenEndpoint] (`at-2`/`rt-2` unless
/// [refreshAnswer] says otherwise), each answer held until [gate] completes
/// when there is one. Sign-in, `auth_metadata` and the rest (sync, keys,
/// whoami) answer like the SDK's [FakeMatrixApi]. Every request is kept in
/// [requests].
class SoftLogoutServer extends http.BaseClient {
  final FakeMatrixApi _api = FakeMatrixApi();
  final List<http.Request> requests = [];
  final Set<String> expired = {};
  Completer<void>? gate;
  http.Response Function()? refreshAnswer;

  /// The device the server signs in, or the one the request asks for.
  String? loginDeviceId;

  Iterable<http.Request> get refreshRequests => requests.where((r) =>
      r.url.path == '/_matrix/client/v3/refresh' ||
      r.url.toString() == tokenEndpoint);

  Iterable<http.Request> get loginRequests => requests.where(
      (r) => r.url.path == '/_matrix/client/v3/login' && r.method == 'POST');

  /// The access tokens the requests to [path] carried.
  List<String?> tokensFor(String path) => requests
      .where((r) => r.url.path == path)
      .map((r) => r.headers['authorization'])
      .toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    requests.add(copy);
    final answer = await _answer(copy);
    if (answer != null) {
      return http.StreamedResponse(
          Stream.value(answer.bodyBytes), answer.statusCode,
          headers: answer.headers, request: request);
    }
    final forwarded = http.Request(
        request.method, copy.url.replace(host: 'fakeserver.notexisting'))
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    return _api.send(forwarded);
  }

  Future<http.Response?> _answer(http.Request request) async {
    final url = request.url;
    final isRefresh = url.toString() == tokenEndpoint ||
        url.path == '/_matrix/client/v3/refresh';
    if (isRefresh) {
      await gate?.future;
      return refreshAnswer?.call() ??
          json(url.toString() == tokenEndpoint
              ? {
                  'access_token': 'at-2',
                  'refresh_token': 'rt-2',
                  'token_type': 'Bearer',
                  'expires_in': 300,
                }
              : {
                  'access_token': 'at-2',
                  'refresh_token': 'rt-2',
                  'expires_in_ms': 300000,
                });
    }
    if (url.host != homeserverHost) return null;
    final authorization = request.headers['authorization'];
    if (authorization != null &&
        expired.contains(authorization.substring('Bearer '.length))) {
      return json({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Token expired',
        'soft_logout': true,
      }, status: 401);
    }
    if (request.method == 'POST' && url.path.endsWith('/filter')) {
      return json({'filter_id': 'filter-1'});
    }
    switch (url.path) {
      case '/.well-known/matrix/client':
        return http.Response('', 404);
      case '/_matrix/client/versions':
        return json({
          'versions': ['v1.11'],
        });
      case '/_matrix/client/v1/auth_metadata':
        return json(authMetadataJson());
      case '/_matrix/client/v3/login':
        if (request.method == 'GET') {
          return json({
            'flows': [
              {'type': 'm.login.password'},
              {'type': 'm.login.sso'},
              {'type': 'm.login.token'},
            ]
          });
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (body['password'] == 'wrong') {
          return json({'errcode': 'M_FORBIDDEN', 'error': 'Invalid password'},
              status: 403);
        }
        return json({
          'user_id': userId,
          'access_token': 'at-login',
          'refresh_token': 'rt-login',
          'expires_in_ms': 300000,
          'device_id': loginDeviceId ?? body['device_id'] ?? 'NEWDEVICE',
        });
    }
    return null;
  }

  static http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}

/// An account signed in on [server] as [userId] on [deviceId] with the
/// token `at-1` (expiring in five minutes) and the refresh token `rt-1`, through OAuth 2.0 when
/// [oidc]. Background sync is off: the tests sync when they want to.
Future<MatrixClient> signedIn(SoftLogoutServer server,
    {bool oidc = false, String? refreshToken = 'rt-1'}) async {
  await initVodozemac();
  final client = await newAccount(server);
  final mx = client.getMatrixClient();
  mx.backgroundSync = false;
  await mx.init(
    newToken: 'at-1',
    newTokenExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
    newRefreshToken: refreshToken,
    newHomeserver: Uri.https(homeserverHost),
    newUserID: userId,
    newDeviceID: deviceId,
    newDeviceName: 'Rooster',
    newOidcClientId: oidc ? oidcClientId : null,
    waitForFirstSync: false,
  );
  await mx.firstSyncReceived;
  return client;
}

/// What the account's database row holds now.
Future<Map<String, Object?>> storedAccount(MatrixClient client) async =>
    Map.of((await client
        .getMatrixClient()
        .database
        .getClient(client.getMatrixClient().clientName))!);
