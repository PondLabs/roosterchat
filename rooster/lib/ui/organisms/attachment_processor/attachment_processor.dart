import 'dart:io';

import 'package:rooster/client/attachment.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:rooster/ui/molecules/file_preview.dart';
import 'package:rooster/ui/molecules/video_player/video_player_controller.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:rooster/utils/mime.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:tiamat/tiamat.dart' as tiamat;

class AttachmentProcessor extends StatefulWidget {
  const AttachmentProcessor({required this.attachment, super.key});
  final PendingFileAttachment attachment;

  @override
  State<AttachmentProcessor> createState() => _AttachmentProcessorState();
}

class _AttachmentProcessorState extends State<AttachmentProcessor> {
  String get promptAttachmentProcessingSendOriginal =>
      Intl.message("Send original (keeps metadata)",
          name: "promptAttachmentProcessingSendOriginal",
          desc: "Switch in the dialog that previews a file before it is "
              "attached: sends the file exactly as it is, with its metadata "
              "(where and when a photo was taken, the camera) left in");

  String get labelAttachmentMetadataNotRemoved => Intl.message(
      "Couldn't remove this image's metadata. To attach it as it is, turn on \"Send original\".",
      name: "labelAttachmentMetadataNotRemoved",
      desc: "Shown in the dialog that previews a file before it is attached, "
          "when the image could not be read well enough to remove its "
          "metadata; nothing is attached unless the person turns on the "
          "\"Send original (keeps metadata)\" switch");

  String get labelImageContainsLocationInfo => Intl.message(
      "Warning: This image contains location metadata",
      name: "labelImageContainsLocationInfo",
      desc:
          "Warning over an image about to be sent whose metadata says where it was taken");

  String get promptChatAddFile => Intl.message("Add File",
      name: "promptChatAddFile",
      desc: "Button at the bottom of the dialog that previews a file before "
          "it is attached to a message: attaches it");

  Map<String, IfdTag>? exifData;
  late IconData icon;
  VideoPlayerController? videoController;

  bool canProcessData = false;
  bool containsGpsData = false;
  bool sendOriginalFile = false;

  bool processing = false;

  /// The image's metadata could not be removed: it is attached only as it
  /// is, through "Send original".
  bool metadataRemovalFailed = false;

  FocusNode focusNode = FocusNode();

  @override
  void initState() {
    icon = Mime.toIcon(widget.attachment.mimeType);
    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      loadExif();
      canProcessData = true;

      if (widget.attachment.mimeType == "image/gif") {
        canProcessData = false;
      }
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      videoController = VideoPlayerController();
      canProcessData = true;
    }
    super.initState();
  }

  @override
  void dispose() {
    videoController?.pause();
    super.dispose();
  }

  void loadExif() async {
    late Map<String, IfdTag> data;
    if (widget.attachment.data != null) {
      data = await readExifFromBytes(widget.attachment.data!);
    } else {
      data = await readExifFromFile(File(widget.attachment.path!));
    }

    setState(() {
      if (data.keys.any((e) => e.toLowerCase().contains("gps"))) {
        containsGpsData = true;
      }

      exifData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaledSafeArea(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: processing ? 0.5 : 1,
            child: IgnorePointer(
              ignoring: processing,
              child: KeyboardListener(
                focusNode: focusNode,
                autofocus: true,
                onKeyEvent: (value) {
                  if (processing) return;

                  if (value.logicalKey == LogicalKeyboardKey.enter) {
                    submit();
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.attachment.name != null)
                      Row(
                        children: [
                          Icon(icon),
                          Flexible(
                            child: tiamat.Text.labelLow(
                              widget.attachment.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints.loose(const Size(500, 500)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: FilePreview(
                              mimeType: widget.attachment.mimeType,
                              path: widget.attachment.path,
                              data: widget.attachment.data,
                              videoController: videoController,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (canProcessData)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: buildFileProcessingSwitch(),
                      ),
                    if (metadataRemovalFailed && !sendOriginalFile)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.Text.error(
                            labelAttachmentMetadataNotRemoved),
                      ),
                    if (sendOriginalFile || !canProcessData)
                      buildMetadataDisplay(),
                    buildConfirmButton(),
                  ],
                ),
              ),
            ),
          ),
          if (processing) const CircularProgressIndicator()
        ],
      ),
    );
  }

  Widget buildFileProcessingSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: tiamat.Text.label(promptAttachmentProcessingSendOriginal),
        ),
        tiamat.Switch(
          state: sendOriginalFile,
          onChanged: (value) => setState(() {
            sendOriginalFile = value;
          }),
        ),
      ],
    );
  }

  Widget buildMetadataDisplay() {
    return Column(
      children: [
        if (containsGpsData) tiamat.Text.error(labelImageContainsLocationInfo)
      ],
    );
  }

  Widget buildConfirmButton() {
    return tiamat.Button(
      text: promptChatAddFile,
      onTap: submit,
    );
  }

  void submit() async {
    if (canProcessData == false || sendOriginalFile) {
      Navigator.of(context).pop(widget.attachment);
    } else if (metadataRemovalFailed) {
      // Only "Send original" attaches this file now.
      return;
    } else {
      setState(() {
        processing = true;
      });
      var file = await processFile();
      if (!mounted) return;
      if (file == null) {
        setState(() {
          processing = false;
          metadataRemovalFailed = true;
        });
        return;
      }
      Navigator.of(context).pop(file);
    }
  }

  /// The file to attach, or null when an image's metadata could not be
  /// removed.
  Future<PendingFileAttachment?> processFile() async {
    PendingFileAttachment? processedFile;

    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processImage();
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processVideo();
    }

    return processedFile;
  }

  /// Removes the image's metadata (see [removeImageMetadata]), or returns
  /// null when it cannot.
  Future<PendingFileAttachment?> processImage() async {
    final attachment = widget.attachment;
    final MetadataRemoval result;
    try {
      final data =
          attachment.data ?? await File(attachment.path!).readAsBytes();
      result = await removeImageMetadata(data);
    } catch (e) {
      // The type only: a file error's message holds the file's path.
      Log.w("Could not remove an image's metadata: ${e.runtimeType}");
      return null;
    }
    final bytes = result.bytes;
    if (bytes == null) return null;

    final mime = result.mimeType ?? attachment.mimeType!;
    var name = attachment.name;
    if (mime != attachment.mimeType) {
      // A re-encode changed the format: the name follows it.
      final extension = mime == "image/png" ? "png" : "jpg";
      final rawName = path.basenameWithoutExtension(name ?? "untitled");
      name = "$rawName.$extension";
    }

    return PendingFileAttachment(
        name: name, data: bytes, size: bytes.lengthInBytes, mimeType: mime);
  }

  Future<PendingFileAttachment> processVideo() async {
    var file = widget.attachment;

    if (videoController != null) {
      file.thumbnailFile = await videoController!.screenshot();
      if (file.thumbnailFile != null) {
        file.thumbnailMime = Mime.lookupType("", data: file.thumbnailFile);
      }
    }

    file.length = await videoController!.getLength();
    file.dimensions = await videoController!.getSize();

    return file;
  }
}
