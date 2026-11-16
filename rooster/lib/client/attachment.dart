import 'dart:io';
import 'dart:typed_data';

import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/mime.dart';
import 'package:flutter/material.dart';

import 'package:mime/mime.dart' as mime;

abstract class Attachment {
  late String? name;
}

abstract class ProcessedAttachment {}

class PendingFileAttachment {
  String? name;
  String? path;
  Uint8List? data;
  String? mimeType;
  int? size;

  Uint8List? thumbnailFile;
  String? thumbnailMime;
  Size? dimensions;
  Duration? length;

  PendingFileAttachment(
      {this.name, this.path, this.data, this.mimeType, this.size}) {
    assert(path != null || data != null);

    mimeType ??= Mime.lookupType(path ?? name ?? "", data: data);
  }

  Future<void> resolve() async {
    if (data != null) return;

    if (path != null) {
      var file = File(path!);
      if (await file.exists()) {
        data = await file.readAsBytes();
        mimeType = mime.lookupMimeType(file.path, headerBytes: data);
      }
    }
  }

  Future<ImagePreparation?>? _imagePreparation;
  Uint8List? _preparedData;

  /// Starts preparing the picture to be sent (size, thumbnail, blurhash;
  /// see `image_preparation.dart`), in the background, so Send finds it
  /// ready. Called when the file is attached; does nothing for a file that
  /// is not a picture or cannot be read.
  Future<void> startImagePreparation({ImagePreparer? preparer}) async {
    // Only a picture is read now: a video or an archive picked by path
    // stays on disk until Send, as before.
    if (!Mime.imageTypes.contains(mimeType)) return;
    await resolve();
    await imagePreparation(preparer: preparer);
  }

  /// The preparation of the file's current bytes: the one already started
  /// when they have not changed since, else a new one. Null for a file
  /// that is not a picture, and for a picture the engine cannot decode.
  Future<ImagePreparation?> imagePreparation({ImagePreparer? preparer}) {
    final data = this.data;
    if (data == null || !Mime.imageTypes.contains(mimeType)) {
      return Future.value(null);
    }
    if (_imagePreparation == null || !identical(_preparedData, data)) {
      _preparedData = data;
      _imagePreparation = (preparer ?? ImagePreparer.instance).prepare(data);
    }
    return _imagePreparation!;
  }

  ImageProvider? getAsImage() {
    if (Mime.imageTypes.contains(mimeType)) {
      if (data != null) {
        return Image.memory(data!).image;
      } else {
        return Image.file(File(path!)).image;
      }
    }

    return null;
  }
}

class FileAttachment implements Attachment {
  @override
  String? name;
  int? fileSize;
  String? mimeType;
  FileProvider file;
  FileAttachment(this.file, {required this.name, this.fileSize, this.mimeType});
}

class ImageAttachment extends FileAttachment {
  final ImageProvider image;
  final double? width;
  final double? height;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  ImageAttachment(
    this.image,
    super.file, {
    required super.name,
    required super.mimeType,
    super.fileSize,
    this.width,
    this.height,
  });
}

class VideoAttachment extends FileAttachment {
  final ImageProvider? thumbnail;
  final double? width;
  final double? height;
  final Duration? duration;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  final Uri? streamUrl;

  VideoAttachment(super.file,
      {super.name,
      required super.mimeType,
      this.thumbnail,
      this.streamUrl,
      this.width,
      this.height,
      this.duration,
      super.fileSize});
}
