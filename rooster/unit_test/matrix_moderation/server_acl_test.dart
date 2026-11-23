// Criterion 3: `m.room.server_acl` is sent with `allow`, `deny` and
// `allow_ip_literals`, and an ACL that would lock our own server out (an
// empty `allow` above all) is refused with no request at all.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';

import 'fakes.dart';

const aclPath = '/_matrix/client/v3/rooms/$roomId/state/m.room.server_acl/';

void main() {
  late Script script;
  late matrix.Room room;
  late MatrixServerAcl acl;

  setUp(() {
    (script, room) = moderatedRoom();
    script.routes.add((r) => r.method == 'PUT' && r.path == aclPath
        ? json({'event_id': r'$acl'})
        : null);
    acl = MatrixServerAcl(room);
  });

  Future<ServerAclRejected> refused(ServerAcl value) async {
    try {
      await acl.save(value);
    } on ServerAclRejected catch (e) {
      return e;
    }
    fail('the ACL was saved');
  }

  test('sends allow, deny and allow_ip_literals', () async {
    await acl.save(ServerAcl(
      allow: ['*'],
      deny: ['evil.example', '*.spam.example'],
      allowIpLiterals: false,
    ));

    final sent = script.where('PUT', aclPath).single;
    expect(sent.body, {
      'allow': ['*'],
      'deny': ['evil.example', '*.spam.example'],
      'allow_ip_literals': false,
    });
  });

  test('keeps fields it does not edit', () async {
    putState(room, 'm.room.server_acl', {
      'allow': ['*'],
      'deny': [],
      'com.example.note': 'kept',
    });

    final current = acl.current;
    await acl.save(ServerAcl(
        allow: current.allow, deny: ['bad.example'], extra: current.extra));

    expect(script.where('PUT', aclPath).single.body, {
      'com.example.note': 'kept',
      'allow': ['*'],
      'deny': ['bad.example'],
      'allow_ip_literals': true,
    });
  });

  test('refuses an empty allow and sends nothing', () async {
    for (final allow in [
      <String>[],
      ['', '  ']
    ]) {
      final error = await refused(ServerAcl(allow: allow));
      expect(error.problems, contains(ServerAclProblem.allowEmpty));
    }
    expect(writes(script), isEmpty);
  });

  test('refuses an allow that leaves our server out', () async {
    final error = await refused(ServerAcl(allow: ['other.org', '*.other.org']));
    expect(error.problems, [ServerAclProblem.ownServerNotAllowed]);
    expect(writes(script), isEmpty);
  });

  test('refuses a deny that matches our server', () async {
    for (final deny in ['example.org', '*.org', 'EXAMPLE.ORG', 'exam?le.org']) {
      final error = await refused(ServerAcl(allow: ['*'], deny: [deny]));
      expect(error.problems, [ServerAclProblem.ownServerDenied], reason: deny);
    }
    expect(writes(script), isEmpty);
  });

  test('refuses blocking IP literals when our server is one', () async {
    final ipAcl = ServerAcl(allow: ['*'], allowIpLiterals: false);
    expect(ipAcl.problemsFor('10.0.0.1:8448'),
        [ServerAclProblem.ownServerIpLiteralBlocked]);
    expect(ipAcl.problemsFor('[::1]:8448'),
        [ServerAclProblem.ownServerIpLiteralBlocked]);
    expect(ipAcl.problemsFor('example.org'), isEmpty);
  });

  test('matches globs on the host, without the port', () {
    final value = ServerAcl(allow: ['*.example.org', 'ex?mple.org']);
    expect(value.admits('matrix.example.org:8448'), isTrue);
    expect(value.admits('example.org'), isTrue);
    expect(value.admits('exaample.org'), isFalse);
    expect(value.admits('example.org.evil'), isFalse);
    expect(value.problemsFor('example.org:8448'), isEmpty);
  });

  test('reads a malformed ACL as servers do', () {
    final value = ServerAcl.fromJson({
      'allow': ['*', 3, null],
      'deny': 'not a list',
      'allow_ip_literals': 'no',
    });
    expect(value.allow, ['*']);
    expect(value.deny, isEmpty);
    expect(value.allowIpLiterals, isTrue);
  });

  test('a room without an ACL starts from allowing every server', () {
    expect(acl.current.allow, ['*']);
    expect(acl.current.deny, isEmpty);
    expect(acl.current.allowIpLiterals, isTrue);
  });
}
