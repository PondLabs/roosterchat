import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/room_component.dart';
import 'package:cockhouse/client/timeline_events/timeline_event.dart';

abstract class ReadReceiptComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Stream<String> get onReadReceiptsUpdated;
  bool? get usePublicReadReceiptsForRoom;
  Future<void> setUsePublicReadReceiptsForRoom(bool? value);

  List<String>? getReceipts(TimelineEvent event);
}
