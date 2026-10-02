import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';

abstract class PetNameComponent<T extends Client> implements Component<T> {
  String? getPetName(String identifier);

  Future<void> setPetName(String identifier, String? name);
}
