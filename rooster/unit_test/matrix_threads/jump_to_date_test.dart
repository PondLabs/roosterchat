// Criterion 4: "Jump to date" asks `timestamp_to_event` (Matrix v1.6,
// MSC3030) with the time in milliseconds and the direction `f` or `b`,
// takes the timeline to the event it returns, and says why in the app's
// language when the room has none there (M_NOT_FOUND) or the server
// predates v1.6.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/ui/organisms/chat/jump_to_date.dart';

import 'harness.dart';

Iterable<Seen> lookups(Script script) =>
    script.where('GET', '/timestamp_to_event');

/// Answers `timestamp_to_event`: an event for the directions in [found],
/// M_NOT_FOUND for the others.
http.Response? Function(Seen) timestamps(Map<String, String> found) => (r) {
      if (!r.path.endsWith('/timestamp_to_event')) return null;
      final id = found[r.url.queryParameters['dir']];
      if (id == null) return matrixError('M_NOT_FOUND', status: 404);
      return json({'event_id': id, 'origin_server_ts': 1});
    };

void main() {
  setUpAll(prepareTests);

  final day = DateTime(2026, 3, 14);

  test('asks for the first event at or after the time, in milliseconds',
      () async {
    final (script, _, room) = await threadAccount(routes: [
      timestamps({'f': r'$first'}),
    ]);
    final at = DateTime.utc(2026, 3, 14, 9, 30);

    final id = await MatrixJumpToDate.eventIdAt(room.matrixRoom, at);

    expect(id, r'$first');
    final url = lookups(script).single.url;
    expect(
        url.path,
        '/_matrix/client/v1/rooms/'
        '${Uri.encodeComponent(room.matrixRoom.id)}/timestamp_to_event');
    expect(url.queryParameters['ts'], '${at.millisecondsSinceEpoch}');
    expect(url.queryParameters['dir'], 'f');
  });

  test('asks backwards with dir=b', () async {
    final (script, _, room) = await threadAccount(routes: [
      timestamps({'b': r'$last'}),
    ]);

    final id = await MatrixJumpToDate.eventIdAt(room.matrixRoom, day,
        direction: matrix.Direction.b);

    expect(id, r'$last');
    expect(lookups(script).single.url.queryParameters['dir'], 'b');
  });

  test(
      "a day starts at its local midnight, and falls back to the last "
      "event before it", () async {
    final (script, _, room) = await threadAccount(routes: [
      timestamps({'b': r'$before'}),
    ]);

    final id = await MatrixJumpToDate.eventIdForDay(
        room.matrixRoom, DateTime(2026, 3, 14, 18, 45));

    expect(id, r'$before');
    expect(
        lookups(script).map((s) => s.url.queryParameters['dir']), ['f', 'b']);
    expect(lookups(script).map((s) => s.url.queryParameters['ts']).toSet(),
        {'${day.millisecondsSinceEpoch}'});
  });

  test('M_NOT_FOUND both ways is "not found"', () async {
    final (_, _, room) = await threadAccount(routes: [
      timestamps({}),
    ]);

    await expectLater(
        MatrixJumpToDate.eventIdForDay(room.matrixRoom, day),
        throwsA(isA<JumpToDateException>()
            .having((e) => e.failure, 'failure', JumpToDateFailure.notFound)));
  });

  test('a server before Matrix v1.6 is not asked', () async {
    final (script, _, room) = await threadAccount(versions: [
      'v1.1',
      'v1.5'
    ], routes: [
      timestamps({'f': r'$x'})
    ]);

    await expectLater(
        MatrixJumpToDate.eventIdAt(room.matrixRoom, day),
        throwsA(isA<JumpToDateException>().having(
            (e) => e.failure, 'failure', JumpToDateFailure.unsupported)));
    expect(lookups(script), isEmpty);
  });

  test('a server without the endpoint is "unsupported"', () async {
    final (_, _, room) = await threadAccount(routes: [
      (r) => r.path.endsWith('/timestamp_to_event')
          ? matrixError('M_UNRECOGNIZED', status: 404)
          : null,
    ]);

    await expectLater(
        MatrixJumpToDate.eventIdAt(room.matrixRoom, day),
        throwsA(isA<JumpToDateException>().having(
            (e) => e.failure, 'failure', JumpToDateFailure.unsupported)));
  });

  group('JumpToDate.jumpToDay', () {
    Future<(List<String>, List<String>)> jump(
        List<http.Response? Function(Seen)> routes,
        {List<String> versions = const ['v1.1', 'v1.6']}) async {
      final (_, _, room) =
          await threadAccount(versions: versions, routes: routes);
      final jumped = <String>[];
      final said = <String>[];
      await JumpToDate.jumpToDay(room, day, jump: jumped.add, notify: said.add);
      return (jumped, said);
    }

    test('takes the timeline to the event found', () async {
      final (jumped, said) = await jump([
        timestamps({'f': r'$first'}),
      ]);
      expect(jumped, [r'$first']);
      expect(said, isEmpty);
    });

    test('says there are no messages there', () async {
      final (jumped, said) = await jump([timestamps({})]);
      expect(jumped, isEmpty);
      expect(said, [JumpToDate.messageJumpToDateNotFound]);
      expect(said.single, 'There are no messages around that date');
    });

    test('says the server is too old', () async {
      final (jumped, said) = await jump([
        timestamps({'f': r'$x'})
      ], versions: [
        'v1.1',
        'v1.5'
      ]);
      expect(jumped, isEmpty);
      expect(said, [JumpToDate.messageJumpToDateUnsupported]);
    });

    test('says it failed when the server does not answer', () async {
      final (jumped, said) = await jump([
        (r) => r.path.endsWith('/timestamp_to_event')
            ? matrixError('M_UNKNOWN', status: 500)
            : null,
      ]);
      expect(jumped, isEmpty);
      expect(said, [JumpToDate.errorJumpToDateFailed]);
    });
  });
}
