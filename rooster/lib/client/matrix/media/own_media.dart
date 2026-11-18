/// A file sent from this device, shown again from its bytes: once its
/// upload has an address, the original and its real thumbnail go into the
/// account's [OwnMediaCache] under that address (the event's own, not its
/// transaction id's), and the timeline, the lightbox and the file's
/// download read them there before asking the homeserver.
///
/// In an encrypted room the bytes kept are the ones the user picked, not
/// the encrypted upload: what the picture providers already keep for
/// media received (`matrix-<mxc>` in the file cache), in the same place.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/cache/own_media_cache.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/debug/log.dart';

/// An account's own media, and what it holds for the sends in progress.
class _OwnMedia {
  _OwnMedia(this.cache);

  final OwnMediaCache cache;

  /// The keys written for a send not yet sent, by transaction id.
  final Map<String, List<String>> pending = {};

  /// The sends taken away ("Cancel"), by transaction id.
  final Set<String> cancelled = {};
}

final Expando<_OwnMedia> _ownMedia = Expando('own media');

/// Gives [client] its account's own media. A send taken away after its
/// upload takes its files out of it: the listener for that is returned,
/// for the account to cancel when it closes. After the account's first
/// sync, the photos whose upload an earlier closing of the app cut short
/// are settled (`interrupted_photo_uploads.dart`).
StreamSubscription<String> attachOwnMedia(
    matrix.Client client, OwnMediaCache cache) {
  final own = _ownMedia[client] = _OwnMedia(cache);
  unawaited(client.onSync.stream.first
      .then((_) => settleInterruptedPhotoUploads(client),
          // Closed before its first sync: nothing to settle now.
          onError: (Object _) {}));
  return client.onCancelSendEvent.stream.listen((txid) async {
    own.cancelled.add(txid);
    final keys = own.pending.remove(txid) ?? const [];
    try {
      await Future.wait(keys.map(cache.remove));
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not forget a cancelled file");
    }
  });
}

OwnMediaCache? ownMediaOf(matrix.Client client) => _ownMedia[client]?.cache;

/// The send under [txid] reached the room: its files stay.
void ownMediaSent(matrix.Client client, String txid) =>
    _ownMedia[client]?.pending.remove(txid);

/// Keeps the files of [pending], a file event this device is sending in
/// [room], as soon as the SDK shows it with its upload's address (still
/// pending, before the event is sent): the bytes come from what the room
/// holds for its transaction id. The thumbnail is kept only when it is the
/// one the event announces (its size), never the whole file in its place.
/// A file sent from disk (its `source` set) is not kept: its bytes are not
/// in memory, and reading them all again is what sending it from disk
/// avoids; its thumbnail still is. Never throws.
Future<void> keepOwnMedia(matrix.Room room, matrix.Event pending) async {
  final own = _ownMedia[room.client];
  if (own == null) return;
  final txid = pending.eventId;
  if (own.cancelled.contains(txid)) return;
  final file = room.sendingFilePlaceholders[txid];
  final mxc = pending.attachmentMxcUrl;
  if (file == null || mxc == null) return;
  final thumbnail = room.sendingFileThumbnails[txid];
  final thumbnailMxc = pending.hasThumbnail ? pending.thumbnailMxcUrl : null;
  final files = {
    if (file.source == null) mxc.toString(): file.bytes,
    if (thumbnail != null &&
        thumbnailMxc != null &&
        pending.thumbnailInfoMap['size'] == thumbnail.bytes.length)
      thumbnailMxc.toString(): thumbnail.bytes,
  };
  if (files.isEmpty) return;
  own.pending[txid] = files.keys.toList();
  try {
    await Future.wait([
      for (final MapEntry(:key, :value) in files.entries)
        own.cache.write(key, value),
    ]);
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not keep a sent file");
  }
}

/// The files of each account's sends whose upload runs after their event
/// was sent (a photo, `async_photo_send.dart`), by address: read from
/// memory while they go up, and written to the own media only once they
/// are up, so a send the app's closing cut short leaves nothing behind.
final Expando<Map<String, Uint8List>> _uploading =
    Expando('own media uploading');

/// Holds [files] (by address) for the timeline while they go up.
void holdUploadingMedia(matrix.Client client, Map<String, Uint8List> files) =>
    (_uploading[client] ??= {}).addAll(files);

/// Lets go of the files [keys] held by [holdUploadingMedia]: up and kept
/// ([keepUploadedMedia]), or not sent.
void releaseUploadingMedia(matrix.Client client, Iterable<String> keys) {
  final held = _uploading[client];
  if (held == null) return;
  for (final key in keys) {
    held.remove(key);
  }
}

/// Writes [files] (by address), uploaded now, to [client]'s own media.
/// Never throws.
Future<void> keepUploadedMedia(
    matrix.Client client, Map<String, Uint8List> files) async {
  final own = _ownMedia[client];
  if (own == null) return;
  try {
    await Future.wait([
      for (final MapEntry(:key, :value) in files.entries)
        own.cache.write(key, value),
    ]);
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not keep a sent file");
  }
}

/// Takes the files [keys] (by address) out of [client]'s own media: a
/// send that never went up. Never throws.
Future<void> forgetOwnMedia(matrix.Client client, Iterable<String> keys) async {
  final own = _ownMedia[client];
  if (own == null) return;
  try {
    await Future.wait(keys.map(own.cache.remove));
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not forget a file not sent");
  }
}

/// [event]'s file ([thumbnail]: its thumbnail, as the SDK would download
/// it) from the account's own media, when [event] is one of the account's
/// and the file is there, or held while it goes up. Null otherwise, and on
/// any error.
Future<Uint8List?> readOwnMedia(matrix.Client client, matrix.Event? event,
    {bool thumbnail = false}) async {
  final held = _uploading[client];
  if (held != null && held.isNotEmpty && event?.senderId == client.userID) {
    try {
      final mxc = event!.attachmentOrThumbnailMxcUrl(getThumbnail: thumbnail);
      final bytes = mxc == null ? null : held[mxc.toString()];
      if (bytes != null) return bytes;
    } catch (_) {}
  }
  return _lookUp(client, event, thumbnail, (cache, key) => cache.read(key));
}

/// Where [event]'s file of the account's own media is on disk (native), as
/// [readOwnMedia] finds it. Null on the web, and whenever [readOwnMedia]
/// would be.
Future<Uri?> ownMediaFile(matrix.Client client, matrix.Event? event) =>
    _lookUp(client, event, false, (cache, key) => cache.fileOf(key));

Future<T?> _lookUp<T>(matrix.Client client, matrix.Event? event, bool thumbnail,
    Future<T?> Function(OwnMediaCache, String) get) async {
  if (event == null || event.senderId != client.userID) return null;
  final cache = ownMediaOf(client);
  if (cache == null) return null;
  try {
    final mxc = event.attachmentOrThumbnailMxcUrl(getThumbnail: thumbnail);
    if (mxc == null) return null;
    return await get(cache, mxc.toString());
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not read a sent file");
    return null;
  }
}
