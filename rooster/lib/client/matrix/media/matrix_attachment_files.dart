/// Turns an attachment into the Matrix SDK's files to send, using the
/// picture's one preparation (`lib/utils/image/preparation/`): the SDK
/// itself decodes nothing.
///
/// The SDK computes a thumbnail, decoding the whole picture again, for any
/// `MatrixImageFile` sent without one (`$SDK/lib/src/room.dart`, in
/// `sendFileEvent`). So a picture with a thumbnail goes as a
/// `MatrixImageFile` with its size and blurhash, the thumbnail beside it;
/// one without goes as a [PreparedImageFile], an `m.image` that is not a
/// `MatrixImageFile`, which the SDK sends as it is.
///
/// A photo the preparation reduced ([ImagePreparation.reduced]) goes as
/// that reduced JPEG, with its size, when it is smaller than the attached
/// bytes (the photo with its metadata removed); otherwise the attached
/// bytes go.
///
/// On native, a file over [streamFromDiskAbove] attached by its path (not a
/// picture, which is prepared from its bytes) is not read here: the SDK
/// reads it from disk at each upload, in pieces (`disk_file_source.dart`).
library;

import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/disk_file_source.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/mime.dart';

/// A picture sent without a thumbnail: `m.image` with its displayed size
/// and blurhash in `info`, as a `MatrixImageFile` would put them, but not
/// one, so the SDK's thumbnail pass does not run on it.
class PreparedImageFile extends matrix.MatrixFile {
  PreparedImageFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    required this.width,
    required this.height,
    this.blurhash,
  });

  final int width;
  final int height;
  final String? blurhash;

  @override
  String get msgType => matrix.MessageTypes.Image;

  @override
  Map<String, dynamic> get info => {
        ...super.info,
        'w': width,
        'h': height,
        if (blurhash != null) 'xyz.amorgan.blurhash': blurhash,
      };
}

/// The files to send for [attachment]: its picture's preparation reused
/// (the one started when it was attached, or one started now), or the
/// file as it is when it is not a picture. A picture the engine cannot
/// decode goes as `application/octet-stream`, so no client tries to draw
/// it. Null when the file cannot be read. An attachment sent from the
/// composer (its [PendingFileAttachment.sending] set) comes back as a
/// [TrackedMatrixAttachment], so the room keeps its stage.
Future<MatrixProcessedAttachment?> matrixFilesForAttachment(
    PendingFileAttachment attachment,
    {ImagePreparer? preparer}) async {
  final fromDisk = await _diskSourceOf(attachment);
  if (fromDisk == null) {
    await attachment.resolve();
    if (attachment.data == null) return null;
  } else {
    attachment.size = fromDisk.length;
  }
  attachment.sending?.fileRead();
  // Read from disk by the SDK, its bytes never held here.
  T file<T extends matrix.MatrixFile>(T file) => file..source = fromDisk;

  final send = attachment.sending;
  MatrixProcessedAttachment processed(matrix.MatrixFile file,
          {matrix.MatrixImageFile? thumbnailFile}) =>
      send == null
          ? MatrixProcessedAttachment(file, thumbnailFile: thumbnailFile)
          : TrackedMatrixAttachment(file, send, thumbnailFile: thumbnailFile);

  ImagePreparation? prepared;
  final isImage = Mime.imageTypes.contains(attachment.mimeType);
  if (isImage) {
    prepared = await attachment.imagePreparation(preparer: preparer);
    final png = prepared?.png;
    if (png != null && attachment.mimeType == "image/bmp") {
      // Sent as PNG, as before: other clients do not all draw BMP. The
      // preparation made it from its one decode.
      attachment.data = png;
      attachment.mimeType = "image/png";
    }
  }

  final extension = attachment.mimeType != null
      ? Mime.extensionFromMime(attachment.mimeType!)
      : null;
  if (isImage && prepared == null) {
    attachment.mimeType = 'application/octet-stream';
  }
  final name = attachment.name ??
      (prepared != null ? "unknown" : "Unknown") +
          (extension == null ? "" : ".$extension");
  // Empty for a file the SDK reads from disk (see [streamFromDiskAbove]).
  var bytes = attachment.data ?? Uint8List(0);

  if (prepared != null) {
    var (width, height) = (prepared.width, prepared.height);
    var mimeType = attachment.mimeType;
    final reduced = prepared.reduced;
    if (reduced != null && reduced.bytes.length < bytes.length) {
      bytes = reduced.bytes;
      (width, height) = (reduced.width, reduced.height);
      mimeType = "image/jpeg";
    }
    // A thumbnail that saves nothing (a flat screenshot sent as PNG can be
    // smaller than it) is left out, as the SDK did.
    final thumbnail = (prepared.thumbnail?.bytes.length ?? 0) < bytes.length
        ? prepared.thumbnail
        : null;
    if (thumbnail == null) {
      return processed(PreparedImageFile(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
        width: width,
        height: height,
        blurhash: prepared.blurhash,
      ));
    }
    return processed(
      matrix.MatrixImageFile(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
        width: width,
        height: height,
        blurhash: prepared.blurhash,
      ),
      thumbnailFile: matrix.MatrixImageFile(
        bytes: thumbnail.bytes,
        name: thumbnail.mimeType == "image/png"
            ? "thumbnail.png"
            : "thumbnail.jpg",
        mimeType: thumbnail.mimeType,
        width: thumbnail.width,
        height: thumbnail.height,
      ),
    );
  }

  // A video's poster, taken by the attach dialog: its size from its
  // header, without decoding it.
  matrix.MatrixImageFile? thumbnailImageFile;
  final poster = attachment.thumbnailFile;
  if (poster != null) {
    final header = readImageHeader(poster);
    thumbnailImageFile = matrix.MatrixImageFile(
        bytes: poster,
        width: header?.width,
        height: header?.height,
        mimeType: attachment.thumbnailMime,
        name: "thumbnail");
  }

  if (Mime.videoTypes.contains(attachment.mimeType)) {
    return processed(
      file(matrix.MatrixVideoFile(
        bytes: bytes,
        name: name,
        mimeType: attachment.mimeType,
        width: attachment.dimensions?.width.toInt(),
        height: attachment.dimensions?.height.toInt(),
        duration: attachment.length?.inMilliseconds,
      )),
      thumbnailFile: thumbnailImageFile,
    );
  }

  return processed(
      file(matrix.MatrixFile(
          bytes: bytes, name: name, mimeType: attachment.mimeType)),
      thumbnailFile: thumbnailImageFile);
}

/// A file attached by its path over this size is sent from disk, never
/// read whole (native). One within it is read and sent from memory, as
/// before: it goes into the account's own media (`own_media.dart`).
const int streamFromDiskAbove = 8 * 1024 * 1024;

/// Where [attachment]'s file is read from at each upload, when it is sent
/// from disk: a file attached by its path, not read yet, not a picture,
/// over [streamFromDiskAbove]. Null otherwise, and on the web.
Future<matrix.FileSendSource?> _diskSourceOf(
    PendingFileAttachment attachment) async {
  final path = attachment.path;
  if (attachment.data != null ||
      path == null ||
      Mime.imageTypes.contains(attachment.mimeType)) {
    return null;
  }
  final source = await diskFileSource(path);
  return source != null && source.length > streamFromDiskAbove ? source : null;
}
