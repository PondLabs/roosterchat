/// Files picked to attach, checked against the server's limit on uploads
/// (`m.upload.size`) by their size before any of their bytes is read: a
/// file over it is refused at once, not after it was read, prepared and
/// sent.
library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/browser_files.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/utils/text_utils.dart';

/// The server's limit on an uploaded file in [room] (`m.upload.size`), or
/// null when it is not known. A test replaces it: its rooms are not
/// Matrix rooms.
Future<int?> Function(Room room) uploadLimitOf = _serverUploadLimit;

Future<int?> _serverUploadLimit(Room room) async =>
    room is MatrixRoom ? await room.maxUploadBytes() : null;

/// Whether [file], from the gallery or the camera, fits [maxBytes], by its
/// length (read from the file system on native), before its bytes are
/// read. One over it goes to [onRefused] with its size.
Future<bool> pickedFileFits(
  XFile file, {
  required int? maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
}) async {
  final bytes = await file.length();
  if (fitsUploadLimit(bytes, maxBytes)) return true;
  onRefused(bytes, maxBytes!);
  return false;
}

/// Whether a file of [bytes] may be sent under [maxBytes] (null: the limit
/// is not known, and the server checks).
bool fitsUploadLimit(int bytes, int? maxBytes) =>
    maxBytes == null || bytes <= maxBytes;

/// What the person is told about a file over the limit.
String messageFileOverUploadLimit(int bytes, int maxBytes) =>
    labelFileOverUploadLimit(TextUtils.readableFileSize(bytes),
        TextUtils.readableFileSize(maxBytes));

String labelFileOverUploadLimit(String size, String limit) => Intl.message(
    "This file is $size, over this server's limit of $limit, so it can't be "
    "sent.",
    name: "labelFileOverUploadLimit",
    args: [size, limit],
    desc: "Shown when a file picked or pasted to send is larger than the "
        "server accepts. The placeholders are sizes, such as '60 MB' and "
        "'50 MB'",
    examples: const {"size": "60 MB", "limit": "50 MB"});

/// Asks the picker for files, as paths and sizes on native and as the
/// browser's `File`s (size known, bytes read on demand) on the web, never
/// their bytes, and makes attachments of those within the limit
/// [maxBytes] gives. Each one over it goes to [onRefused] with its size,
/// unread. The picker opens first and the limit is asked after: on the
/// web a dialog opened after a network wait can lose the click that asked
/// for it.
Future<List<PendingFileAttachment>> pickFileAttachments({
  required Future<int?> Function() maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
  bool? web,
}) async {
  web ??= PlatformUtils.isWeb;
  if (web) {
    // In a browser, its own dialog, whose `File`s a large file is sent
    // from (`browser_files.dart`).
    final picked = await pickBrowserFileAttachments(
        maxBytes: maxBytes, onRefused: onRefused);
    if (picked != null) return picked;
  }
  final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
      withReadStream: web,
      allowMultiple: true);
  if (result == null) return const [];
  return admitPickedFiles(result.files,
      maxBytes: await maxBytes(), onRefused: onRefused, web: web);
}

/// [files] as attachments, checked by size first. On native a file is
/// attached by its path, read when needed; on the web its bytes are read
/// from its stream once it is admitted.
Future<List<PendingFileAttachment>> admitPickedFiles(
  List<PlatformFile> files, {
  required int? maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
  bool? web,
}) async {
  web ??= PlatformUtils.isWeb;
  final admitted = <PendingFileAttachment>[];
  for (final file in files) {
    if (!fitsUploadLimit(file.size, maxBytes)) {
      onRefused(file.size, maxBytes!);
      continue;
    }
    final path = web ? null : file.path;
    if (path != null) {
      admitted.add(
          PendingFileAttachment(name: file.name, path: path, size: file.size));
      continue;
    }
    final stream = file.readStream;
    final data = stream == null ? file.bytes : await _collect(stream);
    if (data == null) continue;
    admitted.add(
        PendingFileAttachment(name: file.name, data: data, size: data.length));
  }
  return admitted;
}

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final piece in stream) {
    builder.add(piece);
  }
  return builder.takeBytes();
}
