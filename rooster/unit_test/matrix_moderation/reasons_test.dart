// Criterion 2: kick, ban, invite and redact send `reason` when one is given
// and leave the key out when it is empty or blank.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';

import 'fakes.dart';

const target = '@target:example.org';
const eventId = r'$message:example.org';

void main() {
  late Script script;
  late matrix.Room room;
  late MatrixRoomModeration moderation;

  setUp(() {
    (script, room) = moderatedRoom();
    moderation = MatrixRoomModeration(room);
  });

  Seen only(String method, String path) {
    final sent = script.where(method, path).toList();
    expect(sent, hasLength(1), reason: '$method $path in ${script.seen}');
    return sent.single;
  }

  for (final (action, path) in [
    ('kick', '/rooms/$roomId/kick'),
    ('ban', '/rooms/$roomId/ban'),
    ('invite', '/rooms/$roomId/invite'),
  ]) {
    Future<void> run(String? reason) => switch (action) {
          'kick' => moderation.kick(target, reason: reason),
          'ban' => moderation.ban(target, reason: reason),
          _ => moderation.invite(target, reason: reason),
        };

    group(action, () {
      test('sends the trimmed reason', () async {
        await run('  flooding the room ');
        expect(only('POST', path).body,
            {'user_id': target, 'reason': 'flooding the room'});
      });

      for (final reason in [null, '', '   ']) {
        test('leaves the reason out when it is "$reason"', () async {
          await run(reason);
          expect(only('POST', path).body, {'user_id': target});
        });
      }
    });
  }

  group('redact', () {
    test('on a v1.18 server, sends the reason with the redaction', () async {
      script.routes.add((r) => r.path.endsWith('/versions')
          ? json({
              'versions': ['v1.18']
            })
          : null);
      script.routes.add((r) => r.method == 'PUT' && r.path.contains('/send/')
          ? json({'event_id': r'$redaction'})
          : null);

      await moderation.redact(eventId, reason: ' off-topic ');

      final sent = only('PUT', '/send/m.room.redaction/');
      expect(sent.body, {'redacts': eventId, 'reason': 'off-topic'});
    });

    test('on an older server, sends the reason to /redact', () async {
      await moderation.redact(eventId, reason: 'off-topic');
      expect(only('PUT', '/redact/$eventId/').body, {'reason': 'off-topic'});
    });

    for (final reason in [null, '', '  ']) {
      test('leaves the reason out when it is "$reason"', () async {
        await moderation.redact(eventId, reason: reason);
        expect(only('PUT', '/redact/$eventId/').body, isEmpty);
      });
    }
  });

  test('cleanReason trims, and gives null for blanks', () {
    expect(MatrixRoomModeration.cleanReason(' a b '), 'a b');
    expect(MatrixRoomModeration.cleanReason(' \n '), isNull);
    expect(MatrixRoomModeration.cleanReason(null), isNull);
  });
}
