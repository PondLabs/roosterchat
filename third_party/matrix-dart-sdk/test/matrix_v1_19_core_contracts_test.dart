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
}
