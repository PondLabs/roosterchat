import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/utils/notifying_list.dart';

abstract class DirectMessagesInterface {
  INotifyingList<Room> get directMessageRooms;

  INotifyingList<Room> get highlightedRoomsList;
}

abstract class DirectMessagesComponent<T extends Client>
    implements Component<T>, DirectMessagesInterface {
  bool isRoomDirectMessage(Room room);

  String? getDirectMessagePartnerId(Room room);

  /// Open a new direct message with another user
  Future<Room?> createDirectMessage(String userId);
}
