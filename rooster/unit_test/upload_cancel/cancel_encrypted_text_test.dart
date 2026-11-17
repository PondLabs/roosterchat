@TestOn('vm')
library;

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
}
