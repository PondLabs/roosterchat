import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/molecules/account_selector.dart';
import 'package:rooster/ui/pages/settings/categories/account/preferences/preferences_chat_privacy.dart';
import 'package:rooster/ui/pages/settings/categories/account/preferences/preferences_ignored_users.dart';
import 'package:flutter/material.dart';

class AccountSettingsTab extends StatefulWidget {
  const AccountSettingsTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  @override
  State<AccountSettingsTab> createState() => _AccountSettingsTabState();
}

class _AccountSettingsTabState extends State<AccountSettingsTab> {
  late Client selectedClient;

  @override
  void initState() {
    selectedClient = widget.clientManager.clients.first;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            onClientSelected: (client) {
              setState(() {
                selectedClient = client;
              });
            },
          ),
        const SizedBox(
          height: 4,
        ),
        ChatPrivacyPreferences(
            client: selectedClient,
            key: ValueKey(
                "chat-privacy-preferences_${selectedClient.identifier}")),
        if (selectedClient case MatrixClient client) ...[
          const SizedBox(height: 8),
          IgnoredUsersPreferences(
              client: client.matrixClient,
              key: ValueKey("ignored-users_${client.identifier}")),
        ],
      ],
    );
  }
}
