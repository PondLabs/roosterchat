import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'oidc_redirect_receiver.dart';

Future<OidcRedirectReceiver> startOidcLoopbackReceiver({
  required OidcLandingPage landingPage,
}) =>
    OidcLoopbackReceiver.start(landingPage: landingPage);

/// The desktop's redirect target (RFC 8252 §7.3): an HTTP server on
/// `127.0.0.1` on a port the system picks, for one sign-in. Only a GET on
/// [callbackPath] counts; anything else (a favicon, a probe) gets a 404.
class OidcLoopbackReceiver implements OidcRedirectReceiver {
  OidcLoopbackReceiver._(
      this._server, this._landingPage, this._openBrowser, this._timeout)
      : redirectUri = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: _server.port,
          path: callbackPath,
        );

  static const String callbackPath = '/callback';

  /// How long the sign-in page may stay open before the attempt is dropped.
  static const Duration defaultTimeout = Duration(minutes: 10);

  static Future<OidcLoopbackReceiver> start({
    required OidcLandingPage landingPage,
    Future<bool> Function(Uri uri)? openBrowser,
    Duration timeout = defaultTimeout,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return OidcLoopbackReceiver._(
      server,
      landingPage,
      openBrowser ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
      timeout,
    );
  }

  final HttpServer _server;
  final OidcLandingPage _landingPage;
  final Future<bool> Function(Uri uri) _openBrowser;
  final Duration _timeout;
  StreamSubscription<HttpRequest>? _requests;

  @override
  final Uri redirectUri;

  @override
  Future<Uri?> authorize(Uri authorizationUri) async {
    final redirect = Completer<Uri?>();
    _requests = _server.listen((request) async {
      final isCallback = request.method == 'GET' &&
          request.uri.path == callbackPath &&
          !redirect.isCompleted;
      if (!isCallback) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final params = request.uri.queryParameters;
      final ok = params['error'] == null && (params['code'] ?? '').isNotEmpty;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('cache-control', 'no-store');
      request.response.write(_landingPage(ok));
      await request.response.close();
      // Built from our own redirect URI, not from the Host header.
      redirect.complete(redirectUri.replace(query: request.uri.query));
    });

    if (!await _openBrowser(authorizationUri)) return null;
    return redirect.future.timeout(_timeout, onTimeout: () => null);
  }

  @override
  Future<void> close() async {
    await _requests?.cancel();
    await _server.close(force: true);
  }
}
