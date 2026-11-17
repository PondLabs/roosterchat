@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';

import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';

/// [OnlyUsTransport] whose room members request fails, as offline: the
/// text's encryption cannot finish, and the SDK tries again every second.
class _MembersOffline extends OnlyUsTransport {
  _MembersOffline({this.offline = true});

  final bool offline;
  int refused = 0;
  int membersAsked = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      membersAsked++;
      if (offline) {
        refused++;
        throw http.ClientException('Connection failed', request.url);
      }
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());
  setUpAll(initVodozemac);

  test(
      'a text in an encrypted room whose encryption cannot finish, '
      'cancelled: it ends at once and never comes back as failed (probe A1)',
      skip: skipWithoutVodozemac, () async {
    final transport = _MembersOffline();
    final (mx, room) =
        await cryptoClient('cancel_encrypted_text', transport, encrypted: true);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final sending = room
        .sendEvent({'msgtype': 'm.text', 'body': 'hello'}, txid: 'txn_text');
    await until(() =>
        echoes.any((e) => e.eventId == 'txn_text') && transport.refused >= 2);
    expect(room.canCancelSend('txn_text'), isTrue);

    final shownBefore = echoes.length;
    final clock = Stopwatch()..start();
    await echoes.lastWhere((e) => e.eventId == 'txn_text').cancelSend();
    final id = await sending.timeout(const Duration(seconds: 5));
    final endedAfter = clock.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final shownAgain = echoes
        .skip(shownBefore)
        .where((e) => e.eventId == 'txn_text')
        .map((e) => e.status)
        .toList();
    print('encrypted text cancelled while its encryption failed: ended '
        '$endedAfter after the Cancel, id $id, PUT /send '
        '${transport.events.length}, shown again $shownAgain, members '
        'requests refused ${transport.refused}');
    expect(id, isNull);
    expect(endedAfter, lessThan(const Duration(seconds: 2)));
    expect(transport.events, isEmpty);
    expect(shownAgain, isEmpty);
    expect(await mx.database.getEventById('txn_text', room), isNull);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a text in an encrypted room cancelled before its first attempt is '
      'not encrypted: no members request, no PUT /send',
      skip: skipWithoutVodozemac, () async {
    final transport = _MembersOffline(offline: false);
    final (mx, room) =
        await cryptoClient('cancel_before_attempt', transport, encrypted: true);
    transport.membersAsked = 0;

    final sending = room
        .sendEvent({'msgtype': 'm.text', 'body': 'hello'}, txid: 'txn_early');
    expect(room.cancelSending('txn_early'), isTrue);
    expect(await sending, isNull);

    print('encrypted text cancelled before its first attempt: members '
        'requests ${transport.membersAsked}, PUT /send '
        '${transport.events.length}');
    expect(transport.membersAsked, 0);
    expect(transport.events, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a text cancelled while its encryption waits on the server, which then '
      'refuses for good: not shown as failed, not stored',
      skip: skipWithoutVodozemac, () async {
    final transport = _HeldMembers();
    final (mx, room) =
        await cryptoClient('cancel_then_refused', transport, encrypted: true);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final hold = transport.hold = Completer<void>();

    final sending = room
        .sendEvent({'msgtype': 'm.text', 'body': 'hello'}, txid: 'txn_refused');
    await until(() => transport.held);
    final shownBefore = echoes.length;
    await echoes.lastWhere((e) => e.eventId == 'txn_refused').cancelSend();
    hold.complete();
    final id = await sending;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final shownAgain = echoes
        .skip(shownBefore)
        .where((e) => e.eventId == 'txn_refused')
        .map((e) => e.status)
        .toList();
    print('encrypted text cancelled, then its members request refused: id '
        '$id, shown again $shownAgain, stored '
        '${await mx.database.getEventById('txn_refused', room) != null}');
    expect(id, isNull);
    expect(shownAgain, isEmpty);
    expect(await mx.database.getEventById('txn_refused', room), isNull);
    expect(transport.events, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a text cancelled while its encryption waits on the server, which then '
      'answers: the encrypted event never leaves',
      skip: skipWithoutVodozemac, () async {
    final transport = _HeldMembers(answer: true);
    final (mx, room) = await cryptoClient('cancel_while_encrypting', transport,
        encrypted: true);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    final hold = transport.hold = Completer<void>();

    final sending = room.sendEvent({'msgtype': 'm.text', 'body': 'hello'},
        txid: 'txn_encrypting');
    await until(() => transport.held);
    await echoes.lastWhere((e) => e.eventId == 'txn_encrypting').cancelSend();
    hold.complete();
    final id = await sending;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    print('encrypted text cancelled during its encryption: id $id, PUT /send '
        '${transport.events.length}, stored '
        '${await mx.database.getEventById('txn_encrypting', room) != null}');
    expect(id, isNull);
    expect(transport.events, isEmpty);
    expect(await mx.database.getEventById('txn_encrypting', room), isNull);
    await mx.dispose(closeDatabase: true);
  });
}

/// [OnlyUsTransport] whose next members request waits for [hold], then is
/// refused for good (403 `M_FORBIDDEN`), or answered with [answer].
class _HeldMembers extends OnlyUsTransport {
  _HeldMembers({this.answer = false});

  final bool answer;
  Completer<void>? hold;
  bool held = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final waiting = hold;
    if (waiting != null &&
        request.method == 'GET' &&
        request.url.path.endsWith('/members')) {
      held = true;
      hold = null;
      await waiting.future;
      if (answer) return super.send(request);
      return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not a member'});
    }
    return super.send(request);
  }
}
