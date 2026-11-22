import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The backup on the server, as the panel shows it.
class KeyBackupStatus {
  const KeyBackupStatus({
    required this.version,
    required this.keyCount,
    required this.etag,
    required this.algorithm,
  });

  final String version;
  final int keyCount;
  final String etag;
  final String algorithm;
}

/// What the panel asks of the account, so a test can stand in for it.
abstract class KeyBackupController {
  /// The backup on the server, or null when there is none.
  Future<KeyBackupStatus?> load();

  /// Replaces the backup with one under a new key, kept in the secret
  /// storage that [recoveryKeyOrPassphrase] opens.
  Future<void> rotate(String recoveryKeyOrPassphrase);

  /// Deletes the backup and turns key backup off for the account.
  Future<void> delete();
}

class MatrixKeyBackupController implements KeyBackupController {
  MatrixKeyBackupController(this.client);

  final Client client;

  KeyManager get _keys => client.encryption!.keyManager;

  @override
  Future<KeyBackupStatus?> load() async {
    final info = await _keys.getKeyBackupStatus();
    if (info == null) return null;
    return KeyBackupStatus(
      version: info.version,
      keyCount: info.count,
      etag: info.etag,
      algorithm: info.algorithm.name,
    );
  }

  @override
  Future<void> rotate(String recoveryKeyOrPassphrase) async {
    final storage = client.encryption!.ssss.open();
    await storage.unlock(keyOrPassphrase: recoveryKeyOrPassphrase);
    await _keys.createKeyBackup(storage);
  }

  @override
  Future<void> delete() => _keys.deleteKeyBackup();
}

/// The details of the account's key backup, with its rotation and its
/// deletion, each asked for again before anything reaches the server.
class MatrixKeyBackupPanel extends StatefulWidget {
  const MatrixKeyBackupPanel(
      {required this.controller, this.onChanged, super.key});

  final KeyBackupController controller;

  /// Called after the backup was rotated or deleted.
  final VoidCallback? onChanged;

  static String labelKeyBackupVersion(String version) =>
      Intl.message("Version: $version",
          name: "labelKeyBackupVersion",
          args: [version],
          desc: "Settings > Security > Message backup: the version of the "
              "backup on the server, a number the server gives it");

  static String labelKeyBackupKeyCount(int howMany) => Intl.plural(howMany,
      zero: "No keys stored",
      one: "1 key stored",
      other: "$howMany keys stored",
      name: "labelKeyBackupKeyCount",
      args: [howMany],
      desc: "Settings > Security > Message backup: how many message keys "
          "the backup on the server holds");

  static String labelKeyBackupEtag(String etag) =>
      Intl.message("Change tag (etag): $etag",
          name: "labelKeyBackupEtag",
          args: [etag],
          desc: "Settings > Security > Message backup: the server's tag for "
              "the backup's current contents, which changes whenever keys "
              "are added. 'etag' is the protocol's name for it");

  static String labelKeyBackupAlgorithm(String algorithm) =>
      Intl.message("Algorithm: $algorithm",
          name: "labelKeyBackupAlgorithm",
          args: [algorithm],
          desc: "Settings > Security > Message backup: the encryption scheme "
              "of the backup, a protocol name such as "
              "m.megolm_backup.v1.curve25519-aes-sha2");

  static String get labelKeyBackupNone =>
      Intl.message("There is no backup on your server.",
          name: "labelKeyBackupNone",
          desc: "Settings > Security > Message backup: the server holds no "
              "backup of your message keys");

  static String get messageKeyBackupLoadFailed =>
      Intl.message("Could not load the details of your backup.",
          name: "messageKeyBackupLoadFailed",
          desc: "Settings > Security > Message backup: asking the server about "
              "the backup failed");

  static String get promptKeyBackupRotate => Intl.message("Rotate key",
      name: "promptKeyBackupRotate",
      desc: "Settings > Security > Message backup: button that replaces the "
          "backup with a new one under a new key");

  static String get promptKeyBackupDelete => Intl.message("Delete backup",
      name: "promptKeyBackupDelete",
      desc: "Settings > Security > Message backup: button that deletes the "
          "backup from the server");

  static String get messageKeyBackupConfirmRotate => Intl.message(
      "A new backup with a new key replaces this one, and every key on this device is saved in it again. The current backup is deleted from your server.",
      name: "messageKeyBackupConfirmRotate",
      desc: "Settings > Security > Message backup: asks before rotating the "
          "backup's key");

  static String get messageKeyBackupConfirmDelete => Intl.message(
      "Your backup is deleted from your server and backup is turned off on all your sessions. Messages that no session of yours can decrypt will be lost.",
      name: "messageKeyBackupConfirmDelete",
      desc: "Settings > Security > Message backup: asks before deleting the "
          "backup");

