import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';

abstract class AccountSwitchPrefix<T extends Client> implements Component<T> {
  (Client, String)? getPrefixedAccount(String string, Room currentRoom);

  String? get clientPrefix;

  String removePrefix(String string, Room currentRoom);

  Future<void> setClientPrefix(String? prefix);

  bool isPossiblyUsingPrefix(String currentText);
}
