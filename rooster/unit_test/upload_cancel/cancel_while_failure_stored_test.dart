@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';

/// [OnlyUsTransport] whose members requests are refused for good (403):
/// a text's encryption fails for good. The first one waits for [hold].
class _MembersRefused extends OnlyUsTransport {
  Completer<void>? hold;
  bool held = false;
  int membersAsked = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      membersAsked++;
      final waiting = hold;
      if (waiting != null) {
        held = true;
        hold = null;
        await waiting.future;
      }
      return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not a member'});
    }
    return super.send(request);
  }
}

/// [OnlyUsTransport] whose members requests fail as offline: the SDK
/// tries the text again after its wait between attempts.
class _MembersOffline extends OnlyUsTransport {
  int refused = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      refused++;
      throw http.ClientException('Connection failed', request.url);
    }
    return super.send(request);
  }
}

/// The client of [mx] closed and started again on what it stored, as the
/// app is: its account, its room and their events, read from [mx]'s
/// database.
Future<(matrix.Client, matrix.Room)> _reopen(
    matrix.Client mx, http.Client transport) async {
  final name = mx.clientName;
  final sqlite = (mx.database as matrix.MatrixSdkDatabase).database!;
  await mx.dispose(closeDatabase: false);
  final again = matrix.Client(name,
      database: await matrix.MatrixSdkDatabase.init(name,
          database: sqlite, sqfliteFactory: databaseFactoryFfi),
      httpClient: transport,
      sendClock: ManualSendClock());
  FakeMatrixApi.client = again;
  await again.init();
  await again.abortSync();
  again.backgroundSync = false;
  return (again, again.getRoomById(roomId)!);
}

void main() {
  setUpAll(initVodozemac);

  test(
      'a text in an encrypted room, not the last message, cancelled 0 to 40 '
      'microtask turns and 0 to 10 timer turns after its encryption is '
      'refused for good: no row of it is left, and none comes back once the '
      'client is opened again',
      skip: skipWithoutVodozemac, () async {
    final left = <String>[];
    final back = <String>[];
    var taken = 0;
    Future<void> run(String kind, int turns) async {
      final name = 'cancel_failure_stored_${kind}_$turns';
      final transport = _MembersRefused();
      final (mx, room) = await cryptoClient(name, transport, encrypted: true);
      final echoes = <matrix.Event>[];
      mx.onTimelineEvent.stream.listen(echoes.add);
      const txid = 'txn_cancelled';
      final hold = transport.hold = Completer<void>();
      final sending = room.sendEvent({'msgtype': 'm.text', 'body': 'text'},
          txid: txid).then<String?>((id) => id, onError: (Object _) => null);
      await until(() => transport.held);
      final menuEvent = echoes.lastWhere((e) => e.eventId == txid);
      // A text behind it: the cancelled one is not the room's last event.
      final behind = room.sendEvent({'msgtype': 'm.text', 'body': 'behind'},
          txid:
              'txn_behind').then<String?>((id) => id,
          onError: (Object _) => null);
      await until(() => echoes.any((e) => e.eventId == 'txn_behind'));

      hold.complete();
      for (var i = 0; i < turns; i++) {
        if (kind == 'micro') {
          await null;
        } else {
          await Future<void>.delayed(Duration.zero);
        }
      }
      // As the app does: asks the room, then the event.
      var cancelled = false;
      if (room.canCancelSend(txid)) {
        await menuEvent.cancelSend();
        cancelled = true;
        taken++;
      }
      await sending;
      await behind;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final at = '${kind[0]}$turns';
      if (cancelled) {
        final stored = await mx.database.getEventById(txid, room);
        final timeline = await room.getTimeline();
        final listed = timeline.events.where((e) => e.eventId == txid);
        timeline.cancelSubscriptions();
        if (stored != null || listed.isNotEmpty) {
          left.add('$at: stored ${stored?.status.name}, listed '
              '${listed.map((e) => e.status.name).toList()}');
        }
      }
      expect(transport.events, isEmpty, reason: 'nothing was sent');

      // The app closed and started again on what it stored.
      final (again, roomAgain) = await _reopen(mx, transport);
      if (cancelled) {
        final stored = await again.database.getEventById(txid, roomAgain);
        final timeline = await roomAgain.getTimeline();
        final listed = timeline.events.where((e) => e.eventId == txid);
        timeline.cancelSubscriptions();
        if (stored != null ||
            listed.isNotEmpty ||
            roomAgain.lastEvent?.eventId == txid) {
          back.add('$at: stored ${stored?.status.name}, listed '
              '${listed.map((e) => e.status.name).toList()}');
        }
      }
      await again.dispose(closeDatabase: true);
    }

    for (var turns = 0; turns <= 40; turns++) {
      await run('micro', turns);
    }
    for (var turns = 0; turns <= 10; turns++) {
      await run('timer', turns);
    }
    print('cancels taken: $taken of 52; left in the database or a timeline: '
        '$left; back after the client opened again: $back');
    expect(taken, greaterThan(40));
    expect(left, isEmpty);
    expect(back, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test(
      'a text cancelled during the wait between two attempts ends at once: '
      'well under the 1 s the wait lasts',
      skip: skipWithoutVodozemac, () async {
    final transport = _MembersOffline();
    final (mx, room) =
        await cryptoClient('cancel_during_wait', transport, encrypted: true);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final sending =
        room.sendEvent({'msgtype': 'm.text', 'body': 'hello'}, txid: 'txn_w');
    // The first attempt failed: the wait of the second has just begun.
    await until(() => transport.refused >= 1,
        limit: const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final clock = Stopwatch()..start();
    await echoes.lastWhere((e) => e.eventId == 'txn_w').cancelSend();
    final id = await sending.timeout(const Duration(seconds: 5));
    final ended = clock.elapsed;

    print('cancelled during the wait between attempts: ended $ended after '
        'the Cancel, attempts ${transport.refused}');
    expect(id, isNull);
    expect(ended, lessThan(const Duration(milliseconds: 500)));
    expect(transport.refused, 1, reason: 'no second attempt');
    await mx.dispose(closeDatabase: true);
  });
}
