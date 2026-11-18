import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/utils/network/keep_alive_client.dart';
import 'package:rooster/utils/network/speed_http_client.dart';

/// What the call token service hands out for one call: the SFU's address
/// and the JWT that lets us into the call's LiveKit room.
class SfuGrant {
  const SfuGrant({required this.url, required this.jwt});

  final String url;
  final String jwt;

  /// When [jwt] lapses, from its own `exp` claim; null when it has none
  /// that can be read, and then it is never held for a later join.
  DateTime? get expires => jwtExpiry(jwt);

  /// The `exp` claim of [jwt], or null.
  static DateTime? jwtExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(),
          isUtc: true);
    } catch (_) {
      return null;
    }
  }
}

/// A grant, and whether it was fetched by someone else than the join that
/// uses it: held from earlier, or asked for ahead of the click. A held one
/// the SFU refuses is asked for again, once.
typedef HeldGrant = ({SfuGrant grant, bool held});

/// The call token service (MatrixRTC's `POST <focus>/sfu/get`, served by
/// lk-jwt-service), through one long-lived HTTP client per account, and the
/// tokens a join needs, fetched ahead of the click and held in memory.
///
/// A new client per join opened a new TCP and TLS connection every time;
/// this one keeps its connection, idle up to 55 s (`dart:io` keeps 15 s), so
/// a join after the first or after the warm-up reuses it. It sends through
/// [SpeedHttpClient], so each request is in the speed log as
/// `token_service`, and the SFU the answer names is registered as `sfu`.
///
/// Held, in memory only and never written anywhere, until 60 s before they
/// lapse ([margin]), by the clock [now]:
///
/// - the account's OpenID token ([openId]), until its `expires_in`; one
///   serves every channel, and one request at a time asks for it;
/// - each room's call token ([sfuGrant]), until its JWT's `exp`; one
///   request at a time per room.
///
/// [forClient] gives an account its service and closes it when the account
/// logs out, which drops every token it held.
class CallTokenService {
  CallTokenService({http.Client? client, DateTime Function()? now})
      : _client =
            client ?? SpeedHttpClient(inner: keepAliveHttpClient(idleTimeout)),
        _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  bool _closed = false;

  /// Bounded: the Join button is disabled while this runs, so a request
  /// that never answers left no way to try again.
  static const timeout = Duration(seconds: 15);

  /// How long the connection to the service is kept while idle.
  static const idleTimeout = Duration(seconds: 55);

  /// A token is used until this long before it lapses.
  static const margin = Duration(seconds: 60);

  /// `GET /healthz` is not sent again this soon after the last one to a
  /// service: its connection is still open.
  static const warmAgain = Duration(seconds: 50);

  bool get isClosed => _closed;

  /// Asks the service at [focus] for a place in the call, with [body] (our
  /// device, the room and an OpenID token, see `CallJoin`), waiting
  /// [within] at most.
  Future<SfuGrant> requestSfu(Uri focus, Map<String, Object?> body,
      {Duration within = timeout}) async {
    if (_closed) throw StateError("The call token service was closed");
    _checkLeft(within);
    HostClassifier.register(focus, HostClass.tokenService);
    final uri = Uri.parse("$focus/sfu/get");
    final result =
        await _client.post(uri, body: jsonEncode(body)).timeout(within);
    if (result.statusCode != 200) {
      throw CallJoinException(
          "Failed to get sfu! HTTP Error ${result.statusCode}",
          MatrixLivekitBackend.errorCallSfuHttp(result.statusCode));
    }
    final data = jsonDecode(result.body) as Map<String, dynamic>;
    final grant =
        SfuGrant(url: data["url"] as String, jwt: data["jwt"] as String);
    HostClassifier.register(Uri.parse(grant.url), HostClass.sfu);
    return grant;
  }

  final Map<String, DateTime> _warmed = {};

