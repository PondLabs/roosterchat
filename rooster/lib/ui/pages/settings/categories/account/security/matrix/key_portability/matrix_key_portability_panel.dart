import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/key_portability/key_file_access.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_export_format.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_key_portability.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Exports the room keys of this device to a file protected by a
/// passphrase, and imports such a file, from Rooster or another app.
class MatrixKeyPortabilityPanel extends StatefulWidget {
  const MatrixKeyPortabilityPanel({
    required this.controller,
    this.files = const FilePickerKeyFileAccess(),
    super.key,
  });

  final KeyPortabilityController controller;
  final KeyFileAccess files;

  /// The shortest passphrase an export takes.
  static const minimumPassphraseLength = 8;

  // Not translated: a file name, the one Element's export has but ours.
  static const fileName = 'rooster-keys.txt';

  static String get labelKeyExportTitle => Intl.message("Export room keys",
      name: "labelKeyExportTitle",
      desc: "Settings > Security: title of the row that saves the keys of "
          "your encrypted messages to a file, and reads such a file");

  static String get labelKeyExportExplanation => Intl.message(
      "Save the keys of your encrypted messages in a file protected by a passphrase, to read those messages in another app or on a new session.",
      name: "labelKeyExportExplanation",
      desc: "Settings > Security: explains the room key export and import");

  static String get promptKeyExport => Intl.message("Export",
      name: "promptKeyExport",
      desc: "Settings > Security: button that saves the room keys to a file");

  static String get promptKeyImport => Intl.message("Import",
      name: "promptKeyImport",
      desc: "Settings > Security: button that reads room keys from a file "
          "saved by Rooster or another Matrix app");

  static String get labelKeyImportTitle => Intl.message("Import room keys",
      name: "labelKeyImportTitle",
      desc: "Settings > Security: title of the dialog asking for the "
          "passphrase of the key file being imported");

  static String get messageKeyExportPassphrase => Intl.message(
      "Choose a passphrase for the file. You will need it to import the keys.",
      name: "messageKeyExportPassphrase",
      desc: "Settings > Security > Export room keys: above the passphrase "
          "fields of the export");

  static String get labelKeyExportPassphrase => Intl.message("Passphrase",
      name: "labelKeyExportPassphrase",
      desc: "Settings > Security > Export room keys: label of the field for "
          "the passphrase that encrypts the file");

  static String get labelKeyExportConfirmPassphrase =>
      Intl.message("Repeat the passphrase",
          name: "labelKeyExportConfirmPassphrase",
          desc: "Settings > Security > Export room keys: label of the second "
              "passphrase field, which must match the first");

  static String errorKeyExportPassphraseTooShort(int howMany) =>
      Intl.plural(howMany,
          one: "Use at least 1 character.",
          other: "Use at least $howMany characters.",
          name: "errorKeyExportPassphraseTooShort",
          args: [howMany],
          desc: "Settings > Security > Export room keys: the passphrase is "
              "shorter than the shortest one allowed");

  static String get errorKeyExportPassphraseMismatch =>
      Intl.message("The passphrases are not the same.",
          name: "errorKeyExportPassphraseMismatch",
          desc: "Settings > Security > Export room keys: the two passphrase "
              "fields differ");

  static String messageKeyExportDone(int howMany) => Intl.plural(howMany,
      zero: "The file was saved, with no keys: this session has none yet.",
      one: "The file was saved, with 1 key.",
      other: "The file was saved, with $howMany keys.",
      name: "messageKeyExportDone",
      args: [howMany],
      desc: "Settings > Security: after the room keys were saved to a file, "
          "how many it holds");

  static String get messageKeyExportFailed =>
      Intl.message("The keys were not exported. Try again.",
          name: "messageKeyExportFailed",
          desc: "Settings > Security: exporting the room keys failed");

  static String get messageKeyImportPassphrase =>
      Intl.message("Enter the passphrase the file was saved with.",
          name: "messageKeyImportPassphrase",
          desc: "Settings > Security > Import room keys: above the "
              "passphrase field");

  static String messageKeyImportDone(int howMany) => Intl.plural(howMany,
      zero: "No keys were imported.",
      one: "1 key was imported.",
      other: "$howMany keys were imported.",
      name: "messageKeyImportDone",
      args: [howMany],
      desc: "Settings > Security: after a key file was imported, how many "
          "keys it gave that this session did not have yet");

