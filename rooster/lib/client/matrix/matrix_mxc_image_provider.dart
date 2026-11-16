import 'dart:io';
import 'dart:typed_data';
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/mime.dart';
import 'package:matrix/matrix.dart';

import '../../utils/image/lod_image.dart';

class MatrixMxcImage extends LODImageProvider {
  Uri identifier;
  Client client;
  MatrixMxcImage(
    this.identifier,
    this.client, {
    super.blurhash,
    bool? doThumbnail,
    bool? doFullres,
    bool cache = true,
    super.autoLoadFullRes,
    super.thumbnailHeight,
    super.fullResHeight,
    Event? matrixEvent,
  }) : super(
          id: "$identifier-$doThumbnail-$doFullres-$thumbnailHeight-$fullResHeight",
        ) {
    if (doThumbnail == null || doThumbnail == true) {
      loadThumbnail = () => loadWithRetries<Uint8List?>(
          client,
          () => loadMatrixThumbnail(
                client,
                identifier,
                matrixEvent,
                cache: cache,
                cached: _cachedThumbnail,
              ));
    }
    if (doFullres == null || doFullres == true) {
      loadFullRes = () => loadWithRetries<Uint8List?>(
          client,
          () => loadMatrixFullRes(
                client,
                identifier,
                matrixEvent,
                cache: cache,
              ));
    }
  }

  /// Where [hasCachedThumbnail] found the thumbnail, so that loading it
  /// asks the cache nothing more.
  Uri? _cachedThumbnail;

  static String getThumbnailIdentifier(Uri uri) {
    return "matrix_thumbnail-$uri";
  }

  static String getIdentifier(Uri uri) {
    return "matrix-$uri";
  }

  /// How many times a picture is asked for before it shows as failed.
  static const maxAttempts = 3;

  /// The wait before attempt [attempt] (2, 3...) after an answer that was
  /// not the picture. Only tests change it.
  static Duration Function(int attempt) retryDelay =
      (attempt) => Duration(seconds: attempt - 1);

  /// [load], asked again up to [maxAttempts] times in all: offline
  /// (native: a socket error), once a sync gets through; after any other
  /// failure (the web's network errors among them), after [retryDelay].
  /// An answer that would come again (a 404) is not asked again. The last
  /// error is thrown: the picture then shows as failed, until it is shown
  /// again.
  static Future<T> loadWithRetries<T>(
      Client client, Future<T> Function() load) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await load();
      } catch (error, trace) {
        final again = error is! MediaDownloadException || error.retryable;
        if (attempt >= maxAttempts || !again) {
          Log.onError(error, trace, content: "Could not load a picture");
          rethrow;
        }
        if (error is SocketException) {
          await client.onSyncStatus.stream
              .firstWhere((sync) => sync.status == SyncStatus.finished);
        } else {
          await Future<void>.delayed(retryDelay(attempt + 1));
        }
      }
    }
  }

  /// [cached]: where the thumbnail is in the file cache, when that is
  /// already known.
  static Future<Uint8List?> loadMatrixThumbnail(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
    Uri? cached,
  }) async {
    var identifier = getThumbnailIdentifier(uri);

    final own = await readOwnMedia(client, matrixEvent, thumbnail: true);
    if (own != null) return own;

    final hit = await _readCached(cached) ??
        await _readCached(await fileCache?.getFile(identifier));
    if (hit != null) return hit;

    Uint8List? bytes;
    if (matrixEvent != null) {
      var data = await matrixEvent.downloadAndDecryptAttachment(
        getThumbnail: true,
        downloadCallback: (url) => downloadMedia(client, url),
      );

      String mime = matrixEvent.thumbnailMimetype;

      if (mime == "") {
        mime = Mime.lookupType("", data: data.bytes) ?? "";
      }

      if (Mime.imageTypes.contains(mime)) {
        bytes = data.bytes;
      } else {
        Log.w("Attachment thumbnail had unknown mime type: '${mime}'");
      }
    } else {
      var response = await client.getContentThumbnailFromUri(uri, 90, 90);
      bytes = response.data;
    }

    if (bytes != null && cache) {
      // A pending event's "thumbnail" is the whole file the SDK still holds
      // (Event.downloadAndDecryptAttachment): never kept as the thumbnail.
      if (matrixEvent?.status.isSending != true) {
        fileCache?.putFile(identifier, bytes);
      }
      return bytes;
    }

    return null;
  }

  static Future<Uint8List?> loadMatrixFullRes(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
  }) async {
    var identifier = getIdentifier(uri);

    final own = await readOwnMedia(client, matrixEvent);
    if (own != null) return own;

    final hit = await _readCached(await fileCache?.getFile(identifier));
    if (hit != null) return hit;

    Uint8List? bytes;
    if (matrixEvent != null) {
      var data = await matrixEvent.downloadAndDecryptAttachment(
        downloadCallback: (url) => downloadMedia(client, url),
      );

      bytes = data.bytes;
    } else {
      var response = await client.getContentFromUri(uri);
      bytes = response.data;
    }

    if (cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
  }

  /// The bytes of the cached file at [uri]; null when there is none or it
  /// cannot be read.
  static Future<Uint8List?> _readCached(Uri? uri) async {
    if (uri == null) return null;
    try {
      return await File.fromUri(uri).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// One lookup in the file cache, whose answer loading the thumbnail
  /// then uses.
  @override
  Future<bool> hasCachedThumbnail() async {
    var id = getThumbnailIdentifier(identifier);
    _cachedThumbnail = await fileCache?.getFile(id);
    return _cachedThumbnail != null;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    bool res = other is MatrixMxcImage && other.identifier == identifier;
    return res;
  }

  @override
  int get hashCode => identifier.hashCode;
}
