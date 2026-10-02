import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/dj/dj_prompts.dart';
import 'package:rooster/ui/organisms/dj/dj_toast.dart';
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
          if (sources == null)
            const DesktopAppNotice(
                '🧩 Plug in sources and pull audio from YouTube, SoundCloud, '
                'X and more into the DJ booth and the soundboard. Sources '
                'run in the desktop app.'),
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

  Future<void> _remove(BuildContext context) async {
    final yes = await AdaptiveDialog.confirmation(context,
        title: 'Remove ${source.name}?',
        prompt: 'Songs it queued stop playing on this computer, and what it '
            'downloaded is deleted.',
        confirmationText: 'Remove',
        cancelText: 'Keep');
    if (yes != true) return;
    try {
      await sources.remove(source.id);
    } catch (e, s) {
      Log.onError(e, s, content: 'DJ booth: could not remove an extension');
      DjToast.show("Couldn't remove ${source.name}: $e", isError: true);
    }
  }

  static String _uses(Set<String> uses) => 'For ${[
        if (uses.contains('dj')) 'the DJ booth',
        if (uses.contains('soundboard')) 'the soundboard',
      ].join(' and ')}';

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
        _uses(source.uses),
        if (from != null) 'From $from',
      ].join('\n')),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (from != null)
            IconButton(
              tooltip: 'Install again from where it came, to update it',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => installDjSource(context, link: from),
            ),
          if (homepage != null)
            IconButton(
              tooltip: 'Open its page',
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: () =>
                  LinkUtils.open(Uri.parse(homepage), context: context),
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => _remove(context),
          ),
        ],
      ),
    );
  }
}
