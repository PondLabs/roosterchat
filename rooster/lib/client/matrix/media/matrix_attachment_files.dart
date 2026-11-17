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
library;

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
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
  await attachment.resolve();
  if (attachment.data == null) return null;
  attachment.sending?.fileRead();

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
  final bytes = attachment.data!;

  if (prepared != null) {
    // A thumbnail that saves nothing (a flat screenshot sent as PNG can be
    // smaller than it) is left out, as the SDK did.
    final thumbnail = (prepared.thumbnail?.bytes.length ?? 0) < bytes.length
        ? prepared.thumbnail
        : null;
    if (thumbnail == null) {
      return processed(PreparedImageFile(
        bytes: bytes,
        name: name,
        mimeType: attachment.mimeType,
        width: prepared.width,
        height: prepared.height,
        blurhash: prepared.blurhash,
      ));
    }
    return processed(
      matrix.MatrixImageFile(
        bytes: bytes,
        name: name,
        mimeType: attachment.mimeType,
        width: prepared.width,
        height: prepared.height,
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
      matrix.MatrixVideoFile(
        bytes: bytes,
        name: name,
        mimeType: attachment.mimeType,
        width: attachment.dimensions?.width.toInt(),
        height: attachment.dimensions?.height.toInt(),
        duration: attachment.length?.inMilliseconds,
      ),
      thumbnailFile: thumbnailImageFile,
    );
  }

  return processed(
      matrix.MatrixFile(
          bytes: bytes, name: name, mimeType: attachment.mimeType),
      thumbnailFile: thumbnailImageFile);
}
