// Pasted links in the browser's booth: a direct link to an audio file is a
// track as it is. Anything else (YouTube, SoundCloud) needs a source
// extension, which only the desktop app runs.
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:rooster/client/components/dj/dj_engine.dart';
import 'package:rooster/client/components/dj/dj_links.dart';
import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';

class WebDjLinkResolver implements DjResolver {
  static final Random _random = Random();
  static String _newId() =>
      List.generate(3, (_) => _random.nextInt(1 << 30).toRadixString(36))
          .join();

  /// The file name in [link]'s path, when it ends like an audio file.
  static String? audioFileOf(DjLink link) {
    final uri = Uri.tryParse(link.url);
    if (uri == null || uri.scheme != 'https') return null;
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return null;
    final extension = name.substring(dot + 1).toLowerCase();
    return DjPlatform.audioFileExtensions.contains(extension) ? name : null;
  }

  @override
  String? sourceFor(DjLink link) =>
      audioFileOf(link) == null ? null : labelDjWebAudioLinkSource;

  @override
  String? get hint => labelDjWebAddHint;

  static String get labelDjWebAudioLinkSource => Intl.message(
      "a link to an audio file",
      name: "labelDjWebAudioLinkSource",
      desc: "In the DJ booth in the browser, what plays a pasted link to an "
          "audio file: fills \"Played by ...\" under the link");

  static String get labelDjWebAddHint => Intl.message(
      "Add songs, or paste a link to an audio file. YouTube and SoundCloud "
      "play from the desktop app.",
      name: "labelDjWebAddHint",
      desc: "Placeholder of the DJ booth's box for links, in the browser");

  static String errorDjWebLinkNeedsDesktop(String host) =>
      Intl.message("Links from $host play from the desktop app",
          name: "errorDjWebLinkNeedsDesktop",
          args: [host],
          desc: "Why a link pasted in the DJ booth in the browser could not be "
              "added: links from that site (the placeholder) need the desktop "
              "app. Follows \"Couldn't add <link>:\"");

  @override
  Future<List<DjTrack>> resolve(DjLink link, {required String addedBy}) async {
    final name = audioFileOf(link);
    if (name == null) {
      throw StateError(errorDjWebLinkNeedsDesktop(link.host));
    }
    final dot = name.lastIndexOf('.');
    final title = Uri.decodeComponent(name.substring(0, dot)).trim();
    return [
      DjTrack(
        id: _newId(),
        source: link.url,
        kind: DjTrack.linkKind,
        title: title.isEmpty
            ? name
            : (title.length > DjTrack.maxText
                ? title.substring(0, DjTrack.maxText)
                : title),
        addedBy: addedBy,
      ),
    ];
  }
}
