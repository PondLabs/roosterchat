import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_server_admin.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/user_profile/user_device_list_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Server tools for server administrators: look up an account's sessions
/// (`whois`) and lock or suspend it. The server decides who may: the others
/// get a notice, never a crash.
class ServerAdminPanel extends StatefulWidget {
  const ServerAdminPanel(this.admin, {super.key});

  final MatrixServerAdmin admin;

  static const userFieldKey = ValueKey('server-admin-user');
  static const lookUpKey = ValueKey('server-admin-look-up');
  static const resultUserKey = ValueKey('server-admin-result-user');
  static const lockedKey = ValueKey('server-admin-locked');
  static const suspendedKey = ValueKey('server-admin-suspended');
  static const noticeKey = ValueKey('server-admin-notice');

  static String get labelServerAdminHeader =>
      Intl.message("Server administration",
          name: "labelServerAdminHeader",
          desc: "Header of the server tools in account settings, for "
              "administrators of the homeserver");

  static String get labelServerAdminDescription => Intl.message(
      "For administrators of your server: see an account's sessions, and "
      "lock or suspend it.",
      name: "labelServerAdminDescription",
      desc: "Under the header of the server administration tools");

  static String get labelServerAdminUser => Intl.message("User ID",
      name: "labelServerAdminUser",
      desc: "Label of the field where a server administrator types the "
          "Matrix ID of the account to look up");

  static String get promptServerAdminLookUp => Intl.message("Look up",
      name: "promptServerAdminLookUp",
      desc: "Button that loads what the server says about the account typed "
          "in the server administration tools");

  static String get labelServerAdminLocked => Intl.message("Locked",
      name: "labelServerAdminLocked",
      desc: "Switch in the server administration tools: the account is "
          "locked and none of its sessions work until it is unlocked");

  static String get labelServerAdminSuspended => Intl.message("Suspended",
      name: "labelServerAdminSuspended",
      desc: "Switch in the server administration tools: the account is "
          "suspended, it can read but not send, join or change its profile");

  static String get labelServerAdminConfirmLockTitle =>
      Intl.message("Lock account",
          name: "labelServerAdminConfirmLockTitle",
          desc: "Title of the confirmation dialog before a server "
              "administrator locks an account");

  static String messageServerAdminConfirmLock(String user) => Intl.message(
      "Lock $user? All of their sessions will stop working until an "
      "administrator unlocks the account.",
      name: "messageServerAdminConfirmLock",
      args: [user],
      desc: "Question in the confirmation dialog before locking a user's "
          "account; user is the Matrix ID");

  static String get promptServerAdminLock => Intl.message("Lock",
      name: "promptServerAdminLock",
      desc: "Button that confirms locking an account in the server "
          "administration tools");

  static String get labelServerAdminConfirmSuspendTitle =>
      Intl.message("Suspend account",
          name: "labelServerAdminConfirmSuspendTitle",
          desc: "Title of the confirmation dialog before a server "
              "administrator suspends an account");

  static String messageServerAdminConfirmSuspend(String user) => Intl.message(
      "Suspend $user? They will still be able to read, but won't be able to "
      "send messages, join rooms or change their profile.",
      name: "messageServerAdminConfirmSuspend",
      args: [user],
      desc: "Question in the confirmation dialog before suspending a user's "
          "account; user is the Matrix ID");

  static String get promptServerAdminSuspend => Intl.message("Suspend",
      name: "promptServerAdminSuspend",
      desc: "Button that confirms suspending an account in the server "
          "administration tools");

  static String get messageServerAdminForbidden =>
      Intl.message("Only administrators of your server can do this.",
          name: "messageServerAdminForbidden",
          desc: "Shown in the server administration tools when the server "
              "refuses because the user is not one of its administrators");

  static String get messageServerAdminUnsupported =>
      Intl.message("Your server doesn't offer these tools.",
          name: "messageServerAdminUnsupported",
          desc: "Shown in the server administration tools when the "
              "homeserver does not know the lock and suspend requests");

  static String get messageServerAdminNotFound =>
      Intl.message("There is no such account on your server.",
          name: "messageServerAdminNotFound",
          desc: "Shown in the server administration tools when the account "
              "looked up does not exist on the homeserver");

  static String get messageServerAdminFailed =>
      Intl.message("The server didn't answer. Try again.",
          name: "messageServerAdminFailed",
          desc: "Shown in the server administration tools when a request "
              "failed for another reason");

  static String get messageServerAdminInvalidUser =>
      Intl.message("Type a full Matrix ID, with the @ and the server.",
          name: "messageServerAdminInvalidUser",
          desc: "Shown in the server administration tools when what was typed "
              "is not a Matrix ID");

