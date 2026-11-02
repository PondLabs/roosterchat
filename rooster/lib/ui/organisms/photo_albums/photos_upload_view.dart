import 'dart:io';

import 'package:rooster/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:rooster/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:path/path.dart' as p;

class PhotosAlbumUploadView extends StatefulWidget {
  final List<PickedPhoto> photos;
  final PhotoAlbumRoom component;
  const PhotosAlbumUploadView(this.photos, this.component, {super.key});

  @override
  State<PhotosAlbumUploadView> createState() => _PhotosAlbumUploadViewState();
}

class _PhotosAlbumUploadViewState extends State<PhotosAlbumUploadView> {
  bool sendOriginal = false;

  String get messageRoomPhotoOriginalWarning => Intl.message(
      "The original image files may contain sensitive metadata, such as the location at which they were taken",
      name: "messageRoomPhotoOriginalWarning",
      desc:
          "Warning in the dialog that uploads photos to a photo album room, while 'Upload Original' is on");

  String get labelRoomPhotoUploadOriginal => Intl.message("Upload Original",
      name: "labelRoomPhotoUploadOriginal",
      desc:
          "Next to a switch in the dialog that uploads photos to a photo album room: send the files as they are, instead of re-encoded copies without their metadata");

  String get promptRoomPhotoUploadFiles => Intl.message("Upload Files",
      name: "promptRoomPhotoUploadFiles",
      desc:
          "Button that uploads the picked photos and videos to a photo album room");

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 300,
            width: 500,
            child: MasonryGridView.extent(
                maxCrossAxisExtent: 100,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                itemCount: widget.photos.length,
                itemBuilder: (context, i) {
                  return Column(
                    children: [
                      if (widget.photos[i].filepath != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 2, 8, 2),
                          child: ClipRRect(
                            child: SizedBox(
                                width: 64,
                                height: 64,
                                child: ClipRRect(
                                    borderRadius:
                                        BorderRadiusGeometry.circular(8),
                                    child: buildFilePreview(i))),
                          ),
                        ),
                      tiamat.Text.tiny(
                        widget.photos[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                }),
          ),
          if (sendOriginal)
            SizedBox(
              width: 500,
              child: tiamat.Text.error(
                messageRoomPhotoOriginalWarning,
                maxLines: 3,
                softwrap: true,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(child: tiamat.Text.label(labelRoomPhotoUploadOriginal)),
              tiamat.Switch(
                state: sendOriginal,
                onChanged: (val) => setState(() {
                  sendOriginal = val;
                }),
              )
            ],
          ),
          tiamat.Button(
            text: promptRoomPhotoUploadFiles,
            onTap: () {
              widget.component.uploadPhotos(widget.photos,
                  sendOriginal: sendOriginal, extractMetadata: true);
              Navigator.of(context).pop();
            },
          )
        ],
      ),
    );
  }

  Widget buildFilePreview(int i) {
    var extension = p.extension(widget.photos[i].name);
    if (extension.startsWith('.')) extension = extension.substring(1);
    var mime = Mime.fromExtenstion(extension);
    print(mime);

    if (Mime.imageTypes.contains(mime)) {
      if (widget.photos[i].filepath != null) {
        return Image.file(fit: BoxFit.cover, File(widget.photos[i].filepath!));
      }

      return Icon(Icons.image);
    }

    if (Mime.videoTypes.contains(mime)) {
      return Icon(Icons.video_file);
    }

    return Icon(Icons.file_present);
  }
}
