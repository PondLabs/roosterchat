// Regression test for finding c1-3:
// `m.room.server_acl`, `m.room.policy`, and `m.policy.rule.*` are outside
// `importantStateEvents`, so on a partial room (`room.partial == true`)
// `ServerAclEditor` and `PolicyServerView` must await `room.postLoad()` before
// initializing form fields and displaying rules.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_policy_server.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';
import 'package:rooster/ui/organisms/moderation/policy_server_view.dart';
import 'package:rooster/ui/organisms/moderation/server_acl_editor.dart';

import '../matrix_phase0/test_helpers.dart';
import 'fakes.dart';

class _StoredStateDatabase extends MemoryCacheDatabase {
  _StoredStateDatabase(this._builders);

  final List<matrix.Event Function(matrix.Room)> _builders;

  @override
  Future<List<matrix.Event>> getUnimportantRoomEventStatesForRoom(
    List<String> events,
    matrix.Room room,
  ) async =>
      [for (final build in _builders) build(room)];
}

class _PartialClient extends matrix.Client {
  _PartialClient(Script script, matrix.DatabaseApi db)
      : super('partial_room_test', httpClient: script.transport, database: db) {
    homeserver = Uri.parse('http://127.0.0.1:9');
    accessToken = 'test-token';
  }

  @override
  String? get userID => self;
}

matrix.Event _state(matrix.Room room, String type, Map<String, Object?> content,
        {String stateKey = ''}) =>
    matrix.Event(
      type: type,
      stateKey: stateKey,
      eventId: '\$${type}_$stateKey',
      senderId: self,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(200),
      content: content,
      room: room,
    );

void main() {
  setUpAll(prepareTests);

  testWidgets('ServerAclEditor loads persisted ACL from a partial room',
      (tester) async {
    final script = Script();
    final db = _StoredStateDatabase([
      (room) => _state(room, 'm.room.server_acl', {
            'allow': ['*'],
            'deny': ['evil.example'],
            'allow_ip_literals': false,
          }),
    ]);
    final client = _PartialClient(script, db);
    final room = joinedRoom(client, id: roomId, ownLevel: 100);
    expect(room.partial, isTrue);

    await tester.pumpWidget(host(ServerAclEditor(MatrixServerAcl(room))));
    await settle(tester);

    expect(find.text('evil.example'), findsOneWidget);
  });

  testWidgets(
      'PolicyServerView loads persisted policy and rules from a partial room',
      (tester) async {
    final script = Script();
    final db = _StoredStateDatabase([
      (room) => _state(room, 'm.room.policy', {
            'via': 'policy.example.org',
            'public_keys': {'ed25519': 'abc'},
          }),
      (room) => _state(
            room,
            'm.policy.rule.user',
            {
              'entity': '@spammer:*',
              'recommendation': 'm.ban',
              'reason': 'spam'
            },
            stateKey: 'r1',
          ),
    ]);
    final client = _PartialClient(script, db);
    final room = joinedRoom(client, id: roomId, ownLevel: 100);
    expect(room.partial, isTrue);

    await tester.pumpWidget(host(PolicyServerView(MatrixPolicyServer(room))));
    await settle(tester);

    expect(find.text('policy.example.org'), findsOneWidget);
    expect(find.text('@spammer:*'), findsOneWidget);
  });
}
