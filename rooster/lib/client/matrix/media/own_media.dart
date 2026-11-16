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

import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/cache/own_media_cache.dart';
import 'package:rooster/debug/log.dart';

final Expando<OwnMediaCache> _ownMedia = Expando('own media');

/// Gives [client] its account's own media.
void attachOwnMedia(matrix.Client client, OwnMediaCache cache) =>
    _ownMedia[client] = cache;

OwnMediaCache? ownMediaOf(matrix.Client client) => _ownMedia[client];

/// Keeps the files of [pending], a file event this device is sending in
/// [room], as soon as the SDK shows it with its upload's address (still
/// pending, before the event is sent): the bytes come from what the room
/// holds for its transaction id. The thumbnail is kept only when it is the
/// one the event announces (its size), never the whole file in its place.
/// Never throws.
Future<void> keepOwnMedia(matrix.Room room, matrix.Event pending) async {
  final cache = ownMediaOf(room.client);
  if (cache == null) return;
  final txid = pending.eventId;
  final file = room.sendingFilePlaceholders[txid];
  final mxc = pending.attachmentMxcUrl;
  if (file == null || mxc == null) return;
  final thumbnail = room.sendingFileThumbnails[txid];
  final thumbnailMxc = pending.hasThumbnail ? pending.thumbnailMxcUrl : null;
  try {
    await Future.wait([
      cache.write(mxc.toString(), file.bytes),
      if (thumbnail != null &&
          thumbnailMxc != null &&
          pending.thumbnailInfoMap['size'] == thumbnail.bytes.length)
        cache.write(thumbnailMxc.toString(), thumbnail.bytes),
    ]);
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not keep a sent file");
  }
}

/// [event]'s file ([thumbnail]: its thumbnail, as the SDK would download
/// it) from the account's own media, when [event] is one of the account's
/// and the file is there. Null otherwise, and on any error.
Future<Uint8List?> readOwnMedia(matrix.Client client, matrix.Event? event,
    {bool thumbnail = false}) async {
  if (event == null || event.senderId != client.userID) return null;
  final cache = ownMediaOf(client);
  if (cache == null) return null;
  try {
    final mxc = event.attachmentOrThumbnailMxcUrl(getThumbnail: thumbnail);
    if (mxc == null) return null;
    return await cache.read(mxc.toString());
  } catch (error, stack) {
    Log.onError(error, stack, content: "Could not read a sent file");
    return null;
  }
}
