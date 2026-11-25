import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/auth/oidc_redirect_receiver.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/language/app_language.dart';

/// Signs in through the homeserver's OAuth 2.0 authorization server (Matrix
/// v1.15 OAuth 2.0 API): Authorization Code with PKCE (S256), the client
/// identified by a Client ID Metadata Document when the server and the build
/// have one, else registered with RFC 7591, and `prompt=create` for the
/// "Create account" button when the server offers it. The browser comes
/// back to a loopback server on `127.0.0.1` on desktop and to `auth.html` on
/// the web. Nothing is stored unless the server hands over a token.
class MatrixOidcLoginFlow implements LoginFlow {
  MatrixOidcLoginFlow({
    required this.authMetadata,
    required this.serverName,
    this.createAccount = false,
    Uri? clientMetadataDocumentUri,
    Future<OidcRedirectReceiver> Function({
      required OidcLandingPage landingPage,
    })? receiverFactory,
  })  : clientMetadataDocumentUri =
            clientMetadataDocumentUri ?? defaultClientMetadataDocumentUri,
        _receiverFactory = receiverFactory ?? createOidcRedirectReceiver;

  /// The homeserver's `auth_metadata`, from `checkHomeserver`.
  final matrix.GetAuthMetadataResponse authMetadata;

  /// The homeserver's name, for the button.
  final String serverName;

  /// Opens the server's registration page (`prompt=create`) instead of its
  /// sign-in page, when the server offers it.
  final bool createAccount;

  /// The URL of Rooster's Client ID Metadata Document, or null to always
  /// register the client (RFC 7591).
  final Uri? clientMetadataDocumentUri;

  final Future<OidcRedirectReceiver> Function({
    required OidcLandingPage landingPage,
  }) _receiverFactory;

