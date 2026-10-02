import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';

abstract class SpaceComponent<R extends Client, T extends Space>
    extends Component<R> {
  late T _space;
  T get space => _space;

  SpaceComponent(super.client, T space) {
    _space = space;
  }
}
