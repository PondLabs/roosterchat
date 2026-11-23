import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';

import '../matrix_auth_oidc/oidc_fakes.dart';

export '../matrix_auth_oidc/oidc_fakes.dart';

const deviceAuthorizationEndpoint = 'https://auth.example.org/oauth2/device';

Map<String, Object?> deviceAuthMetadataJson({bool device = true}) => {
      ...authMetadataJson(),
      if (device) 'device_authorization_endpoint': deviceAuthorizationEndpoint,
      'grant_types_supported': [
        'authorization_code',
        'refresh_token',
        MatrixDeviceAuthFlow.deviceCodeGrantType,
      ],
    };

/// A clock that only moves when the test fires its next timer.
class FakeDeviceGrantClock implements DeviceGrantClock {
  DateTime _now = DateTime.utc(2026, 11, 23, 12);
  final List<FakeTimer> timers = [];

  /// Every delay the flow asked for, in order.
  List<Duration> get delays => timers.map((t) => t.delay).toList();

  int get pendingTimers => timers.where((t) => t.isActive).length;

  @override
  DateTime now() => _now;

  @override
  Timer schedule(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }

  /// Waits (in real time, a bounded number of turns) for the flow to set a
  /// timer, then moves the clock to it and fires it.
  Future<void> fireNext() async {
    await waitFor(() => pendingTimers > 0);
    final timer = timers.lastWhere((t) => t.isActive);
    _now = _now.add(timer.delay);
    timer.fire();
  }
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!condition()) throw StateError('condition not met in time');
}

/// The OAuth-only homeserver of the OAuth tests, plus a device
/// authorization endpoint and a token endpoint that answers from [answers]
/// in order.
class DeviceGrantServer extends http.BaseClient {
  DeviceGrantServer({
    Map<String, Object?>? metadata,
    Map<String, Object?>? authorization,
    List<FutureOr<http.Response>>? answers,
  })  : _inner =
            OAuthOnlyServer(metadata: metadata ?? deviceAuthMetadataJson()),
        authorization = authorization ?? deviceAuthorizationJson(),
        answers = answers ?? [];

  final OAuthOnlyServer _inner;
  Map<String, Object?> authorization;
  final List<FutureOr<http.Response>> answers;
  final List<http.Request> deviceRequests = [];
  final List<http.Request> tokenPolls = [];

  List<http.Request> get registrationRequests =>
      _inner.registrationRequests.toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    if (url != deviceAuthorizationEndpoint && url != tokenEndpoint) {
      return _inner.send(request);
    }
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = await request.finalize().toBytes();
    final http.Response answer;
    if (url == deviceAuthorizationEndpoint) {
      deviceRequests.add(copy);
      answer = json(authorization);
    } else {
      tokenPolls.add(copy);
      answer = await answers.removeAt(0);
    }
    return http.StreamedResponse(
      Stream.value(answer.bodyBytes),
      answer.statusCode,
      headers: answer.headers,
      request: request,
    );
  }

  static http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  static http.Response error(String code) => json({'error': code}, status: 400);

  static http.Response tokens() => json({
        'access_token': 'device-access-token',
        'token_type': 'Bearer',
        'expires_in': 300,
        'refresh_token': 'device-refresh-token',
      });
}

Map<String, Object?> deviceAuthorizationJson({
  Object? interval = 5,
  int expiresIn = 600,
  String verificationUri = 'https://auth.example.org/link',
  String? complete = 'https://auth.example.org/link?code=ABCD-EFGH',
}) =>
    {
      'device_code': 'secret-device-code',
      'user_code': 'ABCD-EFGH',
      'verification_uri': verificationUri,
      if (complete != null) 'verification_uri_complete': complete,
      'expires_in': expiresIn,
      if (interval != null) 'interval': interval,
    };
