// ROOSTER: Tests for the Matrix v1.18-v1.19 Client-Server endpoints (T1.1c):
// v1.19 mutual rooms (MSC2666), v1.18 admin suspend/lock (MSC4323),
// v1.18 event reports without `score` (MSC4277) and v1.18 redactions sent
// through `PUT /send` (MSC4169) with the `/redact` fallback.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:matrix/matrix.dart';
import 'fake_database.dart';

final _homeserver = Uri.parse('https://hs.example.test');

http.Response _json(Object body, [int statusCode = 200]) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

/// A [MatrixApi] whose every request goes to [handler] and is kept in
/// [requests].
MatrixApi _api(
  List<http.Request> requests,
  Future<http.Response> Function(http.Request request) handler,
) =>
    MatrixApi(
      homeserver: _homeserver,
      accessToken: 'access_tok',
      httpClient: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    );

Matcher _throwsMatrixError(MatrixError error) => throwsA(
      isA<MatrixException>().having((e) => e.error, 'error', error),
    );

void main() {
  group('getMutualRooms (v1.19, MSC2666)', () {
    test('GETs /v1/mutual_rooms with user_id and reads the first batch',
        () async {
      final requests = <http.Request>[];
      final api = _api(
        requests,
        (_) async => _json({
          'joined': ['!a:example.test', '!b:example.test'],
          'count': 3,
          'next_batch': 'batch_2',
        }),
      );

      final response = await api.getMutualRooms('@bob+x/y:example.test');

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/_matrix/client/v1/mutual_rooms');
      expect(request.url.queryParameters, {'user_id': '@bob+x/y:example.test'});
      expect(request.url.query, 'user_id=%40bob%2Bx%2Fy%3Aexample.test');
      expect(request.headers['authorization'], 'Bearer access_tok');
      expect(response.joined, ['!a:example.test', '!b:example.test']);
      expect(response.count, 3);
      expect(response.nextBatch, 'batch_2');
    });

    test('sends `from` for the next batch and ends without next_batch',
        () async {
      final requests = <http.Request>[];
      final api = _api(
        requests,
        (_) async => _json({
          'joined': ['!c:example.test'],
          'count': 3,
        }),
      );

      final response =
          await api.getMutualRooms('@bob:example.test', from: 'batch 2/&');

      expect(requests.single.url.queryParameters, {
        'user_id': '@bob:example.test',
        'from': 'batch 2/&',
      });
      expect(requests.single.url.query, contains('from=batch+2%2F%26'));
      expect(response.joined, ['!c:example.test']);
      expect(response.count, 3);
      expect(response.nextBatch, isNull);
    });

    test('pages through every batch with next_batch', () async {
      final requests = <http.Request>[];
      final api = _api(requests, (request) async {
        final from = request.url.queryParameters['from'];
        return switch (from) {
          null => _json({
              'joined': ['!a:example.test'],
              'count': 2,
              'next_batch': 'b2',
            }),
          'b2' => _json({
              'joined': ['!b:example.test'],
              'count': 2,
            }),
          _ => _json({'errcode': 'M_INVALID_PARAM', 'error': 'bad'}, 400),
        };
      });

      final rooms = <String>[];
      String? from;
      do {
        final page = await api.getMutualRooms('@bob:example.test', from: from);
        rooms.addAll(page.joined);
        from = page.nextBatch;
      } while (from != null);

      expect(rooms, ['!a:example.test', '!b:example.test']);
      expect(requests, hasLength(2));
    });

    test('reads an empty answer and tolerates a missing count', () async {
      final api = _api([], (_) async => _json({'joined': <String>[]}));

      final response = await api.getMutualRooms('@nobody:example.test');

      expect(response.joined, isEmpty);
      expect(response.count, isNull);
      expect(response.nextBatch, isNull);
    });

    test('GetMutualRoomsResponse round-trips through JSON', () {
      final json = {
        'joined': ['!a:example.test'],
        'count': 1,
        'next_batch': 'n',
      };
      expect(GetMutualRoomsResponse.fromJson(json).toJson(), json);
      expect(
        GetMutualRoomsResponse.fromJson({'joined': <String>[]}).toJson(),
        {'joined': <String>[]},
      );
    });

    test('throws M_UNRECOGNIZED when the server does not know the endpoint',
        () async {
      final api = _api(
        [],
        (_) async => _json(
          {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized request'},
          404,
        ),
      );

      expect(
        api.getMutualRooms('@bob:example.test'),
        _throwsMatrixError(MatrixError.M_UNRECOGNIZED),
      );
    });

    test('throws M_INVALID_PARAM on a 400', () async {
      final api = _api(
        [],
        (_) async => _json(
          {'errcode': 'M_INVALID_PARAM', 'error': 'invalid user'},
          400,
        ),
      );

      expect(
        api.getMutualRooms('@me:example.test'),
        _throwsMatrixError(MatrixError.M_INVALID_PARAM),
      );
    });
  });

  group('admin suspend and lock (v1.18, MSC4323)', () {
    const userId = '@bob/x:example.test';
    const encoded = '%40bob%2Fx%3Aexample.test';

    for (final (name, field) in [
      ('suspend', 'suspended'),
      ('lock', 'locked'),
    ]) {
      Future<bool> get(MatrixApi api) => name == 'suspend'
          ? api.getUserSuspended(userId)
          : api.getUserLocked(userId);
      Future<bool> set(MatrixApi api, bool value) => name == 'suspend'
          ? api.setUserSuspended(userId, value)
          : api.setUserLocked(userId, value);

      test('GET /v1/admin/$name/{userId} reads `$field`', () async {
        for (final value in [true, false]) {
          final requests = <http.Request>[];
          final api = _api(requests, (_) async => _json({field: value}));

          expect(await get(api), value);
          final request = requests.single;
          expect(request.method, 'GET');
          expect(request.url.path, '/_matrix/client/v1/admin/$name/$encoded');
          expect(request.url.query, isEmpty);
          expect(request.headers['authorization'], 'Bearer access_tok');
        }
      });

      test('PUT /v1/admin/$name/{userId} sends {$field: bool}', () async {
        for (final value in [true, false]) {
          final requests = <http.Request>[];
          final api = _api(requests, (_) async => _json({field: value}));

          expect(await set(api, value), value);
          final request = requests.single;
          expect(request.method, 'PUT');
          expect(request.url.path, '/_matrix/client/v1/admin/$name/$encoded');
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {field: value});
        }
      });

      test('PUT /v1/admin/$name returns what the server answers', () async {
        final api = _api([], (_) async => _json({field: false}));

        expect(await set(api, true), isFalse);
      });

      test('GET and PUT /v1/admin/$name throw M_FORBIDDEN on a 403', () async {
        final api = _api(
          [],
          (_) async => _json(
            {
              'errcode': 'M_FORBIDDEN',
              'error': 'Requesting user is not a server administrator.',
            },
            403,
          ),
        );

        await expectLater(
          get(api),
          _throwsMatrixError(MatrixError.M_FORBIDDEN),
        );
        await expectLater(
          set(api, true),
          _throwsMatrixError(MatrixError.M_FORBIDDEN),
        );
      });

      test('GET /v1/admin/$name throws M_NOT_FOUND on a 404', () async {
        final api = _api(
          [],
          (_) async => _json(
            {'errcode': 'M_NOT_FOUND', 'error': 'User not found.'},
            404,
          ),
        );

        await expectLater(
          get(api),
          _throwsMatrixError(MatrixError.M_NOT_FOUND),
        );
      });
    }
  });

  group('reportEvent without score (v1.18, MSC4277)', () {
    const roomId = '!room:example.test';
    const eventId = r'$event/1:example.test';
    const reportPath =
        '/_matrix/client/v3/rooms/!room%3Aexample.test/report/%24event%2F1%3Aexample.test';

    test('POSTs only the reason, without a score key', () async {
      final requests = <http.Request>[];
      final api = _api(requests, (_) async => _json({}));

      await api.reportEvent(roomId, eventId, reason: 'spam');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, reportPath);
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body, {'reason': 'spam'});
      expect(body.containsKey('score'), isFalse);
    });

    test('POSTs an empty object without reason or score', () async {
      final requests = <http.Request>[];
      final api = _api(requests, (_) async => _json({}));

      await api.reportEvent(roomId, eventId);

      expect(jsonDecode(requests.single.body), <String, Object?>{});
    });

    test('still sends a score a caller passes on purpose', () async {
      final requests = <http.Request>[];
      final api = _api(requests, (_) async => _json({}));

      // ignore: deprecated_member_use_from_same_package
      await api.reportEvent(roomId, eventId, reason: 'r', score: -100);

      expect(jsonDecode(requests.single.body), {'reason': 'r', 'score': -100});
    });

    test('accepts a 200 with {}, with extra fields or with an empty body',
        () async {
      for (final response in [
        _json({}),
        _json({'report_id': 'r1', 'extra': true}),
        http.Response('', 200),
        http.Response('[]', 200),
      ]) {
        final api = _api([], (_) async => response);
        await expectLater(api.reportEvent(roomId, eventId), completes);
      }
    });

    test('throws M_NOT_FOUND on a 404', () async {
      final api = _api(
        [],
        (_) async =>
            _json({'errcode': 'M_NOT_FOUND', 'error': 'Event not found'}, 404),
      );

      expect(
        api.reportEvent(roomId, eventId, reason: 'spam'),
        _throwsMatrixError(MatrixError.M_NOT_FOUND),
      );
    });
  });

  group('m.room.redaction through PUT /send (v1.18, MSC4169)', () {
    const roomId = '!room:example.test';
    const eventId = r'$target:example.test';
    const sendPath =
        '/_matrix/client/v3/rooms/!room%3Aexample.test/send/m.room.redaction/txn1';
    const redactPath =
        '/_matrix/client/v3/rooms/!room%3Aexample.test/redact/%24target%3Aexample.test/txn1';

    late List<http.Request> requests;
    late Client client;

    Future<Room> setUp({
      List<String>? versions,
      http.Response Function(http.Request request)? onSend,
      http.Response Function(http.Request request)? onRedact,
    }) async {
      requests = [];
      client = Client(
        'redaction_test',
        database: await getDatabase(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/_matrix/client/versions') {
            if (versions == null) {
              return _json({'errcode': 'M_UNKNOWN', 'error': 'down'}, 500);
            }
            return _json({'versions': versions});
          }
          if (request.method == 'PUT' &&
              (path.contains('/send/') || path.contains('/redact/'))) {
            requests.add(request);
            final handler = path.contains('/send/') ? onSend : onRedact;
            return handler?.call(request) ?? _json({'event_id': r'$red'});
          }
          return _json({});
        }),
      );
      client.homeserver = _homeserver;
      client.accessToken = 'access_tok';
      return Room(id: roomId, client: client);
    }

    tearDown(() => client.dispose(closeDatabase: true));

    for (final versions in [
      ['v1.18'],
      ['v1.1', 'v1.19'],
      ['v1.20'],
      ['v1.10.1', 'v2.0'],
    ]) {
      test('$versions: sends redacts and reason in the /send body', () async {
        final room = await setUp(versions: versions);

        final id = await room.redactEvent(
          eventId,
          reason: 'spam',
          txid: 'txn1',
        );

        expect(id, r'$red');
        final request = requests.single;
        expect(request.method, 'PUT');
        expect(request.url.path, sendPath);
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'redacts': eventId,
          'reason': 'spam',
        });
      });
    }

    test('v1.18: leaves reason out when there is none', () async {
      final room = await setUp(versions: ['v1.18']);

      await room.redactEvent(eventId, txid: 'txn1');

      expect(requests.single.url.path, sendPath);
      expect(jsonDecode(requests.single.body), {'redacts': eventId});
    });

    test('v1.18: Event.redactEvent takes the same /send path', () async {
      final room = await setUp(versions: ['v1.18']);
      final event = Event(
        eventId: eventId,
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': 'hi'},
        senderId: '@alice:example.test',
        originServerTs: DateTime.now(),
        room: room,
      );

      await event.redactEvent(reason: 'oops', txid: 'txn1');

      expect(requests.single.url.path, sendPath);
      expect(jsonDecode(requests.single.body), {
        'redacts': eventId,
        'reason': 'oops',
      });
    });

    for (final versions in [
      ['v1.17'],
      ['v1.1', 'v1.11', 'v1.17'],
      ['r0.6.1'],
      ['v1', 'v2', 'v1.18.0', 'v1.x'],
      <String>[],
    ]) {
      test('$versions: falls back to PUT /redact', () async {
        final room = await setUp(versions: versions);

        final id = await room.redactEvent(
          eventId,
          reason: 'spam',
          txid: 'txn1',
        );

        expect(id, r'$red');
        final request = requests.single;
        expect(request.method, 'PUT');
        expect(request.url.path, redactPath);
        expect(jsonDecode(request.body), {'reason': 'spam'});
      });
    }

    test('falls back to PUT /redact when the versions cannot be read',
        () async {
      final room = await setUp();

      await room.redactEvent(eventId, txid: 'txn1');

      expect(requests.single.url.path, redactPath);
      expect(jsonDecode(requests.single.body), <String, Object?>{});
    });

    test('v1.18: falls back to PUT /redact when /send is M_UNRECOGNIZED',
        () async {
      final room = await setUp(
        versions: ['v1.18'],
        onSend: (_) => _json(
          {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized request'},
          404,
        ),
      );

      final id = await room.redactEvent(eventId, reason: 'spam', txid: 'txn1');

      expect(id, r'$red');
      expect(requests.map((r) => r.url.path), [sendPath, redactPath]);
      expect(jsonDecode(requests.last.body), {'reason': 'spam'});
    });

    test('v1.18: other /send errors are not retried on /redact', () async {
      final room = await setUp(
        versions: ['v1.18'],
        onSend: (_) => _json(
          {'errcode': 'M_FORBIDDEN', 'error': 'not allowed'},
          403,
        ),
      );

      await expectLater(
        room.redactEvent(eventId, txid: 'txn1'),
        _throwsMatrixError(MatrixError.M_FORBIDDEN),
      );
      expect(requests.map((r) => r.url.path), [sendPath]);
    });

    test('generates a transaction id when none is given', () async {
      final room = await setUp(versions: ['v1.18']);

      await room.redactEvent(eventId);

      final path = requests.single.url.path;
      expect(
        path,
        startsWith(
          '/_matrix/client/v3/rooms/!room%3Aexample.test/send/m.room.redaction/msg',
        ),
      );
    });
  });
}
