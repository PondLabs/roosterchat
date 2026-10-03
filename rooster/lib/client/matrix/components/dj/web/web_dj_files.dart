// Songs a DJ picked in this browser. A browser gives no paths, only the
// files' contents: each is kept as a blob URL for as long as the page is
// open, and queued as `file:<id>` like a desktop DJ's file, so the room sees
// only its name.
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:web/web.dart' as web;

class WebDjFiles {
  WebDjFiles._();
  static final WebDjFiles instance = WebDjFiles._();

  static final Random _random = Random();

  /// Blob URLs by file id.
  final Map<String, String> _urls = {};

  /// A queue entry for the picked file [name] with [bytes].
  DjTrack track(String name, Uint8List bytes,
      {required String id, required String addedBy}) {
    final fileId =
        List.generate(3, (_) => _random.nextInt(1 << 30).toRadixString(36))
            .join();
    final blob = web.Blob([bytes.toJS].toJS);
    _urls[fileId] = web.URL.createObjectURL(blob);
    final dot = name.lastIndexOf('.');
    final title = (dot > 0 ? name.substring(0, dot) : name).trim();
    return DjTrack(
      id: id,
      source: '${DjTrack.filePrefix}$fileId',
      kind: DjTrack.fileKind,
      title: title.isEmpty
          ? name
          : (title.length > DjTrack.maxText
              ? title.substring(0, DjTrack.maxText)
              : title),
      addedBy: addedBy,
    );
  }

  /// Where the file queued as `file:<id>` plays from, when this browser
  /// picked it.
  String? urlOf(String source) {
    if (!source.startsWith(DjTrack.filePrefix)) return null;
    return _urls[source.substring(DjTrack.filePrefix.length)];
  }
}
