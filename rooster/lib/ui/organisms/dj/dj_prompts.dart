// The booth's questions to the user: installing a source extension (from a
// file or a link, nothing fetched without a yes; docs/source-extensions.md), and
// whether to take the decks someone is handing them.
import 'dart:async';

import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/dj/dj_toast.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

String get labelDjReadingExtension => Intl.message("Reading the extension",
    name: "labelDjReadingExtension",
    desc: "Title of the progress window while a source extension (a package "
        "that lets the DJ booth play links) is opened to be installed");

String errorDjReadExtension(String error) => Intl.message(
    "Couldn't read that extension: $error",
    name: "errorDjReadExtension",
    args: [error],
    desc: "Shown when a source extension the user opened could not be read; "
        "the placeholder is why");

String errorDjCantInstallHere(String name, String problem) =>
    Intl.message("$name can't be installed here: $problem",
        name: "errorDjCantInstallHere",
        args: [name, problem],
        desc: "Shown when a source extension can't be installed on this "
            "computer; the placeholders are its name and why");

String labelDjInstallExtensionTitle(String name, String version) =>
    Intl.message("Install $name $version?",
        name: "labelDjInstallExtensionTitle",
        args: [name, version],
        desc: "Title of the window asking whether to install a source "
            "extension; the placeholders are its name and version");

String labelDjReplaceExtensionTitle(
        String name, String oldVersion, String newVersion) =>
    Intl.message("Replace $name $oldVersion with $newVersion?",
        name: "labelDjReplaceExtensionTitle",
        args: [name, oldVersion, newVersion],
        desc: "Title of the window asking whether to update an installed "
            "source extension; the placeholders are its name, the installed "
            "version and the new one");

String get labelDjExtensionWarning => Intl.message(
    "A source extension runs a program on your computer, with your "
    "permissions. It is not made by Rooster's makers: install it only if you "
    "trust where it came from, and use it within the terms of the sites it "
    "plays from.",
    name: "labelDjExtensionWarning",
    desc: "Warning in the window asking whether to install a source "
        "extension (a package, made by others, that lets the DJ booth and "
        "the soundboard play links)");

String labelDjExtensionDownloads(String downloads) =>
    Intl.message("It downloads $downloads.",
        name: "labelDjExtensionDownloads",
        args: [downloads],
        desc: "In the window asking whether to install a source extension: the "
            "programs it will download, a list of names with their sizes");

String get promptDjInstall => Intl.message("Install",
    name: "promptDjInstall",
    desc: "Button that installs a source extension, in the window asking "
        "whether to");

String labelDjInstallingExtension(String name) =>
    Intl.message("Installing $name",
        name: "labelDjInstallingExtension",
        args: [name],
        desc: "Title of the progress window while a source extension is "
            "installed; the placeholder is its name");

String messageDjExtensionInstalled(String name) =>
    Intl.message("$name is installed",
        name: "messageDjExtensionInstalled",
        args: [name],
        desc: "Shown once a source extension is installed; the placeholder is "
            "its name");

String errorDjInstallExtension(String name, String error) =>
    Intl.message("Couldn't install $name: $error",
        name: "errorDjInstallExtension",
        args: [name, error],
        desc: "Shown when installing a source extension failed; the "
            "placeholders are its name and the error");

String get labelDjChooseExtensionFile =>
    Intl.message("Choose a source extension",
        name: "labelDjChooseExtensionFile",
        desc: "Title of the file chooser that opens a source extension (a .zip "
            "file) to install");

String get labelDjAddMusicSourceTitle => Intl.message("Add a music source",
    name: "labelDjAddMusicSourceTitle",
    desc: "Title of the window that installs a source extension, which lets "
        "the DJ booth play songs from links");

String get labelDjAddMusicSourceDescription => Intl.message(
    "A source extension lets the DJ play songs from links. Extensions are "
    "made by others and come as a .zip: open the file, or paste a link to "
    "it.",
    name: "labelDjAddMusicSourceDescription",
    desc: "Explanation in the window that installs a source extension");

String get labelDjExtensionLink => Intl.message("Link to the extension",
    name: "labelDjExtensionLink",
    desc: "Label of the box for a link to a source extension's .zip file");

String get promptDjOpenExtensionFile => Intl.message("Open a file…",
    name: "promptDjOpenExtensionFile",
    desc: "Button that opens a source extension's .zip file from this "
        "computer");