  /// The build's Client ID Metadata Document (MSC2965), given with
  /// `--dart-define OAUTH_CLIENT_METADATA_URL=https://…`. Empty by default:
  /// the document has to be published first, and until then every server is
  /// asked to register the client.
  static Uri? get defaultClientMetadataDocumentUri {
    const value = String.fromEnvironment('OAUTH_CLIENT_METADATA_URL');
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  // Not translated: a URL.
  static final Uri _clientUri =
      Uri.parse('https://pondlabs.github.io/roosterchat/');

  /// Desktop (loopback) and the browser (`auth.html`).
  static bool get isAvailableOnThisPlatform =>
      PlatformUtils.isWeb ||
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isMacOS;

  /// The server offers the sign-in this flow needs.
  static bool isSupportedBy(matrix.GetAuthMetadataResponse metadata) =>
      metadata.supportsAuthorizationCodeWithPkce;

  static String get errorLoginOauthStateMismatch => Intl.message(
      "The sign-in page sent back an answer Rooster did not ask for, so it "
      "was ignored. Try signing in again.",
      name: "errorLoginOauthStateMismatch",
      desc: "In the 'Login failed' dialog when the browser came back from the "
          "server's sign-in page with a reply that does not belong to this "
          "sign-in (a stale tab or a forged link); nothing was signed in");

  static String get errorLoginOauthAccessDenied => Intl.message(
      "Access was not allowed on the sign-in page, so you are not signed in.",
      name: "errorLoginOauthAccessDenied",
      desc: "In the 'Login failed' dialog when the person, or the server, "
          "refused to let Rooster in on the server's sign-in page");

  static String get errorLoginOauthFailed => Intl.message(
      "Your server's sign-in page did not finish signing you in. Try again.",
      name: "errorLoginOauthFailed",
      desc: "In the 'Login failed' dialog when the server's sign-in page came "
          "back with an error or without a login, or the login could not be "
          "completed");

  static String get errorLoginOauthNoClientRegistration => Intl.message(
      "Your server does not let new apps sign in, so Rooster cannot sign in "
      "there.",
      name: "errorLoginOauthNoClientRegistration",
      desc: "In the 'Login failed' dialog when the server neither accepts "
          "Rooster's app description nor lets apps register themselves");

  static String get labelLoginOauthReturnTitle =>
      Intl.message("Back to Rooster",
          name: "labelLoginOauthReturnTitle",
          desc: "Title of the page the system browser shows when it comes back "
              "from the server's sign-in page, on desktop");

  static String get labelLoginOauthReturn => Intl.message(
      "You can close this page and go back to Rooster.",
      name: "labelLoginOauthReturn",
      desc: "The page the system browser shows when it comes back from the "
          "server's sign-in page, on desktop; Rooster finishes the sign-in");

  static String get labelLoginOauthReturnFailed => Intl.message(
      "Signing in did not finish. You can close this page and go back to "
      "Rooster.",
      name: "labelLoginOauthReturnFailed",
      desc: "The page the system browser shows when it comes back from the "
          "server's sign-in page without a login (refused or failed), on "
          "desktop");

  /// The page the system browser shows when it is back (desktop), in the
  /// app's language.
  static String landingPage(bool ok) {
    const escape = HtmlEscape();
    final text = ok ? labelLoginOauthReturn : labelLoginOauthReturnFailed;
    return '''
<!DOCTYPE html>
<html lang="${AppLanguage.current.value.tag}">
<head>
  <meta charset="utf-8">
  <title>${escape.convert(labelLoginOauthReturnTitle)}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin: 0; padding: 0; }
    main {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;
    }
    p { padding: 2em; text-align: center; font-size: 2rem; }
  </style>
</head>
<body>
  <main><p>${escape.convert(text)}</p></main>
</body>
</html>
''';
  }

  /// The message for a refused redirect.
  static String messageForCallbackFailure(matrix.OidcCallbackFailure failure) =>
      switch (failure) {
        matrix.OidcCallbackFailure.stateMissing ||
        matrix.OidcCallbackFailure.stateMismatch =>
          errorLoginOauthStateMismatch,
        matrix.OidcCallbackFailure.accessDenied => errorLoginOauthAccessDenied,
        matrix.OidcCallbackFailure.authorizationError ||
        matrix.OidcCallbackFailure.codeMissing =>
          errorLoginOauthFailed,
      };

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(MatrixSSOLoginFlow.errorLoginWrongClientType);
    }
    final mx = client.getMatrixClient();
    return _signIn(mx, deviceId: null, finish: (session, code) async {
      await mx.oidcLogin(
        session: session,
        code: code,
        state: session.state,
        authMetadata: authMetadata,
      );
      return mx.isLogged() ? LoginResultSuccess() : LoginResultFailed();
    });
  }

  /// The flow that signs [client]'s device in again, when its session was
  /// signed in through OAuth 2.0 and the server still offers it; else null.
  static Future<MatrixOidcLoginFlow?> forReauthentication(
    MatrixClient client, {
    Future<OidcRedirectReceiver> Function({
      required OidcLandingPage landingPage,
    })? receiverFactory,
  }) async {
    if (!isAvailableOnThisPlatform) return null;
    final mx = client.getMatrixClient();
    final stored = await mx.database.getClient(mx.clientName);
    if (stored?['oidc_client_id'] == null || mx.homeserver == null) {
      return null;
    }
    final metadata = await mx.getAuthMetadata();
    if (!isSupportedBy(metadata)) return null;
    return MatrixOidcLoginFlow(
      authMetadata: metadata,
      serverName: mx.homeserver!.host,
      receiverFactory: receiverFactory,
    );
  }

  /// Signs [client]'s device in again on the server's page, asking for this
  /// same device (`urn:matrix:client:device:<device_id>`), so the database
  /// and the encryption keys stay. Throws [ReauthenticationMismatch] when
  /// the server signed in another account or device; nothing is stored then.
  Future<LoginResult> reauthenticate(MatrixClient client) {
    final mx = client.getMatrixClient();
    return _signIn(mx, deviceId: mx.deviceID!, finish: (session, code) async {
      final tokens = await _exchangeCode(mx, session, code);
      await client.tokenRefresher.reauthenticateWithOAuth(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.expiresIn,
        oidcClientId: session.oidcClientData.clientId,
      );
      return LoginResultSuccess();
    });
  }

  /// The Authorization Code grant (RFC 6749 4.1.3) with the PKCE verifier,
  /// without the SDK's `oidcLogin`, which starts a new session.
  Future<matrix.OidcAuthResponse> _exchangeCode(
      matrix.Client mx, matrix.OidcLoginSession session, String code) async {
    final response = await mx.httpClient.post(
      authMetadata.tokenEndpoint,
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': session.redirectUri.toString(),
        'client_id': session.oidcClientData.clientId,
        'code_verifier': session.codeVerifier,
      },
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    if (response.statusCode != 200) {
      mx.unexpectedResponse(response, response.bodyBytes);
    }
    return matrix.OidcAuthResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>);
  }

  /// The browser part: the client, the authorization request (for
  /// [deviceId], or a new device when null), the redirect, then [finish]
  /// with the code.
  Future<LoginResult> _signIn(
    matrix.Client mx, {
    required String? deviceId,
    required Future<LoginResult> Function(
            matrix.OidcLoginSession session, String code)
        finish,
  }) async {
    final OidcRedirectReceiver receiver;
    try {
      receiver = await _receiverFactory(landingPage: landingPage);
    } catch (e, s) {
      Log.onError(e, s, content: "OAuth redirect receiver failed to start");
      return LoginResultError(errorLoginOauthFailed);
    }

    try {
      final redirectUri = receiver.redirectUri;
      final isWeb = redirectUri.scheme == 'https' && PlatformUtils.isWeb;
      final document = clientMetadataDocumentUri;
      // On the web the document only lists the redirect of the deployment
      // it is served from.
      final useDocument = document != null &&
          (!PlatformUtils.isWeb || document.origin == redirectUri.origin);

      final oidcClient = await mx.obtainOidcClient(
        redirectUris: [redirectUri],
        applicationType: isWeb
            ? matrix.OidcApplicationType.web
            : matrix.OidcApplicationType.native,
        clientInformation: matrix.OidcClientInformation(
          clientName: BuildConfig.appName,
          clientUri: isWeb ? Uri.parse('${redirectUri.origin}/') : _clientUri,
          logoUri: null,
          tosUri: null,
          policyUri: null,
        ),
        clientMetadataDocumentUri: useDocument ? document : null,
        authMetadata: authMetadata,
      );

      final session = await mx.initOidcLoginSession(
        oidcClientData: oidcClient,
        redirectUri: redirectUri,
        deviceId: deviceId,
        authMetadata: authMetadata,
        prompt: createAccount && authMetadata.supportsPromptCreate
            ? 'create'
            : null,
      );

      final redirect = await receiver.authorize(session.authenticationUri);
      if (redirect == null) return LoginResultCancelled();

      final String code;
      try {
        code = matrix.parseOidcAuthorizationCallback(session, redirect);
      } on matrix.OidcCallbackException catch (e) {
        // The reason only: the redirect itself may hold a code.
        Log.w("OAuth redirect refused: ${e.failure.name}");
        return LoginResultError(messageForCallbackFailure(e.failure));
      }

      return await finish(session, code);
    } on ReauthenticationMismatch {
      rethrow;
    } on matrix.OidcClientRegistrationException {
      return LoginResultError(errorLoginOauthNoClientRegistration);
    } on matrix.MatrixException catch (e) {
      return LoginResultError(e.errorMessage);
    } catch (e, s) {
      Log.onError(e, s, content: "OAuth sign-in failed");
      return LoginResultError(errorLoginOauthFailed);
    } finally {
      await receiver.close();
    }
  }
}
