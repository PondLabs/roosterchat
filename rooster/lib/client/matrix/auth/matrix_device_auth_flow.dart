import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';

/// Time for the device grant's polling, so tests can move it by hand.
abstract class DeviceGrantClock {
  DateTime now();

  /// Calls [callback] once after [delay]. The flow cancels the timer when it
  /// stops waiting.
  Timer schedule(Duration delay, void Function() callback);
}

class SystemDeviceGrantClock implements DeviceGrantClock {
  const SystemDeviceGrantClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// What the person needs to approve the sign-in on another device.
class DeviceAuthorizationPrompt {
  const DeviceAuthorizationPrompt({
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    this.verificationUriComplete,
  });

  final String userCode;
  final Uri verificationUri;

  /// The verification page with the code already filled in, when the server
  /// sends one: the QR code and the link use it.
  final Uri? verificationUriComplete;
  final DateTime expiresAt;

  Uri get link => verificationUriComplete ?? verificationUri;
}

/// Signs in with the OAuth 2.0 Device Authorization Grant (RFC 8628, Matrix
/// v1.18 MSC4341): the server hands out a code, the person approves it on a
/// device where they can sign in (a phone, a browser), and the token
/// endpoint is polled until it answers. Offered when `auth_metadata` has a
/// `device_authorization_endpoint`, on every platform: nothing comes back to
/// Rooster through a redirect.
class MatrixDeviceAuthFlow implements LoginFlow {
  MatrixDeviceAuthFlow({
    required this.authMetadata,
    this.clock = const SystemDeviceGrantClock(),
    Uri? clientMetadataDocumentUri,
  }) : clientMetadataDocumentUri = clientMetadataDocumentUri ??
            MatrixOidcLoginFlow.defaultClientMetadataDocumentUri;

  final matrix.GetAuthMetadataResponse authMetadata;
  final DeviceGrantClock clock;
  final Uri? clientMetadataDocumentUri;

  static const deviceCodeGrantType =
      'urn:ietf:params:oauth:grant-type:device_code';

  /// RFC 8628 §3.2: polling starts at 5 seconds when the server names none.
  static const defaultInterval = Duration(seconds: 5);

  /// RFC 8628 §3.5: each `slow_down` adds 5 seconds to the interval.
  static const slowDownStep = Duration(seconds: 5);

  static bool isSupportedBy(matrix.GetAuthMetadataResponse? metadata) =>
      metadata?.deviceAuthorizationEndpoint != null;

  /// The code to show, from the moment the server hands it out until the
  /// flow ends.
  final ValueNotifier<DeviceAuthorizationPrompt?> prompt = ValueNotifier(null);

  final Completer<void> _cancelled = Completer<void>();
  Timer? _timer;

  bool get isCancelled => _cancelled.isCompleted;

  /// Stops at once: the pending poll is cancelled and an answer still on its
  /// way is ignored.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _timer?.cancel();
  }

  static String get errorLoginDeviceExpired => Intl.message(
      "The code expired before it was approved. Start again to get a new "
      "one.",
      name: "errorLoginDeviceExpired",
      desc: "In the 'Login failed' dialog when the sign-in code shown for "
          "signing in from another device ran out of time before the person "
          "approved it");

  static String get errorLoginDeviceDenied => Intl.message(
      "The sign-in was refused on the other device, so you are not signed "
      "in.",
      name: "errorLoginDeviceDenied",
      desc: "In the 'Login failed' dialog when the person, or the server, "
          "refused the sign-in on the device where the code was entered");

