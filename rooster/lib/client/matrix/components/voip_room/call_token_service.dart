import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/utils/network/speed_http_client.dart';

/// What the call token service hands out for one call: the SFU's address
/// and the JWT that lets us into the call's LiveKit room.
class SfuGrant {
  const SfuGrant({required this.url, required this.jwt});

  final String url;
  final String jwt;
}

/// The call token service (MatrixRTC's `POST <focus>/sfu/get`, served by
/// lk-jwt-service), through one long-lived HTTP client per account.
///
/// A new client per join opened a new TCP and TLS connection every time;
/// this one keeps its connection, so a join after the first reuses it. It
/// sends through [SpeedHttpClient], so each request is in the speed log as
/// `token_service`, and the SFU the answer names is registered as `sfu`.
///
/// [forClient] gives an account its service and closes it when the account
/// logs out. The warm-up before the click (a later task) is meant to open the
/// connection through the same client.
class CallTokenService {
  CallTokenService({http.Client? client})
      : _client = client ?? SpeedHttpClient(inner: http.Client());

  final http.Client _client;
  bool _closed = false;

  /// Bounded: the Join button is disabled while this runs, so a request
  /// that never answers left no way to try again.
  static const timeout = Duration(seconds: 15);

  bool get isClosed => _closed;

  /// Asks the service at [focus] for a place in the call, with [body] (our
  /// device, the room and an OpenID token, see `CallJoin`).
  Future<SfuGrant> requestSfu(Uri focus, Map<String, Object?> body) async {
    if (_closed) throw StateError("The call token service was closed");
    HostClassifier.register(focus, HostClass.tokenService);
    final uri = Uri.parse("$focus/sfu/get");
    final result =
        await _client.post(uri, body: jsonEncode(body)).timeout(timeout);
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

  /// Closes the connection. Only [forClient]'s logout watch calls this for
  /// an account's service.
  void close() {
    if (_closed) return;
    _closed = true;
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