  /// Opens the connection to the service at [focus] with a `GET /healthz`,
  /// unless one was sent in the last [warmAgain]. Any answer will do, and
  /// an error (in a browser, the service not allowing this origin) is
  /// ignored: this never fails.
  Future<void> warmConnection(Uri focus) async {
    if (_closed) return;
    final key = focus.toString();
    final now = _now();
    final last = _warmed[key];
    if (last != null && now.difference(last) < warmAgain) return;
    _warmed[key] = now;
    HostClassifier.register(focus, HostClass.tokenService);
    try {
      await _client
          .get(Uri.parse("$focus/healthz"))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Only the connection mattered.
    }
  }

  _Held<matrix.OpenIdCredentials>? _openId;
  _Pending<matrix.OpenIdCredentials>? _openIdRequest;

  /// The account's OpenID token: the one held while it has more than
  /// [margin] left, or else one asked for with [request], sharing a request
  /// already running. [ahead] is for the warm-up: a join that shares a
  /// request made ahead which fails sends its own (see [_share]).
  Future<matrix.OpenIdCredentials> openId(
      Future<matrix.OpenIdCredentials> Function() request,
      {bool ahead = false}) async {
    if (_closed) throw StateError("The call token service was closed");
    final held = _openId;
    if (held != null && held.usable(_now())) return held.value;
    final deadline = _now().add(timeout);
    var within = timeout;
    final pending = _openIdRequest;
    if (pending != null) {
      final shared = await _share(pending, ahead: ahead, deadline: deadline);
      if (shared != null) return shared;
      within = _left(deadline);
      _checkLeft(within);
    }
    final started = _now();
    final mine = _Pending(
        request().timeout(within).then((credentials) {
          if (!_closed) {
            _openId = _Held(credentials,
                started.add(Duration(seconds: credentials.expiresIn)));
          }
          return credentials;
        }),
        ahead: ahead);
    _openIdRequest = mine;
    mine.future.whenComplete(() {
      if (identical(_openIdRequest, mine)) _openIdRequest = null;
    }).ignore();
    return mine.future;
  }

  final Map<String, _Held<SfuGrant>> _grants = {};
  final Map<String, _Pending<SfuGrant>> _grantRequests = {};

  static String _grantKey(Uri focus, String roomId, String deviceId) =>
      "$focus $roomId $deviceId";

  /// Whether a call token of room [roomId] is held, whatever its service:
  /// then a join asks for no OpenID token before it knows the service.
  bool holdsGrant(String roomId, String deviceId) {
    final now = _now();
    return _grants.entries.any((entry) =>
        entry.key.endsWith(" $roomId $deviceId") && entry.value.usable(now));
  }

  /// Whether the call token of room [roomId] from the service at [focus],
  /// spelled as there, is held: what [sfuGrant] would answer without a
  /// request.
  bool holdsGrantFrom(Uri focus,
          {required String roomId, required String deviceId}) =>
      _grants[_grantKey(focus, roomId, deviceId)]?.usable(_now()) ?? false;

  /// The call token of room [roomId] from the service at [focus]: the one
  /// held while its JWT has more than [margin] left, or one asked for with
  /// the OpenID token [openId] gives, sharing a request already running.
  /// [ahead] as for [openId].
  Future<HeldGrant> sfuGrant(Uri focus,
      {required String roomId,
      required String deviceId,
      required Future<matrix.OpenIdCredentials> Function() openId,
      bool ahead = false}) async {
    if (_closed) throw StateError("The call token service was closed");
    final key = _grantKey(focus, roomId, deviceId);
    final held = _grants[key];
    if (held != null && held.usable(_now())) {
      return (grant: held.value, held: true);
    }
    final deadline = _now().add(timeout);
    var within = () => timeout;
    final pending = _grantRequests[key];
    if (pending != null) {
      final shared = await _share(pending, ahead: ahead, deadline: deadline);
      if (shared != null) return (grant: shared, held: true);
      // What is left once the OpenID token is there.
      within = () => _left(deadline);
    }
    final mine = _Pending(
        _requestGrant(key, focus, roomId, deviceId, openId, within),
        ahead: ahead);
    _grantRequests[key] = mine;
    mine.future.whenComplete(() {
      if (identical(_grantRequests[key], mine)) _grantRequests.remove(key);
    }).ignore();
    return (grant: await mine.future, held: false);
  }