  static String get errorLoginDeviceFailed =>
      Intl.message("Your server could not sign you in with a code. Try again.",
          name: "errorLoginDeviceFailed",
          desc: "In the 'Login failed' dialog when signing in from another "
              "device failed for a reason the server did not explain");

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(MatrixSSOLoginFlow.errorLoginWrongClientType);
    }
    final mx = client.getMatrixClient();
    try {
      final clientId = (await _untilCancelled(_obtainClient(mx)))?.clientId;
      if (clientId == null) return LoginResultCancelled();

      final scopes = matrix.negotiateOidcScopes(
        scopesSupported: authMetadata.scopesSupported,
        deviceId: matrix.generateRandomDeviceId(),
      );
      final authorization = await _untilCancelled(mx.httpClient.post(
        authMetadata.deviceAuthorizationEndpoint!,
        body: {'client_id': clientId, 'scope': scopes.join(' ')},
      ));
      if (authorization == null) return LoginResultCancelled();
      final grant = _DeviceGrant.parse(authorization, clock.now());
      if (grant == null) return LoginResultError(errorLoginDeviceFailed);
      prompt.value = grant.prompt;

      var interval = grant.interval;
      while (true) {
        final remaining = grant.prompt.expiresAt.difference(clock.now());
        if (remaining <= Duration.zero) {
          return LoginResultError(errorLoginDeviceExpired);
        }
        if (!await _wait(interval < remaining ? interval : remaining)) {
          return LoginResultCancelled();
        }
        if (!clock.now().isBefore(grant.prompt.expiresAt)) {
          return LoginResultError(errorLoginDeviceExpired);
        }

        final answer = await _untilCancelled(mx.httpClient.post(
          authMetadata.tokenEndpoint,
          body: {
            'grant_type': deviceCodeGrantType,
            'device_code': grant.deviceCode,
            'client_id': clientId,
          },
        ));
        if (answer == null) return LoginResultCancelled();

        if (answer.statusCode == 200) {
          final tokens = matrix.OidcAuthResponse.fromJson(
              jsonDecode(utf8.decode(answer.bodyBytes)));
          final expiresIn = tokens.expiresIn;
          // Past this point the account is made: cancelling no longer applies.
          await mx.init(
            newHomeserver: mx.homeserver,
            newToken: tokens.accessToken,
            newRefreshToken: tokens.refreshToken,
            newTokenExpiresAt: expiresIn != null && expiresIn > 0
                ? DateTime.now().add(Duration(seconds: expiresIn))
                : null,
            newOidcClientId: clientId,
          );
          return mx.isLogged() ? LoginResultSuccess() : LoginResultFailed();
        }

        final error = _errorCode(answer);
        switch (error) {
          case 'authorization_pending':
            continue;
          case 'slow_down':
            interval += slowDownStep;
            continue;
          case 'access_denied':
            return LoginResultError(errorLoginDeviceDenied);
          case 'expired_token':
            return LoginResultError(errorLoginDeviceExpired);
          default:
            // The error code only: the answer may echo the device code.
            Log.w("Device grant refused: ${error ?? answer.statusCode}");
            return LoginResultError(errorLoginDeviceFailed);
        }
      }
    } on matrix.OidcClientRegistrationException {
      return LoginResultError(
          MatrixOidcLoginFlow.errorLoginOauthNoClientRegistration);
    } catch (e, s) {
      Log.onError(e, s, content: "Device grant sign-in failed");
      return LoginResultError(errorLoginDeviceFailed);
    } finally {
      _timer?.cancel();
      _timer = null;
      prompt.value = null;
    }
  }

  /// A client allowed to use the device grant: the build's Client ID
  /// Metadata Document when the server takes one, else a registration that
  /// names the grant (the SDK's default registration does not).
  Future<matrix.OidcClientData> _obtainClient(matrix.Client mx) {
    final document = clientMetadataDocumentUri;
    final information = matrix.OidcClientInformation(
      clientName: BuildConfig.appName,
      clientUri: Uri.parse('https://pondlabs.github.io/roosterchat/'),
      logoUri: null,
      tosUri: null,
      policyUri: null,
    );
    // Not translated: a loopback redirect, required by the registration.
    final redirectUri = Uri.parse('http://127.0.0.1/callback');
    if (document != null && authMetadata.supportsClientIdMetadataDocument) {
      return mx.obtainOidcClient(
        redirectUris: [redirectUri],
        applicationType: matrix.OidcApplicationType.native,
        clientInformation: information,
        clientMetadataDocumentUri: document,
        authMetadata: authMetadata,
      );
    }
    if (authMetadata.registrationEndpoint == null) {
      throw const matrix.OidcClientRegistrationException();
    }
    return mx.registerOidcClient(
      redirectUris: [redirectUri],
      applicationType: matrix.OidcApplicationType.native,
      clientInformation: information,
      grantTypes: const [
        'authorization_code',
        'refresh_token',
        deviceCodeGrantType,
      ],
    );
  }

  /// Waits [delay] on the clock; false when cancelled first.
  Future<bool> _wait(Duration delay) async {
    if (isCancelled) return false;
    final elapsed = Completer<bool>();
    _timer = clock.schedule(delay, () {
      if (!elapsed.isCompleted) elapsed.complete(true);
    });
    unawaited(_cancelled.future.then((_) {
      if (!elapsed.isCompleted) elapsed.complete(false);
    }));
    final done = await elapsed.future;
    _timer?.cancel();
    _timer = null;
    return done;
  }

  /// [future]'s value, or null as soon as the flow is cancelled.
  Future<T?> _untilCancelled<T>(Future<T> future) {
    if (isCancelled) return Future.value(null);
    return Future.any<T?>([future, _cancelled.future.then((_) => null)]);
  }

  static String? _errorCode(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map && body['error'] is String
          ? body['error'] as String
          : null;
    } catch (_) {
      return null;
    }
  }
}

class _DeviceGrant {
  _DeviceGrant(this.deviceCode, this.interval, this.prompt);

  final String deviceCode;
  final Duration interval;
  final DeviceAuthorizationPrompt prompt;

  /// The device authorization response (RFC 8628 §3.2), or null when it is
  /// not one: a verification link other than http(s) is refused, since the
  /// screen offers to open it.
  static _DeviceGrant? parse(http.Response response, DateTime now) {
    if (response.statusCode != 200) {
      Log.w("Device authorization refused: ${response.statusCode}");
      return null;
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) return null;
      final deviceCode = json['device_code'];
      final userCode = json['user_code'];
      final verificationUri = _webUri(json['verification_uri']);
      final expiresIn = json['expires_in'];
      final interval = json['interval'];
      if (deviceCode is! String ||
          deviceCode.isEmpty ||
          userCode is! String ||
          userCode.isEmpty ||
          verificationUri == null ||
          expiresIn is! num ||
          expiresIn <= 0) {
        return null;
      }
      return _DeviceGrant(
        deviceCode,
        interval is num && interval > 0
            ? Duration(seconds: interval.ceil())
            : MatrixDeviceAuthFlow.defaultInterval,
        DeviceAuthorizationPrompt(
          userCode: userCode,
          verificationUri: verificationUri,
          verificationUriComplete: _webUri(json['verification_uri_complete']),
          expiresAt: now.add(Duration(seconds: expiresIn.floor())),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Uri? _webUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? uri
        : null;
  }
}
