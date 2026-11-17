/// Asynchronous uploads (`POST /_matrix/media/v1/create`): an mxc reserved
/// before the file is uploaded, so the message can be sent with it at once
/// and the file uploaded to it after (`PUT /_matrix/media/v3/upload/
/// {serverName}/{mediaId}`). GIFs go this way (`matrix_gif_component.dart`),
/// and so do photos (`async_photo_send.dart`).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';

/// What one sender knows of a homeserver's reservations.
class MediaReservations {
  /// Set once the homeserver turns down reserving an mxc up front, so it
  /// isn't asked again for every file.
  bool unsupported = false;

  /// An mxc to send the message with before the file is uploaded to it,
  /// or null to upload first on a homeserver without them. [what] names
  /// the file in the log ("a gif").
  Future<Uri?> reserve(matrix.Client client, {String what = "a gif"}) async {
    if (unsupported) return null;
    try {
      return (await client.createContent()).contentUri;
    } on matrix.MatrixException catch (e) {
      if (e.error == matrix.MatrixError.M_UNRECOGNIZED ||
          e.error == matrix.MatrixError.M_NOT_FOUND) {
        unsupported = true;
      }
      Log.w("Could not reserve an mxc for $what, uploading first: $e");
      return null;
    } catch (e) {
      Log.w("Could not reserve an mxc for $what, uploading first: $e");
      return null;
    }
  }
}

/// Uploads [bytes] to [mxc], reserved with [MediaReservations.reserve]:
/// retried, since once the message is out a failed upload means a broken
/// image. Three attempts, 2 s and 4 s apart; an answer that the media is
/// there already (`M_CANNOT_OVERWRITE_MEDIA`) means an earlier attempt
/// landed after all.
Future<void> uploadToReservedMxc(matrix.Client client, Uri mxc, Uint8List bytes,
    {required String filename,
    required String mimeType,
    String what = "Gif"}) async {
  for (var attempt = 1;; attempt++) {
    try {
      await client.uploadContentToMXC(mxc.host, mxc.pathSegments.first, bytes,
          filename: filename, contentType: mimeType);
      return;
    } on matrix.MatrixException catch (e) {
      // An earlier attempt landed after all.
      if (e.errcode == "M_CANNOT_OVERWRITE_MEDIA") return;
      if (attempt >= 3) rethrow;
      Log.w("$what upload failed (attempt $attempt): $e");
    } catch (e) {
      if (attempt >= 3) rethrow;
      Log.w("$what upload failed (attempt $attempt): $e");
    }
    await Future.delayed(Duration(seconds: attempt * 2));
  }
}
