// Nicknames are for other people. One given to ourselves before that rule
// (the old card menu allowed it) must not replace our name anywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/petname/petname_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_member.dart';

const me = '@me:example.org';
const friend = '@friend:example.org';

class FakeSdkClient implements matrix.Client {
  @override
  String? get userID => me;

  @override
  bool get formatLocalpart => true;

  @override
  bool get mxidLocalPartFallback => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EveryoneIsBoss implements PetNameComponent<MatrixClient> {
  @override
  String? getPetName(String identifier) => 'Boss';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixClient implements MatrixClient {
  final sdk = FakeSdkClient();

  @override
  matrix.Client get matrixClient => sdk;

  @override
  T? getComponent<T extends Component>() {
    final petNames = EveryoneIsBoss();
    return petNames is T ? petNames as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a nickname on ourselves is ignored, one on someone else wins', () {
    final client = FakeMatrixClient();
    final room = matrix.Room(id: '!room:example.org', client: client.sdk);
    MatrixMember member(String id, String name) =>
        MatrixMember(client, matrix.User(id, displayName: name, room: room));

    expect(member(me, 'Me').displayName, 'Me');
    expect(member(friend, 'Friend').displayName, 'Boss');
  });
}
