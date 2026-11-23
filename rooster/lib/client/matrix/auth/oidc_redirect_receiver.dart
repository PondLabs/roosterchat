import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:rooster/config/platform_utils.dart';

import 'oidc_loopback_receiver_stub.dart'
    if (dart.library.io) 'oidc_loopback_receiver_io.dart';

/// Where the authorization server sends the browser back after an OAuth 2.0
/// sign-in, and how the app gets that redirect.
abstract class OidcRedirectReceiver {
  /// The `redirect_uri` to register and to send with the authorization
  /// request.
  Uri get redirectUri;

  /// Opens [authorizationUri] in the browser and completes with the URL the
  /// server redirected to, or null when the person gave up.
  Future<Uri?> authorize(Uri authorizationUri);

  /// Frees whatever the receiver holds (the loopback port).
  Future<void> close();
}

/// The page the browser shows once it is back from the sign-in page; [ok] is
/// false when the redirect carries an error or no code.
typedef OidcLandingPage = String Function(bool ok);

/// The receiver for this platform: the web app's `auth.html` in a browser,
/// a loopback server on `127.0.0.1` on desktop.
Future<OidcRedirectReceiver> createOidcRedirectReceiver({
  required OidcLandingPage landingPage,
}) async {
  if (PlatformUtils.isWeb) return OidcWebRedirectReceiver();
  return startOidcLoopbackReceiver(landingPage: landingPage);
}

/// In a browser: the authorization server redirects to `auth.html` next to
/// the app, which hands the URL back to the app's window (flutter_web_auth_2).
class OidcWebRedirectReceiver implements OidcRedirectReceiver {
  OidcWebRedirectReceiver({Uri? appUri})
      // Resolving drops the page's query and fragment (the app's route).
      : redirectUri = (appUri ?? Uri.base).resolve('auth.html');

  @override
  final Uri redirectUri;

  @override
  Future<Uri?> authorize(Uri authorizationUri) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authorizationUri.toString(),
        callbackUrlScheme: redirectUri.scheme,
      );
      return Uri.parse(result);
    } on PlatformException catch (e) {
      // Spelled like that in flutter_web_auth_2.
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {}
}