String get labelDjProgressStarting => Intl.message("Starting…",
    name: "labelDjProgressStarting",
    desc: "In the progress window of a source extension's install, before "
        "anything is downloaded");

String labelDjProgressDownloading(String name) =>
    Intl.message("Downloading $name…",
        name: "labelDjProgressDownloading",
        args: [name],
        desc: "In the progress window of a source extension's install: what is "
            "being downloaded (the extension, or a program it needs)");

String labelDjHandingYouDecksTitle(String name) =>
    Intl.message("$name is handing you the decks",
        name: "labelDjHandingYouDecksTitle",
        args: [name],
        desc: "Title of the window asking whether to become the DJ (take \"the "
            "decks\" of the DJ booth), when the DJ passes them to the user "
            "unasked; the placeholder is the DJ");

String get labelDjTakeOverQuestion => Intl.message(
    "Take over as the DJ? The music keeps playing and the queue stays as it "
    "is.",
    name: "labelDjTakeOverQuestion",
    desc: "In the window asking whether to become the DJ, when the DJ passes "
        "the DJ booth to the user unasked");

String get promptDjTakeDecks => Intl.message("Take the decks",
    name: "promptDjTakeDecks",
    desc: "Button that accepts becoming the DJ (taking \"the decks\" of the "
        "DJ booth) when the DJ passes them");

String get promptDjKeep => Intl.message("Keep",
    name: "promptDjKeep",
    desc: "Button that cancels removing something in the DJ booth or its "
        "settings (the queue, a source extension): keeps it");

Future<void>? _installing;

/// Asks for a source extension (a file or a link; [link] skips asking, to
/// update one from where it came), shows what it is and what it downloads,
/// and installs it once the user agrees. One at a time.
Future<void> installDjSource(BuildContext context, {String? link}) =>
    _installing ??=
        _install(context, link).whenComplete(() => _installing = null);

Future<void> _install(BuildContext context, String? link) async {
  final sources = DjPlatform.instance.sources;
  if (sources == null) return;

  final choice = link != null
      ? _SourceChoice(link: link)
      : await showDialog<_SourceChoice>(
          context: context, builder: (_) => const _ChooseSourceDialog());
  if (choice == null || !context.mounted) return;

  final DjSourcePackage package;
  try {
    final opened = await _withProgress<DjSourcePackage>(
        context,
        labelDjReadingExtension,
        (onProgress, cancel) => choice.file != null
            ? sources.openFile(choice.file!)
            : sources.openLink(choice.link!, cancel: cancel));
    if (opened == null) return;
    package = opened;
  } catch (e, s) {
    Log.onError(e, s, content: 'DJ booth: could not read an extension');
    DjToast.show(errorDjReadExtension('$e'), isError: true);
    return;
  }
  if (!context.mounted) return;

  final info = package.info;
  final problem = package.problem;
  if (problem != null) {
    DjToast.show(errorDjCantInstallHere(info.name, problem), isError: true);
    return;
  }
  final downloads = package.downloads
      .map((d) => d.$2 == null ? '**${d.$1}**' : '**${d.$1}** (${d.$2})')
      .join(', ');
  final replacing = sources.installed.value
      .where((installed) => installed.id == info.id)
      .firstOrNull;
  final yes = await AdaptiveDialog.confirmation(
    context,
    title: replacing == null
        ? labelDjInstallExtensionTitle(info.name, info.version)
        : labelDjReplaceExtensionTitle(
            info.name, replacing.version, info.version),
    prompt: [
      if (info.description != null) info.description!,
      if (info.homepage != null) info.homepage!,
      labelDjExtensionWarning,
      if (downloads.isNotEmpty) labelDjExtensionDownloads(downloads),
    ].join('\n\n'),
    confirmationText: promptDjInstall,
    cancelText: CommonStrings.promptCancel,
  );
  if (yes != true || !context.mounted) return;

  try {
    final done = await _withProgress<bool>(
        context, labelDjInstallingExtension(info.name),
        (onProgress, cancel) async {
      await sources.install(package, onProgress: onProgress, cancel: cancel);
      return true;
    });
    if (done == true) DjToast.show(messageDjExtensionInstalled(info.name));
  } catch (e, s) {
    Log.onError(e, s, content: 'DJ booth: could not install an extension');
    DjToast.show(errorDjInstallExtension(info.name, '$e'), isError: true);
  }
}

