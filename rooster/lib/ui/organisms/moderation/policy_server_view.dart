import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_policy_server.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/organisms/moderation/moderation_reason_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The room's policy server (`m.room.policy`) and the policy rules
/// (`m.policy.rule.*`) the room holds.
class PolicyServerView extends StatefulWidget {
  const PolicyServerView(this.policy, {this.canEdit = true, super.key});

  final MatrixPolicyServer policy;
  final bool canEdit;

  static const viaFieldKey = ValueKey('policy_server_via');
  static const keyFieldKey = ValueKey('policy_server_key');
  static const saveKey = ValueKey('policy_server_save');

  static String get labelPolicyServer => Intl.message("Policy Server",
      name: "labelPolicyServer",
      desc: "Title of the room setting for the server that checks new "
          "messages against the room's rules before they are shared "
          "(Matrix policy server)");

  static String get labelPolicyServerDescription => Intl.message(
      "A policy server checks new events against this room's rules before other servers accept them. Leave the server empty to turn it off.",
      name: "labelPolicyServerDescription",
      desc: "Explanation at the top of the policy server setting");

  static String get labelPolicyServerVia => Intl.message("Server name",
      name: "labelPolicyServerVia",
      desc: "Field for the policy server's name, like policy.example.org");

  static String get labelPolicyServerKey => Intl.message("Public key (ed25519)",
      name: "labelPolicyServerKey",
      desc: "Field for the policy server's signing key, which its operator "
          "publishes");

  static String get errorPolicyServerName => Intl.message(
      "Enter a server name such as policy.example.org, without https://.",
      name: "errorPolicyServerName",
      desc: "Why the policy server setting will not save a malformed name");

  static String get errorPolicyServerKey => Intl.message(
      "Enter the policy server's public key. Without it, servers ignore the policy server.",
      name: "errorPolicyServerKey",
      desc: "Why the policy server setting will not save without a key");

  static String get messagePolicyServerSaved =>
      Intl.message("Policy server saved.",
          name: "messagePolicyServerSaved",
          desc: "Shown after the room's policy server was saved");

  static String get labelPolicyRules => Intl.message("Policy Rules",
      name: "labelPolicyRules",
      desc: "Heading of the moderation rules (bans of users, rooms or "
          "servers) published in this room");

  static String get labelNoPolicyRules =>
      Intl.message("This room publishes no policy rules.",
          name: "labelNoPolicyRules",
          desc: "Shown instead of the policy rules when there are none");

  static String get labelPolicyRuleUser => Intl.message("User",
      name: "labelPolicyRuleUser",
      desc: "Kind of a policy rule that applies to users");

  static String get labelPolicyRuleRoom => Intl.message("Room",
      name: "labelPolicyRuleRoom",
      desc: "Kind of a policy rule that applies to rooms");

  static String get labelPolicyRuleServer => Intl.message("Server",
      name: "labelPolicyRuleServer",
      desc: "Kind of a policy rule that applies to servers");

  static String get labelPolicyRuleBan => Intl.message("Ban",
      name: "labelPolicyRuleBan",
      desc: "What a policy rule recommends: banning the users, rooms or "
          "servers it names");

  static String kindText(PolicyRuleKind kind) => switch (kind) {
        PolicyRuleKind.user => labelPolicyRuleUser,
        PolicyRuleKind.room => labelPolicyRuleRoom,
        PolicyRuleKind.server => labelPolicyRuleServer,
      };

  static String problemText(PolicyServerProblem problem) => switch (problem) {
        PolicyServerProblem.invalidServerName => errorPolicyServerName,
        PolicyServerProblem.missingKey => errorPolicyServerKey,
      };

  @override
  State<PolicyServerView> createState() => _PolicyServerViewState();
}

class _PolicyServerViewState extends State<PolicyServerView> {
  late final via = TextEditingController(text: widget.policy.current.via);
  late final key =
      TextEditingController(text: widget.policy.current.ed25519PublicKey);
  bool saving = false;
  bool saved = false;
  String? error;

  @override
  void dispose() {
    via.dispose();
    key.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      saved = false;
      error = null;
    });
    try {
      await widget.policy.save(via: via.text, publicKey: key.text);
      saved = true;
    } on PolicyServerRejected {
      // The problems are already on screen; nothing was sent.
    } catch (e, s) {
      Log.onError(e, s, content: "Could not save the policy server");
      error = ModerationStrings.errorText(e);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final problems = widget.policy.problemsOf(via.text, key.text);
    final rules = PolicyRule.of(widget.policy.room);
    TextField field(Key k, TextEditingController controller, String label) =>
        TextField(
          key: k,
          controller: controller,
          enabled: widget.canEdit && !saving,
          onChanged: (_) => setState(() => saved = false),
          decoration: InputDecoration(labelText: label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(PolicyServerView.labelPolicyServerDescription),
        field(PolicyServerView.viaFieldKey, via,
            PolicyServerView.labelPolicyServerVia),
        field(PolicyServerView.keyFieldKey, key,
            PolicyServerView.labelPolicyServerKey),
        for (final problem in problems)
          Text(PolicyServerView.problemText(problem),
              style: TextStyle(color: colors.error)),
        if (error != null) Text(error!, style: TextStyle(color: colors.error)),
        if (saved)
          tiamat.Text.labelLow(PolicyServerView.messagePolicyServerSaved),
        if (widget.canEdit)
          SizedBox(
            height: 40,
            child: tiamat.Button(
              key: PolicyServerView.saveKey,
              text: CommonStrings.promptSave,
              isLoading: saving,
              onTap: problems.isEmpty && !saving ? save : null,
            ),
          ),
        const SizedBox(height: 8),
        tiamat.Text.labelEmphasised(PolicyServerView.labelPolicyRules),
        if (rules.isEmpty)
          tiamat.Text.labelLow(PolicyServerView.labelNoPolicyRules),
        for (final rule in rules)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(rule.entity, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              PolicyServerView.kindText(rule.kind),
              // Not translated: a recommendation the spec does not define is
              // shown as its namespaced identifier.
              rule.isBan
                  ? PolicyServerView.labelPolicyRuleBan
                  : rule.recommendation,
              if (rule.reason != null) rule.reason!,
            ].join(' · ')),
          ),
      ],
    );
  }
}
