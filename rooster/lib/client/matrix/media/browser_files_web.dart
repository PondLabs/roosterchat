import 'dart:async';
import 'dart:js_interop';

import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/browser_file_source.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/utils/mime.dart';
import 'package:web/web.dart' as web;

/// Opens the browser's file dialog and gives the files chosen, or null
/// when it was closed without any. A test replaces it.
Future<List<web.File>?> Function() pickBrowserFiles = _pickWithInput;

/// The files the person picks ([pickBrowserFiles]) as attachments. Each one
/// over the limit [maxBytes] gives goes to [onRefused] by its `File.size`,
/// unread. The dialog opens first and the limit is asked after: a dialog
/// opened after a network wait can lose the click that asked for it.
Future<List<PendingFileAttachment>?> pickBrowserFileAttachments({
  required Future<int?> Function() maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
}) async {
  final files = await pickBrowserFiles();
  if (files == null) return const [];
  final limit = await maxBytes();
  final admitted = <PendingFileAttachment>[];
  for (final file in files) {
    if (limit != null && file.size > limit) {
      onRefused(file.size, limit);
      continue;
    }
    admitted.add(await browserFileAttachment(file, name: file.name));
  }
  return admitted;
}

/// [file] as an attachment: sent from the browser's `Blob` when it is over
/// [streamFromDiskAbove] and not a picture (pictures are prepared from
/// their bytes), else read into memory, as before.
Future<PendingFileAttachment> browserFileAttachment(web.Blob file,
    {String? name, String? mimeType}) async {
  final type = mimeType ?? Mime.lookupType(name ?? "");
  if (file.size <= streamFromDiskAbove || Mime.imageTypes.contains(type)) {
    final data = (await file.arrayBuffer().toDart).toDart.asUint8List();
    return PendingFileAttachment(
        name: name, data: data, mimeType: mimeType, size: data.length);
  }
  return PendingFileAttachment(
      name: name,
      source: BrowserFileSource(file),
      mimeType: mimeType,
      size: file.size);
}

/// A file dropped on the page, which the drop gives as an object URL of
/// its `File` (`blob:`): its `Blob` is fetched from the browser's blob
/// store, not read. Null for another URL.
Future<PendingFileAttachment?> droppedBrowserFile(String url,
    {String? name}) async {
  if (!url.startsWith('blob:')) return null;
  final response = await web.window.fetch(url.toJS).toDart;
  final blob = await response.blob().toDart;
  return browserFileAttachment(blob, name: name);
}

Future<List<web.File>?> _pickWithInput() {
  final done = Completer<List<web.File>?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.style.display = 'none';
  void finish(List<web.File>? files) {
    if (done.isCompleted) return;
    done.complete(files);
    input.remove();
  }

  input.addEventListener(
      'change',
      ((web.Event _) {
        final list = input.files;
        finish(list == null || list.length == 0
            ? null
            : [for (var i = 0; i < list.length; i++) list.item(i)!]);
      }).toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  web.document.body?.append(input);
  input.click();
  return done.future;
}
