// Files dropped on an open chat become attachments: every kind of file
// goes, whatever its type (an archive, a program, no extension at all).
// What cannot be read (a folder, a file without permission) is left out and
// reported; it used to throw and cancel the rest of the drop silently.

import 'package:rooster/client/attachment.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Above this a desktop attachment is read from its path when sent, not held
/// in memory. The browser has no path to read from later, so it always
/// holds the bytes.
const int droppedFileInMemoryLimit = 50000000;

Future<List<PendingFileAttachment>> attachmentsFromDroppedFiles(
  Iterable<XFile> files, {
  void Function(String name, Object error)? onSkipped,
  bool inBrowser = kIsWeb,
}) async {
  final attachments = <PendingFileAttachment>[];
  for (final file in files) {
    try {
      final size = await file.length();
      Uint8List? data;
      if (inBrowser || size < droppedFileInMemoryLimit) {
        data = await file.readAsBytes();
      }
      attachments.add(PendingFileAttachment(
          name: file.name,
          path: inBrowser ? null : file.path,
          size: size,
          data: data));
    } catch (e) {
      onSkipped?.call(file.name, e);
    }
  }
  return attachments;
}

/// Which of the open chats takes a drop at [at]: the one under the pointer,
/// or, dropped anywhere else (the room list, a header), the room's own chat
/// rather than a thread. A thread open beside the chat used to take every
/// drop too, attaching each file twice.
bool chatTakesDrop({
  required Rect? mine,
  required bool isThread,
  required Iterable<Rect> others,
  required Offset at,
}) {
  if (mine != null && mine.contains(at)) return true;
  if (others.any((r) => r.contains(at))) return false;
  return !isThread;
}
