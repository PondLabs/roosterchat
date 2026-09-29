import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/component.dart';

abstract class RoomComponent<R extends Client, T extends Room>
    extends Component<R> {
  late T _room;
  T get room => _room;

  RoomComponent(super.client, T room) {
    _room = room;
  }
}
