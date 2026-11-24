// Criterion 1: the members with membership `ban` are listed from the server
// and unbanned with an optional reason; the list only changes once the
// server agreed, so `M_FORBIDDEN` leaves it as it was.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';

import 'fakes.dart';

const membersPath = '/_matrix/client/v3/rooms/$roomId/members';
const unbanPath = '/_matrix/client/v3/rooms/$roomId/unban';

http.Response? bannedMembers(Seen r) =>
    r.method == 'GET' && r.path == membersPath
        ? json({
            'chunk': [
              memberEvent('@troll:example.org', 'ban',
                  reason: 'spam', displayName: 'Troll'),
              memberEvent('@another:other.org', 'ban'),
              // A server that ignores the filter must not list these.
              memberEvent('@friend:example.org', 'join'),
              memberEvent('@left:example.org', 'leave'),
            ]
          })
        : null;

http.Response? acceptUnban(Seen r) =>
    r.method == 'POST' && r.path == unbanPath ? json({}) : null;

void main() {
  late Script script;
  late matrix.Room room;
  late BannedMembersList list;

  setUp(() {
    (script, room) = moderatedRoom();
    script.routes.add(bannedMembers);
    list = BannedMembersList(MatrixRoomModeration(room));
  });

  test('asks the server for the members with membership ban', () async {
    await list.refresh();

    final asked = script.where('GET', membersPath).single;
    expect(asked.url.queryParameters['membership'], 'ban');
    expect(list.members.map((m) => m.userId),
        ['@another:other.org', '@troll:example.org']);
    final troll = list.members.last;
    expect(troll.displayName, 'Troll');
    expect(troll.reason, 'spam');
    expect(troll.bannedBy, '@mod:example.org');
    expect(list.members.first.reason, isNull);
  });

  test('unban posts the user and the reason, then drops them from the list',
      () async {
    script.routes.add(acceptUnban);
    await list.refresh();

    await list.unban('@troll:example.org', reason: '  served their time ');

    final sent = script.where('POST', unbanPath).single;
    expect(sent.body,
        {'user_id': '@troll:example.org', 'reason': 'served their time'});
    expect(list.members.map((m) => m.userId), ['@another:other.org']);
  });

  test('unban without a reason sends no reason key', () async {
    script.routes.add(acceptUnban);
    await list.refresh();

    for (final reason in [null, '', '  ']) {
      await list.unban('@another:other.org', reason: reason);
    }
    for (final sent in script.where('POST', unbanPath)) {
      expect(sent.body, {'user_id': '@another:other.org'});
    }
  });

  test('M_FORBIDDEN on unban throws and leaves the list untouched', () async {
    script.routes
        .add((r) => r.path == unbanPath ? matrixError('M_FORBIDDEN') : null);
    await list.refresh();
    final before = List.of(list.members);

    Object? error;
    try {
      await list.unban('@troll:example.org');
    } catch (e) {
      error = e;
    }

    expect(error, isA<matrix.MatrixException>());
    expect(ModerationFailure.of(error!), ModerationFailure.forbidden);
    expect(list.members, before);
    expect(list.members.map((m) => m.userId), contains('@troll:example.org'));
  });

  test('a refused refresh keeps the last list', () async {
    await list.refresh();
    final before = list.members;
    script.routes.insert(
        0, (r) => r.path == membersPath ? matrixError('M_FORBIDDEN') : null);

    await expectLater(list.refresh(), throwsA(isA<matrix.MatrixException>()));
    expect(list.members, same(before));
  });

  test('errcodes become moderation failures', () {
    matrix.MatrixException error(String code) =>
        matrix.MatrixException.fromJson({'errcode': code, 'error': code});
    expect(ModerationFailure.of(error('M_FORBIDDEN')),
        ModerationFailure.forbidden);
    expect(
        ModerationFailure.of(error('M_NOT_FOUND')), ModerationFailure.notFound);
    expect(ModerationFailure.of(error('M_LIMIT_EXCEEDED')),
        ModerationFailure.rateLimited);
    expect(ModerationFailure.of(error('M_UNKNOWN')), ModerationFailure.other);
    expect(ModerationFailure.of(Exception('offline')), ModerationFailure.other);
  });

  test('unbanning takes the ban power level', () {
    putState(room, 'm.room.power_levels', {
      'users': {self: 50},
      'ban': 50,
    });
    expect(MatrixRoomModeration(room).canBan, isTrue);
    putState(room, 'm.room.power_levels', {
      'users': {self: 49},
      'ban': 50,
    });
    expect(MatrixRoomModeration(room).canBan, isFalse);
  });
}