  static String messageKeyImportAlreadyHeld(int howMany) => Intl.plural(howMany,
      one: "This session already had 1 key from the file.",
      other: "This session already had $howMany keys from the file.",
      name: "messageKeyImportAlreadyHeld",
      args: [howMany],
      desc: "Settings > Security: after a key file was imported, how many "
          "of its keys were left out because this session already holds "
          "them, as good or better");

  static String messageKeyImportSkipped(int howMany) => Intl.plural(howMany,
      one: "1 key in the file could not be used.",
      other: "$howMany keys in the file could not be used.",
      name: "messageKeyImportSkipped",
      args: [howMany],
      desc: "Settings > Security: after a key file was imported, how many "
          "of its entries were not keys this app can read");

  static String get errorKeyImportWrongPassphrase =>
      Intl.message("The passphrase is wrong, or the file was changed.",
          name: "errorKeyImportWrongPassphrase",
          desc: "Settings > Security > Import room keys: the file does not "
              "open with this passphrase. Nothing was imported");

  static String get errorKeyImportDamaged =>
      Intl.message("The file is damaged or incomplete. Nothing was imported.",
          name: "errorKeyImportDamaged",
          desc: "Settings > Security > Import room keys: the file is a key "
              "export cut short or broken");

  static String get errorKeyImportNotAKeyFile =>
      Intl.message("This is not a room key file. Nothing was imported.",
          name: "errorKeyImportNotAKeyFile",
          desc: "Settings > Security > Import room keys: the picked file is "
              "not a Matrix key export");

  static String get errorKeyImportInvalidContent => Intl.message(
      "The file opened, but holds no keys this app can read. Nothing was imported.",
      name: "errorKeyImportInvalidContent",
      desc: "Settings > Security > Import room keys: the passphrase was "
          "right but the content is not a list of room keys");

  static String get messageKeyImportFailed =>
      Intl.message("The keys were not imported. Try again.",
          name: "messageKeyImportFailed",
          desc: "Settings > Security: importing the room keys failed for "
              "another reason");

  /// What the panel says when an import of a key file failed.
  static String importError(Object error) => switch (error) {
        MegolmExportException(error: MegolmExportError.wrongPassphrase) =>
          errorKeyImportWrongPassphrase,
        MegolmExportException(error: MegolmExportError.damaged) =>
          errorKeyImportDamaged,
        MegolmExportException(error: MegolmExportError.notAKeyExport) =>
          errorKeyImportNotAKeyFile,
        MegolmExportException(error: MegolmExportError.invalidContent) =>
          errorKeyImportInvalidContent,
        _ => messageKeyImportFailed,
      };

  @override
  State<MatrixKeyPortabilityPanel> createState() =>
      _MatrixKeyPortabilityPanelState();
}

class _MatrixKeyPortabilityPanelState extends State<MatrixKeyPortabilityPanel> {
  bool busy = false;
  List<String> messages = const [];
  String? error;

  Future<void> exportKeys() async {
    final passphrase = await AdaptiveDialog.show<String>(context,
        title: MatrixKeyPortabilityPanel.labelKeyExportTitle,
        builder: (_) => const _ExportPassphraseView());
    if (passphrase == null || !mounted) return;
    await run(() async {
      final export = await widget.controller.exportKeys(passphrase);
      final saved = await widget.files
          .save(MatrixKeyPortabilityPanel.fileName, export.file);
      return [
        if (saved) MatrixKeyPortabilityPanel.messageKeyExportDone(export.count)
      ];
    }, (_) => MatrixKeyPortabilityPanel.messageKeyExportFailed);
  }

  Future<void> importKeys() async {
    final Uint8List? file;
    try {
      file = await widget.files.pick();
    } catch (e, s) {
      Log.onError(e, s);
      setState(() => error = MatrixKeyPortabilityPanel.messageKeyImportFailed);
      return;
    }
    if (file == null || !mounted) return;
    final passphrase = await AdaptiveDialog.show<String>(context,
        title: MatrixKeyPortabilityPanel.labelKeyImportTitle,
        builder: (_) => const _ImportPassphraseView());
    if (passphrase == null || !mounted) return;
    await run(() async {
      final result = await widget.controller.importKeys(file!, passphrase);
      return [
        MatrixKeyPortabilityPanel.messageKeyImportDone(result.imported),
        if (result.alreadyHeld > 0)
          MatrixKeyPortabilityPanel.messageKeyImportAlreadyHeld(
              result.alreadyHeld),
        if (result.unusable > 0)
          MatrixKeyPortabilityPanel.messageKeyImportSkipped(result.unusable),
      ];
    }, MatrixKeyPortabilityPanel.importError);
  }

