// Where a feature needs the desktop app (DJing, adding soundboard sounds,
// source extensions, system-wide shortcuts...): says so, and links to the
// releases page to download it.
import 'package:cockhouse/utils/links/link_utils.dart';
import 'package:cockhouse/utils/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopAppNotice extends StatelessWidget {
  /// A short pitch for what the desktop app adds, ending with a sentence
  /// ("🎧 Take over the decks! DJing lives in the desktop app.").
  final String message;

  const DesktopAppNotice(this.message, {super.key});

  static String get labelDownloadDesktopApp =>
      Intl.message("Get the desktop app",
          name: "labelDownloadDesktopApp",
          desc: "Link to the releases page, shown where a feature needs the "
              "desktop app");

  static String get labelDesktopPlatforms =>
      Intl.message("Available for Windows and Linux.",
          name: "labelDesktopPlatforms",
          desc: "Follows the pitch for a feature that needs the desktop app");

  /// Opens the page to download the desktop app from.
  static Future<void> openDownloads(BuildContext context) =>
      LinkUtils.open(Uri.parse(UpdateChecker.releasesPageUrl),
          context: context);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            const Icon(Icons.desktop_windows_outlined, size: 20),
            Flexible(
              child: tiamat.Text.labelLow('$message $labelDesktopPlatforms'),
            ),
            TextButton.icon(
              onPressed: () => openDownloads(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(labelDownloadDesktopApp),
            ),
          ],
        ),
      ),
    );
  }
}
