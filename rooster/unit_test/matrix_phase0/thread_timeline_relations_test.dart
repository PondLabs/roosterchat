import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';

import 'test_helpers.dart';

void main() {
  const roomId = '!room/a+b:example.test';
  const rootId = r'$root+1/2=3';

  group('MatrixThreadTimeline.getThreadEvents', () {
    test(
      'uses stable v1 getRelatingEventsWithRelType with URL-encoded IDs and '
      'appends root on final page',
      () async {
        final seen = <Uri>[];
        final mx = matrix.Client(
          'thread_test',
          database: MemoryCacheDatabase(),
          httpClient: MockClient((request) async {
            seen.add(request.url);
            return http.Response(
              jsonEncode({
                'chunk': [
                  {
                    'type': 'm.room.message',
                    'event_id': r'$reply1',
                    'sender': '@alice:example.test',
                    'origin_server_ts': 1000,
                    'content': {
                      'msgtype': 'm.text',
                      'body': 'hello in thread',
                      'm.relates_to': {
                        'rel_type': 'm.thread',
                        'event_id': rootId,
                      },
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        )
          ..homeserver = Uri.parse('http://127.0.0.1:9')
          ..accessToken = 'test-token';

        final mxRoom = matrix.Room(id: roomId, client: mx);
        final client = _StubMatrixClient(mx);
        final rootEvent = _FakeTimelineEvent(
          matrix.Event(
            type: matrix.EventTypes.Message,
            eventId: rootId,
            senderId: '@bob:example.test',
            originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
            content: {'msgtype': 'm.text', 'body': 'thread root'},
            room: mxRoom,
          ),
          client: client,
        );
        final room = _StubMatrixRoom(client, mxRoom);
        final mainTimeline =
            _StubMatrixTimeline(knownEvents: {rootId: rootEvent});

        final threadTimeline = MatrixThreadTimeline(
          client: client,
          room: room,
          threadRootId: rootId,
          mainRoomTimeline: mainTimeline,
          component: _StubThreadsComponent(),
        );
        addTearDown(threadTimeline.close);

        final events = await threadTimeline.getThreadEvents(
          limit: 15,
          nextBatch: 'tok_prev',
        );

        expect(seen, hasLength(1));
        final url = seen.single;
        expect(url.path, isNot(contains('/client/unstable/')));
        expect(
          url.path,
          '/_matrix/client/v1/rooms/'
          '${Uri.encodeComponent(roomId)}/relations/'
          '${Uri.encodeComponent(rootId)}/m.thread',
        );
        expect(url.queryParameters['limit'], '15');
        expect(url.queryParameters['from'], 'tok_prev');
        expect(threadTimeline.finished, isTrue);
        expect(events.map((e) => e.eventId).toList(), [r'$reply1', rootId]);
      },
    );

    test('keeps paginating when next_batch is present and handles missing root',
        () async {
      var call = 0;
      final mx = matrix.Client(
        'thread_paging_test',
        database: MemoryCacheDatabase(),
        httpClient: MockClient((request) async {
          call++;
          return http.Response(
            jsonEncode({
              'chunk': [
                {
                  'type': 'm.room.message',
                  'event_id': '\$reply$call',
                  'sender': '@alice:example.test',
                  'origin_server_ts': 1000 + call,
                  'content': {'msgtype': 'm.text', 'body': 'page $call'},
                },
              ],
              if (call == 1) 'next_batch': 'page_2',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )
        ..homeserver = Uri.parse('http://127.0.0.1:9')
        ..accessToken = 'test-token';

      final mxRoom = matrix.Room(id: roomId, client: mx);
      final client = _StubMatrixClient(mx);
      final room = _StubMatrixRoom(client, mxRoom);
      final mainTimeline = _StubMatrixTimeline(failFetch: true);

      final threadTimeline = MatrixThreadTimeline(
        client: client,
        room: room,
        threadRootId: rootId,
        mainRoomTimeline: mainTimeline,
        component: _StubThreadsComponent(),
      );
      addTearDown(threadTimeline.close);

      final page1 = await threadTimeline.getThreadEvents();
      expect(threadTimeline.finished, isFalse);
      expect(threadTimeline.nextBatch, 'page_2');
      expect(page1.map((e) => e.eventId).toList(), [r'$reply1']);

      final page2 = await threadTimeline.getThreadEvents(
          nextBatch: threadTimeline.nextBatch);
      expect(threadTimeline.finished, isTrue);
      expect(threadTimeline.nextBatch, isNull);
      expect(page2.map((e) => e.eventId).toList(), [r'$reply2']);
    });
  });
}

class _StubMatrixClient implements MatrixClient {
  _StubMatrixClient(this._mx);
  final matrix.Client _mx;

  @override
  matrix.Client getMatrixClient() => _mx;

  @override
  matrix.Client get matrixClient => _mx;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMatrixRoom implements MatrixRoom {
  _StubMatrixRoom(this._client, this.matrixRoom);
  final MatrixClient _client;

  @override
  final matrix.Room matrixRoom;

  @override
  String get identifier => matrixRoom.id;

  @override
  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) =>
      _FakeTimelineEvent(event, client: _client);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimelineEvent extends MatrixTimelineEvent {
  _FakeTimelineEvent(super.event, {required super.client});
}

class _StubMatrixTimeline implements MatrixTimeline {
  _StubMatrixTimeline({
    this.knownEvents = const {},
    this.failFetch = false,
  });

  final Map<String, TimelineEvent> knownEvents;
  final bool failFetch;

  @override
  StreamController<int> onEventAdded = StreamController.broadcast();

  @override
  StreamController<int> onChange = StreamController.broadcast();

  @override
  StreamController<int> onRemove = StreamController.broadcast();

  @override
  matrix.Timeline? get matrixTimeline => null;

  @override
  TimelineEvent? tryGetEvent(String eventId) => knownEvents[eventId];

  @override
  Future<TimelineEvent?> fetchEventById(String eventId) async {
    if (failFetch) {
      throw Exception('Root event unavailable');
    }
    return knownEvents[eventId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubThreadsComponent implements ThreadsComponent {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