  Future<SfuGrant> _requestGrant(
      String key,
      Uri focus,
      String roomId,
      String deviceId,
      Future<matrix.OpenIdCredentials> Function() openId,
      Duration Function() within) async {
    final credentials = await openId();
    final SfuGrant grant;
    try {
      grant = await requestSfu(
          focus,
          {
            "device_id": deviceId,
            "room": roomId,
            "openid_token": {
              "matrix_server_name": credentials.matrixServerName,
              "access_token": credentials.accessToken,
              "expires_in": credentials.expiresIn,
            }
          },
          within: within());
    } catch (_) {
      // The service may have refused the OpenID token held: the next try
      // asks for a new one.
      if (identical(_openId?.value, credentials)) _openId = null;
      rethrow;
    }
    final expires = grant.expires;
    if (!_closed && expires != null) _grants[key] = _Held(grant, expires);
    return grant;
  }

  /// What [pending] gives, or null when the caller is to send its own
  /// request: a join ([ahead] false) sharing a request made ahead that
  /// failed before [deadline]. A join waits for it until [deadline] at
  /// most, 15 s ([timeout]) from its own start: one that never answers
  /// fails the join then, as the join's own request would, rather than
  /// 15 s after the warm-up sent it and then 15 s more for the join's own.
  Future<T?> _share<T>(_Pending<T> pending,
      {required bool ahead, required DateTime deadline}) async {
    if (ahead) return pending.future;
    try {
      return await pending.future.timeout(_left(deadline));
    } catch (_) {
      if (!pending.ahead || _left(deadline) <= Duration.zero) rethrow;
      return null;
    }
  }

  /// How long is left until [deadline], [timeout] at most.
  Duration _left(DateTime deadline) {
    final left = deadline.difference(_now());
    return left > timeout ? timeout : left;
  }

  /// Fails a request that has no time left before it is sent.
  static void _checkLeft(Duration within) {
    if (within <= Duration.zero) {
      throw TimeoutException("No time left for the request", within);
    }
  }

  /// Drops the call token held for room [roomId] at [focus]: the SFU
  /// refused it.
  void forgetGrant(Uri focus,
          {required String roomId, required String deviceId}) =>
      _grants.remove(_grantKey(focus, roomId, deviceId));

  /// Closes the connection and drops every token held. Only [forClient]'s
  /// logout watch calls this for an account's service.
  void close() {
    if (_closed) return;
    _closed = true;
    _openId = null;
    _openIdRequest = null;
    _grants.clear();
    _grantRequests.clear();
    _client.close();
  }

  static final Expando<CallTokenService> _services = Expando();

  /// The service of the account [client], made on first use ([create], for
  /// tests) and closed when the account logs out: the next join after a
  /// login gets a new one.
  static CallTokenService forClient(matrix.Client client,
          {CallTokenService Function()? create}) =>
      forAccount(client, client.onLoginStateChanged.stream, create: create);

  /// [forClient] for an [account] whose login states come from
  /// [loginStates]. Tests call it with a stream of their own.
  static CallTokenService forAccount(
      Object account, Stream<matrix.LoginState> loginStates,
      {CallTokenService Function()? create}) {
    final existing = _services[account];
    if (existing != null && !existing.isClosed) return existing;
    final service = (create ?? CallTokenService.new)();
    _services[account] = service;
    late final StreamSubscription<matrix.LoginState> watch;
    watch = loginStates.listen((state) {
      if (state != matrix.LoginState.loggedOut) return;
      service.close();
      if (identical(_services[account], service)) _services[account] = null;
      watch.cancel();
    }, onError: (Object _) {});
    return service;
  }
}

/// A token held until [lapses].
class _Held<T> {
  _Held(this.value, this.lapses);

  final T value;
  final DateTime lapses;

  /// Whether it still has more than [CallTokenService.margin] left at [now].
  bool usable(DateTime now) =>
      now.isBefore(lapses.subtract(CallTokenService.margin));
}

/// A request running, and whether the warm-up made it.
class _Pending<T> {
  _Pending(this.future, {required this.ahead}) {
    // Its error is the caller's to report.
    future.ignore();
  }

  final Future<T> future;
  final bool ahead;
}
