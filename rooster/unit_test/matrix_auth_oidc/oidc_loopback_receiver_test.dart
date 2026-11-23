// The desktop's loopback redirect target, on a real HttpServer bound to
// 127.0.0.1: what a browser sending the person back would do. Kept apart
// from widget tests, whose binding answers every HttpClient call with 400.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/client/matrix/auth/oidc_loopback_receiver_io.dart';

import 'oidc_fakes.dart';

/// A browser: GETs [uri] on the loopback server, returns status and page.
Future<(int, String)> browse(Uri uri) =>
    HttpOverrides.runWithHttpOverrides(() => _browse(uri), RealHttpOverrides());

Future<(int, String)> _browse(Uri uri) async {
  final http = HttpClient();
  try {
    final request = await http.getUrl(uri);
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    http.close(force: true);
  }
}

void main() {
  test('binds 127.0.0.1 on a free port with a /callback redirect', () async {
    final receiver = await OidcLoopbackReceiver.start(
      landingPage: (ok) => ok ? 'ok' : 'failed',
      openBrowser: (_) async => true,
    );
    addTearDown(receiver.close);
    expect(receiver.redirectUri.scheme, 'http');
    expect(receiver.redirectUri.host, '127.0.0.1');
    expect(receiver.redirectUri.port, greaterThan(0));
    expect(receiver.redirectUri.path, '/callback');
  });

  test('hands back the callback, ignores other paths', () async {
    late (int, String) favicon, callback;
    final receiver = await OidcLoopbackReceiver.start(
      landingPage: (ok) => ok ? 'page-ok' : 'page-failed',
      openBrowser: (authorizationUri) async {
        final redirect = Uri.parse(
          authorizationUri.queryParameters['redirect_uri']!,
        );
        favicon = await browse(redirect.replace(path: '/favicon.ico'));
        callback = await browse(
          redirect.replace(queryParameters: {'code': 'c', 'state': 's'}),
        );
        return true;
      },
    );
    addTearDown(receiver.close);
    final authorization = Uri.https('auth.example.org', '/authorize', {
      'redirect_uri': receiver.redirectUri.toString(),
    });

    final redirect = await receiver.authorize(authorization);

    expect(favicon.$1, HttpStatus.notFound);
    expect(callback, (HttpStatus.ok, 'page-ok'));
    expect(redirect!.path, '/callback');
    expect(redirect.host, '127.0.0.1');
    expect(redirect.queryParameters, {'code': 'c', 'state': 's'});
  });

  test('an error redirect shows the failure page', () async {
    late (int, String) page;
    final receiver = await OidcLoopbackReceiver.start(
      landingPage: (ok) => ok ? 'page-ok' : 'page-failed',
      openBrowser: (uri) async {
        page = await browse(
          Uri.parse(uri.queryParameters['redirect_uri']!)
              .replace(queryParameters: {'error': 'access_denied'}),
        );
        return true;
      },
    );
    addTearDown(receiver.close);
    await receiver.authorize(Uri.https('auth.example.org', '/authorize', {
      'redirect_uri': receiver.redirectUri.toString(),
    }));
    expect(page.$2, 'page-failed');
  });

  test('no browser means no sign-in', () async {
    final receiver = await OidcLoopbackReceiver.start(
      landingPage: (ok) => '',
      openBrowser: (_) async => false,
    );
    addTearDown(receiver.close);
    expect(
      await receiver.authorize(Uri.https('auth.example.org', '/authorize')),
      isNull,
    );
  });

  test('the port is freed on close', () async {
    final receiver = await OidcLoopbackReceiver.start(
      landingPage: (ok) => '',
      openBrowser: (_) async => true,
    );
    await receiver.close();
    await expectLater(
      browse(receiver.redirectUri),
      throwsA(isA<SocketException>()),
    );
  });

  group('the sign-in through the loopback', skip: skipWithoutVodozemac, () {
    setUpAll(initVodozemac);

    for (final (name, params, message) in [
      (
        'error=access_denied',
        (String state) => {'error': 'access_denied', 'state': state},
        () => MatrixOidcLoginFlow.errorLoginOauthAccessDenied,
      ),
      (
        'a different state',
        (String state) => {'code': 'c0de', 'state': 'forged'},
        () => MatrixOidcLoginFlow.errorLoginOauthStateMismatch,
      ),
      (
        'no state',
        (String state) => {'code': 'c0de'},
        () => MatrixOidcLoginFlow.errorLoginOauthStateMismatch,
      ),
    ]) {
      test('$name is refused with no session stored', () async {
        final server = OAuthOnlyServer(metadata: authMetadataJson());
        final client = await newAccount(server);
        final (ok, _) = await client.setHomeserver(Uri.https(homeserverHost));
        expect(ok, isTrue);

        late (int, String) page;
        final flow = MatrixOidcLoginFlow(
          authMetadata: client.authMetadata!,
          serverName: homeserverHost,
          receiverFactory: ({required landingPage}) =>
              OidcLoopbackReceiver.start(
            landingPage: landingPage,
            openBrowser: (authorizationUri) async {
              final query = authorizationUri.queryParameters;
              page = await browse(
                Uri.parse(query['redirect_uri']!).replace(
                  queryParameters: params(query['state']!),
                ),
              );
              return true;
            },
          ),
        );

        final result = await flow.submit(client);

        expect(result, isA<LoginResultError>());
        expect((result as LoginResultError).errorMessage, message());
        expect(page.$1, HttpStatus.ok);
        expect(server.tokenRequests, isEmpty);
        expect(client.getMatrixClient().isLogged(), isFalse);
        expect(client.getMatrixClient().accessToken, isNull);
      });
    }
  });
}
