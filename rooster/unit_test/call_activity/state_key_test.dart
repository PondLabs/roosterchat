// An activity session's room state lives under its id behind an
// underscore: the id is the host's LiveKit identity, which starts with
// "@", and Synapse refuses such a state key from anyone but that user id
// itself ("You are not allowed to set others state").
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/call_activity/matrix_call_activity_component.dart';

void main() {
  const identity = '@alice:localhost:DEVICEID';

  test('a session id never makes a state key starting with @', () {
    final key = MatrixCallActivityComponent.stateKeyOf(identity);
    expect(key.startsWith('@'), isFalse);
    expect(key, '_$identity');
  });

  test('the session id comes back out of its key', () {
    expect(
        MatrixCallActivityComponent.sessionIdOf(
            MatrixCallActivityComponent.stateKeyOf(identity)),
        identity);
    expect(MatrixCallActivityComponent.sessionIdOf('plain'), 'plain',
        reason: 'a key without the underscore is taken as it is');
  });
}
