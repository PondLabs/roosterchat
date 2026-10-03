// Pasted links in the browser's booth: a direct link to an audio file is a
// track as it is. Anything else (YouTube, SoundCloud) needs a source
// extension, which only the desktop app runs.
import 'dart:math';

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
      audioFileOf(link) == null ? null : 'a link to an audio file';

  @override
  String? get hint => 'Add songs, or paste a link to an audio file. YouTube '
      'and SoundCloud play from the desktop app.';

  @override
  Future<List<DjTrack>> resolve(DjLink link, {required String addedBy}) async {
    final name = audioFileOf(link);
    if (name == null) {
      throw StateError('Links from ${link.host} play from the desktop app');
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