  Future<void> run(Future<List<String>> Function() action,
      String Function(Object error) failure) async {
    setState(() {
      busy = true;
      messages = const [];
      error = null;
    });
    List<String> done = const [];
    String? failed;
    try {
      done = await action();
    } on MegolmExportException catch (e) {
      // Expected (a wrong passphrase, a damaged file): no stack to log.
      failed = failure(e);
    } catch (e, s) {
      Log.onError(e, s);
      failed = failure(e);
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      messages = done;
      error = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.label(
                      MatrixKeyPortabilityPanel.labelKeyExportTitle),
                  tiamat.Text.labelLow(
                      MatrixKeyPortabilityPanel.labelKeyExportExplanation),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  tiamat.Button.secondary(
                      text: MatrixKeyPortabilityPanel.promptKeyExport,
                      isLoading: busy,
                      onTap: busy ? null : exportKeys),
                  tiamat.Button.secondary(
                      text: MatrixKeyPortabilityPanel.promptKeyImport,
                      isLoading: busy,
                      onTap: busy ? null : importKeys),
                ],
              ),
            ),
          ],
        ),
        for (final message in messages) tiamat.Text.labelLow(message),
        if (error != null) tiamat.Text.error(error!),
      ],
    );
  }
}

/// Asks for the export's passphrase twice, hidden as it is typed, and
/// gives it back once it is long enough and both are the same.
class _ExportPassphraseView extends StatefulWidget {
  const _ExportPassphraseView();

  @override
  State<_ExportPassphraseView> createState() => _ExportPassphraseViewState();
}

class _ExportPassphraseViewState extends State<_ExportPassphraseView> {
  final passphrase = TextEditingController();
  final repeated = TextEditingController();
  String? error;

  @override
  void dispose() {
    passphrase.dispose();
    repeated.dispose();
    super.dispose();
  }

  void submit() {
    const minimum = MatrixKeyPortabilityPanel.minimumPassphraseLength;
    final String? problem;
    if (passphrase.text.length < minimum) {
      problem =
          MatrixKeyPortabilityPanel.errorKeyExportPassphraseTooShort(minimum);
    } else if (passphrase.text != repeated.text) {
      problem = MatrixKeyPortabilityPanel.errorKeyExportPassphraseMismatch;
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop(context, passphrase.text);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(
              MatrixKeyPortabilityPanel.messageKeyExportPassphrase),
          tiamat.Text.label(MatrixKeyPortabilityPanel.labelKeyExportPassphrase),
          tiamat.TextInput(
            key: const ValueKey('key-export-passphrase'),
            controller: passphrase,
            obscureText: true,
          ),
          tiamat.Text.label(
              MatrixKeyPortabilityPanel.labelKeyExportConfirmPassphrase),
          tiamat.TextInput(
            key: const ValueKey('key-export-passphrase-repeated'),
            controller: repeated,
            obscureText: true,
            onSubmitted: (_) => submit(),
          ),
          if (error != null) tiamat.Text.error(error!),
          tiamat.Button(
              text: MatrixKeyPortabilityPanel.promptKeyExport, onTap: submit),
          tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

/// Asks for the passphrase of the file being imported.
class _ImportPassphraseView extends StatefulWidget {
  const _ImportPassphraseView();

  @override
  State<_ImportPassphraseView> createState() => _ImportPassphraseViewState();
}

class _ImportPassphraseViewState extends State<_ImportPassphraseView> {
  final passphrase = TextEditingController();

  @override
  void dispose() {
    passphrase.dispose();
    super.dispose();
  }

  void submit() {
    if (passphrase.text.isEmpty) return;
    Navigator.pop(context, passphrase.text);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(
              MatrixKeyPortabilityPanel.messageKeyImportPassphrase),
          tiamat.TextInput(
            key: const ValueKey('key-import-passphrase'),
            controller: passphrase,
            obscureText: true,
            onSubmitted: (_) => submit(),
          ),
          tiamat.Button(
              text: MatrixKeyPortabilityPanel.promptKeyImport, onTap: submit),
          tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
