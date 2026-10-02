import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';

abstract class PinnedMessagesComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  List<String> getPinnedMessages();

  Future<void> pinMessage(String eventId);

  Future<void> unpinMessage(String eventId);

  bool isMessagePinned(String eventId);

  bool get canPinMessages;
}
