/// Files picked to attach, checked against the server's limit on uploads
/// (`m.upload.size`) by their size before any of their bytes is read: a
/// file over it is refused at once, not after it was read, prepared and
/// sent.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/utils/text_utils.dart';

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
/// their bytes, and makes attachments of those within [maxBytes]. Each
/// one over it goes to [onRefused] with its size, unread.
Future<List<PendingFileAttachment>> pickFileAttachments({
  required int? maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
  bool? web,
}) async {
  web ??= PlatformUtils.isWeb;
  final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
      withReadStream: web,
      allowMultiple: true);
  if (result == null) return const [];
  return admitPickedFiles(result.files,
      maxBytes: maxBytes, onRefused: onRefused, web: web);
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
