import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/push_notifications/matrix_notification_history.dart';
import 'package:rooster/client/matrix/components/push_notifications/matrix_push_rules.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/account_selector.dart';
import 'package:rooster/ui/organisms/notifications/notification_history_panel.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The notification rules and history of one signed-in account, with a
/// picker when there are several. Both live on the homeserver, so they
/// are the same on every device.
class AccountNotificationSettings extends StatefulWidget {
  const AccountNotificationSettings({super.key});

  @override
  State<AccountNotificationSettings> createState() =>
      _AccountNotificationSettingsState();
}

class _AccountNotificationSettingsState
    extends State<AccountNotificationSettings> {
  String get labelSettingsNotificationRules => Intl.message(
      "Notification rules",
      name: "labelSettingsNotificationRules",
      desc: "Settings > Notifications: header of the panel with what the "
          "account gets notified about, kept on the server for every device");

  String get labelSettingsNotificationHistory =>
      Intl.message("Notification history",
          name: "labelSettingsNotificationHistory",
          desc: "Settings > Notifications: header of the list of the "
              "notifications the account got");

  List<Client> get clients =>
      clientManager?.clients.whereType<MatrixClient>().toList() ?? const [];

  MatrixClient? client;
  MatrixPushRulesController? rules;
  MatrixNotificationHistory? history;

  @override
  void initState() {
    super.initState();
    select(clients.firstOrNull as MatrixClient?);
  }

  void select(MatrixClient? value) {
    rules?.dispose();
    history?.dispose();
    client = value;
    if (value == null) return;
    rules = MatrixPushRulesController(value.getMatrixClient())..load();
    history = MatrixNotificationHistory(value.getMatrixClient());
  }

  @override
  void dispose() {
    rules?.dispose();
    history?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    if (client == null) return const SizedBox();
    return Column(children: [
      if (clients.length > 1)
        AccountSelector(clients,
            onClientSelected: (c) => setState(() => select(c as MatrixClient))),
      tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        header: labelSettingsNotificationRules,
        child: PushRulesSettings(
            controller: rules!, key: ValueKey("rules:${client.identifier}")),
      ),
      const SizedBox(height: 10),
      tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        header: labelSettingsNotificationHistory,
        child: NotificationHistoryPanel(
          key: ValueKey("history:${client.identifier}"),
          history: history!,
          onOpen: (n) => openNotificationEvent(context,
              roomId: n.roomId,
              eventId: n.event.eventId,
              clientId: client.identifier),
        ),
      ),
      const SizedBox(height: 10),
    ]);
  }
}

/// Switches for the server's own push rules, and the keywords you added.
class PushRulesSettings extends StatefulWidget {
  const PushRulesSettings({required this.controller, super.key});
  final MatrixPushRulesController controller;

  @override
  State<PushRulesSettings> createState() => _PushRulesSettingsState();
}

class _PushRulesSettingsState extends State<PushRulesSettings> {
  String get labelPushRuleAccount =>
      Intl.message("Notifications for this account",
          name: "labelPushRuleAccount",
          desc: "Settings > Notifications > Notification rules: the switch "
              "that mutes every notification of the account");

  String get labelPushRuleAccountDescription => Intl.message(
      "Turn off to mute every notification, on all of your devices",
      name: "labelPushRuleAccountDescription",
      desc: "Under the 'Notifications for this account' switch");

  String get labelPushRuleDirectMessages => Intl.message("Direct messages",
      name: "labelPushRuleDirectMessages",
      desc: "Settings > Notifications > Notification rules: switch for "
          "messages in one-to-one chats");

  String get labelPushRuleEncryptedDirectMessages =>
      Intl.message("Encrypted direct messages",
          name: "labelPushRuleEncryptedDirectMessages",
          desc: "Settings > Notifications > Notification rules: switch for "
              "end-to-end encrypted messages in one-to-one chats");

  String get labelPushRuleRoomMessages => Intl.message("Messages in rooms",
      name: "labelPushRuleRoomMessages",
      desc: "Settings > Notifications > Notification rules: switch for "
          "messages in rooms with more than two people");

  String get labelPushRuleEncryptedRoomMessages =>
      Intl.message("Encrypted messages in rooms",
          name: "labelPushRuleEncryptedRoomMessages",
          desc: "Settings > Notifications > Notification rules: switch for "
              "end-to-end encrypted messages in rooms with more than two "
              "people");

  String get labelPushRuleInvites => Intl.message("Invitations",
      name: "labelPushRuleInvites",
      desc: "Settings > Notifications > Notification rules: switch for "
          "being invited to a room");

  String get labelPushRuleCalls => Intl.message("Calls",
      name: "labelPushRuleCalls",
      desc: "Settings > Notifications > Notification rules: switch for "
          "incoming calls");

  String get labelPushRuleKeywords => Intl.message("Keywords",
      name: "labelPushRuleKeywords",
      desc: "Settings > Notifications > Notification rules: header of the "
          "words that notify you when a message has them");

  String get labelPushRuleKeywordsDescription =>
      Intl.message("Get a notification when a message has one of these words",
          name: "labelPushRuleKeywordsDescription",
          desc: "Under the 'Keywords' header in Settings > Notifications");

