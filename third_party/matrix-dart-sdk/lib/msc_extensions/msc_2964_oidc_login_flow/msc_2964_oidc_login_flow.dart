import 'dart:convert';
import 'dart:math';

import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/crypto/crypto.dart';

// ROOSTER: Matrix v1.15-v1.18 scope negotiation and redirect validation.
export 'oidc_authorization.dart';

extension Msc2964OidcLoginFlow on Client {
  /// Initializes a new OIDC Login session by creating a state, a code verifier
  /// and an authorization URI.
  /// It needs an already created OIDC Client from `Client.registerOidcClient()`
  /// and the `authMetadata` from `Client.checkHomeserver()`.
  /// Use the authorization URI to open it in browser and fetch `code` and
  /// `state` from the query parameters of the redirect URI to login with
  /// `Client.oidcLogin()`.
  Future<OidcLoginSession> initOidcLoginSession({
    required OidcClientData oidcClientData,
    required Uri redirectUri,
    String? deviceId,
    Set<String>? scopes,
    int codeVerifierBytesLength = 32,
    OidcResponseMode? responseMode,
    String? prompt,
    // ROOSTER: reuse the metadata from checkHomeserver() instead of fetching it again.
    GetAuthMetadataResponse? authMetadata,
  }) async {
    authMetadata ??= await getAuthMetadata();
    deviceId ??= generateRandomDeviceId();
    // ROOSTER: stable `urn:matrix:client:*` scopes (Matrix v1.15) when the
    // server lists them in `scopes_supported`, MSC2967 scopes otherwise.
    scopes ??= negotiateOidcScopes(
      scopesSupported: authMetadata.scopesSupported,
      deviceId: deviceId,
    );
    responseMode ??= redirectUri.scheme == 'https'
        ? OidcResponseMode.fragment
        : OidcResponseMode.query;
    // ROOSTER: never ask for a response mode the server does not offer.
    final modes = authMetadata.responseModesSupported;
    if (modes.isNotEmpty && !modes.contains(responseMode.name)) {
      final other = responseMode == OidcResponseMode.fragment
          ? OidcResponseMode.query
          : OidcResponseMode.fragment;
      if (modes.contains(other.name)) responseMode = other;
    }

    final state = base64UrlEncodeNoPadding(secureRandomBytes(32));
    final codeVerifier =
        base64UrlEncodeNoPadding(secureRandomBytes(codeVerifierBytesLength));
    final codeChallenge = base64UrlEncodeNoPadding(
      vod.CryptoUtils.sha256(input: ascii.encode(codeVerifier)),
    );
    final authenticationUri = authMetadata.authorizationEndpoint.replace(
      queryParameters: {
        'client_id': oidcClientData.clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'scope': scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'response_mode': responseMode.name,
        'state': state,
        if (prompt != null) 'prompt': prompt,
      },
    );

    return OidcLoginSession(
      oidcClientData: oidcClientData,
      authenticationUri: authenticationUri,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
      state: state,
      deviceId: deviceId,
      scopes: scopes,
      responseMode: responseMode,
    );
  }

