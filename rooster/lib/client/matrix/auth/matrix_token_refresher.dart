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
  const ReauthenticationMismatch({this.newDevice = false});

  /// The same account on a new device: an OAuth sign-in where the server did
  /// not grant the device it was asked for.
  final bool newDevice;
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

  final StreamController<matrix.MatrixError> _restrictions =
      StreamController<matrix.MatrixError>.broadcast();

  /// Account restriction errors (`M_USER_LOCKED`, `M_USER_SUSPENDED`) seen on
  /// responses from the homeserver or during token renewal.
  Stream<matrix.MatrixError> get onRestriction => _restrictions.stream;

  /// Records an account restriction error seen on a homeserver response or
  /// token renewal.
  void reportRestriction(matrix.MatrixError error) {
    if (error == matrix.MatrixError.M_USER_LOCKED ||
        error == matrix.MatrixError.M_USER_SUSPENDED) {
      _restrictions.add(error);
    }
  }

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
    return _start();
  }

  /// Tries the refresh token again after it was refused. The state stays
  /// until it works: a failure keeps asking the person to sign in again.
  Future<String?> retry() => _start();

  Future<String?> _start() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  static const Symbol _renewalZoneKey = #roosterTokenRenewal;

  /// Called by [TokenRefreshingHttpClient] for every answer: the status of
  /// the renewal's own requests tells a server failing from a refusal (the
  /// SDK throws a bare exception for an OAuth error or a proxy's page).
  static void recordStatus(int status) {
    final answer = Zone.current[_renewalZoneKey];
    if (answer is _RenewalStatus) answer.status = status;
  }

  Future<String?> _run() async {
    final client = _client();
    final answer = _RenewalStatus();
    try {
      await runZoned(() => _renew(client),
          zoneValues: {_renewalZoneKey: answer});
      _resumeSync(client);
      return client.accessToken;
    } catch (e) {
      if (e is matrix.MatrixException) {
        reportRestriction(e.error);
      }
      // The kind of error only: it may quote the request.
      final reason = e is matrix.MatrixException ? e.errcode : e.runtimeType;
      if (_isTransient(e, answer.status)) {
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

  /// A server error (5xx), a rate limit (429), an account lock/suspension
  /// (`M_USER_LOCKED`, `M_USER_SUSPENDED`) or no answer at all: the token was
  /// not refused, so the next renewal tries again.
  static bool _isTransient(Object e, int? status) =>
      (status != null && (status >= 500 || status == 429)) ||
      e is http.ClientException ||
      e is TimeoutException ||
      (e is matrix.MatrixException &&
          (e.error == matrix.MatrixError.M_LIMIT_EXCEEDED ||
              e.error == matrix.MatrixError.M_USER_LOCKED ||
              e.error == matrix.MatrixError.M_USER_SUSPENDED));

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
    await _swapTokens(
      client,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: expiresInMs != null && expiresInMs > 0
          ? DateTime.now().add(Duration(milliseconds: expiresInMs))
          : null,
      oidcClientId: null,
    );
  }

  /// Signs this same device in again with the tokens of an OAuth 2.0
  /// sign-in that asked for this device (`urn:matrix:client:device:<id>`),
  /// keeping the database and the keys. The server says whose token it is
  /// (`whoami`) before anything is stored: [ReauthenticationMismatch] when it
  /// is another account or device, and the old session stays as it was.
  Future<void> reauthenticateWithOAuth({
    required String accessToken,
    required String? refreshToken,
    required int? expiresInSeconds,
    required String oidcClientId,
  }) async {
    final client = _client();
    final userId = client.userID!;
    final deviceId = client.deviceID!;
    final owner = await matrix.MatrixApi(
      homeserver: client.homeserver,
      accessToken: accessToken,
      httpClient: client.httpClient,
    ).getTokenOwner();
    if (owner.userId != userId) throw const ReauthenticationMismatch();
    if (owner.deviceId != deviceId) {
      throw const ReauthenticationMismatch(newDevice: true);
    }

    await _swapTokens(
      client,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresInSeconds != null && expiresInSeconds > 0
          ? DateTime.now().add(Duration(seconds: expiresInSeconds))
          : null,
      oidcClientId: oidcClientId,
    );
  }

  /// Puts the new tokens on the session this device has, without a new
  /// login: the device, its Olm account and the database stay.
  Future<void> _swapTokens(
    matrix.Client client, {
    required String accessToken,
    required String? refreshToken,
    required DateTime? expiresAt,
    required String? oidcClientId,
  }) async {
    final homeserver = client.homeserver!;
    final userId = client.userID!;
    final deviceId = client.deviceID!;
    // Soft logged out, init only swaps the tokens of the session it has.
    client.onLoginStateChanged.add(matrix.LoginState.softLoggedOut);
    await client.init(
      newToken: accessToken,
      newTokenExpiresAt: expiresAt,
      newRefreshToken: refreshToken,
      newHomeserver: homeserver,
      newUserID: userId,
      newDeviceID: deviceId,
      newDeviceName: client.deviceName,
      newOidcClientId: oidcClientId,
      waitForFirstSync: false,
    );
    // init keeps the old refresh token when the answer has none, and
    // stores nothing without one.
    await client.database.updateClient(
      homeserver.toString(),
      accessToken,
      expiresAt,
      refreshToken,
      userId,
      deviceId,
      client.deviceName,
      client.prevBatch,
      client.encryption?.pickledOlmAccount,
      oidcClientId,
    );
    client.onLoginStateChanged.add(matrix.LoginState.loggedIn);
    _resumeSync(client);
  }
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

  /// Extracts an account lock (`401 M_USER_LOCKED`) or suspension
  /// (`403 M_USER_SUSPENDED`) error from a homeserver response body.
  static matrix.MatrixError? restrictionOf(int statusCode, List<int> body) {
    if (statusCode != 401 && statusCode != 403) return null;
    try {
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map) return null;
      final errcode = json['errcode'];
      if (errcode == 'M_USER_LOCKED') {
        return matrix.MatrixError.M_USER_LOCKED;
      }
      if (statusCode == 403 && errcode == 'M_USER_SUSPENDED') {
        return matrix.MatrixError.M_USER_SUSPENDED;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  http.StreamedResponse _bufferAndReport(
      http.StreamedResponse response, List<int> body) {
    final restriction = restrictionOf(response.statusCode, body);
    if (restriction != null) refresher.reportRestriction(restriction);
    return http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      contentLength: body.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authorization = request.headers['authorization'];
    final response = await _inner.send(request);
    MatrixTokenRefresher.recordStatus(response.statusCode);
    if ((response.statusCode != 401 && response.statusCode != 403) ||
        !_isHomeserver(request.url)) {
      return response;
    }

    final body = await response.stream.toBytes();
    final answer = _bufferAndReport(response, body);
    if (response.statusCode != 401 ||
        authorization == null ||
        !authorization.startsWith('Bearer ') ||
        !isSoftLogout(body)) {
      return answer;
    }

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
    final retried = await _inner.send(again);
    if (retried.statusCode == 401 || retried.statusCode == 403) {
      return _bufferAndReport(retried, await retried.stream.toBytes());
    }
    return retried;
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

/// The HTTP status of the last answer a renewal got.
class _RenewalStatus {
  int? status;
}
