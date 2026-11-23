// ROOSTER: Matrix v1.15-v1.18 OAuth 2.0 API helpers (MSC2964/MSC2965/MSC2967):
// scope negotiation from `scopes_supported`, `prompt=create`, the checks a
// server must pass for Authorization Code + PKCE, and the validation of the
// redirect the authorization server sends back. Kept apart from the flow so
// the device grant (RFC 8628) and refresh work can reuse them.

import 'package:matrix/matrix.dart';

/// The Matrix scope tokens of the OAuth 2.0 API.
abstract final class OidcMatrixScopes {
  /// Matrix v1.15 stable scope for full client-server API access.
  static const String api = 'urn:matrix:client:api:*';

  /// Matrix v1.15 stable prefix of the device scope.
  static const String devicePrefix = 'urn:matrix:client:device:';

  /// MSC2967 unstable scope, still the only one some MAS versions accept.
  static const String unstableApi =
      'urn:matrix:org.matrix.msc2967.client:api:*';

  /// MSC2967 unstable prefix of the device scope.
  static const String unstableDevicePrefix =
      'urn:matrix:org.matrix.msc2967.client:device:';

  static const String openid = 'openid';
}

/// Whether [scopesSupported] (from `auth_metadata`) announces the stable
/// Matrix scopes. Servers that list none, or only the MSC2967 ones, get the
/// unstable scopes.
bool oidcServerSupportsStableScopes(List<String>? scopesSupported) =>
    scopesSupported != null &&
    scopesSupported.any(
      (scope) =>
          scope == OidcMatrixScopes.api ||
          scope.startsWith(OidcMatrixScopes.devicePrefix),
    );

/// The scopes to ask for: the Matrix API scope and the device scope for
/// [deviceId], stable when the server lists them in `scopes_supported` and
/// MSC2967 otherwise. `openid` is only added when the server does not list
/// its scopes or lists `openid`.
Set<String> negotiateOidcScopes({
  required List<String>? scopesSupported,
  required String deviceId,
}) {
  final stable = oidcServerSupportsStableScopes(scopesSupported);
  return {
    if (scopesSupported == null || scopesSupported.contains('openid'))
      OidcMatrixScopes.openid,
    stable ? OidcMatrixScopes.api : OidcMatrixScopes.unstableApi,
    '${stable ? OidcMatrixScopes.devicePrefix : OidcMatrixScopes.unstableDevicePrefix}$deviceId',
  };
}

extension OidcAuthMetadataSupport on GetAuthMetadataResponse {
  /// The server supports what a Matrix client needs for the Authorization
  /// Code grant: the `code` response type and PKCE with S256.
  bool get supportsAuthorizationCodeWithPkce =>
      grantTypesSupported.contains('authorization_code') &&
      responseTypesSupported.contains('code') &&
      codeChallengeMethodsSupported.contains('S256');

  /// The server can open its registration page (`prompt=create`, MSC4191 /
  /// Matrix v1.17).
  bool get supportsPromptCreate =>
      promptValuesSupported?.contains('create') == true;

  /// The server accepts an HTTPS URL as `client_id` (Client ID Metadata
  /// Document, Matrix v1.15 MSC2965).
  bool get supportsClientIdMetadataDocument =>
      clientIdMetadataDocumentSupported == true;
}

/// Why the authorization server's redirect was refused.
enum OidcCallbackFailure {
  /// The redirect carries no `state`.
  stateMissing,

  /// The `state` is not the one this session sent: a stale page or a forged
  /// redirect.
  stateMismatch,

  /// The person refused access (`error=access_denied`).
  accessDenied,

  /// The server answered with another OAuth error.
  authorizationError,

  /// The redirect has neither an error nor a `code`.
  codeMissing,
}

class OidcCallbackException implements Exception {
  final OidcCallbackFailure failure;

  /// The OAuth `error` code, when the server sent one.
  final String? error;

  const OidcCallbackException(this.failure, {this.error});

  @override
  String toString() =>
      'OidcCallbackException(${failure.name}${error == null ? '' : ', $error'})';
}

/// Reads the authorization `code` from [callbackUri], the redirect the
/// authorization server sent back for [session]. The `state` is checked
/// before anything else is trusted; any failure throws an
/// [OidcCallbackException] and nothing is exchanged.
String parseOidcAuthorizationCallback(
  OidcLoginSession session,
  Uri callbackUri,
) {
  final fromFragment = callbackUri.fragment.isEmpty
      ? const <String, String>{}
      : Uri.splitQueryString(callbackUri.fragment);
  final fromQuery = callbackUri.queryParameters;
  final preferred = session.responseMode == OidcResponseMode.fragment
      ? fromFragment
      : fromQuery;
  final params = preferred.isNotEmpty
      ? preferred
      : (identical(preferred, fromQuery) ? fromFragment : fromQuery);

  final state = params['state'];
  if (state != null && !_constantTimeEquals(state, session.state)) {
    throw const OidcCallbackException(OidcCallbackFailure.stateMismatch);
  }
  final error = params['error'];
  if (error != null) {
    throw OidcCallbackException(
      error == 'access_denied'
          ? OidcCallbackFailure.accessDenied
          : OidcCallbackFailure.authorizationError,
      error: error,
    );
  }
  if (state == null || state.isEmpty) {
    throw const OidcCallbackException(OidcCallbackFailure.stateMissing);
  }
  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw const OidcCallbackException(OidcCallbackFailure.codeMissing);
  }
  return code;
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