class _SourceChoice {
  final String? file;
  final String? link;

  const _SourceChoice({this.file, this.link});
}

class _ChooseSourceDialog extends StatefulWidget {
  const _ChooseSourceDialog();

  @override
  State<_ChooseSourceDialog> createState() => _ChooseSourceDialogState();
}

class _ChooseSourceDialogState extends State<_ChooseSourceDialog> {
  final TextEditingController _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  bool get _linkOk => Uri.tryParse(_link.text.trim())?.scheme == 'https';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: labelDjChooseExtensionFile,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = result?.files.singleOrNull?.path;
    if (path != null && mounted) {
      Navigator.of(context).pop(_SourceChoice(file: path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(labelDjAddMusicSourceTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            tiamat.Text.labelLow(labelDjAddMusicSourceDescription),
            TextField(
              controller: _link,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_linkOk) {
                  Navigator.of(context)
                      .pop(_SourceChoice(link: _link.text.trim()));
                }
              },
              decoration: InputDecoration(
                  isDense: true,
                  labelText: labelDjExtensionLink,
                  // Not translated: an example of a link, not words.
                  hintText: 'https://…/extension.zip'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _pickFile, child: Text(promptDjOpenExtensionFile)),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(CommonStrings.promptCancel)),
        FilledButton(
          onPressed: _linkOk
              ? () => Navigator.of(context)
                  .pop(_SourceChoice(link: _link.text.trim()))
              : null,
          child: Text(CommonStrings.promptNext),
        ),
      ],
    );
  }
}

Future<T?> _withProgress<T>(
        BuildContext context,
        String title,
        Future<T> Function(
                void Function(String step, double? progress) onProgress,
                DjSourceCancel cancel)
            task) =>
    runWithProgressDialog(context, title, task);

/// Runs [task] under a dialog showing its progress, with a Cancel button.
/// Null when the user cancelled. The dialog is gone by the time this
/// returns, so the caller can show the next one.
///
/// It removes its own route, never whatever is on top: a quick task (reading
/// a small file) can finish before the dialog has even been built, and a
/// plain pop() then closed the dialog the caller showed next.
Future<T?> runWithProgressDialog<T>(
    BuildContext context,
    String title,
    Future<T> Function(void Function(String step, double? progress) onProgress,
            DjSourceCancel cancel)
        task) async {
  final progress = ValueNotifier<(String, double?)>(('', null));
  final cancel = DjSourceCancel();
  final shown = Completer<Route<dynamic>>();
  final closed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final route = ModalRoute.of(dialogContext);
      if (route != null && !shown.isCompleted) shown.complete(route);
      return AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              tiamat.Text.labelLow(value.$1.isEmpty
                  ? labelDjProgressStarting
                  : labelDjProgressDownloading(value.$1)),
              LinearProgressIndicator(value: value.$2),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: cancel.cancel,
              child: Text(CommonStrings.promptCancel)),
        ],
      );
    },
  );
  try {
    return await task((step, value) => progress.value = (step, value), cancel);
  } on DjSourceCancelled {
    return null;
  } catch (_) {
    if (cancel.cancelled) return null;
    rethrow;
  } finally {
    final route = await shown.future;
    final navigator = route.navigator;
    if (navigator != null && route.isActive) {
      // Popped normally when it is on top, so it animates out; taken out
      // from under whatever else is showing otherwise.
      if (route.isCurrent) {
        navigator.pop();
        await closed;
      } else {
        navigator.removeRoute(route);
      }
    }
  }
}

/// Asks whether to take the decks [fromName] is handing over, for someone
/// who didn't ask for them. Unanswered for long, it counts as a no.
Future<bool> askToTakeDecks(String fromName) async {
  final context = navigator.currentContext;
  if (context == null || !context.mounted) return false;
  final answer = await AdaptiveDialog.confirmation(
    context,
    title: labelDjHandingYouDecksTitle(fromName),
    prompt: labelDjTakeOverQuestion,
    confirmationText: promptDjTakeDecks,
    cancelText: CommonStrings.promptPoliteNo,
  ).timeout(const Duration(seconds: 60), onTimeout: () {
    final open = navigator.currentContext;
    if (open != null && open.mounted) Navigator.of(open).maybePop();
    return false;
  });
  return answer == true;
}
