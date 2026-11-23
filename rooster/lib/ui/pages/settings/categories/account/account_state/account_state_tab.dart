import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_archived_rooms.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/archived_rooms_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../../../../molecules/account_selector.dart';

class AccountStateTab extends StatefulWidget {
  const AccountStateTab(
      {required this.clientManager, this.selectedClientIndex = 0, super.key});
  final ClientManager clientManager;
  final int selectedClientIndex;
  @override
  State<AccountStateTab> createState() => _AccountStateTabState();
}

class _AccountStateTabState extends State<AccountStateTab> {
  Client? selectedClient;

  @override
  void initState() {
    selectedClient = widget.clientManager.clients[widget.selectedClientIndex];
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
        if (selectedClient case MatrixClient client)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ArchivedRoomsView(
              MatrixArchivedRooms(client.getMatrixClient()),
              key: ValueKey(client.identifier),
            ),
          ),
        selectedClient!.buildDebugInfo()
      ],
    );
  }
}
