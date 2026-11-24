// Regression test for finding c1-1:
// `allow` entries with mismatched case (e.g. `EXAMPLE.ORG` when ownServer is
// `example.org`) must be refused rather than saved, because case-sensitive
// Matrix servers (Tuwunel/Ruma, Dendrite) evaluate `allow` case-sensitively
// and would permanently lock our own server out of the room, while `deny` must
// stay case-insensitive to protect against case-insensitive servers (Synapse).
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';

import 'fakes.dart';

const aclPath = '/_matrix/client/v3/rooms/$roomId/state/m.room.server_acl/';

void main() {
  test(
      'refuses uppercase allow that misses ownServer on case-sensitive servers',
      () async {
    final (script, room) = moderatedRoom();
    script.routes.add((r) => r.method == 'PUT' && r.path == aclPath
        ? json({'event_id': r'$acl'})
        : null);
    final acl = MatrixServerAcl(room);

    for (final allow in [
      ['EXAMPLE.ORG'],
      ['Example.org'],
    ]) {
      await expectLater(
        acl.save(ServerAcl(allow: allow)),
        throwsA(isA<ServerAclRejected>().having(
          (e) => e.problems,
          'problems',
          [ServerAclProblem.ownServerNotAllowed],
        )),
        reason: 'allow=$allow must not pass for ownServer=example.org',
      );
    }
    expect(writes(script), isEmpty);

    // Deny stays case-insensitive to protect Synapse rooms as well.
    expect(
      ServerAcl(allow: ['*'], deny: ['EXAMPLE.ORG']).problemsFor('example.org'),
      [ServerAclProblem.ownServerDenied],
    );
  });
}
