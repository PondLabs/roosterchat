import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/preferences/bool_preference.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings > Developer: which sync each account uses (Simplified Sliding
/// Sync, MSC4186, or `/v3/sync`), and the switch that keeps every account
/// on `/v3/sync`. See third_party/README.md, "Simplified Sliding Sync".
class SyncTransportPanel extends StatefulWidget {
  const SyncTransportPanel({this.clients, this.preference, super.key});

  /// The signed-in Matrix accounts when null.
  final List<matrix.Client> Function()? clients;

  /// [MatrixClient.forceV3Sync] when null.
  final BoolPreference? preference;

  static String get labelDeveloperSync => Intl.message("Sync",
      name: "labelDeveloperSync",
      desc: "Title of the Developer settings section that shows how each "
          "account gets new messages from its server (the Matrix sync)");

  static String get labelDeveloperSyncSlidingSync =>
      Intl.message("Simplified Sliding Sync",
          name: "labelDeveloperSyncSlidingSync",
          desc: "In Developer settings > Sync: the account syncs with "
              "Simplified Sliding Sync (MSC4186, Matrix 2.0), the newer "
              "and faster way to get new messages");

  static String get labelDeveloperSyncClassic =>
      Intl.message("Classic sync (/v3/sync)",
          name: "labelDeveloperSyncClassic",
          desc: "In Developer settings > Sync: the account syncs the older "
              "way, with the /v3/sync endpoint (keep '/v3/sync' as it is)");

  static String labelDeveloperSyncFellBack(String reason) => Intl.message(
      "Classic sync (/v3/sync): the server refused Sliding Sync ($reason)",
      name: "labelDeveloperSyncFellBack",
      args: [reason],
      desc: "In Developer settings > Sync: the account tried Simplified "
          "Sliding Sync, the server refused it, and it went back to the "
          "older /v3/sync. The reason is the server's error code or HTTP "
          "status, like M_UNRECOGNIZED or HTTP 404 (keep '/v3/sync' as it is)");

  static String get labelDeveloperSyncNoAccounts =>
      Intl.message("No account is signed in",
          name: "labelDeveloperSyncNoAccounts",
          desc: "In Developer settings > Sync, when there is no account to "
              "show the sync of");

  static String get labelDeveloperForceClassicSync =>
      Intl.message("Force classic sync",
          name: "labelDeveloperForceClassicSync",
          desc: "Title of a developer setting that keeps every account on "
              "the older /v3/sync, even where the server offers Simplified "
              "Sliding Sync");

  static String get labelDeveloperForceClassicSyncDescription => Intl.message(
      "Uses /v3/sync even where the server offers Simplified Sliding Sync. "
      "Applies from the next sync, without losing encryption keys or messages",
      name: "labelDeveloperForceClassicSyncDescription",
      desc: "Description under the developer setting 'Force classic sync' "
          "(keep '/v3/sync' as it is)");

  /// What [client] syncs with, in words.
  static String describe(matrix.Client client) {
    if (client.syncTransport == matrix.SyncTransport.slidingSync) {
      return labelDeveloperSyncSlidingSync;
    }
    final reason = client.slidingSyncFallbackReason;
    return reason == null
        ? labelDeveloperSyncClassic
        : labelDeveloperSyncFellBack(reason);
  }

  @override
  State<SyncTransportPanel> createState() => _SyncTransportPanelState();
}

class _SyncTransportPanelState extends State<SyncTransportPanel> {
  final List<StreamSubscription<matrix.SyncTransport>> _subscriptions = [];

  BoolPreference get preference =>
      widget.preference ?? MatrixClient.forceV3Sync;

  List<matrix.Client> get clients =>
      widget.clients?.call() ??
      [
        for (final client in clientManager?.clients ?? const [])
          if (client is MatrixClient && client.isLoggedIn())
            client.getMatrixClient(),
      ];

  @override
  void initState() {
    super.initState();
    for (final client in clients) {
      _subscriptions.add(client.onSyncTransportChanged.stream
          .listen((_) => mounted ? setState(() {}) : null));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = clients;
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(SyncTransportPanel.labelDeveloperSync),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (accounts.isEmpty)
                tiamat.Text.labelLow(
                    SyncTransportPanel.labelDeveloperSyncNoAccounts),
              for (final client in accounts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Not translated: a Matrix ID.
                      tiamat.Text.label(client.userID ?? client.clientName),
                      tiamat.Text.labelLow(SyncTransportPanel.describe(client)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        BooleanPreferenceToggle(
          preference: preference,
          title: SyncTransportPanel.labelDeveloperForceClassicSync,
          description:
              SyncTransportPanel.labelDeveloperForceClassicSyncDescription,
          onChanged: (_) {
            for (final client in clients) {
              client.forceLegacySync = preference.value;
            }
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}
