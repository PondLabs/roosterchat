import 'dart:convert';
import 'dart:ui' as ui;

import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/custom_uri.dart';
import 'package:rooster/utils/language/app_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:intl/intl.dart';

import 'package:universal_html/html.dart' as html;
import 'package:matrix/matrix.dart' as matrix;

class MatrixSSOLoginFlow implements SsoLoginFlow {
  static String get errorLoginWrongClientType =>
      Intl.message("Attempted to login with the wrong type of client",
          name: "errorLoginWrongClientType",
          desc: "In the 'Login failed' dialog if single sign-on was started "
              "for an account of another kind than Matrix; should never "
              "happen");

  static String get labelLoginSsoDoneTitle => Intl.message("Signed in",
      name: "labelLoginSsoDoneTitle",
      desc: "Title of the page the browser shows once single sign-on is done "
          "and the app has the login, in the system browser on desktop");

  static String get labelLoginSsoDone => Intl.message(
      "You're signed in. You can close this page and go back to Rooster.",
      name: "labelLoginSsoDone",
      desc: "The page the browser shows once single sign-on is done and the "
          "app has the login, in the system browser on desktop");

  /// The page the system browser shows when single sign-on hands the login
  /// back (desktop), in the app's language.
  static String _landingPage() {
    const escape = HtmlEscape();
    return '''
<!DOCTYPE html>
<html lang="${AppLanguage.current.value.tag}">
<head>
  <meta charset="utf-8">
  <title>${escape.convert(labelLoginSsoDoneTitle)}</title>
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
  <main><p>${escape.convert(labelLoginSsoDone)}</p></main>
</body>
</html>
''';
  }

  @override
  String? id;
  String? brand;

  @override
  ImageProvider<Object>? icon;

  @override
  String name;

  MatrixSSOLoginFlow({this.id, required this.name, this.icon, this.brand});

  factory MatrixSSOLoginFlow.fromJson(
      MatrixClient client, Map<String, dynamic> json) {
    final rawIcon = json['icon'];
    final iconUri =
        rawIcon is String && rawIcon.isNotEmpty ? Uri.tryParse(rawIcon) : null;
    return MatrixSSOLoginFlow(
      id: json['id'],
      name: json['name'],
      icon: iconUri != null ? getLoginFlowImage(iconUri, client) : null,
      brand: json['brand'],
    );
  }

  static ImageProvider<Object>? getLoginFlowImage(
      Uri iconUri, MatrixClient client) {
    if (iconUri.scheme == 'mxc') {
      if (iconUri.authority.isEmpty ||
          iconUri.pathSegments.isEmpty ||
          iconUri.pathSegments.first.isEmpty ||
          client.getMatrixClient().baseUri == null) {
        return null;
      }
      return MatrixSsoIconImageProvider(iconUri, client);
    }
    if (iconUri.scheme == 'https' || iconUri.scheme == 'http') {
      return MatrixSsoIconImageProvider(iconUri, client);
    }
    return null;
  }