  static String noticeFor(ServerAdminFailure failure) => switch (failure) {
        ServerAdminFailure.forbidden => messageServerAdminForbidden,
        ServerAdminFailure.unsupported => messageServerAdminUnsupported,
        ServerAdminFailure.notFound => messageServerAdminNotFound,
        ServerAdminFailure.other => messageServerAdminFailed,
      };

  @override
  State<ServerAdminPanel> createState() => _ServerAdminPanelState();
}

class _ServerAdminPanelState extends State<ServerAdminPanel> {
  final field = TextEditingController();
  ServerAdminLookup? result;
  String? userId;
  String? notice;
  bool busy = false;

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void clearResult() {
    if (result != null || userId != null || notice != null) {
      setState(() {
        result = null;
        userId = null;
        notice = null;
      });
    }
  }

  Future<void> lookUp() async {
    final id = field.text.trim();
    if (!RegExp(r'^@[^\s:]+:\S+$').hasMatch(id)) {
      setState(() {
        result = null;
        userId = null;
        notice = ServerAdminPanel.messageServerAdminInvalidUser;
      });
      return;
    }
    setState(() => busy = true);
    final found = await widget.admin.lookUp(id);
    if (!mounted) return;
    if (field.text.trim() != id) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      busy = false;
      userId = id;
      result = found;
      final failure = found.failure;
      notice = failure == null ? null : ServerAdminPanel.noticeFor(failure);
    });
  }

  Future<void> change(bool locked, bool value) async {
    final id = userId, current = result;
    if (id == null || current == null) return;
    if (value) {
      final confirmed = await AdaptiveDialog.confirmation(
        context,
        title: locked
            ? ServerAdminPanel.labelServerAdminConfirmLockTitle
            : ServerAdminPanel.labelServerAdminConfirmSuspendTitle,
        prompt: locked
            ? ServerAdminPanel.messageServerAdminConfirmLock(id)
            : ServerAdminPanel.messageServerAdminConfirmSuspend(id),
        confirmationText: locked
            ? ServerAdminPanel.promptServerAdminLock
            : ServerAdminPanel.promptServerAdminSuspend,
        cancelText: CommonStrings.promptCancel,
        dangerous: true,
      );
      if (confirmed != true || !mounted || userId != id || result != current) {
        return;
      }
    }
    setState(() => busy = true);
    try {
      final answer = locked
          ? await widget.admin.setLocked(id, value)
          : await widget.admin.setSuspended(id, value);
      locked ? current.locked = answer : current.suspended = answer;
      notice = null;
    } catch (e, s) {
      Log.onError(e, s, content: "Server administration request failed");
      notice = ServerAdminPanel.noticeFor(MatrixServerAdmin.failureOf(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final found = result;
    final shownUser = userId;
    final devices = found?.whois?.devices ?? const {};
    final hasDetails = found != null &&
        shownUser != null &&
        (found.whois != null ||
            found.locked != null ||
            found.suspended != null);
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: ServerAdminPanel.labelServerAdminHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(ServerAdminPanel.labelServerAdminDescription),
          TextField(
            key: ServerAdminPanel.userFieldKey,
            controller: field,
            decoration: InputDecoration(
                labelText: ServerAdminPanel.labelServerAdminUser),
            onChanged: (_) => clearResult(),
            onSubmitted: (_) => lookUp(),
          ),
          tiamat.Button.secondary(
            key: ServerAdminPanel.lookUpKey,
            text: ServerAdminPanel.promptServerAdminLookUp,
            isLoading: busy,
            onTap: busy ? null : lookUp,
          ),
          if (notice != null)
            tiamat.Text.error(notice!, key: ServerAdminPanel.noticeKey),
          if (hasDetails)
            tiamat.Text.labelEmphasised(
              shownUser,
              key: ServerAdminPanel.resultUserKey,
            ),
          if (found?.whois != null) ...[
            tiamat.Text.labelEmphasised(
                UserDeviceListView.labelProfileSessions(devices.length)),
            for (final device in devices.entries)
              tiamat.Text.label([
                device.key,
                for (final session in device.value.sessions ?? const [])
                  for (final connection in session.connections ?? const [])
                    if (connection.ip != null) connection.ip!,
              ].join(' · ')),
          ],
          if (found?.locked != null)
            SwitchListTile(
              key: ServerAdminPanel.lockedKey,
              contentPadding: EdgeInsets.zero,
              title: tiamat.Text.label(ServerAdminPanel.labelServerAdminLocked),
              value: found!.locked!,
              onChanged: busy ? null : (value) => change(true, value),
            ),
          if (found?.suspended != null)
            SwitchListTile(
              key: ServerAdminPanel.suspendedKey,
              contentPadding: EdgeInsets.zero,
              title:
                  tiamat.Text.label(ServerAdminPanel.labelServerAdminSuspended),
              value: found!.suspended!,
              onChanged: busy ? null : (value) => change(false, value),
            ),
        ],
      ),
    );
  }
}
