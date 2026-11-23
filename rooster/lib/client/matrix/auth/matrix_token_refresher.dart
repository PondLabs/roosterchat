import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';

/// Whether the account's access token can still be renewed on its own.
enum TokenRefreshState {
  /// Signed in; an expired token is renewed with the refresh token.
  active,

  /// The refresh token was refused (or there is none): the person has to
  /// sign this same device in again. Sync is stopped, nothing is deleted.
  needsReauthentication,
}

/// The server signed in another account or device than this one, so its
/// token was not used.
class ReauthenticationMismatch implements Exception {
  const ReauthenticationMismatch();
}

/// Renews an account's access token after a soft logout (`401
/// M_UNKNOWN_TOKEN` with `soft_logout: true`) or before it expires, with the
/// SDK's [matrix.Client.refreshAccessToken]: `/v3/refresh`, or the OAuth 2.0
/// `token_endpoint` (`grant_type=refresh_token`) for a session signed in
/// through OAuth. The device, its Olm account and the database stay.
///
/// Every caller waiting at the same time shares one request. A refused
/// renewal moves to [TokenRefreshState.needsReauthentication], where
/// [refresh] makes no request until [retry] or [reauthenticate].
class MatrixTokenRefresher {
  MatrixTokenRefresher(
    this._client, {
    @visibleForTesting Future<void> Function(matrix.Client client)? renew,
  }) : _renew = renew ?? ((client) => client.refreshAccessToken());

  final matrix.Client Function() _client;
  final Future<void> Function(matrix.Client client) _renew;

  final ValueNotifier<TokenRefreshState> state =
      ValueNotifier(TokenRefreshState.active);

  Future<String?>? _inFlight;
  bool _stoppedSync = false;

  /// The SDK's `onSoftLogout`. It never throws: the SDK logs out, and
  /// deletes the database with the keys, when it does.
  Future<void> onSoftLogout(matrix.Client client) async {
    await refresh();
  }

  /// The renewed access token, or null when it was not renewed. A request
  /// sent with [staleToken] gets the current token without a new renewal
  /// when it was already renewed since.
  Future<String?> refresh({String? staleToken}) {
    final current = _client().accessToken;
    if (staleToken != null && current != null && current != staleToken) {
      return Future.value(current);
    }
    if (state.value == TokenRefreshState.needsReauthentication) {
      return Future.value(null);
    }
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  /// Tries the refresh token again after it was refused.
  Future<String?> retry() {
    state.value = TokenRefreshState.active;
    return refresh();
  }

  Future<String?> _run() async {
    final client = _client();
    try {
      await _renew(client);
      _resumeSync(client);
      return client.accessToken;
    } catch (e) {
      // The kind of error only: it may quote the request.
      final reason = e is matrix.MatrixException ? e.errcode : e.runtimeType;
      if (_isTransient(e)) {
        Log.w("Access token not renewed, will try again: $reason");
        return null;
      }
      Log.w("Access token renewal refused: $reason");
      _stoppedSync = true;
      client.backgroundSync = false;
      state.value = TokenRefreshState.needsReauthentication;
      return null;
    }
  }

  static bool _isTransient(Object e) =>
      e is http.ClientException ||
      e is TimeoutException ||
      (e is matrix.MatrixException &&
          e.error == matrix.MatrixError.M_LIMIT_EXCEEDED);

  void _resumeSync(matrix.Client client) {
    state.value = TokenRefreshState.active;
    if (_stoppedSync) {
      _stoppedSync = false;
      client.backgroundSync = true;
    }
  }

  /// Signs this same device in again with the account's [password] or a
  /// single sign-on [loginToken], keeping the database and the keys. Throws
  /// the server's [matrix.MatrixException] (a wrong password), or
  /// [ReauthenticationMismatch] when the server answers for another account
  /// or device.
  Future<void> reauthenticate({String? password, String? loginToken}) async {
    final client = _client();
    final homeserver = client.homeserver!;
    final userId = client.userID!;
    final deviceId = client.deviceID!;
    // Without the old token, which the server no longer takes.
    final api =
        matrix.MatrixApi(homeserver: homeserver, httpClient: client.httpClient);
    final response = await api.login(
      password != null
          ? matrix.LoginType.mLoginPassword
          : matrix.LoginType.mLoginToken,
      identifier: password != null
          ? matrix.AuthenticationUserIdentifier(user: userId)
          : null,
      password: password,
      token: loginToken,
      deviceId: deviceId,
      refreshToken: true,
    );
    if (response.userId != userId || response.deviceId != deviceId) {
      throw const ReauthenticationMismatch();
    }

    final expiresInMs = response.expiresInMs;
    final expiresAt = expiresInMs != null && expiresInMs > 0
        ? DateTime.now().add(Duration(milliseconds: expiresInMs))
        : null;
    // Soft logged out, init only swaps the tokens of the session it has.
    client.onLoginStateChanged.add(matrix.LoginState.softLoggedOut);
    await client.init(
      newToken: response.accessToken,
      newTokenExpiresAt: expiresAt,
      newRefreshToken: response.refreshToken,
      newHomeserver: homeserver,
      newUserID: userId,
      newDeviceID: deviceId,
      newDeviceName: client.deviceName,
      waitForFirstSync: false,
    );
    // init keeps the old refresh token when the answer has none, and
    // stores nothing without one.
    await client.database.updateClient(
      homeserver.toString(),
      response.accessToken,
      expiresAt,
      response.refreshToken,
      userId,
      deviceId,
      client.deviceName,
      client.prevBatch,
      client.encryption?.pickledOlmAccount,
      null,
    );
    client.onLoginStateChanged.add(matrix.LoginState.loggedIn);
    _resumeSync(client);
  }

  void dispose() => state.dispose();
}

/// Sends every request of the account and, when the homeserver answers one
/// sent with the account's token with a soft logout, waits for the shared
/// [MatrixTokenRefresher.refresh] and sends it once more with the new token.
/// A request whose body is a stream (not kept in memory) is not sent again;
/// the renewal still starts for the next one.
class TokenRefreshingHttpClient extends http.BaseClient {
  TokenRefreshingHttpClient({
    required http.Client inner,
    required this.refresher,
    required Uri? Function() homeserver,
  })  : _inner = inner,
        _homeserver = homeserver;

  final http.Client _inner;
  final MatrixTokenRefresher refresher;
  final Uri? Function() _homeserver;

  static bool isSoftLogout(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      return json is Map &&
          json['errcode'] == 'M_UNKNOWN_TOKEN' &&
          json['soft_logout'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authorization = request.headers['authorization'];
    final response = await _inner.send(request);
    if (response.statusCode != 401 ||
        authorization == null ||
        !authorization.startsWith('Bearer ') ||
        !_isHomeserver(request.url)) {
      return response;
    }

    final body = await response.stream.toBytes();
    final answer = http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      contentLength: body.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
    if (!isSoftLogout(body)) return answer;

    final staleToken = authorization.substring('Bearer '.length);
    if (request is! http.Request) {
      unawaited(refresher.refresh(staleToken: staleToken));
      return answer;
    }
    final token = await refresher.refresh(staleToken: staleToken);
    if (token == null || token == staleToken) return answer;

    final again = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..headers['authorization'] = 'Bearer $token'
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = request.bodyBytes;
    return _inner.send(again);
  }

  bool _isHomeserver(Uri url) {
    final homeserver = _homeserver();
    return homeserver != null &&
        url.scheme == homeserver.scheme &&
        url.host == homeserver.host &&
        url.port == homeserver.port;
  }

  @override
  void close() => _inner.close();
}
