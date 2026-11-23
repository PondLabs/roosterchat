// OAuth 2.0 sign-in on an OAuth-only homeserver (MAS): discovery keeps the
// server's auth_metadata and offers the OAuth buttons, the authorization URL
// carries PKCE and prompt=create only when it should, and a redirect with a
// wrong or missing state, or an error, signs nothing in.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'oidc_fakes.dart';

Future<(MatrixClient, OAuthOnlyServer, List<MatrixOidcLoginFlow>)> discover(
  Map<String, Object?>? metadata, {
  http.Response? loginAnswer,
}) async {
  final server = OAuthOnlyServer(metadata: metadata, loginAnswer: loginAnswer);
  final client = await newAccount(server);
  final (ok, flows) = await client.setHomeserver(Uri.https(homeserverHost));
  expect(ok, isTrue, reason: 'the homeserver check passes');
  return (client, server, flows!.whereType<MatrixOidcLoginFlow>().toList());
}

String s256(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

void main() {
  group('discovery on an OAuth-only server', () {
    test('passes with /v3/login 404, keeps authMetadata, offers OAuth',
        () async {
      final (client, server, oidc) = await discover(authMetadataJson());

      expect(client.authMetadata, isNotNull);
      expect(client.authMetadata!.authorizationEndpoint.toString(),
          authorizationEndpoint);
      expect(oidc, hasLength(1));
      expect(oidc.single.createAccount, isFalse);
      expect(oidc.single.serverName, homeserverHost);
      expect(identical(oidc.single.authMetadata, client.authMetadata), isTrue);
      expect(
        server.requests.map((r) => r.url.path),
        containsAllInOrder([
          '/_matrix/client/v1/auth_metadata',
          '/_matrix/client/v3/login',
        ]),
      );
    });

    test('also passes when /v3/login lists no flows', () async {
      final (client, _, oidc) = await discover(
        authMetadataJson(),
        loginAnswer: http.Response(jsonEncode({'flows': []}), 200),
      );
      expect(client.authMetadata, isNotNull);
      expect(oidc, hasLength(1));
    });

    test('password stays next to OAuth when the server still offers it',
        () async {
      final server = OAuthOnlyServer(
        metadata: authMetadataJson(),
        loginAnswer: http.Response(
            jsonEncode({
              'flows': [
                {'type': 'm.login.password'}
              ]
            }),
            200),
      );
      final client = await newAccount(server);
      final (ok, flows) = await client.setHomeserver(Uri.https(homeserverHost));
      expect(ok, isTrue);
      expect(flows!.whereType<MatrixOidcLoginFlow>(), hasLength(1));
      expect(flows.whereType<MatrixPasswordLoginFlow>(), hasLength(1));
    });

    test('a create button only when prompt_values_supported has create',
        () async {
      final (_, _, withCreate) =
          await discover(authMetadataJson(prompts: ['create']));
      expect(withCreate.map((f) => f.createAccount), [false, true]);

      final (_, _, withoutCreate) =
          await discover(authMetadataJson(prompts: ['login']));
      expect(withoutCreate.map((f) => f.createAccount), [false]);
    });

    test('no auth_metadata and no login flows is not a valid server', () async {
      final server = OAuthOnlyServer();
      final client = await newAccount(server);
      final (ok, flows) = await client.setHomeserver(Uri.https(homeserverHost));
      expect(ok, isFalse);
      expect(flows, isNull);
      expect(client.authMetadata, isNull);
    });
  });

  group('the OAuth sign-in', skip: skipWithoutVodozemac, () {
    setUpAll(initVodozemac);

    Uri? echoState(Uri authorizationUri, Map<String, String> extra) =>
        redirectWith(
          Uri.parse(authorizationUri.queryParameters['redirect_uri']!),
          {'state': authorizationUri.queryParameters['state']!, ...extra},
        );

    test('PKCE S256, scopes, DCR and the token exchange', () async {
      final (client, server, oidc) = await discover(authMetadataJson(scopes: [
        'openid',
        'urn:matrix:client:api:*',
        'urn:matrix:client:device:*',
      ]));
      final receiver =
          FakeRedirectReceiver((uri) => echoState(uri, {'code': 'c0de'}));
      final flow = MatrixOidcLoginFlow(
        authMetadata: oidc.single.authMetadata,
        serverName: homeserverHost,
        receiverFactory: ({required landingPage}) async => receiver,
      );

      final result = await flow.submit(client);

      expect(result, isA<LoginResultSuccess>());
      expect(receiver.closed, isTrue);
      final authorization = receiver.opened.single.queryParameters;
      expect(authorization['client_id'], 'dcr-client-01');
      expect(authorization['code_challenge_method'], 'S256');
      expect(authorization['response_type'], 'code');
      expect(authorization['redirect_uri'], receiver.redirectUri.toString());
      final scopes = authorization['scope']!.split(' ');
      expect(scopes, contains('urn:matrix:client:api:*'));
      expect(
        scopes.where((s) => s.startsWith('urn:matrix:client:device:')),
        hasLength(1),
      );
      expect(authorization.containsKey('prompt'), isFalse);

      final registration = jsonDecode(server.registrationRequests.single.body);
      expect(registration['redirect_uris'], [receiver.redirectUri.toString()]);
      expect(registration['application_type'], 'native');

      final token = server.tokenRequests.single.bodyFields;
      expect(token['grant_type'], 'authorization_code');
      expect(token['code'], 'c0de');
      expect(token['client_id'], 'dcr-client-01');
      expect(token['redirect_uri'], receiver.redirectUri.toString());
      expect(s256(token['code_verifier']!), authorization['code_challenge']);
      expect(client.getMatrixClient().isLogged(), isTrue);
      expect(client.getMatrixClient().accessToken, 'at-c0de');
    });

    test('CIMD: the document URL is the client_id, nothing is registered',
        () async {
      final (client, server, oidc) =
          await discover(authMetadataJson(cimd: true));
      final receiver = FakeRedirectReceiver((uri) => null);
      final document =
          Uri.parse('https://rooster.example/oauth/client-metadata.json');
      final flow = MatrixOidcLoginFlow(
        authMetadata: oidc.single.authMetadata,
        serverName: homeserverHost,
        clientMetadataDocumentUri: document,
        receiverFactory: ({required landingPage}) async => receiver,
      );

      expect(await flow.submit(client), isA<LoginResultCancelled>());
      expect(receiver.opened.single.queryParameters['client_id'],
          document.toString());
      expect(server.registrationRequests, isEmpty);
    });

    test('DCR when the server does not take metadata documents', () async {
      final (client, server, oidc) =
          await discover(authMetadataJson(cimd: false));
      final receiver = FakeRedirectReceiver((uri) => null);
      final flow = MatrixOidcLoginFlow(
        authMetadata: oidc.single.authMetadata,
        serverName: homeserverHost,
        clientMetadataDocumentUri:
            Uri.parse('https://rooster.example/oauth/client-metadata.json'),
        receiverFactory: ({required landingPage}) async => receiver,
      );
      await flow.submit(client);
      expect(
          receiver.opened.single.queryParameters['client_id'], 'dcr-client-01');
      expect(server.registrationRequests, hasLength(1));
    });

    group('prompt=create', () {
      Future<Uri> authorizationFor({
        required List<String>? prompts,
        required bool createAccount,
      }) async {
        final (client, _, oidc) =
            await discover(authMetadataJson(prompts: prompts));
        final receiver = FakeRedirectReceiver((uri) => null);
        final flow = MatrixOidcLoginFlow(
          authMetadata: oidc.first.authMetadata,
          serverName: homeserverHost,
          createAccount: createAccount,
          receiverFactory: ({required landingPage}) async => receiver,
        );
        await flow.submit(client);
        return receiver.opened.single;
      }

      test('the create button sends prompt=create when announced', () async {
        final uri =
            await authorizationFor(prompts: ['create'], createAccount: true);
        expect(uri.queryParameters['prompt'], 'create');
      });

      test('the sign-in button never sends it', () async {
        final uri =
            await authorizationFor(prompts: ['create'], createAccount: false);
        expect(uri.queryParameters.containsKey('prompt'), isFalse);
      });

      test('not sent when the server does not announce create', () async {
        for (final prompts in [
          null,
          <String>['login']
        ]) {
          final uri =
              await authorizationFor(prompts: prompts, createAccount: true);
          expect(uri.queryParameters.containsKey('prompt'), isFalse);
        }
      });
    });

    group('a refused redirect signs nothing in', () {
      Future<void> expectRefused(
        Uri? Function(Uri authorizationUri) answer,
        String message,
      ) async {
        final (client, server, oidc) = await discover(authMetadataJson());
        final receiver = FakeRedirectReceiver(answer);
        final flow = MatrixOidcLoginFlow(
          authMetadata: oidc.single.authMetadata,
          serverName: homeserverHost,
          receiverFactory: ({required landingPage}) async => receiver,
        );

        final result = await flow.submit(client);

        expect(result, isA<LoginResultError>());
        expect((result as LoginResultError).errorMessage, message);
        expect(server.tokenRequests, isEmpty);
        expect(client.getMatrixClient().isLogged(), isFalse);
        expect(client.getMatrixClient().accessToken, isNull);
        expect(receiver.closed, isTrue);
      }

      test('a different state', () async {
        await expectRefused(
          (uri) => redirectWith(
            Uri.parse(uri.queryParameters['redirect_uri']!),
            {'code': 'c0de', 'state': 'forged'},
          ),
          MatrixOidcLoginFlow.errorLoginOauthStateMismatch,
        );
      });

      test('no state', () async {
        await expectRefused(
          (uri) => redirectWith(
            Uri.parse(uri.queryParameters['redirect_uri']!),
            {'code': 'c0de'},
          ),
          MatrixOidcLoginFlow.errorLoginOauthStateMismatch,
        );
      });

      test('error=access_denied', () async {
        await expectRefused(
          (uri) => echoState(uri, {'error': 'access_denied'}),
          MatrixOidcLoginFlow.errorLoginOauthAccessDenied,
        );
      });

      test('another error', () async {
        await expectRefused(
          (uri) => echoState(uri, {'error': 'server_error'}),
          MatrixOidcLoginFlow.errorLoginOauthFailed,
        );
      });
    });
  });
}
