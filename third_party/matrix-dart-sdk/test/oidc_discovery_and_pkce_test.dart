// ROOSTER: discovery (`.well-known` 30x, MSC4402), `auth_metadata` before
// `/v3/login`, and the OAuth 2.0 Authorization Code + PKCE pieces (scopes,
// CIMD/DCR, `prompt=create`, redirect validation). Everything runs against a
// MockClient: no network.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

const _wellKnownPath = '/.well-known/matrix/client';

Map<String, Object?> _authMetadataJson({
  List<String>? scopes,
  bool? cimd,
  bool withRegistration = true,
  List<String>? prompts,
}) =>
    {
      'issuer': 'https://auth.example.org/',
      'authorization_endpoint': 'https://auth.example.org/authorize',
      'token_endpoint': 'https://auth.example.org/oauth2/token',
      if (withRegistration)
        'registration_endpoint': 'https://auth.example.org/oauth2/registration',
      'revocation_endpoint': 'https://auth.example.org/oauth2/revoke',
      'response_types_supported': ['code'],
      'response_modes_supported': ['query', 'fragment'],
      'grant_types_supported': ['authorization_code', 'refresh_token'],
      'code_challenge_methods_supported': ['S256'],
      if (scopes != null) 'scopes_supported': scopes,
      if (cimd != null) 'client_id_metadata_document_supported': cimd,
      if (prompts != null) 'prompt_values_supported': prompts,
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _redirect(int status, String location) =>
    http.Response('', status, headers: {'location': location});

Future<Client> _client(
  Future<http.Response> Function(http.Request) handler,
) async =>
    Client(
      'oidc_test',
      httpClient: MockClient(handler),
      database: await getDatabase(),
    );

/// A homeserver at `https://matrix.example.org` with v1.15 and OAuth.
Future<http.Response> _homeserver(
  http.Request request, {
  Map<String, Object?>? authMetadata,
  http.Response? login,
}) async {
  if (request.url.host != 'matrix.example.org') {
    return http.Response('not here', 404);
  }
  switch (request.url.path) {
    case '/_matrix/client/versions':
      return _json({
        'versions': ['v1.11', 'v1.15'],
      });
    case '/_matrix/client/v1/auth_metadata':
      return authMetadata == null
          ? _json({'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'}, 404)
          : _json(authMetadata);
    case '/_matrix/client/v3/login':
      return login ??
          _json({
            'flows': [
              {'type': 'm.login.password'},
            ],
          });
  }
  return http.Response('not found', 404);
}

const _wellKnownBody = {
  'm.homeserver': {'base_url': 'https://matrix.example.org'},
};

void main() {
  group('.well-known 30x (MSC4402)', () {
    test('301 then 308 are followed and resolve the homeserver', () async {
      final seen = <Uri>[];
      final client = await _client((request) async {
        seen.add(request.url);
        if (request.url.toString() == 'https://example.org$_wellKnownPath') {
          expect(request.followRedirects, isFalse);
          return _redirect(301, 'https://www.example.org$_wellKnownPath');
        }
        if (request.url.toString() ==
            'https://www.example.org$_wellKnownPath') {
          // Relative Location, resolved against the URL it came from.
          return _redirect(308, '/discovery/client.json');
        }
        if (request.url.toString() ==
            'https://www.example.org/discovery/client.json') {
          return _json(_wellKnownBody);
        }
        return _homeserver(request);
      });

      final result = await client.checkHomeserver(Uri.https('example.org'));

      expect(
        result.$1?.mHomeserver.baseUrl,
        Uri.parse('https://matrix.example.org'),
      );
      expect(client.homeserver, Uri.parse('https://matrix.example.org'));
      expect(client.baseUri, Uri.parse('https://matrix.example.org'));
      expect(seen.take(3).map((u) => u.toString()), [
        'https://example.org$_wellKnownPath',
        'https://www.example.org$_wellKnownPath',
        'https://www.example.org/discovery/client.json',
      ]);
    });

    test('302 and 307 are followed too', () async {
      final client = await _client((request) async {
        final url = request.url.toString();
        if (url == 'https://example.org$_wellKnownPath') {
          return _redirect(302, 'https://a.example.org/wk');
        }
        if (url == 'https://a.example.org/wk') {
          return _redirect(307, 'https://b.example.org/wk');
        }
        if (url == 'https://b.example.org/wk') return _json(_wellKnownBody);
        return _homeserver(request);
      });
      await client.checkHomeserver(Uri.https('example.org'));
      expect(client.homeserver, Uri.parse('https://matrix.example.org'));
    });

    test('exactly five redirects still resolve', () async {
      final client = await _client((request) async {
        final url = request.url.toString();
        if (url == 'https://example.org$_wellKnownPath') {
          return _redirect(301, 'https://example.org/hop/1');
        }
        final hop = RegExp(r'/hop/(\d+)$').firstMatch(url);
        if (hop != null) {
          final n = int.parse(hop.group(1)!);
          return n < 5
              ? _redirect(301, 'https://example.org/hop/${n + 1}')
              : _json(_wellKnownBody);
        }
        return _homeserver(request);
      });
      await client.checkHomeserver(Uri.https('example.org'));
      expect(client.homeserver, Uri.parse('https://matrix.example.org'));
    });

    test('more than five redirects fail explicitly', () async {
      final client = await _client((request) async {
        final url = request.url.toString();
        if (url == 'https://example.org$_wellKnownPath') {
          return _redirect(301, 'https://example.org/hop/1');
        }
        final hop = RegExp(r'/hop/(\d+)$').firstMatch(url);
        if (hop != null) {
          return _redirect(
            308,
            'https://example.org/hop/${int.parse(hop.group(1)!) + 1}',
          );
        }
        return _homeserver(request);
      });
      await expectLater(
        client.checkHomeserver(Uri.https('example.org')),
        throwsA(
          isA<WellKnownRedirectException>().having(
            (e) => e.failure,
            'failure',
            WellKnownRedirectFailure.tooManyRedirects,
          ),
        ),
      );
      expect(client.homeserver, isNull);
    });

    test('a redirect loop fails explicitly', () async {
      final client = await _client((request) async {
        final url = request.url.toString();
        if (url == 'https://example.org$_wellKnownPath') {
          return _redirect(301, 'https://www.example.org$_wellKnownPath');
        }
        if (url == 'https://www.example.org$_wellKnownPath') {
          return _redirect(302, 'https://example.org$_wellKnownPath');
        }
        return _homeserver(request);
      });
      await expectLater(
        client.checkHomeserver(Uri.https('example.org')),
        throwsA(
          isA<WellKnownRedirectException>().having(
            (e) => e.failure,
            'failure',
            WellKnownRedirectFailure.loop,
          ),
        ),
      );
      expect(client.homeserver, isNull);
    });

    for (final target in [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'matrix:r/room:example.org',
    ]) {
      test('a redirect to $target fails explicitly', () async {
        var followed = false;
        final client = await _client((request) async {
          if (request.url.toString() == 'https://example.org$_wellKnownPath') {
            return _redirect(301, target);
          }
          if (request.url.scheme != 'https') followed = true;
          return _homeserver(request);
        });
        await expectLater(
          client.checkHomeserver(Uri.https('example.org')),
          throwsA(
            isA<WellKnownRedirectException>().having(
              (e) => e.failure,
              'failure',
              WellKnownRedirectFailure.unsupportedScheme,
            ),
          ),
        );
        expect(followed, isFalse);
        expect(client.homeserver, isNull);
      });
    }

    test('a redirect without Location fails explicitly', () async {
      final client = await _client((request) async {
        if (request.url.toString() == 'https://example.org$_wellKnownPath') {
          return http.Response('', 302);
        }
        return _homeserver(request);
      });
      await expectLater(
        client.checkHomeserver(Uri.https('example.org')),
        throwsA(
          isA<WellKnownRedirectException>().having(
            (e) => e.failure,
            'failure',
            WellKnownRedirectFailure.missingLocation,
          ),
        ),
      );
    });

    test('a missing well-known file is still ignored', () async {
      final client = await _client((request) async {
        if (request.url.host == 'matrix.example.org' &&
            request.url.path == _wellKnownPath) {
          return http.Response('nope', 404);
        }
        return _homeserver(request);
      });
      final result =
          await client.checkHomeserver(Uri.https('matrix.example.org'));
      expect(result.$1, isNull);
      expect(client.homeserver, Uri.parse('https://matrix.example.org'));
    });
  });

  group('auth_metadata before /v3/login', () {
    test('an OAuth-only server whose /v3/login is 404 passes', () async {
      final requested = <String>[];
      final client = await _client((request) async {
        requested.add(request.url.path);
        return _homeserver(
          request,
          authMetadata: _authMetadataJson(),
          login: http.Response('<html>Not Found</html>', 404),
        );
      });

      final result = await client.checkHomeserver(
        Uri.https('matrix.example.org'),
        checkWellKnown: false,
      );

      expect(result.$3, isEmpty);
      expect(
        result.$4?.authorizationEndpoint,
        Uri.parse('https://auth.example.org/authorize'),
      );
      expect(result.$4?.supportsAuthorizationCodeWithPkce, isTrue);
      expect(client.homeserver, Uri.parse('https://matrix.example.org'));
      expect(
        requested.indexOf('/_matrix/client/v1/auth_metadata'),
        lessThan(requested.indexOf('/_matrix/client/v3/login')),
      );
    });

    test('an OAuth-only server with no login flows passes', () async {
      final client = await _client(
        (request) async => _homeserver(
          request,
          authMetadata: _authMetadataJson(),
          login: _json({'flows': <Object>[]}),
        ),
      );
      final result = await client.checkHomeserver(
        Uri.https('matrix.example.org'),
        checkWellKnown: false,
      );
      expect(result.$3, isEmpty);
      expect(result.$4, isNotNull);
    });

    test('legacy flows are still returned next to OAuth', () async {
      final client = await _client(
        (request) async =>
            _homeserver(request, authMetadata: _authMetadataJson()),
      );
      final result = await client.checkHomeserver(
        Uri.https('matrix.example.org'),
        checkWellKnown: false,
      );
      expect(result.$3.map((f) => f.type), ['m.login.password']);
      expect(result.$4, isNotNull);
    });

    test('without auth_metadata an unusable /v3/login still fails', () async {
      final client = await _client(
        (request) async => _homeserver(
          request,
          login: _json({'flows': <Object>[]}),
        ),
      );
      await expectLater(
        client.checkHomeserver(
          Uri.https('matrix.example.org'),
          checkWellKnown: false,
        ),
        throwsA(isA<BadServerLoginTypesException>()),
      );
      expect(client.homeserver, isNull);
    });
  });

  group('scopes', () {
    test('stable scopes when scopes_supported lists them', () {
      expect(
        negotiateOidcScopes(
          scopesSupported: [
            'openid',
            'urn:matrix:client:api:*',
            'urn:matrix:client:device:*',
          ],
          deviceId: 'ABCDEFGHIJ',
        ),
        {
          'openid',
          'urn:matrix:client:api:*',
          'urn:matrix:client:device:ABCDEFGHIJ',
        },
      );
    });

    test('MSC2967 scopes when scopes_supported is missing', () {
      expect(
        negotiateOidcScopes(scopesSupported: null, deviceId: 'ABCDEFGHIJ'),
        {
          'openid',
          'urn:matrix:org.matrix.msc2967.client:api:*',
          'urn:matrix:org.matrix.msc2967.client:device:ABCDEFGHIJ',
        },
      );
    });

    test('MSC2967 scopes when only the unstable ones are listed', () {
      expect(
        negotiateOidcScopes(
          scopesSupported: [
            'openid',
            'urn:matrix:org.matrix.msc2967.client:api:*',
          ],
          deviceId: 'ABCDEFGHIJ',
        ),
        contains('urn:matrix:org.matrix.msc2967.client:api:*'),
      );
    });

    test('no openid when the server lists scopes without it', () {
      expect(
        negotiateOidcScopes(
          scopesSupported: ['urn:matrix:client:api:*'],
          deviceId: 'ABCDEFGHIJ',
        ),
        {'urn:matrix:client:api:*', 'urn:matrix:client:device:ABCDEFGHIJ'},
      );
    });
  });

  group('PKCE (S256), CIMD/DCR and prompt=create', () {
    setUpAll(() async {
      if (!vod.isInitialized()) {
        await vod.init(wasmPath: './pkg/', libraryPath: './rust/target/debug/');
      }
    });

    String challengeOf(String verifier) => base64UrlEncodeNoPadding(
          vod.CryptoUtils.sha256(input: ascii.encode(verifier)),
        );

    test('S256 matches the RFC 7636 appendix B example', () {
      expect(
        challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    Future<(Client, List<http.Request>)> oauthClient(
      Map<String, Object?> metadata,
    ) async {
      final requests = <http.Request>[];
      final client = await _client((request) async {
        requests.add(request);
        if (request.url.toString() ==
            'https://auth.example.org/oauth2/registration') {
          return _json(
            {
              'client_id': 'dcr-client-01',
              ...(jsonDecode(request.body) as Map<String, Object?>),
            },
            201,
          );
        }
        return _homeserver(request, authMetadata: metadata);
      });
      await client.checkHomeserver(
        Uri.https('matrix.example.org'),
        checkWellKnown: false,
      );
      return (client, requests);
    }

    final clientInformation = OidcClientInformation(
      clientName: 'Rooster',
      clientUri: Uri.parse('https://rooster.example/'),
      logoUri: null,
      tosUri: null,
      policyUri: null,
    );
    final cimdUrl = Uri.parse('https://rooster.example/oauth/client.json');
    final loopback = Uri.parse('http://127.0.0.1:43123/callback');

    test('authorization URL carries a valid S256 challenge and scopes',
        () async {
      final metadata = GetAuthMetadataResponse.fromJson(
        _authMetadataJson(
          scopes: ['openid', 'urn:matrix:client:api:*'],
        ),
      );
      final (client, _) = await oauthClient(metadata.toJson());
      final oidcClient = OidcClientData(
        clientId: 'abc',
        clientIdIssuedAt: null,
        clientInformation: clientInformation,
        additionalProperties: const {},
      );

      final session = await client.initOidcLoginSession(
        oidcClientData: oidcClient,
        redirectUri: loopback,
        authMetadata: metadata,
        deviceId: 'ABCDEFGHIJ',
      );
      final other = await client.initOidcLoginSession(
        oidcClientData: oidcClient,
        redirectUri: loopback,
        authMetadata: metadata,
      );

      final query = session.authenticationUri.queryParameters;
      expect(
        session.authenticationUri.replace(query: '').toString(),
        'https://auth.example.org/authorize?',
      );
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'abc');
      expect(query['redirect_uri'], loopback.toString());
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge'], challengeOf(session.codeVerifier));
      expect(query.containsKey('code_verifier'), isFalse);
      // RFC 7636 §4.1: 43-128 unreserved characters.
      expect(
        session.codeVerifier,
        matches(RegExp(r'^[A-Za-z0-9\-._~]{43,128}$')),
      );
      expect(query['state'], session.state);
      expect(session.state.length, greaterThanOrEqualTo(43));
      expect(other.state, isNot(session.state));
      expect(other.codeVerifier, isNot(session.codeVerifier));
      expect(query['response_mode'], 'query');
      expect(query['scope']!.split(' ').toSet(), {
        'openid',
        'urn:matrix:client:api:*',
        'urn:matrix:client:device:ABCDEFGHIJ',
      });
      expect(query.containsKey('prompt'), isFalse);
    });

    test('scopes fall back to MSC2967 when not advertised', () async {
      final metadata = GetAuthMetadataResponse.fromJson(_authMetadataJson());
      final (client, _) = await oauthClient(metadata.toJson());
      final session = await client.initOidcLoginSession(
        oidcClientData: OidcClientData(
          clientId: 'abc',
          clientIdIssuedAt: null,
          clientInformation: clientInformation,
          additionalProperties: const {},
        ),
        redirectUri: loopback,
        authMetadata: metadata,
        deviceId: 'ZYXWVUTSRQ',
      );
      expect(
        session.authenticationUri.queryParameters['scope']!.split(' ').toSet(),
        {
          'openid',
          'urn:matrix:org.matrix.msc2967.client:api:*',
          'urn:matrix:org.matrix.msc2967.client:device:ZYXWVUTSRQ',
        },
      );
      expect(session.deviceId, 'ZYXWVUTSRQ');
    });

    test('prompt=create is sent only when asked for', () async {
      final metadata = GetAuthMetadataResponse.fromJson(
        _authMetadataJson(prompts: ['create']),
      );
      expect(metadata.supportsPromptCreate, isTrue);
      expect(
        GetAuthMetadataResponse.fromJson(_authMetadataJson())
            .supportsPromptCreate,
        isFalse,
      );
      final (client, _) = await oauthClient(metadata.toJson());
      final data = OidcClientData(
        clientId: 'abc',
        clientIdIssuedAt: null,
        clientInformation: clientInformation,
        additionalProperties: const {},
      );
      final create = await client.initOidcLoginSession(
        oidcClientData: data,
        redirectUri: loopback,
        authMetadata: metadata,
        prompt: 'create',
      );
      expect(create.authenticationUri.queryParameters['prompt'], 'create');
      final plain = await client.initOidcLoginSession(
        oidcClientData: data,
        redirectUri: loopback,
        authMetadata: metadata,
      );
      expect(
        plain.authenticationUri.queryParameters.containsKey('prompt'),
        isFalse,
      );
    });

    test('CIMD is used when client_id_metadata_document_supported is true',
        () async {
      final (client, requests) =
          await oauthClient(_authMetadataJson(cimd: true));
      requests.clear();
      final data = await client.obtainOidcClient(
        redirectUris: [loopback],
        applicationType: OidcApplicationType.native,
        clientInformation: clientInformation,
        clientMetadataDocumentUri: cimdUrl,
      );
      expect(data.clientId, cimdUrl.toString());
      expect(data.isClientIdMetadataDocument, isTrue);
      expect(
        requests.where((r) => r.url.path == '/oauth2/registration'),
        isEmpty,
      );
    });

    test('DCR (RFC 7591) is used when CIMD is not supported', () async {
      final (client, requests) =
          await oauthClient(_authMetadataJson(cimd: false));
      final data = await client.obtainOidcClient(
        redirectUris: [loopback],
        applicationType: OidcApplicationType.native,
        clientInformation: clientInformation,
        clientMetadataDocumentUri: cimdUrl,
      );
      expect(data.clientId, 'dcr-client-01');
      expect(data.isClientIdMetadataDocument, isFalse);
      final registration =
          requests.singleWhere((r) => r.url.path == '/oauth2/registration');
      expect(registration.method, 'POST');
      final body = jsonDecode(registration.body) as Map<String, Object?>;
      expect(body['redirect_uris'], [loopback.toString()]);
      expect(body['application_type'], 'native');
      expect(body['token_endpoint_auth_method'], 'none');
      expect(body['grant_types'], contains('authorization_code'));
      expect(body['client_uri'], 'https://rooster.example/');
    });

    test('DCR is used when the app has no metadata document', () async {
      final (client, _) = await oauthClient(_authMetadataJson(cimd: true));
      final data = await client.obtainOidcClient(
        redirectUris: [loopback],
        applicationType: OidcApplicationType.native,
        clientInformation: clientInformation,
      );
      expect(data.clientId, 'dcr-client-01');
    });

    test('neither CIMD nor DCR fails explicitly', () async {
      final (client, _) = await oauthClient(
        _authMetadataJson(cimd: false, withRegistration: false),
      );
      await expectLater(
        client.obtainOidcClient(
          redirectUris: [loopback],
          applicationType: OidcApplicationType.native,
          clientInformation: clientInformation,
          clientMetadataDocumentUri: cimdUrl,
        ),
        throwsA(isA<OidcClientRegistrationException>()),
      );
    });

    test('an invalid metadata document URL is refused', () async {
      final (client, _) = await oauthClient(_authMetadataJson(cimd: true));
      for (final bad in [
        'http://rooster.example/client.json',
        'https://rooster.example/',
        'https://rooster.example/client.json#x',
      ]) {
        await expectLater(
          client.obtainOidcClient(
            redirectUris: [loopback],
            applicationType: OidcApplicationType.native,
            clientInformation: clientInformation,
            clientMetadataDocumentUri: Uri.parse(bad),
          ),
          throwsArgumentError,
          reason: bad,
        );
      }
    });
  });

  group('authorization redirect', () {
    final session = OidcLoginSession(
      oidcClientData: OidcClientData(
        clientId: 'abc',
        clientIdIssuedAt: null,
        clientInformation: OidcClientInformation(
          clientName: null,
          clientUri: Uri.parse('https://rooster.example/'),
          logoUri: null,
          tosUri: null,
          policyUri: null,
        ),
        additionalProperties: const {},
      ),
      authenticationUri: Uri.parse('https://auth.example.org/authorize'),
      redirectUri: Uri.parse('http://127.0.0.1:43123/callback'),
      codeVerifier: 'verifier',
      state: 'expected-state-value',
    );

    Matcher fails(OidcCallbackFailure failure) => throwsA(
          isA<OidcCallbackException>()
              .having((e) => e.failure, 'failure', failure),
        );

    test('code is returned when state matches', () {
      expect(
        parseOidcAuthorizationCallback(
          session,
          Uri.parse(
            'http://127.0.0.1:43123/callback?code=c0de&state=expected-state-value',
          ),
        ),
        'c0de',
      );
    });

    test('a different state is refused', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse('http://127.0.0.1:43123/callback?code=c0de&state=other'),
        ),
        fails(OidcCallbackFailure.stateMismatch),
      );
    });

    test('a missing state is refused', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse('http://127.0.0.1:43123/callback?code=c0de'),
        ),
        fails(OidcCallbackFailure.stateMissing),
      );
    });

    test('error=access_denied is refused', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse(
            'http://127.0.0.1:43123/callback?error=access_denied&state=expected-state-value',
          ),
        ),
        fails(OidcCallbackFailure.accessDenied),
      );
    });

    test('another OAuth error is refused', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse(
            'http://127.0.0.1:43123/callback?error=server_error&state=expected-state-value',
          ),
        ),
        fails(OidcCallbackFailure.authorizationError),
      );
    });

    test('a forged error with the wrong state is a state mismatch', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse(
            'http://127.0.0.1:43123/callback?error=access_denied&state=x',
          ),
        ),
        fails(OidcCallbackFailure.stateMismatch),
      );
    });

    test('no code is refused', () {
      expect(
        () => parseOidcAuthorizationCallback(
          session,
          Uri.parse(
            'http://127.0.0.1:43123/callback?state=expected-state-value',
          ),
        ),
        fails(OidcCallbackFailure.codeMissing),
      );
    });

    test('fragment mode reads the fragment', () {
      final fragmentSession = OidcLoginSession(
        oidcClientData: session.oidcClientData,
        authenticationUri: session.authenticationUri,
        redirectUri: Uri.parse('https://rooster.example/auth.html'),
        codeVerifier: 'verifier',
        state: 'expected-state-value',
        responseMode: OidcResponseMode.fragment,
      );
      expect(
        parseOidcAuthorizationCallback(
          fragmentSession,
          Uri.parse(
            'https://rooster.example/auth.html#code=frag&state=expected-state-value',
          ),
        ),
        'frag',
      );
      expect(
        () => parseOidcAuthorizationCallback(
          fragmentSession,
          Uri.parse(
            'https://rooster.example/auth.html?state=expected-state-value#code=frag&state=evil',
          ),
        ),
        fails(OidcCallbackFailure.stateMismatch),
      );
    });

    test('oidcLogin refuses a different state before any request', () async {
      var requests = 0;
      final client = await _client((request) async {
        requests++;
        return http.Response('{}', 500);
      });
      await expectLater(
        client.oidcLogin(session: session, code: 'c0de', state: 'other'),
        throwsException,
      );
      expect(requests, 0);
    });
  });
}
