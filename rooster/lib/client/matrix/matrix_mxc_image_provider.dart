import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:rooster/cache/own_media_cache.dart';
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/media_show_trace.dart';
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
    bool serverThumbnail = false,
    super.autoLoadFullRes,
    super.thumbnailHeight,
    super.fullResHeight,
    Event? matrixEvent,
  }) : super(
          id: "$identifier-$doThumbnail-$doFullres-$thumbnailHeight-$fullResHeight",
          // A chat's picture (it has an event), not an avatar.
          traceShows: matrixEvent != null,
          // A chat's picture that failed is asked again when shown again;
          // an avatar, an emoji or a sticker once per session.
          forgetsFailures: matrixEvent != null,
        ) {
    // New attempts are for a chat's pictures only: an avatar that cannot be
    // had is asked for once, as a member list shows hundreds.
    final attempts = matrixEvent != null ? maxAttempts : 1;
    if (doThumbnail == null || doThumbnail == true) {
      loadThumbnail = () => loadWithRetries<Uint8List?>(
          client,
          attempts: attempts,
          () => loadMatrixThumbnail(
                client,
                identifier,
                matrixEvent,
                cache: cache,
                cached: _cachedThumbnail,
                serverThumbnail: serverThumbnail,
              ));
    }
    if (doFullres == null || doFullres == true) {
      loadFullRes = () => loadWithRetries<Uint8List?>(
          client,
          attempts: attempts,
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

  /// The size asked of the homeserver for a picture's thumbnail when the
  /// sender gave none, scaled to fit (never cropped: the bubble shows the
  /// whole picture). The bubble is at most 500 x 200 (logical pixels,
  /// `message_attachment.dart`): a 4:3 photo is 267 x 200 there, 800 x 600
  /// at a phone's 3x; a portrait one 150 x 200, 450 x 600. Synapse makes
  /// this size ahead (`thumbnail_sizes` default), so it is not resized on
  /// demand.
  static const serverThumbnailWidth = 800;
  static const serverThumbnailHeight = 600;

  /// Above this size a still picture with no sender's thumbnail is shown
  /// from the homeserver's thumbnail.
  static const serverThumbnailAbove = 300 * 1000;

  /// The still picture types the homeserver scales into a still thumbnail
  /// that shows the same. Not GIF nor WebP: an animation's thumbnail is a
  /// still.
  static const serverThumbnailTypes = {'image/jpeg', 'image/png', 'image/bmp'};

  /// Per account, the pictures whose homeserver thumbnail was answered
  /// with a 4xx that would come again (not a 401 or 403, which a token or
  /// a permission can change), the oldest out past
  /// [_noServerThumbnailLimit]: shown again, they go straight to the whole
  /// picture. Only in memory, and forgotten on logout
  /// ([forgetNoServerThumbnails]).
  static final Expando<LinkedHashSet<String>> _noServerThumbnail =
      Expando('no server thumbnail');
  static const _noServerThumbnailLimit = 512;

  /// What [client]'s account remembers of the thumbnails its homeserver
  /// refused (a copy).
  @visibleForTesting
  static Set<String> noServerThumbnailsOf(Client client) =>
      Set.of(_noServerThumbnail[client] ?? const <String>{});

  /// Forgets the thumbnails [client]'s homeserver refused: its account
  /// logged out.
  static void forgetNoServerThumbnails(Client client) =>
      _noServerThumbnail[client] = null;

  static void _rememberNoServerThumbnail(Client client, Uri uri) {
    final refused = _noServerThumbnail[client] ??= LinkedHashSet();
    if (refused.length >= _noServerThumbnailLimit) {
      refused.remove(refused.first);
    }
    refused.add(uri.toString());
  }

  /// Whether [event]'s picture is shown from a thumbnail the homeserver
  /// scales: it has no sender's thumbnail, is not encrypted (the server
  /// cannot read it), is a still JPEG, PNG or BMP, and is larger than
  /// [serverThumbnailAbove] or of unknown size. The whole file then loads
  /// when the picture is opened, or when the thumbnail cannot be had.
  static bool asksServerThumbnail(Event event) {
    if (event.hasThumbnail || event.isAttachmentEncrypted) return false;
    if (!serverThumbnailTypes
        .contains(event.attachmentMimetype.toLowerCase())) {
      return false;
    }
    final size = event.infoMap['size'];
    return size is! int || size > serverThumbnailAbove;
  }

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

  /// The longest wait a 429 can ask for and still be asked again in the
  /// same display; past it the picture shows as failed, and the next
  /// display asks again.
  static const longestRetryAfter = Duration(seconds: 10);

  /// [load], asked up to [attempts] times in all: offline (native: a
  /// socket error), again once a sync gets through, as before at least
  /// once; after any other failure (the web's network errors among them),
  /// after [retryDelay], or the wait a 429 asked for (one over
  /// [longestRetryAfter], or one not understood, is not asked again). An answer that would come again (a 404) is not
  /// asked again ([worthAskingAgain]). The last error is thrown: the
  /// picture then shows as failed.
  static Future<T> loadWithRetries<T>(Client client, Future<T> Function() load,
      {int attempts = maxAttempts}) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await load();
      } catch (error, trace) {
        final offline = error is SocketException;
        final limit = offline ? max(attempts, 2) : attempts;
        final asked = error is MediaDownloadException ? error.retryAfter : null;
        final unknownWait =
            error is MediaDownloadException && error.retryAfterUnreadable;
        if (attempt >= limit ||
            !(offline || worthAskingAgain(error)) ||
            unknownWait ||
            (asked != null && asked > longestRetryAfter)) {
          Log.onError(error, trace, content: "Could not load a picture");
          rethrow;
        }
        if (offline) {
          await client.onSyncStatus.stream
              .firstWhere((sync) => sync.status == SyncStatus.finished);
        } else {
          final delay = retryDelay(attempt + 1);
          // A 429 that says how long: at least that.
          await Future<void>.delayed(
              asked != null && asked > delay ? asked : delay);
        }
      }
    }
  }

  /// Whether asking again after [error] can get another answer: not after
  /// the homeserver answered with a 4xx other than 408 and 429 (the
  /// download's [MediaDownloadException], or the SDK's [MatrixException]
  /// of an avatar's request).
  static bool worthAskingAgain(Object error) {
    // The SDK makes its error from the body alone (`MatrixApi`'s
    // `MatrixException.fromJson`, no response): its errcode says.
    if (error is MatrixException && error.response == null) {
      return !_sameAnswerAgain.contains(error.errcode);
    }
    final status = switch (error) {
      MediaDownloadException(:final statusCode) => statusCode,
      MatrixException(:final response?) => response.statusCode,
      _ => null,
    };
    if (status == null) return true;
    return status >= 500 || status == 408 || status == 429;
  }

  /// The errcodes of the 4xx answers that asking again would get again
  /// (not `M_LIMIT_EXCEEDED`, a 429; nor `M_UNKNOWN`, which a 500 has).
  static const _sameAnswerAgain = {
    'M_NOT_FOUND',
    'M_FORBIDDEN',
    'M_UNKNOWN_TOKEN',
    'M_MISSING_TOKEN',
    'M_UNAUTHORIZED',
    'M_UNRECOGNIZED',
    'M_TOO_LARGE',
    'M_NOT_JSON',
    'M_BAD_JSON',
    'M_INVALID_PARAM',
    'M_MISSING_PARAM',
    'M_USER_DEACTIVATED',
  };

  /// [cached]: where the thumbnail is in the file cache, when that is
  /// already known. [serverThumbnail]: the homeserver's scaled thumbnail
  /// of [matrixEvent]'s picture ([asksServerThumbnail]).
  static Future<Uint8List?> loadMatrixThumbnail(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
    Uri? cached,
    bool serverThumbnail = false,
  }) async {
    var identifier = getThumbnailIdentifier(uri);

    final trace = MediaShowTrace.current;
    final hit = await readOwnMedia(client, matrixEvent, thumbnail: true) ??
        await _readCached(cached) ??
        await _readCached(await fileCache?.getFile(identifier));
    if (hit != null) {
      trace?.cacheHit(hit.length);
      return hit;
    }
    // The homeserver has no thumbnail for it: straight to the whole
    // picture, which the cache may hold.
    if (serverThumbnail &&
        matrixEvent != null &&
        _noServerThumbnail[client]?.contains(uri.toString()) == true) {
      return loadMatrixFullRes(client, uri, matrixEvent, cache: cache);
    }
    trace?.cacheMiss();

    Uint8List? bytes;
    if (serverThumbnail && matrixEvent != null) {
      try {
        bytes = await downloadMedia(
            client,
            await uri.getThumbnailUri(client,
                width: serverThumbnailWidth,
                height: serverThumbnailHeight,
                method: ThumbnailMethod.scale));
      } on MediaDownloadException catch (error) {
        if (error.retryable) rethrow;
        // No thumbnail to be had (a 404, a type it does not scale): the
        // whole picture, kept as itself, never as the thumbnail; and the
        // thumbnail not asked again by this account, unless the refusal
        // was the token's or a permission's, which can change.
        if (error.statusCode != 401 && error.statusCode != 403) {
          _rememberNoServerThumbnail(client, uri);
        }
        return loadMatrixFullRes(client, uri, matrixEvent, cache: cache);
      }
    } else if (matrixEvent != null) {
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

    if (bytes != null) trace?.downloaded(bytes.length);

    if (bytes != null && cache) {
      // A pending event's "thumbnail" is the whole file the SDK still holds
      // (Event.downloadAndDecryptAttachment): never kept as the thumbnail.
      if (matrixEvent?.status.isSending != true) {
        final own = ownMediaCacheFor(client, matrixEvent);
        if (own == null) {
          fileCache?.putFile(identifier, bytes);
        } else if (!serverThumbnail) {
          // Under the key the own media reads it by. The homeserver's
          // scaled thumbnail has no key of its own there: not kept.
          _keepOwn(
              own,
              matrixEvent!.attachmentOrThumbnailMxcUrl(getThumbnail: true),
              bytes);
        }
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

    final trace = MediaShowTrace.current;
    final hit = await readOwnMedia(client, matrixEvent) ??
        await _readCached(await fileCache?.getFile(identifier));
    if (hit != null) {
      trace?.cacheHit(hit.length);
      return hit;
    }
    trace?.cacheMiss();

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
    trace?.downloaded(bytes.length);

    if (cache) {
      final own = ownMediaCacheFor(client, matrixEvent);
      if (own == null) {
        fileCache?.putFile(identifier, bytes);
      } else {
        _keepOwn(own, matrixEvent!.attachmentMxcUrl, bytes);
      }
      return bytes;
    }

    return null;
  }

  /// Keeps [bytes] of the account's own [mxc] in its own media again (the
  /// cache's clean took them). Never throws: the picture is shown anyway.
  static void _keepOwn(OwnMediaCache own, Uri? mxc, Uint8List bytes) {
    if (mxc == null) return;
    own.write(mxc.toString(), bytes).catchError((Object error, StackTrace s) {
      Log.onError(error, s, content: "Could not keep an own file again");
    });
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
