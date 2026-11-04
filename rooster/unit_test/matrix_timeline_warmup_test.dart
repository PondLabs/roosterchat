import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/models/timeline_chunk.dart' as chunk;

class _NoDatabase implements matrix.DatabaseApi {
  @override
  Future<List<matrix.Event>> getUnimportantRoomEventStatesForRoom(
          List<String> types, matrix.Room room) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the events whose previews are warmed. Everything else of a
/// preview component the timeline does not touch while warming.
class _SpyComponent implements UrlPreviewComponent<MatrixClient> {
  final List<TimelineEvent> warmed = [];

  @override
  void warmUpPreviews(Timeline timeline, Iterable<TimelineEvent> events) {
    warmed.addAll(events);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A message with a link in its formatted body, as history delivers one.
matrix.Event _message(matrix.Room room, String eventId, String link) =>
    matrix.Event.fromJson({
      'type': 'm.room.message',
      'event_id': eventId,
      'sender': '@someone:example.com',
      'origin_server_ts': 0,
      'content': {
        'msgtype': 'm.text',
        'format': 'org.matrix.custom.html',
        'formatted_body': 'have a look at <a href="$link">$link</a>',
      },
    }, room);

MatrixClient _client() {
  final client =
      MatrixClient(identifier: 'timeline-warm-up', database: _NoDatabase());
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyComponent spy;
  late MatrixClient client;
  late MatrixRoom room;
  late matrix.Room mxRoom;

  setUp(() {
    spy = _SpyComponent();
    client = _client();
    client.componentsInternal
        .removeWhere((component) => component is UrlPreviewComponent);
    client.componentsInternal.add(spy);

    final mx = client.getMatrixClient();
    mxRoom = matrix.Room(id: '!room:example.com', client: mx);
    room = MatrixRoom(client, mxRoom, mx);
  });

  test('the timeline as it opens warms every message it was given', () {
    final sdkTimeline = matrix.Timeline(
        room: mxRoom,
        chunk: chunk.TimelineChunk(events: [
          _message(mxRoom, r'$page', 'https://example.com/article'),
          _message(
              mxRoom, r'$yt', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          // A message without a link is filtered by the component's own
          // predicate; the spy sees what the component was handed.
        ]));

    final timeline =
        MatrixTimeline(client, room, mxRoom, initialTimeline: sdkTimeline);

    expect(timeline.events, hasLength(2));
    expect(spy.warmed.map((event) => event.eventId), [r'$page', r'$yt'],
        reason: 'open a room and its links are already being fetched, '
            'not fetched when each message first builds');
  });

  test('a page of history is warmed while it is being converted', () {
    final sdkTimeline =
        matrix.Timeline(room: mxRoom, chunk: chunk.TimelineChunk(events: []));
    final timeline =
        MatrixTimeline(client, room, mxRoom, initialTimeline: sdkTimeline);
    expect(spy.warmed, isEmpty);

    sdkTimeline.chunk.events
        .add(_message(mxRoom, r'$old', 'https://x.com/someone/status/123'));
    timeline.onEventInserted(0);

    expect(spy.warmed.single.eventId, r'$old',
        reason: 'history arrives, warm-up starts, and the card is later '
            'found finished when the message scrolls into view');
  });
}
