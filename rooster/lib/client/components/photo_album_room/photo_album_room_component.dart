import 'dart:typed_data';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:rooster/client/components/room_component.dart';

class PickedPhoto {
  String? filepath;
  String name;
  final Future<Uint8List> Function() getBytes;

  /// Its size in bytes, read without its bytes, when known: one over the
  /// server's limit is refused before it is read.
  final Future<int> Function()? length;

  PickedPhoto(
      {this.filepath, required this.name, required this.getBytes, this.length});
}

abstract class PhotoAlbumRoom<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  bool get canUpload;

  Future<void> uploadPhotos(
    List<PickedPhoto> photos, {
    bool sendOriginal = false,
    bool extractMetadata = true,
  });

  Future<PhotoAlbumTimeline> getTimeline();
}
