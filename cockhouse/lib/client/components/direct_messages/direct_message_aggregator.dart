import 'dart:async';

import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/client_manager.dart';
import 'package:cockhouse/client/components/direct_messages/direct_message_component.dart';
import 'package:cockhouse/debug/log.dart';
import 'package:cockhouse/utils/notifying_list.dart';
import 'package:cockhouse/utils/notifying_list_mapped.dart';

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
      Log.i("Highlihgted rooms list updated!");
    });
  }
}
