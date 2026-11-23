import 'oidc_redirect_receiver.dart';

/// No loopback server where there is no `dart:io` (the web build uses
/// [OidcWebRedirectReceiver]).
Future<OidcRedirectReceiver> startOidcLoopbackReceiver({
  required OidcLandingPage landingPage,
}) =>
    throw UnsupportedError('No loopback redirect receiver on this platform');
