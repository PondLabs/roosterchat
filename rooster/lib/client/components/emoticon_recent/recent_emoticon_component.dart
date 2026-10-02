import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';

abstract class RecentEmoticonComponent<T extends Client>
    implements Component<T> {
  List<Emoticon> getRecentTypedEmoticon(Room? room);

  List<Emoticon> getRecentReactionEmoticon(Room room);

  Future<void> typedEmoticon(Room room, Emoticon emoticon);

  Future<void> reactedEmoticon(Room room, Emoticon emoticon);

  Future<void> clear();
}
