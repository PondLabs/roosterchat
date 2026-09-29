import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/room_component.dart';
import 'package:cockhouse/client/member.dart';

abstract class TypingIndicatorComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Stream<void> get onTypingUsersUpdated;

  bool? get typingIndicatorEnabledForRoom;
  Future<void> setTypingIndicatorEnabledForRoom(bool? value);

  List<Member> get typingUsers;

  Future<void> setTypingStatus(bool status);
}