  /// Resolves SSO identity provider icon bytes using authenticated media
  /// (`/_matrix/client/v1/media/thumbnail/...`) on v1.11+ servers when an
  /// access token is available, or falling back safely to `null` when
  /// `/_matrix/media/v3/thumbnail` returns 404/401 or fails.
  static Future<Uint8List?> resolveIconBytes(
    Uri iconUri,
    MatrixClient client,
  ) async {
    final mx = client.getMatrixClient();
    try {
      if (iconUri.scheme == 'https' || iconUri.scheme == 'http') {
        final response = await mx.httpClient.get(iconUri);
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
        return null;
      }

      if (iconUri.scheme != 'mxc') return null;
      final serverName = iconUri.authority;
      final mediaId =
          iconUri.pathSegments.isNotEmpty ? iconUri.pathSegments.first : '';
      final baseUri = mx.baseUri;
      if (serverName.isEmpty || mediaId.isEmpty || baseUri == null) {
        return null;
      }

      var authedMedia = false;
      try {
        authedMedia = await mx.authenticatedMediaSupported();
      } catch (_) {}

      final hasToken = mx.accessToken != null && mx.accessToken!.isNotEmpty;
      if (authedMedia && hasToken) {
        final file = await mx.getContentThumbnailAuthed(
          serverName,
          mediaId,
          96,
          96,
          method: matrix.Method.crop,
        );
        return file.data.isNotEmpty ? file.data : null;
      }

      final fallbackUri = baseUri.resolveUri(
        Uri(
          pathSegments: [
            '_matrix',
            'media',
            'v3',
            'thumbnail',
            serverName,
            mediaId,
          ],
          queryParameters: const {
            'width': '96',
            'height': '96',
            'method': 'crop',
          },
        ),
      );
      final response = await mx.httpClient.get(fallbackUri);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(errorLoginWrongClientType);
    }

    try {
      var mx = client.getMatrixClient();
      final token = await obtainLoginToken(mx);
      if (token == null) return LoginResultFailed();

      var login = await mx.login(
        matrix.LoginType.mLoginToken,
        token: token,
        // Renewed on its own later (MatrixTokenRefresher).
        refreshToken: true,
      );

      if (login.accessToken.isNotEmpty) {
        return LoginResultSuccess();
      } else {
        return LoginResultFailed();
      }
    } catch (e, t) {
      Log.onError(e, t);
      // I didn't spell this wrong, its just like that in flutter_web_auth_2
      if (e is PlatformException && e.code == "CANCELED") {
        return LoginResultCancelled();
      }
      return LoginResultError(e.toString());
    }
  }

  /// Opens the server's single sign-on page and returns the `loginToken` it
  /// hands back, or null without one. Signing the same device in again
  /// after a refused renewal uses it too. Throws a [PlatformException] with
  /// the code `CANCELED` when the person closes the page.
  Future<String?> obtainLoginToken(matrix.Client mx) async {
    String redirectUrl = SsoLoginUri().toString();

    if (PlatformUtils.isWeb) {
      redirectUrl =
          Uri.parse(html.window.location.href).resolve("auth.html").toString();
    }

    String callbackScheme = Uri.parse(redirectUrl).scheme;

    // https://github.com/ThexXTURBOXx/flutter_web_auth_2/blob/2b67cb9674c7d3228de4f5728a73b09ae6598cf9/flutter_web_auth_2/README.md#windows-and-linux
    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      redirectUrl = "http://localhost:3001/login";
      callbackScheme = "http://localhost:3001";
    }

    final url = mx.homeserver!.replace(
      path: '/_matrix/client/v3/login/sso/redirect${id == null ? '' : '/$id'}',
      queryParameters: {'redirectUrl': redirectUrl},
    );

    final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackScheme,
        options: FlutterWebAuth2Options(
          useWebview: false,
          landingPageHtml: _landingPage(),
        ));

    final token = Uri.parse(result).queryParameters['loginToken'];
    return token == null || token.isEmpty ? null : token;
  }
}

/// Loads an SSO identity provider icon through [MatrixSSOLoginFlow] and falls
/// back to a 1x1 transparent PNG when the icon cannot be fetched or decoded.
class MatrixSsoIconImageProvider
    extends ImageProvider<MatrixSsoIconImageProvider> {
  const MatrixSsoIconImageProvider(this.uri, this.client);

  final Uri uri;
  final MatrixClient client;

  static final Uint8List _transparentFallbackPng = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    ),
  );

  @override
  Future<MatrixSsoIconImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture<MatrixSsoIconImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    MatrixSsoIconImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel: uri.toString(),
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final bytes = await MatrixSSOLoginFlow.resolveIconBytes(uri, client);
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      } catch (_) {}
    }
    final fallback =
        await ui.ImmutableBuffer.fromUint8List(_transparentFallbackPng);
    return decode(fallback);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixSsoIconImageProvider &&
          other.uri == uri &&
          identical(other.client, client);

  @override
  int get hashCode => Object.hash(uri, identityHashCode(client));
}
