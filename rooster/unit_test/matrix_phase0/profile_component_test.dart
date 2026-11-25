import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'test_helpers.dart';

void main() {
  const selfId = '@alice:example.test';

  ({
    MatrixProfileComponent component,
    List<http.Request> requests,
  }) buildComponent({
    Map<String, Object?>? capabilitiesResponse,
    int capabilitiesStatus = 200,
    Future<http.Response> Function(http.Request)? onProfileRequest,
  }) {
    final requests = <http.Request>[];
    final mx = TestMatrixClient(
      'profile_phase0_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/_matrix/client/v3/capabilities') {
          return http.Response(
            jsonEncode(
              capabilitiesResponse ?? {'capabilities': <String, Object?>{}},
            ),
            capabilitiesStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        if (onProfileRequest != null) {
          return onProfileRequest(request);
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessToken: 'test-token',
      userId: selfId,
    );

    final client = _StubMatrixClient(mx, selfId);
    return (component: MatrixProfileComponent(client), requests: requests);
  }

  group('MatrixProfileComponent URL encoding', () {
    test(
        'URL-encodes field names containing / and . in setField and removeField',
        () async {
      final setup = buildComponent();
      const field = 'com.example/custom.field';

      await setup.component.setField(field, 'value');
      await setup.component.removeField(field);

      final writes = setup.requests
          .where((r) => r.method == 'PUT' || r.method == 'DELETE')
          .toList();
      expect(writes, hasLength(2));
      const expectedPath = '/_matrix/client/v3/profile/'
          '%40alice%3Aexample.test/com.example%2Fcustom.field';
      expect(writes[0].method, 'PUT');
      expect(writes[0].url.path, expectedPath);
      expect(writes[0].url.pathSegments.last, field);
      expect(writes[1].method, 'DELETE');
      expect(writes[1].url.path, expectedPath);
      expect(writes[1].url.pathSegments.last, field);
    });
  });

  group('MatrixProfileComponent m.profile_fields capability (v1.16)', () {
    test('rejects all writes and deletes when enabled is false', () async {
      final setup = buildComponent(
        capabilitiesResponse: {
          'capabilities': {
            'm.profile_fields': {
              'enabled': false,
              'allowed': ['m.tz'],
            },
          },
        },
      );

      await expectLater(
        setup.component.setField('m.tz', 'UTC'),
        throwsA(isA<ProfileFieldNotAllowedException>()),
      );
      await expectLater(
        setup.component.removeField('m.tz'),
        throwsA(isA<ProfileFieldNotAllowedException>()),
      );
      expect(
        setup.requests.where((r) => r.method == 'PUT' || r.method == 'DELETE'),
        isEmpty,
      );
    });

    test('enforces allowed list and ignores disallowed when allowed is present',
        () async {
      final setup = buildComponent(
        capabilitiesResponse: {
          'capabilities': {
            'm.profile_fields': {
              'enabled': true,
              'allowed': ['m.tz', 'chat.commet.profile_bio'],
              'disallowed': ['m.tz'],
            },
          },
        },
      );

      await setup.component.setField('m.tz', 'UTC');
      await expectLater(
        setup.component.setField('chat.commet.profile_status', 'busy'),
        throwsA(isA<ProfileFieldNotAllowedException>()),
      );
      await expectLater(
        setup.component.removeField('chat.commet.profile_status'),
        throwsA(isA<ProfileFieldNotAllowedException>()),
      );

      final writes = setup.requests
          .where((r) => r.method == 'PUT' || r.method == 'DELETE')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.url.pathSegments.last, 'm.tz');
    });

    test('enforces disallowed list when allowed is absent', () async {
      final setup = buildComponent(
        capabilitiesResponse: {
          'capabilities': {
            'm.profile_fields': {
              'enabled': true,
              'disallowed': ['chat.commet.profile_banner'],
            },
          },
        },
      );

      await expectLater(
        setup.component.setField('chat.commet.profile_banner', 'mxc://s/1'),
        throwsA(isA<ProfileFieldNotAllowedException>()),
      );
      await setup.component.setField('m.tz', 'America/Sao_Paulo');

      final writes = setup.requests
          .where((r) => r.method == 'PUT' || r.method == 'DELETE')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.url.pathSegments.last, 'm.tz');
    });

    test('allows writes when /v3/capabilities omits m.profile_fields or 404s',
        () async {
      final setup = buildComponent(capabilitiesStatus: 404);
      await setup.component.setField('m.tz', 'UTC');
      expect(setup.requests.where((r) => r.method == 'PUT'), hasLength(1));
    });
  });

  group('MatrixProfileComponent.getProfile HTTP 403 handling (v1.12)', () {
    test('returns fallback profile without throwing on HTTP 403 M_FORBIDDEN',
        () async {
      final setup = buildComponent(
        onProfileRequest: (request) async => http.Response(
          jsonEncode({
            'errcode': 'M_FORBIDDEN',
            'error': 'Profile access denied',
          }),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );

      final profile = await setup.component.getProfile('@private:example.test');
      expect(profile, isA<MatrixProfile>());
      final mxProfile = profile as MatrixProfile;
      expect(mxProfile.identifier, '@private:example.test');
      expect(mxProfile.displayName, '@private:example.test');
      expect(mxProfile.accessForbidden, isTrue);
      expect(mxProfile.fields, isEmpty);
    });

    test('returns populated profile on HTTP 200 with accessForbidden false',
        () async {
      final setup = buildComponent(
        onProfileRequest: (request) async => http.Response(
          jsonEncode({
            'displayname': 'Bob',
            'm.tz': 'UTC',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final profile = await setup.component.getProfile('@bob:example.test')
          as MatrixProfile;
      expect(profile.accessForbidden, isFalse);
      expect(profile.displayName, 'Bob');
      expect(profile.timezone, 'UTC');
    });
  });
}

class _StubProfile implements Profile {
  _StubProfile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMatrixClient implements MatrixClient {
  _StubMatrixClient(this._mx, String selfId) : self = _StubProfile(selfId);

  final matrix.Client _mx;

  @override
  Profile? self;

  @override
  matrix.Client get matrixClient => _mx;

  @override
  matrix.Client getMatrixClient() => _mx;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
