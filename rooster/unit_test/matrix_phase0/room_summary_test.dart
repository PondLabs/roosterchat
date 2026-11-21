import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart' as rooster;
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';

import 'test_helpers.dart';

void main() {
  matrix.Client buildClient(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return matrix.Client(
      'summary_test',
      httpClient: MockClient(handler),
      database: MemoryCacheDatabase(),
    )
      ..homeserver = Uri.parse('http://127.0.0.1:9')
      ..accessToken = 'test-token';
  }

  group('isMatrixVersionAtLeast', () {
    test('compares major and minor integers properly', () {
      expect(isMatrixVersionAtLeast('v1.15', 1, 15), isTrue);
      expect(isMatrixVersionAtLeast('v1.19', 1, 15), isTrue);
      expect(isMatrixVersionAtLeast('v2.0', 1, 15), isTrue);
      expect(isMatrixVersionAtLeast('v1.14', 1, 15), isFalse);
      expect(isMatrixVersionAtLeast('v1.2', 1, 15), isFalse);
      expect(isMatrixVersionAtLeast('r0.6.1', 1, 15), isFalse);
      expect(isMatrixVersionAtLeast('invalid', 1, 15), isFalse);
    });
  });

  group('MatrixExtensions.getRoomPreview', () {
    test(
      'uses stable v1 getRoomSummary on server >= v1.15 and maps '
      'chat.commet.calendar / photo_album',
      () async {
        final seen = <Uri>[];
        final client = buildClient((request) async {
          seen.add(request.url);
          if (request.url.path == '/_matrix/client/versions') {
            return http.Response(
              jsonEncode({
                'versions': ['v1.1', 'v1.14', 'v1.15'],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.startsWith('/_matrix/client/v1/room_summary/')) {
            final roomType = request.url.path.contains('photo')
                ? 'chat.commet.photo_album'
                : 'chat.commet.calendar';
            return http.Response(
              jsonEncode({
                'room_id': '!cal:example.test',
                'name': 'Team Room',
                'topic': 'Schedule',
                'num_joined_members': 4,
                'join_rule': 'public',
                'room_type': roomType,
                'guest_can_join': false,
                'world_readable': true,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'errcode': 'M_UNRECOGNIZED'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        });

        final calendar = await client.getRoomPreview(
          '!cal:example.test',
          via: ['a.test', 'b.test'],
        );
        expect(calendar, isNotNull);
        expect(calendar!.displayName, 'Team Room');
        expect(calendar.type, rooster.RoomType.calendar);
        expect(calendar.numMembers, 4);
        expect(calendar.visibility, isA<rooster.RoomVisibilityPublic>());

        final album = await client.getRoomPreview('!photo:example.test');
        expect(album, isNotNull);
        expect(album!.type, rooster.RoomType.photoAlbum);

        final summaryRequests =
            seen.where((u) => u.path != '/_matrix/client/versions').toList();
        expect(summaryRequests, hasLength(2));
        expect(
          summaryRequests.every(
            (u) => u.path.startsWith('/_matrix/client/v1/room_summary/'),
          ),
          isTrue,
        );
        expect(
          seen.any((u) => u.path.contains('im.nheko.summary')),
          isFalse,
        );
        expect(
          summaryRequests.first.queryParametersAll['via'],
          ['a.test', 'b.test'],
        );
      },
    );

    test('falls back to im.nheko.summary only on server < v1.15', () async {
      final seen = <Uri>[];
      final client = buildClient((request) async {
        seen.add(request.url);
        if (request.url.path == '/_matrix/client/versions') {
          return http.Response(
            jsonEncode({
              'versions': ['v1.1', 'v1.14'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path
            .startsWith('/_matrix/client/unstable/im.nheko.summary/rooms/')) {
          return http.Response(
            jsonEncode({
              'room_id': '!old:example.test',
              'name': 'Legacy Calendar',
              'num_joined_members': 2,
              'join_rule': 'invite',
              'room_type': 'chat.commet.calendar',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final preview = await client.getRoomPreview('!old:example.test');
      expect(preview, isNotNull);
      expect(preview!.displayName, 'Legacy Calendar');
      expect(preview.type, rooster.RoomType.calendar);
      expect(
        seen.any((u) => u.path.contains('/client/v1/room_summary/')),
        isFalse,
      );
      expect(
        seen.any(
          (u) => u.path.contains('/client/unstable/im.nheko.summary/rooms/'),
        ),
        isTrue,
      );
    });

    test(
      'does not treat chat.rooster.* room_types as calendar or photo album and '
      'does not fall back to unstable on >= v1.15 error',
      () async {
        final seen = <Uri>[];
        final client = buildClient((request) async {
          seen.add(request.url);
          if (request.url.path == '/_matrix/client/versions') {
            return http.Response(
              jsonEncode({
                'versions': ['v1.15']
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.contains('fail')) {
            return http.Response(
              jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'Missing'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'room_id': '!legacytype:example.test',
              'name': 'Old Namespace',
              'num_joined_members': 1,
              'join_rule': 'public',
              'room_type': 'chat.rooster.calendar',
              'guest_can_join': false,
              'world_readable': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final preview = await client.getRoomPreview('!legacytype:example.test');
        expect(preview, isNotNull);
        expect(preview!.type, rooster.RoomType.defaultRoom);

        await expectLater(
          client.getRoomPreview('!fail:example.test'),
          throwsA(isA<matrix.MatrixException>()),
        );
        expect(
          seen.any((u) => u.path.contains('im.nheko.summary')),
          isFalse,
        );
      },
    );
  });
}
