import 'dart:convert';

import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/custom_uri.dart';
import 'package:rooster/utils/language/app_language.dart';
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
          MatrixClient client, Map<String, dynamic> json) =>
      MatrixSSOLoginFlow(
        id: json['id'],
        name: json['name'],
        icon: json['icon'] != null
            ? getLoginFlowImage(
                Uri.parse(
                  json['icon'],
                ),
                client,
              )
            : null,
        brand: json['brand'],
      );

  static NetworkImage getLoginFlowImage(Uri mxc, MatrixClient client) {
    var path =
        '_matrix/media/v3/thumbnail/${Uri.encodeComponent(mxc.authority)}/${Uri.encodeComponent(mxc.pathSegments.first)}';

    var server = client.getMatrixClient().baseUri!;
    var request =
        server.replace(path: path, query: "width=96&height=96&method=crop");
    return NetworkImage(request.toString());
  }

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(errorLoginWrongClientType);
    }

    try {
      var mx = client.getMatrixClient();

      String redirectUrl = SsoLoginUri().toString();

      if (PlatformUtils.isWeb) {
        redirectUrl = Uri.parse(html.window.location.href)
            .resolve("auth.html")
            .toString();
      }

      String callbackScheme = Uri.parse(redirectUrl).scheme;

      // https://github.com/ThexXTURBOXx/flutter_web_auth_2/blob/2b67cb9674c7d3228de4f5728a73b09ae6598cf9/flutter_web_auth_2/README.md#windows-and-linux
      if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
        redirectUrl = "http://localhost:3001/login";
        callbackScheme = "http://localhost:3001";
      }

      final url = mx.homeserver!.replace(
        path:
            '/_matrix/client/v3/login/sso/redirect${id == null ? '' : '/$id'}',
        queryParameters: {'redirectUrl': redirectUrl},
      );

      final result = await FlutterWebAuth2.authenticate(
          url: url.toString(),
          callbackUrlScheme: callbackScheme,
          options: FlutterWebAuth2Options(
            useWebview: false,
            landingPageHtml: _landingPage(),
          ));

      var token = Uri.parse(result).queryParameters['loginToken'];
      if (token?.isEmpty ?? false) {
        return LoginResultFailed();
      }

      var login = await mx.login(
        matrix.LoginType.mLoginToken,
        token: token,
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
}
