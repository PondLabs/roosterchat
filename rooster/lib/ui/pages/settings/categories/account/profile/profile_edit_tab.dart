import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/ui/molecules/user_panel.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/profile_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ProfileEditTab extends StatefulWidget {
  const ProfileEditTab(
      {required this.clientManager, this.initialClient, super.key});
  final ClientManager clientManager;

  /// The account to show first; the first account when null.
  final Client? initialClient;

  @override
  State<ProfileEditTab> createState() => _ProfileEditTabState();
}

class _ProfileEditTabState extends State<ProfileEditTab> {
  late Client client =
      widget.clientManager.clients.contains(widget.initialClient)
          ? widget.initialClient!
          : widget.clientManager.clients.first;

  @override
  Widget build(BuildContext context) {
    final clients = widget.clientManager.clients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AccountSelector always starts on the first account.
        if (clients.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: tiamat.DropdownSelector<Client>(
              items: clients,
              value: client,
              itemHeight: 65,
              onItemSelected: (item) => setState(() => client = item!),
              itemBuilder: (item) => Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                child: UserPanelView(
                  displayName: item.self!.displayName,
                  detail: item.self!.detail,
                  avatar: item.self!.avatar,
                ),
              ),
            ),
          ),
        Expanded(
          child:
              ProfileEditor(key: ValueKey(client.identifier), client: client),
        ),
      ],
    );
  }
}
