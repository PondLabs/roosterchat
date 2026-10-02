import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/member.dart';

abstract class TypingIndicatorComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Stream<void> get onTypingUsersUpdated;

  bool? get typingIndicatorEnabledForRoom;
  Future<void> setTypingIndicatorEnabledForRoom(bool? value);

  List<Member> get typingUsers;

  Future<void> setTypingStatus(bool status);
}
