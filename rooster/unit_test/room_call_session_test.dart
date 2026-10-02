// The sidebar lights up a voice channel's members while they talk, in our
// own call. It found that call through VoipRoomComponent.currentSession,
// which the join sets only once it returns; the session registers with the
// call manager before that, so on the only list update there was no call yet
// and the members never lit up. It is looked up in the call manager's list.
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/ui/atoms/room_text_button.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.identifier, this.client);

  @override
  final String identifier;

  @override
  final Client client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.roomId, this.client, [this.state = VoipState.connected]);

  @override
  final String roomId;

  @override
  final Client client;

  @override
  VoipState state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final client = _Client();
  final room = _Room('!voice:x', client);

  test("our call in the room is found as soon as the call manager has it", () {
    final session = _Session('!voice:x', client);
    expect(
        // ignore: invalid_use_of_visible_for_testing_member
        RoomTextButton.callSessionIn(
            room, [_Session('!other:x', client), session]),
        same(session));
  });

  test('a call in another room, or on another account, is not this one', () {
    expect(
        // ignore: invalid_use_of_visible_for_testing_member
        RoomTextButton.callSessionIn(room, [
          _Session('!other:x', client),
          _Session('!voice:x', _Client()),
        ]),
        isNull);
  });

  test('a call that ended is not ours any more', () {
    expect(
        // ignore: invalid_use_of_visible_for_testing_member
        RoomTextButton.callSessionIn(
            room, [_Session('!voice:x', client, VoipState.ended)]),
        isNull);
  });
}