  String get promptPushRuleKeywordAdd => Intl.message("Add a keyword",
      name: "promptPushRuleKeywordAdd",
      desc: "Settings > Notifications > Keywords: placeholder of the box "
          "you type a new keyword in");

  String get messagePushRuleKeywordEmpty =>
      Intl.message("Type a keyword first.",
          name: "messagePushRuleKeywordEmpty",
          desc: "Settings > Notifications > Keywords: Add was pressed with "
              "the box empty");

  String get messagePushRuleKeywordDuplicate =>
      Intl.message("You already have that keyword.",
          name: "messagePushRuleKeywordDuplicate",
          desc: "Settings > Notifications > Keywords: the keyword typed is "
              "already in the list");

  String get messagePushRuleFailed =>
      Intl.message("Couldn't save the change. Try again.",
          name: "messagePushRuleFailed",
          desc: "Settings > Notifications > Notification rules: the server "
              "refused a change, which was undone");

  String messagePushRuleRateLimited(int seconds) => Intl.plural(seconds,
      one: "Too many changes at once. Try again in 1 second.",
      other: "Too many changes at once. Try again in $seconds seconds.",
      name: "messagePushRuleRateLimited",
      args: [seconds],
      desc: "Settings > Notifications > Notification rules: the server "
          "refused a change for coming too fast, and said how long to wait");

  String get messagePushRulesLoadFailed =>
      Intl.message("Couldn't load your notification rules.",
          name: "messagePushRulesLoadFailed",
          desc: "Settings > Notifications > Notification rules: the server "
              "could not be reached or refused, next to a button to try "
              "again");

  final keyword = TextEditingController();
  String? keywordProblem;

  MatrixPushRulesController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(changed);
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    keyword.dispose();
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  String label(GlobalPushRule rule) => switch (rule) {
        GlobalPushRule.master => labelPushRuleAccount,
        GlobalPushRule.directMessages => labelPushRuleDirectMessages,
        GlobalPushRule.encryptedDirectMessages =>
          labelPushRuleEncryptedDirectMessages,
        GlobalPushRule.roomMessages => labelPushRuleRoomMessages,
        GlobalPushRule.encryptedRoomMessages =>
          labelPushRuleEncryptedRoomMessages,
        GlobalPushRule.invites => labelPushRuleInvites,
        GlobalPushRule.calls => labelPushRuleCalls,
      };

  Future<void> addKeyword() async {
    final result = await controller.addKeyword(keyword.text);
    if (!mounted) return;
    setState(() {
      keywordProblem = switch (result) {
        KeywordChange.empty => messagePushRuleKeywordEmpty,
        KeywordChange.duplicate => messagePushRuleKeywordDuplicate,
        _ => null,
      };
      if (result == KeywordChange.added) keyword.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.loaded) {
      if (controller.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Row(children: [
        Expanded(child: tiamat.Text.labelLow(messagePushRulesLoadFailed)),
        tiamat.Button.secondary(
            text: CommonStrings.promptRetry, onTap: controller.load),
      ]);
    }

    // The master rule mutes when enabled: its switch shows the opposite.
    final muted = controller.isEnabled(GlobalPushRule.master) == true;
    final retry = controller.retryAfter;
    final error = controller.lastError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rule in GlobalPushRule.values)
          if (controller.isEnabled(rule) != null)
            buildSwitch(
              rule,
              value: rule == GlobalPushRule.master
                  ? !muted
                  : controller.isEnabled(rule)!,
              enabled: rule == GlobalPushRule.master || !muted,
            ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: tiamat.Text.error(retry != null
                ? messagePushRuleRateLimited(retry.inSeconds.clamp(1, 3600))
                : messagePushRuleFailed),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(labelPushRuleKeywords),
              tiamat.Text.labelLow(labelPushRuleKeywordsDescription),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final rule in controller.keywords)
                  InputChip(
                    label: Text(rule.pattern!),
                    onDeleted: controller.isPending(rule.ruleId)
                        ? null
                        : () => controller.removeKeyword(rule.ruleId),
                    deleteButtonTooltipMessage: CommonStrings.promptRemove,
                  ),
              ]),
              Row(children: [
                Expanded(
                  child: tiamat.TextInput(
                    controller: keyword,
                    placeholder: promptPushRuleKeywordAdd,
                    onSubmitted: (_) => addKeyword(),
                  ),
                ),
                tiamat.Button.secondary(
                    text: CommonStrings.promptAdd, onTap: addKeyword),
              ]),
              if (keywordProblem != null) tiamat.Text.error(keywordProblem!),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildSwitch(GlobalPushRule rule,
      {required bool value, required bool enabled}) {
    final pending = controller.isPending(rule.ruleId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(label(rule)),
              if (rule == GlobalPushRule.master)
                tiamat.Text.labelLow(labelPushRuleAccountDescription),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
          child: tiamat.Switch(
            key: ValueKey("push-rule:${rule.ruleId}"),
            state: value,
            onChanged: !enabled || pending
                ? null
                : (on) => controller.setEnabled(
                    rule, rule == GlobalPushRule.master ? !on : on),
          ),
        ),
      ]),
    );
  }
}
