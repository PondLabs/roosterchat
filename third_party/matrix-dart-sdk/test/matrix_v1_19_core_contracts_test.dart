// ROOSTER: Tests for Matrix v1.19 SDK core contracts (T1.1a).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

void main() {
  Logs().level = Level.error;

  group('1. AuthenticationTypes.oauth and Capabilities (v1.16-v1.20)', () {
    test('AuthenticationTypes.oauth equals m.oauth without breaking existing',
        () {
      expect(AuthenticationTypes.oauth, 'm.oauth');
      expect(AuthenticationTypes.oauth2, 'm.login.oauth2');
      expect(AuthenticationTypes.password, 'm.login.password');
    });

    test(
      'Capabilities.fromJson deserializes forget_forced_upon_leave, profile_fields, and preview_url',
      () {
        final caps = Capabilities.fromJson({
          'm.forget_forced_upon_leave': {'enabled': true},
          'm.profile_fields': {
            'enabled': true,
            'allowed': ['displayname', 'avatar_url', 'eu.she-a.color'],
          },
          'm.preview_url': {'enabled': false},
          'com.example.custom': {'enabled': true},
        });

        expect(caps.mForgetForcedUponLeave?.enabled, isTrue);
        expect(caps.mProfileFields?.enabled, isTrue);
        expect(
          caps.mProfileFields?.allowed,
          ['displayname', 'avatar_url', 'eu.she-a.color'],
        );
        expect(caps.mProfileFields?.disallowed, isNull);
        expect(caps.mPreviewUrl?.enabled, isFalse);

        expect(
          caps.additionalProperties.containsKey('m.forget_forced_upon_leave'),
          isFalse,
        );
        expect(
          caps.additionalProperties.containsKey('m.profile_fields'),
          isFalse,
        );
        expect(
          caps.additionalProperties.containsKey('m.preview_url'),
          isFalse,
        );
        expect(
          caps.additionalProperties['com.example.custom'],
          {'enabled': true},
        );

        final roundTrip = caps.toJson();
        expect(roundTrip['m.forget_forced_upon_leave'], {'enabled': true});
        expect(roundTrip['m.profile_fields'], {
          'allowed': ['displayname', 'avatar_url', 'eu.she-a.color'],
          'enabled': true,
        });
        expect(roundTrip['m.preview_url'], {'enabled': false});
        expect(roundTrip['com.example.custom'], {'enabled': true});
      },
    );

    test('Capabilities.fromJson handles absent and null fields on old servers',
        () {
      final empty = Capabilities.fromJson({});
      expect(empty.mForgetForcedUponLeave, isNull);
      expect(empty.mProfileFields, isNull);
      expect(empty.mPreviewUrl, isNull);
      expect(empty.toJson(), isEmpty);

      final explicitNulls = Capabilities.fromJson({
        'm.forget_forced_upon_leave': null,
        'm.profile_fields': null,
        'm.preview_url': null,
      });
      expect(explicitNulls.mForgetForcedUponLeave, isNull);
      expect(explicitNulls.mProfileFields, isNull);
      expect(explicitNulls.mPreviewUrl, isNull);

      final missingEnabled = Capabilities.fromJson({
        'm.forget_forced_upon_leave': <String, Object?>{},
        'm.profile_fields': <String, Object?>{},
        'm.preview_url': <String, Object?>{},
      });
      expect(missingEnabled.mForgetForcedUponLeave, isNull);
      expect(missingEnabled.mProfileFields, isNull);
      expect(missingEnabled.mPreviewUrl, isNull);
    });

    test('Capabilities equality and hashCode reflect new capability fields',
        () {
      final a = Capabilities(
        mForgetForcedUponLeave: BooleanCapability(enabled: true),
        mPreviewUrl: BooleanCapability(enabled: true),
      );
      final b = Capabilities(
        mForgetForcedUponLeave: BooleanCapability(enabled: true),
        mPreviewUrl: BooleanCapability(enabled: true),
      );
      final diffForget = Capabilities(
        mForgetForcedUponLeave: BooleanCapability(enabled: false),
        mPreviewUrl: BooleanCapability(enabled: true),
      );
      final diffPreview = Capabilities(
        mForgetForcedUponLeave: BooleanCapability(enabled: true),
        mPreviewUrl: BooleanCapability(enabled: false),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diffForget)));
      expect(a, isNot(equals(diffPreview)));
    });

    test('MatrixApi.getCapabilities parses v1.16-v1.20 capabilities payload',
        () async {
      final api = MatrixApi(
        homeserver: Uri.parse('https://hs.example.test'),
        accessToken: 'tok',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/_matrix/client/v3/capabilities');
          return http.Response(
            jsonEncode({
              'capabilities': {
                'm.forget_forced_upon_leave': {'enabled': true},
                'm.profile_fields': {
                  'enabled': true,
                  'disallowed': ['m.tz'],
                },
                'm.preview_url': {'enabled': true},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final caps = await api.getCapabilities();
      expect(caps.mForgetForcedUponLeave?.enabled, isTrue);
      expect(caps.mProfileFields?.enabled, isTrue);
      expect(caps.mProfileFields?.disallowed, ['m.tz']);
      expect(caps.mPreviewUrl?.enabled, isTrue);
    });
  });

  group('2. GetAuthMetadataResponse (v1.15-v1.18)', () {
    test(
      'fromJson preserves all v1.15-v1.18 fields and ignores unknown extra keys',
      () {
        final metadata = GetAuthMetadataResponse.fromJson({
          'issuer': 'https://auth.example.test/',
          'authorization_endpoint': 'https://auth.example.test/oauth2/auth',
          'token_endpoint': 'https://auth.example.test/oauth2/token',
          'registration_endpoint': 'https://auth.example.test/oauth2/register',
          'revocation_endpoint': 'https://auth.example.test/oauth2/revoke',
          'device_authorization_endpoint':
              'https://auth.example.test/oauth2/device',
          'account_management_uri': 'https://auth.example.test/account',
          'account_management_actions_supported': [
            'org.matrix.profile',
            'org.matrix.sessions_list',
            'org.matrix.account_deactivate',
          ],
          'client_id_metadata_document_supported': true,
          'scopes_supported': [
            'openid',
            'urn:matrix:client:api:*',
            'urn:matrix:client:device:*',
          ],
          'prompt_values_supported': ['create'],
          'response_types_supported': ['code'],
          'response_modes_supported': ['query', 'fragment'],
          'grant_types_supported': [
            'authorization_code',
            'refresh_token',
            'urn:ietf:params:oauth:grant-type:device_code',
          ],
          'code_challenge_methods_supported': ['S256'],
          'jwks_uri': 'https://auth.example.test/.well-known/jwks.json',
          'org.matrix.unknown_future_extension': {'nested': 123},
        });

        expect(metadata.issuer, Uri.parse('https://auth.example.test/'));
        expect(
          metadata.authorizationEndpoint,
          Uri.parse('https://auth.example.test/oauth2/auth'),
        );
        expect(
          metadata.tokenEndpoint,
          Uri.parse('https://auth.example.test/oauth2/token'),
        );
        expect(
          metadata.registrationEndpoint,
          Uri.parse('https://auth.example.test/oauth2/register'),
        );
        expect(
          metadata.revocationEndpoint,
          Uri.parse('https://auth.example.test/oauth2/revoke'),
        );
        expect(
          metadata.deviceAuthorizationEndpoint,
          Uri.parse('https://auth.example.test/oauth2/device'),
        );
        expect(
          metadata.accountManagementUri,
          Uri.parse('https://auth.example.test/account'),
        );
        expect(
          metadata.accountManagementActionsSupported,
          [
            'org.matrix.profile',
            'org.matrix.sessions_list',
            'org.matrix.account_deactivate',
          ],
        );
        expect(metadata.clientIdMetadataDocumentSupported, isTrue);
        expect(
          metadata.scopesSupported,
          [
            'openid',
            'urn:matrix:client:api:*',
            'urn:matrix:client:device:*',
          ],
        );
        expect(metadata.promptValuesSupported, ['create']);

        final json = metadata.toJson();
        expect(
          json['device_authorization_endpoint'],
          'https://auth.example.test/oauth2/device',
        );
        expect(
          json['account_management_uri'],
          'https://auth.example.test/account',
        );
        expect(
          json['account_management_actions_supported'],
          [
            'org.matrix.profile',
            'org.matrix.sessions_list',
            'org.matrix.account_deactivate',
          ],
        );
        expect(json['client_id_metadata_document_supported'], isTrue);
        expect(
          json['scopes_supported'],
          [
            'openid',
            'urn:matrix:client:api:*',
            'urn:matrix:client:device:*',
          ],
        );
        expect(
          json['registration_endpoint'],
          'https://auth.example.test/oauth2/register',
        );
        expect(
          json['revocation_endpoint'],
          'https://auth.example.test/oauth2/revoke',
        );
        expect(json['prompt_values_supported'], ['create']);
        expect(json.containsKey('jwks_uri'), isFalse);
      },
    );

    test(
      'fromJson handles absent and null optional fields without throwing (e.g. CIMD without DCR)',
      () {
        final absent = GetAuthMetadataResponse.fromJson({
          'issuer': 'https://auth.example.test/',
          'authorization_endpoint': 'https://auth.example.test/oauth2/auth',
          'token_endpoint': 'https://auth.example.test/oauth2/token',
          'client_id_metadata_document_supported': false,
        });

        expect(absent.registrationEndpoint, isNull);
        expect(absent.revocationEndpoint, isNull);
        expect(absent.deviceAuthorizationEndpoint, isNull);
        expect(absent.accountManagementUri, isNull);
        expect(absent.accountManagementActionsSupported, isNull);
        expect(absent.clientIdMetadataDocumentSupported, isFalse);
        expect(absent.scopesSupported, isNull);
        expect(absent.promptValuesSupported, isNull);
        expect(absent.codeChallengeMethodsSupported, isEmpty);
        expect(absent.grantTypesSupported, isEmpty);
        expect(absent.responseModesSupported, isEmpty);
        expect(absent.responseTypesSupported, isEmpty);

        final absentJson = absent.toJson();
        expect(absentJson.containsKey('registration_endpoint'), isFalse);
        expect(absentJson.containsKey('revocation_endpoint'), isFalse);
        expect(
          absentJson.containsKey('device_authorization_endpoint'),
          isFalse,
        );
        expect(absentJson.containsKey('account_management_uri'), isFalse);
        expect(absentJson['client_id_metadata_document_supported'], isFalse);

        final explicitNulls = GetAuthMetadataResponse.fromJson({
          'issuer': 'https://auth.example.test/',
          'authorization_endpoint': 'https://auth.example.test/oauth2/auth',
          'token_endpoint': 'https://auth.example.test/oauth2/token',
          'registration_endpoint': null,
          'revocation_endpoint': null,
          'device_authorization_endpoint': '',
          'account_management_uri': null,
          'account_management_actions_supported': null,
          'client_id_metadata_document_supported': null,
          'scopes_supported': null,
          'prompt_values_supported': null,
          'response_types_supported': null,
          'response_modes_supported': null,
          'grant_types_supported': null,
          'code_challenge_methods_supported': null,
        });

        expect(explicitNulls.registrationEndpoint, isNull);
        expect(explicitNulls.revocationEndpoint, isNull);
        expect(explicitNulls.deviceAuthorizationEndpoint, isNull);
        expect(explicitNulls.accountManagementUri, isNull);
        expect(explicitNulls.accountManagementActionsSupported, isNull);
        expect(explicitNulls.clientIdMetadataDocumentSupported, isNull);
        expect(explicitNulls.scopesSupported, isNull);
        expect(explicitNulls.promptValuesSupported, isNull);
      },
    );

    test('MatrixApi.getAuthMetadata parses v1.18 CIMD server response',
        () async {
      final api = MatrixApi(
        homeserver: Uri.parse('https://hs.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/_matrix/client/v1/auth_metadata');
          return http.Response(
            jsonEncode({
              'issuer': 'https://auth.example.test/',
              'authorization_endpoint': 'https://auth.example.test/authorize',
              'token_endpoint': 'https://auth.example.test/token',
              'device_authorization_endpoint':
                  'https://auth.example.test/device',
              'client_id_metadata_document_supported': true,
              'scopes_supported': ['openid', 'urn:matrix:client:api:*'],
              'response_types_supported': ['code'],
              'response_modes_supported': ['query', 'fragment'],
              'grant_types_supported': [
                'authorization_code',
                'refresh_token',
              ],
              'code_challenge_methods_supported': ['S256'],
              'unknown_extra_field': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final metadata = await api.getAuthMetadata();
      expect(metadata.registrationEndpoint, isNull);
      expect(metadata.revocationEndpoint, isNull);
      expect(
        metadata.deviceAuthorizationEndpoint,
        Uri.parse('https://auth.example.test/device'),
      );
      expect(metadata.clientIdMetadataDocumentSupported, isTrue);
      expect(
        metadata.scopesSupported,
        ['openid', 'urn:matrix:client:api:*'],
      );
    });

    test(
      'registerOidcClient and revokeOidcToken fail cleanly when endpoints are absent',
      () async {
        final client = Client(
          'oidc_missing_endpoints',
          database: await getDatabase(),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/_matrix/client/v1/auth_metadata')) {
              return http.Response(
                jsonEncode({
                  'issuer': 'https://auth.example.test/',
                  'authorization_endpoint':
                      'https://auth.example.test/authorize',
                  'token_endpoint': 'https://auth.example.test/token',
                  'response_types_supported': ['code'],
                  'response_modes_supported': ['query', 'fragment'],
                  'grant_types_supported': ['authorization_code'],
                  'code_challenge_methods_supported': ['S256'],
                  'client_id_metadata_document_supported': true,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('{}', 404);
          }),
        );
        client.homeserver = Uri.parse('https://hs.example.test');
        addTearDown(() => client.dispose(closeDatabase: true));

        await expectLater(
          () => client.registerOidcClient(
            redirectUris: [Uri.http('localhost:12345')],
            applicationType: OidcApplicationType.native,
            clientInformation: OidcClientInformation(
              clientName: 'Test',
              clientUri: Uri.https('client.example.test'),
              logoUri: null,
              tosUri: null,
              policyUri: null,
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('registration_endpoint'),
            ),
          ),
        );

        await expectLater(
          () => client.revokeOidcToken('cid', 'tok', 'access_token'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('revocation_endpoint'),
            ),
          ),
        );
      },
    );
  });

  group('3. Standardized MatrixError codes', () {
    test('MatrixException recognizes all standardized MatrixError codes', () {
      const expectedCodes = <String, MatrixError>{
        'M_USER_LOCKED': MatrixError.M_USER_LOCKED,
        'M_USER_SUSPENDED': MatrixError.M_USER_SUSPENDED,
        'M_USER_LIMIT_EXCEEDED': MatrixError.M_USER_LIMIT_EXCEEDED,
        'M_CANNOT_OVERWRITE_MEDIA': MatrixError.M_CANNOT_OVERWRITE_MEDIA,
        'M_NOT_YET_UPLOADED': MatrixError.M_NOT_YET_UPLOADED,
        'M_MISSING_TOKEN': MatrixError.M_MISSING_TOKEN,
        'M_WRONG_ROOM_KEYS_VERSION': MatrixError.M_WRONG_ROOM_KEYS_VERSION,
        'M_INCOMPATIBLE_ROOM_VERSION': MatrixError.M_INCOMPATIBLE_ROOM_VERSION,
        'M_UNSUPPORTED_ROOM_VERSION': MatrixError.M_UNSUPPORTED_ROOM_VERSION,
        'M_RESOURCE_LIMIT_EXCEEDED': MatrixError.M_RESOURCE_LIMIT_EXCEEDED,
        'M_DUPLICATE_ANNOTATION': MatrixError.M_DUPLICATE_ANNOTATION,
      };

      for (final entry in expectedCodes.entries) {
        final fromJson = MatrixException.fromJson({
          'errcode': entry.key,
          'error': 'Error ${entry.key}',
        });
        expect(fromJson.errcode, entry.key);
        expect(fromJson.error, entry.value);

        final fromResp = MatrixException(
          http.Response(
            jsonEncode({'errcode': entry.key, 'error': 'Error ${entry.key}'}),
            403,
          ),
        );
        expect(fromResp.error, entry.value);
      }

      final unknown = MatrixException.fromJson({
        'errcode': 'M_FUTURE_UNRECOGNIZED_CODE',
        'error': 'Unknown',
      });
      expect(unknown.error, MatrixError.M_UNKNOWN);
    });
  });

  group('4. Global HTTP Retry-After parsing (v1.10 MSC4041)', () {
    final fixedNow = DateTime.utc(2026, 10, 21, 7, 28, 0);

    MatrixApi apiReturning(
      Map<String, Object?> body, {
      int statusCode = 429,
      Map<String, String> headers = const {},
      DateTime? now,
    }) {
      return MatrixApi(
        homeserver: Uri.parse('https://hs.example.test'),
        accessToken: 'tok',
        now: () => now ?? fixedNow,
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(body),
            statusCode,
            headers: {'content-type': 'application/json', ...headers},
          );
        }),
      );
    }

    test(
        'MatrixApi.request parses delta-seconds Retry-After case-insensitively',
        () async {
      for (final header in [
        {'Retry-After': '12'},
        {'retry-after': '12'},
        {'RETRY-AFTER': '  12  '},
      ]) {
        final api = apiReturning(
          {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Too Many Requests'},
          headers: header,
        );
        await expectLater(
          () => api.request(RequestType.GET, '/client/v3/account/whoami'),
          throwsA(
            isA<MatrixException>()
                .having((e) => e.error, 'error', MatrixError.M_LIMIT_EXCEEDED)
                .having((e) => e.retryAfterMs, 'retryAfterMs', 12000)
                .having(
                  (e) => e.raw.containsKey('retry_after_ms'),
                  'raw keeps original body',
                  isFalse,
                ),
          ),
        );
      }

      final zeroApi = apiReturning(
        {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Too Many Requests'},
        headers: {'Retry-After': '0'},
      );
      await expectLater(
        () => zeroApi.request(RequestType.GET, '/client/v3/account/whoami'),
        throwsA(
          isA<MatrixException>().having((e) => e.retryAfterMs, 'zero', 0),
        ),
      );
    });

    test(
      'JSON retry_after_ms takes precedence over Retry-After header; null body falls back',
      () async {
        final bodyWinsApi = apiReturning(
          {
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too Many Requests',
            'retry_after_ms': 500,
          },
          headers: {'Retry-After': '12'},
        );
        await expectLater(
          () =>
              bodyWinsApi.request(RequestType.GET, '/client/v3/account/whoami'),
          throwsA(
            isA<MatrixException>()
                .having((e) => e.retryAfterMs, 'body wins', 500),
          ),
        );

        final nullBodyApi = apiReturning(
          {
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too Many Requests',
            'retry_after_ms': null,
          },
          headers: {'Retry-After': '12'},
        );
        await expectLater(
          () =>
              nullBodyApi.request(RequestType.GET, '/client/v3/account/whoami'),
          throwsA(
            isA<MatrixException>()
                .having((e) => e.retryAfterMs, 'fallback to header', 12000),
          ),
        );
      },
    );

    test(
      'MatrixApi.request parses RFC 7231 HTTP-date formats (IMF-fixdate, RFC 850, asctime, leap year, past)',
      () async {
        final cases = <(String, DateTime, int)>[
          ('Wed, 21 Oct 2026 07:28:12 GMT', fixedNow, 12000),
          (
            'Sun, 6 Nov 2026 08:49:49 GMT',
            DateTime.utc(2026, 11, 6, 8, 49, 37),
            12000,
          ),
          ('Wednesday, 21-Oct-26 07:28:12 GMT', fixedNow, 12000),
          ('Wed Oct 21 07:28:12 2026', fixedNow, 12000),
          (
            'Sun Nov  6 08:49:49 2026',
            DateTime.utc(2026, 11, 6, 8, 49, 37),
            12000,
          ),
          (
            'Tue, 29 Feb 2028 12:00:15 GMT',
            DateTime.utc(2028, 2, 29, 12, 0, 0),
            15000,
          ),
          // Past HTTP-date (including RFC 850 50-year rollover to 1994) clamps to 0.
          ('Wed, 21 Oct 2026 07:27:00 GMT', fixedNow, 0),
          ('Sunday, 06-Nov-94 08:49:37 GMT', fixedNow, 0),
        ];

        for (final (headerValue, clockNow, expectedMs) in cases) {
          final api = apiReturning(
            {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Rate limited'},
            headers: {'Retry-After': headerValue},
            now: clockNow,
          );
          await expectLater(
            () => api.request(RequestType.GET, '/client/v3/account/whoami'),
            throwsA(
              isA<MatrixException>().having(
                (e) => e.retryAfterMs,
                'retryAfterMs for "$headerValue"',
                expectedMs,
              ),
            ),
          );
        }
      },
    );

    test(
      'MatrixApi.unexpectedResponse extracts Retry-After for generated Api endpoints',
      () async {
        final deltaApi = apiReturning(
          {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Too Many Requests'},
          headers: {'Retry-After': '12'},
        );
        await expectLater(
          () => deltaApi.getCapabilities(),
          throwsA(
            isA<MatrixException>()
                .having((e) => e.error, 'error', MatrixError.M_LIMIT_EXCEEDED)
                .having((e) => e.retryAfterMs, 'delta seconds', 12000),
          ),
        );

        final dateApi = apiReturning(
          {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Too Many Requests'},
          headers: {'retry-after': 'Wed, 21 Oct 2026 07:28:15 GMT'},
        );
        await expectLater(
          () => dateApi.getCapabilities(),
          throwsA(
            isA<MatrixException>()
                .having((e) => e.retryAfterMs, 'HTTP-date', 15000),
          ),
        );
      },
    );

    test(
      'Malformed or negative Retry-After headers are ignored without throwing',
      () async {
        const invalidValues = [
          '',
          '   ',
          '-1',
          '-12',
          '-0',
          '+12',
          '12.5',
          '12s',
          'not-a-date',
          'Foo, 21 Oct 2026 07:28:12 GMT',
          'Wed, 30 Feb 2026 07:28:12 GMT',
          'Sat, 29 Feb 2025 07:28:12 GMT',
          'Wed, 21 Oct 2026 25:00:00 GMT',
          'Wed, 21 Oct 2026 07:60:00 GMT',
          'Wed, 21 Oct 2026 07:28:12 PST',
          '99999999999999999999999999',
          '9223372036854775807',
        ];

        for (final bad in invalidValues) {
          final api = apiReturning(
            {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Rate limited'},
            headers: {'Retry-After': bad},
          );
          await expectLater(
            () => api.request(RequestType.GET, '/client/v3/account/whoami'),
            throwsA(
              isA<MatrixException>()
                  .having((e) => e.error, 'error', MatrixError.M_LIMIT_EXCEEDED)
                  .having(
                    (e) => e.retryAfterMs,
                    'ignored "$bad"',
                    isNull,
                  ),
            ),
          );

          final direct = MatrixException(
            http.Response(
              jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Limited'}),
              429,
              headers: {'Retry-After': bad},
            ),
            now: () => fixedNow,
          );
          expect(direct.retryAfterMs, isNull, reason: 'Direct "$bad"');
        }
      },
    );
  });
}
