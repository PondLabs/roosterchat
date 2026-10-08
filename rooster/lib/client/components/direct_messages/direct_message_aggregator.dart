import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/notifying_list.dart';
import 'package:rooster/utils/notifying_list_mapped.dart';

class DirectMessagesAggregator implements DirectMessagesInterface {
  ClientManager clientManager;

  @override
  late INotifyingList<Room> directMessageRooms;

  @override
  late INotifyingList<Room> highlightedRoomsList;

  final StreamController updatedController = StreamController.broadcast();

  final StreamController highlightedUpdateController =
      StreamController.broadcast();

  DirectMessagesAggregator(this.clientManager) {
    directMessageRooms = NotifyingListMapped<Room, Client>(
      baseList: clientManager.clients,
      map: (value) {
        final comp = value.getComponent<DirectMessagesComponent>();
        return comp!.directMessageRooms;
      },
    );

    highlightedRoomsList = NotifyingListMapped<Room, Client>(
      baseList: clientManager.clients,
      map: (value) {
        final comp = value.getComponent<DirectMessagesComponent>();
        return comp!.highlightedRoomsList;
      },
    );

    highlightedRoomsList.onListUpdated.listen((_) {
      Log.d("Highlighted rooms list updated!");
    });
  }
}
