import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/organisms/moderation/moderation_reason_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Edits the room's `m.room.server_acl`, refusing to save an ACL that would
/// lock our own server out of the room for good.
class ServerAclEditor extends StatefulWidget {
  const ServerAclEditor(this.acl, {this.canEdit = true, super.key});

  final MatrixServerAcl acl;
  final bool canEdit;

  static const allowFieldKey = ValueKey('server_acl_allow');
  static const denyFieldKey = ValueKey('server_acl_deny');
  static const ipLiteralsKey = ValueKey('server_acl_ip_literals');
  static const saveKey = ValueKey('server_acl_save');

  static String get labelServerAcl => Intl.message("Server Access",
      name: "labelServerAcl",
      desc: "Title of the room setting that says which Matrix servers may "
          "take part in the room (the server ACL)");

  static String get labelServerAclDescription => Intl.message(
      "Choose which servers may take part in this room. One server per line; * matches any characters and ? one character.",
      name: "labelServerAclDescription",
      desc: "Explanation at the top of the server access editor");

  static String get labelServerAclAllow => Intl.message("Allowed servers",
      name: "labelServerAclAllow",
      desc: "Label of the list of servers that may take part in the room");

  static String get labelServerAclDeny => Intl.message("Blocked servers",
      name: "labelServerAclDeny",
      desc: "Label of the list of servers that may not take part in the "
          "room, even when allowed");

  static String get labelServerAclIpLiterals => Intl.message(
      "Allow servers named by an IP address",
      name: "labelServerAclIpLiterals",
      desc: "Switch in the server access editor for servers whose name is an "
          "IP address instead of a domain");

  static String get errorServerAclAllowEmpty => Intl.message(
      "Allow at least one server. With no allowed servers, no one could ever use this room again.",
      name: "errorServerAclAllowEmpty",
      desc: "Why the server access editor will not save an empty list of "
          "allowed servers");

  static String errorServerAclOwnServerNotAllowed(String server) => Intl.message(
      "Your server, $server, is not on the allowed list. Saving this would lock you out of the room for good.",
      name: "errorServerAclOwnServerNotAllowed",
      args: [server],
      desc: "Why the server access editor will not save, with the user's "
          "own server name");

  static String errorServerAclOwnServerDenied(String server) => Intl.message(
      "Your server, $server, is on the blocked list. Saving this would lock you out of the room for good.",
      name: "errorServerAclOwnServerDenied",
      args: [server],
      desc: "Why the server access editor will not save, with the user's own "
          "server name");

  static String errorServerAclIpLiteral(String server) => Intl.message(
      "Your server, $server, is named by an IP address. Blocking those would lock you out of the room for good.",
      name: "errorServerAclIpLiteral",
      args: [server],
      desc: "Why the server access editor will not save, with the user's own "
          "server name");

  static String get messageServerAclSaved =>
      Intl.message("Server access saved.",
          name: "messageServerAclSaved",
          desc: "Shown after the room's server access was saved");

  static String problemText(ServerAclProblem problem, String server) =>
      switch (problem) {
        ServerAclProblem.allowEmpty => errorServerAclAllowEmpty,
        ServerAclProblem.ownServerNotAllowed =>
          errorServerAclOwnServerNotAllowed(server),
        ServerAclProblem.ownServerDenied =>
          errorServerAclOwnServerDenied(server),
        ServerAclProblem.ownServerIpLiteralBlocked =>
          errorServerAclIpLiteral(server),
      };

  @override
  State<ServerAclEditor> createState() => _ServerAclEditorState();
}

class _ServerAclEditorState extends State<ServerAclEditor> {
  final allow = TextEditingController();
  final deny = TextEditingController();
  ServerAcl initial = ServerAcl(allow: ['*']);
  bool allowIpLiterals = true;
  bool loading = false;
  bool loadFailed = false;
  bool saving = false;
  bool saved = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.acl.room.partial) {
      loading = true;
      _load();
    } else {
      _applyCurrent();
    }
  }

  void _applyCurrent() {
    initial = widget.acl.current;
    allow.text = initial.allow.join('\n');
    deny.text = initial.deny.join('\n');
    allowIpLiterals = initial.allowIpLiterals;
  }

  Future<void> _load() async {
    try {
      await widget.acl.room.postLoad();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load the server ACL");
      error = ModerationStrings.errorText(e);
      loadFailed = true;
    }
    if (!mounted) return;
    if (!loadFailed) _applyCurrent();
    setState(() => loading = false);
  }

  ServerAcl get edited => ServerAcl(
        allow: allow.text.split('\n'),
        deny: deny.text.split('\n'),
        allowIpLiterals: allowIpLiterals,
        extra: initial.extra,
      );

  @override
  void dispose() {
    allow.dispose();
    deny.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      saved = false;
      error = null;
    });
    try {
      await widget.acl.save(edited);
      saved = true;
    } on ServerAclRejected {
      // The problems are already on screen; nothing was sent.
    } catch (e, s) {
      Log.onError(e, s, content: "Could not save the server ACL");
      error = ModerationStrings.errorText(e);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).colorScheme;
    if (loadFailed) {
      return Text(error!, style: TextStyle(color: colors.error));
    }
    final server = widget.acl.ownServer;
    final problems = widget.acl.problemsOf(edited);
    TextField field(Key key, TextEditingController controller, String label) =>
        TextField(
          key: key,
          controller: controller,
          enabled: widget.canEdit && !saving,
          minLines: 2,
          maxLines: 6,
          onChanged: (_) => setState(() => saved = false),
          decoration: InputDecoration(labelText: label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(ServerAclEditor.labelServerAclDescription),
        field(ServerAclEditor.allowFieldKey, allow,
            ServerAclEditor.labelServerAclAllow),
        field(ServerAclEditor.denyFieldKey, deny,
            ServerAclEditor.labelServerAclDeny),
        SwitchListTile(
          key: ServerAclEditor.ipLiteralsKey,
          contentPadding: EdgeInsets.zero,
          title: Text(ServerAclEditor.labelServerAclIpLiterals),
          value: allowIpLiterals,
          onChanged: widget.canEdit && !saving
              ? (value) => setState(() {
                    allowIpLiterals = value;
                    saved = false;
                  })
              : null,
        ),
        for (final problem in problems)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.error, size: 20),
              Expanded(
                child: Text(ServerAclEditor.problemText(problem, server),
                    style: TextStyle(color: colors.error)),
              ),
            ],
          ),
        if (error != null) Text(error!, style: TextStyle(color: colors.error)),
        if (saved) tiamat.Text.labelLow(ServerAclEditor.messageServerAclSaved),
        if (widget.canEdit)
          SizedBox(
            height: 40,
            child: tiamat.Button(
              key: ServerAclEditor.saveKey,
              text: CommonStrings.promptSave,
              isLoading: saving,
              onTap: problems.isEmpty && !saving ? save : null,
            ),
          ),
      ],
    );
  }
}
