import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'test_helpers.dart';

/// Valid 1x1 transparent PNG.
final _samplePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

void main() {
  _StubMatrixClient buildClient({
    required Future<http.Response> Function(http.Request) handler,
    String? accessToken,
  }) {
    final mx = matrix.Client(
      'sso_test',
      httpClient: MockClient(handler),
      database: MemoryCacheDatabase(),
    )
      ..homeserver = Uri.parse('http://127.0.0.1:9')
      ..accessToken = accessToken;
    return _StubMatrixClient(mx);
  }

  group('MatrixSSOLoginFlow icon resolution', () {
    test(
      'uses authenticated media endpoint on v1.11+ when access token is present',
      () async {
        final seen = <http.Request>[];
        final client = buildClient(
          accessToken: 'secret-token',
          handler: (request) async {
            seen.add(request);
            if (request.url.path == '/_matrix/client/versions') {
              return http.Response(
                jsonEncode({
                  'versions': ['v1.1', 'v1.11']
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path ==
                '/_matrix/client/v1/media/thumbnail/example.test/idp_icon') {
              return http.Response.bytes(
                _samplePng,
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            return http.Response('{}', 404);
          },
        );

        final bytes = await MatrixSSOLoginFlow.resolveIconBytes(
          Uri.parse('mxc://example.test/idp_icon'),
          client,
        );

        expect(bytes, _samplePng);
        final mediaReq = seen.singleWhere(
          (r) => r.url.path != '/_matrix/client/versions',
        );
        expect(
          mediaReq.url.path,
          '/_matrix/client/v1/media/thumbnail/example.test/idp_icon',
        );
        expect(mediaReq.headers['authorization'], 'Bearer secret-token');
        expect(
          seen.any((r) => r.url.path.contains('/_matrix/media/v3/thumbnail/')),
          isFalse,
        );
      },
    );

    for (final statusCode in [404, 401]) {
      test(
        'returns null safely without throwing when /_matrix/media/v3/thumbnail '
        'returns $statusCode on unauthenticated v1.11+ server',
        () async {
          final client = buildClient(
            accessToken: null,
            handler: (request) async {
              if (request.url.path == '/_matrix/client/versions') {
                return http.Response(
                  jsonEncode({
                    'versions': ['v1.11', 'v1.15']
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response(
                jsonEncode({'errcode': 'M_NOT_FOUND'}),
                statusCode,
                headers: {'content-type': 'application/json'},
              );
            },
          );

          final bytes = await MatrixSSOLoginFlow.resolveIconBytes(
            Uri.parse('mxc://example.test/idp_icon'),
            client,
          );
          expect(bytes, isNull);
        },
      );
    }

    testWidgets(
      'Image widget renders fallback safely when thumbnail returns 404/401',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);

        final client = buildClient(
          accessToken: null,
          handler: (request) async {
            if (request.url.path == '/_matrix/client/versions') {
              return http.Response(
                jsonEncode({
                  'versions': ['v1.12']
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({'errcode': 'M_MISSING_TOKEN'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          },
        );

        final flow = MatrixSSOLoginFlow.fromJson(client, {
          'id': 'oidc',
          'name': 'Example SSO',
          'icon': 'mxc://example.test/idp_icon',
        });
        expect(flow.icon, isNotNull);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: Image(image: flow.icon!)),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });

        expect(tester.takeException(), isNull);
        expect(errors, isEmpty);
      },
    );

    test('falls back to /_matrix/media/v3/thumbnail on server < v1.11',
        () async {
      final seen = <Uri>[];
      final client = buildClient(
        accessToken: 'secret-token',
        handler: (request) async {
          seen.add(request.url);
          if (request.url.path == '/_matrix/client/versions') {
            return http.Response(
              jsonEncode({
                'versions': ['v1.1', 'v1.10']
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/_matrix/media/v3/thumbnail/example.test/idp_icon') {
            return http.Response.bytes(
              _samplePng,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return http.Response('{}', 404);
        },
      );

      final bytes = await MatrixSSOLoginFlow.resolveIconBytes(
        Uri.parse('mxc://example.test/idp_icon'),
        client,
      );
      expect(bytes, _samplePng);
      expect(
        seen.any(
          (u) => u.path == '/_matrix/media/v3/thumbnail/example.test/idp_icon',
        ),
        isTrue,
      );
    });

    test('fromJson returns null icon for missing or invalid mxc URI', () {
      final client = buildClient(
        handler: (_) async => http.Response('{}', 200),
      );
      expect(
        MatrixSSOLoginFlow.fromJson(client, {'name': 'No Icon'}).icon,
        isNull,
      );
      expect(
        MatrixSSOLoginFlow.fromJson(
          client,
          {'name': 'Broken', 'icon': 'mxc://example.test'},
        ).icon,
        isNull,
      );
      expect(
        MatrixSSOLoginFlow.fromJson(
          client,
          {'name': 'Unsupported', 'icon': 'javascript:alert(1)'},
        ).icon,
        isNull,
      );
    });
  });
}

class _StubMatrixClient implements MatrixClient {
  _StubMatrixClient(this._mx);
  final matrix.Client _mx;

  @override
  String get identifier => 'sso-client';

  @override
  matrix.Client getMatrixClient() => _mx;

  @override
  matrix.Client get matrixClient => _mx;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