  /// Performs a login with OIDC. It needs an `OidcLoginSession` from
  /// `Client.initOidcLoginSession()` and the `code` and `state` from the
  /// query parameters of the returned URL.
  Future<void> oidcLogin({
    required OidcLoginSession session,
    required String code,
    required String state,
    // ROOSTER: reuse the metadata from checkHomeserver().
    GetAuthMetadataResponse? authMetadata,
  }) async {
    if (session.state != state) {
      throw Exception(
        'OIDC state differs from initial session. This could either be a bug or a man-in-the-middle attack.',
      );
    }
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': session.redirectUri.toString(),
      'client_id': session.oidcClientData.clientId,
      'code_verifier': session.codeVerifier,
    };
    authMetadata ??= await getAuthMetadata();
    final response = await httpClient.post(
      authMetadata.tokenEndpoint,
      body: body,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    if (response.statusCode != 200) {
      unexpectedResponse(
        response,
        response.bodyBytes,
      );
    }
    final responseString = utf8.decode(response.bodyBytes);
    final oidcAuthResponse =
        OidcAuthResponse.fromJson(jsonDecode(responseString));
    // ROOSTER: OAuth 2.0 / OIDC `expires_in` is in seconds (RFC 6749 §5.1); ignore non-positive values.
    final expiresIn = oidcAuthResponse.expiresIn;
    final tokenExpiresAt = expiresIn != null && expiresIn > 0
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null;
    await init(
      newHomeserver: homeserver,
      newToken: oidcAuthResponse.accessToken,
      newRefreshToken: oidcAuthResponse.refreshToken,
      newTokenExpiresAt: tokenExpiresAt,
      newOidcClientId: session.oidcClientData.clientId,
    );
  }

  Future<OidcAuthResponse> oidcRefresh(
    String oidcClientId,
    String refreshToken,
  ) async {
    final authMetadata = await getAuthMetadata();
    final response = await httpClient.post(
      authMetadata.tokenEndpoint,
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': oidcClientId,
      },
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    if (response.statusCode != 200) {
      unexpectedResponse(
        response,
        response.bodyBytes,
      );
    }
    final responseString = utf8.decode(response.bodyBytes);
    return OidcAuthResponse.fromJson(jsonDecode(responseString));
  }

  Future<void> revokeOidcToken(
    String oidcClientId,
    String token,
    String tokenType,
  ) async {
    final authMetadata = await getAuthMetadata();
    // ROOSTER: revocation_endpoint is optional in RFC 8414 / Matrix auth_metadata.
    final revocationEndpoint = authMetadata.revocationEndpoint;
    if (revocationEndpoint == null) {
      throw Exception('OIDC server does not advertise a revocation_endpoint.');
    }
    final response = await httpClient.post(
      revocationEndpoint,
      body: <String, String>{
        'token': token,
        'token_type': tokenType,
        'client_id': oidcClientId,
      },
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    if (response.statusCode != 200) {
      unexpectedResponse(
        response,
        response.bodyBytes,
      );
    }
  }
}

class OidcAuthResponse {
  final String accessToken, tokenType;
  final String? refreshToken, scope;
  final int? expiresIn;

  OidcAuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.refreshToken,
    required this.scope,
    required this.expiresIn,
  });

  factory OidcAuthResponse.fromJson(Map<String, Object?> json) {
    // ROOSTER: Parse `expires_in` safely as an integer number of seconds.
    final rawExpiresIn = json['expires_in'];
    final expiresIn = rawExpiresIn is int
        ? rawExpiresIn
        : (rawExpiresIn is num && rawExpiresIn.isFinite
            ? rawExpiresIn.toInt()
            : null);
    return OidcAuthResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      refreshToken: json['refresh_token'] as String?,
      scope: json['scope'] as String?,
      expiresIn: expiresIn,
    );
  }
}

class OidcLoginSession {
  final OidcClientData oidcClientData;
  final Uri authenticationUri, redirectUri;
  final String codeVerifier, state;

  // ROOSTER: what the session asked for, so the redirect is read where the
  // server puts it and the device ID is known before the token exchange.
  final String? deviceId;
  final Set<String> scopes;
  final OidcResponseMode responseMode;

  OidcLoginSession({
    required this.oidcClientData,
    required this.authenticationUri,
    required this.redirectUri,
    required this.codeVerifier,
    required this.state,
    this.deviceId,
    this.scopes = const {},
    this.responseMode = OidcResponseMode.query,
  });
}

enum OidcResponseMode { fragment, query }

String base64UrlEncodeNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', ''); // URL-safe & unpadded
}

String generateRandomDeviceId() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final random = Random.secure();
  return List.generate(10, (_) => letters[random.nextInt(letters.length)])
      .join();
}
