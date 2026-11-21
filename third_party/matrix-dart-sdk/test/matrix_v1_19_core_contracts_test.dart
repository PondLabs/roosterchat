// ROOSTER: Tests for Matrix v1.19 SDK core contracts (T1.1a).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix_api_lite.dart';

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
}
