import 'dart:async';
import 'dart:js_interop';

import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/clipboard/pasted_file.dart';
import 'package:web/web.dart' as web;

void Function() listenForPastedFiles({
  required bool Function() accept,
  required void Function(List<PastedFile> files) onFiles,
}) {
  void onPaste(web.ClipboardEvent event) {
    final clipboard = event.clipboardData;
    if (clipboard == null || !accept()) return;
    final types = clipboard.types.toDart.map((type) => type.toDart);
    if (types.contains("text/plain")) return;
    final files = [
      for (var i = 0; i < clipboard.files.length; i++) clipboard.files.item(i)!,
    ];
    if (files.isEmpty) return;
    event.preventDefault();
    unawaited(_read(files).then(onFiles).catchError((Object e, StackTrace s) =>
        Log.onError(e, s, content: "Could not read a pasted file")));
  }

  final listener = onPaste.toJS;
  web.document.addEventListener("paste", listener);
  return () => web.document.removeEventListener("paste", listener);
}

Future<List<PastedFile>> _read(List<web.File> files) async => [
      for (final file in files)
        PastedFile((await file.arrayBuffer().toDart).toDart.asUint8List(),
            name: file.name.isEmpty ? null : file.name,
            mimeType: file.type.isEmpty ? null : file.type),
    ];