  static String get labelKeyBackupUnlockTitle =>
      Intl.message("Unlock your secret storage",
          name: "labelKeyBackupUnlockTitle",
          desc: "Settings > Security > Message backup: title of the dialog "
              "asking for the recovery key, which keeps the new backup key");

  static String get labelKeyBackupUnlockHint =>
      Intl.message("Recovery key or security phrase",
          name: "labelKeyBackupUnlockHint",
          desc: "Settings > Security > Message backup: placeholder of the "
              "field for the recovery key or the security phrase");

  static String get messageKeyBackupRotateFailed => Intl.message(
      "The key was not rotated. Check your recovery key and try again.",
      name: "messageKeyBackupRotateFailed",
      desc: "Settings > Security > Message backup: rotating the backup's key "
          "failed, for example because of a wrong recovery key");

  static String get messageKeyBackupDeleteFailed =>
      Intl.message("The backup was not deleted. Try again.",
          name: "messageKeyBackupDeleteFailed",
          desc: "Settings > Security > Message backup: deleting the backup "
              "failed");

  @override
  State<MatrixKeyBackupPanel> createState() => _MatrixKeyBackupPanelState();
}

class _MatrixKeyBackupPanelState extends State<MatrixKeyBackupPanel> {
  KeyBackupStatus? status;
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    KeyBackupStatus? loaded;
    String? failure;
    try {
      loaded = await widget.controller.load();
    } catch (e, s) {
      Log.onError(e, s);
      failure = MatrixKeyBackupPanel.messageKeyBackupLoadFailed;
    }
    if (!mounted) return;
    setState(() {
      status = loaded;
      loading = false;
      error = failure;
    });
  }

  Future<void> rotate() async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: MatrixKeyBackupPanel.promptKeyBackupRotate,
        prompt: MatrixKeyBackupPanel.messageKeyBackupConfirmRotate,
        confirmationText: MatrixKeyBackupPanel.promptKeyBackupRotate,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (confirmed != true || !mounted) return;
    final key = await AdaptiveDialog.show<String>(context,
        title: MatrixKeyBackupPanel.labelKeyBackupUnlockTitle,
        builder: (_) => const _UnlockView());
    if (key == null || key.isEmpty) return;
    await run(() => widget.controller.rotate(key),
        MatrixKeyBackupPanel.messageKeyBackupRotateFailed);
  }

  Future<void> delete() async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: MatrixKeyBackupPanel.promptKeyBackupDelete,
        prompt: MatrixKeyBackupPanel.messageKeyBackupConfirmDelete,
        confirmationText: MatrixKeyBackupPanel.promptKeyBackupDelete,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (confirmed != true || !mounted) return;
    await run(widget.controller.delete,
        MatrixKeyBackupPanel.messageKeyBackupDeleteFailed);
  }

  Future<void> run(Future<void> Function() action, String failure) async {
    setState(() => busy = true);
    String? failed;
    try {
      await action();
    } catch (e, s) {
      Log.onError(e, s);
      failed = failure;
    }
    if (!mounted) return;
    setState(() => busy = false);
    await load();
    if (!mounted) return;
    setState(() => error = failed);
    if (failed == null) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()));
    }
    final backup = status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        if (backup == null && error == null)
          tiamat.Text.labelLow(MatrixKeyBackupPanel.labelKeyBackupNone),
        if (backup != null) ...[
          tiamat.Text.labelLow(
              MatrixKeyBackupPanel.labelKeyBackupVersion(backup.version)),
          tiamat.Text.labelLow(
              MatrixKeyBackupPanel.labelKeyBackupKeyCount(backup.keyCount)),
          tiamat.Text.labelLow(
              MatrixKeyBackupPanel.labelKeyBackupEtag(backup.etag)),
          tiamat.Text.labelLow(
              MatrixKeyBackupPanel.labelKeyBackupAlgorithm(backup.algorithm)),
        ],
        if (error != null) tiamat.Text.error(error!),
        if (backup != null)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              tiamat.Button.secondary(
                  text: MatrixKeyBackupPanel.promptKeyBackupRotate,
                  isLoading: busy,
                  onTap: busy ? null : rotate),
              tiamat.Button.danger(
                  text: MatrixKeyBackupPanel.promptKeyBackupDelete,
                  isLoading: busy,
                  onTap: busy ? null : delete),
            ],
          ),
      ],
    );
  }
}

/// Asks for the recovery key or security phrase, hidden as it is typed.
class _UnlockView extends StatefulWidget {
  const _UnlockView();

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.TextInput(
            controller: controller,
            obscureText: true,
            placeholder: MatrixKeyBackupPanel.labelKeyBackupUnlockHint,
            onSubmitted: (_) => submit(),
          ),
          tiamat.Button(
              text: CommonStrings.promptContinue, onTap: () => submit()),
          tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
