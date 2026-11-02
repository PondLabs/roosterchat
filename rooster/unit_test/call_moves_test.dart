// Who may move someone to another voice channel, or out of the call: the
// receiving Rooster checks it before it switches (docs/voice-channel-members.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/matrix_call_moves_component.dart';

const admin = '@admin:example.org';
const mod = '@mod:example.org';
const member = '@member:example.org';
const other = '@other:example.org';

class _SdkClient implements matrix.Client {
  @override
  String? get userID => member;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

matrix.Room _room({int? kick}) {
  final room = matrix.Room(id: '!voice:example.org', client: _SdkClient());
  room.states[matrix.EventTypes.RoomPowerLevels] = {
    '': matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomPowerLevels,
      stateKey: '',
      senderId: admin,
      content: {
        'users': {admin: 100, mod: 50},
        'users_default': 0,
        if (kick != null) 'kick': kick,
      },
    ),
  };
  return room;
}

void main() {
  test('anyone may move themselves', () {
    expect(MatrixCallMovesComponent.mayMove(_room(), member, member), isTrue);
  });

  test('someone with the power to kick moves those below them', () {
    final room = _room();
    expect(MatrixCallMovesComponent.mayMove(room, mod, member), isTrue);
    expect(MatrixCallMovesComponent.mayMove(room, admin, mod), isTrue);
  });

  test('nobody moves their equal or someone above them', () {
    final room = _room();
    expect(MatrixCallMovesComponent.mayMove(room, member, other), isFalse);
    expect(MatrixCallMovesComponent.mayMove(room, mod, admin), isFalse);
  });

  test("the room's kick level decides", () {
    final room = _room(kick: 75);
    expect(MatrixCallMovesComponent.mayMove(room, mod, member), isFalse);
    expect(MatrixCallMovesComponent.mayMove(room, admin, member), isTrue);
  });
}
