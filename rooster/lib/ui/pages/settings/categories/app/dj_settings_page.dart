import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/dj/dj_prompts.dart';
import 'package:rooster/ui/organisms/dj/dj_toast.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Source extensions: what finds and downloads the audio a pasted link
/// points to, for the DJ booth and the soundboard
/// (docs/source-extensions.md). Desktop only.
class DjSettingsPage extends StatelessWidget {
  const DjSettingsPage({super.key});

  String get headerDjSources => Intl.message("Sources",
      name: "headerDjSources",
      desc: "Header for the DJ booth's source extensions in settings");

  String get labelDjSourcesDescription => Intl.message(
      "The DJ booth and the soundboard take audio files from this computer "
      "and links to audio files. To take links to pages too (a video, a "
      "post), add a source: an extension, made by others, that finds and "
      "downloads the audio a link points to. Install only ones you trust, "
      "and use them within the terms of the sites they download from.",
      name: "labelDjSourcesDescription",
      desc: "Explains what DJ source extensions are");

  String get labelDjSourcesNone => Intl.message("No source installed.",
      name: "labelDjSourcesNone",
      desc: "Shown when no DJ source extension is installed");

  String get labelDjSourcesAdd => Intl.message("Add a source…",
      name: "labelDjSourcesAdd",
      desc: "Button that installs a DJ source extension");

  String get labelDjSourcesDesktopOnly => Intl.message(
      "🧩 Plug in sources and pull audio from YouTube, SoundCloud, X and more "
      "into the DJ booth and the soundboard. Sources run in the desktop app.",
      name: "labelDjSourcesDesktopOnly",
      desc: "In the DJ settings of an app that can't run source extensions "
          "(web, phones): they need the desktop app. A link to download it "
          "follows");

  @override
  Widget build(BuildContext context) {
    final sources = DjPlatform.instance.sources;
    return tiamat.Panel(
      header: headerDjSources,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          tiamat.Text.labelLow(labelDjSourcesDescription),
          if (sources == null) DesktopAppNotice(labelDjSourcesDesktopOnly),
          if (sources != null)
            ValueListenableBuilder(
              valueListenable: sources.installed,
              builder: (context, installed, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  if (installed.isEmpty) tiamat.Text.label(labelDjSourcesNone),
                  for (final source in installed)
                    _SourceTile(sources: sources, source: source),
                ],
              ),
            ),
          if (sources != null)
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button(
                text: labelDjSourcesAdd,
                onTap: () => installDjSource(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.sources, required this.source});

  final DjSources sources;
  final DjSourceInfo source;

  static String labelDjRemoveSourceTitle(String name) => Intl.message(
      "Remove $name?",
      name: "labelDjRemoveSourceTitle",
      args: [name],
      desc: "Title of the window asking whether to remove a source extension; "
          "the placeholder is its name");

  static String get labelDjRemoveSourcePrompt => Intl.message(
      "Songs it queued stop playing on this computer, and what it downloaded "
      "is deleted.",
      name: "labelDjRemoveSourcePrompt",
      desc: "In the window asking whether to remove a source extension: what "
          "removing it does");

  static String errorDjRemoveSource(String name, String error) =>
      Intl.message("Couldn't remove $name: $error",
          name: "errorDjRemoveSource",
          args: [name, error],
          desc: "Shown when removing a source extension failed; the "
              "placeholders are its name and the error");

  static String get labelDjSourceForDj => Intl.message("For the DJ booth",
      name: "labelDjSourceForDj",
      desc: "Under an installed source extension in settings: what it is "
          "used for");

  static String get labelDjSourceForSoundboard =>
      Intl.message("For the soundboard",
          name: "labelDjSourceForSoundboard",
          desc: "Under an installed source extension in settings: what it is "
              "used for");

  static String get labelDjSourceForBoth =>
      Intl.message("For the DJ booth and the soundboard",
          name: "labelDjSourceForBoth",
          desc: "Under an installed source extension in settings: what it is "
              "used for");

  static String labelDjSourceFrom(String link) => Intl.message("From $link",
      name: "labelDjSourceFrom",
      args: [link],
      desc: "Under an installed source extension in settings: the link it "
          "was installed from");

  static String get tooltipDjReinstallSource =>
      Intl.message("Install again from where it came, to update it",
          name: "tooltipDjReinstallSource",
          desc: "Tooltip on the button that updates an installed source "
              "extension by installing it again from its link");

  static String get tooltipDjOpenSourcePage => Intl.message("Open its page",
      name: "tooltipDjOpenSourcePage",
      desc: "Tooltip on the button that opens an installed source "
          "extension's web page");

  Future<void> _remove(BuildContext context) async {
    final yes = await AdaptiveDialog.confirmation(context,
        title: labelDjRemoveSourceTitle(source.name),
        prompt: labelDjRemoveSourcePrompt,
        confirmationText: CommonStrings.promptRemove,
        cancelText: promptDjKeep);
    if (yes != true) return;
    try {
      await sources.remove(source.id);
    } catch (e, s) {
      Log.onError(e, s, content: 'DJ booth: could not remove an extension');
      DjToast.show(errorDjRemoveSource(source.name, '$e'), isError: true);
    }
  }

  /// What the extension is for, when it says something this app knows.
  static String? _uses(Set<String> uses) =>
      switch ((uses.contains('dj'), uses.contains('soundboard'))) {
        (true, true) => labelDjSourceForBoth,
        (true, false) => labelDjSourceForDj,
        (false, true) => labelDjSourceForSoundboard,
        (false, false) => null,
      };

  @override
  Widget build(BuildContext context) {
    final homepage = source.homepage;
    final from = source.installedFrom;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text('${source.name} ${source.version}'),
      subtitle: Text([
        if (source.description != null) source.description!,
        if (_uses(source.uses) case final uses?) uses,
        if (from != null) labelDjSourceFrom(from),
      ].join('\n')),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (from != null)
            IconButton(
              tooltip: tooltipDjReinstallSource,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => installDjSource(context, link: from),
            ),
          if (homepage != null)
            IconButton(
              tooltip: tooltipDjOpenSourcePage,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: () =>
                  LinkUtils.open(Uri.parse(homepage), context: context),
            ),
          IconButton(
            tooltip: CommonStrings.promptRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => _remove(context),
          ),
        ],
      ),
    );
  }
}
