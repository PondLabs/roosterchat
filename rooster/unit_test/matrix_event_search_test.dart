import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class Api implements matrix.Client {
  final cursors = <String?>[];
  bool fail = false;
  @override
  Future<matrix.SearchResults> search(
    matrix.Categories categories, {
    String? nextBatch,
  }) async {
    cursors.add(nextBatch);
    if (fail) throw StateError('offline');
    return matrix.SearchResults.fromJson({
      'search_categories': {
        'room_events': {
          if (nextBatch == null) 'next_batch': 'page2',
          'results': [
            for (final id in nextBatch == null ? ['a', 'b'] : ['b', 'c'])
              {
                'result': {
                  'event_id': id,
                  'sender': '@user:example.com',
                  'origin_server_ts': 1,
                  'type': 'm.room.message',
                  'content': {'msgtype': 'm.text', 'body': id},
                },
              },
          ],
        },
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClientAdapter implements MatrixClient {
  ClientAdapter(this.matrixClient);
  @override
  final matrix.Client matrixClient;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Event implements TimelineEvent {
  Event(this.eventId);
  @override
  final String eventId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RoomAdapter implements MatrixRoom {
  @override
  String get identifier => '!room:example.com';
  @override
  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) =>
      Event(event.eventId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SdkTimeline implements matrix.Timeline {
  SdkTimeline(matrix.Client client)
      : room = matrix.Room(id: '!room:example.com', client: client);
  @override
  final matrix.Room room;
  List<(List<matrix.Event>, String?)> chunks = [];
  bool fail = false;
  @override
  Stream<(List<matrix.Event>, String?)> startSearch({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    String? sinceEventId,
    int? limit,
    bool Function(matrix.Event)? searchFunc,
  }) async* {
    if (fail) throw StateError('offline');
    yield* Stream.fromIterable(chunks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TimelineAdapter implements MatrixTimeline {
  TimelineAdapter(Api api)
      : client = ClientAdapter(api),
        matrixTimeline = SdkTimeline(api);
  @override
  final Client client;
  @override
  final Room room = RoomAdapter();
  @override
  final matrix.Timeline matrixTimeline;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('server pagination retains previous hits without duplicates', () async {
    final api = Api();
    final session = MatrixServerEventSearchSession(TimelineAdapter(api));
    final first = await session.startSearch('hello').single;
    expect(first.map((event) => event.eventId), ['a', 'b']);
    expect(session.canContinueSearch, isTrue);
    final second = await session.continueSearch().single;
    expect(second.map((event) => event.eventId), ['a', 'b', 'c']);
    expect(first.map((event) => event.eventId), ['a', 'b']);
    expect(api.cursors, [null, 'page2']);
    expect(session.canContinueSearch, isFalse);
    expect(session.currentlySearching, isFalse);
    final reset = await session.startSearch('new query').single;
    expect(reset.map((event) => event.eventId), ['a', 'b']);
  });

  test('server errors reach the stream and finish the loading state', () async {
    final api = Api()..fail = true;
    final session = MatrixServerEventSearchSession(TimelineAdapter(api));
    await expectLater(session.startSearch('hello'), emitsError(isStateError));
    expect(session.currentlySearching, isFalse);
    api.fail = false;
    expect(await session.startSearch('hello').single, hasLength(2));
  });

  test('encrypted search clears an exhausted cursor and loading on failure',
      () async {
    final timeline = TimelineAdapter(Api());
    final sdk = timeline.matrixTimeline as SdkTimeline;
    final session = MatrixEncryptedRoomEventSearchSession(timeline);
    sdk.chunks = [([], 'older')];
    await session.startSearch('hello').drain<void>();
    expect(session.canContinueSearch, isTrue);
    sdk.chunks = [([], null)];
    await session.continueSearch().drain<void>();
    expect(session.canContinueSearch, isFalse);
    sdk.fail = true;
    await expectLater(session.startSearch('hello'), emitsError(isStateError));
    expect(session.currentlySearching, isFalse);
  });
}
